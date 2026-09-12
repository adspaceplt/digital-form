const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = fs.readFileSync(process.argv[2] + '/crmshot.js', 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const [w, h, tag, coarse] of [[1280, 900, '1280', false], [390, 844, '390', true]]) {
    const ctx = await b.newContext(coarse ? { viewport: { width: w, height: h }, hasTouch: true, isMobile: true } : { viewport: { width: w, height: h } });
    const p = await ctx.newPage();
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    await p.goto('http://127.0.0.1:8899/admin/?s=clients', { waitUntil: 'networkidle' });
    await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
    await p.waitForTimeout(700);
    // the intake form
    await p.locator('#crmNew').click(); await p.waitForTimeout(400);
    await p.locator('#crmAddBox').screenshot({ path: process.argv[2] + '/lead-form-' + tag + '.png' });
    await p.fill('#crmName', 'COMPANY NAME SDN BHD');
    await p.fill('#crmContactName', 'John Doe');
    await p.fill('#crmContactPhone', '012-345 6789');
    await p.fill('#crmEnquiry', 'Package B and a launch video');
    await p.locator('#crmSave').click(); await p.waitForTimeout(900);
    // two service lines, one confirmed
    await p.locator('#crmAddService').click(); await p.waitForTimeout(400);
    await p.selectOption('#svPick', 'pkg-b'); await p.fill('#svQty', '3'); await p.selectOption('#svState', 'quoted');
    await p.locator('#svSave').click(); await p.waitForTimeout(900);
    await p.locator('#crmAddService').click(); await p.waitForTimeout(400);
    await p.selectOption('#svPick', 'custom'); await p.fill('#svLabel', 'Launch video'); await p.fill('#svRate', '20000'); await p.selectOption('#svState', 'confirmed');
    await p.locator('#svSave').click(); await p.waitForTimeout(900);
    await p.screenshot({ path: process.argv[2] + '/lead-record-' + tag + '.png', fullPage: true });
    // the rate card
    if (coarse) { await p.locator('#navToggle').click(); await p.waitForTimeout(300); }
    await p.locator('.navitem[data-section="services"]').click(); await p.waitForTimeout(700);
    await p.screenshot({ path: process.argv[2] + '/ratecard-' + tag + '.png', fullPage: true });
    console.log(tag + ' ok: ' + await p.locator('#svcList .svc-row').count() + ' rate card rows');
    await ctx.close();
  }
  await b.close();
})();
