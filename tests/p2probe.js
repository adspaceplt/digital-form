/* Throwaway probe: measure the things the screenshots only suggest. */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const seedOf = f => fs.readFileSync(T + '/' + f, 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
const CRM = seedOf('crmshot.js'), CAMP = seedOf('head.js'), PORTAL = seedOf('portal.js');
const QR = 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};';

const cols = () => {
  const out = [];
  document.querySelectorAll('.crm-table, .softpanel').forEach(t => {
    const rows = [...t.children].filter(r => r.offsetParent !== null && r.children.length > 1);
    if (rows.length < 2) return;
    const xs = rows.map(r => [...r.children].map(c => Math.round(c.getBoundingClientRect().left)));
    out.push({ table: t.className.split(' ').slice(0, 2).join('.'), rows: xs.slice(0, 4) });
  });
  return out;
};

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => console.log('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + CRM + CAMP + PORTAL }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(900);

  for (const sec of ['links', 'team', 'services']) {
    await p.locator('.navitem[data-section="' + sec + '"]').click();
    await p.waitForTimeout(700);
    console.log('--- ' + sec + ' ---');
    console.log(JSON.stringify(await p.evaluate(cols), null, 1));
  }

  // The view heads on every section: is there one on each?
  await p.evaluate(() => {});
  for (const sec of ['clients', 'review', 'campaigns', 'links', 'services', 'team']) {
    await p.locator('.navitem[data-section="' + sec + '"]').click();
    await p.waitForTimeout(600);
    const h = await p.evaluate(() => {
      const v = [...document.querySelectorAll('.viewhead')].filter(e => e.offsetParent !== null);
      const bar = [...document.querySelectorAll('.cmdbar')].filter(e => e.offsetParent !== null);
      const first = [...document.querySelectorAll('#view > *, .section > *')].filter(e => e.offsetParent !== null)[0];
      return { heads: v.map(e => e.textContent.trim().slice(0, 40)), bars: bar.length,
        firstTop: first ? Math.round(first.getBoundingClientRect().top) : null };
    });
    console.log(sec + ' → ' + JSON.stringify(h));
  }
  await b.close();
})();
