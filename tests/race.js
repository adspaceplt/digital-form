// The real Supabase client can answer getSession from local storage before
// campaigns.js has even run. The section must still land on the tab the
// address names.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
let STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
STUB = STUB.replace('var session = null', 'var session = window.__EARLY ? { user: { email: window.__EARLY } } : null');
if (!/window\.__EARLY/.test(STUB)) throw new Error('stub patch missed');
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.some(function(c){return c.id==='cmpX';})) return;
  D.campaigns.push({ id:'cmpX', client_id:'c1', title:'Existing campaign', slots:5, state:'draft',
    deliverable:'video', push_format:'site_visit', access_token:'STX' });
  window.__persist && window.__persist(); })();`;
const errs = []; let bad = 0;
const check = (label, ok) => { console.log((ok ? 'ok   ' : 'FAIL ') + label); if (!ok) bad++; };
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1200, height: 800 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.addInitScript(() => { window.__EARLY = 'adspacestudios@gmail.com'; });
  const where = async () => (await p.locator('#sectionTitle').innerText()) + ' @ ' + new URL(p.url()).search;

  await p.goto('http://127.0.0.1:8899/admin/?s=campaigns&tab=roster', { waitUntil: 'networkidle' }); await p.waitForTimeout(800);
  console.log('roster: ' + await where());
  check('roster tab survives an early session', await p.locator('#rosterView').isVisible() && /tab=roster/.test(p.url()));

  await p.goto('http://127.0.0.1:8899/admin/?s=campaigns&campaign=cmpX', { waitUntil: 'networkidle' }); await p.waitForTimeout(800);
  console.log('campaign: ' + await where());
  check('open campaign survives an early session', await p.locator('#campWork').isVisible() && /campaign=cmpX/.test(p.url()));

  await p.goto('http://127.0.0.1:8899/admin/?s=links', { waitUntil: 'networkidle' }); await p.waitForTimeout(800);
  console.log('links: ' + await where());
  check('links survives an early session', await p.locator('#sectionLinks').isVisible());

  await p.goto('http://127.0.0.1:8899/admin/?s=campaigns', { waitUntil: 'networkidle' }); await p.waitForTimeout(800);
  check('campaign list survives an early session', await p.locator('#campListView').isVisible());

  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  if (errs.length) bad++;
  await b.close();
  console.log(bad ? 'race: PROBLEM' : 'race: ok');
})();
