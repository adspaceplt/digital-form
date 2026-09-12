const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(process.argv[2] + '/pdfx/node_modules/pdf-lib/dist/pdf-lib.min.js', 'utf8') }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(process.argv[2] + '/pdfx/node_modules/@pdf-lib/fontkit/dist/fontkit.umd.min.js', 'utf8') }));
  await p.goto('http://127.0.0.1:8899/admin/?s=clients', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(700);
  console.log('pdf-lib loaded: ' + await p.evaluate(() => !!window.PDFLib));
  await p.locator('.crm-row').filter({ hasText: 'Laman Citra' }).click(); await p.waitForTimeout(800);
  for (const [pick, qty, state, label, rate, months, start] of [['pkg-b', '3', 'confirmed'], ['custom', '1', 'confirmed', 'Launch video, up to 60 seconds, one on-site shoot included', '20000'], ['pkg-b', '1', 'quoted', '', '', '6', '2026-10']]) {
    await p.locator('#crmAddService').click(); await p.waitForTimeout(300);
    await p.selectOption('#svPick', pick); await p.fill('#svQty', qty); await p.selectOption('#svState', state);
    if (label) { await p.fill('#svLabel', label); await p.fill('#svRate', rate); }
    if (months) { await p.fill('#svTenure', months); await p.fill('#svStart', start + '-12'); }
    await p.locator('#svSave').click(); await p.waitForTimeout(900);
  }
  const dl = p.waitForEvent('download');
  await p.locator('#crmCover').click();
  const got = await dl; await got.saveAs(process.argv[2] + '/' + got.suggestedFilename());
  console.log('saved ' + got.suggestedFilename());
  await p.waitForTimeout(500);
  await p.screenshot({ path: process.argv[2] + '/docs-1280.png', fullPage: true });
  console.log('errors: ' + (errs.join(' | ') || 'none'));
  await b.close();
})();
