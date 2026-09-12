// A Singapore client is quoted in S$ on their own page, with no ringgit sign.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmpSG', client_id:'c2', title:'Cafe launch', slots:2, state:'open',
    deliverable:'video', push_format:'site_visit', access_token:'SGD1' });
  D.campaigns.push({ id:'cmpMY', client_id:'c1', title:'Laman Citra push', slots:2, state:'open',
    deliverable:'video', push_format:'site_visit', access_token:'MYR1' });
  D.creators.forEach(function(cr,i){
    D.campaign_options.push({ id:'so'+i, campaign_id:'cmpSG', creator_id:cr.id, rate:400,
      platforms:'RedNote', state:'option', position:i });
    D.campaign_options.push({ id:'mo'+i, campaign_id:'cmpMY', creator_id:cr.id, rate:400,
      platforms:'RedNote', state:'option', position:i });
  });
  window.__persist && window.__persist(); })();`;
let bad = 0;
const check = (l, ok, extra) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (extra ? '  ' + extra : '')); if (!ok) bad++; };
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1000, height: 1000 } });
  const errs = [];
  for (const [token, sign, wrong, taxed] of [['SGD1', 'S$', 'RM', true], ['MYR1', 'RM', 'S$', true]]) {
    const p = await ctx.newPage();
    p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    await p.goto('http://127.0.0.1:8899/creators/?k=' + token, { waitUntil: 'networkidle' });
    await p.waitForTimeout(900);
    await p.locator('.crow-tick').first().click(); await p.waitForTimeout(400);
    const bar = await p.locator('.confirmbar').innerText();
    console.log('  ' + token + ' bar: ' + JSON.stringify(bar.replace(/\n/g, ' | ')));
    check(token + ' shows ' + sign, bar.includes(sign));
    check(token + ' never shows ' + wrong, !bar.includes(wrong));
    await p.locator('#confirmBtn').click().catch(() => {});
    await p.waitForTimeout(500);
    if (await p.locator('#confirmTotals').isVisible()) {
      const tot = (await p.locator('#confirmTotals').innerText()).replace(/\n/g, ' | ');
      console.log('  ' + token + ' totals: ' + JSON.stringify(tot));
      check(token + (taxed ? ' charges tax' : ' charges no tax'),
        /SST|GST/.test(tot) === taxed);
      check(token + ' totals use ' + sign, tot.includes(sign) && !tot.includes(wrong));
    }
    await p.close();
  }
  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  if (errs.length) bad++;
  await b.close();
  console.log(bad ? 'sgd: PROBLEM' : 'sgd: ok');
})();
