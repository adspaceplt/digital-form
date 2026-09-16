const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');

const STUB = fs.readFileSync(process.argv[2] + '/stub.js', 'utf8');
const BASE = 'http://127.0.0.1:8899';
const errs = [];
const out = [];
const say = (s) => { out.push(s); console.log(s); };
let bad = 0;
const check = (l, ok, x) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (x ? '  ' + x : '')); if (!ok) bad++; };

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  page.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE ' + m.text()); });

  // The real Supabase bundle never loads here; the stub answers for it.
  await page.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  await page.goto(BASE + '/admin/', { waitUntil: 'networkidle' });

  say('--- signed out ---');
  say('topbar kicker: ' + await page.locator('.brand-kicker').innerText());
  say('console hidden: ' + await page.locator('#console').isHidden());

  await page.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await page.waitForTimeout(400);

  say('--- signed in ---');
  say('sidebar kicker: ' + await page.locator('.sidebar-kicker').innerText());
  /* Who you are, the register and the way out live behind the account control
     at the end of the bar, not in a block at the foot of the sidebar. */
  say('account button: visible=' + await page.locator('#acctBtn').isVisible() +
      ' mark=' + await page.locator('#acctMark').innerText());
  check('the sidebar carries no account block',
    await page.locator('.sidebar-foot').count() === 0);
  await page.locator('#acctBtn').click(); await page.waitForTimeout(250);
  const so = page.locator('#signOut');
  say('account menu: ' + (await page.locator('#acctMenu').innerText()).replace(/\n/g, ' | '));
  check('sign out is in the account menu', await so.isVisible());
  check('and so is the address', (await page.locator('#whoami').innerText()).includes('@'));
  await page.keyboard.press('Escape'); await page.waitForTimeout(200);
  check('Escape closes it', await page.locator('#acctMenu').isHidden());
  say('nav items:      ' + (await page.locator('.navitem').allInnerTexts()).join(' , '));
  say('section title:  ' + await page.locator('#sectionTitle').innerText());
  say('activity link visible: ' + await page.locator('#activityOpen').isVisible());

  // Activity sheet
  await page.locator('#activityOpen').click();
  await page.waitForTimeout(250);
  say('sheet open: ' + await page.locator('#activitySheet').isVisible() +
      ' rows=' + await page.locator('#activityList .act').count());
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);
  say('sheet after Esc: ' + await page.locator('#activitySheet').isHidden());

  // Smart Links
  await page.locator('.navitem[data-section="links"]').click();
  await page.waitForTimeout(400);
  say('--- smart links ---');
  say('title: ' + await page.locator('#sectionTitle').innerText());
  say('review hidden: ' + await page.locator('#sectionReview').isHidden());
  say('activity link now: ' + await page.locator('#activityOpen').isVisible());
  say('rows: ' + await page.locator('.link-row:not(.crm-head)').count() + ' count=' + await page.locator('#linkCount').innerText());
  say('first row: ' + (await page.locator('.link-row:not(.crm-head)').first().innerText()).replace(/\n/g, ' | '));

  // Search
  await page.fill('#linkSearch', 'raya');
  await page.waitForTimeout(200);
  say('search raya -> ' + await page.locator('.link-row:not(.crm-head)').count() + ' (' + await page.locator('#linkCount').innerText() + ')');
  await page.fill('#linkSearch', '');
  await page.waitForTimeout(200);

  // Add one
  await page.locator('#showAddLink').click();
  await page.fill('#newSlug', 'Merdeka 2026');
  await page.fill('#newTarget', 'example.com/merdeka');
  await page.locator('#saveLink').click();
  await page.waitForTimeout(300);
  say('bad slug rejected: ' + await page.locator('#linkMsg').innerText());
  await page.fill('#newSlug', 'merdeka-2026');
  await page.locator('#saveLink').click();
  await page.waitForTimeout(400);
  say('after add: rows=' + await page.locator('.link-row:not(.crm-head)').count() +
      ' https-normalised=' + await page.evaluate(() => (window.__DB.links.find(l => l.slug === 'merdeka-2026') || {}).target_url));

  // Duplicate
  await page.locator('#showAddLink').click();
  await page.fill('#newSlug', 'raya-2026');
  await page.fill('#newTarget', 'https://x.com');
  await page.locator('#saveLink').click();
  await page.waitForTimeout(250);
  say('duplicate blocked: ' + await page.locator('#linkMsg').innerText());
  await page.locator('#cancelAddLink').click();

  // Bulk import, mixed separators + one bad line
  await page.locator('#showImport').click();
  await page.fill('#importText',
    'deepavali\thttps://example.com/deepavali\tDeepavali\n' +
    'cny-2027, https://example.com/cny, Chinese New Year\n' +
    'open-house   example.com/oh\n' +
    'BROKEN LINE ONLY\n' +
    'spring-launch https://example.com/spring-v2 Spring updated');
  await page.locator('#runImport').click();
  await page.waitForTimeout(500);
  say('import msg: ' + await page.locator('#importMsg').innerText());
  say('total links: ' + await page.evaluate(() => window.__DB.links.length));
  say('spring updated -> ' + await page.evaluate(() => window.__DB.links.find(l => l.slug === 'spring-launch').target_url));

  await page.screenshot({ path: process.argv[2] + '/links-1280.png', fullPage: false });
  await page.locator('.navitem[data-section="review"]').click();
  await page.waitForTimeout(300);
  say('back to review: ' + await page.locator('#sectionTitle').innerText() +
      ' activity link=' + await page.locator('#activityOpen').isVisible());
  await page.screenshot({ path: process.argv[2] + '/review-1280.png' });

  // Phone
  await page.setViewportSize({ width: 390, height: 780 });
  await page.waitForTimeout(300);
  const doc = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  say('--- 390px --- overflow: ' + (doc.sw > doc.cw ? 'YES ' + doc.sw + '>' + doc.cw : 'none'));
  await page.locator('#navToggle').click();
  await page.waitForTimeout(300);
  await page.locator('.navitem[data-section="links"]').click();
  await page.waitForTimeout(400);
  const d2 = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  say('links @390 overflow: ' + (d2.sw > d2.cw ? 'YES ' + d2.sw + '>' + d2.cw : 'none') +
      ' drawer closed=' + !(await page.locator('#sidebar').evaluate(e => e.classList.contains('is-open'))));
  await page.screenshot({ path: process.argv[2] + '/links-390.png', fullPage: false });

  say('--- errors ---');
  say(errs.length ? errs.join('\n') : 'none');
  await browser.close();
  console.log(bad ? 'run: ' + bad + ' FAIL' : 'run: ok');
  if (bad) process.exit(1);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
