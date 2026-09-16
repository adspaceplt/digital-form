/*
 * The letter workflow, in the states somebody actually lands on: a client with
 * no Client ID, the selection sheet, an issued letter, one signed and awaiting
 * verification, one verified, one void, and a letter from before the change.
 * At 1280 and 390, because the sheet is where the choice is made and a phone
 * is where half of it is made.
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const OUT = process.env.OUT || (T + '/');
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const SEED = fs.readFileSync(T + '/letter.js', 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
const CODED = SEED + `(function(){
  window.__DB.clients.filter(function(c){ return c.id === 'c1'; })[0].client_code = 'AC180';
  window.__persist && window.__persist(); })();`;

async function open(ctx, seed) {
  const p = await ctx.newPage();
  p.on('pageerror', e => console.log('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + seed }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib={};' }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/?s=clients&client=laman-citra', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(1300);
  await p.mouse.move(2, 2);
  return p;
}

/* A sheet is `position: fixed`, so a full page shot smears it down the scroll
   height instead of showing it. Those states are shot at viewport size, which
   is also what somebody is actually looking at when they use one. */
const shoot = async (p, name, viewportOnly) => {
  await p.waitForTimeout(350);
  await p.screenshot({ path: OUT + name, fullPage: !viewportOnly });
  console.log('shot ' + name);
};

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const [w, h, tag] of [[1280, 1000, '1280'], [390, 1200, '390']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h },
      hasTouch: tag === '390', isMobile: tag === '390' });

    // 1. No Client ID: the letter is refused, and the record says what to do.
    /* The record is a workspace with panes now: a section's controls are in
       the pane that owns them. */
    const pane = async (pg, k) => { await pg.locator('#crmTabs .tab[data-pane="' + k + '"]').click(); await pg.waitForTimeout(300); };
    let p = await open(ctx, SEED);
    await pane(p, 'documents');
    await p.locator('#crmCover').click();
    await p.waitForTimeout(500);
    await shoot(p, 'lt-nocode-' + tag + '.png');
    await p.close();

    // 2. The selection sheet.
    p = await open(ctx, CODED);
    await pane(p, 'documents');
    await p.locator('#crmCover').click();
    await p.waitForTimeout(600);
    await shoot(p, 'lt-pick-' + tag + '.png', true);

    // 3. Issued.
    await p.locator('#pickGo').click();
    await p.waitForTimeout(1400);
    await shoot(p, 'lt-issued-' + tag + '.png');

    const rowAt = () => p.evaluate(() => [...document.querySelectorAll('#crmDocuments .doc-row')]
      .filter(r => !r.classList.contains('crm-head')).findIndex(r => /AQL\//.test(r.innerText)));
    const act = async (a) => {
      const i = await rowAt();
      await p.evaluate(([n, name]) => {
        const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
        rows[n].querySelector('[data-a="menu"]').click();
        rows[n].querySelector('[data-a="' + name + '"]').click();
      }, [i, a]);
      await p.waitForTimeout(1100);
    };

    // 4. Signed, awaiting verification.
    await act('sign');
    await shoot(p, 'lt-signed-' + tag + '.png');

    // 5. Verified, and the service it confirmed.
    p.once('dialog', d => d.accept());
    await act('verify');
    await shoot(p, 'lt-verified-' + tag + '.png');
    await p.close();

    // 6. Void, beside the legacy letter that is never offered verification.
    p = await open(ctx, CODED);
    await pane(p, 'documents');
    await p.locator('#crmCover').click();
    await p.waitForTimeout(600);
    await p.locator('#pickGo').click();
    await p.waitForTimeout(1400);
    await p.evaluate(() => {
      const rows = [...document.querySelectorAll('#crmDocuments .doc-row')].filter(r => !r.classList.contains('crm-head'));
      const r = rows.filter(x => /AQL\//.test(x.innerText))[0];
      r.querySelector('[data-a="menu"]').click();
      r.querySelector('[data-a="void"]').click();
    });
    await p.waitForTimeout(1200);
    await p.mouse.move(2, 2);
    await shoot(p, 'lt-void-' + tag + '.png');
    await p.close();

    await ctx.close();
  }
  await b.close();
})().catch(e => { console.error('FAIL', e); process.exit(1); });
