// WeChat Liquid Glass · 解锁服务器(一体版:着色器就在这份代码里,不用建 KV)
// 用法:在 Cloudflare 的 Worker 里点 Edit code,把原来的内容全删掉,整份粘贴这个文件,Deploy。
// 只需要再加一个 Secret:SIGN_PRIV = keygen.html 生成的私钥。
//
// ───── 你以后可能要改的只有这一处 ─────
// FIX108 起名单以 KV(绑定 LIST)为准,加人 / 踢人请用管理 App「授权台」(/v1/admin/*),改这里不再生效。
// 这个常量只剩两个用途:① KV 里还没有任何名单时的回退(不误锁);② App「导入现有名单」
// (POST /v1/admin/seed)的种子。一行一个账号哈希(64 位)。
// FIX112：名单以 KV（绑定 LIST）为唯一权威，这里**刻意留空**。
// 这个常量只用于「KV 从未导入过任何名单」的首次引导；一旦留了真实账号，就是隐形后门——
// 踢掉 KV 里最后一个账号后 KV 变空，isAllowed 的回退分支会读到这里、把这些账号重新放行
// （正是“踢了还继续下发”的根因）。加人 / 踢人一律用授权台（/v1/admin/*）写 KV。
// 代价：KV 为空时判定为“全部拒绝”，这是期望行为——想放行先在授权台「加人」进 KV。
const ALLOWLIST = [];
// 着色器版本:换新着色器时我会直接给你新的整份文件,这行不用手改。
const VER = "1";
// 复查间隔(秒):授权用户在线时多久联网核对一次 = 踢人多久生效;离线仍按 expiresAt(7 天)。
// 只影响在线核对频率与负载,不碰签名有效期。想调快 / 调慢改这一个数即可(上限 7 天)。
const RECHECK_AFTER = 3 * 24 * 3600;   // FIX120：3 天（放宽在线核对频率——断网/重启按缓存票据照用；离线仍按 expiresAt 7 天）
// ──────────────────────────────────
// 着色器水印站点(FIX107 升级):挪到"二进制里没有参照"的 8 个 Metal-only 常数——AA 半宽、glow 下限、
// 按压光学增益、smoothstep 边界,全是"动了也看不出来"的保护/边界值,且散布多处。去掉了旧版 5 系数全挤在
// WXGContinuousDeviation(其基准值恰好也编进了 dylib,一 diff 就能定位)的毛病。pre+lit+suf 是该常数在
// 着色器里的唯一上下文;下发时按账号把 lit 换成微扰值。tools/watermark_decode.mjs 用同一组上下文反查。
const WM_SITES = [
  { pre: "aa=",             lit: ".8",  suf: "/u.viewport.z",     base: 0.8  },
  { pre: "max(width,",      lit: ".01", suf: ")",                 base: 0.01 },
  { pre: "max(g.w,",        lit: ".05", suf: ")",                 base: 0.05 },
  { pre: "max(g.z,",        lit: ".05", suf: ")",                 base: 0.05 },
  { pre: "refraction*=1.+", lit: ".35", suf: "*buttonPress",      base: 0.35 },
  { pre: "dispersion*=1.+", lit: ".20", suf: "*buttonPress",      base: 0.20 },
  { pre: "(1.+",            lit: ".04", suf: "*buttonPress)",     base: 0.04 },
  { pre: "smoothstep(-.5,", lit: ".5",  suf: ",inLens.distance)", base: 0.5  },
];

