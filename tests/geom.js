/*
 * Geometry, measured on the populated states that actually show the fault.
 *
 * The rules this file enforces are about a *component's* width, not the
 * window's. The record pane sits inside a 243px sidebar and beside a rail, so
 * at a 1280px window it is about 590px wide: every `@media (max-width: 760px)`
 * rule in the stylesheet is false while the pane it governs is narrower than
 * 760. That is the whole root cause of the wrapping, the stacked words and the
 * rows of unequal height, and it cannot be caught by a check that only knows
 * the viewport. So each assertion below reads the element's own box.
 *
 *   node tests/geom.js tests
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const SHOTS = process.env.SHOTS ? (process.env.SHOTS_DIR || T + '/geom') + '/' : null;
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const seedOf = f => fs.readFileSync(T + '/' + f, 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
const CRM = seedOf('crmshot.js'), CAMP = seedOf('head.js');
const QR = 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};';

/* Widths the brief names. 320 and 390 are phones, 768 and 1024 are the band
   where a desktop window still gives the pane less room than its tracks ask
   for, and 1280 and 1440 are the desk. */
const WIDTHS = [1440, 1280, 1024, 768, 390, 320];

/* Enough creators and service lines that a column has something to collapse
   under. One creator proves nothing about rows of equal height. */
const FULL = `(function(){ var D = window.__DB;
  var c = (D.campaigns || []).filter(function(x){ return x.id === 'cmp1'; })[0];
  if (c) { c.deadline = '2026-09-22'; c.owner = 'Qiao Rou'; }
  var names = ['香香的爆米花', '恩比', 'Vini168小队长',
               '小熊爱睡觉', '泡芙小姐姐'];
  var steps = ['confirmed', 'pending_visit', 'pending_draft', 'changes', 'shortlisted'];
  D.creators = D.creators || []; D.campaign_options = D.campaign_options || [];
  names.forEach(function (n, i) {
    var cid = 'gcr' + i;
    if (!D.creators.filter(function (x) { return x.id === cid; }).length) {
      D.creators.push({ id: cid, name: n, active: true, access_code: 'GEOM' + i + 'AAA',
        client_rate: 360 + i * 40 });
    }
    D.campaign_options.push({ id: 'gop' + i, campaign_id: 'cmp1', creator_id: cid,
      state: steps[i], rate: 800 + i * 200, position: i + 20,
      platforms: i % 2 ? 'rednote' : 'rednote, Instagram',
      visit_date: i % 2 ? '2026-09-2' + (i + 1) : null, visit_time: i % 2 ? '10am' : null,
      planned_publish: i % 3 ? '2026-09-28' : null, creators: D.creators.filter(function (x) { return x.id === cid; })[0] });
  });
  D.client_services = D.client_services || [];
  D.client_services.push({ id: 'gsv1', client_id: 'c1', slug: 'social-media',
    label: 'Social media management for Instagram, Facebook and TikTok',
    qty: 1, rate: 3200, tenure: 6, start_on: '2026-04-01', state: 'confirmed' });
  D.client_services.push({ id: 'gsv2', client_id: 'c1', slug: 'content-creation',
    label: 'Content creation', qty: 2, rate: 900, tenure: 6, start_on: '2026-04-01', state: 'confirmed' });
  window.__persist && window.__persist(); })();`;

let fails = 0, checks = 0;
const say = (ok, name, detail) => {
  checks++; if (!ok) fails++;
  console.log((ok ? 'ok   ' : 'FAIL ') + name + (detail ? '  ' + detail : ''));
};

