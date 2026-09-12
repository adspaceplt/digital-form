const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Mixed', slots:4, state:'production',
    deliverable:'video', push_format:'site_visit', access_token:'BAR' });
  D.campaign_options.push({ id:'o1', campaign_id:'cmp1', creator_id:'k1', rate:360,
    platforms:'RedNote', state:'posted', position:0 });
  D.campaign_options.push({ id:'o2', campaign_id:'cmp1', creator_id:'k2', rate:360,
    platforms:'RedNote', state:'pending_visit', position:1 });
  D.campaign_options.push({ id:'o3', campaign_id:'cmp1', creator_id:'k3', rate:500,
    platforms:'RedNote', state:'option', position:2 });
  window.__persist && window.__persist();
})();`;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1000, height: 900 } });
  const p = await ctx.newPage();
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/creators/?k=BAR', { waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  console.log('progress (booked count towards slots):', await p.locator('#progCount').innerText());
  console.log('confirm bar hidden with nothing new ticked:', await p.locator('#confirmBar').isHidden());
  await p.locator('.crow-tick').first().click();
  await p.waitForTimeout(300);
  console.log('after ticking one:', await p.locator('#progCount').innerText(),
              '| bar:', await p.locator('#confirmSummary').innerText());
  await p.locator('.crow-tick').first().click();
  await p.waitForTimeout(300);
  console.log('untick -> bar hidden again:', await p.locator('#confirmBar').isHidden());
  // when everything is booked there is nothing to choose
  await p.evaluate(() => { window.__DB.campaign_options[2].state = 'confirmed'; window.__persist(); });
  await p.reload({ waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  console.log('all booked -> progress card hidden:', await p.locator('#progressCard').isHidden(),
              '| cards:', await p.locator('.crow').count(),
              '| bookings:', await p.locator('.booking').count());
  await ctx.close(); await b.close();
})();
