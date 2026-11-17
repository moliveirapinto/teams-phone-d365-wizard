// Minimal mock of the Dataverse endpoints the wizard reads, plus a static file server.
// Usage: node tests/mock-d365-server.js [port]
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'webresource');
const port = Number(process.argv[2] || 8765);
let syncCalls = 0;
const send = (res, body, status = 200) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(body)); };

http.createServer((req, res) => {
  const u = decodeURIComponent(req.url);
  if (u.startsWith('/api/data/')) {
    if (u.includes('WhoAmI')) return send(res, { UserId: '11111111-1111-1111-1111-111111111111' });
    if (u.includes('systemusers(')) return send(res, { internalemailaddress: 'admin@contoso.onmicrosoft.com', fullname: 'Test Admin' });
    if (u.includes('CCaaS_SynchronizePhoneNumbers')) { syncCalls++; return send(res, { TotalTeamsNumbers: syncCalls >= 2 ? 1 : null }); }
    if (u.includes('msdyn_occommunicationprovidersettingentries')) return send(res, { value: [{ msdyn_value: 'e404520c-564a-4e7c-9f33-ad12acc64a90', _msdyn_communicationprovidersettingentid_value: 'f12273ec-bcf3-4078-aed5-36aad92fb7ea' }] });
    if (u.includes('msdyn_occommunicationprovidersettings')) return send(res, { value: [{ msdyn_occommunicationprovidersettingid: 'f12273ec-bcf3-4078-aed5-36aad92fb7ea', msdyn_occommunicationproviderimmutableid: 'a85f3a50-64f4-459a-9661-d8697a106b8a', msdyn_name: 'test-ops-acs' }] });
    if (u.includes('msdyn_ocphonenumbers')) return send(res, { value: syncCalls >= 2 ? [{ msdyn_ocphonenumberid: 'p1', msdyn_phonenumber: '+12122108677', msdyn_teamsresourceaccount: 'ra1' }] : [] });
    if (u.includes('msdyn_ocvoicechannelsettings')) return send(res, { value: [] });
    if (u.includes('appmodules')) return send(res, { value: [{ uniquename: 'msdyn_CSAdminCenter', name: 'Customer Service admin center' }] });
    return send(res, { value: [] });
  }
  const f = path.join(root, u === '/' ? 'mau_TeamsPhoneSetup.html' : u.slice(1).split('?')[0]);
  if (f.startsWith(root) && fs.existsSync(f)) { res.writeHead(200, { 'Content-Type': f.endsWith('.png') ? 'image/png' : 'text/html' }); return res.end(fs.readFileSync(f)); }
  res.writeHead(404); res.end();
}).listen(port, () => console.log(`mock D365 on http://127.0.0.1:${port}`));
