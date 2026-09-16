const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const errs = [];
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
  p.on('console', m => { if (m.type() === 'error' && !/favicon|404/i.test(m.text())) errs.push('CONSOLE ' + m.text()); });
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  say('tab title: ' + await p.title());
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(400);

  say('nav: ' + (await p.locator('.navitem').allInnerTexts()).join(' | '));
  await p.locator('.navitem[data-section="campaigns"]').click();
  await p.waitForTimeout(400);
  say('section title: ' + await p.locator('#sectionTitle').innerText());
  say('doc title now: ' + await p.title());

  // ---- Roster
  await p.locator('#tabRoster').click();
  await p.waitForTimeout(400);
  say('roster rows: ' + await p.locator('#rosterList .cr-row:not(.crm-head)').count() + '  count=' + await p.locator('#rosterCount').innerText());
  /* Two creators whose names begin with the same character are two rows that
     have to read differently. The disc that used to start the row gave both
     the same grey circle, so what the row carries is the record instead. */
  say('no monogram: ' + (await p.locator('#rosterList .cr-mono').count() === 0));
  say('every row states a record: ' +
    (await p.locator('#rosterList .cr-row:not(.crm-head) .cr-rec').allInnerTexts()).join(' / '));
  // The profile is on the row, as the word and the mark that says it leaves.
  say('the profile is a link on the row: ' +
    (await p.locator('#rosterList .cr-row:not(.crm-head) .plink-bare').first().innerText()));
  // Every column starts where its heading does, on every row.
  say('header cells: ' + (await p.locator('#rosterList .crm-head span').count()) +
    ' for ' + await p.evaluate(() => getComputedStyle(
      document.querySelector('#rosterList .cr-row:not(.crm-head)')).gridTemplateColumns.split(' ').length) +
    ' columns');
  const hs = await p.locator('#rosterList .cr-row:not(.crm-head)').evaluateAll(
    l => l.map(r => Math.round(r.getBoundingClientRect().height)));
  say('rows share one height: ' + (Math.max(...hs) - Math.min(...hs) <= 2) + ' ' + hs.join(','));

  await p.locator('#showAddCreator').click();
  await p.fill('#crName', '测试博主');
  await p.fill('#profRows .prof-url', 'https://www.xiaohongshu.com/user/profile/aaaa1111bbbb2222cccc3333');
  await p.waitForTimeout(250);
  say('platform read: ' + await p.locator('.prof-read').first().innerText());

  // a link that already belongs to someone
  await p.locator('#addProfRow').click();
  await p.fill('#profRows .profrow:nth-child(2) .prof-url', 'https://instagram.com/popcorn.xx');
  await p.waitForTimeout(300);
  say('dupe warning: ' + await p.locator('#dupeWarn').innerText());

  // a junk link
  await p.fill('#profRows .profrow:nth-child(2) .prof-url', 'https://example.com/whoever');
  await p.waitForTimeout(250);
  say('junk read: ' + await p.locator('.profrow:nth-child(2) .prof-read').innerText());

  // short link is accepted but anonymous
  await p.fill('#profRows .profrow:nth-child(2) .prof-url', 'https://xhslink.com/m/3XdbpK9PDIQ');
  await p.waitForTimeout(250);
  say('short link read: ' + await p.locator('.profrow:nth-child(2) .prof-read').innerText());

  await p.fill('#crRate', '400');
  await p.locator('#saveCreator').click();
  await p.waitForTimeout(500);
  say('roster after add: ' + await p.locator('#rosterList .cr-row:not(.crm-head)').count() + ' rows');

  // ---- Campaign
  await p.locator('#tabCampaigns').click();
  await p.waitForTimeout(300);
  await p.locator('#showAddCamp').click();
  await p.waitForTimeout(300);
  // typed client, not picked: an existing name resolves, a new one is created
  await p.selectOption('#campClient', 'c1');
  await p.fill('#campTitle', 'Laman Citra Launch');
  await p.fill('#campPurpose', 'Promote the newly launched project');
  await p.fill('#campSlots', '10');
  await p.selectOption('#campOwner', 'Qiao Rou');
  await p.locator('#addCamp').click();
  await p.waitForTimeout(500);
  say('name: ' + await p.locator('#campName').innerText() + ' | purpose: ' + await p.locator('#campPurposeLine').innerText());
  say('facts labels: ' + (await p.locator('#campFacts dt').allInnerTexts()).join(' | '));
  say('facts values: ' + (await p.locator('#campFacts dd').allInnerTexts()).join(' | '));
  say('invoice panel closed on a new campaign: ' + await p.locator('#invoiceBody').isHidden() + ' | summary=' + await p.locator('#invoiceSummary').innerText());
  say('delete hidden until editing: ' + await p.locator('#campDelete').isHidden());
  say('client resolved to existing id: ' + await p.evaluate(() => window.__DB.campaigns[0].client_id === 'c1'));
  say('clients still: ' + await p.evaluate(() => window.__DB.clients.length));
  say('select vs input height match: ' + await p.evaluate(() => {
    const a = document.querySelector('#campFormat').getBoundingClientRect().height;
    const b = document.querySelector('#campTitle').getBoundingClientRect().height;
    return Math.abs(a - b) < 1 ? 'yes' : 'no (' + a + ' vs ' + b + ')';
  }));
  say('campaign link: ' + (await p.locator('#campLink').inputValue()).replace(/k=.*/, 'k=…'));

  // add options
  await cpane('creators');
  await p.locator('#showAddOption').click();
  await p.waitForTimeout(400);
  say('picker rows: ' + await p.locator('#optionPick .pickrow').count());
  say('rate prefilled from usual rate: ' + await p.locator('#optionPick .pickrate').first().inputValue());
  // her links are rednote + Instagram, so both start ticked; this campaign is rednote only
  /* Ticking a platform a creator has no link for used to mean leaving the
     campaign, adding the link on the creators list, and coming back. The tick
     opens into the field in place, and what is typed is saved to the creator. */
  const need = p.locator('#optionPick .pickrow').filter({ hasText: '恩比' }).first();
  const igbox = need.locator('.pbox').filter({ hasText: 'Instagram' }).first();
  const wide = async () => Math.round((await igbox.boundingBox()).width);
  const shut = await wide();
  say('the box is a tick before it is ticked: ' + shut + 'px, field off the tab order: ' +
    await igbox.locator('.pbox-link').isDisabled());
  await need.locator('.pbox-tick input[value="Instagram"]').check();
  await p.waitForTimeout(500);
  const open = await wide();
  say('ticking opens it into the field: ' + open + 'px, ' + (open > shut + 100 ? 'in place' : 'DID NOT OPEN'));
  say('and the row still holds one line: ' + (Math.round((await need.boundingBox()).height) < 70));
  await need.locator('.pbox-tick input[value="Instagram"]').uncheck();
  await p.waitForTimeout(500);
  say('unticking shuts it again: ' + (Math.round(await wide()) === shut));
  await need.locator('.pbox-tick input[value="Instagram"]').check();
  await p.waitForTimeout(400);
  await igbox.locator('.pbox-link').fill('https://instagram.com/enbi.my');
  await need.locator('.pickrate').fill('380');
  await need.locator(".pickadd > button").click();
  await p.waitForTimeout(500);
  const kept = await p.evaluate(() => (window.__DB.creator_profiles || []).filter(
    r => r.platform === 'instagram' && r.handle === 'enbi.my'));
  say('link kept on the creator: ' + JSON.stringify(kept.map(r => r.url)));
  if (kept.length !== 1) { console.log('FAIL the link typed on the picker row is not saved to the creator'); }

  const first = p.locator('#optionPick .pickrow').first();
  say('platforms pre-ticked: ' + (await first.locator('.pbox input:checked').evaluateAll(l => l.map(i => i.value))).join(', '));
  await first.locator('.pbox input[value="Instagram"]').uncheck();
  // none ticked is refused before the rate is even looked at
  await first.locator('.pbox input[value="rednote"]').uncheck();
  await first.locator('button').click();
  await p.waitForTimeout(250);
  say('no platform refused: ' + await p.locator('#optionMsg').innerText());
  await first.locator('.pbox input[value="rednote"]').check();
  // the first one is offered at a campaign-specific rate, not her usual one
  await first.locator('.pickrate').fill('555');
  await first.locator('button').click();
  await p.waitForTimeout(400);
  say('offer rate: ' + await p.evaluate(() => window.__DB.campaign_options[0].rate) +
      ' | platforms: ' + await p.evaluate(() => window.__DB.campaign_options[0].platforms) +
      ' | roster still: ' + await p.evaluate(() => window.__DB.creators[0].client_rate));
  // one without any rate typed is refused
  await p.locator('#optionPick .pickrate').first().fill('');
  await p.locator('#optionPick .pickrow button').first().click();
  await p.waitForTimeout(300);
  say('empty rate refused: ' + await p.locator('#optionMsg').innerText());
  for (let i = 0; i < 3; i++) {
    const btn = p.locator('#optionPick .pickrow button').first();
    if (await btn.count() === 0) break;
    const rate = p.locator('#optionPick .pickrate').first();
    if (!(await rate.inputValue())) await rate.fill('300');
    await btn.click();
    await p.waitForTimeout(300);
  }
  say('options added: ' + await p.locator('#creatorList .kcard').count());
  say('first option row shows: ' + await p.locator('#creatorList .kstep-sum').first().innerText());

  say('=== new creator from inside the campaign ===');
  /* Keying somebody in is the rarer of the panel's two jobs, so it is folded
     shut and the panel opens on the roster. */
  say('keyed-in form starts folded: ' + await p.locator('#ncBox').isHidden());
  await p.locator('#ncToggle').click(); await p.waitForTimeout(250);
  await p.fill('#ncName', '阿May日常');
  await p.fill('#ncRate', '420');
  await p.fill('#ncProfRows .prof-url', 'https://instagram.com/popcorn.xx');
  await p.waitForTimeout(300);
  say('taken link warned: ' + await p.locator('#ncDupe').innerText());
  await p.fill('#ncProfRows .prof-url', 'https://www.xiaohongshu.com/user/profile/ffff0000ffff0000ffff0000');
  await p.waitForTimeout(200);
  say('link ticked its platform: ' + (await p.locator('#ncPlatforms .pbox input:checked').evaluateAll(l => l.map(i => i.value))).join(', '));
  await p.locator('#ncPlatforms .pbox input[value="TikTok"]').check();
  const rosterBefore = await p.evaluate(() => window.__DB.creators.length);
  await p.locator('#ncSave').click();
  await p.waitForTimeout(900);
  say('roster grew: ' + (await p.evaluate(() => window.__DB.creators.length) - rosterBefore) +
      ' | offered at: ' + await p.evaluate(() => window.__DB.campaign_options[window.__DB.campaign_options.length - 1].rate) +
      ' on ' + await p.evaluate(() => window.__DB.campaign_options[window.__DB.campaign_options.length - 1].platforms) +
      ' | options now: ' + await p.locator('#creatorList .kcard').count());

  say('=== edit the rate on an offer ===');
  await p.locator('#creatorList [data-a="rate"]').first().click();
  await p.waitForTimeout(200);
  await p.locator('#creatorList .rate-edit input[type="number"]').fill('610');
  await p.locator('#creatorList .rate-edit .pbox input[value="Instagram"]').check();
  await p.locator('#creatorList .rate-edit button').first().click();
  await p.waitForTimeout(500);
  say('after edit: ' + await p.locator('#creatorList .kstep-sum').first().innerText());

  say('=== edit the campaign ===');
  say('delete looks like a warning: ' + ((await p.locator('#campDelete').getAttribute('class')).indexOf('is-danger') > -1) + ' | hidden until asked: ' + await p.locator('#campDelete').isHidden());
  await p.locator('#campEdit').click();
  await p.waitForTimeout(400);
  say('form title: ' + await p.locator('#campFormTitle').innerText());
  await p.fill('#campTitle', 'Laman Citra Launch, phase 2');
  await p.fill('#campPurpose', 'Promote the second release');
  await p.fill('#campSlots', '12');
  await p.selectOption('#campOwner', 'Aisyah');
  await p.locator('#addCamp').click();
  await p.waitForTimeout(600);
  say('facts after edit: ' + (await p.locator('#campFacts dd').allInnerTexts()).join(' | '));
  say('title after edit: ' + await p.locator('#campName').innerText() + ' | purpose: ' + await p.locator('#campPurposeLine').innerText());
  say('form closed: ' + await p.locator('#addCampBox').isHidden());

  say('=== invoice, after the fact ===');
  // The counts and the money left the Overview for the rail in Phase 2. Same
  // figures, read where they now are.
  say('selection: ' + (await p.locator('#campPickRail').innerText()).replace(/\n/g, ' / '));
  say('amount: ' + (await p.locator('#campMoneyRail').innerText()).replace(/\n/g, ' / '));
  const noPanel = await p.locator('#invoicePanel').isHidden();
  say('nothing confirmed: no invoice section at all: ' + noPanel);
  if (!noPanel) { console.log('FAIL the invoice section is offered before a creator is confirmed'); }

  say('=== confirm a creator, then the invoice ===');
  const card = p.locator('#creatorList .kcard').first();
  await card.locator('.kmenu-btn').scrollIntoViewIfNeeded();
  await card.locator('.kmenu-btn').click(); await p.waitForTimeout(250);
  await p.locator('.kmenu [data-a="pick"]').first().click();
  await p.waitForTimeout(600);
  await cpane('client');
  await p.locator('#campLock').click(); await p.waitForTimeout(300);
  await p.fill('#lockPerson', 'Wei Ling');
  await p.locator('#lockGo').click();
  await p.waitForTimeout(900);
  say('option states: ' + await p.evaluate(() => window.__DB.campaign_options.map(o => o.state).join(',')));
  /* The panel arrives with the confirmation. It lives in the Finance pane, so
     "arrived" is its own hidden flag rather than whether the pane it sits in
     happens to be the one on screen. */
  const hasPanel = !(await p.locator('#invoicePanel').evaluate(e => e.hidden));
  say('invoice section arrives with the confirmation: ' + hasPanel);
  if (!hasPanel) { console.log('FAIL the invoice section is missing after a creator is confirmed'); }

  await cpane('finance');
  say('invoice panel opened by hand: ' + await p.locator('#invoiceBody').isVisible());
  await p.fill('#invNo', '026114');
  await p.locator('#invCancel').click(); await p.waitForTimeout(300);
  say('cancel puts back what is stored: "' + await p.locator('#invNo').inputValue() + '"');
  await p.fill('#invNo', '026114');
  await p.locator('#invSave').click();
  await p.waitForTimeout(600);
  say('summary now: ' + await p.locator('#invoiceSummary').innerText() + ' | panel stays open=' + await p.locator('#invoiceBody').isVisible());
  await p.route('https://s3.test/**', r => r.fulfill({ status: 200, body: '' }));
  let putSeen = false;
  p.on('request', r => { if (r.method() === 'PUT' && r.url().startsWith('https://s3.test/')) putSeen = true; });
  await p.setInputFiles('#invFile', { name: 'AINV026114.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4 test') });
  await p.fill('#invNo', '026115');
  await p.locator('#invSave').click();
  await p.waitForTimeout(1100);
  say('signed as: ' + await p.evaluate(() => JSON.stringify((window.__signed || []).slice(-1)[0])));
  say('PUT went to S3: ' + putSeen);
  say('msg: ' + await p.locator('#invMsg').innerText());
  const both = await p.evaluate(() => {
    const c = window.__DB.campaigns[0];
    return c.invoice_no === 'AINV026115' && !!c.invoice_url;
  });
  say('one Save stored the number and the PDF together: ' + both);
  if (!both) { console.log('FAIL Save covers the number and the PDF'); }
  say('stored url: ' + await p.evaluate(() => window.__DB.campaigns[0].invoice_url));
  say('current shows link: ' + await p.locator('#invCurrent a').count() + ' -> ' + await p.locator('#invCurrent').innerText());
  say('summary with PDF: ' + await p.locator('#invoiceSummary').innerText());
  await p.locator('#invRemove').click(); await p.waitForTimeout(500);
  const removed = await p.evaluate(() => window.__DB.campaigns[0].invoice_url == null);
  say('PDF removed: ' + removed + ' | undo offered: ' + await p.locator('#campUndo').isVisible());
  if (!removed) { console.log('FAIL the invoice PDF can be removed'); }
  await p.locator('#campUndo button').click(); await p.waitForTimeout(500);
  const back = await p.evaluate(() => !!window.__DB.campaigns[0].invoice_url);
  say('undo put it back: ' + back + ' | link shown again: ' + await p.locator('#invCurrent a').count());
  if (!back) { console.log('FAIL undo restores the invoice PDF'); }
  say('selection: ' + (await p.locator('#campPickRail').innerText()).replace(/\n/g, ' / '));
  say('amount: ' + (await p.locator('#campMoneyRail').innerText()).replace(/\n/g, ' / '));

  say('=== the client only sees an invoice once one is due ===');
  const tok = await p.evaluate(() => window.__DB.campaigns[0].access_token);
  const shownNow = await p.evaluate(async t =>
    (await window.__rpc('get_campaign', { p_token: t })).data.campaign.invoice_no, tok);
  say('confirmed, so the client reads: ' + shownNow);

  // Revert the confirmation: the invoice has to leave both pages with it.
  p.once('dialog', d => d.accept());
  await cpane('creators');
  const live = p.locator('#creatorList .kcard').first();
  await live.locator('.kmenu-btn').scrollIntoViewIfNeeded();
  await live.locator('.kmenu-btn').click(); await p.waitForTimeout(250);
  await p.locator('.kmenu [data-a="unbook"]').first().click();
  await p.waitForTimeout(800);
  say('option states after the revert: ' + await p.evaluate(() => window.__DB.campaign_options.map(o => o.state).join(',')));
  const backOpen = await p.evaluate(() => window.__DB.campaigns[0].state) === 'open';
  say('nobody in production, so the campaign is open again: ' + backOpen +
      ' | head reads "' + await p.locator('#campState').innerText() +
      '" and offers "' + await p.locator('#campPublish').innerText() + '"');
  if (!backOpen) { console.log('FAIL the campaign leaves production with its last creator'); }
  const goneHere = await p.locator('#invoicePanel').isHidden();
  const goneThere = await p.evaluate(async t => {
    const c = (await window.__rpc('get_campaign', { p_token: t })).data.campaign;
    return c.invoice_no == null && c.invoice_url == null;
  }, tok);
  say('invoice section gone from the console: ' + goneHere + ' | withheld from the client: ' + goneThere);
  say('the number is kept, not thrown away: ' + await p.evaluate(() => window.__DB.campaigns[0].invoice_no));
  if (!goneHere || !goneThere) { console.log('FAIL reverting the confirmation takes the invoice back'); }

  // Confirm again: the same invoice comes back, nothing retyped.
  const again = p.locator('#creatorList .kcard').first();
  await again.locator('.kmenu-btn').scrollIntoViewIfNeeded();
  await again.locator('.kmenu-btn').click(); await p.waitForTimeout(250);
  await p.locator('.kmenu [data-a="pick"]').first().click();
  await p.waitForTimeout(600);
  await cpane('client');
  await p.locator('#campLock').click(); await p.waitForTimeout(300);
  await p.fill('#lockPerson', 'Wei Ling');
  await p.locator('#lockGo').click(); await p.waitForTimeout(900);
  say('confirmed again, the client reads: ' + await p.evaluate(async t =>
    (await window.__rpc('get_campaign', { p_token: t })).data.campaign.invoice_no, tok));

  await cpane('client');
  await p.locator('#campPublish').click();
  await p.waitForTimeout(400);
  say('after publish: state=' + await p.locator('#campState').innerText() + ' btn=' + await p.locator('#campPublish').innerText());

  const token = await p.evaluate(() => window.__DB.campaigns[0].access_token);
  await p.screenshot({ path: process.argv[2] + '/camp-admin.png' });

  // ---- Client page
  const cp = await b.newPage({ viewport: { width: 1280, height: 1000 } });
  cp.on('pageerror', e => errs.push('CLIENT PAGEERROR ' + e.message));
  cp.on('console', m => { if (m.type() === 'error' && !/favicon|404/i.test(m.text())) errs.push('CLIENT ' + m.text()); });
  await cp.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await cp.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  // the client page needs the same stub DB, so seed it the same way
  await cp.goto('http://127.0.0.1:8899/creators/?k=' + token, { waitUntil: 'networkidle' });
  await cp.waitForTimeout(700);
  say('--- client ---');
  say('state box visible: ' + await cp.locator('#stateBox').isVisible());
  await b.close();
  say('--- errors ---');
  say(errs.length ? errs.join('\n') : 'none');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
