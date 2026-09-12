// The client portal: one sign-in, one client, requests the team answers.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
let bad = 0;
const check = (l, ok, extra) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (extra ? '  ' + extra : '')); if (!ok) bad++; };

// Laman Citra with a portal contact, a confirmed line, a quoted line, a
// letter, a published content set and a campaign in production.
const SEED = `
(function(){
  var D = window.__DB;
  D.client_requests = D.client_requests || [];
  if (D.client_services.some(function (s) { return s.id === 'pv1'; })) return;
  D.client_contacts.forEach(function (c) { if (c.id === 'ct1') { c.portal_access = true; c.email = 'lim@lc.com'; } });
  D.client_contacts.push({ id:'pct2', client_id:'c1', name:'Ms Tan', role:'Finance', phone:'0198887777', email:'tan@lc.com', lang:'zh', is_primary:false, portal_access:false });
  D.client_contacts.push({ id:'pct3', client_id:'c1', name:'Ms Ng', role:'Marketing', email:'fail@lc.com', lang:'en', is_primary:false, portal_access:false });
  D.client_services.push({ id:'pv1', client_id:'c1', service_slug:'pkg-b', label:'Package B · 2 platforms · 4 contents', unit:'Per month, 6 month minimum', qty:1, rate:2830, tenure:6, start_on:'2026-10-12', state:'confirmed', created_at:'2026-09-01T00:00:00Z' });
  D.client_services.push({ id:'pv2', client_id:'c1', service_slug:'koc-10', label:'KOC package · 10 creators', unit:'Per campaign', qty:1, rate:4500, tenure:1, start_on:null, state:'quoted', created_at:'2026-09-02T00:00:00Z' });
  D.client_services.push({ id:'pv3', client_id:'c1', service_slug:null, label:'Launch video', unit:'One on-site shoot', qty:1, rate:20000, tenure:1, state:'enquired', created_at:'2026-09-03T00:00:00Z' });
  D.client_documents.push({ id:'pd1', client_id:'c1', kind:'offer', number:'AQT/INT/2609001', issued_at:'2026-09-12', market:'MY',
    subtotal:4500, tax:360, total:4860, issued_by:'Qiao Rou', created_at:'2026-09-12T00:00:00Z',
    bill_to:{ name:'Laman Citra', legal_name:'LAMAN CITRA SDN BHD', contact:'Mr Lim', contact_role:'Director', address:'JB' },
    lines:[{ label:'KOC package · 10 creators', unit:'Per campaign', qty:1, rate:4500, tenure:1, state:'quoted', tax:true }] });
  D.batches.push({ id:'pb1', client_id:'c1', title:'Sept 2026', published:true });
  D.campaigns.push({ id:'pcq', client_id:'c1', title:'Laman Citra phase 2', title_zh:'第二期推广', slots:10, state:'production', deliverable:'video', push_format:'site_visit', access_token:'Q1' });
  D.clients.forEach(function (c) { if (c.id === 'c1') c.access_token = 'R1'; });
  window.__persist && window.__persist();
})();
`;

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1200, height: 1000 } });
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('dialog', d => d.accept());
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: `
    window.__drawn = [];
    window.PDFLib = { rgb: () => ({}), StandardFonts: { Helvetica: 'H', HelveticaBold: 'HB' },
      PDFDocument: { create: () => Promise.resolve({
        embedFont: () => Promise.resolve({ widthOfTextAtSize: (s, z) => String(s).length * z * 0.5 }),
        addPage: () => ({ drawText: (s) => window.__drawn.push(String(s)), drawLine: () => {} }),
        save: () => Promise.resolve(new Uint8Array([37, 80, 68, 70])) }) } };` }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  // --- signed out ---
  await p.goto('http://127.0.0.1:8899/client/', { waitUntil: 'networkidle' });
  await p.waitForTimeout(400);
  check('signed out, the page is the sign-in cover', await p.locator('#stateBox').isVisible() &&
    (await p.locator('#stateTitle').innerText()) === 'Client sign-in' && await p.locator('#signForm').isVisible());
  check('the header holds no sign out yet', await p.locator('#portalOut').isHidden());
  await p.locator('#signGo').click(); await p.waitForTimeout(200);
  check('an email is required', /required/.test(await p.locator('#stateMsg').innerText()));
  await p.fill('#signEmail', 'lim@lc.com');
  await p.locator('#signGo').click(); await p.waitForTimeout(300);
  check('the link is sent and the page says where', (await p.locator('#stateTitle').innerText()) === 'Check your email' &&
    (await p.locator('#stateText').innerText()).includes('lim@lc.com'));

  // --- an email not on any client ---
  await p.evaluate(() => window.__signIn('nobody@example.com')); await p.waitForTimeout(500);
  check('an unlisted email gets Access not assigned', (await p.locator('#stateTitle').innerText()) === 'Access not assigned' &&
    await p.locator('#app').isHidden());
  check('sign out is offered to the unlisted person', await p.locator('#portalOut').isVisible());

  // --- the client ---
  await p.evaluate(() => window.__signIn('lim@lc.com')); await p.waitForTimeout(600);
  check('the listed email opens the portal', await p.locator('#app').isVisible() && await p.locator('#stateBox').isHidden());
  const facts = await p.locator('#ovFacts').innerText();
  check('the company as registered', facts.includes('LAMAN CITRA SDN BHD') && facts.includes('202201012345') && facts.includes('Malaysia · RM'));
  check('the account manager and the status', facts.includes('Qiao Rou') && facts.includes('Active'));
  check('one company: no company select', await p.locator('#clientPick').isHidden());
  check('contacts listed with the main contact and portal marks',
    await p.locator('#ovContacts .ct-row:not(.crm-head)').count() === 3 &&
    (await p.locator('#ovContacts').innerText()).includes('Main contact') &&
    (await p.locator('#ovContacts').innerText()).includes('Portal'));
  check('no ⋯ on a contact row', await p.locator('#ovContacts .kmenu-btn').count() === 0);

  const svc = await p.locator('#svcBox').innerText();
  check('confirmed and quoted lines shown, the enquiry kept back',
    await p.locator('#svcBox .csv-row:not(.crm-head)').count() === 2 && !svc.includes('Launch video'));
  check('the term and the amount', svc.includes('6 months from 12 Oct 2026') && svc.includes('RM 16,980.00'));
  check('the totals', svc.includes('Quoted') && svc.includes('RM 4,500.00') && svc.includes('Confirmed'));
  check('a chip, not a select, for a state the client only reads', await p.locator('#svcBox select').count() === 0 &&
    await p.locator('#svcBox .chip-state').count() === 2);
  check('the confirmed line offers a change; the quoted one does not', await p.locator('#svcBox .kmenu-btn').count() === 1);
  check('no requests yet: the section is not there', await p.locator('#rqWrap').isHidden());

  const docs = await p.locator('#docBox').innerText();
  check('the letter is listed by number', docs.includes('AQT/INT/2609001') && docs.includes('Letter of Offer') && docs.includes('RM 4,860.00'));
  await p.locator('#docBox .kmenu-btn').scrollIntoViewIfNeeded(); await p.waitForTimeout(300);
  await p.locator('#docBox .kmenu-btn').click(); await p.waitForTimeout(200);
  await p.locator('#docBox [data-a="download"]').click(); await p.waitForTimeout(500);
  check('the letter is drawn from its snapshot', await p.evaluate(() => (window.__drawn || []).join(' ').includes('AQT/INT/2609001') &&
    (window.__drawn || []).join(' ').includes('LAMAN CITRA SDN BHD')));

  const eng = await p.locator('#engBox').innerText();
  check('engagements link the two client pages', await p.locator('#engWrap').isVisible() && eng.includes('Content Review') &&
    eng.includes('Laman Citra phase 2') && eng.includes('In production'));
  const hrefs = await p.locator('#engBox a').evaluateAll(as => as.map(a => a.getAttribute('href')));
  check('each opens with its own token', hrefs.includes('/review/?k=R1') && hrefs.includes('/creators/?k=Q1'));
  check('account lists who can sign in', (await p.locator('#accBox').innerText()).includes('Mr Lim') &&
    !(await p.locator('#accBox').innerText()).includes('Ms Tan'));
  check('no bank line: no payment section', await p.locator('#payWrap').isHidden());

  // --- a request ---
  await p.locator('#svcBox .kmenu-btn').scrollIntoViewIfNeeded(); await p.waitForTimeout(300);
  await p.locator('#svcBox .kmenu-btn').click(); await p.waitForTimeout(200);
  check('upgrade, downgrade and cancel in the ⋯', await p.locator('#svcBox [data-a="upgrade"]').isVisible() &&
    await p.locator('#svcBox [data-a="cancel"]').isVisible());
  await p.locator('#svcBox [data-a="upgrade"]').click(); await p.waitForTimeout(300);
  check('the sheet names the line', await p.locator('#reqSheet').isVisible() && (await p.locator('#reqFacts').innerText()).includes('Package B'));
  await p.locator('#reqGo').click(); await p.waitForTimeout(200);
  check('an upgrade needs a note', /required/.test(await p.locator('#reqMsg').innerText()));
  await p.fill('#reqNote', 'Package C from November');
  await p.locator('#reqGo').click(); await p.waitForTimeout(600);
  check('the request is recorded against the line', await p.evaluate(() => {
    const r = window.__DB.client_requests[0];
    return r && r.kind === 'upgrade' && r.service_id === 'pv1' && r.service_label.includes('Package B') && r.state === 'requested' && r.contact_name === 'Mr Lim';
  }));
  check('and logged', await p.evaluate(() => window.__DB.activity_log.some(a => a.action === 'request.raised')));
  check('the section appears with the request', await p.locator('#rqWrap').isVisible() &&
    (await p.locator('#rqBox').innerText()).includes('Upgrade · Package B') && (await p.locator('#rqBox').innerText()).includes('Requested'));
  check('no fee yet: the currency sign in mute', (await p.locator('#rqBox .svc-amt').innerText()).trim() === 'RM');

  await p.locator('#rqBox .kmenu-btn').scrollIntoViewIfNeeded(); await p.waitForTimeout(300);
  await p.locator('#rqBox .kmenu-btn').click(); await p.waitForTimeout(200);
  await p.locator('#rqBox [data-a="withdraw"]').click(); await p.waitForTimeout(500);
  check('withdrawn, with a way back', (await p.locator('#rqBox').innerText()).includes('Withdrawn') && await p.locator('#rqUndo').isVisible());
  await p.locator('#rqUndo button').click(); await p.waitForTimeout(500);
  check('undo puts it back', (await p.locator('#rqBox').innerText()).includes('Requested') &&
    await p.evaluate(() => window.__DB.client_requests[0].withdrawn_at === null));

  await p.locator('#ovRequest').click(); await p.waitForTimeout(300);
  await p.fill('#reqNote', 'New address: 12 Jalan Baru');
  await p.locator('#reqGo').click(); await p.waitForTimeout(600);
  check('a change of details carries no line', await p.evaluate(() => window.__DB.client_requests.some(r => r.kind === 'details' && !r.service_id)));

  // --- Chinese ---
  await p.locator('#langToggle').click(); await p.waitForTimeout(400);
  const zh = await p.locator('#app').innerText();
  check('the page reads in Chinese', zh.includes('服务') && zh.includes('已确认') && zh.includes('已提交') && zh.includes('第二期推广'));
  await p.locator('#langToggle').click(); await p.waitForTimeout(300);

  // --- the console side, in the same tab so the stand-in's data is shared ---
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  const a = p;
  await a.goto('http://127.0.0.1:8899/admin/?s=clients&client=c1', { waitUntil: 'networkidle' });
  await a.evaluate(() => window.__signIn('adspacestudios@gmail.com')); await a.waitForTimeout(900);
  check('the console shows the requests', await a.locator('#crmRequests').isVisible() &&
    await a.locator('#crmRequestList .doc-row:not(.crm-head)').count() === 2);
  check('the request row: who, what, a state select', (await a.locator('#crmRequestList').innerText()).includes('Mr Lim') &&
    await a.locator('#crmRequestList .state-select').count() === 2);
  const upgradeRow = a.locator('#crmRequestList .doc-row:not(.crm-head)', { hasText: 'Upgrade' });
  await upgradeRow.locator('.state-select').selectOption('reviewing'); await a.waitForTimeout(400);
  check('the state moves and is logged', await a.evaluate(() => window.__DB.client_requests.some(r => r.kind === 'upgrade' && r.state === 'reviewing') &&
    window.__DB.activity_log.some(x => x.action === 'request.changed')));
  await upgradeRow.locator('.kmenu-btn').scrollIntoViewIfNeeded(); await a.waitForTimeout(300);
  await upgradeRow.locator('.kmenu-btn').click(); await a.waitForTimeout(200);
  await upgradeRow.locator('[data-a="reply"]').click(); await a.waitForTimeout(200);
  check('reply opens with the fee and the note', await a.locator('#crmReplyBox').isVisible());
  await a.fill('#rqFee', '500'); await a.fill('#rqReply', 'Package C from 1 Nov, pro rated.');
  await a.locator('#rqSave').click(); await a.waitForTimeout(500);
  check('the fee and the reply are saved by name', await a.evaluate(() => {
    const r = window.__DB.client_requests.find(x => x.kind === 'upgrade');
    return r.fee === 500 && /pro rated/.test(r.reply) && r.decided_by === 'ADspace';
  }));
  check('the console prints the fee', (await a.locator('#crmRequestList').innerText()).includes('RM 500.00'));

  // portal access is a switch on the contact
  const lim = a.locator('#crmContacts .ct-row:not(.crm-head)', { hasText: 'Mr Lim' });
  check('the contact carries the Portal mark', (await lim.innerText()).includes('Portal'));
  await lim.locator('[data-a="menu"]').scrollIntoViewIfNeeded(); await a.waitForTimeout(300);
  await lim.locator('[data-a="menu"]').click(); await a.waitForTimeout(200);
  check('the ⋯ offers to remove it', await a.locator('#crmContacts [data-a="unportal"]').isVisible());
  await a.locator('#crmContacts [data-a="unportal"]').click(); await a.waitForTimeout(500);
  check('removed, logged, with Undo', await a.evaluate(() => window.__DB.client_contacts.find(c => c.id === 'ct1').portal_access === false &&
    window.__DB.activity_log.some(x => x.action === 'contact.portal_off')) && await a.locator('#crmUndo').isVisible());
  await a.locator('#crmUndo button').click(); await a.waitForTimeout(500);
  check('undo restores access and asks for the login', await a.evaluate(() => window.__DB.client_contacts.find(c => c.id === 'ct1').portal_access === true &&
    (window.__signed || []).some(s => s.name === 'invite-member' && s.body && s.body.kind === 'client' && s.body.email === 'lim@lc.com')));
  const tan = a.locator('#crmContacts .ct-row:not(.crm-head)', { hasText: 'Ms Tan' });
  await tan.locator('[data-a="menu"]').scrollIntoViewIfNeeded(); await a.waitForTimeout(300);
  await tan.locator('[data-a="menu"]').click(); await a.waitForTimeout(200);
  await tan.locator('[data-a="portal"]').click(); await a.waitForTimeout(500);
  check('a second contact can be let in', await a.evaluate(() => window.__DB.client_contacts.find(c => c.id === 'pct2').portal_access === true));
  check('and told the invitation went', (await a.locator('#crmWorkMsg').innerText()).includes('Invitation sent to tan@lc.com'));
  const ng = a.locator('#crmContacts .ct-row:not(.crm-head)', { hasText: 'Ms Ng' });
  await ng.locator('[data-a="menu"]').scrollIntoViewIfNeeded(); await a.waitForTimeout(300);
  await ng.locator('[data-a="menu"]').click(); await a.waitForTimeout(200);
  await ng.locator('[data-a="portal"]').click(); await a.waitForTimeout(500);
  check('a failed invitation says why, in the function\'s own words', (await a.locator('#crmWorkMsg').innerText()).includes('Error sending invite email') &&
    await a.evaluate(() => window.__DB.client_contacts.find(c => c.id === 'pct3').portal_access === true));
  await ng.locator('[data-a="menu"]').click(); await a.waitForTimeout(200);
  await ng.locator('[data-a="unportal"]').click(); await a.waitForTimeout(400);
  await tan.locator('[data-a="menu"]').scrollIntoViewIfNeeded(); await a.waitForTimeout(300);
  await tan.locator('[data-a="menu"]').click(); await a.waitForTimeout(200);
  await tan.locator('[data-a="unportal"]').click(); await a.waitForTimeout(500);
  await a.evaluate(() => { window.__DB.client_contacts.find(c => c.id === 'ct1').portal_access = false; window.__persist(); });

  // the portal reads the answer; without the switch the same email is not let in
  await p.goto('http://127.0.0.1:8899/client/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('lim@lc.com')); await p.waitForTimeout(600);
  check('without the switch the same email is not let in', (await p.locator('#stateTitle').innerText()) === 'Access not assigned');
  await p.evaluate(() => { window.__DB.client_contacts.find(c => c.id === 'ct1').portal_access = true; window.__persist(); });
  await p.goto('http://127.0.0.1:8899/client/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('lim@lc.com')); await p.waitForTimeout(600);
  const rq = await p.locator('#rqBox').innerText();
  check('the client sees the state, the fee and the reply', rq.includes('Reviewing') && rq.includes('RM 500.00') && rq.includes('pro rated'));
  check('a request under review can no longer be withdrawn',
    await p.locator('#rqBox .doc-row', { hasText: 'Upgrade' }).locator('.kmenu-btn').count() === 0);

  console.log('errors: ' + (errs.length ? errs.join(' | ') : 'none'));
  console.log(bad || errs.length ? 'portal: PROBLEM (' + bad + ' fail)' : 'portal: ok');
  await b.close();
  process.exit(bad || errs.length ? 1 : 0);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
