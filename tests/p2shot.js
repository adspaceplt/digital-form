/*
 * Phase 2 evidence. Every route the visual pass touches, at 1280 and 390, from
 * one set of fixtures, so a before and an after are the same screen twice and
 * not two different ones. The admin shell and one dense register are shot again
 * in dark, because dark is the console's alone and a colour written into a rule
 * is what breaks it.
 *
 *   OUT=tests/p2/before node tests/p2shot.js tests
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const OUT = (process.env.OUT || T + '/p2/now') + '/';
const ONLY = process.env.ONLY ? new Set(process.env.ONLY.split(',')) : null;
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const seedOf = f => fs.readFileSync(T + '/' + f, 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
const CRM = seedOf('crmshot.js'), CAMP = seedOf('head.js'), CLIENT = seedOf('client.js');
const CPROD = seedOf('cprod.js'), PORTAL = seedOf('portal.js'), CREATOR = seedOf('creator.js');
const QR = 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};';

/* The campaign fixtures carry one confirmed booking and one waiting on us, so
   the record has something in every pane rather than a single row. */
const CAMPFULL = `(function(){ var D = window.__DB;
  var c = (D.campaigns || []).filter(function(x){ return x.id === 'cm1'; })[0];
  if (c) { c.due_on = '2026-09-22'; c.owner = 'Qiao Rou'; }
  window.__persist && window.__persist(); })();`;

const errs = [];

async function shot(p, name) {
  if (ONLY && !ONLY.has(name.replace(/-(1280|390)(-dark)?$/, ''))) return;
  fs.mkdirSync(OUT, { recursive: true });
  await p.screenshot({ path: OUT + name + '.png', fullPage: true }).catch(e => errs.push(name + ' ' + e.message));
  console.log('shot ' + name);
}

async function walk(b, coarse, dark) {
  const tag = (coarse ? '390' : '1280') + (dark ? '-dark' : '');
  const ctx = await b.newContext(coarse
    ? { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true }
    : { viewport: { width: 1280, height: 900 } });
  if (dark) await ctx.addInitScript(() => { try { localStorage.setItem('adspace-theme', 'dark'); } catch (e) {} });
  const page = async (seed) => {
    const p = await ctx.newPage();
    p.on('pageerror', e => errs.push(tag + ' PAGEERROR ' + e.message));
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + seed }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
    await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib={};' }));
    await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    return p;
  };
  const nav = async (p, sec) => {
    if (coarse) { await p.locator('#navToggle').click(); await p.waitForTimeout(300); }
    await p.locator('.navitem[data-section="' + sec + '"]').click(); await p.waitForTimeout(650);
    await p.mouse.move(2, 2); await p.waitForTimeout(150);
  };

  // ---- Console ----
  let p = await page(CRM + CAMP + PORTAL + CAMPFULL);
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(900); await p.mouse.move(2, 2); await p.waitForTimeout(200);
  await shot(p, 'shell-clients-' + tag);

  await nav(p, 'campaigns');
  await shot(p, 'campaigns-register-' + tag);

  const camp = p.locator('#campCards .bigcard, .camp-row', { hasText: 'Promote New Launch' });
  await (await camp.count() ? camp.first() : p.locator('#campCards .bigcard, .camp-row').first()).click();
  await p.waitForTimeout(800); await p.mouse.move(2, 2); await p.waitForTimeout(200);
  await shot(p, 'campaign-overview-' + tag);

  const cpane = async (k) => {
    const t = p.locator('#campTabs .tab[data-pane="' + k + '"]');
    if (await t.count()) { await t.click(); await p.waitForTimeout(500); await p.mouse.move(2, 2); await p.waitForTimeout(150); }
  };
  await cpane('creators'); await shot(p, 'campaign-creators-' + tag);
  await cpane('schedule'); await shot(p, 'campaign-schedule-' + tag);
  await cpane('finance');  await shot(p, 'campaign-finance-' + tag);

  await p.locator('#tabRoster').click(); await p.waitForTimeout(700);
  await p.mouse.move(2, 2); await p.waitForTimeout(150);
  await shot(p, 'creator-roster-' + tag);

  await nav(p, 'review');  await shot(p, 'content-review-' + tag);
  await nav(p, 'links');   await shot(p, 'short-links-' + tag);
  await nav(p, 'services'); await shot(p, 'rate-card-' + tag);
  await nav(p, 'team');    await shot(p, 'team-' + tag);
  await p.close();

  if (dark) { await ctx.close(); return; }

  // ---- Client-facing ----
  p = await page(PORTAL);
  await p.goto('http://127.0.0.1:8899/client/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('lim@lc.com')); await p.waitForTimeout(900);
  await p.mouse.move(2, 2); await p.waitForTimeout(150);
  await shot(p, 'client-portal-' + tag);
  await p.close();

  p = await page(CLIENT);
  await p.goto('http://127.0.0.1:8899/creators/?k=TESTTOKEN', { waitUntil: 'networkidle' });
  await p.waitForTimeout(800); await p.mouse.move(2, 2); await p.waitForTimeout(150);
  await shot(p, 'creator-selection-' + tag);
  await p.close();

  p = await page(CPROD);
  await p.goto('http://127.0.0.1:8899/creators/?k=CPROD', { waitUntil: 'networkidle' });
  await p.waitForTimeout(800); await p.mouse.move(2, 2); await p.waitForTimeout(150);
  await shot(p, 'creator-selection-booked-' + tag);
  await p.close();

  p = await page(CREATOR);
  await p.goto('http://127.0.0.1:8899/creator/?k=K2BBBBBB', { waitUntil: 'networkidle' });
  await p.waitForTimeout(900); await p.mouse.move(2, 2); await p.waitForTimeout(150);
  await shot(p, 'creator-portal-' + tag);
  await p.close();

  p = await ctx.newPage();
  p.on('pageerror', e => errs.push(tag + ' PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/review/?k=demo', { waitUntil: 'networkidle' });
  await p.waitForTimeout(1100); await p.mouse.move(2, 2); await p.waitForTimeout(150);
  await shot(p, 'content-review-client-' + tag);
  await p.close();
  await ctx.close();
}

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  await walk(b, false, false);
  await walk(b, true, false);
  await walk(b, false, true);
  await b.close();
  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  console.log('p2shot: ' + (errs.length ? 'PROBLEM' : 'ok') + ' → ' + OUT);
  process.exit(errs.length ? 1 : 0);
})();
