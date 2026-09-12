const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Promote New Launch Project', invoice_no:'AINV2026114',
    slots:2, deadline:'2026-09-22', owner:'Qiao Rou', push_format:'site_visit', deliverable:'video',
    state:'open', access_token:'HDR', created_at:'2026-09-11T03:00:00Z' });
  D.campaign_options.push({ id:'o1', campaign_id:'cmp1', creator_id:'k1', rate:8640, platforms:'RedNote', state:'shortlisted', position:0 });
  D.campaign_options.push({ id:'o2', campaign_id:'cmp1', creator_id:'k1', rate:8640, platforms:'RedNote', state:'shortlisted', position:1 });
  window.__persist && window.__persist();
})();`;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(400);
  await p.locator('#navToggle').click(); await p.waitForTimeout(400); await p.locator('.navitem[data-section="campaigns"]').click(); await p.waitForTimeout(400);
  await p.locator('#campCards .bigcard').first().click(); await p.waitForTimeout(700);
  await p.locator('#campWork > section.panel').first().screenshot({ path: process.argv[2] + '/head-390.png' });
  await b.close(); console.log('shots written'); return;
  await p.locator('#addOptionBox').screenshot({ path: process.argv[2] + '/addbox-390.png' });
  await b.close();
  console.log('shots written');
})();
