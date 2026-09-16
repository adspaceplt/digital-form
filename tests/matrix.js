/* The wider responsive matrix, and the keyboard.
 *
 * `uxaudit` walks every page and state at the two widths this portal is tuned
 * for, in both themes. This suite is the other axis: a representative screen
 * from every route, at 320, 375, 390, 768, 1024, 1280 and 1440, and once more
 * at 1280 under 200% browser zoom — the widths between the two the audit walks
 * were the ones a layout fault could hide in, and that was a known gap.
 *
 * It runs the same in-page checks `uxaudit` runs (overflow, clipping, wrapped
 * values, control size, names on fields and icon buttons, focus rings), reusing
 * that file's own function so the two can never drift. It also drives the
 * keyboard through the controls that open a dialog, because Escape, focus
 * return and a visible ring are not things a screenshot shows.
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const seedOf = f => fs.readFileSync(T + '/' + f, 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
const CRM = seedOf('crmshot.js');
const CAMP = seedOf('head.js');
const CLIENT = seedOf('client.js');
const PORTAL = seedOf('portal.js');
const CREATOR = seedOf('creator.js');
const QR = 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};';

/* The audit's own in-page checks, read out of uxaudit.js rather than copied:
   one definition, so a rule added there is a rule this matrix enforces too. */
const AUDIT = fs.readFileSync(T + '/uxaudit.js', 'utf8')
  .match(/\/\* Runs inside the page[\s\S]*?\nfunction inPage\(coarse\) \{[\s\S]*?\n\}\n/)[0]
  .replace(/^[\s\S]*?function inPage/, 'function inPage');

/* Which of the audit's findings this suite is responsible for. Contrast and
   the palette are width-independent and are measured by `uxaudit` in both
   themes; what changes with width is geometry, so that is what fails here. */
const FAIL = new Set(['overflow', 'orphan', 'wrap', 'clip', 'target', 'label', 'icon-label', 'focus', 'type', 'row-height']);

const WIDTHS = [320, 375, 390, 768, 1024, 1280, 1440];
let fails = 0;
const errs = [];
const bad = (l, x) => { console.log('FAIL ' + l + (x ? '  ' + x : '')); fails++; };
const ok = (l, x) => console.log('ok   ' + l + (x ? '  ' + x : ''));

/* Browser zoom is not the CSS `zoom` property. Pressing Ctrl + halves the CSS
   viewport a 1280px window reports, so the media queries fire and the layout
   somebody sees at 200% is the layout at 640. Setting `zoom: 2` on the root
   instead leaves the media queries reading 1280 and scales a desktop layout
   past the window, which measures a case no reader is in. */
async function make(b, width, zoom) {
  const css = zoom ? Math.round(width / 2) : width;
  const coarse = css <= 640;
  const ctx = await b.newContext({
    viewport: { width: css, height: zoom ? 450 : 900 },
    hasTouch: coarse, isMobile: coarse,
    deviceScaleFactor: zoom ? 2 : 1
  });
  return { ctx, coarse };
}

async function open(ctx, url, seed, zoom) {
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + url + ' ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + (seed || '') }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib={};' }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899' + url, { waitUntil: 'networkidle' });
  await p.waitForTimeout(zoom ? 900 : 700);
  return p;
}

