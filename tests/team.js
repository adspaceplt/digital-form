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
  check('team table lists everyone', await p.locator('.team-row').count() === 3);
  check('the admin cannot deactivate themselves',
    await p.locator('.team-row').first().locator('select[data-f="active"]').isDisabled());
  check('groups listed', await p.locator('.group-row').count() === 3);
  check('the Admin group is locked', await p.locator('.group-row').first().locator('input[data-f="can_remove"]').isDisabled());
  // a switch on the Account group saves at once
  const account = p.locator('.group-row').nth(1);
  await account.locator('input[data-f="can_activity"]').check(); await p.waitForTimeout(500);
  check('a group switch saves at once', await p.evaluate(() => window.__DB.team_roles.find(r => r.slug === 'account').can_activity === true));
  // move Aisyah to Sales
  const aisyah = p.locator('.team-row').filter({ hasText: 'Aisyah' });
  await aisyah.locator('select[data-f="role"]').selectOption('sales'); await p.waitForTimeout(500);
  check('a member changes group', await p.evaluate(() => window.__DB.team_members.find(t => t.name === 'Aisyah').role === 'sales'));
  // add a group
  await p.locator('#groupAdd').click(); await p.waitForTimeout(200);
  await p.fill('#grName', 'Finance'); await p.locator('#grSave').click(); await p.waitForTimeout(500);
  check('a group can be added', await p.locator('.group-row').count() === 4 && await p.evaluate(() => !!window.__DB.team_roles.find(r => r.slug === 'finance')));
  check('an unused group can be deleted', await p.locator('.group-row').filter({ hasText: 'Finance' }).locator('[data-a="del"]').count() === 1);
  // add a person and invite
  await p.locator('#teamAdd').click(); await p.waitForTimeout(300);
  await p.fill('#tmName', 'Wei Ling'); await p.fill('#tmEmail', 'weiling@adspacestudios.com');
  await p.selectOption('#tmRole', 'sales');
  await p.locator('#tmSave').click(); await p.waitForTimeout(800);
  check('person added to the team', await p.locator('.team-row').count() === 4);
  const invited = await p.evaluate(() => (window.__signed || []).filter(x => x.name === 'invite-member'));
  check('an invitation was requested for them', invited.length === 1 && invited[0].body.email === 'weiling@adspacestudios.com');
  console.log('  message: ' + await p.locator('#teamMsg').innerText());
  check('the message says the invitation went out', /invitation sent to/i.test(await p.locator('#teamMsg').innerText()));
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

  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  if (errs.length) bad++;
  await b.close();
  console.log(bad ? 'team: PROBLEM' : 'team: ok');
})();
