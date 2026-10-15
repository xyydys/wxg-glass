#!/usr/bin/env node
// FIX107 · 着色器水印解码：从一份泄露的 .metal 反查它是从哪个授权账号扒出去的。
//
//   node plugin/tools/watermark_decode.mjs <leaked.metal> <SIGN_PRIV(base64 pkcs8)> [account_hash ...]
//
// SIGN_PRIV 就是 Cloudflare 上那把签名私钥(同一把，用来派生水印钥匙)。不传 account 时，
// 自动读取 server/worker.js 里的 ALLOWLIST 逐个比对。原理：服务器下发给每个账号的着色器，会把
// 8 个 Metal-only 的保护/边界常数按 账号+私钥 做确定性微扰(肉眼无感、二进制里没有参照)；这里按
// 同一组上下文读回那 8 个值、还原每个槽的整数，再对候选账号重算一遍，完全一致的那个就是源头。
// WM_SITES / 派生逻辑必须与 server/worker.js 保持一致。
import { readFileSync } from 'node:fs';
import { createHash, createHmac } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// 与 server/worker.js 的 WM_SITES 一一对应(pre/suf 是常数在着色器里的唯一上下文)。
const WM_SITES = [
  { pre: "aa=",             suf: "/u.viewport.z",     base: 0.8  },
  { pre: "max(width,",      suf: ")",                 base: 0.01 },
  { pre: "max(g.w,",        suf: ")",                 base: 0.05 },
  { pre: "max(g.z,",        suf: ")",                 base: 0.05 },
  { pre: "refraction*=1.+", suf: "*buttonPress",      base: 0.35 },
  { pre: "dispersion*=1.+", suf: "*buttonPress",      base: 0.20 },
  { pre: "(1.+",            suf: "*buttonPress)",     base: 0.04 },
  { pre: "smoothstep(-.5,", suf: ",inLens.distance)", base: 0.5  },
];
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const unit = b => b * 0.0008;

function slotsFor(account, signPriv) {
  const key = createHash('sha256').update('wxg.watermark.v1|' + signPriv).digest();
  return WM_SITES.map((_, i) => createHmac('sha256', key).update(account + '|' + i).digest()[0] % 16);
}
function extract(metal) {
  const vals = [];
  for (const s of WM_SITES) {
    const m = metal.match(new RegExp(esc(s.pre) + '\\s*([0-9.]+)\\s*' + esc(s.suf)));
    if (!m) return null;
    vals.push(Number(m[1]));
  }
  return vals;
}
const recoverSlots = values => values.map((v, i) => Math.round((v - WM_SITES[i].base) / unit(WM_SITES[i].base) + 7.5));

const [, , leakedPath, signPriv, ...accountsArg] = process.argv;
if (!leakedPath || !signPriv) {
  console.error('用法: node watermark_decode.mjs <leaked.metal> <SIGN_PRIV base64> [account_hash ...]');
  process.exit(2);
}
const metal = readFileSync(leakedPath, 'utf8');
const values = extract(metal);
if (!values) {
  console.error('没找到全部 8 个水印站点：这份可能被改写过，或不是本插件的着色器。');
  process.exit(1);
}
const leaked = recoverSlots(values);
console.log('水印槽:', leaked.join(','), '  原始值:', values.join(','));

let accounts = accountsArg;
if (!accounts.length) {
  const worker = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), '../../server/worker.js'), 'utf8');
  accounts = [...worker.matchAll(/"([0-9a-f]{64})"/g)].map(m => m[1]);
}
const hit = accounts.find(acc => slotsFor(acc, signPriv).every((k, i) => k === leaked[i]));
if (hit) console.log('\n✅ 源头账号（授权码哈希）:', hit);
else console.log('\n❌ 候选名单里没有完全匹配的账号——可能不是名单内账号扒的，或水印被改动过（可逐槽比对上面的槽值）。');
