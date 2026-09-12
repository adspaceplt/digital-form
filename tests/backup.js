const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const errs = [];
const say = s => console.log(s);
// 3 slots, 6 options. Client picks 3 and marks 2 backups, gets locked, then one withdraws.
const SEED = `(function(){ var D = window.__DB; if (D.campaigns.length) return;
  D.campaigns.push({ id:'cmp1', client_id:'c1', title:'Backups', slots:3, state:'open',
    deliverable:'video', push_format:'site_visit', access_token:'BK' });
  ['A','B','C','D','E','F'].forEach(function(n,i){
    D.creators.push({ id:'b'+i, name:'Creator '+n, client_rate:300+i*10 });
    D.campaign_options.push({ id:'ob'+i, campaign_id:'cmp1', creator_id:'b'+i, rate:300+i*10,
      platforms:'RedNote', state:'option', position:i });
  });
  window.__persist && window.__persist();
})();`;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1000, height: 900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/creators/?k=BK', { waitUntil: 'networkidle' });
  await p.waitForTimeout(600);

  say('=== choosing ===');
  say('hint: ' + await p.locator('#chooseHint').innerText());
  for (const i of [0, 1, 2]) { await p.locator('.crow-tick').nth(i).click(); await p.waitForTimeout(120); }
  await p.waitForTimeout(200);
  say('3 picked -> backup line: ' + await p.locator('#progBackup').innerText());
  say('confirm disabled: ' + await p.locator('#confirmBtn').isDisabled());
  await p.locator('.crow-backup').nth(3).click();
  await p.waitForTimeout(200);
  say('1 backup -> ' + await p.locator('#progBackup').innerText() + ' | disabled=' + await p.locator('#confirmBtn').isDisabled());
  await p.locator('.crow-backup').nth(4).click();
  await p.waitForTimeout(900);
  say('2 backups -> ' + await p.locator('#progBackup').innerText() + ' | disabled=' + await p.locator('#confirmBtn').isDisabled());
  say('server: ' + await p.evaluate(() => window.__DB.campaign_options.map(o => o.state[0]).join('')));

  say('=== team locks, then Creator B withdraws ===');
  await p.evaluate(() => {
    const D = window.__DB;
    D.campaign_options.forEach(o => { if (o.state === 'shortlisted') o.state = 'confirmed'; });
    D.campaigns[0].state = 'production';
    D.campaign_options[1].state = 'withdrawn';
    window.__persist();
  });
  await p.reload({ waitUntil: 'networkidle' });
  await p.waitForTimeout(700);
  say('progress: ' + await p.locator('#progCount').innerText() + ' / ' + await p.locator('#progSay').innerText());
  say('hint now: ' + await p.locator('#chooseHint').innerText());
  say('hint class: ' + await p.locator('#chooseHint').getAttribute('class'));
  const order = await p.locator('.crow .crow-name b').allInnerTexts();
  say('list order: ' + order.join(', '));
  say('priority tags: ' + await p.locator('.tag-pri').count() + ' on ' +
      (await p.locator('.crow:has(.tag-pri) .crow-name b').allInnerTexts()).join(', '));
  say('withdrawn shown in bookings as: ' + await p.locator('.booking.is-off .chip-state').innerText());

  // promote a backup into the slot
  await p.locator('.crow').first().locator('.crow-tick').click();
  await p.waitForTimeout(300);
  say('after promoting one: ' + await p.locator('#progCount').innerText() + ' / ' + await p.locator('#progSay').innerText());
  say('backup line: ' + await p.locator('#progBackup').innerText());
  say('confirm disabled (needs a fresh backup): ' + await p.locator('#confirmBtn').isDisabled());
  say('priority mode over: ' + (await p.locator('#chooseHint').getAttribute('class')).indexOf('is-priority') < 0);

  await p.screenshot({ path: process.argv[2] + '/backup.png', fullPage: true });
  await ctx.close(); await b.close();
  say('=== errors ==='); say(errs.length ? errs.join('\n') : 'none');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