async function measure(p, label, coarse) {
  const found = await p.evaluate(([src, c]) => {
    // eslint-disable-next-line no-new-func
    return new Function(src + '; return inPage(' + (c ? 'true' : 'false') + ');')();
  }, [AUDIT, coarse]);
  const hits = found.filter(f => FAIL.has(f[0]));
  if (!hits.length) { ok(label); return; }
  hits.slice(0, 4).forEach(f => bad(label, f[0] + ': ' + f[1]));
}

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

  /* One screen from every route, populated: a list, a record with panes, a
     campaign command centre, the creator's page, the client's selection, the
     review gallery and the client's own portal. */
  const ROUTES = [
    ['console clients', '/admin/?s=clients', CRM, 'adspacestudios@gmail.com'],
    ['client record', '/admin/?s=clients&client=laman-citra&tab=services', CRM, 'adspacestudios@gmail.com'],
    ['campaign centre', '/admin/?s=campaigns', CAMP, 'adspacestudios@gmail.com'],
    ['creators list', '/admin/?s=campaigns&tab=roster', CAMP, 'adspacestudios@gmail.com'],
    ['rate card', '/admin/?s=services', CRM, 'adspacestudios@gmail.com'],
    ['short links', '/admin/?s=links', CRM, 'adspacestudios@gmail.com'],
    ['team', '/admin/?s=team', CRM, 'adspacestudios@gmail.com'],
    ['creator page', '/creator/?k=K2BBBBBB', CREATOR, null],
    ['creator selection', '/creators/?k=TESTTOKEN', CLIENT, null],
    ['client portal', '/client/', PORTAL, 'lim@lc.com']
  ];

  for (const zoom of [false, true]) {
    for (const width of (zoom ? [1280, 1440] : WIDTHS)) {
      const { ctx, coarse } = await make(b, width, zoom);
      const tag = width + (zoom ? ' @200%' : '');
      for (const [name, url, seed, signIn] of ROUTES) {
        const p = await open(ctx, url, seed, zoom);
        if (signIn) {
          await p.evaluate(e => window.__signIn(e), signIn);
          await p.waitForTimeout(zoom ? 1100 : 900);
        }
        await measure(p, tag + ' · ' + name, coarse);
        await p.close();
      }
      await ctx.close();
    }
  }

  /* ---- The keyboard ------------------------------------------------------
     A dialog has to be reachable without a pointer, say what it is, take the
     focus, give it back, and close on Escape. None of that shows in a
     screenshot, so none of it was being checked. */
  const { ctx } = await make(b, 1280, false);

  const p = await open(ctx, '/admin/?s=clients', CRM, false);
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(900);

  // The account control: open from the keyboard, close on Escape, focus back.
  await p.locator('#acctBtn').focus();
  await p.keyboard.press('Enter'); await p.waitForTimeout(250);
  const acctOpen = !(await p.locator('#acctMenu').evaluate(e => e.hidden));
  acctOpen ? ok('the account control opens from the keyboard')
           : bad('the account control opens from the keyboard');
  const ring = await p.evaluate(() => {
    const el = document.activeElement;
    const cs = getComputedStyle(el);
    return cs.boxShadow !== 'none' || cs.outlineStyle !== 'none';
  });
  ring ? ok('and what has focus inside it shows a ring')
       : bad('and what has focus inside it shows a ring');
  await p.keyboard.press('Escape'); await p.waitForTimeout(250);
  const shut = await p.locator('#acctMenu').evaluate(e => e.hidden);
  const back = await p.evaluate(() => document.activeElement && document.activeElement.id);
  shut ? ok('Escape closes it') : bad('Escape closes it');
  back === 'acctBtn' ? ok('and focus goes back to the control that opened it')
                     : bad('and focus goes back to the control that opened it', String(back));

  // The record's panes are buttons in a tablist, so they are reachable.
  await p.locator('.crm-row').first().click(); await p.waitForTimeout(700);
  const tabbed = await p.evaluate(() => {
    const t = document.querySelector('#crmTabs .tab[data-pane="billing"]');
    if (!t) return 'missing';
    t.focus();
    return document.activeElement === t ? 'ok' : 'not focusable';
  });
  tabbed === 'ok' ? ok('a record pane takes focus') : bad('a record pane takes focus', tabbed);
  await p.keyboard.press('Enter'); await p.waitForTimeout(400);
  (await p.locator('.rec-pane[data-pane="billing"]').isVisible())
    ? ok('and Enter opens it') : bad('and Enter opens it');
  await p.close();

  // The creator sheet: reachable, named, Escape closes, focus returns.
  const q = await open(ctx, '/admin/?s=campaigns&tab=roster', CAMP, false);
  await q.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await q.waitForTimeout(900);
  await q.locator('#showAddCreator').focus();
  await q.keyboard.press('Enter'); await q.waitForTimeout(450);
  (await q.locator('#addCreatorBox').isVisible())
    ? ok('the creator sheet opens from the keyboard') : bad('the creator sheet opens from the keyboard');
  const named = await q.locator('#addCreatorBox .sheet-card').evaluate(el =>
    el.getAttribute('role') === 'dialog' && el.getAttribute('aria-modal') === 'true' &&
    !!document.getElementById(el.getAttribute('aria-labelledby') || ''));
  named ? ok('and says what it is') : bad('and says what it is');
  await q.keyboard.press('Escape'); await q.waitForTimeout(400);
  (await q.locator('#addCreatorBox').isHidden())
    ? ok('Escape closes the sheet') : bad('Escape closes the sheet');
  const home = await q.evaluate(() => document.activeElement && document.activeElement.id);
  home === 'showAddCreator' ? ok('and focus goes home')
                            : bad('and focus goes home', String(home));
  await q.close();
  await ctx.close();

  await b.close();
  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  if (errs.length) fails += errs.length;
  console.log(fails ? 'matrix: ' + fails + ' FAIL' : 'matrix: ok');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
