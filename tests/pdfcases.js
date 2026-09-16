/*
 * The letter drawn against its extremes, and asserted on where things land.
 *
 * tests/pdfreal.js drives the console and decodes one letter. This renders the
 * cases a real client list produces and that a single fixture never reaches: a
 * long registered name, a service list that runs past one page, a one-off
 * letter with no term, and a letter with nothing but a single cheap line. The
 * faults it is here for are positional — a closing stranded at the top of a
 * page, an execution block split across two, a field off the media box — and
 * every one of those decodes perfectly as text.
 *
 * It writes each case out as a PDF so tests/pdfshot.js can rasterise them and
 * they can be read.
 *
 * Usage: node tests/pdfcases.js tests
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');

let bad = 0;
const check = (l, ok, x) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (x ? '  ' + x : '')); if (!ok) bad++; };

const line = (label, rate, tenure, detail) => ({
  label: label, qty: 1, rate: rate, tenure: tenure || 6, unit: 'per month',
  detail: detail || '', tax: true, state: 'quoted', start_on: '2026-10-01'
});

/* A package's inclusions are what push a letter onto a second page, so the
   long case carries the real thing rather than lorem. */
const FULL = ['Up to 2 platforms',
  '4 contents each month: 1 graphic and 3 reels up to 60s, or 4 reels up to 60s',
  'Dedicated account management and content posting',
  'Strategic content planning for every deliverable',
  'Professional copywriting for every planned deliverable',
  'One-time on-site shoot for Reels content',
  'Basic accounts analytics report'].join('\n');

