const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Keyed', slots:2, state:'open',
    deliverable:'video', push_format:'site_visit', access_token:'KEY' });
  D.creators.forEach(function(cr,i){ D.campaign_options.push({ id:'ok'+i, campaign_id:'cmp1',
    creator_id:cr.id, rate:cr.client_rate, platforms:'RedNote', state:'option', position:i }); });
  window.__persist && window.__persist();
})();`;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await (await b.newContext({ viewport: { width: 1200, height: 900 } })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(400);
  await p.locator('.navitem[data-section="campaigns"]').click(); await p.waitForTimeout(400);
  await p.locator('#campCards .bigcard').first().click(); await p.waitForTimeout(600);
  console.log('lock hidden with nothing shortlisted:', await p.locator('#campLock').isHidden());
  // Accepting for the client now lives in the card's actions menu, so each
  // one is two steps: open the menu on that card, then pick the action.
  // Accepting moves the card up the list, so target by state, not position.
  const act = async (state, what) => {
    const card = p.locator('.kcard[data-state="' + state + '"]').first();
    await card.locator('[data-a="menu"]').click(); await p.waitForTimeout(250);
    await card.locator('[data-a="' + what + '"]').click({ timeout: 6000 }); await p.waitForTimeout(500);
  };
  await p.locator('.kcard').first().locator('[data-a="menu"]').click(); await p.waitForTimeout(250);
  console.log('menu offers:', (await p.locator('.kcard').first().locator('.kmenu-item b').allInnerTexts()).join(' / '));
  await p.keyboard.press('Escape'); await p.waitForTimeout(200);
  await act('option', 'pick');
  await act('option', 'pick');
  console.log('after keying two:', await p.evaluate(() => window.__DB.campaign_options.map(o => o.state).join(',')));
  console.log('lock now:', await p.locator('#campLock').innerText());
  await act('option', 'pick');
  console.log('third refused:', await p.locator('#campWorkMsg').innerText());
  await act('shortlisted', 'unpick'); await p.waitForTimeout(200);
  console.log('after unkey:', await p.evaluate(() => window.__DB.campaign_options.map(o => o.state).join(',')));
  await b.close();
  console.log('errors:', errs.length ? errs.join('|') : 'none');
})();
