// Smoke test: loads the wizard against the mock, checks auto-detection, generates the PowerShell,
// syntax-checks it (and optionally lints it), unit-tests the country fallback, and exercises the
// hands-free flow: download script -> auto-sync -> number imported -> attached to a workstream.
// Prereqs: npm i playwright-core, Microsoft Edge (or CHANNEL=chrome, or CHROME_PATH=<browser exe>),
//          PowerShell (pwsh or powershell) on PATH for the script checks (skipped if missing).
// Usage:   node tests/mock-d365-server.js &   then   node tests/smoke.js      (LINT=1 also runs PSScriptAnalyzer)
// Start a fresh mock for every run: it keeps sync state in memory.
const { chromium } = require('playwright-core');
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const URL = process.env.WIZARD_URL || 'http://127.0.0.1:8765/';
const assert = (c, m) => { if (!c) { console.error('FAIL: ' + m); process.exitCode = 1; } else console.log('ok   ' + m); };
const shell = ['pwsh', 'powershell'].find(s => { try { return spawnSync(s, ['-NoProfile', '-Command', '1']).status === 0; } catch (e) { return false; } });
const ps = cmd => spawnSync(shell, ['-NoProfile', '-NonInteractive', '-Command', cmd]).stdout.toString().trim();

(async () => {
  const launch = process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : { channel: process.env.CHANNEL || 'msedge' };
  const b = await chromium.launch({ ...launch, headless: true });
  const ctx = await b.newContext({ acceptDownloads: true });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  // Run the wizard's timers 100x faster so the 2-minute auto-sync cadence takes seconds.
  await p.addInitScript(() => { const st = window.setTimeout; window.setTimeout = (f, ms, ...a) => st(f, (ms || 0) / 100, ...a); });
  await p.goto(URL); await p.waitForTimeout(1500);

  assert(await p.evaluate(() => state.acs === 'a85f3a50-64f4-459a-9661-d8697a106b8a'), 'ACS id auto-detected from the Teams Phone System provider');
  assert(await p.evaluate(() => state.appId === 'e404520c-564a-4e7c-9f33-ad12acc64a90'), 'Dynamics App ID auto-detected');
  assert(await p.evaluate(() => state.pstn === 'Auto'), 'number type defaults to Auto-detect');

  await p.locator('input[data-k=phone]').first().fill('+12122108677');
  const script = await p.evaluate(() => buildPs());
  assert(/Sync-CsOnlineApplicationInstance[^\n]*-AcsResourceId \$AcsId/.test(script), 'script binds the ACS resource (-AcsResourceId)');
  assert(!/Out-Null\s*\n\s*Sync-Cs/.test(script), 'binding errors are not swallowed');
  assert(/TeamsResourceAccount\.Read\.All/.test(script) && /'TeamsResourceAccount\.Read'/.test(script), 'Entra app requests both TeamsResourceAccount permissions');
  assert(/\[switch\]\$CheckOnly/.test(script) && /\[switch\]\$ListNumbers/.test(script), 'script offers -CheckOnly and -ListNumbers');
  assert(/IsoCountryCode/.test(script) && /\$PstnType\s+= "Auto"/.test(script), 'number type and country come from Teams');
  assert(/ContainsKey\('AcsResourceId'\)/.test(script), 'script detects a MicrosoftTeams module without -AcsResourceId');
  assert(!/__[A-Z_]+__/.test(script), 'no unreplaced template placeholders');

  // Duplicate resource account across two rows is rejected.
  const dup = await p.evaluate(() => { state.lines.push({ display: 'Second', upn: state.lines[0].upn, phone: '+12122108678' }); const ok = validateAll(false); state.lines.pop(); return ok; });
  assert(dup === false, 'duplicate resource account across rows is rejected');

  const f = path.join(os.tmpdir(), 'wizard-gen.ps1'); fs.writeFileSync(f, script);
  if (!shell) console.log('skip PowerShell checks (no pwsh/powershell on PATH)');
  else {
    assert(ps(`$e=$null;$t=$null;[void][Management.Automation.Language.Parser]::ParseFile('${f}',[ref]$t,[ref]$e);$e.Count`) === '0', 'generated PowerShell parses without errors');
    const cb = path.join(os.tmpdir(), 'wizard-country.ps1');
    fs.writeFileSync(cb, await p.evaluate(() => COUNTRY_BLOCK));
    const got = ps(`. '${cb}'; (@('+14165550123','+12125550123','+12425550123','+525512345678','+77011234567','+79161234567','+442071234567') | ForEach-Object { Get-CountryCodeFromE164 $_ }) -join ','`);
    assert(got === 'CA,US,BS,MX,KZ,RU,GB', `country fallback (Canada, US, Bahamas, Mexico, Kazakhstan, Russia, UK): ${got}`);
    if (process.env.LINT) {
      const n = ps(`Import-Module PSScriptAnalyzer; @(Invoke-ScriptAnalyzer -Path '${f}' -Severity Error).Count`);
      assert(n === '0', `PSScriptAnalyzer reports no errors (${n})`);
    }
  }

  // Hands-free flow: downloading the script starts auto-sync; no Sync click needed.
  const [dl] = await Promise.all([p.waitForEvent('download'), p.getByRole('button', { name: /Download \.ps1/ }).click()]);
  const bytes = fs.readFileSync(await dl.path());
  assert(bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF, 'downloaded .ps1 has a UTF-8 BOM (Windows PowerShell 5.1 safe)');
  await p.waitForFunction(() => /imported/.test(document.querySelector('#resTable').innerText), null, { timeout: 45000 }).catch(() => {});
  assert(/imported/.test(await p.locator('#resTable').innerText()), 'auto-sync imports the number without clicking Sync (number stored as "+1 212-210-8677")');
  await p.waitForFunction(() => /Main voice workstream/.test(document.querySelector('#resTable').innerText), null, { timeout: 45000 }).catch(() => {});
  assert(/attached/.test(await p.locator('#resTable').innerText()) && /Main voice workstream, Outbound/.test(await p.locator('#resTable').innerText()), 'workstream attachment detected on its own, listing every workstream the number is on');
  assert(await p.evaluate(() => document.querySelectorAll('.stp.done').length === 4), 'all four steps marked done');
  assert(errs.length === 0, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
  await b.close();
})().catch(e => { console.error(e); process.exitCode = 1; });
