const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Promote Newly Launch Project',
    slots:4, state:'production', deliverable:'video', push_format:'site_visit',
    access_token:'CPROD', invoice_no:'AINV2026114', invoice_url:'https://mycdn.adspace.me/content/c1/inv.pdf' });
  // one waiting on the client, one live with numbers, one still filming, one on offer
  D.campaign_options.push({ id:'o1', campaign_id:'cmp1', creator_id:'k1', rate:360,
    platforms:'RedNote, Instagram', state:'reviewing', revision_round:1,
    draft_url:'https://drive.google.com/drive/folders/abc', visit_date:'2026-10-14',
    visit_time:'2pm', position:0 });
  D.campaign_options.push({ id:'o2', campaign_id:'cmp1', creator_id:'k2', rate:360,
    platforms:'RedNote', state:'posted', revision_round:1, position:1 });
  D.option_posts.push({ id:'pp1', option_id:'o2', platform:'RedNote',
    post_url:'https://xiaohongshu.com/explore/xyz', published_at:'2026-10-20',
    window_days:7, impressions:48000, engagements:3200, views:41000 });
  // shoot booked for the 9th, listed third: it must come out first
  D.campaign_options.push({ id:'o3', campaign_id:'cmp1', creator_id:'k3', rate:500,
    platforms:'RedNote', state:'pending_visit', visit_date:'2026-10-09',
    visit_time:'10am', position:2 });
  D.creators.push({ id:'k7', name:'泡芙小姐姐', followers:5100, client_rate:360 });
  D.campaign_options.push({ id:'o4', campaign_id:'cmp1', creator_id:'k7', rate:360,
    platforms:'RedNote', state:'option', position:3 });
  window.__persist && window.__persist();
})();`;


(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1000, height: 1100 } });
  const p = await ctx.newPage();
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/creators/?k=CPROD', { waitUntil: 'networkidle' });
  await p.waitForTimeout(900);
  await p.screenshot({ path: process.argv[2] + "/c-full-1000.png", fullPage: true }); await p.locator("#amountToggle").click(); await p.waitForTimeout(200); await p.screenshot({ path: process.argv[2] + "/c-full-open.png", fullPage: true }); await p.setViewportSize({ width: 390, height: 844 }); await p.waitForTimeout(300); await p.screenshot({ path: process.argv[2] + "/c-full-390.png", fullPage: true });
  console.log('brand:', JSON.stringify(await p.locator('.brand').innerText()));
  
  await b.close();
  console.log('shot written');
})();