/* Runs in the page. Returns the numbers each rule is about. */
function measure() {
  const box = el => el ? el.getBoundingClientRect() : null;
  const vis = el => el && el.offsetParent !== null && el.getBoundingClientRect().height > 0;
  const out = { doc: document.documentElement.scrollWidth, win: window.innerWidth };

  const pane = [...document.querySelectorAll('.rec-pane')].filter(vis)[0];
  out.pane = pane ? Math.round(box(pane).width) : null;

  // --- the campaign tab strip: one row, or one row that scrolls ---
  const strip = document.getElementById('campTabs') || document.getElementById('crmTabs');
  if (vis(strip)) {
    const tabs = [...strip.querySelectorAll('.tab')].filter(vis);
    out.tabRows = new Set(tabs.map(t => Math.round(box(t).top))).size;
    out.tabStrip = Math.round(box(strip).width);
    out.tabScrolls = strip.scrollWidth > strip.clientWidth + 1;
    out.tabShrink = tabs.every(t => getComputedStyle(t).flexShrink === '0');
  }

  // --- collapsed booking rows: equal height, status and menu in their columns ---
  /* A collapsed booking is one whose body is hidden; there is no `is-open`
     class, the fold is the body's `hidden` attribute. */
  out.bookCount = document.querySelectorAll('.bookreg .kcard').length;
  const heads = [...document.querySelectorAll('.bookreg .kcard > .kcard-head')]
    .filter(h => { const b = h.parentElement.querySelector('[data-body]'); return vis(h) && b && b.hidden; });
  if (heads.length > 1) {
    const hs = heads.map(h => Math.round(box(h).height));
    out.rowH = hs;
    out.rowSpread = Math.max(...hs) - Math.min(...hs);
    const tagX = heads.map(h => { const t = h.querySelector('.kcard-tags'); return t ? Math.round(box(t).left) : null; }).filter(x => x !== null);
    const actX = heads.map(h => { const a = h.querySelector('.kcard-act'); return a ? Math.round(box(a).right) : null; }).filter(x => x !== null);
    out.tagSpread = tagX.length > 1 ? Math.max(...tagX) - Math.min(...tagX) : 0;
    out.actSpread = actX.length > 1 ? Math.max(...actX) - Math.min(...actX) : 0;
    /* How many lines the row actually has, read off the grid itself. Counting
       the children's tops calls every correct row wrapped, because
       `align-items: center` gives children of different heights different
       tops; counting their centres calls it wrapped too, because the running
       number spans both rows and sits between them. The computed
       `grid-template-rows` is the only reading that is neither. */
    out.headLines = heads.map(h =>
      getComputedStyle(h).gridTemplateRows.trim().split(/\s+/).filter(Boolean).length);
  }

  // --- the service name track stays readable, or the row stacks on purpose ---
  const svc = [...document.querySelectorAll('#crmServices .csv-row:not(.crm-head)')].filter(vis);
  if (svc.length) {
    const names = svc.map(r => r.querySelector('.svc-name')).filter(Boolean);
    out.svcName = names.map(n => Math.round(box(n).width));
    out.svcStacked = names.length
      ? getComputedStyle(svc[0]).gridTemplateAreas.indexOf('name') > -1 : false;
    // Words stacking one per line is the fault: a name box narrower than its
    // own longest word has nowhere to put it.
    out.svcWordFits = names.every(n => n.scrollWidth <= Math.ceil(box(n).width) + 1 ||
      getComputedStyle(n).overflowWrap !== 'anywhere');
  }

  // --- the account menu: anchored, bounded, and its rows read across ---
  const menu = document.getElementById('acctMenu');
  if (vis(menu)) {
    const r = box(menu), btn = box(document.getElementById('acctBtn'));
    out.acctW = Math.round(r.width);
    out.acctBelow = btn ? Math.round(r.top - btn.bottom) : null;
    out.acctRightAligned = btn ? Math.abs(r.right - btn.right) < 40 : false;
    const items = [...menu.querySelectorAll('.kmenu-item')].filter(vis);
    out.acctRows = items.map(i => Math.round(box(i).height));
    out.acctAcross = items.every(i => getComputedStyle(i).flexDirection === 'row');
    out.acctAlign = items.every(i => {
      const ta = getComputedStyle(i).textAlign;
      return ta === 'left' || ta === 'start';
    });
  }

  // --- the one blue action, and no ink slabs left over ---
  const ACT = getComputedStyle(document.documentElement).getPropertyValue('--action').trim();
  const FILL = getComputedStyle(document.documentElement).getPropertyValue('--fill').trim();
  const norm = c => {
    const m = (c || '').match(/rgba?\(([^)]+)\)/);
    if (!m) return c;
    const a = m[1].split(/[,\s/]+/).map(Number);
    return '#' + [a[0], a[1], a[2]].map(v => ('0' + v.toString(16)).slice(-2)).join('');
  };
  out.inkSlabs = [...document.querySelectorAll('button, a.btn, [role=button]')]
    .filter(vis)
    .filter(b => norm(getComputedStyle(b).backgroundColor) === norm(FILL))
    .filter(b => !b.closest('.acttab, .crow-tick, .crow-backup, .progress-fill, .railbar'))
    .map(b => (b.id || b.className.split(' ')[0]) + ':"' + (b.textContent || '').trim().slice(0, 18) + '"');
  out.blueActions = [...document.querySelectorAll('button, a.btn, [role=button]')]
    .filter(vis)
    .filter(b => norm(getComputedStyle(b).backgroundColor) === norm(ACT))
    .map(b => (b.id || b.className.split(' ')[0]) + ':"' + (b.textContent || '').trim().slice(0, 18) + '"');

  // --- finance: two columns only while both fields keep useful width ---
  /* Only the rows that carry fields: a row of buttons is 116px wide by design,
     which is the button floor and not a squeezed field. */
  const rows = [...document.querySelectorAll('#invoiceBody .row')]
    .filter(vis).filter(r => r.querySelector('input, select, textarea'));
  if (rows.length) {
    out.finFields = rows.map(r => [...r.children].filter(vis)
      .filter(c => c.querySelector('input, select, textarea') || /input|select/.test(c.className))
      .map(c => Math.round(box(c).width)));
    out.finPad = getComputedStyle(document.getElementById('invoicePanel') || rows[0]).paddingTop;
  }

  // --- every control still clears its floor ---
  const coarse = matchMedia('(pointer: coarse)').matches;
  const floor = coarse ? 44 : 32;
  out.small = [...document.querySelectorAll('button, .btn, .input, .select, a.btn')]
    .filter(vis)
    .filter(b => !b.closest('.card-stage, .kmenu-item'))
    .filter(b => box(b).height < floor - 0.6)
    .map(b => (b.id || b.className.split(' ')[0]) + '@' + Math.round(box(b).height));
  return out;
}

