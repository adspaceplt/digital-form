const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const errs = [];
const say = s => console.log(s);

const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Promote Newly Launch Project',
    slots:4, state:'open', deliverable:'video', push_format:'site_visit',
    access_token:'PROD', deadline:'2026-09-30' });
  D.creators.forEach(function(cr,i){
    D.campaign_options.push({ id:'o'+(i+1), campaign_id:'cmp1', creator_id:cr.id,
      rate:cr.client_rate, platforms:'RedNote, Instagram',
      state: i < 2 ? 'shortlisted' : 'option', revision_round:0, position:i }); });
  window.__persist && window.__persist();
})();`;

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 1000 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('console', m => { if (m.type() === 'error' && !/404|Failed to load resource|TUNNEL/i.test(m.text())) errs.push('CONSOLE ' + m.text()); });
  p.on('dialog', d => d.accept('scheduling clash'));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(400);
  await p.locator('.navitem[data-section="campaigns"]').click();
  await p.waitForTimeout(500);
  await p.locator('#campCards .bigcard').first().click();
  await p.waitForTimeout(600);

  say('=== lock ===');
  say('lock button: "' + await p.locator('#campLock').innerText() + '" visible=' + await p.locator('#campLock').isVisible());
  say('production hidden before lock: ' + await p.locator('#creatorList').isHidden());

  await p.locator('#campLock').click();
  await p.waitForTimeout(300);
  say('lock sheet rows: ' + await p.locator('#lockList .act').count());
  say('recorded by the signed-in person: ' + await p.locator('#lockBy').innerText());
  await p.fill('#lockPerson', 'Wei Ling');
  await p.selectOption('#lockSource', 'whatsapp');
  await p.locator('#lockGo').click();
  await p.waitForTimeout(800);

  say('campaign state: ' + await p.locator('#campState').innerText());
  say('confirmation record: ' + await p.evaluate(() => JSON.stringify(window.__DB.campaign_confirmations[0])));
  say('option states: ' + await p.evaluate(() => window.__DB.campaign_options.map(o => o.state).join(',')));
  say('production visible: ' + await p.locator('#creatorList').isVisible() + ' rows=' + await p.locator('.kcard').count());

  say('=== bulk logistics ===');
  await p.locator('#bulkToggle').click();
  await p.fill('#bulkDate', '2026-10-14');
  await p.fill('#bulkTime', '2pm');
  await p.locator('#bulkApply').click();
  await p.waitForTimeout(700);
  say('bulk msg: ' + await p.locator('#bulkMsg').innerText());
  // Production cards fold to one line; open the first to work on it.
  say('folded by default: ' + await p.locator('.kcard').first().locator('[data-body]').isHidden());
  say('folded summary: ' + await p.locator('.kcard').first().locator('.kcard-sum').innerText());
  await p.locator('.kcard').first().locator('.kfold').click(); await p.waitForTimeout(200);
  say('row summary: ' + await p.locator('.kstep-sum').first().innerText());

  // hand-set one card, then confirm "apply to blanks" leaves it alone
  await p.locator('.kcard').first().locator('[data-f="visit_time"]').fill('4pm');
  await p.locator('.kcard').first().locator('[data-a="save"]').click();
  await p.waitForTimeout(600);
  await p.fill('#bulkTime', '9am');
  await p.locator('#bulkApply').click();
  await p.waitForTimeout(700);
  say('hand-set row kept: ' + await p.evaluate(() =>
    window.__DB.campaign_options.filter(o => o.state !== 'option')[0].visit_time));
  say('no location or PIC fields: ' + (await p.locator('[data-f="visit_location"], [data-f="visit_pic"], #bulkLoc, #bulkPic').count() === 0));
  say('bulk msg 2: ' + await p.locator('#bulkMsg').innerText());

  say('=== pipeline ===');
  say('open card stays open across saves: ' +
      await p.locator('.kcard').first().locator('[data-f="visit_date"]').isVisible());
  say('draft step hidden before filming: ' + (await p.locator('.kcard').first().locator('[data-f="draft_url"]').count() === 0));
  const steps = [];
  for (let i = 0; i < 6; i++) {
    const body = p.locator('.kcard').first();
    const adv = body.locator('[data-a="advance"]');
    if (await adv.count() === 0) break;
    const label = (await adv.innerText()).trim();
    // Each step is gated on what it needs; prove the gate, then satisfy it.
    if (label === 'Reviewing' && i === 2) {
      await adv.click(); await p.waitForTimeout(300);
      say('reviewing refused without a draft: ' + await body.locator('[data-msg]').innerText());
      await body.locator('[data-f="draft_url"]').fill('drive.google.com/file/d/abc');
    }
    if (label === 'Scheduled') {
      await adv.click(); await p.waitForTimeout(300);
      say('scheduled refused without a publish date: ' + await body.locator('[data-msg]').innerText());
      await body.locator('[data-f="planned_publish"]').fill(new Date().toISOString().slice(0, 10));
    }
    steps.push(label);
    await adv.click();
    await p.waitForTimeout(600);
  }
  say('advanced through: ' + steps.join(' → '));
  say('draft link saved with scheme: ' + await p.evaluate(() => window.__DB.campaign_options.filter(o => o.state !== 'option')[0].draft_url));
  say('final state: ' + await p.evaluate(() => window.__DB.campaign_options.filter(o => o.state !== 'option')[0].state));
  say('posts seeded: ' + await p.evaluate(() => JSON.stringify(window.__DB.option_posts.map(x => x.platform))));

  say('=== metrics ===');
  const row0 = p.locator('.kcard').first();
  say('post rows shown: ' + await row0.locator('.postrow').count());
  const pr = row0.locator('.postrow').first();
  await pr.locator('[data-p="post_url"]').fill('https://xiaohongshu.com/explore/abc123');
  await pr.locator('[data-p="published_at"]').fill('2026-10-20');
  await pr.locator('[data-p="impressions"]').fill('48000');
  await pr.locator('[data-p="engagements"]').fill('3200');
  await pr.locator('[data-p="views"]').fill('41000');
  await pr.locator('[data-p-save]').click();
  await p.waitForTimeout(700);
  say('default window: ' + await p.evaluate(() => window.__DB.option_posts[0].window_days));
  say('rollup visible: ' + await p.locator('#rollup').isVisible());
  say('rollup: ' + (await p.locator('#rollupTally').innerText()).replace(/\n/g, ' / '));

  say('=== everything reverses ===');
  const openBody = async () => p.locator('.kcard').first();
  let body = await openBody();
  say('rare outcomes hidden until asked: ' + await body.locator('.kmenu').isHidden());
  say('step back offers: ' + await body.locator('[data-a="back"]').innerText());
  await body.locator('[data-a="back"]').click();
  await p.waitForTimeout(700);
  say('state after one step back: ' + await p.evaluate(() => window.__DB.campaign_options.filter(o => o.state !== 'option')[0].state));
  say('metrics kept through the step back: ' + await p.evaluate(() => window.__DB.option_posts[0].impressions));

  body = await openBody();
  await body.locator('[data-a="menu"]').click();
  await p.waitForTimeout(250);
  say('menu opens with ' + await body.locator('.kmenu-item').count() + ' labelled choices: ' +
      (await body.locator('.kmenu-item b').allInnerTexts()).join(' / '));
  await body.locator('[data-a="withdraw"]').click();
  await p.waitForTimeout(800);
  say('withdrawn: ' + await p.evaluate(() => window.__DB.campaign_options.filter(o => o.state === 'withdrawn').length));
  const dead = p.locator('.kcard.is-off').first();
  say('ended row offers a way back: ' + await dead.locator('[data-a="reinstate"]').isVisible());
  await dead.locator('[data-a="reinstate"]').click();
  await p.waitForTimeout(800);
  say('after reinstating: ' + await p.evaluate(() => window.__DB.campaign_options.filter(o => o.state !== 'option').map(o => o.state).join(',')));

  body = await openBody();
  await body.locator('[data-a="menu"]').click();
  await p.waitForTimeout(250);
  await body.locator('[data-a="unbook"]').click();
  await p.waitForTimeout(800);
  say('sent back to the options: ' + await p.evaluate(() =>
    window.__DB.campaign_options.filter(o => o.state === 'option').length) + ' of 4 now selectable');

  say('campaign itself reopens: "' + await p.locator('#campPublish').innerText() + '"');
  await p.locator('#campPublish').click();
  await p.waitForTimeout(700);
  say('campaign state after reopening: ' + await p.locator('#campState').innerText());

  await p.screenshot({ path: process.argv[2] + '/prod.png', fullPage: false });
  await ctx.close();
  await b.close();
  say('=== errors ===');
  say(errs.length ? errs.join('\n') : 'none');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
