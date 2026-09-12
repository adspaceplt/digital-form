const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');

const STUB = fs.readFileSync(process.argv[2] + '/stub.js', 'utf8');
const BASE = 'http://127.0.0.1:8899';
const errs = [];
const out = [];
const say = (s) => { out.push(s); console.log(s); };

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
  say('sidebar foot:   ' + (await page.locator('.sidebar-foot').innerText()).replace(/\n/g, ' | '));
  const so = page.locator('#signOut');
  const box = await so.boundingBox();
  const st = await so.evaluate(el => { const c = getComputedStyle(el); return c.borderStyle + ' ' + c.borderWidth + ' / svg=' + !!el.querySelector('svg'); });
  say('sign out: visible=' + await so.isVisible() + ' w=' + Math.round(box.width) + ' border=' + st);
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
  say('rows: ' + await page.locator('.slink').count() + ' count=' + await page.locator('#linkCount').innerText());
  say('first row: ' + (await page.locator('.slink').first().innerText()).replace(/\n/g, ' | '));

  // Search
  await page.fill('#linkSearch', 'raya');
  await page.waitForTimeout(200);
  say('search raya -> ' + await page.locator('.slink').count() + ' (' + await page.locator('#linkCount').innerText() + ')');
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
  say('after add: rows=' + await page.locator('.slink').count() +
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
})().catch(e => { console.error('FAIL', e); process.exit(1); });
