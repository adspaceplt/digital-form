const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const errs = [];
const say = s => console.log(s);

// The client page gets its own JS context, so seed the same campaign into it.
const SEED = `
(function(){
  var D = window.__DB;
  if (D.campaigns.length) return;   // already seeded and restored
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Promote Newly Launch Project',
    title_zh:'新项目推广', slots:10, deadline:'2026-09-22', state:'open', deliverable:'video',
    brief:'One video per creator, posted on the placements shown.',
    brief_zh:'每位博主一条视频，按所示平台发布。', access_token:'TESTTOKEN' });
  var names = ['香香的爆米花 🍿','恩比','小熊爱睡觉'];
  D.creators.forEach(function(cr,i){
    D.campaign_options.push({ id:'o'+(i+1), campaign_id:'cmp1', creator_id:cr.id,
      rate:cr.client_rate, platforms:'RedNote, Instagram', state:'option',
      is_replacement: i===2, position:i });
  });
  // a fourth, to test the slot cap and NEW badge
  D.creators.push({ id:'k4', name:'泡芙小姐姐', followers:5100, client_rate:360 });
  D.creator_profiles.push({ id:'p9', creator_id:'k4', platform:'xhs',
    url:'https://www.xiaohongshu.com/user/profile/5b151d89e8ac2b76c0776e85', handle:'5b151d89e8ac2b76c0776e85' });
  D.campaign_options.push({ id:'o4', campaign_id:'cmp1', creator_id:'k4', rate:360,
    platforms:'RedNote', state:'option', is_replacement:false, position:3 });

  // a second campaign with only two slots, to exercise the cap
  D.campaigns.push({ id:'cmp2', client_id:'c1', title:'Small push', slots:2,
    state:'open', deliverable:'video', access_token:'CAPTOKEN' });
  D.creators.forEach(function(cr,i){
    D.campaign_options.push({ id:'q'+(i+1), campaign_id:'cmp2', creator_id:cr.id,
      rate:cr.client_rate, platforms:'RedNote', state:'option', position:i });
  });
  window.__persist && window.__persist();
})();
`;

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1280, height: 1000 } });
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('console', m => { if (m.type() === 'error' && !/favicon|404|Failed to load resource/i.test(m.text())) errs.push('CONSOLE ' + m.text()); });
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  await p.goto('http://127.0.0.1:8899/creators/?k=TESTTOKEN', { waitUntil: 'networkidle' });
  await p.waitForTimeout(600);

  say('title: ' + await p.title());
  say('client: ' + await p.locator('#clientName').innerText());
  say('campaign: ' + await p.locator('#campTitle').innerText());
  say('due: ' + (await p.locator('#engageFacts').innerText()).replace(/\n/g, ' '));
  say('cards: ' + await p.locator('.crow').count());
  say('progress: "' + await p.locator('#progLabel').innerText() + '" / "' + await p.locator('#progCount').innerText() + '" / "' + await p.locator('#progSay').innerText() + '"');
  say('replacement badges: ' + await p.locator('.tag-rep').count());
  say('profile buttons on row 1: ' + (await p.locator('.crow').first().locator('.plink').allInnerTexts()).join(' | '));
  say('due pill: ' + (await p.locator('#engageFacts').innerText()).replace(/\n/g, ' '));
  say('confirm bar hidden at 0: ' + await p.locator('#confirmBar').isHidden());

  // select three
  for (let i = 0; i < 3; i++) { await p.locator('.crow-tick').nth(i).click(); await p.waitForTimeout(150); }
  say('after 3: ' + await p.locator('#progCount').innerText() + ' / ' + await p.locator('#progSay').innerText());
  say('bar: ' + await p.locator('#confirmSummary').innerText());
  const w = await p.locator('#progFill').evaluate(e => e.style.width);
  say('bar width: ' + w);
  await p.waitForTimeout(800);
  say('saves fired: ' + await p.evaluate(() => window.__saves || 0));
  say('server states: ' + await p.evaluate(() => window.__DB.campaign_options
        .filter(o => o.campaign_id === 'cmp1').map(o => o.state).join(',')));

  // backup
  await p.locator('.crow-backup').nth(3).click();
  await p.waitForTimeout(250);
  say('backup card class: ' + await p.locator('.crow').nth(3).getAttribute('class'));

  // language
  await p.locator('#langToggle').click();
  await p.waitForTimeout(300);
  say('--- zh ---');
  say('kicker: ' + await p.locator('#kicker').innerText());
  say('campaign: ' + await p.locator('#campTitle').innerText());
  say('progress: ' + await p.locator('#progCount').innerText() + ' / ' + await p.locator('#progSay').innerText());
  say('due: ' + (await p.locator('#engageFacts').innerText()).replace(/\n/g, ' '));
  await p.locator('#langToggle').click();
  await p.waitForTimeout(300);

  // ---- cap, on a campaign with two slots ----
  await p.goto('http://127.0.0.1:8899/creators/?k=CAPTOKEN', { waitUntil: 'networkidle' });
  await p.waitForTimeout(600);
  say('--- cap test (2 slots, 4 options: two spare, so two backups wanted) ---');
  say('progress: ' + await p.locator('#progCount').innerText() + ' / ' + await p.locator('#progSay').innerText());
  await p.locator('.crow-tick').nth(0).click(); await p.waitForTimeout(150);
  await p.locator('.crow-tick').nth(1).click(); await p.waitForTimeout(250);
  say('after 2: ' + await p.locator('#progCount').innerText() + ' / ' + await p.locator('#progSay').innerText());
  say('done class: ' + await p.locator('#progressCard').getAttribute('class'));
  const pick3 = p.locator('.crow-tick').nth(2);
  say('3rd button: "' + await pick3.innerText() + '" disabled=' + await pick3.isDisabled());
  // two slots filled, one spare creator: exactly one backup is wanted
  say('backup line: ' + await p.locator('#progBackup').innerText());
  say('confirm gated: ' + await p.locator('#confirmBtn').isDisabled() + ' -> ' + (await p.locator('#confirmSummary').innerText()).replace(/\n/g, ' | '));
  await p.locator('.crow-backup').nth(2).click();
  await p.waitForTimeout(300);
  say('after 1 backup: ' + await p.locator('#progBackup').innerText() + ' | confirm enabled=' + !(await p.locator('#confirmBtn').isDisabled()));
  await p.locator('.crow-backup').nth(3).click();
  await p.waitForTimeout(300);
  say('after 2 backups: ' + await p.locator('#progBackup').innerText() + ' | confirm enabled=' + !(await p.locator('#confirmBtn').isDisabled()));
  await p.waitForTimeout(800);

  // returning to the link should show what was left
  await p.reload({ waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  say('after revisit: ' + await p.locator('#progCount').innerText() +
      ' selected-cards=' + await p.locator('.crow.is-on').count());
  say('NEW badges on revisit: ' + await p.locator('.tag-new').count());

  await p.screenshot({ path: process.argv[2] + '/client-1280.png', fullPage: true });

  // confirm
  await p.locator('#confirmBtn').click();
  await p.waitForTimeout(300);
  say('sheet open: ' + await p.locator('#confirmSheet').isVisible() + ' rows=' + await p.locator('#confirmList .act').count());
  say('sheet totals: ' + (await p.locator('#confirmTotals').innerText()).replace(/\n/g, ' | '));
  await p.locator('#confirmGo').click();
  await p.waitForTimeout(250);
  say('no name: ' + await p.locator('#confirmMsg').innerText());
  await p.fill('#confirmName', 'Wei Ling');
  await p.locator('#confirmGo').click();
  await p.waitForTimeout(400);
  say('confirmed record: ' + await p.evaluate(() => JSON.stringify(window.__DB.campaign_confirmations)));
  say('after confirm: ' + await p.locator('#stateText').innerText());

  // phone
  await p.setViewportSize({ width: 390, height: 800 });
  await p.goto('http://127.0.0.1:8899/creators/?k=TESTTOKEN', { waitUntil: 'networkidle' });
  await p.waitForTimeout(600);
  const d = await p.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  say('390 overflow: ' + (d.sw > d.cw ? 'YES ' + d.sw + '>' + d.cw : 'none'));
  await p.screenshot({ path: process.argv[2] + '/client-390.png', fullPage: true });

  await b.close();
  say('--- errors ---');
  say(errs.length ? errs.join('\n') : 'none');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