export default {
  async fetch(req, env, ctx) {
    if (req.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
    const url = new URL(req.url);

    // FIX108: 管理接口。名单与活动都走 KV，App 用 ADMIN_TOKEN 调这组 /v1/admin/*。
    // 不碰下面的签名/着色器逻辑；没配 KV 或没设 ADMIN_TOKEN 时整组退化为 503。
    if (url.pathname === "/v1/admin" || url.pathname.startsWith("/v1/admin/"))
      return stripCors(await admin(req, env, url));   // L8: 管理接口响应不带 CORS，不让浏览器跨源读取

    if (req.method === "GET") {   // 自检：私钥在不在、对应的公钥是哪把（公钥本来就是公开的）
      let pub = null;
      if (env.SIGN_PRIV) { try { pub = await publicFromPriv(env.SIGN_PRIV.trim()); } catch { pub = "invalid"; } }
      const list = await listMeta(env);
      return json({ ok: true, service: "wxg-unlock", ver: VER, signKey: env.SIGN_PRIV ? "set" : "missing", pub,
                    listSource: list.source, admin: env.ADMIN_TOKEN ? "set" : "missing" });   // L5: 不再对未鉴权请求泄露授权人数（allowCount 只在已鉴权的 /v1/admin/ping 返回）
    }
    if (req.method !== "POST") return json({ error: "POST only" }, 405);

    if (url.pathname !== "/v1/unlock") return json({ error: "not found" }, 404);

    // M3（FIX116）：边缘限流（Workers Rate Limiting 绑定，非 KV）。按来源 IP 限速，挡住洪水 / 批量探测。
    // fail-open：绑定缺失或异常一律放行，绝不因限流误伤正版。429 只是暂时失败，客户端退避重试，
    // 手里有效的缓存票不受影响（不会触发“被拒删缓存”，那只对 403 生效）。
    if (env.UNLOCK_RL) {
      const ip = req.headers.get("CF-Connecting-IP") || "";
      if (ip) {
        try {
          const { success } = await env.UNLOCK_RL.limit({ key: ip });
          if (!success) return json({ error: "rate limited" }, 429);
        } catch { /* 限流器异常 → 放行 */ }
      }
    }

    let body;
    try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
    const account = String(body.account || "").toLowerCase();
    const device  = String(body.device  || "").toLowerCase();
    const ts      = Number(body.ts || 0);

    if (!/^[0-9a-f]{64}$/.test(account)) return json({ error: "bad account" }, 400);
    if (!/^[0-9a-f]{64}$/.test(device))  return json({ error: "bad device" }, 400);   // L9: 设备也必须是 hex64 正版指纹（原来只查非空）
    if (!ts || Math.abs(Date.now() / 1000 - ts) > 300) return json({ error: "stale" }, 400);   // 5 分钟重放窗口

    if (!(await isAllowed(env, account))) { logCheckin(env, ctx, account, device, "denied"); return json({ error: "not authorized" }, 403); }
    if (!env.SIGN_PRIV) return json({ error: "SIGN_PRIV not set" }, 500);

    const expiresAt = Math.floor(Date.now() / 1000) + 7 * 24 * 3600;  // 有效期 7 天
    const shaderBytes = utf8(await watermarkedShader(account, env.SIGN_PRIV.trim()));   // FIX106: 按账号盖隐形水印
    const digestBytes = await sha256(shaderBytes);
    const digest = toHex(digestBytes);
    const msg    = [account, device, VER, expiresAt, digest].join("|");   // 绑定账号 + 设备
    let sigDer;
    try { sigDer = await signP256der(env.SIGN_PRIV.trim(), utf8(msg)); }
    catch { return json({ error: "SIGN_PRIV invalid" }, 500); }
    // FIX106: 着色器不再明文下发。用验签结果(sig)+摘要+账号/设备经 HKDF 派生 AES 密钥，
    // 把着色器封成 iv‖密文；只有拿到对这个账号 + 这台设备的真签名才解得开。patch 掉验签
    // 或自建服务器伪造票据，都只会解出坏着色器，而不是打开大门。签名与报文字段格式不变。
    const shaderKey = await hkdf32(sigDer, digestBytes, utf8("WXGLiquidGlass.shader.v1|" + account + "|" + device));
    const sealed = await aesCbcSeal(shaderKey, shaderBytes);
    logCheckin(env, ctx, account, device, "ok");
    return json({ ver: VER, expiresAt, shader: b64(sealed), digest, sig: b64(sigDer), recheckAfter: RECHECK_AFTER });
  }
};

const enc = new TextEncoder();
function utf8(s) { return enc.encode(s); }
function b64(bytes) { let s = ""; const a = new Uint8Array(bytes); for (let i = 0; i < a.length; i++) s += String.fromCharCode(a[i]); return btoa(s); }
function fromB64(s) { const bin = atob(s); const a = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i); return a; }
function toHex(bytes) { return [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2, "0")).join(""); }
async function sha256(bytes) { return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)); }
function cors(resp) {
  resp.headers.set("access-control-allow-origin", "*");
  resp.headers.set("access-control-allow-methods", "GET, POST, DELETE, OPTIONS");
  resp.headers.set("access-control-allow-headers", "content-type, authorization");
  return resp;
}
// L8: 管理接口不开放 CORS（原生 App 不走浏览器 CORS，本就不需要）。
function stripCors(resp) {
  resp.headers.delete("access-control-allow-origin");
  resp.headers.delete("access-control-allow-methods");
  resp.headers.delete("access-control-allow-headers");
  return resp;
}
function json(obj, status = 200) {
  return cors(new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } }));
}
// ECDSA P-256 / SHA-256,输出 X9.62 DER 字节(iOS SecKeyVerifySignature 要的格式)
async function signP256der(privB64, message) {
  const key = await crypto.subtle.importKey("pkcs8", fromB64(privB64), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, message));
  return rawToDer(raw);
}
// FIX106: HKDF-SHA256 → 32 字节(ikm=签名, salt=着色器摘要, info=固定串|账号|设备);
// 以及 AES-256-CBC 封装(Web Crypto 自带 PKCS7),输出 iv(16)‖密文,与插件端 CommonCrypto 对齐。
async function hkdf32(ikm, salt, info) {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, key, 256);
  return new Uint8Array(bits);
}
async function aesCbcSeal(keyBytes, plaintext) {
  const iv = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "AES-CBC" }, false, ["encrypt"]);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-CBC", iv }, key, plaintext));
  const out = new Uint8Array(iv.length + ct.length);
  out.set(iv, 0); out.set(ct, iv.length);
  return out;
}
// FIX106: 按账号给着色器盖隐形水印。水印钥匙从签名私钥派生(不随着色器下发、客户端拿不到);
// 每个站点做 4 比特(0..15)的确定性微扰:±约 0.6%,挑的都是保护/边界值,肉眼不可见。
// 8 个槽共 16^8 ≈ 43 亿种组合。解码见 tools/watermark_decode.mjs(对名单逐个重算、比中即源头)。
async function hmacSha256(keyBytes, msgBytes) {
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, msgBytes));
}
async function watermarkKey(signPrivB64) { return sha256(utf8("wxg.watermark.v1|" + signPrivB64)); }
function wmValue(base, k) { return (base + (k - 7.5) * base * 0.0008).toFixed(9); }
async function watermarkSlots(account, signPrivB64) {
  const key = await watermarkKey(signPrivB64);
  const slots = [];
  for (let i = 0; i < WM_SITES.length; i++) { const mac = await hmacSha256(key, utf8(account + "|" + i)); slots.push(mac[0] % 16); }
  return slots;
}
async function watermarkedShader(account, signPrivB64) {
  const slots = await watermarkSlots(account, signPrivB64);
  let shader = SHADER;
  for (let i = 0; i < WM_SITES.length; i++) {
    const s = WM_SITES[i];
    shader = shader.replace(s.pre + s.lit + s.suf, s.pre + wmValue(s.base, slots[i]) + s.suf);
  }
  return shader;
}
// 从私钥推出公钥（未压缩 04||X||Y 十六进制），用来核对和插件内置的是不是同一把
async function publicFromPriv(privB64) {
  const key = await crypto.subtle.importKey("pkcs8", fromB64(privB64), { name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const jwk = await crypto.subtle.exportKey("jwk", key);
  const b = s => toHex(fromB64(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)));
  return "04" + b(jwk.x) + b(jwk.y);
}
function rawToDer(raw) {
  const der = i => {
    let v = raw.slice(i, i + 32), s = 0;
    while (s < v.length - 1 && v[s] === 0) s++;
    v = v.slice(s);
    if (v[0] & 0x80) v = Uint8Array.of(0, ...v);
    return Uint8Array.of(0x02, v.length, ...v);
  };
  const r = der(0), s = der(32), body = Uint8Array.of(...r, ...s);
  return Uint8Array.of(0x30, body.length, ...body);
}

// ───── 着色器(插件的核心,不要外传;不用看也不用改)─────
// 注:着色器按账号盖隐形水印(见 WM_BASE / watermarkedShader),每个账号下发的字节与摘要都不同,这里不再记固定 sha256。
const SHADER = [
  "#include <metal_stdlib>",
  "using namespace metal;",
  "#ifndef WXG_LENS_OPTICS_H",
  "#define WXG_LENS_OPTICS_H",
  "#ifndef WXG_OPTICS_H",
  "#define WXG_OPTICS_H",
  "// The exact same geometry functions are compiled by the Metal renderer and C tests.",
  "#ifdef __METAL_VERSION__",
  "#define WXG_POW pow",
  "#define WXG_SQRT sqrt",
  "#define WXG_ABS fabs",
  "#define WXG_MIN min",
  "#define WXG_MAX max",
  "#define WXG_LOG log",
  "#define WXG_EXP exp",
  "#define WXG_ATAN2 atan2",
  "#define WXG_SIN sin",
  "#define WXG_COS cos",
  "#else",
  "#include <math.h>",
  "#define WXG_POW powf",
  "#define WXG_SQRT sqrtf",
  "#define WXG_ABS fabsf",
  "#define WXG_MIN fminf",
  "#define WXG_MAX fmaxf",
  "#define WXG_LOG logf",
  "#define WXG_EXP expf",
  "#define WXG_ATAN2 atan2f",
  "#define WXG_SIN sinf",
  "#define WXG_COS cosf",
  "#endif",
  "static inline float WXGOClamp(float x,float lo,float hi) { return WXG_MIN(hi,WXG_MAX(lo,x)); }",
  "typedef struct { float distance,nx,ny; } WXGShapeSample;",
  "/* FIX96: Core Animation's continuous capsule (cornerCurve continuous, corner",
  "   radius half the short side), measured on the tester's phone at 3x: the",
  "   dock's lens (aspect 1.26) and the dock itself (5.3) in FIX93's screenshot",
  "   give the same curve to 0.2% of the radius. About each end's centre, at the",
  "   angle phi (radians) from the straight side's normal (0 where a circle would",
  "   leave the straight side, pi/2 the very end, negative over the straight",
  "   side), its outline lies R * this outside the circular capsule (inside where",
  "   negative): it leaves the straight side some 16 degrees early, runs up to",
  "   1.2% R inside around the join, crosses at 23 degrees and is up to 0.9% R",
  "   fuller near 42 degrees (a squircle's end). A 5-term sine series over -24..90",
  "   degrees (rms 0.16% R, 0.06 pt on the lens). */",
  "static inline float WXGContinuousDeviation(float phi) {",
  "    float t=(phi+.41887902f)/1.98967535f;   // -24 .. 90 degrees",
  "    if(!(t>0.f && t<1.f))return 0.f;",
  "    float th=3.14159265f*t,s1=WXG_SIN(th),c1=WXG_COS(th);",
  "    float s2=2.f*s1*c1,c2=c1*c1-s1*s1;",
  "    float s3=s2*c1+c2*s1,c3=c2*c1-s2*s1;",
  "    float s4=s3*c1+c3*s1,c4=c3*c1-s3*s1;",
  "    float s5=s4*c1+c4*s1;",
  "    return .000865f*s1-.007454f*s2-.002456f*s3+.002256f*s4+.002806f*s5;",
  "}",
  "// FIX96: how far a capsule's continuous outline lies outside the circular",
  "// one at a point (centred coordinates): what the capsule's distance loses. A",
  "// nearly round shape (aspect below 1.25) blends back to the circle by 1.15;",
  "// the correction fades out toward each end's centre, far inside every band.",
  "static inline float WXGContinuousCorrection(float x,float y,float width,float height) {",
  "    float r=WXG_MAX(.5f,WXG_MIN(width,height)*.5f);",
  "    float longSide=WXG_MAX(width,height),shortSide=WXG_MAX(WXG_MIN(width,height),1.f);",
  "    float k=WXGOClamp((longSide/shortSide-1.15f)/.10f,0.f,1.f);",
  "    if(!(k>0.f) || !(r>1.f))return 0.f;",
  "    int horizontal=width>=height;",
  "    float along=horizontal?WXG_ABS(x)-(width*.5f-r):WXG_ABS(y)-(height*.5f-r),across=horizontal?WXG_ABS(y):WXG_ABS(x);",
  "    if(along<-.4452f*across)return 0.f;   // over the straight side, before -24 degrees (most of a long capsule)",
  "    float rho=WXG_SQRT(along*along+across*across);",
  "    if(rho<.15f*r)return 0.f;",
  "    float phi=WXG_ATAN2(along,across);",
  "    float f=WXGOClamp((rho-.15f*r)/(.25f*r),0.f,1.f);f=f*f*(3.f-2.f*f);",
  "    return k*f*r*WXGContinuousDeviation(phi)*(phi<0.f?WXG_COS(phi):1.f);",
  "}",
  "// An optical distance/normal for a capsule. The visible contour and strokes",
  "// are Core Animation's continuous corners; FIX96: the distance follows that",
  "// contour (WXGContinuousCorrection). The normal stays the circle's.",
  "static inline WXGShapeSample WXGCapsuleOpticalField(float x,float y,float width,float height) {",
  "    float r=WXG_MAX(.5f,WXG_MIN(width,height)*.5f);",
  "    float qx=WXG_ABS(x)-(width*.5f-r),qy=WXG_ABS(y)-(height*.5f-r);",
  "    float ox=WXG_MAX(0.f,qx),oy=WXG_MAX(0.f,qy),length=WXG_SQRT(ox*ox+oy*oy);",
  "    WXGShapeSample out;",
  "    out.distance=length+WXG_MIN(WXG_MAX(qx,qy),0.f)-r-WXGContinuousCorrection(x,y,width,height);",
  "    out.nx=(x<0.f?-ox:ox)/WXG_MAX(length,.0001f);",
  "    out.ny=(y<0.f?-oy:oy)/WXG_MAX(length,.0001f);",
  "    return out;",
  "}",
  "// Multiline editors grow as continuous rounded rectangles, without stretching",
  "// a capsule texture. A zero radius keeps the exact TEST9 capsule branch.",
  "static inline WXGShapeSample WXGRoundedOpticalField(float x,float y,float width,float height,float radius) {",
  "    float r=WXGOClamp(radius,.5f,WXG_MIN(width,height)*.5f);",
  "    float qx=WXG_ABS(x)-(width*.5f-r),qy=WXG_ABS(y)-(height*.5f-r);",
  "    float ox=WXG_MAX(0.f,qx),oy=WXG_MAX(0.f,qy),len=WXG_SQRT(ox*ox+oy*oy);",
  "    WXGShapeSample out;",
  "    out.distance=len+WXG_MIN(WXG_MAX(qx,qy),0.f)-r;",
  "    if(len>.0001f){out.nx=(x<0?-ox:ox)/len;out.ny=(y<0?-oy:oy)/len;}",
  "    else if(qx>qy){out.nx=x<0?-1.f:1.f;out.ny=0;}",
  "    else{out.nx=0;out.ny=y<0?-1.f:1.f;}",
  "    return out;",
  "}",
  "static inline float WXGSelectionGap(float requested,float height) {",
  "    return WXGOClamp(requested,2.f,WXG_MIN(14.f,height*.3f));",
  "}",
  "static inline float WXGSelectionWidth(float width,float gap) { return WXG_MAX(1.f,(width-2.f*gap)/4.f); }",
  "static inline float WXGSelectionCenter(float width,float gap,int index) {",
  "    if(index<0) index=0;",
  "    if(index>3) index=3;",
  "    return gap+WXGSelectionWidth(width,gap)*(index+.5f);",
  "}",
  "static inline float WXGLensHeight(float barHeight,float gap,float press,float growth,float stretch) {",
  "    (void)stretch; // Horizontal motion must not alter height or the vertical centre.",
  "    float rest=barHeight-2.f*gap;",
  "    return rest+(barHeight*growth-rest)*WXGOClamp(press,0.f,1.f);",
  "}",
  "static inline float WXGLensWidth(float slot,float barHeight,float press,float growth,float stretch) {",
  "    float expanded=WXG_MAX(barHeight*growth,slot*1.20f);",
  "    return (slot+(expanded-slot)*WXGOClamp(press,0.f,1.f))*(1.f+stretch);",
  "}",
  "enum { WXGCanvasPaddingX=40, WXGCanvasPaddingY=40 };",
  "typedef struct {",
  "    float barX,barY,barWidth,barHeight;",
  "    float lensX,lensY,lensWidth,lensHeight;",
  "    float scale,anchorX;",
  "} WXGDockGeometry;",
  "static inline WXGDockGeometry WXGDockLayout(float width,float height,float gap,float anchor,",
  "                                           float press,float growth,float stretch,float barGrowth,float wrap) {",
  "    press=WXGOClamp(press,0.f,1.f);",
  "    WXGDockGeometry g;",
  "    g.scale=1.f+(barGrowth-1.f)*press;",
  "    g.barWidth=width*g.scale; g.barHeight=height*g.scale;",
  "    g.barX=(width-g.barWidth)*.5f; g.barY=(height-g.barHeight)*.5f;",
  "    float first=WXGSelectionCenter(width,gap,0),last=WXGSelectionCenter(width,gap,3);",
  "    float t=WXGOClamp((anchor-first)/WXG_MAX(1.f,last-first),0.f,1.f);",
  "    g.anchorX=first+(last-first)*t;",
  "    g.lensWidth=WXGLensWidth(WXGSelectionWidth(width,gap),height,press,growth,stretch)*g.scale;",
  "    g.lensHeight=WXGLensHeight(height,gap,press,growth,stretch)*g.scale;",
  "    // Preserve equal resting gaps; at full press extend OUTSIDE the grown bar.",
  "    // The bar's geometry in the shader has no horizontal lens magnification.",
  "    float outside=gap*g.scale*(1.f-press)-wrap*press;",
  "    g.lensX=g.barX+outside+t*(g.barWidth-2.f*outside-g.lensWidth);",
  "    g.lensY=(height-g.lensHeight)*.5f;",
  "    return g;",
  "}",
  "static inline float WXGFitMaterialWidth(float screenWidth,float fraction,float barGrowth,float wrap) {",
  "    return WXG_MAX(1.f,WXG_MIN(screenWidth*fraction,(screenWidth-2.f*(wrap+4.f))/barGrowth));",
  "}",
  "static inline float WXGRimStrength(float nx,float ny,float fade) {",
  "    float t=WXGOClamp((WXG_ABS(nx+ny)*.70710678f-.05f)/.60f,0.f,1.f);",
  "    float highlight=t*t*(3.f-2.f*t);",
  "    return 1.f-WXGOClamp(fade,0.f,1.f)*(1.f-(.015f+.985f*highlight));",
  "}",
  "/* FIX27: the rim with its two bright diagonals faded separately. fadeTopLeft",
  "   and fadeBottomRight dim the top/left and bottom/right halves (0 = full);",
  "   `fade` still dims the two side diagonals. With both new fades at 0 this is",
  "   exactly WXGRimStrength. */",
  "static inline float WXGRimStrengthTLBR(float nx,float ny,float fade,float fadeTopLeft,float fadeBottomRight) {",
  "    float t=WXGOClamp((WXG_ABS(nx+ny)*.70710678f-.05f)/.60f,0.f,1.f);",
  "    float highlight=t*t*(3.f-2.f*t);",
  "    float side=1.f-.985f*WXGOClamp(fade,0.f,1.f);",
  "    float diagonal=1.f-WXGOClamp(nx+ny<0.f?fadeTopLeft:fadeBottomRight,0.f,1.f);",
  "    return side+(diagonal-side)*highlight;",
  "}",
  "static inline float WXGPressedBorderAlpha(float press) {",
  "    return press<.005f?0.f:WXGOClamp(press,0.f,1.f);",
  "}",
  "// Constant inset over the whole inner contour; only the tiny contact band",
  "// joins it back to the bar outside the lens. Never pinch by horizontal position.",
  "static inline float WXGInnerInset(float barHeight,float press,float reduction,float lensDistance) {",
  "    float full=barHeight*.5f*WXGOClamp(press,0.f,1.f)*WXGOClamp(reduction,0.f,.30f);",
  "    // FIX47: the outer border joins the inset inner border at about 45 degrees:",
  "    // the inset grows over as many points inward from the lens edge as it is",
  "    // deep (was a 1.25 pt step, which read as a broken bracket).",
  "    float t=WXGOClamp(-lensDistance/WXG_MAX(1.25f,full),0.f,1.f);",
  "    return full*t*t*(3.f-2.f*t);",
  "}",
  "/* FIX88: the bar seen in the lens, inset by `full`, joins the bar's edge",
  "   outside at 45 degrees and flattens toward the full inset (1 - (1 - u)^2",
  "   over 2 * full: slope 1 at the join, 0 at the full inset). `along` is how far",
  "   inside the lens the nearest point of the bar's outline lies, measured",
  "   ALONG that outline (WXGLensDepthAlongBar). WXGInnerInset measured it by the",
  "   distance from the lens outline, whose sides are steep where the bar's edge",
  "   crosses them: the join ran down along the lens' side, a vertical step that",
  "   refraction turned into a flat-bottomed cap. iOS 26 enters on a slope. */",
  "static inline float WXGInnerInsetAlong(float barHeight,float press,float reduction,float along) {",
  "    float full=barHeight*.5f*WXGOClamp(press,0.f,1.f)*WXGOClamp(reduction,0.f,.30f);",
  "    if(!(full>0.f))return 0.f;",
  "    float u=WXGOClamp(along/(2.f*full),0.f,1.f);",
  "    return full*u*(2.f-u);",
  "}",
  "/* How far a point of the bar's outline (tangent tx, ty) lies inside the",
  "   lens along that outline: the lens distance there over how fast it changes",
  "   along the outline (|t . n|, the lens normal; at least .3, so a lens edge",
  "   running alongside the bar never jumps straight to the full inset). */",
  "static inline float WXGLensDepthAlongBar(float lensDistance,float tx,float ty,float lnx,float lny) {",
  "    float rate=WXG_MAX(WXG_ABS(tx*lnx+ty*lny),.3f);",
  "    return WXG_MAX(0.f,-lensDistance)/rate;",
  "}",
  "static inline float WXGOpticalOffset(float distance,float edgeWidth,float strength) {",
  "    float t=WXGOClamp(-distance/WXG_MAX(edgeWidth,1.f),0.f,1.f);",
  "    float edge=1.f-t*t*(3.f-2.f*t);",
  "    // Exactly preserve TEST6's ordinary curve throughout its old 0..2 range.",
  "    // Above 2, extend the amplitude instead of leaving the old .40 cap in place.",
  "    strength=WXGOClamp(strength,0.f,20.f);",
  "    float amplitude=WXG_MIN(.32f*strength,.40f)+.32f*WXG_MAX(0.f,strength-2.f);",
  "    return edgeWidth*amplitude*edge*edge;",
  "}",
  "/* FIX113 I (WXG_LENS_CANCEL; user: an offset that cancels the refraction",
  "   width): the lens' refraction with `cancel` (0..1) of its rim offset taken",
  "   away. 0 is WXGOpticalOffset: the rim shows what lies edge width x",
  "   amplitude further in, so whatever is under the rim (an icon) is skipped,",
  "   more the wider / stronger it is. 1: no offset at the rim nor at the",
  "   band's inner edge, the push in between (edge^2 x t: compressed at the rim",
  "   up to 2.55x, stretched past the middle of the band), capped at 1.55 so the",
  "   mapping never folds back (the slope stays >= 0.2): what is under the band",
  "   stays in the band, however wide it is, at most 0.29 band widths from where",
  "   it is. Between: a straight mix. */",
  "static inline float WXGLensRefractionOffset(float distance,float edgeWidth,float strength,float cancel) {",
  "    float full=WXGOpticalOffset(distance,edgeWidth,strength);",
  "    cancel=WXGOClamp(cancel,0.f,1.f);",
  "    if(!(cancel>0.f))return full;",
  "    float t=WXGOClamp(-distance/WXG_MAX(edgeWidth,1.f),0.f,1.f);",
  "    float edge=1.f-t*t*(3.f-2.f*t);",
  "    strength=WXGOClamp(strength,0.f,20.f);",
  "    float amplitude=WXG_MIN(.32f*strength,.40f)+.32f*WXG_MAX(0.f,strength-2.f);",
  "    float bump=edgeWidth*WXG_MIN(amplitude,1.55f)*edge*edge*t;",
  "    return full*(1.f-cancel)+bump*cancel;",
  "}",
  "static inline float WXGMaterialOpacity(float alpha,float clearMaterial,float edge,float fadeAtEdge) {",
  "    float opacity=WXGOClamp(alpha*(1.22f-.22f*WXGOClamp(clearMaterial,0.f,1.f)),0.f,1.f);",
  "    return opacity*(1.f-.82f*edge*edge*WXGOClamp(fadeAtEdge,0.f,1.f));",
  "}",
  "// Shrink the clear rim toward the outside as coverage grows. Coverage zero is",
  "// exactly TEST8; one removes the sharp component everywhere, including d=0.",
  "static inline float WXGBlurSharpWeight(float distance,float edgeWidth,float coverage) {",
  "    coverage=WXGOClamp(coverage,0.f,1.f);",
  "    if(coverage>=1.f) return 0.f;",
  "    float width=WXG_MAX(.001f,edgeWidth*(1.f-coverage));",
  "    float t=WXGOClamp(-distance/width,0.f,1.f);",
  "    float edge=1.f-t*t*(3.f-2.f*t);",
  "    return .88f*edge*edge*(1.f-coverage);",
  "}",
  "static inline float WXGLensRingBlurWeight(float distance,float edgeWidth,float coverage) {",
  "    coverage=WXGOClamp(coverage,0.f,1.f);",
  "    return coverage*(1.f-WXGBlurSharpWeight(distance,edgeWidth,coverage));",
  "}",
  "static inline float WXGCaptureScale(float screenScale) { return WXGOClamp(screenScale,1.f,3.f); }",
  "typedef struct {",
  "    int count;",
  "    float center;",
  "    float offsets[54];",
  "    float weights[54];",
  "} WXGGaussianKernel;",
  "#ifndef __METAL_VERSION__",
  "// Pair neighbouring Gaussian taps using bilinear filtering. This preserves a",
  "// dense kernel; widely spaced fixed taps would recreate ghosting at large blur.",
  "static inline WXGGaussianKernel WXGMakeGaussian(float sigma) {",
  "    WXGGaussianKernel k={0}; k.center=1;",
  "    if(sigma<.05f) return k;",
  "    sigma=WXGOClamp(sigma,.05f,36.f);",
  "    int radius=(int)ceilf(3.f*sigma); float total=1;",
  "    for(int i=1;i<=radius;i+=2) {",
  "        float a=expf(-.5f*(float)(i*i)/(sigma*sigma));",
  "        float b=i+1<=radius?expf(-.5f*(float)((i+1)*(i+1))/(sigma*sigma)):0;",
  "        float weight=a+b;",
  "        if(weight<1e-12f) continue;",
  "        k.offsets[k.count]=i+b/weight; k.weights[k.count]=weight; ++k.count;",
  "        total+=2*weight;",
  "    }",
  "    k.center=1/total;",
  "    for(int i=0;i<k.count;i++) k.weights[i]/=total;",
  "    return k;",
  "}",
  "#endif",
  "#endif",
  "",
  "typedef struct {float refraction,dispersion,edgeWidth;} WXGOpticalValues;",
  "// Resting selection belongs to the ordinary bar. Its pressed optical profile",
  "// fades in using the original demo press spring, independently of motion strain.",
  "static inline WXGOpticalValues WXGPressedOptics(WXGOpticalValues body,WXGOpticalValues lens,float press) {",
  "    float p=WXGOClamp(press,0,1);",
  "    return (WXGOpticalValues){body.refraction+(lens.refraction-body.refraction)*p,",
  "        body.dispersion+(lens.dispersion-body.dispersion)*p,",
  "        body.edgeWidth+(lens.edgeWidth-body.edgeWidth)*p};",
  "}",
  "// Selection is a resting-state cue, not another layer inside the raised lens.",
  "// Withdraw it as the lens rises, keep it absent while it is lifted (dragging),",
  "// bring it back as it settles. Smooth endpoints avoid a flash.",
  "// FIX98 (user: the pill went clear at once and coloured at once): over press",
  "// 0.05..0.45 (was 0..0.12, a frame or two of the press spring), so the",
  "// touch-down bump (0.10) keeps it (0.96) and the colour follows the lift and",
  "// the release. A tap's scripted lens has its own colour track (WXGDockScript.h).",
  "static inline float WXGRestingSelectionWeight(float press) {",
  "    float p=WXGOClamp((press-.05f)/.40f,0.f,1.f);",
  "    return 1.f-p*p*(3.f-2.f*p);",
  "}",
  "/* FIX21: iOS 26-style lens rim. The refraction band keeps the full width",
  "   where the lens normal is horizontal (its rounded ends) and narrows to",
  "   `topRatio` of it where the normal is vertical (the parts that stand above",
  "   and below the bar). pow(|nx|, sharpness): leaving an end the band narrows",
  "   quickly, then approaches the top/bottom width slowly. topRatio 1 returns",
  "   exactly `side`, i.e. the previous isotropic lens. */",
  "/* FIX47: the FIX21 rule (widest at the lens ends, topRatio above/below), but a",
  "   lens end that has passed the bar's end narrows quickly to the top/bottom",
  "   width (barDistance < 0 inside the bar, 4 pt blend): at the dock's ends only",
  "   the inset bar and a narrow rim remain. Inside the bar it equals the FIX21 rule. */",
  "static inline float WXGLensEdgeWidthAtBar(float nx,float ny,float side,float topRatio,float sharpness,float barDistance) {",
  "    float r=WXGOClamp(topRatio,.05f,1.f);",
  "    if(r>=1.f)return side;",
  "    float len=WXG_SQRT(nx*nx+ny*ny);",
  "    float h=len>1e-4f?WXG_ABS(nx)/len:1.f;",
  "    float t=WXGOClamp((barDistance+4.f)/8.f,0.f,1.f);t=t*t*(3.f-2.f*t);",
  "    return side*(r+(1.f-r)*WXG_POW(h,WXGOClamp(sharpness,.5f,8.f))*(1.f-t));",
  "}",
  "static inline float WXGLensEdgeWidth(float nx,float ny,float side,float topRatio,float sharpness) {",
  "    float r=WXGOClamp(topRatio,.05f,1.f);",
  "    if(r>=1.f)return side;",
  "    float len=WXG_SQRT(nx*nx+ny*ny);",
  "    float h=len>1e-4f?WXG_ABS(nx)/len:1.f;",
  "    return side*(r+(1.f-r)*WXG_POW(h,WXGOClamp(sharpness,.5f,8.f)));",
  "}",
  "",
  "/* ---- FIX57: the dock's ends ------------------------------------------------",
  "   With FIX47's band a lens resting on the first / last tab still pulled the",
  "   bar's end cap into its rim: points just inside the bar's end kept the wide",
  "   end band, so the inner bar stuck to the lens edge. Now, as a lens end",
  "   reaches the bar's end, the band that bends the bar seen through the lens",
  "   (and the page behind it) relaxes toward the top / bottom width: from",
  "   WXG_END_START pt before the bar's end to WXG_END_DONE pt past it, smoothly.",
  "   Everywhere else it is FIX47's band; icons and titles always keep FIX47's. */",
  "#define WXG_END_START 10.f",
  "#define WXG_END_DONE 2.f",
  "/* How far one end (side < 0 left, else right) has relaxed, 0..1, from the",
  "   bar's and the lens's horizontal extent (same space). */",
  "static inline float WXGLensEndReach(float barX0,float barX1,float lensX0,float lensX1,int side) {",
  "    float over=side<0?barX0-lensX0:lensX1-barX1;",
  "    float t=WXGOClamp((over+WXG_END_START)/(WXG_END_START+WXG_END_DONE),0.f,1.f);",
  "    return t*t*(3.f-2.f*t);",
  "}",
  "/* `width` with each half of the lens pulled toward the top / bottom width by",
  "   its end's reach (0..1). Both 0 returns `width` exactly. */",
  "static inline float WXGLensEndRelax(float width,float nx,float side,float topRatio,float reachLeft,float reachRight) {",
  "    float c=WXGOClamp(nx<0.f?reachLeft:reachRight,0.f,1.f);",
  "    if(c<=0.f)return width;",
  "    float top=side*WXGOClamp(topRatio,.05f,1.f);",
  "    return top+(width-top)*(1.f-c);",
  "}",
  "/* ---- FIX94: the bar seen through the lens follows the lens' rim ------------",
  "   With the refraction band narrowed above and below (lensTopEdgeRatio < 1),",
  "   the lens' flat middle showed the bar as it is: the lens stands above and",
  "   below the bar (plus the inset), so a dark slot appeared at the top and the",
  "   bottom, thickest in the middle and gone at the rounded corners, the",
  "   opposite of the band. Now the bar is magnified vertically about its centre,",
  "   column by column, so that its (inset) top / bottom edge comes to `margin`",
  "   times the band's width (at the rim above that column) from the lens' rim:",
  "   the dark border is then thinnest at the top / bottom and grows toward the",
  "   corners, the bar inside the lens nearly an ellipse. Where the rim lies",
  "   inside the bar (the lens' ends, the joins) the scale is 1 (smoothly), so",
  "   the 45-degree join stays. A bar end cap inside the lens takes the scale of",
  "   its straight part's end (x clamped), so it detaches as before (vertically",
  "   stretched by that scale), but never more than its own column allows: with",
  "   the lens' end over the cap (dragging onto / off an end tab) the cap's edge",
  "   stays margin x band inside the rim there too. Everything in the bar's",
  "   screen space (scaled by the press); the lens a capsule centred lx, ly.",
  "   margin <= 0: off (returns 1). */",
  "/* The scale that puts the bar's top edge at column x (the outline there hb",
  "   above the bar's centre by, its tangent tx, ty) margin x band inside the",
  "   lens' rim; 0 outside the lens. */",
  "static inline float WXGLensBarColumnZoom(float x,float hb,float halfH,float tx,float ty,float by,float lx,float ly,float lw,float lh,",
  "                                         float insetHeight,float press,float pinch,float side,float ratio,float sharpness,float margin) {",
  "    float r=WXG_MIN(lw,lh)*.5f,a=WXG_MAX(0.f,lw*.5f-r),ah=WXG_MAX(0.f,lh*.5f-r);",
  "    float dx=WXG_ABS(x-lx)-a;",
  "    if(dx>=r)return 0.f;",
  "    float lhalf=ah+r,nx=0.f,ny=1.f;",
  "    if(dx>0.f){float c=WXG_SQRT(WXG_MAX(0.f,r*r-dx*dx));lhalf=ah+c;nx=dx/r;ny=c/r;}",
  "    float e=margin*WXGLensEdgeWidth(nx,ny,side,ratio,sharpness);",
  "    // The inset (FIX88, 45 degrees from the join) at the bar's top edge here,",
  "    // its vertical part (the outline's normal is hb / halfH upward).",
  "    WXGShapeSample l=WXGCapsuleOpticalField(x-lx,by-hb-ly,lw,lh);",
  "    float inset=WXGInnerInsetAlong(insetHeight,press,pinch,WXGLensDepthAlongBar(l.distance,tx,ty,l.nx,l.ny));",
  "    return (lhalf-(by-ly>0.f?by-ly:ly-by)-e)/WXG_MAX(hb-inset*hb/WXG_MAX(halfH,.5f),1.f);",
  "}",
  "static inline float WXGLensBarZoom(float x,float bx,float by,float bw,float bh,float lx,float ly,float lw,float lh,",
  "                                   float insetHeight,float press,float pinch,float side,float ratio,float sharpness,float margin) {",
  "    if(!(margin>0.f) || !(bw>1.f) || !(bh>1.f) || !(lw>1.f) || !(lh>1.f))return 1.f;",
  "    float halfH=bh*.5f,straight=WXG_MAX(0.f,bw*.5f-halfH),over=WXG_ABS(x-bx)-straight;",
  "    float xc=bx+WXGOClamp(x-bx,-straight,straight);",
  "    float z=WXGLensBarColumnZoom(xc,halfH,halfH,1.f,0.f,by,lx,ly,lw,lh,insetHeight,press,pinch,side,ratio,sharpness,margin);",
  "    if(over>0.f) {   // over an end cap: also what this column itself allows",
  "        float c=WXG_MIN(over,halfH),hb=WXG_SQRT(WXG_MAX(0.f,halfH*halfH-c*c)),s=x<bx?-1.f:1.f;",
  "        z=WXG_MIN(z,WXGLensBarColumnZoom(x,hb,halfH,hb/halfH,s*c/halfH,by,lx,ly,lw,lh,insetHeight,press,pinch,side,ratio,sharpness,margin));",
  "    }",
  "    if(!(z>0.f))return 1.f;",
  "    float k=(z-1.f)/.04f;   // a smooth max(1, z)",
  "    return k>20.f?z:1.f+.04f*WXG_LOG(1.f+WXG_EXP(k));",
  "}",
  "/* ---- FIX113 M (WXG_LENS_FLAT): the bar in the lens, small and flat ---------",
  "   User: take away the slanted line that joins the inner outline to the outer",
  "   one; cut it off from the magnified outside, small and flat inside. The bar",
  "   seen through the dock's lens is then not bent by the lens' refraction and",
  "   is inset by its full amount everywhere (no FIX47 / FIX88 45-degree join to",
  "   the bar outside): where it meets the lens' rim it just ends there, a step.",
  "   The plugin asks for it with |extra.w| = WXG_LENS_FLAT (the sign is still",
  "   FIX113 H's direction). Older shaders read +WXG_LENS_FLAT as FIX94's",
  "   margin, which that far from the rim leaves the bar unbent (only the join's",
  "   slope stays), and -WXG_LENS_FLAT as outward. */",
  "#define WXG_LENS_FLAT 1000.f",
  "static inline int WXGLensFlatCode(float w) {return WXG_ABS(w)>=WXG_LENS_FLAT*.5f;}",
  "static inline float WXGLensFullInset(float barHeight,float press,float reduction) {",
  "    return WXGInnerInsetAlong(barHeight,press,reduction,1e6f);",
  "}",
  "#endif",
  "",
  "",
  "struct WXGUniforms {",
  "    float4 viewport;   // width/height in points, drawable scale, time",
  "    float4 bar;",
  "    float4 lens;",
  "    float4 material;   // press, refraction, dispersion, Gaussian sigma in points",
  "    float4 appearance; // dark, clear, native distance field available, surface (0 body / 1 lens)",
  "    float4 optics;     // content zoom, body border width, body pinch, edge width",
  "    float4 lensOptics; // independent pressed refraction, RGB dispersion, edge width, lens blur coverage",
  "    float4 selectionColor;",
  "    float4 borderColor;",
  "    float4 motion;     // whole-bar scale, fade material at edge, blur coverage, icon anchor x",
  "    float4 rim;        // directional fade, dark gain, lens stroke width, optional maximum corner radius",
  "    float4 tintColor;  // independent material veil, including opacity",
  "    float4 sync;       // FIX18 x: 0 readback optics, 1 hybrid edge band, 2 render-server body; FIX21 y: lens top/bottom width ratio, z: narrowing sharpness",
  "    float4 style;      // FIX27 x: material veil fade width in pt (0 = refraction width), y: rim top-left fade, z: rim bottom-right fade; FIX113 I w: WXG_LENS_CANCEL (the lens' rim offset cancelled, 0..1)",
  "    float4 glow;       // FIX86 x: iOS 27-like rim on (optics.y is then its width; FIX87: x = 1 + the highlight's angle in radians), y: end level, z: sharpness, w: inward curve",
  "    float4 extra;      // FIX88 y: lens dispersion range (pt), z: its top / bottom ratio; FIX89 x: the second highlight's width; FIX94 w: the bar-follows-the-rim margin (0 off); FIX113 H w < 0: WXG_LENS_OUTWARD; FIX113 M |w| = WXG_LENS_FLAT: the bar in the lens flat",
  "    float4 glow2;      // FIX89: the iOS 27-like rim's second highlight, as glow",
  "    float4 glowColor2; // FIX89: its colour, alpha = opacity (the first's is borderColor)",
  "    float4 extra2;     // FIX97 x: the colour split of the bar seen through the lens (pt), y: its share of the lens' own split, z: the page behind (0 black .. 1 white); FIX98 w: 1 + the selection colour's weight (0: by the press)",
  "};",
  "// FIX113 H (WXG_LENS_OUTWARD): the lens' refraction direction. With extra.w",
  "// below zero the rim gathers what lies just outside the lens (iOS 26: a",
  "// neighbouring icon comes into the rim, compressed) instead of what lies",
  "// further in (an icon under the rim was skipped: the band showed what is up",
  "// to edge width x amplitude further in). Older plugins send 0 (inward, as",
  "// before); older shaders read extra.w only above zero (FIX94, off).",
  "float wxgLensDirection(constant WXGUniforms &u) {return u.extra.w<0.?-1.:1.;}",
  "// FIX86: the bar outline drawn by the shader (inside the dock's lens) as the",
  "// iOS 27-like rim of the CA rim view (WXGRimGlow.h): full at the outline,",
  "// fading inward over `width` (depth = points inside the outline), and along",
  "// the outline 1 where it faces the highlight's direction (FIX87: at an",
  "// angle, 0 = up / down), the end level where it faces across it.",
  "// FIX89: two of these, each its own colour, drawn one over the other.",
  "float wxgGlowStroke(float coverage,float depth,float width,float nx,float ny,float4 g) {",
  "    float inward=pow(saturate(1.-max(depth,0.)/max(width,.01)),max(g.w,.05));",
  "    float a=g.x-1.,k=max(g.z,.05);",
  "    float facing=min(abs(nx*sin(a)+ny*cos(a)),1.);",
  "    float along=saturate(g.y)+(1.-saturate(g.y))*pow(facing,k);",
  "    return coverage*inward*along;",
  "}",
  "// FIX27: the distance from the contour over which the material veil weakens.",
  "float wxgVeilWidth(float refractionWidth,constant WXGUniforms &u) { return u.style.x>0.?u.style.x:refractionWidth; }",
  "struct WXGOut { float4 position [[position]]; float2 uv; };",
  "vertex WXGOut wxgVertex(uint vid [[vertex_id]]) {",
  "    const float2 vertices[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};",
  "    WXGOut out; out.position=float4(vertices[vid],0,1);",
  "    out.uv=float2(vertices[vid].x*.5+.5,.5-vertices[vid].y*.5); return out;",
  "}",
  "constexpr sampler wxgSampler(coord::normalized,address::clamp_to_edge,filter::linear);",
  "// Full-resolution separable Gaussian with paired adjacent taps, no mipmap blur.",
  "kernel void wxgBlur(texture2d<float,access::sample> input [[texture(0)]],",
  "                    texture2d<float,access::write> output [[texture(1)]],",
  "                    constant float4 &params [[buffer(0)]],",
  "                    constant WXGGaussianKernel &weights [[buffer(1)]],uint2 pos [[thread_position_in_grid]]) {",
  "    if(pos.x>=output.get_width() || pos.y>=output.get_height()) return;",
  "    float2 uv=(float2(pos)+.5)/float2(output.get_width(),output.get_height());",
  "    float4 sum=input.sample(wxgSampler,uv)*weights.center;",
  "    for(int i=0;i<weights.count;i++) {",
  "        float2 offset=params.xy*weights.offsets[i];",
  "        sum+=(input.sample(wxgSampler,uv+offset)+input.sample(wxgSampler,uv-offset))*weights.weights[i];",
  "    }",
  "    output.write(sum,pos);",
  "}",
  "WXGShapeSample wxgShape(float2 p,float4 rect,float radius) {",
  "    float2 q=p-(rect.xy+rect.zw*.5);",
  "    return radius>0.?WXGRoundedOpticalField(q.x,q.y,rect.z,rect.w,radius):WXGCapsuleOpticalField(q.x,q.y,rect.z,rect.w);",
  "}",
  "float wxgMask(float d,float aa) { return 1.-smoothstep(-aa,aa,d); }",
  "// FIX88: the bar's inset in the lens at a point of the bar's (base) space:",
  "// from the nearest point of the bar's outline, how far inside the lens it",
  "// lies along that outline (WXGLensDepthAlongBar), through WXGInnerInsetAlong.",
  "// The lens pass evaluates it where the bar is sampled (after refraction), so",
  "// the slope itself is refracted.",
  "float wxgLensInset(float2 basePt,float press,constant WXGUniforms &u) {",
  "    WXGShapeSample b=wxgShape(basePt,u.bar,u.rim.w);",
  "    float2 c=u.bar.xy+u.bar.zw*.5;",
  "    float2 q=basePt-float2(b.nx,b.ny)*b.distance;",
  "    float2 qs=c+(q-c)*u.motion.x;",
  "    WXGShapeSample l=wxgShape(qs,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));",
  "    float along=WXGLensDepthAlongBar(l.distance,-b.ny,b.nx,l.nx,l.ny);",
  "    return WXGInnerInsetAlong(u.bar.w*u.motion.x,press,u.optics.z,along);",
  "}",
  "float wxgEdge(float d,float width) { return 1.-smoothstep(0.,width,max(-d,0.)); }",
  "float3 wxgRGB(texture2d<float> tex,float2 p,float2 chroma,constant WXGUniforms &u) {",
  "    return float3(tex.sample(wxgSampler,(p+chroma)/u.viewport.xy).r,",
  "                  tex.sample(wxgSampler,p/u.viewport.xy).g,",
  "                  tex.sample(wxgSampler,(p-chroma)/u.viewport.xy).b);",
  "}",
  "float2 wxgBasePoint(float2 p,constant WXGUniforms &u) {",
  "    float2 c=u.bar.xy+u.bar.zw*.5;",
  "    return c+(p-c)/u.motion.x;",
  "}",
  "float3 wxgBody(texture2d<float> raw,texture2d<float> soft,texture2d<float> lensSoft,float blurBlend,float blurCoverage,float2 geometry,",
  "               float inset,float2 ray,float2 extraChroma,WXGOpticalValues optical,constant WXGUniforms &u) {",
  "    WXGShapeSample shape=wxgShape(geometry,u.bar,u.rim.w); float2 n=float2(shape.nx,shape.ny);",
  "    shape.distance+=inset;",
  "    float edge=wxgEdge(shape.distance,optical.edgeWidth);",
  "    float offset=WXGOpticalOffset(shape.distance,optical.edgeWidth,optical.refraction)*u.motion.x;",
  "    float2 source=ray-n*offset;",
  "    float2 chroma=n*(optical.dispersion*edge*.85)+extraChroma;",
  "    float3 sharp=wxgRGB(raw,source,chroma,u),blurred=wxgRGB(soft,source,chroma,u);",
  "    if(blurBlend>0.)blurred=mix(blurred,wxgRGB(lensSoft,source,chroma,u),blurBlend);",
  "    float3 face=mix(blurred,sharp,WXGBlurSharpWeight(shape.distance,optical.edgeWidth,blurCoverage));",
  "    float luma=dot(face,float3(.2126,.7152,.0722)); face=mix(float3(luma),face,1.05);",
  "    // Default is the original TEST6 edge attenuation; disabling it keeps the",
  "    // same user-selected opacity throughout the material.",
  "    float opacity=WXGMaterialOpacity(u.tintColor.a,u.appearance.y,wxgEdge(shape.distance,wxgVeilWidth(optical.edgeWidth,u)),u.motion.y);",
  "    return saturate(mix(face,u.tintColor.rgb,opacity));",
  "}",
  "/* FIX114 Z (user: the dock's Telegram icons and the group bar's text in a",
  "   colour of their own (green) got fringes of other colours at the lens edge,",
  "   read as \"the old blue\"): splitting a coloured glyph into its red, green and",
  "   blue copies leaves, where only one copy covers, that one channel of the",
  "   glyph's colour over the others of what is under it (green: cyan on one",
  "   side, yellow on the other). A coloured glyph's fringes now keep its own",
  "   colour: the copy on the red side lighter, on the blue side deeper; grey,",
  "   black and white artwork (the resting icons, dark text) keeps the classic",
  "   split. Samples are premultiplied. */",
  "float wxgIconColourWeight(float4 r,float4 g,float4 b,thread float3 &colour) {",
  "    float4 c=g.a>=max(r.a,b.a)?g:(r.a>=b.a?r:b);",
  "    if(c.a<.004){colour=float3(0.);return 0.;}",
  "    colour=saturate(c.rgb/c.a);",
  "    float spread=max(colour.r,max(colour.g,colour.b))-min(colour.r,min(colour.g,colour.b));",
  "    return smoothstep(.12,.35,spread);",
  "}",
  "float3 wxgIcons(texture2d<float> icons,float2 source,float2 chroma,float3 face,",
  "                 constant WXGUniforms &u) {",
  "    float4 r=icons.sample(wxgSampler,(source+chroma)/u.viewport.xy);",
  "    float4 g=icons.sample(wxgSampler,source/u.viewport.xy);",
  "    float4 b=icons.sample(wxgSampler,(source-chroma)/u.viewport.xy);",
  "    // Images contain premultiplied alpha; each refracted colour uses its own alpha.",
  "    float3 split=float3(r.r+face.r*(1.-r.a),g.g+face.g*(1.-g.a),b.b+face.b*(1.-b.a));",
  "    float3 colour=float3(0.);float k=wxgIconColourWeight(r,g,b,colour);",
  "    if(k<=0.)return split;",
  "    float3 own=mix(face,mix(colour,float3(1.),.35),r.a*.6);",
  "    own=mix(own,colour*.82,b.a*.6);",
  "    own=mix(own,colour,g.a);",
  "    return mix(split,own,k);",
  "}",
  "// FIX18 render-server modes. This layer is composited by Core Animation over",
  "// a CABackdropLayer that the render server captures and blurs at DISPLAY time,",
  "// so that part never lags. Output is premultiplied. With tint opacity k and",
  "// hybrid edge-band weight w, compositing over the live backdrop B gives",
  "//   w*F + (1-w)*(k*tint + (1-k)*B)",
  "// i.e. the readback face F only inside the refraction band, and the same",
  "// tint veil as the readback path everywhere else.",
  "float4 wxgSyncBase(float3 face,float w,float k,constant WXGUniforms &u) {",
  "    return float4(face*w+(1.-w)*k*u.tintColor.rgb,1.-(1.-w)*(1.-k));",
  "}",
  "float4 wxgOver(float4 src,float4 dst) { return src+dst*(1.-src.a); }",
  "float4 wxgIconsOver(texture2d<float> icons,float2 source,float2 chroma,float4 acc,constant WXGUniforms &u) {",
  "    float4 r=icons.sample(wxgSampler,(source+chroma)/u.viewport.xy);",
  "    float4 g=icons.sample(wxgSampler,source/u.viewport.xy);",
  "    float4 b=icons.sample(wxgSampler,(source-chroma)/u.viewport.xy);",
  "    float4 split=float4(r.r+acc.r*(1.-r.a),g.g+acc.g*(1.-g.a),b.b+acc.b*(1.-b.a),g.a+acc.a*(1.-g.a));",
  "    float3 colour=float3(0.);float k=wxgIconColourWeight(r,g,b,colour);   // FIX114 Z",
  "    if(k<=0.)return split;",
  "    float lit=r.a*.6,deep=b.a*.6;",
  "    float4 own=wxgOver(float4(mix(colour,float3(1.),.35)*lit,lit),acc);",
  "    own=wxgOver(float4(colour*.82*deep,deep),own);",
  "    own=wxgOver(float4(colour*g.a,g.a),own);",
  "    return mix(split,own,k);",
  "}",
  "// FIX97: the bar seen through the render-server lens at screen point p: its",
  "// signed distance on screen (inset contour; < 0 inside), the bent sample and",
  "// inset (FIX44 / FIX46 / FIX57 / FIX88 / FIX94, as the lens pass had them",
  "// inline), so it can be asked again at a channel's shifted point.",
  "struct WXGLensBar { float dd; WXGShapeSample s; float insetBent; float rim; float2 n; };",
  "WXGLensBar wxgLensBar(float2 p,float press,WXGOpticalValues optical,constant WXGUniforms &u) {",
  "    WXGShapeSample lens=wxgShape(p,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));",
  "    float2 n=float2(lens.nx,lens.ny),center=u.lens.xy+u.lens.zw*.5;",
  "    float lensWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,optical.edgeWidth,u.sync.y,u.sync.z,wxgShape(wxgBasePoint(p,u),u.bar,u.rim.w).distance*u.motion.x);",
  "    float2 barMid=u.bar.xy+u.bar.zw*.5;",
  "    float barHalf=u.bar.z*u.motion.x*.5;",
  "    float endLeft=WXGLensEndReach(barMid.x-barHalf,barMid.x+barHalf,u.lens.x,u.lens.x+u.lens.z,-1);",
  "    float endRight=WXGLensEndReach(barMid.x-barHalf,barMid.x+barHalf,u.lens.x,u.lens.x+u.lens.z,1);",
  "    float barBand=WXGLensEndRelax(lensWidth,lens.nx,optical.edgeWidth,u.sync.y,endLeft,endRight);",
  "    // FIX113 M (WXG_LENS_FLAT): flat, the bar as it lies (not bent), inset in full.",
  "    bool flat=WXGLensFlatCode(u.extra.w)!=0;",
  "    float2 bend=flat?wxgBasePoint(p,u):wxgBasePoint(p-n*(WXGLensRefractionOffset(lens.distance,barBand,optical.refraction,u.style.w)*press*wxgLensDirection(u)),u);",
  "    // FIX94 (extra.w = the margin, 0 off): the bar follows the lens' rim,",
  "    // magnified vertically per column (WXGLensBarZoom), not bent.",
  "    float zf=1.;",
  "    if(u.extra.w>0. && !flat) {",
  "        zf=WXGLensBarZoom(p.x,barMid.x,barMid.y,u.bar.z*u.motion.x,u.bar.w*u.motion.x,center.x,center.y,u.lens.z,u.lens.w,",
  "                          u.bar.w*u.motion.x,press,u.optics.z,optical.edgeWidth,u.sync.y,u.sync.z,u.extra.w);",
  "        bend=wxgBasePoint(float2(p.x,barMid.y+(p.y-barMid.y)/zf),u);",
  "    }",
  "    WXGLensBar r;",
  "    // FIX97: how strongly the lens refracts the bar here: deep in its band, and",
  "    // the band's width against the ends' (1 at the ends, the top / bottom",
  "    // ratio above and below); the direction.",
  "    r.rim=wxgEdge(lens.distance,barBand)*clamp(barBand/max(optical.edgeWidth,1.),0.,1.);r.n=n;",
  "    r.s=wxgShape(bend,u.bar,u.rim.w);",
  "    r.insetBent=flat?WXGLensFullInset(u.bar.w*u.motion.x,press,u.optics.z):wxgLensInset(bend,press,u);   // FIX88: the slope first, then refracted",
  "    // The magnified bar's distance on screen: vertical stretch only, so by its",
  "    // normal (the top / bottom zf times, the ends' sides 1).",
  "    r.dd=(r.s.distance*u.motion.x+r.insetBent)/max(length(float2(r.s.nx,r.s.ny/zf)),1./zf);",
  "    return r;",
  "}",
  "// The bar's outline stroke in the lens for one channel's coverage / distance.",
  "float wxgLensStroke(float cv,float dd,float soft,WXGShapeSample s,constant WXGUniforms &u) {",
  "    return u.glow.x>.5?wxgGlowStroke(cv,-dd,u.optics.y,s.nx,s.ny,u.glow):max(0.,cv-(1.-smoothstep(-soft,soft,dd+u.optics.y)));",
  "}",
  "// FIX98: how much of the resting selection colour shows: the dock's own",
  "// (extra2.w = 1 + weight: a tap's scripted fade), else by the press.",
  "float wxgSelectionWeight(float press,constant WXGUniforms &u) {return u.extra2.w>.5?saturate(u.extra2.w-1.):WXGRestingSelectionWeight(press);}",
  "// FIX97: the bar's layers in the lens (veil, outline stroke, second",
  "// highlight, resting selection) for one distance; premultiplied. With the",
  "// colour split off this is exactly the FIX46..FIX96 lens pass.",
  "float4 wxgLensBarLayers(float dd,float soft,float em,float rimStrength,float selW,WXGShapeSample s,constant WXGUniforms &u) {",
  "    float cv=1.-smoothstep(-soft,soft,dd);",
  "    float4 acc=float4(u.tintColor.rgb,1.)*(WXGMaterialOpacity(u.tintColor.a,u.appearance.y,em,u.motion.y)*cv);",
  "    acc=wxgOver(float4(u.borderColor.rgb,1.)*(wxgLensStroke(cv,dd,soft,s,u)*u.borderColor.a*rimStrength),acc);",
  "    if(u.glow.x>.5) acc=wxgOver(float4(u.glowColor2.rgb,1.)*(wxgGlowStroke(cv,-dd,u.extra.x,s.nx,s.ny,u.glow2)*u.glowColor2.a),acc);   // FIX89",
  "    return wxgOver(float4(u.selectionColor.rgb,1.)*(u.selectionColor.a*cv*selW),acc);",
  "}",
  "// FIX97: the same layers over a continuous spectrum, blue (t = -1, the bar at",
  "// p - split) to red (t = +1, p + split), seven wavelengths with the distance",
  "// quadratic through the three asked for; red / green / blue weigh them by",
  "// tents peaking at t = 1 / 0 / -1. A thin highlight fans into a soft rainbow,",
  "// not three separate coloured lines; with no split it is wxgLensBarLayers.",
  "// Core Animation lays this layer over the live page with ONE alpha (the most",
  "// covered channel's), so a channel covered less would show too little of the",
  "// page: that share of the page behind (extra2.z, its brightness: black in",
  "// dark mode, white in light) is added back, exact over that page.",
  "float4 wxgLensBarSpectrum(float dd,float ddR,float ddB,float soft,float em,float rimStrength,float selW,WXGShapeSample s,constant WXGUniforms &u) {",
  "    float a1=(ddR-ddB)*.5,a2=(ddR+ddB)*.5-dd;",
  "    float wide=max(soft,abs(a1)*.25+abs(a2)*.4);   // each wavelength covers its step (the largest, t 2/3..1)",
  "    float3 rgb=float3(0.),alpha=float3(0.);",
  "    for(int k=0;k<7;k++) {",
  "        float t=float(k)/3.-1.;",
  "        float3 w=float3(saturate(t),1.-abs(t),saturate(-t));",
  "        float4 l=wxgLensBarLayers(dd+t*(a1+t*a2),wide,em,rimStrength,selW,s,u);",
  "        rgb+=w*l.rgb;alpha+=w*l.a;",
  "    }",
  "    rgb/=float3(2.,3.,2.);alpha/=float3(2.,3.,2.);",
  "    float most=max(alpha.x,max(alpha.y,alpha.z));",
  "    return float4(rgb+saturate(u.extra2.z)*(float3(most)-alpha),most);",
  "}",
  "fragment float4 wxgFragment(WXGOut in [[stage_in]],constant WXGUniforms &u [[buffer(0)]],",
  "                            texture2d<float> raw [[texture(0)]],",
  "                            texture2d<float> normalIcons [[texture(1)]],",
  "                            texture2d<float> selectedIcons [[texture(2)]],",
  "                            texture2d<float> soft [[texture(3)]],",
  "                            texture2d<float> bodyField [[texture(4)]],",
  "                            texture2d<float> lensSoft [[texture(5)]]) {",
  "    float2 p=in.uv*u.viewport.xy;",
  "    // Native continuous clipping and separate native-width directional rims",
  "    // own the final silhouette. No second analytical alpha mask cuts it again.",
  "    float2 base=wxgBasePoint(p,u);",
  "    WXGOpticalValues bodyOptics={u.material.y,u.material.z,u.optics.w};",
  "    if(u.appearance.w<.5) {",
  "        // Ordinary buttons deform one body. This path has no selection tint,",
  "        // inner capsule, second silhouette or lens rim; dock optics stay intact.",
  "        float2 bodyRay=p;",
  "        if(u.appearance.w<-.5) {",
  "            float buttonPress=clamp(u.material.x,0.,1.);",
  "            bodyOptics.refraction*=1.+.35*buttonPress;",
  "            bodyOptics.dispersion*=1.+.20*buttonPress;",
  "            float2 bodyCenter=u.bar.xy+u.bar.zw*.5;",
  "            bodyRay=bodyCenter+(p-bodyCenter)/(1.+.04*buttonPress);",
  "        }",
  "        float3 face=wxgBody(raw,soft,soft,0.,u.motion.z,base,0.,bodyRay,float2(0),bodyOptics,u);",
  "        if(u.sync.x>.5) {",
  "            WXGShapeSample shape=wxgShape(base,u.bar,u.rim.w);",
  "            float e=wxgEdge(shape.distance,bodyOptics.edgeWidth);",
  "            // FIX40: sync.w = 1: the veil is a render-server layer under this",
  "            // pass (always present, cold start included); draw icons only.",
  "            float k=u.sync.w>.5?0.:WXGMaterialOpacity(u.tintColor.a,u.appearance.y,wxgEdge(shape.distance,wxgVeilWidth(bodyOptics.edgeWidth,u)),u.motion.y);",
  "            float4 veil=wxgSyncBase(face,u.sync.x>1.5?0.:e,k,u);",
  "            float4 withIcons=wxgIconsOver(normalIcons,base,float2(0),veil,u);",
  "            // FIX37: inside the dock's lens the lens pass draws the selected",
  "            // (filled) icons; the body must not draw the unselected ones there",
  "            // too, or both show (refracted, slightly offset) as a ghost.",
  "            if(u.sync.x>1.5 && u.lens.z>.5 && u.lens.w>.5) {",
  "                WXGShapeSample inLens=wxgShape(p,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));",
  "                withIcons=mix(withIcons,veil,1.-smoothstep(-.5,.5,inLens.distance));",
  "            }",
  "            return withIcons;",
  "        }",
  "        return float4(wxgIcons(normalIcons,base,float2(0),face,u),1);",
  "    }",
  "    float aa=.8/u.viewport.z,press=clamp(u.material.x,0.,1.);",
  "    WXGOpticalValues independent={u.lensOptics.x,u.lensOptics.y,u.lensOptics.z};",
  "    WXGOpticalValues optical=WXGPressedOptics(bodyOptics,independent,press);",
  "    WXGShapeSample lens=wxgShape(p,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));",
  "    float2 center=u.lens.xy+u.lens.zw*.5,n=float2(lens.nx,lens.ny);",
  "    float zoom=1.+press*(u.optics.x-1.);",
  "    // FIX21: the lens rim is widest at its rounded ends and thin above/below the bar.",
  "    // FIX47: a lens end past the bar's end narrows to the top/bottom width.",
  "    float lensWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,optical.edgeWidth,u.sync.y,u.sync.z,wxgShape(base,u.bar,u.rim.w).distance*u.motion.x);",
  "    float offset=WXGLensRefractionOffset(lens.distance,lensWidth,optical.refraction,u.style.w)*press*wxgLensDirection(u);   // FIX113 I",
  "    float2 refracted=p-n*offset;",
  "    float2 ray=center+(refracted-center)/zoom;",
  "    // FIX88: the colour split over its own band (u.extra.y, its own top /",
  "    // bottom ratio u.extra.z), blended from the glass's band as it lifts.",
  "    float dispSide=u.extra.y>0.?mix(bodyOptics.edgeWidth,u.extra.y,press):optical.edgeWidth;",
  "    float dispWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,dispSide,u.extra.z>0.?u.extra.z:u.sync.y,u.sync.z,wxgShape(base,u.bar,u.rim.w).distance*u.motion.x);",
  "    float2 chroma=n*(optical.dispersion*wxgEdge(lens.distance,dispWidth)*(1.55*press));",
  "    float2 iconCenter=float2(u.motion.w,u.bar.y+u.bar.w*.5);",
  "    // FIX21: icons are magnified about their own anchor in the bar's unscaled",
  "    // space, so an elastically stretched lens (whose centre shifts) cannot move them.",
  "    float2 barCentre=u.bar.xy+u.bar.zw*.5;",
  "    float2 iconRay=iconCenter+((barCentre+(refracted-barCentre)/u.motion.x)-iconCenter)/zoom;",
  "    // Change only the geometric contour: regular parallel inset at top, bottom",
  "    // and both ends. Optical sampling never displaces this contour.",
  "    WXGShapeSample body=wxgShape(base,u.bar,u.rim.w);",
  "    float nativeDistance=body.distance;",
  "    if(u.appearance.z>.5) nativeDistance=bodyField.sample(wxgSampler,base/u.viewport.xy).r;",
  "    float inset=WXGLensFlatCode(u.extra.w)?WXGLensFullInset(u.bar.w*u.motion.x,press,u.optics.z):wxgLensInset(base,press,u);   // FIX88 (was WXGInnerInset by the lens distance); FIX113 M flat",
  "    float d=nativeDistance*u.motion.x+inset;",
  "    float coverage=wxgMask(d,aa),stroke=max(0.,coverage-wxgMask(d+u.optics.y,aa));",
  "    if(u.sync.x>1.5) {",
  "        // Render-server lens: the shared backdrop is live underneath. Draw the",
  "        // same veil, rim stroke, resting selection and zoomed icons only.",
  "        // FIX44: the bar under the lens is bent by the lens' refraction.",
  "        // FIX46: by the refraction band only (no zoom), so the inset smaller",
  "        // inner bar stays; analytic outline antialiased over its actual",
  "        // screen-space gradient (no stair steps or torn slivers).",
  "        // FIX57: as a lens end reaches the bar's end, the bar seen through it",
  "        // uses the band relaxed toward the top/bottom width (no more sticking",
  "        // to the rim at the first / last tab); icons keep lensWidth.",
  "        // (All of it in wxgLensBar, FIX97.)",
  "        WXGLensBar g=wxgLensBar(p,press,optical,u);",
  "        WXGShapeSample s=g.s;",
  "        float dd=g.dd;",
  "        // FIX97 (extra2.x: the split everywhere in the lens, growing from its",
  "        // centre to its rim like a dome's; extra2.y: the share of the lens' own",
  "        // colour split where the lens refracts the bar (its ends' wide band,",
  "        // thin above and below); both 0 = off, as FIX46..FIX96): the bar seen",
  "        // through the lens splits its colours too, across all of its edges",
  "        // (the slots' \"brackets\", its outline highlights): red from that far",
  "        // out, blue from that far in, over a continuous spectrum (FIX46's",
  "        // removed split had three separate lines and no switch).",
  "        float soft=max(aa,fwidth(dd)*.75);",
  "        float em=wxgEdge(s.distance+g.insetBent/u.motion.x,wxgVeilWidth(optical.edgeWidth,u));",
  "        float rimStrength=WXGRimStrengthTLBR(s.nx,s.ny,u.rim.x,u.style.y,u.style.z)*mix(1.,u.rim.y,u.appearance.x);",
  "        float selW=wxgSelectionWeight(press,u);",
  "        float4 acc=wxgLensBarLayers(dd,soft,em,rimStrength,selW,s,u);",
  "        if(u.extra2.x>0. || u.extra2.y>0.) {",
  "            float2 dome=(p-center)/max(u.lens.zw*.5,float2(1.));",
  "            float2 split=dome*(u.extra2.x*press)+g.n*(u.extra2.y*optical.dispersion*1.55*press*g.rim);",
  "            if(lens.distance<1. && dot(split,split)>1e-6)   // the lens canvas is the whole view: only in the lens",
  "                acc=wxgLensBarSpectrum(dd,wxgLensBar(p+split,press,optical,u).dd,wxgLensBar(p-split,press,optical,u).dd,soft,em,rimStrength,selW,s,u);",
  "        }",
  "        return wxgIconsOver(selectedIcons,iconRay,chroma/(u.motion.x*zoom),acc,u);",
  "    }",
  "    float3 clear=wxgRGB(raw,ray,chroma,u);",
  "    float blurCoverage=mix(u.motion.z,u.lensOptics.w,press);",
  "    float3 ringSoft=mix(wxgRGB(soft,ray,chroma,u),wxgRGB(lensSoft,ray,chroma,u),press);",
  "    clear=mix(clear,ringSoft,WXGLensRingBlurWeight(lens.distance,lensWidth,blurCoverage));",
  "    // Coverage zero preserves the TEST8 clear ring. Disabling material",
  "    // attenuation applies the same tint veil over the whole lens ring.",
  "    if(u.motion.y<.5) clear=mix(clear,u.tintColor.rgb,WXGMaterialOpacity(u.tintColor.a,u.appearance.y,0.,0.));",
  "    float3 material=wxgBody(raw,soft,lensSoft,press,blurCoverage,base,inset/u.motion.x,ray,chroma,optical,u);",
  "    float3 face=mix(clear,material,coverage);",
  "    float rimStrength=WXGRimStrengthTLBR(body.nx,body.ny,u.rim.x,u.style.y,u.style.z)*mix(1.,u.rim.y,u.appearance.x);",
  "    if(u.glow.x>.5) stroke=wxgGlowStroke(coverage,-d,u.optics.y,body.nx,body.ny,u.glow);   // FIX86",
  "    face=mix(face,u.borderColor.rgb,stroke*u.borderColor.a*rimStrength);",
  "    if(u.glow.x>.5) face=mix(face,u.glowColor2.rgb,wxgGlowStroke(coverage,-d,u.extra.x,body.nx,body.ny,u.glow2)*u.glowColor2.a);   // FIX89",
  "    // Withdraw the resting selection as the lens rises. It must not leave a",
  "    // selected-colour patch where the raised lens overlaps the ordinary bar.",
  "    face=mix(face,u.selectionColor.rgb,u.selectionColor.a*coverage*wxgSelectionWeight(press,u));",
  "    return float4(wxgIcons(selectedIcons,iconRay,chroma/(u.motion.x*zoom),face,u),1);",
  "}",
  "",
].join("\n");

// ───────────────────────── FIX108 · 管理接口 + KV 名单 / 活动 ─────────────────────────
// KV 绑定名 LIST（在 wrangler.jsonc 里配）。没配就整段退化：名单回退到文件顶部的
// ALLOWLIST 常量，/v1/admin/* 一律 503 —— 所以这份 worker 不配 KV 也能照旧跑，可零风险先部署。
//
//   allow:<account>   {account, note, addedAt}             —— 在这张表里即「已授权」
//   seen:<account>    {account, lastDevice, devices:[{d,last}], deviceCount, activeDevices, flagged, lastTs, firstTs, count, lastResult}
//   ev:<ts>:<rand>    {ts, account, device, result}         —— 近期核对流水（30 天 TTL）
const LICENSE_PREFIX = "WXGLiquidGlass.license.v1:";
const EV_TTL = 30 * 24 * 3600;
// FIX114（A：设备治理）：每账号记录用过的设备，近 DEVICE_WINDOW 内 >1 台即 flagged（授权台爆红，只标记、不拦截）。
// SEEN_TTL 让 seen: 记录“不活动即过期（每次核对刷新）”，防被随机账号刷爆 KV（审计 H1）。
const SEEN_TTL = 90 * 24 * 3600;        // 90 天不活动即过期；正版常核对会不断刷新
const DEVICE_WINDOW = 7 * 24 * 3600;    // 近 7 天算“在用”（与票据有效期一致）
const DEVICE_KEEP = 5;                  // 每账号最多留最近 5 台设备

function hasKV(env) { return !!(env && env.LIST && typeof env.LIST.get === "function"); }
async function sha256hex(str) { return toHex(await sha256(utf8(str))); }

// KV 是否已导入名单（判定回退用，只在「账号不在 KV」时才查，开销落在拒绝分支）
async function kvPopulated(env) {
  const r = await env.LIST.list({ prefix: "allow:", limit: 1 });
  return r.keys.length > 0;
}
// 名单判定：KV 优先；KV 尚未导入任何名单时回退常量，避免误锁测试机。
async function isAllowed(env, account) {
  if (hasKV(env)) {
    if (await env.LIST.get("allow:" + account)) return true;
    if (await kvPopulated(env)) return false;              // KV 已是权威来源
  }
  return ALLOWLIST.map(s => s.trim().toLowerCase()).includes(account);   // 回退
}
async function listMeta(env) {
  if (!hasKV(env)) return { source: "const", count: ALLOWLIST.length };
  let count = 0, cursor;
  do { const r = await env.LIST.list({ prefix: "allow:", cursor }); count += r.keys.length; cursor = r.list_complete ? undefined : r.cursor; } while (cursor);
  return { source: "kv", count };
}

// 核对流水：尽力而为，绝不影响解锁响应（ctx.waitUntil + try/catch 吞掉一切）。
function logCheckin(env, ctx, account, device, result) {
  if (!hasKV(env) || !/^[0-9a-f]{64}$/.test(account)) return;
  const ts = Math.floor(Date.now() / 1000);
  const validDevice = /^[0-9a-f]{64}$/.test(device || "") ? device : "";   // 只认正版设备指纹，脏值不进集合
  const job = (async () => {
    try {
      const prev = JSON.parse(await env.LIST.get("seen:" + account) || "null") || {};
      // FIX117：被拒记录全部写回（含从没见过的账号）——新人/被踢/加错账号的“拒绝”都会出现在
      // 授权台核对记录里，拿它来对账号哈希、给新人开通。当初 FIX115 为防洪水跳过写入，现在洪水已由
      // FIX116 边缘限流 + ev:/seen: 的 TTL + 管理页扫描封顶兜住，恢复安全。
      // FIX114：设备集合 [{d,last}]，只在成功核对(ok)时累计（被拒的不算“在用”）。
      let devices = Array.isArray(prev.devices) ? prev.devices.filter(x => x && typeof x.d === "string")
                  : (prev.lastDevice ? [{ d: prev.lastDevice, last: prev.lastTs || ts }] : []);
      const knownDevice = validDevice && devices.some(x => x.d === validDevice);   // FIX120：加设备前先判断是不是老设备
      if (result === "ok" && validDevice) {
        const i = devices.findIndex(x => x.d === validDevice);
        if (i >= 0) devices[i] = { d: validDevice, last: ts };
        else devices.push({ d: validDevice, last: ts });
        devices.sort((a, b) => (b.last || 0) - (a.last || 0));   // 最近在前
        if (devices.length > DEVICE_KEEP) devices = devices.slice(0, DEVICE_KEEP);
      }
      const activeDevices = devices.filter(x => ts - (x.last || 0) <= DEVICE_WINDOW).length;
      const flagged = activeDevices > 1;
      // FIX120：砍 KV 写入——只在“有变化”或“跨 UTC 天保底”时写 seen:/ev:，其余（同设备·同结果·同状态·同一天）
      // 跳过（读照旧）。稳定用户≈每账号每天一次写；新设备 / 被拒 / 爆红翻转即时写，多设备检测不受影响。
      const material = !prev.lastTs
                    || result !== (prev.lastResult || "")
                    || (result === "ok" && validDevice && !knownDevice)
                    || flagged !== !!prev.flagged
                    || Math.floor((prev.lastTs || 0) / 86400) !== Math.floor(ts / 86400);
      if (!material) return;
      const seen = {
        account,
        lastDevice: validDevice || prev.lastDevice || "",
        devices,
        deviceCount: devices.length,
        activeDevices,
        flagged,                                    // A：近 7 天 >1 台设备 → 授权台爆红（只标记、不拦截）
        lastTs: ts,
        firstTs: prev.firstTs || ts,
        count: (prev.count | 0) + 1,
        lastResult: result,
      };
      await env.LIST.put("seen:" + account, JSON.stringify(seen), { expirationTtl: SEEN_TTL });
      const rand = Math.random().toString(36).slice(2, 8);
      await env.LIST.put(`ev:${ts}:${rand}`, JSON.stringify({ ts, account, device: validDevice, result }), { expirationTtl: EV_TTL });
    } catch { /* 日志失败不影响授权 */ }
  })();
  if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(job); else job.catch(() => {});
}

// ── 鉴权 ──
function tseq(a, b) { if (a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; }
// L7: 比对口令的 SHA-256（两边都是 64-hex 定长），tseq 定长恒时比较，不通过响应时序泄露口令长度。
async function adminAuthed(req, env) {
  if (!env.ADMIN_TOKEN) return false;
  const m = /^Bearer\s+(.+)$/i.exec((req.headers.get("authorization") || "").trim());
  if (!m) return false;
  const a = await sha256hex(m[1]);
  const b = await sha256hex(env.ADMIN_TOKEN);
  return tseq(a, b);
}

// ── 路由 ──
async function admin(req, env, url) {
  // L6：先统一鉴权（未授权一律 401），再暴露任何配置状态（KV 是否绑定等），不给未鉴权者当探针。
  if (!(await adminAuthed(req, env))) return json({ error: "unauthorized" }, 401);
  if (!hasKV(env)) return json({ error: "admin disabled (bind KV namespace LIST)" }, 503);
  const p = url.pathname;

  if (p === "/v1/admin/ping" && req.method === "GET") {
    const meta = await listMeta(env);
    return json({ ok: true, admin: true, ver: VER, allowCount: meta.count, recheckAfter: RECHECK_AFTER, signKey: env.SIGN_PRIV ? "set" : "missing" });
  }

  if (p === "/v1/admin/allow") {
    if (req.method === "GET") {
      const entries = []; let cursor;
      do {
        const r = await env.LIST.list({ prefix: "allow:", cursor });
        for (const k of r.keys) { const v = JSON.parse(await env.LIST.get(k.name) || "null"); if (v) entries.push(v); }
        cursor = r.list_complete ? undefined : r.cursor;
      } while (cursor);
      entries.sort((a, b) => (b.addedAt || 0) - (a.addedAt || 0));
      return json({ count: entries.length, entries });
    }
    if (req.method === "POST") {
      let body; try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
      let account = String(body.account || "").toLowerCase().trim();
      if (!account && body.wxid) account = await sha256hex(LICENSE_PREFIX + String(body.wxid));   // 服务器侧也能从 wxid 算，双保险
      if (!/^[0-9a-f]{64}$/.test(account)) return json({ error: "bad account" }, 400);
      const old = JSON.parse(await env.LIST.get("allow:" + account) || "null");
      const entry = { account, note: String(body.note || (old && old.note) || "").slice(0, 200), addedAt: (old && old.addedAt) || Math.floor(Date.now() / 1000) };
      await env.LIST.put("allow:" + account, JSON.stringify(entry));
      return json({ ok: true, added: !old, entry });
    }
    return json({ error: "method not allowed" }, 405);
  }

  if (p.startsWith("/v1/admin/allow/") && req.method === "DELETE") {
    const account = decodeURIComponent(p.slice("/v1/admin/allow/".length)).toLowerCase().trim();
    if (!/^[0-9a-f]{64}$/.test(account)) return json({ error: "bad account" }, 400);
    const existed = !!(await env.LIST.get("allow:" + account));
    await env.LIST.delete("allow:" + account);
    return json({ ok: true, removed: existed });
  }

  if (p === "/v1/admin/seed" && req.method === "POST") {   // 把文件顶部 ALLOWLIST 常量导入 KV（幂等）
    let added = 0;
    for (const raw of ALLOWLIST) {
      const account = raw.trim().toLowerCase();
      if (!/^[0-9a-f]{64}$/.test(account)) continue;
      if (await env.LIST.get("allow:" + account)) continue;
      await env.LIST.put("allow:" + account, JSON.stringify({ account, note: "seed from worker.js", addedAt: Math.floor(Date.now() / 1000) }));
      added++;
    }
    const meta = await listMeta(env);
    return json({ ok: true, added, count: meta.count });
  }

  if (p === "/v1/admin/activity" && req.method === "GET") {
    const limit = Math.min(parseInt(url.searchParams.get("limit") || "100", 10) || 100, 1000);
    const names = []; let cursor;
    do {
      const r = await env.LIST.list({ prefix: "ev:", cursor });
      for (const k of r.keys) names.push(k.name);
      cursor = r.list_complete ? undefined : r.cursor;
    } while (cursor && names.length < 5000);
    names.sort();                                   // 键名含零填充 ts，升序即时间序
    const events = [];
    for (const name of names.slice(-limit)) { const v = JSON.parse(await env.LIST.get(name) || "null"); if (v) events.push(v); }
    events.reverse();                               // 最新在前
    const accounts = []; cursor = undefined;
    do {
      const r = await env.LIST.list({ prefix: "seen:", cursor });
      for (const k of r.keys) { const v = JSON.parse(await env.LIST.get(k.name) || "null"); if (v) accounts.push(v); }
      cursor = r.list_complete ? undefined : r.cursor;
    } while (cursor && accounts.length < 5000);   // FIX114/H1：给 seen: 扫描封顶，防被刷爆后拖垮管理页
    accounts.sort((a, b) => (b.lastTs || 0) - (a.lastTs || 0));
    return json({ events, accounts });
  }

  return json({ error: "not found" }, 404);
}
