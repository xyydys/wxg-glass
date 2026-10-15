#!/usr/bin/env node
// FIX106 · 着色器水印解码：从一份泄露的 .metal 反查它是从哪个授权账号扒出去的。
//
//   node plugin/tools/watermark_decode.mjs <leaked.metal> <SIGN_PRIV(base64 pkcs8)> [account_hash ...]
//
// SIGN_PRIV 就是 Cloudflare 上那把签名私钥（同一把，用来派生水印钥匙）。不传 account 时，
// 自动读取 server/worker.js 里的 ALLOWLIST 逐个比对。原理：服务器下发给每个账号的着色器，会把
// WXGContinuousDeviation 的 5 个拟合系数按 账号+私钥 做确定性微扰（肉眼无感）；这里读出那 5 个
// 值、还原每个槽的整数，再对候选账号重算一遍，完全一致的那个就是源头。与 server/worker.js 的
// watermarkKey / watermarkSlots / wmValue 必须保持一致。
import { readFileSync } from 'node:fs';
import { createHash, createHmac } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const WM_BASE = [0.000865, 0.007454, 0.002456, 0.002256, 0.002806];
const unit = b => b * 0.0008;

function slotsFor(account, signPriv) {
  const key = createHash('sha256').update('wxg.watermark.v1|' + signPriv).digest();
  return WM_BASE.map((_, i) => createHmac('sha256', key).update(account + '|' + i).digest()[0] % 16);
}
function recoverSlots(values) {
  return values.map((v, i) => Math.round((v - WM_BASE[i]) / unit(WM_BASE[i]) + 7.5));
}
function extract(metal) {
  const m = metal.match(/return\s*([0-9.]+)f?\s*\*\s*s1\s*-\s*([0-9.]+)f?\s*\*\s*s2\s*-\s*([0-9.]+)f?\s*\*\s*s3\s*\+\s*([0-9.]+)f?\s*\*\s*s4\s*\+\s*([0-9.]+)f?\s*\*\s*s5/);
  return m ? m.slice(1, 6).map(Number) : null;
}

const [, , leakedPath, signPriv, ...accountsArg] = process.argv;
if (!leakedPath || !signPriv) {
  console.error('用法: node watermark_decode.mjs <leaked.metal> <SIGN_PRIV base64> [account_hash ...]');
  process.exit(2);
}
const metal = readFileSync(leakedPath, 'utf8');
const values = extract(metal);
if (!values) {
  console.error('没找到水印系数行（return ...*s1-...*s2...）：这份可能被改写过，或不是本插件的着色器。');
  process.exit(1);
}
const leaked = recoverSlots(values);
console.log('水印槽:', leaked.join(','), '  原始系数:', values.join(','));

let accounts = accountsArg;
if (!accounts.length) {
  const worker = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), '../../server/worker.js'), 'utf8');
  accounts = [...worker.matchAll(/"([0-9a-f]{64})"/g)].map(m => m[1]);
}
const hit = accounts.find(acc => slotsFor(acc, signPriv).every((k, i) => k === leaked[i]));
if (hit) console.log('\n✅ 源头账号（授权码哈希）:', hit);
else console.log('\n❌ 候选名单里没有完全匹配的账号——可能不是名单内账号扒的，或水印被改动过。');
