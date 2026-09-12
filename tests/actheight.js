const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = fs.readFileSync(process.argv[2] + '/crmshot.js', 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await (await b.newContext({ viewport: { width: 1280, height: 900 } })).newPage();
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/?s=clients', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(700);
  await p.locator('#activityOpen').click(); await p.waitForTimeout(500);
  const hs = [];
  for (const t of ['all', 'clients', 'team', 'review', 'campaigns', 'links']) {
    await p.locator('.acttab[data-af="' + t + '"]').click(); await p.waitForTimeout(250);
    const h = await p.locator('#activitySheet .sheet-card').evaluate(el => Math.round(el.getBoundingClientRect().height));
    const n = await p.locator('#activityList .act').count();
    hs.push(t + '=' + h + 'px/' + n + ' rows');
  }
  console.log(hs.join('  '));
  await p.screenshot({ path: process.argv[2] + '/act-1280.png' });
  await b.close();
})();
