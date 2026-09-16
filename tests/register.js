/*
 * The Client Register and the record's Overview summary — the two client-area
 * surfaces of this correction — proved at both widths and in every state a
 * person can actually land on.
 *
 * A directory is not "done" because its populated case renders. Somebody
 * arrives while it is still loading, somebody filters it down to nothing,
 * somebody's read is refused; each of those is a screen, and each has to say
 * what happened and offer the way out. This suite drives all five and shoots
 * them, so the states are reviewed rather than assumed.
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const SEED = fs.readFileSync(T + '/crmshot.js', 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
const QR = 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};';

let bad = 0;
const errs = [];
const check = (l, ok, x) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (x ? '  ' + x : '')); if (!ok) bad++; };

/* The three fixtures the states need. The register reads `clients`; emptying
   it is the empty state, and making the read fail is the failed one. */
const NONE = '(function(){ window.__DB.clients.length = 0; })();';
const FAIL = "(function(){ window.__failRead = { clients: 'permission denied for table clients' }; })();";
const SLOW = '(function(){ window.__slowRead = { clients: 1500 }; })();';
const REC = '#crmWork ';

async function open(ctx, url, seed, shot) {
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + url + ' ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED + (seed || '') }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899' + url, { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  if (shot !== 'loading') await p.waitForTimeout(900);
  return p;
}

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

  for (const [w, h, tag] of [[1280, 1000, '1280'], [390, 900, '390']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h },
      hasTouch: tag === '390', isMobile: tag === '390' });
    console.log('=== ' + tag + ' ===');

    /* ---- Populated ------------------------------------------------------ */
    let p = await open(ctx, '/admin/?s=clients');
    /* Scoped to the clients list: Phase 2 made the campaign register and the
       Content Review client list the same surface, so `.crm-register` is no
       longer unique in the console. The claim here was always about this one. */
    check('one register surface, not a panel per stage',
      await p.locator('#crmList .crm-register').count() === 1 &&
      await p.locator('#crmList .crm-group').count() === 0);
    check('and one header over it',
      await p.locator('#crmList .crm-head').count() === 1);
    const bands = await p.locator('#crmList .crm-band').allTextContents();
    check('the stages are labelled divider rows inside it', bands.length >= 2,
      bands.map(s => s.replace(/\s+/g, ' ').trim()).join(' / '));
    check('a row is one control that opens the workspace',
      await p.locator('#crmList .crm-row').first().evaluate(el =>
        el.tagName === 'BUTTON' && !el.querySelector('button, a, select, input')));
    check('no sideways overflow', await p.evaluate(() =>
      document.documentElement.scrollWidth <= window.innerWidth));
    await p.screenshot({ path: T + '/reg-' + tag + '-populated.png' });

    /* ---- Filtered empty -------------------------------------------------- */
    await p.locator('#crmSearch').fill('zzzzzz');
    await p.waitForTimeout(400);
    const fe = (await p.locator('#crmList').innerText()).replace(/\s+/g, ' ').trim();
    check('a filter that matches nothing says so', /No matches/i.test(fe), fe.slice(0, 60));
    check('and offers the way back', await p.locator('#crmList [data-a="go"]').count() === 1);
    await p.screenshot({ path: T + '/reg-' + tag + '-filtered.png' });
    /* Clicked with a pointer, not dispatched: focusing the button blurs the
       search box, the box fires `change`, and a repaint on that change
       detached the button between mousedown and click — so the one way out of
       a filtered empty list did nothing at all when it was pressed. */
    await p.locator('#crmList [data-a="go"]').click();
    await p.waitForTimeout(400);
    check('clearing them brings the register back',
      await p.locator('#crmList .crm-row').count() > 0 &&
      (await p.locator('#crmSearch').inputValue()) === '');
    await p.close();

    /* ---- Loading --------------------------------------------------------- */
    p = await open(ctx, '/admin/?s=clients', SLOW, 'loading');
    await p.waitForTimeout(500);
    const skel = await p.locator('#crmList .skel .skel-row').count();
    check('it says it is loading before it has anything', skel > 0, String(skel));
    await p.screenshot({ path: T + '/reg-' + tag + '-loading.png' });
    await p.waitForTimeout(1400);
    check('and the register replaces it when the read lands',
      await p.locator('#crmList .crm-row').count() > 0 &&
      await p.locator('#crmList .skel').count() === 0);
    await p.close();

    /* ---- Empty ----------------------------------------------------------- */
    p = await open(ctx, '/admin/?s=clients', NONE);
    const em = (await p.locator('#crmList').innerText()).replace(/\s+/g, ' ').trim();
    check('an empty register says so in two words', /No clients yet/i.test(em), em.slice(0, 60));
    check('and the way out is to add the first lead',
      (await p.locator('#crmList [data-a="go"]').innerText()).trim() === 'Add the first lead');
    check('the count says nothing rather than "0 clients"',
      (await p.locator('#crmCount').innerText()).trim() === '');
    await p.screenshot({ path: T + '/reg-' + tag + '-empty.png' });
    await p.close();

    /* ---- Failed ---------------------------------------------------------- */
    p = await open(ctx, '/admin/?s=clients', FAIL);
    const fl = (await p.locator('#crmList').innerText()).replace(/\s+/g, ' ').trim();
    check('a refused read names what failed', /could not be loaded/i.test(fl), fl.slice(0, 80));
    check('and shows the database message the team can act on',
      /permission denied/i.test(fl));
    check('with a way to try again',
      await p.locator('#crmList [data-a="retry"]').count() === 1);
    await p.screenshot({ path: T + '/reg-' + tag + '-failed.png' });
    await p.close();

    /* ---- The record's Overview ------------------------------------------- */
    p = await open(ctx, '/admin/?s=clients&client=laman-citra');
    await p.waitForTimeout(700);
    check('Overview is the pane it opens on',
      await p.locator(REC + '.rec-pane[data-pane="overview"]').isVisible());
    const rows = await p.locator('#crmSummary .ovsec-head h3').allTextContents();
    check('the Overview is titled sections, not metric cards', rows.length >= 4,
      rows.map(s => s.trim()).join(' / '));
    check('and none of them is a decorative tile',
      await p.locator('#crmSummary .tally, #crmSummary .tally-cell').count() === 0);
    check('every section says something',
      await p.locator('#crmSummary .ovsec').evaluateAll(
        els => els.every(e => e.textContent.trim().length > 0)));
    /* The identity area carries the record, not a thin title strip. */
    check('the record opens on an identity mark',
      (await p.locator('#crmClientMark').innerText()).trim().length > 0 ||
      await p.locator('#crmClientMark img').count() === 1);
    /* Scoped to the client record: the campaign record grew a rail of its own
       in Phase 2, so `.rec-rail` matches two of them in the console now. */
    check('the rail carries the details block',
      await p.locator('#crmWork .rec-rail .railblock .facts').count() === 1);
    /* Every rail block leaves when the data behind it is not there, so the
       rule under the last one is set rather than left to `:last-child`. */
    const lastRule = await p.evaluate(() => {
      const on = [...document.querySelectorAll('#crmWork .rec-rail .railblock')].filter(b => !b.hidden);
      if (!on.length) return 'none shown';
      const last = on[on.length - 1];
      return last.classList.contains('is-last') &&
        on.slice(0, -1).every(b => !b.classList.contains('is-last')) ? 'ok' : 'wrong block';
    });
    check('and the rule under it belongs to the last one drawn', lastRule === 'ok', lastRule);
    /* The tab strip is its own height: a rail taller than tabs plus pane used
       to have its extra shared between the two rows and push the pane down. */
    const gap = await p.evaluate(() => {
      const t = document.querySelector('#crmTabs');
      const s = document.querySelector('#crmSummary');
      if (!t || !s) return -1;
      return Math.round(s.getBoundingClientRect().top - t.getBoundingClientRect().bottom);
    });
    check('the pane starts right under the tabs', gap >= 0 && gap <= 20, gap + 'px');
    check('no sideways overflow on the record', await p.evaluate(() =>
      document.documentElement.scrollWidth <= window.innerWidth));
    await p.screenshot({ path: T + '/rec-' + tag + '-overview.png' });

    /* A summary row that points somewhere takes you there, and the address
       follows, or a refresh lands back on Overview with nothing said. */
    const go = p.locator('#crmSummary .ovgo[data-go]').first();
    if (await go.count()) {
      const want = await go.getAttribute('data-go');
      await go.click(); await p.waitForTimeout(450);
      check('a summary row opens the pane it points at',
        await p.locator(REC + '.rec-pane[data-pane="' + want + '"]').isVisible(), want);
      check('and the address follows it',
        (await p.evaluate(() => location.search)).indexOf('tab=' + want) > -1,
        await p.evaluate(() => location.search));
    }
    await p.close();
    await ctx.close();
  }

  console.log('=== errors ===');
  console.log(errs.length ? errs.join('\n') : 'none');
  if (errs.length) bad += errs.length;
  await b.close();
  console.log(bad ? 'register: ' + bad + ' FAIL' : 'register: ok');
  if (bad) process.exit(1);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
