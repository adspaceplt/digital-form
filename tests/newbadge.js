const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Rolling options', slots:10,
    state:'open', deliverable:'video', access_token:'ROLL' });
  D.creators.slice(0,2).forEach(function(cr,i){
    D.campaign_options.push({ id:'o'+(i+1), campaign_id:'cmp1', creator_id:cr.id,
      rate:cr.client_rate, platforms:'RedNote', state:'option', position:i }); });
  window.__persist && window.__persist();
})();`;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1100, height: 900 } });
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  await p.goto('http://127.0.0.1:8899/creators/?k=ROLL', { waitUntil: 'networkidle' });
  await p.waitForTimeout(600);
  console.log('first visit cards:', await p.locator('.crow').count(),
              'NEW badges:', await p.locator('.tag-new').count());

  // sourcing continues: two more options arrive
  await p.evaluate(() => {
    var D = window.__DB;
    D.campaign_options.push({ id:'o3', campaign_id:'cmp1', creator_id:'k3', rate:500,
      platforms:'RedNote', state:'option', position:2 });
    D.creators.push({ id:'k9', name:'是甜甜啊', followers:4400, client_rate:360 });
    D.campaign_options.push({ id:'o4', campaign_id:'cmp1', creator_id:'k9', rate:360,
      platforms:'RedNote', state:'option', position:3 });
    window.__persist();
  });
  await p.reload({ waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  console.log('after more sourcing:', await p.locator('.crow').count(), 'cards,',
              await p.locator('.tag-new').count(), 'marked NEW');
  const names = await p.locator('.crow:has(.tag-new) .crow-name b').allInnerTexts();
  console.log('marked:', names.join(', '));
  await p.screenshot({ path: process.argv[2] + '/newbadge.png' });

  // third visit: nothing added, badges should clear
  await p.reload({ waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  console.log('third visit NEW badges:', await p.locator('.tag-new').count());
  await b.close();
  console.log('errors:', errs.length ? errs.join('|') : 'none');
})();
