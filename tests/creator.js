/*
 * The creator's own page: signing in with a code, seeing only their own
 * booking, handing work in, and being asked for payment details at the right
 * moment rather than the convenient one.
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');

/* Shared with tests/uxaudit.js, which walks this page as part of the sweep. */
const SEED = `
(function(){
  var D = window.__DB;
  if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmA', client_id:'c1', title:'Laman Citra Launch',
    title_zh:'新项目推广', state:'production', slots:4, push_format:'visit',
    access_token:'CMATOK',
    deliverable:'One video', brief:'One reel at the showroom.' + String.fromCharCode(10) + 'Golden hour if you can.' });
  D.campaigns.push({ id:'cmDraft', client_id:'c1', title:'Unannounced thing', state:'draft', slots:2 });
  /* A second live campaign for the same creator, so the work queue has more
     than one row to order and the walk sees it. */
  D.campaigns.push({ id:'cmB', client_id:'c1', title:'Raya Table Tents',
    title_zh:'开斋节桌卡', state:'production', slots:2, push_format:'seeding',
    access_token:'CMBTOK', deliverable:'One video', brief:'Unbox the tin on camera.' });
  D.campaign_options.push({ id:'oA', campaign_id:'cmA', creator_id:'k2', rate:380,
    platforms:'rednote, Instagram', state:'pending_draft', revision_round:0,
    visit_date:'2026-09-22', visit_time:'10am', visit_location:'Laman Citra showroom',
    visit_pic:'Aisyah', visit_pic_phone:'012-345 6789', planned_publish:'2026-09-28' });
  D.campaign_options.push({ id:'oB', campaign_id:'cmA', creator_id:'k1', rate:360,
    platforms:'rednote', state:'option' });
  D.campaign_options.push({ id:'oC', campaign_id:'cmA', creator_id:'k3', rate:500,
    platforms:'rednote', state:'scheduled', visit_date:'2026-08-01' });
  D.campaign_options.push({ id:'oD', campaign_id:'cmDraft', creator_id:'k2', rate:300,
    platforms:'rednote', state:'confirmed' });
  D.campaign_options.push({ id:'oE', campaign_id:'cmB', creator_id:'k2', rate:420,
    platforms:'rednote', state:'scheduled', visit_date:'2026-10-06', planned_publish:'2026-10-12' });
  D.campaign_deliverables.push({ id:'dA', option_id:'oC', url:'https://mycdn.adspace.me/x.jpg',
    name:'cover.jpg', kind:'image', bytes:12345, round:1 });
  window.__persist();
})();
`;
const SEED_BODY = new Function(SEED);
const errs = [];
let fails = 0;
const check = (what, ok, detail) => {
  console.log((ok ? 'ok   ' : 'FAIL ') + what + (detail ? '  ' + detail : ''));
  if (!ok) fails++;
};
const say = s => console.log(s);

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  /* The campaign record is a command centre with panes now, so a section's
     controls are in the pane that owns them. */
  const cpane = async (k) => {
    await p.locator('#campTabs .tab[data-pane="' + k + '"]').click();
    await p.waitForTimeout(250);
  };
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('console', m => { if (m.type() === 'error' && !/favicon|404|ERR_/i.test(m.text())) errs.push('CONSOLE ' + m.text()); });
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  // The signed PUT goes straight to storage and never through Supabase.
  let puts = [];
  await p.route('https://s3.test/**', r => { puts.push(r.request().url()); r.fulfill({ status: 200, body: '' }); });

  const seed = () => p.evaluate(SEED_BODY);

  // ---- The code is the whole sign-in -----------------------------------------
  await p.goto('http://127.0.0.1:8899/creator/', { waitUntil: 'networkidle' });
  await p.waitForTimeout(500);
  await seed();
  await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(500);

  check('with no code the page asks for one', await p.locator('#codeRow').isVisible() &&
    await p.locator('#app').isHidden());
  say('cover: "' + await p.locator('#stateTitle').innerText() + '" / "' +
    await p.locator('#stateText').innerText() + '"');

  await p.fill('#codeInput', 'ZZZZZZZZ');
  await p.locator('#codeGo').click(); await p.waitForTimeout(400);
  check('a code that is not ours is answered on the form, not by a blank page',
    await p.locator('#codeRow').isVisible() && (await p.locator('#stateMsg').innerText()).length > 0,
    await p.locator('#stateMsg').innerText());

  await p.fill('#codeInput', 'k2bbbbbb');           // typed in lower case, with no dash
  await p.locator('#codeGo').click(); await p.waitForTimeout(600);
  check('the right code opens the page', await p.locator('#app').isVisible());
  check('and it is their name on it', (await p.locator('#whoName').innerText()) === '恩比',
    await p.locator('#whoName').innerText());

  /* ---- The work queue ------------------------------------------------------
     Two live bookings, so the page is a queue and one card, not two cards
     stacked with two upload boxes. The one waiting on them opens by itself. */
  check('the queue lists both bookings', await p.locator('#workQueue .qrow').count() === 2,
    String(await p.locator('#workQueue .qrow').count()));
  check('the one waiting on them is first', (await p.locator('#workQueue .qrow').first().innerText()).includes('Laman Citra Launch'),
    await p.locator('#workQueue .qrow').first().innerText());
  check('and is marked as needing them', await p.locator('#workQueue .qrow .tone.is-warn').count() === 1);
  check('one card is open, not both', await p.locator('#workList .booking').count() === 1);
  check('and it is the one that needs them',
    (await p.locator('#workList .booking').innerText()).includes('Laman Citra Launch'));
  await p.locator('#workQueue .qrow').nth(1).click(); await p.waitForTimeout(400);
  check('picking another opens it in place',
    (await p.locator('#workList .booking').innerText()).includes('Raya Table Tents') &&
    await p.locator('#workList .booking').count() === 1);
  check('the booking travels in the address', p.url().indexOf('#b=') > -1, p.url());
  await p.goBack(); await p.waitForTimeout(400);
  check('Back returns to the booking before it',
    (await p.locator('#workList .booking').innerText()).includes('Laman Citra Launch'), p.url());

  // ---- Only their own booking, and only what a creator may see ---------------
  const cards = () => p.locator('#workList .booking');
  check('one booking, not the campaign', await cards().count() === 1, String(await cards().count()));
  const card = cards().first();
  const txt = await card.innerText();
  say('card: ' + txt.replace(/\n/g, ' | '));
  check('the brand and the campaign are named', txt.includes('Laman Citra Launch') && txt.includes('Laman Citra'));
  check('their own fee, not the client\'s amount', txt.includes('RM 380'), (txt.match(/RM [\d,.]+/g) || []).join(' '));
  check('the shoot, the place and who to ask for',
    txt.includes('22 Sept 2026') && txt.includes('showroom') && txt.includes('Aisyah'));
  check('the placements the fee covers', txt.includes('rednote · Instagram'));
  check('the brief', txt.includes('showroom') && txt.includes('Golden hour'));
  /* A campaign still being put together, and an offer nobody has confirmed,
     are both our business and not the creator's. */
  check('a draft campaign never reaches them', !txt.includes('Unannounced'));
  const all = await p.locator('#workList').innerText();
  check('nor does an offer they have not been confirmed on', !all.includes('Offered'));

  // ---- Handing in ------------------------------------------------------------
  check('the step they are on says what we are waiting for',
    txt.includes('submission is due'), txt.split('\n').find(l => /waiting|review/i.test(l)));
  check('and the hand-in is open', await card.locator('[data-a="submit"]').isVisible());

  // Nothing attached is refused, before anything is written.
  await card.locator('[data-a="submit"]').click(); await p.waitForTimeout(400);
  check('handing in nothing is refused', (await card.locator('[data-msg]').innerText()).length > 0,
    await card.locator('[data-msg]').innerText());
  check('and the step has not moved', await p.evaluate(() =>
    window.__DB.campaign_options.find(o => o.id === 'oA').state) === 'pending_draft');

  await card.locator('input[type=file]').setInputFiles([
    { name: 'reel-cut1.mp4', mimeType: 'video/mp4', buffer: Buffer.from('a video') },
    { name: 'cover.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('an image') }
  ]);
  await p.waitForTimeout(900);
  check('both files are attached and shown', await p.locator('.filecard').count() === 2,
    (await p.locator('.filecard').count()) + ' | ' + await card.locator('[data-msg]').innerText());
  check('each one went straight to storage', puts.length === 2, puts.join(' '));
  check('and into a key built from the booking, not from the browser',
    puts.every(u => u.includes('/creator/oA/')), puts.join(' '));
  check('and onto this booking, never another one', await p.evaluate(() =>
    window.__DB.campaign_deliverables.filter(d => d.option_id === 'oA').length === 2 &&
    !window.__DB.campaign_deliverables.some(d => d.option_id === 'oB')));

  /* ---- The failure that was invisible ---------------------------------------
     creator_add_file failed in production on an ambiguous column, and this page
     threw from inside a fulfilment handler whose sibling rejection handler
     cannot catch it. Nothing was said, the bar stood at 100%, and Submit then
     refused because no file had been recorded. */
  await p.evaluate(() => { window.__refuseAdd = true; });
  await p.locator('input[type=file]').setInputFiles(
    { name: 'refused.mp4', mimeType: 'video/mp4', buffer: Buffer.from('a video') });
  await p.waitForTimeout(900);
  const refusedMsg = await card.locator('[data-msg]').innerText();
  check('a save the database refuses is reported by name', refusedMsg.includes('refused.mp4'), refusedMsg);
  check('and the progress row does not stand there full',
    await card.locator('[data-up]').isHidden());
  check('and Submit is usable again', !(await card.locator('[data-a="submit"]').isDisabled()));
  check('and nothing was recorded for it', await p.evaluate(() =>
    !window.__DB.campaign_deliverables.some(d => d.name === 'refused.mp4')));
  await p.evaluate(() => { window.__refuseAdd = false; });

  // A file over the ceiling is refused by name before a byte moves.
  await p.evaluate(() => { window.ADSPACE_CONFIG.s3.maxUploadMB = 0.000001; });
  const putsBefore = puts.length;
  await p.locator('input[type=file]').setInputFiles(
    { name: 'huge.mp4', mimeType: 'video/mp4', buffer: Buffer.from('bigger than nothing') });
  await p.waitForTimeout(600);
  const bigMsg = await card.locator('[data-msg]').innerText();
  check('a file over the limit is named and refused before it is uploaded',
    bigMsg.includes('huge.mp4') && bigMsg.includes('MB') && puts.length === putsBefore, bigMsg);
  await p.evaluate(() => { window.ADSPACE_CONFIG.s3.maxUploadMB = 300; });

  // Anything a person can attach, a person can remove.
  await p.locator('.filecard [data-a="rm"]').first().click(); await p.waitForTimeout(600);
  check('a file can be taken back off', await p.locator('.filecard').count() === 1,
    String(await p.locator('.filecard').count()));

  await p.locator('[data-cap]').fill('New launch at Laman Citra ✨');
  await p.locator('[data-a="submit"]').click(); await p.waitForTimeout(800);
  /* Submitting reaches the team, not the client. It used to go straight to
     Reviewing, which on the client's page reads "Your approval": the chip
     asked them to decide the moment the creator uploaded, over files they
     cannot read. */
  check('submitting moves the step to Submitted, which is ours', await p.evaluate(() =>
    window.__DB.campaign_options.find(o => o.id === 'oA').state) === 'submitted',
    await p.evaluate(() => window.__DB.campaign_options.find(o => o.id === 'oA').state));
  check('and keeps the caption they wrote', await p.evaluate(() =>
    window.__DB.campaign_options.find(o => o.id === 'oA').draft_caption) === 'New launch at Laman Citra ✨');
  const after = await cards().first().innerText();
  check('the hand-in closes once it is ours', await p.locator('[data-a="submit"]').count() === 0);
  check('and a handed-in file can no longer be pulled back off',
    await p.locator('.filecard [data-a="rm"]').count() === 0);
  check('and the card says where it now is', after.includes('under review'),
    after.replace(/\n/g, ' | '));

  /* ---- The client is not asked to approve what has not been released -------- */
  await p.goto('http://127.0.0.1:8899/creators/?k=CMATOK', { waitUntil: 'networkidle' });
  await p.waitForTimeout(800);
  const beforeRelease = await p.locator('#bookingList').innerText().catch(() => '');
  check('the client is told Pending draft, never Your approval',
    beforeRelease.includes('Pending draft') && !beforeRelease.includes('Your approval'),
    beforeRelease.replace(/\n/g, ' | ').slice(0, 200));
  check('and has nothing to review yet',
    await p.locator('.booking-cta').count() === 0);

  // The team releases it. Only now is it theirs to decide on.
  await p.evaluate(() => {
    window.__DB.campaign_options.find(o => o.id === 'oA').state = 'reviewing';
    window.__persist();
  });
  await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(800);
  const released = await p.locator('#bookingList').innerText();
  check('once released the client is asked to approve',
    released.includes('Reviewing') && released.includes('Your approval'),
    released.replace(/\n/g, ' | ').slice(0, 200));
  check('and there is something to open', await p.locator('.booking-cta').count() === 1);
  await p.locator('.booking-cta').first().click(); await p.waitForTimeout(400);
  const sheet = await p.locator('#draftSheet').innerText();
  check('the sheet shows the creator\'s own file, not a pasted link',
    sheet.includes('cover.jpg'), sheet.replace(/\n/g, ' | ').slice(0, 200));
  check('and the caption they wrote', sheet.includes('New launch at Laman Citra'));

  // Back to the creator's page for the rest of the run.
  await p.goto('http://127.0.0.1:8899/creator/', { waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  await p.evaluate(() => {
    window.__DB.campaign_options.find(o => o.id === 'oA').state = 'reviewing';
    window.__persist();
  });

  // ---- The payment form is named on approval, not on submit ------------------
  check('no payment form while it is still being reviewed',
    (await p.locator('#workList').innerText()).indexOf('payment details') < 0);
  await p.evaluate(() => {
    window.__DB.campaign_options.find(o => o.id === 'oA').state = 'scheduled';
    window.__persist();
  });
  await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(700);
  check('the code is remembered, so there is no second sign-in',
    await p.locator('#app').isVisible());
  check('once approved, the payment form is asked for',
    (await p.locator('#workList').innerText()).includes('payment details'));
  check('and it points at AP01', /ap01/i.test(await p.locator('[data-a="pay"]').first().getAttribute('href')),
    await p.locator('[data-a="pay"]').first().getAttribute('href'));

  // ---- A link signs them in in one tap, and drops the code from the address --
  await p.evaluate(() => { try { localStorage.clear(); } catch (e) {} });
  await p.goto('http://127.0.0.1:8899/creator/?k=K3CCCCCC', { waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  check('the link opens the page with no typing', await p.locator('#app').isVisible() &&
    (await p.locator('#whoName').innerText()) === '小熊爱睡觉');
  check('and the code leaves the address bar', !p.url().includes('K3CCCCCC'), p.url());

  // ---- Chinese ---------------------------------------------------------------
  await p.locator('#langToggle').click(); await p.waitForTimeout(400);
  const zh = await p.locator('#workList').innerText();
  say('zh: ' + zh.replace(/\n/g, ' | '));
  check('the page is localised, and rednote is 小红书 there', zh.includes('小红书'));

  // ---- A creator stood down loses the page -----------------------------------
  await p.evaluate(() => {
    window.__DB.creators.find(c => c.id === 'k3').active = false;
    window.__persist();
  });
  await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(700);
  check('standing a creator down closes their page', await p.locator('#app').isHidden() &&
    await p.locator('#codeRow').isHidden(), await p.locator('#stateTitle').innerText());

  /* ---- And the team sees it, on the same database ----------------------------
     An upload nobody on our side can open is the Drive folder again with extra
     steps, so the console is opened on the campaign the creator just delivered
     to and the file and the caption are read off the card. */
  await p.goto('http://127.0.0.1:8899/admin/?s=campaigns&campaign=cmA', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(1000);
  await cpane('creators');
  const theirs = p.locator('#creatorList .kcard').filter({ hasText: '恩比' }).first();
  await theirs.locator('.kcard-head').click();
  await p.waitForTimeout(400);
  const seen = await theirs.innerText();
  check('the team sees the file the creator uploaded', seen.includes('cover.jpg'),
    seen.replace(/\n/g, ' | ').slice(0, 220));
  check('and the caption they wrote',
    (await theirs.locator('[data-f="draft_caption"]').inputValue()).includes('Laman Citra'));

  // At Submitted the card offers the two moves that are the team's: release it,
  // or send it back to the creator without the client ever seeing the round.
  await p.evaluate(() => {
    window.__DB.campaign_options.find(o => o.id === 'oA').state = 'submitted';
    window.__persist();
  });
  await p.reload({ waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(1200);
  await cpane('creators');
  const card2 = p.locator('#creatorList .kcard').filter({ hasText: '恩比' }).first();
  // No click: a card waiting on us is open already. That is the fix.
  check('the team can release it to the client',
    (await card2.locator('[data-a="advance"]').innerText()).includes('Release to client'),
    await card2.locator('[data-a="advance"]').innerText());
  check('and can send it back to the creator instead',
    await card2.locator('[data-a="sendback"]').count() === 1);
  /* The card that is waiting on us opens by itself. Folded it was a name, a
     chip and a summary line, so the files, the caption and both actions sat
     behind a fold nobody knew to open: a booking with no next action. */
  check('the card waiting on us is open without being asked',
    await card2.locator('[data-body]').isVisible());
  check('and is marked as waiting even when folded',
    (await card2.evaluate(el => el.className)).includes('is-waiting'));
  const open2 = await card2.innerText();
  check('the files the creator sent are on it',
    open2.includes('raya') || open2.includes('cover.jpg'), open2.replace(/\n/g, ' | ').slice(0, 180));
  check('and the caption they wrote',
    (await card2.locator('[data-f="draft_caption"]').inputValue()).includes('Laman Citra'));
  check('and the folded line says how much arrived',
    (await card2.locator('.kcard-sum').innerText()).includes('file'),
    await card2.locator('.kcard-sum').innerText());

  console.log(errs.length ? errs.join('\n') : 'no page errors');
  console.log(fails + ' FAIL');
  await b.close();
  if (fails) process.exit(1);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
