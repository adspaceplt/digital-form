const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  // No Supabase bundle at all -> demo mode, which is the client page's fallback.
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/review/', { waitUntil: 'networkidle' });
  await p.waitForTimeout(1200);
  const s = await p.evaluate(() => {
    const sheets = [...document.styleSheets].filter(s => (s.href || '').includes('portal.css'));
    let rules = 0; try { rules = sheets[0].cssRules.length; } catch (e) { rules = -1; }
    return { rules, cards: document.querySelectorAll('.card').length,
             title: document.title, bodyText: document.body.innerText.slice(0, 90) };
  });
  console.log('portal.css rules parsed:', s.rules);
  console.log('review cards rendered:', s.cards);
  console.log('title:', s.title);
  console.log('errors:', errs.length ? errs.join(' | ') : 'none');
  await p.screenshot({ path: process.argv[2] + '/review-client.png' });
  await b.close();
})();