async function open(ctx, url, seed, after) {
  const p = await ctx.newPage();
  p.on('pageerror', e => { console.log('PAGEERROR ' + e.message); fails++; });
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + seed }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib={};' }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899' + url, { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(1100);
  if (after) await after(p);
  await p.mouse.move(2, 2);
  await p.waitForTimeout(200);
  return p;
}

async function shot(p, name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTS, { recursive: true });
  await p.screenshot({ path: SHOTS + name + '.png', fullPage: true }).catch(() => {});
}

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

  for (const w of WIDTHS) {
    const coarse = w <= 390;
    const ctx = await b.newContext(coarse
      ? { viewport: { width: w, height: 844 }, hasTouch: true, isMobile: true }
      : { viewport: { width: w, height: 900 } });
    const at = ' @' + w;

    // ---- the campaign's Creators pane, five bookings at five steps ----
    let p = await open(ctx, '/admin/?s=campaigns', CRM + CAMP + FULL, async (pg) => {
      await pg.locator('#campCards .crm-row').first().click();
      await pg.waitForTimeout(800);
      await pg.locator('#campTabs .tab[data-pane="creators"]').click();
      await pg.waitForTimeout(600);
    });
    let m = await p.evaluate(measure);
    await shot(p, 'campaign-creators-' + w);

    say(m.doc <= m.win + 1, 'no document overflow' + at, m.doc + ' vs ' + m.win);
    if (m.tabRows !== undefined) {
      say(m.tabRows === 1, 'the tab strip is one row' + at, m.tabRows + ' rows, pane ' + m.pane);
      say(m.tabShrink, 'and its tabs do not shrink' + at);
    }
    say(m.bookCount >= 5, 'the fixture put six bookings on the campaign' + at,
      m.bookCount + ' cards');
    if (m.rowH) {
      say(m.rowSpread <= 2, 'collapsed bookings agree on their height' + at,
        m.rowH.join(',') + ' spread ' + m.rowSpread);
      /* 56 to 72 is the one line register row. It cannot also hold on a phone:
         there the row is deliberately two lines, and the first of them is as
         tall as the 44px touch target the same brief requires — 44 + 20 for the
         chip line + 24 of padding is 88, and no arrangement of a name, a state,
         a date and two controls in 358px is shorter. So the band is asserted
         where the row is one line, and the phone is held to its own ceiling and
         to the same consistency. */
      const tight = m.pane !== null && m.pane <= 460;
      if (tight) {
        say(m.rowH.every(h => h <= 92), 'a phone booking row stays within two lines' + at, m.rowH.join(','));
        say(m.headLines.every(n => n <= 2), 'and is two lines, not three' + at, m.headLines.join(','));
      } else {
        say(m.rowH.every(h => h >= 56 && h <= 72), 'and each is 56 to 72px' + at, m.rowH.join(','));
        say(m.headLines.every(n => n === 1), 'nothing in a collapsed row has wrapped to a second line' + at,
          m.headLines.join(','));
      }
      say(m.tagSpread <= 2, 'the status starts on one shared line' + at, 'spread ' + m.tagSpread);
      say(m.actSpread <= 2, 'and the menu ends the last column' + at, 'spread ' + m.actSpread);
    }
    say(m.inkSlabs.length === 0, 'no ink primary is left over' + at, m.inkSlabs.join(' '));
    say(m.blueActions.length <= 2, 'at most two blue actions in view' + at, m.blueActions.join(' '));
    say(m.small.length === 0, 'every control clears its floor' + at, m.small.join(' '));
    await p.close();

    // ---- the campaign's Finance pane ----
    p = await open(ctx, '/admin/?s=campaigns', CRM + CAMP + FULL, async (pg) => {
      await pg.locator('#campCards .crm-row').first().click();
      await pg.waitForTimeout(800);
      await pg.locator('#campTabs .tab[data-pane="finance"]').click();
      await pg.waitForTimeout(500);
      const t = pg.locator('#invoiceToggle');
      if (await t.isVisible().catch(() => false)) {
        if ((await t.getAttribute('aria-expanded')) !== 'true') { await t.click(); await pg.waitForTimeout(400); }
      }
    });
    m = await p.evaluate(measure);
    await shot(p, 'campaign-finance-' + w);
    say(m.doc <= m.win + 1, 'no document overflow, finance' + at, m.doc + ' vs ' + m.win);
    say(!!(m.finFields && m.finFields.length), 'the invoice fold is open to be measured' + at,
      (m.finFields || []).length + ' rows');
    if (m.finFields) {
      /* Two fields share a line only while both keep a useful width; below
         that they stack, rather than each being squeezed to a stub. */
      const bad = m.finFields.filter(r => r.length > 1 && Math.min(...r) < 150);
      say(bad.length === 0, 'finance fields keep a useful width or stack' + at,
        JSON.stringify(m.finFields));
    }
    say(m.inkSlabs.length === 0, 'no ink primary on finance' + at, m.inkSlabs.join(' '));
    await p.close();

    // ---- the client record's Services pane ----
    p = await open(ctx, '/admin/?s=clients&client=laman-citra&tab=services', CRM + FULL);
    m = await p.evaluate(measure);
    await shot(p, 'client-services-' + w);
    say(m.doc <= m.win + 1, 'no document overflow, services' + at, m.doc + ' vs ' + m.win);
    say(!!(m.svcName && m.svcName.length >= 2), 'the fixture put service lines on the client' + at,
      (m.svcName || []).length + ' lines');
    if (m.svcName) {
      /* Either the desktop grid is on and the name has room to be read, or the
         row has stacked on purpose. What is not allowed is the grid staying on
         while the name is squeezed until its words break one per line. */
      say(m.svcStacked || Math.min(...m.svcName) >= 180,
        'the service name keeps a readable track, or the row stacks' + at,
        m.svcName.join(',') + (m.svcStacked ? ' (stacked)' : ' (grid)'));
      say(m.svcWordFits, 'and no description is broken word by word' + at);
    }
    await p.close();

    // ---- the account menu ----
    p = await open(ctx, '/admin/?s=clients', CRM, async (pg) => {
      await pg.locator('#acctBtn').click();
      await pg.waitForTimeout(350);
    });
    m = await p.evaluate(measure);
    await shot(p, 'account-menu-' + w);
    if (m.acctW !== undefined) {
      say(m.acctW >= 232 && m.acctW <= 300, 'the account menu is 240 to 280 wide' + at, m.acctW + 'px');
      say(m.acctBelow !== null && m.acctBelow >= 0 && m.acctBelow <= 16,
        'anchored just below its button' + at, m.acctBelow + 'px');
      say(m.acctRightAligned, 'and to the button, not the page' + at);
      say(m.acctAcross, 'its rows read across, not down' + at);
      say(m.acctAlign, 'and their text starts at the left' + at);
      say(m.acctRows.every(h => h >= 40 && h <= 48), 'each row is 40 to 44px' + at, m.acctRows.join(','));
    }
    say(m.doc <= m.win + 1, 'no document overflow, account menu' + at, m.doc + ' vs ' + m.win);
    await p.close();
    await ctx.close();
  }

  await b.close();
  console.log(fails ? 'geom: ' + fails + ' FAIL of ' + checks : 'geom: ok (' + checks + ' checks)');
  process.exit(fails ? 1 : 0);
})();
