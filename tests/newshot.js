// Screenshots of the client record, the billing fold and the rate card at
// 1280 and at 390 with a coarse pointer, with services and a document seeded.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
const OUT = process.argv[3] || (process.argv[2] + '/walk');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const [tag, opts] of [['1280', { viewport: { width: 1280, height: 900 } }],
                             ['390', { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true }]]) {
    const ctx = await b.newContext(opts);
    const p = await ctx.newPage();
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
    await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib=null;' }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    await p.goto('http://127.0.0.1:8899/admin/?s=clients', { waitUntil: 'networkidle' });
    await p.evaluate(() => {
      const D = window.__DB;
      D.client_contacts.push({ id: 'ct2', client_id: 'c1', name: 'Ms Tan', role: 'Finance', phone: '0198887777', whatsapp: '0198887777', email: 'tan@lc.com', lang: 'zh', is_primary: false });
      D.client_services.push(
        { id: 's1', client_id: 'c1', service_slug: 'pkg-b', label: 'Package B · 2 platforms · 4 contents', unit: 'Per month, 6 month minimum', qty: 1, rate: 2830, tenure: 6, start_on: '2026-10-12', state: 'confirmed' },
        { id: 's2', client_id: 'c1', service_slug: 'koc-10', label: 'KOC package · 10 creators', unit: 'Per campaign', qty: 1, rate: 4500, tenure: 1, start_on: null, state: 'quoted' },
        { id: 's3', client_id: 'c1', service_slug: null, label: 'Launch video', unit: null, qty: 1, rate: 20000, tenure: 1, start_on: null, state: 'enquired', note: 'One on-site shoot' });
      D.client_documents.push({ id: 'd1', client_id: 'c1', kind: 'cover', number: 'AQT/INT/2609001', issued_at: '2026-09-12', market: 'MY', subtotal: 21480, tax: 1718.4, total: 23198.4, bill_to: {}, lines: [], issued_by: 'adspacestudios@gmail.com', created_at: '2026-09-12T08:00:00Z', voided_at: null });
      window.__signIn('adspacestudios@gmail.com');
    });
    await p.waitForTimeout(800);
    await p.locator('.crm-row').filter({ hasText: 'Laman Citra' }).click(); await p.waitForTimeout(900);
    await p.screenshot({ path: OUT + '/record-' + tag + '.png', fullPage: true });
    await p.locator('#crmBillToggle').click(); await p.waitForTimeout(300);
    await p.locator('#crmBillBody').screenshot({ path: OUT + '/billing-' + tag + '.png' });
    await p.locator('#crmBillToggle').click(); await p.waitForTimeout(200);
    if (tag === '390') { await p.locator('#navToggle').click(); await p.waitForTimeout(300); }
    await p.locator('.navitem[data-section="services"]').click(); await p.waitForTimeout(700);
    await p.screenshot({ path: OUT + '/ratecard-' + tag + '.png', fullPage: true });
    console.log(tag + ' errors: ' + (errs.join(' | ') || 'none'));
    await ctx.close();
  }
  await b.close();
})();
