// Access: an admin sees Team and everything; sales sees Clients only; a login
// with no team row sees a plain notice; an invitation is sent on add.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
let bad = 0;
const check = (l, ok, x) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (x ? '  ' + x : '')); if (!ok) bad++; };
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 900 } });
  const errs = [];
  const page = async (email) => {
    const p = await ctx.newPage();
    p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
    p.on('dialog', d => d.accept());
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
    await p.evaluate((e) => window.__signIn(e), email);
    await p.waitForTimeout(800);
    return p;
  };
  const visibleNav = async (p) => (await p.locator('.navitem:not([hidden]) span').allInnerTexts()).join(', ');

  // admin
  let p = await page('adspacestudios@gmail.com');
  console.log('  admin sees: ' + await visibleNav(p));
  check('admin sees Team', (await visibleNav(p)).includes('Team'));
  check('admin sees the activity record', await p.locator('#activityOpen').isVisible());
  await p.locator('.navitem[data-section="team"]').click(); await p.waitForTimeout(600);
  check('team table lists everyone', await p.locator('.team-row:not(.team-head)').count() === 3);
  /* Everyone here is active, so Active earns no column and no accent: the row
     names the exception and the ⋯ carries the change. */
  check('no row carries a state select',
    await p.locator('.team-row select[data-f="active"]').count() === 0);
  check('and no row is painted with the accent',
    await p.locator('#teamList .state-select').count() === 0);
  const selfRow = p.locator('.team-row:not(.team-head)').first();
  await selfRow.locator('[data-a="menu"]').click(); await p.waitForTimeout(200);
  check('a person cannot stand themselves down',
    await selfRow.locator('[data-a="state"]').count() === 0);
  await p.keyboard.press('Escape');

  /* People sit under the group they are in, so the answer to "who is in
     Sales" is a heading rather than a column of identical selects. */
  // innerText would come back shouting: the heading is uppercased in CSS.
  const cats = () => p.locator('#teamList .svc-cat').evaluateAll(els => els.map(e => e.textContent).join(','));
  check('members are grouped under their group', await cats() === 'Admin,Marketing,Sales', await cats());
  check('and the row no longer repeats the group', await p.locator('.team-row select[data-f="role"]').count() === 0);
  const rowOrder = await p.locator('#teamList .team-table > div').evaluateAll(
    els => els.filter(e => e.matches('.svc-cat, .team-row:not(.team-head)')).map(e => e.matches('.svc-cat') ? '[' + e.textContent + ']' : e.querySelector('b').textContent.trim().split(' ')[0]).join(' '));
  check('each person sits under their own heading', rowOrder === '[Admin] ADspace [Marketing] Aisyah [Sales] Qiao', rowOrder);

  check('groups listed', await p.locator('.group-row').count() === 3);
  const grants = await p.locator('.group-grants').allInnerTexts();
  check('a group states what it opens', grants[0] === 'Everything' && grants[1].startsWith('Clients · Content Review'), grants.join(' | '));
  check('and no longer needs a column per switch', await p.locator('.group-row input[type=checkbox]').count() === 0);
  check('the Admin group cannot be edited', await p.locator('.group-row').first().locator('.kmenu-btn').count() === 0);

  // A switch now lives in the panel that edits the group, as a service does.
  await p.locator('.group-row').nth(1).locator('[data-a="menu"]').click(); await p.waitForTimeout(150);
  await p.locator('.group-row').nth(1).locator('[data-a="rename"]').click(); await p.waitForTimeout(250);
  check('Edit opens the group with its switches set',
    await p.locator('#grFlags input[data-f="can_clients"]').isChecked() &&
    !(await p.locator('#grFlags input[data-f="can_activity"]').isChecked()));
  await p.locator('#grFlags input[data-f="can_activity"]').check();
  await p.locator('#grSave').click(); await p.waitForTimeout(500);
  check('a group switch saves', await p.evaluate(() => window.__DB.team_roles.find(r => r.slug === 'account').can_activity === true));
  check('and the row says so', (await p.locator('.group-grants').nth(1).innerText()).includes('Activity record'));

  // Moving somebody between groups is Edit, where a rare action belongs.
  const aisyah = p.locator('.team-row:not(.team-head)').filter({ hasText: 'Aisyah' });
  await aisyah.locator('[data-a="menu"]').click(); await p.waitForTimeout(150);
  await aisyah.locator('[data-a="edit"]').click(); await p.waitForTimeout(250);
  check('Edit opens the person as they stand',
    await p.inputValue('#tmName') === 'Aisyah' && await p.inputValue('#tmRole') === 'account');
  await p.selectOption('#tmRole', 'sales'); await p.locator('#tmSave').click(); await p.waitForTimeout(600);
  check('a member changes group', await p.evaluate(() => window.__DB.team_members.find(t => t.name === 'Aisyah').role === 'sales'));
  check('and moves under the other heading', await cats() === 'Admin,Sales', await cats());
  // add a group
  await p.locator('#groupAdd').click(); await p.waitForTimeout(200);
  check('a new group starts on Clients and nothing else',
    await p.locator('#grFlags input[data-f="can_clients"]').isChecked() &&
    await p.locator('#grFlags input:checked').count() === 1);
  await p.fill('#grName', 'Finance');
  await p.locator('#grFlags input[data-f="can_billing"]').check();
  await p.locator('#grSave').click(); await p.waitForTimeout(500);
  check('a group can be added', await p.locator('.group-row').count() === 4 && await p.evaluate(() => !!window.__DB.team_roles.find(r => r.slug === 'finance')));
  check('with the switches it was given',
    await p.evaluate(() => { const r = window.__DB.team_roles.find(x => x.slug === 'finance'); return r.can_clients === true && r.can_billing === true && r.can_review === false; }));
  check('an unused group can be deleted', await p.locator('.group-row').filter({ hasText: 'Finance' }).locator('[data-a="del"]').count() === 1);
  // Aisyah was moved to Sales above; put her back before the counts below.
  await p.evaluate(() => { window.__DB.team_members.find(t => t.name === 'Aisyah').role = 'account'; window.__persist && window.__persist(); });
  // add a person and invite
  await p.locator('#teamAdd').click(); await p.waitForTimeout(300);
  await p.fill('#tmName', 'Wei Ling'); await p.fill('#tmEmail', 'weiling@adspacestudios.com');
  await p.selectOption('#tmRole', 'sales');
  await p.locator('#tmSave').click(); await p.waitForTimeout(800);
  check('person added to the team', await p.locator('.team-row:not(.team-head)').count() === 4);
  const invited = await p.evaluate(() => (window.__signed || []).filter(x => x.name === 'invite-member'));
  check('an invitation was requested for them', invited.length === 1 && invited[0].body.email === 'weiling@adspacestudios.com');
  console.log('  message: ' + await p.locator('#teamMsg').innerText());
  check('the message says the invitation went out', /invitation sent to/i.test(await p.locator('#teamMsg').innerText()));

  // Standing somebody down, and putting them back, both from the ⋯.
  const wl = () => p.locator('.team-row:not(.team-head)').filter({ hasText: 'Wei Ling' });
  await wl().locator('[data-a="menu"]').click(); await p.waitForTimeout(200);
  check('another person is set inactive from the \u22ef',
    (await wl().locator('[data-a="state"]').innerText()) === 'Set inactive');
  await wl().locator('[data-a="state"]').click(); await p.waitForTimeout(600);
  check('the change is stored',
    await p.evaluate(() => window.__DB.team_members.find(t => t.name === 'Wei Ling').active === false));
  check('and the row names it rather than colouring it',
    /Inactive/.test(await wl().innerText()) && await p.locator('#teamList .state-select').count() === 0);
  await wl().locator('[data-a="menu"]').click(); await p.waitForTimeout(200);
  check('and the same item puts them back',
    (await wl().locator('[data-a="state"]').innerText()) === 'Set active');
  await wl().locator('[data-a="state"]').click(); await p.waitForTimeout(600);
  check('back on',
    await p.evaluate(() => window.__DB.team_members.find(t => t.name === 'Wei Ling').active === true));
  await p.screenshot({ path: process.argv[2] + '/d-team.png' });
  await p.close();

  // sales
  p = await page('qiaorou@adspacestudios.com');
  console.log('  sales sees: ' + await visibleNav(p));
  check('sales sees Clients and Services', (await visibleNav(p)) === 'Clients, Services');
  check('sales does not see the activity record', await p.locator('#activityOpen').isHidden());
  check('sales lands on Clients', await p.locator('#sectionClients').isVisible());
  await p.goto('http://127.0.0.1:8899/admin/?s=campaigns', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('qiaorou@adspacestudios.com')); await p.waitForTimeout(800);
  check('a refused address falls back to what is allowed', await p.locator('#sectionClients').isVisible() && await p.locator('#sectionCampaigns').isHidden());
  // Aisyah moved to Sales above; put her back for the account check.
  await p.evaluate(() => { window.__DB.team_members.find(t => t.name === 'Aisyah').role = 'account'; window.__persist && window.__persist(); });
  await p.close();

  // account: sees the work, cannot remove
  p = await page('aisyah@adspacestudios.com');
  console.log('  account sees: ' + await visibleNav(p));
  check('account does not see Team', !(await visibleNav(p)).includes('Team'));
  check('removal controls are not drawn for account', await p.evaluate(() => document.body.classList.contains('no-remove')));
  await p.close();

  // a login that is not on the team
  p = await page('stranger@example.com');
  check('a login with no team row sees the notice and nothing else',
    await p.locator('#noTeamShell').isVisible() && await p.locator('#console').isHidden());
  check('the notice names them', (await p.locator('#noTeamWho').innerText()) === 'stranger@example.com');
  await p.close();

  /* Signed in is not allowed in. The console chrome names every section of
     the tool, and it used to be drawn the moment a session existed, for as
     long as the me() call took, to anybody at all. Nothing is shown until the
     database has said who this is. */
  const SLOW = `(function () {
    var make = window.supabase.createClient;
    window.supabase.createClient = function () {
      var c = make.apply(this, arguments), rpc = c.rpc;
      c.rpc = function (name, args) {
        var q = rpc.call(c, name, args);
        if (name !== 'me') return q;
        return new Promise(function (go) { setTimeout(function () { q.then(go); }, 1500); });
      };
      return c;
    };
  })();`;
  p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SLOW }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('stranger@example.com'));
  await p.waitForTimeout(500);
  check('the console is not drawn while access is still being decided',
    await p.locator('#console').isHidden() &&
    !(await p.locator('.navitem').first().isVisible()) &&
    !(await p.locator('#noTeamShell').isVisible()));
  await p.waitForTimeout(1600);
  check('and the cover arrives once it is', await p.locator('#noTeamShell').isVisible());
  await p.close();

  // The same wait must not blank the console for somebody who does belong.
  p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SLOW }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(500);
  check('a colleague waits too, rather than seeing it early',
    await p.locator('#console').isHidden());
  await p.waitForTimeout(1600);
  check('and the console arrives whole',
    await p.locator('#console').isVisible() && (await visibleNav(p)).includes('Team'));
  await p.close();

  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  if (errs.length) bad++;
  await b.close();
  console.log(bad ? 'team: PROBLEM' : 'team: ok');
})();
