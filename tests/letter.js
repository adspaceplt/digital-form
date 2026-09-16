/*
 * The Letter of Offer and the service lifecycle, driven the way a person
 * drives them.
 *
 * The fault this proves gone: `client_services.state` was both the commercial
 * state of a service and the selection set for the next letter, so a line
 * already sent to a client on one letter was silently carried into the next —
 * issuing correctly confirms nothing, which is exactly what left it at
 * `quoted` for the following letter to pick up. A letter is issued for the
 * services somebody chose now, and only a verified signature confirms them.
 *
 * The rules are asserted against the real functions in tests/sql.js. This
 * suite is the other half: that the console offers the right lines, refuses
 * the wrong ones, and cannot be made to issue twice.
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');

let bad = 0;
const errs = [];
const check = (l, ok, x) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (x ? '  ' + x : '')); if (!ok) bad++; };

/* One client with a line confirmed months ago off a letter that was signed and
   verified, one new enquiry priced and marked To quote, one still enquired,
   and a letter from before this change that has no mappings at all. */
const SEED = `(function(){ var D = window.__DB;
  var c = D.clients.filter(function(x){ return x.id === 'c1'; })[0];
  c.stage = 'active'; c.owner = 'Qiao Rou';
  D.client_services.push({ id:'sv_old', client_id:'c1', label:'Social media management',
    qty:1, rate:3200, tenure:6, start_on:'2026-03-01', state:'confirmed', unit:'per month' });
  D.client_services.push({ id:'sv_new', client_id:'c1', label:'Paid advertising',
    qty:1, rate:1500, tenure:3, start_on:'2026-10-01', state:'quoted', unit:'per month' });
  D.client_services.push({ id:'sv_two', client_id:'c1', label:'SEO retainer',
    qty:1, rate:800, tenure:6, state:'quoted', unit:'per month' });
  D.client_services.push({ id:'sv_enq', client_id:'c1', label:'Photography day',
    qty:1, rate:1200, tenure:1, state:'enquired', unit:'per day' });
  D.client_documents.push({ id:'doc_old', client_id:'c1', kind:'offer',
    number:'AQT/INT/2603001', issued_at:'2026-03-02', market:'MY',
    subtotal:19200, tax:1536, total:20736, issued_by:'Qiao Rou',
    bill_to:{ name:'Laman Citra' }, signed_at:'2026-03-05T00:00:00Z',
    lines:[{ label:'Social media management', qty:1, rate:3200, tenure:6 }],
    created_at:'2026-03-02T09:00:00Z', voided_at:null });
  window.__persist && window.__persist(); })();`;

const open = async (ctx, seed) => {
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + (seed || SEED) }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib={};' }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/?s=clients&client=laman-citra', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(1300);
  return p;
};

/* The client record is a workspace with panes, so a section's controls live in
   the pane that owns them. `pane()` is what a person does with the tab strip;
   every interaction below opens its own section first. */
const pane = async (p, k) => {
  await p.locator('#crmTabs .tab[data-pane="' + k + '"]').click();
  await p.waitForTimeout(300);
};

const svcState = (p, id) => p.evaluate(i =>
  (window.__DB.client_services.filter(s => s.id === i)[0] || {}).state, id);