const CASES = [
  { name: 'short', legal: 'ACE SDN BHD', contact: 'Lim',
    lines: [line('Social media management', 1500, 6)] },
  { name: 'longname',
    legal: 'PERBADANAN PEMBANGUNAN PERUMAHAN DAN HARTANAH NUSAJAYA SELATAN BERHAD',
    contact: 'Datuk Seri Mohd Firdaus bin Abdul Rahman Al-Hafiz',
    contactRole: 'Executive Director, Corporate Communications and Branding',
    lines: [line('Social media management', 3200, 12, FULL)] },
  { name: 'manylines',
    legal: 'MULTI SERVICE HOLDINGS SDN BHD', contact: 'Tan',
    lines: [line('Package A', 3200, 6, FULL), line('Package B', 2800, 6, FULL),
            line('Paid advertising', 1500, 6, FULL), line('SEO retainer', 900, 6, FULL),
            line('Content shoot', 2400, 6, FULL)] },
  { name: 'oneoff',
    legal: 'ONE OFF EVENTS SDN BHD', contact: 'Chan',
    lines: [{ label: 'Launch video, up to 60 seconds', qty: 1, rate: 20000, tenure: 1,
              unit: 'One on-site shoot', detail: '', tax: true, state: 'quoted' }] }
];

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await (await b.newContext()).newPage();
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(T + '/pdfx/node_modules/pdf-lib/dist/pdf-lib.min.js', 'utf8') }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(T + '/pdfx/node_modules/@pdf-lib/fontkit/dist/fontkit.umd.min.js', 'utf8') }));
  await p.goto('http://127.0.0.1:8899/admin/?s=clients', { waitUntil: 'networkidle' });

  /* pdf.js, served off the same local server, reads back where every glyph
     actually landed. The long-name case ran the Attn line off the right edge
     and the text still decoded perfectly, because a clipped string is clipped
     by the media box and not by the stream: nothing but the geometry says so. */
  const PDFJS_BASE = 'http://127.0.0.1:8899/tests/pdfx/node_modules/pdfjs-dist/build/';
  let canMeasure = true;
  try { await p.addScriptTag({ url: PDFJS_BASE + 'pdf.min.js' }); }
  catch (e) { canMeasure = false; console.log('note: pdf.js not available, bounds not measured'); }

  const PDFLib = require(require('path').resolve(T, 'pdfx/node_modules/pdf-lib'));
  const WANT = ['acceptance_authorised_signatory', 'acceptance_name',
                'acceptance_designation', 'acceptance_date'];

  for (const c of CASES) {
    const b64 = await p.evaluate(async (cc) => {
      const doc = {
        number: 'AQL/TC' + cc.name.toUpperCase().slice(0, 4) + '/260901', kind: 'offer',
        issued_at: '2026-09-16', market: 'MY', issued_by: 'Qiao Rou',
        subtotal: 0, tax: 0, total: 0,
        bill_to: { name: cc.legal, legal_name: cc.legal, contact: cc.contact,
                   contact_role: cc.contactRole || 'Director', address: '1 Jalan Test' },
        lines: cc.lines
      };
      const bytes = await window.ADspaceDocs.render(doc);
      let s = '';
      for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
      return btoa(s);
    }, c);

    const file = T + '/case-' + c.name + '.pdf';
    fs.writeFileSync(file, Buffer.from(b64, 'base64'));

    const pdf = await PDFLib.PDFDocument.load(fs.readFileSync(file));
    const n = pdf.getPageCount();
    const form = pdf.getForm();
    const names = form.getFields().map(f => f.getName());
    check(c.name + ': the four acceptance fields exist',
      WANT.every(w => names.indexOf(w) > -1), n + ' pages, ' + names.length + ' fields');

    /* Every widget sits on one page and inside it. A field drawn past the
       media box is a field no reader will show. */
    let offPage = 0, pagesUsed = {};
    const pageRefs = pdf.getPages().map(pg => pg.ref);
    WANT.forEach(w => {
      if (names.indexOf(w) < 0) return;
      form.getTextField(w).acroField.getWidgets().forEach(wd => {
        const r = wd.getRectangle();
        const pref = wd.P();
        const idx = pageRefs.findIndex(x => String(x) === String(pref));
        pagesUsed[idx] = true;
        const size = pdf.getPage(idx < 0 ? n - 1 : idx).getSize();
        if (r.x < 0 || r.y < 0 || r.width <= 0 || r.height <= 0 ||
            r.x + r.width > size.width + 0.5 || r.y + r.height > size.height + 0.5) offPage++;
      });
    });
    check(c.name + ': no field leaves its page', offPage === 0, offPage + ' outside');
    /* The execution block is one act and stays on one sheet: a stamp box on a
       page of its own is a signature that proves nothing about what it signs. */
    check(c.name + ': the execution block is all on one page',
      Object.keys(pagesUsed).length === 1, 'pages ' + Object.keys(pagesUsed).join(','));

    /* Nothing drawn may cross the margins. 54pt each side is the text column;
       the letterhead and the foot sit inside it too, so one bound covers the
       page. A tolerance of a point absorbs the glyph advance pdf.js reports
       for a trailing space. */
    if (canMeasure) {
      const over = await p.evaluate(async ([data, worker, M]) => {
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = worker;
        const raw = atob(data);
        const arr = new Uint8Array(raw.length);
        for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
        const doc = await window.pdfjsLib.getDocument({ data: arr }).promise;
        const bad = [];
        for (let i = 1; i <= doc.numPages; i++) {
          const pg = await doc.getPage(i);
          const vp = pg.getViewport({ scale: 1 });
          const tc = await pg.getTextContent();
          tc.items.forEach(it => {
            const x = it.transform[4], y = it.transform[5];
            if (x < M - 1 || x + it.width > vp.width - M + 1 || y < 20 || y > vp.height - 20) {
              bad.push('p' + i + ' "' + String(it.str).slice(0, 34) + '" x=' + Math.round(x) +
                       ' end=' + Math.round(x + it.width));
            }
          });
        }
        return bad;
      }, [b64, PDFJS_BASE + 'pdf.worker.min.js', 54]);
      check(c.name + ': nothing drawn crosses the margins',
        over.length === 0, over.slice(0, 3).join(' | '));
    }
  }

  console.log('errors: ' + (errs.join(' | ') || 'none'));
  await b.close();
  console.log(bad || errs.length ? 'pdfcases: ' + (bad + errs.length) + ' FAIL' : 'pdfcases: ok');
  process.exit(bad || errs.length ? 1 : 0);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
