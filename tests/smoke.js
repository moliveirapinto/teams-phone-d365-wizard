// Smoke test: loads the wizard against the mock, checks auto-detection, generates the PowerShell,
// syntax-checks it with the PowerShell parser, and exercises the in-wizard Sync flow.
// Prereqs: npm i playwright-core, Microsoft Edge (or set CHANNEL=chrome), PowerShell (pwsh or powershell) on PATH.
// Usage: node tests/mock-d365-server.js &  then  node tests/smoke.js
const { chromium } = require('playwright-core');
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const URL = process.env.WIZARD_URL || 'http://127.0.0.1:8765/';
const assert = (c, m) => { if (!c) { console.error('FAIL: ' + m); process.exitCode = 1; } else console.log('ok   ' + m); };

(async () => {
  const b = await chromium.launch({ channel: process.env.CHANNEL || 'msedge', headless: true });
  const p = await b.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.addInitScript(() => { const st = window.setTimeout; window.setTimeout = (f, ms, ...a) => st(f, (ms || 0) / 100, ...a); });
  await p.goto(URL); await p.waitForTimeout(2000);

  assert(await p.evaluate(() => state.acs === 'a85f3a50-64f4-459a-9661-d8697a106b8a'), 'ACS id auto-detected from the Teams Phone System provider');
  assert(await p.evaluate(() => state.appId === 'e404520c-564a-4e7c-9f33-ad12acc64a90'), 'Dynamics App ID auto-detected');

  await p.locator('input[data-k=phone]').first().fill('+12122108677');
  const ps = await p.evaluate(() => buildPs());
  assert(/Sync-CsOnlineApplicationInstance[^\n]*-AcsResourceId \$AcsId/.test(ps), 'script binds the ACS resource (-AcsResourceId)');
  assert(!/Out-Null\s*\n\s*Sync-Cs/.test(ps), 'binding errors are not swallowed');

  const f = path.join(os.tmpdir(), 'wizard-gen.ps1'); fs.writeFileSync(f, ps);
  const shell = ['pwsh', 'powershell'].find(s => spawnSync(s, ['-NoProfile', '-Command', '1']).status === 0);
  const r = spawnSync(shell, ['-NoProfile', '-Command', `$e=$null;$t=$null;[void][Management.Automation.Language.Parser]::ParseFile('${f}',[ref]$t,[ref]$e);$e.Count`]);
  assert(r.stdout.toString().trim() === '0', 'generated PowerShell parses without errors');

  await p.getByRole('button', { name: /Sync now/ }).click(); await p.waitForTimeout(5000);
  assert(/imported/.test(await p.locator('#resTable').innerText()), 'Sync flow imports the number and reports it');
  assert(errs.length === 0, 'no page errors');
  await b.close();
})();
