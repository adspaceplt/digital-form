const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const errs = [];
const say = s => console.log(s);

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
  const ctx = await b.newContext({ viewport: { width: 1100, height: 1100 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('console', m => { if (m.type() === 'error' && !/404|Failed to load resource|TUNNEL/i.test(m.text())) errs.push('CONSOLE ' + m.text()); });
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  await p.goto('http://127.0.0.1:8899/creators/?k=CPROD', { waitUntil: 'networkidle' });
  await p.waitForTimeout(700);

  say('sections: "' + await p.locator('#bookingHead').innerText() + '" / "' + await p.locator('#chooseHead').innerText() + '"');
  say('bookings: ' + await p.locator('.booking').count() + '  still choosable: ' + await p.locator('.crow').count());
  say('chips: ' + (await p.locator('.chip-state').allInnerTexts()).join(' | '));
  say('highlighted (theirs to act on): ' + await p.locator('.booking:has(.booking-cta)').count() +
      ' -> ' + await p.locator('.booking:has(.booking-cta) .chip-state').innerText());
  say('order (soonest shoot first): ' + (await p.locator('.booking .booking-head b').allInnerTexts()).join(' > '));
  say('first card facts: ' + (await p.locator('.booking').first().locator('.booking-facts').innerText()).replace(/\n/g, ' | '));
  say('progress: ' + await p.locator('#progCount').innerText() + ' / ' + await p.locator('#progSay').innerText());
  say('live post link: ' + await p.locator('.results-link').count());
  say('results shown: ' + (await p.locator('.results').innerText()).replace(/\n/g, ' | '));
  say('amount folded by default: ' + await p.locator('#bookedTotals').isHidden() +
      ' · toggle says "' + await p.locator('#amountToggle').innerText() + '"');
  await p.locator('#amountToggle').click(); await p.waitForTimeout(250);
  say('booked totals once opened: ' + (await p.locator('#bookedTotals').innerText()).replace(/\n/g, ' | '));
  await p.locator('#amountToggle').click(); await p.waitForTimeout(200);
  say('folds shut again: ' + await p.locator('#bookedTotals').isHidden());
  say('invoice link: visible=' + await p.locator('#amountPdf').isVisible() + ' text="' + await p.locator('#amountPdf').innerText() + '" href=' + await p.locator('#amountPdf').getAttribute('href'));

  say('=== draft review ===');
  say('reviewing row is highlighted wherever it sits: ' + await p.locator('.booking:has(.booking-cta)').count());
  await p.locator('.booking-cta').click();
  await p.waitForTimeout(400);
  say('sheet: ' + await p.locator('#draftSheet').isVisible() + ' heading=' + await p.locator('#draftHeading').innerText());
  say('drive link: ' + await p.locator('#draftOpen').getAttribute('href'));
  await p.locator('#draftChanges').click();
  await p.waitForTimeout(250);
  say('changes without a note: ' + await p.locator('#draftMsg').innerText());
  await p.fill('#draftNote', 'Please cut the intro and show the facade earlier.');
  await p.fill('#draftBy', 'Wei Ling');
  await p.locator('#draftChanges').click();
  await p.waitForTimeout(900);
  say('state after changes: ' + await p.evaluate(() => window.__DB.campaign_options[0].state));
  say('round now: ' + await p.evaluate(() => window.__DB.campaign_options[0].revision_round));
  say('review logged: ' + await p.evaluate(() => JSON.stringify(window.__DB.option_reviews[0])));
  say('chip now: ' + (await p.locator('.chip-state').allInnerTexts()).join(' | '));

  say('=== approve path ===');
  await p.evaluate(() => { window.__DB.campaign_options[0].state = 'reviewing'; window.__persist(); });
  await p.reload({ waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  say('reviewing card facts: ' + (await p.locator('.booking:has(.booking-cta) .booking-facts').innerText()).replace(/\n/g, ' | '));
  await p.locator('.booking-cta').click();
  await p.waitForTimeout(350);
  say('last-round warning: ' + await p.locator('#draftBlurb').innerText());
  await p.locator('#draftApprove').click();
  await p.waitForTimeout(900);
  say('state after approve: ' + await p.evaluate(() => window.__DB.campaign_options[0].state));
  say('chips now: ' + (await p.locator('.chip-state').allInnerTexts()).join(' | '));

  await p.screenshot({ path: process.argv[2] + '/cprod.png', fullPage: true });

  say('=== 中文 ===');
  await p.locator('#langToggle').click();
  await p.waitForTimeout(400);
  say('chips: ' + (await p.locator('.chip-state').allInnerTexts()).join(' | '));
  say('head: ' + await p.locator('#bookingHead').innerText());

  await p.setViewportSize({ width: 390, height: 900 });
  await p.waitForTimeout(300);
  const d = await p.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  say('390 overflow: ' + (d.sw > d.cw ? 'YES ' + d.sw + '>' + d.cw : 'none'));

  await ctx.close(); await b.close();
  say('=== errors ==='); say(errs.length ? errs.join('\n') : 'none');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
