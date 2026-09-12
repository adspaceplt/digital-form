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
    // an active client so the engagement actions render
    const n = await p.locator('.crm-row').count();
    let opened = false;
    for (let i = 0; i < n; i++) {
      const t = await p.locator('.crm-row').nth(i).innerText();
      if (/active/i.test(t)) { await p.locator('.crm-row').nth(i).click(); opened = true; break; }
    }
    if (!opened) await p.locator('.crm-row').first().click();
    await p.waitForTimeout(800);
    await p.locator('#crmEngageActions').scrollIntoViewIfNeeded().catch(() => {});
    await p.screenshot({ path: process.argv[2] + '/crm-engage-' + tag + '.png', fullPage: true });
    console.log(tag + ' actions: ' + JSON.stringify(await p.locator('#crmEngageActions').innerText().catch(() => 'n/a')));
    await ctx.close();
  }
  await b.close();
})();
