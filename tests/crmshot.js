const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = `(function(){ var D = window.__DB; if (D.clients.length > 2) return;
  ['Star Living','HKL Lim Motorsport','Dale & Cecil','Niro Granite','The Mill International'].forEach(function(n,i){
    D.clients.push({ id:'cs'+i, name:n, stage:['active','proposal','lead','active','past'][i],
      market: i===2 ? 'SG':'MY', owner:['Qiao Rou','Aisyah','Qiao Rou','Aisyah','Qiao Rou'][i],
      industry:['Retail','Automotive','Lifestyle','Retail','Property'][i], sst_applies:true,
      access_token:'t'+i });
  });
  D.client_contacts.push({ id:'k1', client_id:'c1', name:'Mr Lim', role:'Marketing Manager',
    phone:'012-345 6789', whatsapp:'60123456789', email:'lim@lamancitra.com', lang:'en', is_primary:true });
  D.client_contacts.push({ id:'k2', client_id:'c1', name:'Ms Tan', role:'Admin',
    phone:'017-222 8888', email:'tan@lamancitra.com', lang:'zh', is_primary:false });
  D.campaigns.push({ id:'cq', client_id:'c1', title:'Laman Citra phase 2', slots:10,
    state:'production', deliverable:'video', push_format:'site_visit', access_token:'Q1' });
  window.__persist && window.__persist(); })();`;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1440, height: 1000 } });
  const p = await ctx.newPage();
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/?s=clients', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(900);
  await p.screenshot({ path: process.argv[2] + '/d-crm-list.png' });
  await p.locator('.crm-row').first().click(); await p.waitForTimeout(800);
  await p.screenshot({ path: process.argv[2] + '/d-crm-client.png', fullPage: true });
  await p.locator('#crmBillToggle').click(); await p.waitForTimeout(300);
  await p.locator('#crmBillBody').screenshot({ path: process.argv[2] + '/d-billing.png' });
  await p.locator('#crmAddContact').click(); await p.waitForTimeout(300);
  await p.locator('#crmContactBox').screenshot({ path: process.argv[2] + '/d-contactform.png' });
  // the two admin forms from the screenshots
  await p.goto('http://127.0.0.1:8899/admin/?s=campaigns&campaign=cq', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(900);
  await p.locator('#invoiceToggle').click(); await p.waitForTimeout(300);
  await p.locator('#invoiceBody').screenshot({ path: process.argv[2] + '/d-invoice.png' });
  await p.locator('#campEdit').click(); await p.waitForTimeout(400);
  await p.locator('#addCampBox').screenshot({ path: process.argv[2] + '/d-campform.png' });
  await b.close();
  console.log('desktop shots written');
})();
