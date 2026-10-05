// render cheatsheet.html -> cheatsheet.pdf at scale 1 (no shrink-to-fit), and report overflow
// usage: node render.mjs [in.html] [out.pdf]
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const CHROME = process.env.CHROME || `${process.env.HOME}/.cache/ms-playwright/chromium_headless_shell-1223/chrome-headless-shell-linux64/chrome-headless-shell`;
const src = resolve(process.argv[2] || 'cheatsheet.html');
const out = resolve(process.argv[3] || 'cheatsheet.pdf');
const dir = mkdtempSync(join(tmpdir(), 'cs-'));
const page = join(dir, 'page.html');
writeFileSync(page, '<!doctype html><html><head><meta charset="utf-8"></head><body>' + readFileSync(src, 'utf8') + '</body></html>');

const port = 9333 + Math.floor(Math.random() * 500);
const ch = spawn(CHROME, ['--no-sandbox', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/prof`, 'about:blank'], { stdio: 'ignore' });
// content box in CSS px: landscape letter minus 0.25in margins (PAGE=portrait for 8.5x11)
const [W, H] = process.env.PAGE === 'portrait' ? [768, 1008] : [1008, 768];
const sleep = ms => new Promise(r => setTimeout(r, ms));
let ws;
for (let i = 0; i < 50; i++) {
  try {
    const t = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
    const p = t.find(x => x.type === 'page');
    if (p) { ws = new WebSocket(p.webSocketDebuggerUrl); break; }
  } catch {}
  await sleep(100);
}
await new Promise(r => ws.addEventListener('open', r));
let id = 0; const pending = new Map(); const events = [];
ws.addEventListener('message', m => { const d = JSON.parse(m.data); if (d.id) { pending.get(d.id)?.(d); pending.delete(d.id); } else events.push(d); });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });

await send('Page.enable');
await send('Emulation.setEmulatedMedia', { media: 'print' });
await send('Page.navigate', { url: 'file://' + page });
for (let i = 0; i < 100 && !events.some(e => e.method === 'Page.loadEventFired'); i++) await sleep(100);
await send('Runtime.evaluate', { expression: 'document.fonts.ready', awaitPromise: true });
await sleep(300);
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
await send('Emulation.setScrollbarsHidden', { hidden: true });
await sleep(200);
// options: FS=7.4 fixes the size; otherwise binary-search the largest --fs that fits for each MONOS entry
const monos = (process.env.MONOS || 'IBM Plex Mono|100%|0.95').split(',').map(x => x.split('|'));
const probe = await send('Runtime.evaluate', { returnByValue: true, awaitPromise: true, expression: `(async () => {
  const root = document.documentElement.style;
  const fits = () => [...document.querySelectorAll('.cols')].every(c => c.scrollWidth <= c.clientWidth + 1)
                     && document.documentElement.scrollHeight <= ${H} && document.documentElement.scrollWidth <= ${W + 1};
  const raf = () => new Promise(r => requestAnimationFrame(() => r()));
  const res = []; window.__halves = () => [...document.querySelectorAll(".cols")].map(c => c.scrollWidth + "/" + c.clientWidth);
  for (const [fam, stretch, scale] of ${JSON.stringify(monos)}) {
    root.setProperty('--mono', '"' + fam + '", monospace'); root.setProperty('--mstretch', stretch); root.setProperty('--mscale', scale);
    let lo = 5, hi = 10;
    ${process.env.FS ? `lo = ${process.env.FS};` : `for (let i = 0; i < 14; i++) { const mid = (lo + hi) / 2; root.setProperty('--fs', mid + 'pt'); await raf(); if (fits()) lo = mid; else hi = mid; }`}
    root.setProperty('--fs', lo.toFixed(2) + 'pt'); await raf();
    res.push({fam, stretch, scale, fs: +lo.toFixed(2), fits: fits(), halves: window.__halves(), load: [...document.fonts].filter(f=>f.status==='loaded').map(f=>f.family).filter((v,i,a)=>a.indexOf(v)===i).join('/')});
    if (${process.env.AT || 0}) { root.setProperty('--fs', '${process.env.AT || 7}pt'); await raf(); res.push({at: ${process.env.AT || 0}, halves: [...document.querySelectorAll('.cols')].map(c => (c.scrollWidth / c.clientWidth).toFixed(2))}); root.setProperty('--fs', lo.toFixed(2) + 'pt'); await raf(); }
  }
  return res; })()` });
const results = probe.result.result.value;
console.error(JSON.stringify(results));
const pdf = await send('Page.printToPDF', { preferCSSPageSize: true, scale: 1, printBackground: true, displayHeaderFooter: false });
writeFileSync(out, Buffer.from(pdf.result.data, 'base64'));
ws.close(); ch.kill();
