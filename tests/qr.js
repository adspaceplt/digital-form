const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub.js', 'utf8');
const errs = [];
const say = s => console.log(s);

// Stands in for qrcodejs: draws a canvas and records what it was asked to encode.
const QRLIB = `
window.QRCode = function (el, o) {
  var c = document.createElement('canvas');
  c.width = o.width; c.height = o.height;
  var x = c.getContext('2d');
  x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height);
  x.fillStyle = '#000';
  for (var i = 0; i < o.text.length; i++) x.fillRect((i*7) % c.width, (i*11) % c.height, 6, 6);
  c.setAttribute('data-text', o.text);
  el.appendChild(c);
};
window.QRCode.CorrectLevel = { L:1, M:0, Q:3, H:2 };
`;

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 950 }, acceptDownloads: true });
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('console', m => { if (m.type() === 'error' && !/404|Failed to load resource/i.test(m.text())) errs.push('CONSOLE ' + m.text()); });
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QRLIB }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));

  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(400);
  await p.locator('.navitem[data-section="links"]').click();
  await p.waitForTimeout(500);

  say('qr buttons on rows: ' + await p.locator('.slink [data-a="qr"]').count());
  await p.locator('.slink [data-a="qr"]').first().click();
  await p.waitForTimeout(400);
  say('sheet heading: ' + await p.locator('#qrHeading').innerText());
  say('empty state: ' + await p.locator('#qrList').innerText());

  await p.fill('#qrLabel', 'Mall poster A');
  await p.locator('#qrNew').click();
  await p.waitForTimeout(500);
  say('codes: ' + await p.locator('.qrrow').count());
  const encoded = await p.locator('.qrrow-img canvas').first().getAttribute('data-text');
  say('encoded: ' + encoded);
  say('shown url: ' + await p.locator('.qrrow-url').first().innerText());
  say('match: ' + (encoded === await p.locator('.qrrow-url').first().innerText()));
  say('label: ' + await p.locator('.qrrow-body b').first().innerText());

  // a second code for the same link
  await p.fill('#qrLabel', 'Roadshow bunting');
  await p.locator('#qrNew').click();
  await p.waitForTimeout(500);
  const both = await p.locator('.qrrow-img canvas').evaluateAll(cs => cs.map(c => c.getAttribute('data-text')));
  say('two codes, distinct: ' + (both.length === 2 && both[0] !== both[1]));
  say('same slug in both: ' + both.every(u => u.indexOf('go.adspace.me/spring-launch?q=') > -1));

  // revoke the first
  p.on('dialog', d => d.accept());
  await p.locator('.qrrow').first().locator('[data-q="toggle"]').click();
  await p.waitForTimeout(500);
  say('first row class: ' + await p.locator('.qrrow').first().getAttribute('class'));
  say('revoked tag: ' + await p.locator('.qrrow').first().locator('.act-tag').count());
  say('button now: ' + await p.locator('.qrrow').first().locator('[data-q="toggle"]').innerText());
  say('second untouched: ' + await p.locator('.qrrow').nth(1).getAttribute('class'));
  say('db active flags: ' + await p.evaluate(() => window.__DB.link_qrs.map(q => q.active).join(',')));

  // encoded text must not change when revoked - the picture is permanent
  const after = await p.locator('.qrrow-img canvas').first().getAttribute('data-text');
  say('encoded unchanged after revoke: ' + (after === both[0]));

  // restore
  await p.locator('.qrrow').first().locator('[data-q="toggle"]').click();
  await p.waitForTimeout(500);
  say('after restore: ' + await p.locator('.qrrow').first().getAttribute('class'));

  // download
  const dl = p.waitForEvent('download', { timeout: 5000 }).catch(() => null);
  await p.locator('.qrrow').first().locator('[data-q="dl"]').click();
  const file = await dl;
  say('download: ' + (file ? file.suggestedFilename() : 'none'));

  await p.screenshot({ path: process.argv[2] + '/qr.png' });

  // no duplicate canvases after repaint
  await p.locator('#qrSheetClose').click();
  await p.waitForTimeout(200);
  await p.locator('.slink [data-a="qr"]').first().click();
  await p.waitForTimeout(500);
  say('canvases after reopen (should be 2): ' + await p.locator('.qrrow-img canvas').count());

  // phone
  await p.setViewportSize({ width: 390, height: 800 });
  await p.waitForTimeout(300);
  const d = await p.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  say('390 overflow: ' + (d.sw > d.cw ? 'YES ' + d.sw + '>' + d.cw : 'none'));

  await ctx.close();

  // ---- library fails to load ----
  const ctx2 = await b.newContext({ viewport: { width: 1100, height: 800 } });
  const p2 = await ctx2.newPage();
  p2.on('pageerror', e => errs.push('NOLIB PAGEERROR ' + e.message));
  await p2.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p2.route('**/qrcode*.js', r => r.abort());
  await p2.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p2.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await p2.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p2.waitForTimeout(400);
  await p2.locator('.navitem[data-section="links"]').click();
  await p2.waitForTimeout(400);
  await p2.locator('.slink [data-a="qr"]').first().click();
  await p2.waitForTimeout(300);
  await p2.fill('#qrLabel', 'No library');
  await p2.locator('#qrNew').click();
  await p2.waitForTimeout(500);
  say('--- library blocked ---');
  say('fallback text: ' + await p2.locator('.qrrow-img').first().innerText());
  say('row still usable: url shown = ' + await p2.locator('.qrrow-url').first().innerText());
  await ctx2.close();

  await b.close();
  say('--- errors ---');
  say(errs.length ? errs.join('\n') : 'none');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
