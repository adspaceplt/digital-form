const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const [w, h, tag, mob] of [[1440, 900, 'd', false], [390, 844, 'm', true]]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h }, isMobile: mob, hasTouch: mob, deviceScaleFactor: mob ? 2 : 1 });
    const p = await ctx.newPage();
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    await p.goto('http://127.0.0.1:8899/admin/?s=team', { waitUntil: 'networkidle' });
    await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
    await p.waitForTimeout(900);
    await p.screenshot({ path: process.argv[2] + '/' + tag + '-team.png' });
    console.log(tag, 'overflow', await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth),
      'controls', await p.evaluate(() => [...new Set([...document.querySelectorAll('#sectionTeam .btn, #sectionTeam .select, #sectionTeam input[type=checkbox]')].filter(e => e.offsetParent).map(e => Math.round(e.getBoundingClientRect().height)))].sort((a,b)=>a-b).join(',')));
    await ctx.close();
  }
  await b.close();
})();
