// Every portal page draws the same header and footer from one module.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
let bad = 0;
const check = (l, ok) => { console.log((ok ? 'ok   ' : 'FAIL ') + l); if (!ok) bad++; };
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1200, height: 900 } });
  const errs = [];
  for (const [path, kicker, footer] of [
    ['/admin/', 'Digital Portal', true],
    ['/review/?k=NOPE', 'Content Review', true],
    ['/creators/?k=NOPE', 'Creator Selection', true]
  ]) {
    const p = await ctx.newPage();
    p.on('pageerror', e => errs.push(path + ' PAGEERROR ' + e.message));
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    await p.goto('http://127.0.0.1:8899' + path, { waitUntil: 'networkidle' });
    await p.waitForTimeout(600);
    check(path + ' has the shared top bar', await p.locator('#topbar').count() === 1);
    check(path + ' names its section "' + kicker + '"',
      (await p.locator('#kicker').innerText()).trim() === kicker);
    check(path + ' falls back to the wordmark when the mark 404s',
      await p.locator('#agencyWordmark').isVisible());
    check(path + (footer ? ' has the shared footer' : ' leaves the footer out'),
      (await p.locator('.portalfoot').count() > 0) === footer);
    if (footer) {
      const f = await p.locator('.portalfoot-in').boundingBox();
      const vh = p.viewportSize().height;
      // On a short page the footer sits on the floor, not halfway up it.
      check(path + ' footer sits at the bottom of a short page',
        Math.abs((f.y + f.height) - vh) < 4);
      check(path + ' footer reads left and right only',
        (await p.locator('.portalfoot-in > *').count()) === 2);
      console.log('     ' + JSON.stringify(await p.locator('.portalfoot-in').innerText()));
      check(path + ' terms link points at the policies page',
        (await p.locator('.portalfoot-link').getAttribute('href')) ===
          'https://adspacestudios.com/legal/policies');
    }
    check(path + ' adds the favicon from the chrome',
      await p.locator('link[rel="icon"]').count() >= 1);
    await p.close();
  }
  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  if (errs.length) bad++;
  await b.close();
  console.log(bad ? 'chrome: PROBLEM' : 'chrome: ok');
})();
