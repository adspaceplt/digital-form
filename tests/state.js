const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const errs = [];
const say = s => console.log(s);
// enough creators to make the roster scroll
const SEED = `(function(){ var D = window.__DB; if (D.creators.length > 3) return;
  for (var i = 0; i < 40; i++) {
    D.creators.push({ id:'r'+i, name:'博主 '+i, client_rate:300 });
    D.creator_profiles.push({ id:'rp'+i, creator_id:'r'+i, platform:'xhs',
      url:'https://www.xiaohongshu.com/user/profile/'+('000000000000000000000'+i).slice(-24), handle:('000000000000000000000'+i).slice(-24) });
  }
  D.campaigns.push({ id:'cmpX', client_id:'c1', title:'Existing campaign', slots:5, state:'draft',
    deliverable:'video', push_format:'site_visit', access_token:'STX' });
  window.__persist && window.__persist();
})();`;

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1200, height: 800 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  // the stub signs in on load if a flag is set, so a reload stays signed in
  await p.addInitScript(() => { window.addEventListener('load', () => setTimeout(() => window.__signIn && window.__signIn('adspacestudios@gmail.com'), 50)); });
  const reload = async () => { await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(900); };
  const where = async () => (await p.locator('#sectionTitle').innerText()) + ' @ ' + new URL(p.url()).search;

  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' }); await p.waitForTimeout(700);
  say('start: ' + await where());

  say('=== section survives ===');
  await p.locator('.navitem[data-section="links"]').click(); await p.waitForTimeout(400);
  say('links: ' + await where());
  await reload();
  say('after reload: ' + await where() + ' | links visible=' + await p.locator('#sectionLinks').isVisible());

  await p.locator('.navitem[data-section="campaigns"]').click(); await p.waitForTimeout(400);
  await p.locator('#tabRoster').click(); await p.waitForTimeout(600);
  say('roster: ' + await where());
  await p.evaluate(() => window.scrollTo(0, 900)); await p.waitForTimeout(400);
  await reload();
  say('after reload: ' + await where() + ' | roster visible=' + await p.locator('#rosterView').isVisible() +
      ' | tab on=' + await p.locator('#tabRoster').getAttribute('class') + ' | scrollY=' + await p.evaluate(() => Math.round(window.scrollY)));

  say('=== an open campaign survives ===');
  await p.locator('#tabCampaigns').click(); await p.waitForTimeout(500);
  await p.locator('#campCards .bigcard').first().click(); await p.waitForTimeout(600);
  say('open: ' + await where() + ' | name=' + await p.locator('#campName').innerText());
  await reload();
  say('after reload: ' + await where() + ' | work visible=' + await p.locator('#campWork').isVisible() + ' | name=' + await p.locator('#campName').innerText());

  say('=== typing a new campaign survives ===');
  await p.locator('#campBack').click(); await p.waitForTimeout(400);
  await p.locator('#showAddCamp').click(); await p.waitForTimeout(400);
  await p.selectOption('#campClient', 'c1');
  await p.fill('#campTitle', 'Showroom relaunch');
  await p.fill('#campPurpose', 'Bring footfall back after the refit');
  await p.fill('#campSlots', '8');
  await p.selectOption('#campFormat', 'seeding');
  await p.fill('#campOwner', 'Qiao Rou');
  await p.waitForTimeout(200);
  await reload();
  say('form open=' + await p.locator('#addCampBox').isVisible() + ' | title=' + await p.locator('#campFormTitle').innerText() +
      ' | client=' + await p.locator('#campClient').inputValue() + ' | name=' + await p.locator('#campTitle').inputValue() +
      ' | purpose=' + await p.locator('#campPurpose').inputValue() +
      ' | slots=' + await p.locator('#campSlots').inputValue() + ' | format=' + await p.locator('#campFormat').inputValue() +
      ' | owner=' + await p.locator('#campOwner').inputValue());
  await p.locator('#addCamp').click(); await p.waitForTimeout(600);
  say('created -> ' + await where() + ' | name=' + await p.locator('#campName').innerText());
  await reload();
  say('after create+reload: form open=' + await p.locator('#addCampBox').isVisible() + ' (draft cleared) | still in campaign=' + await p.locator('#campWork').isVisible());

  say('=== editing survives, and stays with its campaign ===');
  await p.locator('#campEdit').click(); await p.waitForTimeout(400);
  await p.fill('#campTitle', 'Showroom relaunch, week 2');
  await p.waitForTimeout(200);
  await reload();
  say('edit form open=' + await p.locator('#addCampBox').isVisible() + ' | heading=' + await p.locator('#campFormTitle').innerText() +
      ' | typed=' + await p.locator('#campTitle').inputValue() + ' | button=' + await p.locator('#addCamp').innerText());
  await p.locator('#cancelAddCamp').click(); await p.waitForTimeout(200);
  await reload();
  say('after cancel+reload: form open=' + await p.locator('#addCampBox').isVisible());

  say('=== a creator being added inside the campaign survives ===');
  await p.locator('#showAddOption').click(); await p.waitForTimeout(500);
  await p.fill('#ncName', '新博主');
  await p.fill('#ncRate', '480');
  await p.fill('#ncProfRows .prof-url', 'https://instagram.com/brand.new');
  await p.waitForTimeout(250);
  await p.locator('#ncPlatforms .pbox input[value="TikTok"]').check();
  await p.waitForTimeout(250);
  await reload();
  say('add box open=' + await p.locator('#addOptionBox').isVisible() + ' | name=' + await p.locator('#ncName').inputValue() +
      ' | rate=' + await p.locator('#ncRate').inputValue() + ' | link=' + await p.locator('#ncProfRows .prof-url').first().inputValue() +
      ' | ticked=' + (await p.locator('#ncPlatforms .pbox input:checked').evaluateAll(l => l.map(i => i.value))).join(','));

  say('=== back to Content Review still works ===');
  await p.locator('.navitem[data-section="review"]').click(); await p.waitForTimeout(500);
  say('review: ' + await where() + ' | clients listed=' + await p.locator('#clientCards .bigcard').count());
  await reload();
  say('after reload: ' + await where() + ' | clients listed=' + await p.locator('#clientCards .bigcard').count());

  await ctx.close(); await b.close();
  say('=== errors ==='); say(errs.length ? errs.join('\n') : 'none');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