const docs = p => p.evaluate(() => window.__DB.client_documents
  .filter(d => String(d.number).indexOf('AQL/') === 0)
  .map(d => ({ number: d.number, lines: (d.lines || []).map(l => l.label),
               signed: !!d.signed_at, verified: !!d.verified_at, voided: !!d.voided_at })));

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 1000 } });

  // ---- The Client ID gate --------------------------------------------------
  let p = await open(ctx);
  await pane(p, 'documents');
  await p.locator('#crmCover').click();
  await p.waitForTimeout(400);
  check('without a Client ID the sheet does not open',
    await p.locator('#pickSheet').evaluate(e => e.hidden));
  check('and the record says what to do about it',
    /Client ID/.test(await p.locator('#crmDocMsg').innerText()),
    (await p.locator('#crmDocMsg').innerText()).trim());

  // Typed the way it is stored.
  await p.locator('#crmEdit').click();
  await p.waitForTimeout(400);
  await p.locator('#crmClientCode').fill('');
  await p.locator('#crmClientCode').type('ac 180/x');
  check('a Client ID is normalised as it is typed',
    (await p.locator('#crmClientCode').inputValue()) === 'AC180X',
    await p.locator('#crmClientCode').inputValue());
  await p.locator('#crmClientCode').fill('AC180');
  await p.locator('#crmSave').click();
  await p.waitForTimeout(700);
  check('and is stored on the client',
    (await p.evaluate(() => window.__DB.clients.filter(c => c.id === 'c1')[0].client_code)) === 'AC180');
  check('and reads on the record',
    /AC180/.test(await p.locator('#crmFacts').innerText()));

  // ---- What the sheet offers ----------------------------------------------
  await pane(p, 'documents');
  await p.locator('#crmCover').click();
  await p.waitForTimeout(500);
  check('the sheet opens once there is a Client ID',
    !(await p.locator('#pickSheet').evaluate(e => e.hidden)));
  const groups = await p.locator('#pickBody .svc-cat').allTextContents();
  check('it separates what may be quoted from what may not', groups.length >= 2,
    groups.map(s => s.trim()).join(' / '));
  const ticked = await p.evaluate(() => [...document.querySelectorAll('#pickBody input')]
    .filter(i => i.checked).map(i => i.closest('.lpickrow').querySelector('b').textContent));
  check('only the To quote lines are ticked',
    ticked.length === 2 && ticked.indexOf('Paid advertising') > -1 && ticked.indexOf('SEO retainer') > -1,
    ticked.join(', '));
  const shownConfirmed = await p.evaluate(() => [...document.querySelectorAll('#pickBody .lpickrow')]
    .filter(r => r.querySelector('b').textContent === 'Social media management')
    .map(r => ({ checked: r.querySelector('input').checked, off: r.querySelector('input').disabled }))[0]);
  check('the confirmed line is shown and left unticked',
    shownConfirmed && shownConfirmed.checked === false, JSON.stringify(shownConfirmed));
  check('an enquired line is not offered at all',
    !(await p.locator('#pickBody').innerText()).includes('Photography day'));

  // ---- Issuing carries only what was chosen, and confirms nothing ---------
  await p.evaluate(() => {
    // Take SEO retainer off: a letter is for the services somebody chose.
    const r = [...document.querySelectorAll('#pickBody .lpickrow')]
      .filter(x => x.querySelector('b').textContent === 'SEO retainer')[0];
    r.querySelector('input').click();
  });
  await p.waitForTimeout(250);
  check('the running total follows the ticks',
    /1 service/.test(await p.locator('#pickSum').innerText()),
    (await p.locator('#pickSum').innerText()).trim());
  await p.locator('#pickGo').click();
  await p.waitForTimeout(1200);
  let list = await docs(p);
  check('one letter is issued', list.length === 1, JSON.stringify(list));
  check('and carries only the service that was chosen',
    list[0] && list[0].lines.length === 1 && list[0].lines[0] === 'Paid advertising',
    JSON.stringify(list[0] && list[0].lines));
  check('its serial is AQL/AC180/YYMM01', /^AQL\/AC180\/\d{4}01$/.test(list[0].number), list[0].number);
  check('issuing confirms nothing', (await svcState(p, 'sv_new')) === 'quoted');
  check('the confirmed line is untouched', (await svcState(p, 'sv_old')) === 'confirmed');
  check('and the To quote line left off it stays To quote', (await svcState(p, 'sv_two')) === 'quoted');

  // ---- A line already on a live letter is not offered again ---------------
  await pane(p, 'documents');
  await p.locator('#crmCover').click();
  await p.waitForTimeout(500);
  const held = await p.evaluate(() => [...document.querySelectorAll('#pickBody .lpickrow')]
    .filter(r => r.querySelector('b').textContent === 'Paid advertising')
    .map(r => ({ off: r.querySelector('input').disabled, why: r.innerText.replace(/\n/g, ' ') }))[0]);
  check('a line already on a live letter cannot be ticked', held && held.off === true, JSON.stringify(held));
  check('and the row says which letter holds it', held && /AQL\/AC180\//.test(held.why), held && held.why);
  await p.locator('#pickCancel').click();
  await p.waitForTimeout(250);

  // ---- Signing confirms nothing; verification confirms only its own -------
  const openMenu = async (n) => {
    await p.evaluate(i => {
      const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
      rows[i].querySelector('[data-a="menu"]').click();
    }, n);
    await p.waitForTimeout(250);
  };
  const rowIdx = await p.evaluate(() => [...document.querySelectorAll('#crmDocuments .doc-row')]
    .filter(r => !r.classList.contains('crm-head'))
    .findIndex(r => /AQL\//.test(r.innerText)));
  await openMenu(rowIdx);
  check('a fresh letter offers Mark signed and not Verify',
    (await p.evaluate(i => {
      const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
      return [...rows[i].querySelectorAll('.kmenu-item')].map(x => x.innerText.trim()).join('|');
    }, rowIdx)).includes('Mark signed'));
  await p.evaluate(i => {
    const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
    rows[i].querySelector('[data-a="sign"]').click();
  }, rowIdx);
  await p.waitForTimeout(900);
  list = await docs(p);
  check('marking signed moves the letter', list[0].signed === true);
  check('and confirms nothing', (await svcState(p, 'sv_new')) === 'quoted');
  check('the row reads Signed',
    /Signed/.test(await p.locator('#crmDocuments').innerText()));

  /* The client's value is the confirmed total, and verifying is what confirms
     a line, so verifying is what moves it. It was not moving: verify repainted
     the documents and the services and never called syncValue, so the record
     kept the old figure until something else happened to save a line. */
  const valueNow = async () => {
    const t = await p.locator('#crmFacts').innerText();
    return t.replace(/\s+/g, ' ');
  };
  const valueBefore = await valueNow();

  p.once('dialog', d => d.accept());
  await openMenu(rowIdx);
  await p.evaluate(i => {
    const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
    rows[i].querySelector('[data-a="verify"]').click();
  }, rowIdx);
  await p.waitForTimeout(1400);
  check('verifying confirms the line the letter captured',
    (await svcState(p, 'sv_new')) === 'confirmed');
  check('and nothing else', (await svcState(p, 'sv_two')) === 'quoted');
  check('the already confirmed line is untouched', (await svcState(p, 'sv_old')) === 'confirmed');
  check('and the enquired one is untouched', (await svcState(p, 'sv_enq')) === 'enquired');
  list = await docs(p);
  check('the letter reads Verified', list[0].verified === true);
  const valueAfter = await valueNow();
  check('and the client\'s value follows the confirmation',
    valueAfter !== valueBefore && /24,200/.test(valueAfter),
    'before: ' + valueBefore.slice(0, 110) + '  ||  after: ' + valueAfter.slice(0, 110));

  // ---- The legacy letter stays history ------------------------------------
  const legacy = await p.evaluate(() => {
    const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
    const r = rows.filter(x => /AQT\/INT\//.test(x.innerText))[0];
    if (!r) return 'missing';
    r.querySelector('[data-a="menu"]').click();
    return [...r.querySelectorAll('.kmenu-item')].map(x => x.innerText.trim()).join('|');
  });
  check('a letter from before the change is readable', legacy !== 'missing', legacy);
  check('and is never offered verification', !/Verify/.test(legacy), legacy);

  // ---- Editing a service afterwards does not rewrite the snapshot ---------
  await p.evaluate(() => {
    const s = window.__DB.client_services.filter(x => x.id === 'sv_new')[0];
    s.label = 'Paid advertising RENAMED'; s.rate = 9999;
  });
  list = await docs(p);
  check('editing a service does not rewrite the issued snapshot',
    list[0].lines[0] === 'Paid advertising', list[0].lines[0]);
  await p.close();

  // ---- One submission, one letter -----------------------------------------
  p = await open(ctx, SEED + `(function(){
    window.__DB.clients.filter(function(c){ return c.id === 'c1'; })[0].client_code = 'AC180';
    window.__persist && window.__persist(); })();`);
  await pane(p, 'documents');
  await p.locator('#crmCover').click();
  await p.waitForTimeout(500);
  await p.evaluate(() => {
    const go = document.getElementById('pickGo');
    go.click(); go.click(); go.click();
  });
  await p.waitForTimeout(1600);
  list = await docs(p);
  check('three presses of Issue letter make one letter', list.length === 1, JSON.stringify(list.map(d => d.number)));
  check('and spend one serial', /01$/.test(list[0].number), list[0].number);
  check('the control is shut while the request is in flight',
    await p.evaluate(() => {
      const go = document.getElementById('pickGo');
      return go.disabled === false; // back on afterwards
    }));

  // ---- Confirmed is not a state this row may set --------------------------
  await pane(p, 'services');
  const opts = await p.evaluate(() => {
    const sel = [...document.querySelectorAll('#crmServices .csv-row [data-f="state"]')][0];
    return sel ? [...sel.options].map(o => o.value).join(',') : '(none)';
  });
  check('Confirmed is not in the per service dropdown', !/confirmed/.test(opts), opts);
  check('and a confirmed line reads as a chip instead',
    await p.evaluate(() => [...document.querySelectorAll('#crmServices .csv-row')]
      .some(r => /Social media management/.test(r.innerText) && r.querySelector('.svc-state .tone'))));


  // ---- Voiding and deleting, as the console drives them --------------------
  // Both ask in a sheet: one needs a reason, the other needs the reference
  // typed back. Neither is a question a browser confirm() can carry.
  await p.close();
  p = await open(ctx, SEED + `(function(){
    window.__DB.clients.filter(function(c){ return c.id === 'c1'; })[0].client_code = 'AC180';
    window.__persist && window.__persist(); })();`);
  await pane(p, 'documents');
  await p.locator('#crmCover').click();
  await p.waitForTimeout(500);
  await p.locator('#pickGo').click();
  await p.waitForTimeout(1200);

  const rowOf = () => p.evaluate(() => [...document.querySelectorAll('#crmDocuments .doc-row')]
    .filter(r => !r.classList.contains('crm-head'))
    .findIndex(r => /AQL\//.test(r.innerText)));
  const items = async () => {
    const i = await rowOf();
    return p.evaluate(n => {
      const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
      return [...rows[n].querySelectorAll('.kmenu-item')]
        .filter(x => getComputedStyle(x).display !== 'none')
        .map(x => x.innerText.trim()).join('|');
    }, i);
  };
  const act = async (a) => {
    const i = await rowOf();
    await p.evaluate(([n, name]) => {
      const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
      rows[n].querySelector('[data-a="menu"]').click();
      rows[n].querySelector('[data-a="' + name + '"]').click();
    }, [i, a]);
    await p.waitForTimeout(400);
  };

  check('an issued letter offers Delete permanently and not Void',
    /Delete permanently/.test(await items()) && !/Void letter/.test(await items()), await items());

  // Signed, then verified, so there is a confirmation to reverse.
  await act('sign'); await p.waitForTimeout(600);
  p.once('dialog', d => d.accept());
  await act('verify'); await p.waitForTimeout(900);
  check('the line is confirmed by the verification', (await svcState(p, 'sv_new')) === 'confirmed');
  check('a verified letter offers Void letter', /Void letter/.test(await items()), await items());

  // Void: the sheet, the reason, and what it says it will do.
  await act('void');
  check('voiding opens a sheet rather than a browser dialog',
    !(await p.locator('#voidSheet').evaluate(e => e.hidden)));
  check('and the sheet says what goes back',
    /puts back the service lines/.test(await p.locator('#voidWhat').innerText()));
  await p.locator('#voidGo').click();
  await p.waitForTimeout(400);
  check('it refuses an empty reason',
    /reason is required/i.test(await p.locator('#voidMsg').innerText()),
    (await p.locator('#voidMsg').innerText()).trim());
  check('and the letter is untouched', (await svcState(p, 'sv_new')) === 'confirmed');
  await p.locator('#voidReason').fill('Client changed the scope');
  await p.locator('#voidGo').click();
  await p.waitForTimeout(1200);
  check('a reason voids it', (await docs(p))[0].voided === true);
  check('and the line it alone confirmed goes back to To quote',
    (await svcState(p, 'sv_new')) === 'quoted', await svcState(p, 'sv_new'));
  check('the line confirmed months ago is untouched', (await svcState(p, 'sv_old')) === 'confirmed');
  check('the reason is kept with the letter',
    (await p.evaluate(() => window.__DB.client_documents
      .filter(d => /AQL\//.test(d.number))[0].void_reason)) === 'Client changed the scope');
  check('a voided letter is no longer offered Void',
    !/Void letter/.test(await items()), await items());

  // Delete: the reference typed back, exactly.
  const number = (await docs(p))[0].number;
  await act('del');
  check('deleting opens its own sheet',
    !(await p.locator('#delSheet').evaluate(e => e.hidden)));
  check('and says the deletion cannot be undone',
    /cannot be undone/.test(await p.locator('#delWhat').innerText()));
  await p.locator('#delConfirm').fill('AQL/AC180/999999');
  await p.locator('#delReason').fill('Wrong client');
  await p.locator('#delGo').click();
  await p.waitForTimeout(400);
  check('a reference that does not match is refused',
    /Type AQL/.test(await p.locator('#delMsg').innerText()),
    (await p.locator('#delMsg').innerText()).trim());
  check('and the letter is still there', (await docs(p)).length === 1);
  await p.locator('#delConfirm').fill(number);
  await p.locator('#delReason').fill('');
  await p.locator('#delGo').click();
  await p.waitForTimeout(400);
  check('an empty reason is refused even with the right reference',
    /reason is required/i.test(await p.locator('#delMsg').innerText()));
  await p.locator('#delReason').fill('Issued against the wrong client');
  await p.locator('#delGo').click();
  await p.waitForTimeout(1400);
  check('the reference and a reason delete it', (await docs(p)).length === 0,
    JSON.stringify(await docs(p)));
  check('and a minimal audit event is left behind',
    await p.evaluate(n => (window.__DB.client_document_deletions || [])
      .some(x => x.number === n && x.reason === 'Issued against the wrong client' && !('lines' in x)), number));

  // A serial that has been spent is never handed out again.
  await p.locator('#crmCover').click();
  await p.waitForTimeout(500);
  await p.locator('#pickGo').click();
  await p.waitForTimeout(1200);
  check('the next letter takes a new serial',
    (await docs(p))[0].number !== number, (await docs(p))[0].number + ' vs ' + number);

  // ---- Neither action is offered to somebody who may not take it ----------
  await p.close();
  p = await open(ctx, SEED + `(function(){
    window.__DB.clients.filter(function(c){ return c.id === 'c1'; })[0].client_code = 'AC180';
    window.__persist && window.__persist(); })();`);
  await pane(p, 'documents');
  await p.evaluate(() => {
    document.body.classList.add('no-remove');
    document.body.classList.add('no-docvoid');
  });
  await p.locator('#crmCover').click();
  await p.waitForTimeout(500);
  await p.locator('#pickGo').click();
  await p.waitForTimeout(1200);
  check('a person without either capability is offered no removal at all',
    !/Delete permanently|Void letter/.test(await items()), await items());
  // And the database refuses it even when the page is made to ask.
  await p.evaluate(() => { window.__teamCan.remove = false; window.__teamCan.doc_void = false; });
  const refused = await p.evaluate(async () => {
    const d = window.__DB.client_documents.filter(x => /AQL\//.test(x.number))[0];
    const r = await window.ADspaceAPI.client.rpc('letter_delete',
      { p_doc: d.id, p_confirm: d.number, p_reason: 'trying it on' });
    return JSON.stringify(r.data);
  });
  check('and a direct call is refused by the database', /not-allowed/.test(refused), refused);
  check('so the letter is still there',
    (await p.evaluate(() => window.__DB.client_documents.filter(x => /AQL\//.test(x.number)).length)) === 1);

  await ctx.close();
  console.log('=== errors ===');
  console.log(errs.length ? errs.join('\n') : 'none');
  if (errs.length) bad += errs.length;
  await b.close();
  console.log(bad ? 'letter: ' + bad + ' FAIL' : 'letter: ok');
  if (bad) process.exit(1);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
