/*
 * The client record's Overview, in the two shapes it actually has: an active
 * client with contacts, services, letters and calls behind it, and a lead with
 * almost none of that. Both at 1280 and at 390, because the section that reads
 * well when it is full is not the one that has to be checked.
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const OUT = process.env.OUT || (T + '/');
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const SEED = fs.readFileSync(T + '/crmshot.js', 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];

/* A populated active client: the record with everything on it. Laman Citra is
   the fixture every other suite already uses, so this adds the rows it has
   never had rather than a second client nobody else knows about. */
const FULL = `(function(){ var D = window.__DB;
  var c = D.clients.filter(function(x){ return x.id === 'c1'; })[0];
  if (c) {
    c.owner = 'Qiao Rou'; c.industry = 'Property'; c.source = 'referral';
    c.commence = '1_3'; c.deal_value = 18400;
    c.legal_name = 'LAMAN CITRA SDN BHD'; c.company_no = '202301009988';
    c.billing_address = '12, Jalan Molek 1/5, 81100 Johor Bahru, Johor';
    c.website = 'lamancitra.com';
    c.created_at = new Date(Date.now() - 248 * 864e5).toISOString();
  }
  D.client_services = D.client_services || [];
  D.client_services.push({ id:'sv1', client_id:'c1', slug:'social-media', label:'Social media management',
    qty:1, rate:3200, tenure:6, start_on:'2026-04-01', state:'confirmed' });
  D.client_services.push({ id:'sv2', client_id:'c1', slug:'content-creation', label:'Content creation',
    qty:2, rate:900, tenure:6, start_on:'2026-04-01', state:'confirmed' });
  D.client_services.push({ id:'sv3', client_id:'c1', slug:'ads', label:'Paid advertising',
    qty:1, rate:1500, tenure:3, start_on:'2026-07-01', state:'quoted' });
  D.client_touches = D.client_touches || [];
  D.client_touches.push({ id:'t1', client_id:'c1', kind:'call', happened_at:'2026-09-11',
    contact_name:'Mr Lim', summary:'Discussed the Q4 plan and the phase 2 launch dates.',
    next_action:'Send the revised proposal', next_at:'2026-09-19', by_whom:'Qiao Rou' });
  D.client_touches.push({ id:'t2', client_id:'c1', kind:'visit', happened_at:'2026-08-28',
    contact_name:'Mr Lim', summary:'Site visit at the show unit with the content team.', by_whom:'Qiao Rou' });
  D.client_touches.push({ id:'t3', client_id:'c1', kind:'whatsapp', happened_at:'2026-08-14',
    contact_name:'Ms Tan', summary:'Confirmed the billing address for the letter.', by_whom:'Aisyah' });
  D.client_documents = D.client_documents || [];
  D.client_documents.push({ id:'d1', client_id:'c1', kind:'offer', number:'AQT/INT/2608001',
    issued_at:'2026-08-20', subtotal:18400, tax:1472, total:19872 });
  D.activity_log = D.activity_log || [];
  [['client.billing','complete','2026-08-21T09:12:00Z'],
   ['client.stage','Proposal sent to Active','2026-08-22T10:04:00Z'],
   ['document.issued','AQT/INT/2608001','2026-08-20T16:30:00Z']].forEach(function(a,i){
    D.activity_log.push({ id:'al'+i, action:a[0], subject:'Laman Citra', detail:a[1],
      actor:'Qiao Rou', created_at:a[2] });
  });
  window.__persist && window.__persist(); })();`;

async function open(ctx, url, seed) {
  const p = await ctx.newPage();
  p.on('pageerror', e => { console.log('PAGEERROR ' + e.message); });
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + SEED + (seed || '') }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib={};' }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899' + url, { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(1200);
  // Park the pointer, or whatever the last click landed under is caught hovered.
  await p.mouse.move(2, 2);
  await p.waitForTimeout(250);
  return p;
}

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const [w, h, tag] of [[1280, 1100, '1280'], [390, 1400, '390']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h },
      hasTouch: tag === '390', isMobile: tag === '390' });

    const full = await open(ctx, '/admin/?s=clients&client=laman-citra', FULL);
    await full.screenshot({ path: OUT + 'ov-active-' + tag + '.png', fullPage: tag === '390' });
    console.log('shot ov-active-' + tag);
    await full.close();

    // A lead: keyed in this morning, nothing on it yet.
    const lead = await open(ctx, '/admin/?s=clients&client=dale-cecil');
    await lead.screenshot({ path: OUT + 'ov-lead-' + tag + '.png', fullPage: tag === '390' });
    console.log('shot ov-lead-' + tag);
    await lead.close();

    await ctx.close();
  }
  await b.close();
})().catch(e => { console.error('FAIL', e); process.exit(1); });
