const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const errs = [];
const say = s => console.log(s);

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
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
  say('roster rows: ' + await p.locator('#rosterList .slink').count() + '  count=' + await p.locator('#rosterCount').innerText());

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
  say('roster after add: ' + await p.locator('#rosterList .slink').count() + ' rows');

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
  await p.fill('#campOwner', 'Wei Ling');
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
  await p.locator('#showAddOption').click();
  await p.waitForTimeout(400);
  say('picker rows: ' + await p.locator('#optionPick .pickrow').count());
  say('rate prefilled from usual rate: ' + await p.locator('#optionPick .pickrate').first().inputValue());
  // her links are RedNote + Instagram, so both start ticked; this campaign is RedNote only
  const first = p.locator('#optionPick .pickrow').first();
  say('platforms pre-ticked: ' + (await first.locator('.pbox input:checked').evaluateAll(l => l.map(i => i.value))).join(', '));
  await first.locator('.pbox input[value="Instagram"]').uncheck();
  // none ticked is refused before the rate is even looked at
  await first.locator('.pbox input[value="RedNote"]').uncheck();
  await first.locator('button').click();
  await p.waitForTimeout(250);
  say('no platform refused: ' + await p.locator('#optionMsg').innerText());
  await first.locator('.pbox input[value="RedNote"]').check();
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
  await p.fill('#campOwner', 'Aisyah');
  await p.locator('#addCamp').click();
  await p.waitForTimeout(600);
  say('facts after edit: ' + (await p.locator('#campFacts dd').allInnerTexts()).join(' | '));
  say('title after edit: ' + await p.locator('#campName').innerText() + ' | purpose: ' + await p.locator('#campPurposeLine').innerText());
  say('form closed: ' + await p.locator('#addCampBox').isHidden());

  say('=== invoice, after the fact ===');
  say('stats: ' + (await p.locator('#campTally').innerText()).replace(/\n/g, ' / '));
  await p.locator('#invoiceToggle').click(); await p.waitForTimeout(200);
  say('invoice panel opened by hand: ' + await p.locator('#invoiceBody').isVisible());
  await p.fill('#invNo', '026114');
  await p.locator('#invSaveNo').click();
  await p.waitForTimeout(500);
  say('summary now: ' + await p.locator('#invoiceSummary').innerText() + ' | panel stays open=' + await p.locator('#invoiceBody').isVisible());
  await p.locator('#invUpload').click();
  await p.waitForTimeout(250);
  say('no file: ' + await p.locator('#invMsg').innerText());
  await p.route('https://s3.test/**', r => r.fulfill({ status: 200, body: '' }));
  let putSeen = false;
  p.on('request', r => { if (r.method() === 'PUT' && r.url().startsWith('https://s3.test/')) putSeen = true; });
  await p.setInputFiles('#invFile', { name: 'AINV2026114.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4 test') });
  await p.locator('#invUpload').click();
  await p.waitForTimeout(900);
  say('signed as: ' + await p.evaluate(() => JSON.stringify((window.__signed || []).slice(-1)[0])));
  say('PUT went to S3: ' + putSeen);
  say('msg: ' + await p.locator('#invMsg').innerText());
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
  say('tally: ' + (await p.locator('#campTally').innerText()).replace(/\n/g, ' / '));

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
