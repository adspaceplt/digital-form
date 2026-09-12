// The CRM is where a client lives, and the currency follows the client.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
let bad = 0;
const check = (l, ok, extra) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (extra ? '  ' + extra : '')); if (!ok) bad++; };
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1200, height: 1000 } });
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('dialog', d => d.accept());
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  // A stand-in for the PDF library: draws nothing, records what it was asked to draw.
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: `
    window.__drawn = [];
    window.PDFLib = { rgb: () => ({}), StandardFonts: { Helvetica: 'H', HelveticaBold: 'HB' },
      PDFDocument: { create: () => Promise.resolve({
        embedFont: () => Promise.resolve({ widthOfTextAtSize: (s, z) => String(s).length * z * 0.5 }),
        addPage: () => ({ drawText: (s) => window.__drawn.push(String(s)), drawLine: () => {} }),
        save: () => Promise.resolve(new Uint8Array([37, 80, 68, 70])) }) } };` }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  // The stub signs out on reload unless told otherwise, same as the state suite.
  await p.addInitScript(() => {
    window.addEventListener('load', () => setTimeout(
      () => window.__signIn && window.__signIn('adspacestudios@gmail.com'), 40));
  });
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(500);

  check('the activity record is offered from the very first screen',
    await p.locator('#activityOpen').isVisible());

  await p.locator('.navitem[data-section="clients"]').click(); await p.waitForTimeout(600);
  check('Clients is a section of its own', await p.locator('#sectionClients').isVisible());
  check('both clients listed', await p.locator('.crm-row').count() === 2,
    await p.locator('#crmCount').innerText());

  console.log('  rows: ' + (await p.locator('.crm-row').allInnerTexts()).map(t => t.replace(/\n/g, ' | ')).join('  //  '));
  check('the Singapore client is marked in S$',
    (await p.locator('.crm-row').nth(0).innerText()).includes('S$') ||
    (await p.locator('.crm-row').nth(1).innerText()).includes('S$'));

  // filters
  await p.selectOption('#crmStage', 'active'); await p.waitForTimeout(300);
  check('stage filters the list', await p.locator('.crm-row').count() === 1);
  await p.selectOption('#crmStage', 'all'); await p.waitForTimeout(300);
  await p.fill('#crmSearch', 'furiku'); await p.waitForTimeout(300);
  check('search finds by name', await p.locator('.crm-row').count() === 1);
  await p.fill('#crmSearch', ''); await p.waitForTimeout(300);

  // create
  await p.locator('#crmNew').click(); await p.waitForTimeout(300);
  check('intake asks for the person, not the brand links',
    await p.locator('#crmContactName').isVisible() && await p.locator('#crmSocialIg').isHidden());
  await p.locator('#crmSave').click(); await p.waitForTimeout(300);
  check('a client must have a name', (await p.locator('#crmMsg').innerText()).length > 0);
  await p.fill('#crmName', 'Star Living');
  await p.locator('#crmSave').click(); await p.waitForTimeout(300);
  check('a lead must have a contact person', /contact/i.test(await p.locator('#crmMsg').innerText()));
  await p.selectOption('#crmSource', 'referral');
  await p.selectOption('#crmMarket', 'SG');
  await p.fill('#crmOwnerPick', 'Qiao Rou');
  await p.fill('#crmContactName', 'Mr Lim');
  await p.fill('#crmContactPhone', '012-345 6789');
  await p.fill('#crmEnquiry', 'Launch video and three months of Package B');
  await p.locator('#crmSave').click(); await p.waitForTimeout(900);
  check('opens the client it just created',
    (await p.locator('#crmClientName').innerText()) === 'Star Living');
  check('the source is on the record', (await p.locator('#crmFacts').innerText()).includes('Referral'));
  check('the person who asked is the main contact',
    await p.locator('#crmContacts .ct-row:not(.crm-head)').count() === 1 &&
    (await p.locator('#crmContacts').innerText()).includes('Main contact'));
  check('the enquiry stands in until a service line is added',
    (await p.locator('#crmServices').innerText()).includes('Package B'));
  check('a review link is issued at creation, so Content Review has nothing to make',
    await p.evaluate(() => Boolean((window.__DB.clients.find(c => c.name === 'Star Living') || {}).access_token)));
  console.log('  facts: ' + (await p.locator('#crmFacts').innerText()).replace(/\n/g, ' | '));
  check('the new client is priced in S$', (await p.locator('#crmFacts').innerText()).includes('S$'));

  // contacts
  await p.locator('#crmAddContact').click(); await p.waitForTimeout(300);
  await p.fill('#ctName', 'Ms Tan');
  await p.fill('#ctRole', 'Finance');
  await p.locator('#ctSave').click(); await p.waitForTimeout(800);
  check('a second contact saved', await p.locator('#crmContacts .ct-row:not(.crm-head)').count() === 2);
  check('the first contact stays the main one',
    (await p.locator('#crmContacts .ct-row:not(.crm-head)').first().innerText()).includes('Mr Lim'));
  check('phone and WhatsApp are one tap each',
    await p.locator('#crmContacts .plink').count() >= 2);

  // billing, and the tax switch
  await p.locator('#crmBillToggle').click(); await p.waitForTimeout(300);
  check('the tax switch names the tax', (await p.locator('#crmSstLabel').innerText()).length > 0,
    JSON.stringify(await p.locator('#crmSstLabel').innerText()));
  await p.locator('#crmSstApplies').uncheck();
  await p.fill('#crmCompanyNo', '202201012345');
  await p.locator('#crmBillSave').click(); await p.waitForTimeout(800);
  check('tax can be turned off per client',
    await p.evaluate(() => (window.__DB.clients.find(c => c.name === 'Star Living') || {}).sst_applies === false));

  // refresh keeps you inside the client
  const url = p.url();
  const newId = await p.evaluate(() => (window.__DB.clients.find(c => c.name === 'Star Living') || {}).id);
  check('the address carries this client', url.indexOf('client=' + newId) > -1, url + ' vs ' + newId);
  await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(1100);
  check('a refresh lands back inside the client',
    await p.locator('#crmWork').isVisible() &&
    (await p.locator('#crmClientName').innerText()) === 'Star Living');

  // editing happens on the record, not over the list
  check('engagements wait for Active', await p.locator('#crmEngage').isHidden());
  await p.locator('#crmEdit').click(); await p.waitForTimeout(400);
  check('edit opens on the record in place of its head',
    await p.locator('#crmWork #crmAddBox').isVisible() && await p.locator('#crmListView').isHidden() &&
    await p.locator('#crmClientName').isHidden());
  await p.locator('#crmCancel').click(); await p.waitForTimeout(300);
  check('cancel stays on the record', await p.locator('#crmWork').isVisible() && await p.locator('#crmClientName').isVisible());

  // the gate: a lead cannot be made active until billing is complete
  await p.selectOption('#crmClientStage', 'active'); await p.waitForTimeout(500);
  // The select goes back and the record opens on the billing fields.
  const gate = await p.locator('#crmBillMsg').innerText();
  check('a lead cannot be made active without e-invoice details',
    /Billing details required/.test(gate) && await p.locator('#crmBillBody').isVisible() &&
    (await p.locator('#crmClientStage').inputValue()) === 'lead', gate.slice(0, 70));
  await p.selectOption('#crmClientStage', 'proposal'); await p.waitForTimeout(600);
  check('any other stage changes from the head',
    (await p.locator('#crmClientStage').inputValue()) === 'proposal' &&
    await p.evaluate(() => (window.__DB.clients.find(c => c.name === 'Star Living') || {}).stage === 'proposal'));
  await p.selectOption('#crmClientStage', 'lead'); await p.waitForTimeout(600);
  check('the page says what is missing', await p.locator('#crmGate').isVisible());

  // the list is grouped: leads on top, active below
  await p.locator('#crmBack').click(); await p.waitForTimeout(600);
  const groups = await p.locator('.crm-group-head h3').allInnerTexts();
  console.log('  groups: ' + groups.map(g => g.replace(/\n/g, ' ')).join(' / '));
  check('leads sit above active clients', groups[0].indexOf('Leads') === 0 && groups.some(g => g.indexOf('Active') === 0));

  // the registered name is kept in capitals
  await p.locator('.crm-row').filter({ hasText: 'Star Living' }).click(); await p.waitForTimeout(700);
  await p.locator('#crmBillToggle').click(); await p.waitForTimeout(300);
  await p.fill('#crmLegalName', 'star living sdn bhd');
  check('company name is forced to capitals', (await p.locator('#crmLegalName').inputValue()) === 'STAR LIVING SDN BHD');

  // a call logged against the client, with a next action
  await p.locator('#crmAddTouch').click(); await p.waitForTimeout(300);
  await p.selectOption('#tcKind', 'visit');
  await p.fill('#tcSummary', 'Walked the showroom. They want the launch video before Raya.');
  await p.fill('#tcNext', 'Send proposal');
  await p.fill('#tcNextAt', '2020-01-01');
  await p.locator('#tcSave').click(); await p.waitForTimeout(700);
  check('visit logged', await p.locator('.touch').count() === 1);
  check('the first entry makes the lead contacted', (await p.locator('#crmClientStage').inputValue()) === 'contacted' &&
    await p.evaluate(() => (window.__DB.clients.find(c => c.name === 'Star Living') || {}).stage === 'contacted'));
  check('the log records who wrote it', (await p.locator('.touch-meta').innerText()).includes('adspacestudios'));
  check('an overdue next action is marked', await p.locator('.touch.is-due').count() === 1);
  check('the main contact is offered as who it was with', (await p.locator('#crmContactNames option').count()) >= 1);

  // reversibility: edit a log entry, remove it, put it back; mark its action done
  await p.locator('.touch [data-a="edit"]').first().click(); await p.waitForTimeout(300);
  check('edit opens the entry prefilled', (await p.locator('#tcSummary').inputValue()).includes('Walked the showroom'));
  await p.fill('#tcSummary', 'Walked the showroom. Budget confirmed at S$ 20k.');
  await p.locator('#tcSave').click(); await p.waitForTimeout(600);
  check('the edit is saved and marked as edited',
    (await p.locator('.touch-summary').first().innerText()).includes('20k') &&
    (await p.locator('.touch-meta').first().innerText()).includes('edited'));
  await p.locator('.touch [data-a="del"]').first().click(); await p.waitForTimeout(500);
  check('removing hides rather than deletes', await p.locator('.touch:not(.is-off)').count() === 0 &&
    await p.evaluate(() => window.__DB.client_touches.length === 1));
  check('an Undo is offered', await p.locator('#crmUndo').isVisible());
  await p.locator('#crmUndo button').click(); await p.waitForTimeout(600);
  check('undo puts it back', await p.locator('.touch:not(.is-off)').count() === 1);
  await p.locator('.touch [data-a="done"]').first().click(); await p.waitForTimeout(500);
  check('a next action can be marked done', await p.locator('.touch-next.is-done').count() === 1);
  await p.locator('.touch [data-a="undone"]').first().click(); await p.waitForTimeout(500);
  check('and reopened', await p.locator('.touch-next.is-done').count() === 0);

  // contacts: edit in place, remove with undo, put back
  await p.locator('#crmContacts .ct-row:not(.crm-head) [data-a="menu"]').first().click(); await p.waitForTimeout(250);
  await p.locator('#crmContacts [data-a="edit"]').first().click(); await p.waitForTimeout(300);
  check('contact edit opens prefilled', (await p.locator('#ctName').inputValue()) === 'Mr Lim');
  await p.fill('#ctRole', 'Marketing Director');
  await p.locator('#ctSave').click(); await p.waitForTimeout(600);
  check('contact edit saved', (await p.locator('#crmContacts').innerText()).includes('Marketing Director'));
  await p.locator('#crmContacts .ct-row:not(.crm-head) [data-a="menu"]').first().click(); await p.waitForTimeout(250);
  await p.locator('#crmContacts [data-a="del"]').first().click(); await p.waitForTimeout(500);
  check('contact removal is a hide, and can be shown again',
    await p.evaluate(() => window.__DB.client_contacts.filter(c => c.client_id !== 'c1').length === 2) &&
    await p.locator('.crm-removed-toggle').count() === 1);
  await p.locator('.crm-removed-toggle').click(); await p.waitForTimeout(400);
  await p.locator('#crmContacts .ct-row.is-off [data-a="menu"]').click(); await p.waitForTimeout(250);
  await p.locator('#crmContacts [data-a="restore"]').click(); await p.waitForTimeout(600);
  check('a removed contact can be put back', await p.locator('#crmContacts .ct-row:not(.is-off):not(.crm-head)').count() === 2);

  // services: a line from the rate card, then a custom line, confirmed; the value follows
  await p.locator('#crmAddService').click(); await p.waitForTimeout(400);
  check('the rate card is offered, grouped', await p.locator('#svPick optgroup').count() >= 2);
  await p.selectOption('#svPick', 'pkg-b'); await p.waitForTimeout(150);
  check('picking a package fills its rate', (await p.locator('#svRate').inputValue()) === '2830');
  await p.fill('#svQty', '3');
  await p.selectOption('#svState', 'quoted');
  await p.locator('#svSave').click(); await p.waitForTimeout(900);
  check('the line is listed with its amount', (await p.locator('#crmServices').innerText()).includes('8,490'));
  check('a quoted total is the value until something is confirmed',
    (await p.locator('#crmFacts').innerText()).includes('8,490'));
  await p.locator('#crmAddService').click(); await p.waitForTimeout(400);
  await p.selectOption('#svPick', 'custom'); await p.waitForTimeout(150);
  check('a custom line asks for its name', await p.locator('#svLabelRow').isVisible());
  await p.fill('#svLabel', 'Launch video');
  await p.fill('#svRate', '20000');
  await p.selectOption('#svState', 'confirmed');
  await p.locator('#svSave').click(); await p.waitForTimeout(900);
  check('confirmed lines set the value', (await p.locator('#crmFacts').innerText()).includes('20,000'));
  await p.locator('#crmServices .svc-row:not(.crm-head)').first().locator('select[data-f="state"]').selectOption('confirmed'); await p.waitForTimeout(900);
  check('confirming the second line adds it up', (await p.locator('#crmFacts').innerText()).includes('28,490'));

  // a Letter of Offer from the quoted lines only, numbered for the month, kept as issued
  await p.locator('#crmServices .svc-row:not(.crm-head)').first().locator('select[data-f="state"]').selectOption('quoted'); await p.waitForTimeout(900);
  const dl = p.waitForEvent('download', { timeout: 8000 }).catch(() => null);
  await p.locator('#crmCover').click();
  const got = await dl; await p.waitForTimeout(600);
  const ymd = new Date().toISOString().slice(2, 10).replace(/-/g, '');
  const yymm = ymd.slice(0, 4);
  check('the letter downloads under its number', !!got && got.suggestedFilename() === 'AQT-INT-' + yymm + '001.pdf',
    got ? got.suggestedFilename() : 'no download');
  check('the letter carries the quoted lines only, the contact and who signed it', await p.evaluate(() => {
    const d = window.__DB.client_documents[0];
    return !!d && d.kind === 'offer' && d.issued_by === 'ADspace' && d.lines.length === 1 && d.lines[0].state === 'quoted' &&
      d.total === 8490 && d.tax === 0 && d.bill_to.contact === 'Mr Lim' && d.bill_to.owner === 'Qiao Rou';
  }));
  check('the PDF carries the number, the client, the contact, the total and the acceptance block',
    await p.evaluate(yymm => { const all = window.__drawn.join(' ');
      return window.__drawn.some(s => s === 'AQT/INT/' + yymm + '001') && /Star Living/i.test(all) && /Mr Lim/.test(all) && /8,490/.test(all) &&
        /LETTER OF OFFER/.test(all) && /pleased to set out/.test(all) && /Confirmed and accepted/.test(all); }, yymm));
  check('the document is listed', await p.locator('#crmDocuments .doc-row:not(.crm-head)').count() === 1);
  await p.locator('#crmCover').click(); await p.waitForTimeout(800);
  check('the next one this month takes the next number',
    await p.evaluate(yymm => window.__DB.client_documents.some(d => d.number === 'AQT/INT/' + yymm + '002'), yymm));
  await p.locator('#crmServices .svc-row:not(.crm-head)').first().locator('select[data-f="state"]').selectOption('confirmed'); await p.waitForTimeout(900);
  await p.locator('#crmCover').click(); await p.waitForTimeout(600);
  check('with nothing quoted there is no letter to issue', /No quoted lines/.test(await p.locator('#crmDocMsg').innerText()) &&
    await p.evaluate(() => window.__DB.client_documents.length === 2));

  // the billing contact is one of the contacts, the main one unless chosen
  await p.locator('#crmBack').click(); await p.waitForTimeout(600);
  await p.locator('.crm-row').filter({ hasText: 'Laman Citra' }).click(); await p.waitForTimeout(800);
  check('an active client with a main contact has billing complete', (await p.locator('#crmBillSummary').innerText()).includes('Complete'));
  await p.locator('#crmBillToggle').click(); await p.waitForTimeout(300);
  check('the billing contact is prefilled with the main contact',
    (await p.locator('#crmBillContact option:checked').innerText()).includes('Mr Lim'));
  await p.locator('#crmAddService').click(); await p.waitForTimeout(300);
  await p.selectOption('#svPick', 'koc-10'); await p.selectOption('#svState', 'confirmed');
  await p.locator('#svSave').click(); await p.waitForTimeout(900);
  await p.locator('#crmAddService').click(); await p.waitForTimeout(300);
  await p.selectOption('#svPick', 'static-graphic'); await p.selectOption('#svState', 'quoted');
  await p.fill('#svTenure', '6'); await p.fill('#svStart', '2026-10-12');
  await p.locator('#svSave').click(); await p.waitForTimeout(900);
  check('a line can run for a term from a start date',
    (await p.locator('#crmServices').innerText()).includes('2,160') &&
    (await p.locator('#crmServices').innerText()).includes('6 months from 12 Oct 2026'));
  check('engagements show on an active client', await p.locator('#crmEngage').isVisible());
  await p.locator('#crmCover').click(); await p.waitForTimeout(900);
  check('the letter takes the quoted line only, with SST', await p.evaluate(() => {
    const d = window.__DB.client_documents.find(x => x.client_id === 'c1');
    return !!d && d.lines.length === 1 && d.subtotal === 2160 && d.tax === 172.8 && d.total === 2332.8 && d.bill_to.email === 'lim@lc.com';
  }));
  await p.locator('#crmDocuments .doc-row:not(.crm-head)').first().locator('select[data-f="state"]').selectOption('void'); await p.waitForTimeout(600);
  check('a document can be voided and stays listed', await p.locator('#crmDocuments .doc-row.is-off').count() === 1 &&
    await p.evaluate(() => window.__DB.client_documents.length === 3));
  // the voided row keeps a working menu, and only a voided document can be deleted
  await p.locator('#crmDocuments .doc-row.is-off [data-a="menu"]').click(); await p.waitForTimeout(250);
  check('a voided document still opens its menu', await p.locator('#crmDocuments .doc-row.is-off [data-a="del"]').isVisible());
  await p.locator('#crmDocuments .doc-row.is-off [data-a="del"]').click(); await p.waitForTimeout(600);
  check('a voided document can be deleted', await p.locator('#crmDocuments .doc-row:not(.crm-head)').count() === 0 &&
    await p.evaluate(() => window.__DB.client_documents.length === 2));
  await p.locator('#crmBack').click(); await p.waitForTimeout(600);
  await p.locator('.crm-row').filter({ hasText: 'Star Living' }).click(); await p.waitForTimeout(800);

  // the brand profile is its own fold with its own save
  await p.locator('#crmBrandToggle').click(); await p.waitForTimeout(300);
  await p.fill('#crmSocialIg', '@starliving');
  await p.fill('#crmNotes', 'Warm, family first. No hard sell.');
  await p.locator('#crmBrandSave').click(); await p.waitForTimeout(800);
  check('brand links and notes save together',
    await p.evaluate(() => { const c = window.__DB.clients.find(c => c.name === 'Star Living'); return c.social_ig === '@starliving' && /family/.test(c.brand_notes); }));
  check('the head shows the link', await p.locator('#crmLinks .plink').count() >= 1);
  await p.locator('#crmBack').click(); await p.waitForTimeout(800);
  check('the pipeline group carries its value', (await p.locator('.crm-group-worth').first().innerText()).includes('28,490'));
  check('next actions are gathered at the top of the list', await p.locator('#crmDue').isVisible() &&
    (await p.locator('.due-row').count()) >= 1);
  check('the overdue one is marked', await p.locator('.due-row.is-due').count() >= 1);
  await p.locator('.due-row [data-a="done"]').first().click(); await p.waitForTimeout(600);
  check('done clears it from the strip', await p.locator('.due-row').count() === 0 || await p.locator('#crmDue').isHidden());

  // Content Review no longer creates clients
  await p.locator('.navitem[data-section="review"]').click(); await p.waitForTimeout(500);
  check('Content Review no longer offers to create a client',
    await p.locator('#addClientBox').count() === 0 && await p.locator('#goToCrm').isVisible());
  await p.waitForTimeout(500);
  const reviewNames = await p.locator('#clientCards .bigcard-name').allInnerTexts();
  console.log('  content review lists: ' + reviewNames.join(', '));
  check('Content Review lists only active clients', reviewNames.indexOf('Star Living') < 0 && reviewNames.indexOf('Laman Citra') > -1);
  await p.locator('#goToCrm').click(); await p.waitForTimeout(500);
  check('and sends you to the CRM instead', await p.locator('#sectionClients').isVisible());

  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  if (errs.length) bad++;
  await b.close();
  console.log(bad ? 'crm: PROBLEM' : 'crm: ok');
})();
