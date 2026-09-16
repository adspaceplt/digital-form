const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const STUB = fs.readFileSync(process.argv[2] + '/stub2.js', 'utf8');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(process.argv[2] + '/pdfx/node_modules/pdf-lib/dist/pdf-lib.min.js', 'utf8') }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(process.argv[2] + '/pdfx/node_modules/@pdf-lib/fontkit/dist/fontkit.umd.min.js', 'utf8') }));
  await p.goto('http://127.0.0.1:8899/admin/?s=clients', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(700);
  console.log('pdf-lib loaded: ' + await p.evaluate(() => !!window.PDFLib));
  await p.locator('.crm-row').filter({ hasText: 'Laman Citra' }).click(); await p.waitForTimeout(800);
  /* The record is a workspace with panes now, so a section's controls are in
     the pane that owns them. */
  const pane = async (k) => { await p.locator('#crmTabs .tab[data-pane="' + k + '"]').click(); await p.waitForTimeout(300); };
  await pane('services');
  for (const [pick, qty, state, label, rate, months, start] of [['pkg-b', '3', 'confirmed'], ['custom', '1', 'confirmed', 'Launch video, up to 60 seconds, one on-site shoot included', '20000'], ['pkg-b', '1', 'quoted', '', '', '3', '2026-10']]) {
    await p.locator('#crmAddService').click(); await p.waitForTimeout(300);
    await p.selectOption('#svPick', pick); await p.fill('#svQty', qty); await p.selectOption('#svState', state);
    if (label) { await p.fill('#svLabel', label); await p.fill('#svRate', rate); }
    if (months) { await p.fill('#svTenure', months); await p.fill('#svStart', start + '-12'); }
    await p.locator('#svSave').click(); await p.waitForTimeout(900);
  }
  /* A letter is built from the Client ID staff enter, and is issued for the
     services somebody chose rather than for whatever happened to be marked To
     quote. Both are part of what the drawn file has to show. */
  await p.locator('#crmEdit').click(); await p.waitForTimeout(400);
  await p.fill('#crmClientCode', 'AC180');
  await p.locator('#crmSave').click(); await p.waitForTimeout(900);
  await pane('documents');
  await p.locator('#crmCover').click(); await p.waitForTimeout(600);
  const offered = await p.evaluate(() => [...document.querySelectorAll('#pickBody .lpickrow')]
    .map(r => ({ name: r.querySelector('b').textContent,
                 on: r.querySelector('input').checked })));
  console.log((offered.filter(o => o.on).length === 1 ? 'ok   ' : 'FAIL ') +
    'only the To quote line is ticked  ' + JSON.stringify(offered));
  if (offered.filter(o => o.on).length !== 1) errs.push('selection');
  const dl = p.waitForEvent('download');
  await p.locator('#pickGo').click();
  const got = await dl; await got.saveAs(process.argv[2] + '/' + got.suggestedFilename());
  console.log('saved ' + got.suggestedFilename());
  await p.waitForTimeout(500);
  await p.screenshot({ path: process.argv[2] + '/docs-1280.png', fullPage: true });
  /* Step 6 used to be a person remembering to decompress the streams by hand.
     The letter is the one artefact a client signs, so what it says is checked
     here instead. Each embedded font carries its own ToUnicode table and the
     subsets collide, so a run is decoded against every table and the reading
     with the fewest unknowns wins. */
  const alts = [];
  const read = (file) => {
    const d = fs.readFileSync(file);
    const outs = [];
    const zlib = require('zlib');
    let i = 0;
    while ((i = d.indexOf('stream', i)) >= 0) {
      let a = i + 6; while (d[a] === 13 || d[a] === 10) a++;
      const e = d.indexOf('endstream', a);
      if (e < 0) break;
      try { outs.push(zlib.inflateSync(d.slice(a, e))); } catch (err) { /* not deflate */ }
      i = e + 9;
    }
    const all = Buffer.concat(outs).toString('latin1');
    const maps = [];
    for (const m of all.matchAll(/beginbfchar([\s\S]*?)endbfchar/g)) {
      const t = {};
      for (const c of m[1].matchAll(/<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4,})>/g)) {
        t[parseInt(c[1], 16)] = String.fromCharCode(parseInt(c[2].slice(0, 4), 16));
      }
      maps.push(t);
    }
    const runs = [];
    for (const blk of all.matchAll(/BT([\s\S]*?)ET/g)) {
      const hexes = [...blk[1].matchAll(/<([0-9A-Fa-f]+)>\s*Tj/g)].map(x => x[1]);
      if (!hexes.length) continue;
      /* Fewest unknowns is not enough: a subset that happens to cover every
         glyph id decodes cleanly into nonsense. Real text is mostly words, so
         the reading with the most of its length inside runs of three or more
         letters wins. */
      let best = null;
      for (const t of maps) {
        const out = hexes.map(h => {
          let s2 = '';
          for (let j = 0; j < h.length; j += 4) s2 += t[parseInt(h.slice(j, j + 4), 16)] || '\uFFFD';
          return s2;
        }).join('');
        /* Every clean reading is kept, not only the winner. A short run is the
           one case where two subsets both decode it cleanly and the score
           cannot separate them — and the page foot, which carries the
           reference, is exactly that: a dozen characters, most of them
           digits. Asserting against the winner alone made the foot invisible
           and would have reported a missing reference that is on the page. */
        const bad = (out.match(/\uFFFD/g) || []).length;
        const words = (out.match(/[A-Za-z]{3,}/g) || []).join('').length;
        const score = words / Math.max(1, out.length) - bad;
        if (!bad) alts.push(out);
        if (!best || score > best.score) best = { out, score };
      }
      if (best) runs.push(best.out);
    }
    return runs;
  };

  const runs = read(process.argv[2] + '/' + got.suggestedFilename());
  const joined = runs.join('\n');
  const num = (got.suggestedFilename().match(/AQL-[A-Z0-9]+-\d+/) || [''])[0].replace(/-/g, '/');
  const has = (re) => (joined.match(re) || []).length;
  /* A short run is the one case where two font subsets both decode without an
     unknown character, so the winner-takes-all score can hand back the wrong
     reading for a page foot or the tail of a wrapped sentence. `anyText` is
     every clean reading of every run, which is what the page-foot reference
     assertion below has always used; the short assertions use it too rather
     than reporting a line that is on the page as missing. */
  const anyText = joined + '\n' + alts.join('\n');
  const hasAny = (re) => (anyText.match(re) || []).length;
  const pageCount = has(/Page \d+ of \d+/g);
  const say = (l, ok, extra) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (extra ? '  ' + extra : '')); if (!ok) errs.push(l); };

  if (process.env.DUMP) console.log('---RUNS---\n' + runs.map((r,i)=>i+': '+r).join('\n'));
  say('every page is numbered', pageCount >= 2, pageCount + ' pages');
  /* A page lifted out of this letter still says which letter it came from. */
  /* Counted across every clean reading, because the foot is a short run that
     more than one font subset decodes without a single unknown character. */
  const refRe = new RegExp(num.replace(/\//g, '.'), 'g');
  const feet = alts.filter(a => refRe.test(a) && (refRe.lastIndex = 0) === 0).length;
  say('every page foot names the letter', feet >= pageCount, feet + ' readings carry ' + num);
  /* Initials on every page but the one that is signed: a letter whose
     substance is on page one and whose signature is on page two can be
     executed and then have page one swapped. */
  say('every page but the last carries an initials line',
    hasAny(/Client initials/g) >= pageCount - 1,
    hasAny(/Client initials/g) + ' of ' + (pageCount - 1));
  /* And the signed page says what it is signing, so a substituted page
     disagrees with it. */
  /* The wrapped tail of a sentence is a short run, and a short run is the one
     case where two subsets both decode it cleanly, so the assertion is on the
     part that carries the meaning rather than on the last few words. */
  say('the acceptance names the letter and its date in the approved wording',
    /By signing below, the Client accepts Letter of Of+er/.test(joined) &&
    new RegExp('Of+er ' + num.replace(/\//g, '.')).test(joined) &&
    /the services, fees, and terms set out in this document/.test(anyText.replace(/\s+/g, ' ')));
  /* Agreement prose takes a plain date. An ordinal reads as a letterhead
     flourish and this is the operative sentence. */
  say('and dates it without an ordinal',
    /dated \d{1,2} [A-Z][a-z]+ \d{4}/.test(joined) && !/dated \d{1,2}(st|nd|rd|th)/.test(joined));
  /* The page count is one of the three marks that contradicts a swapped first
     page, so it survives the rewrite even though the sentence around it did not. */
  say('and still states how many pages it comprises',
    /This letter comprises \d+ pages/.test(joined));
  /* The figures a client is accepting are in a table, from the same
     calculation the price table above was drawn from. */
  say('the acceptance summarises the fee, the term and the total',
    /Monthly fee/.test(joined) && /Contract term/.test(joined) && /Total contract value/.test(joined));
  /* A role is not a signatory. */
  say('no internal role name reaches the letter',
    !/Superadmin|Administrator|Team member/i.test(joined));
  say('and the closing signs for the company',
    /For and on behalf of ADSPACE/i.test(joined));
  say('the execution block names the signing area and its three fields',
    /Authorised signatory and company stamp/.test(joined) &&
    /Name/.test(joined) && /Designation/.test(joined) && /Date/.test(joined));
  /* 17. The output shows the serial staff will quote, and only the lines the
     letter was issued for: a line the client already has on an earlier letter
     is not on this one. */
  say('the serial is AQL, the Client ID and the month', /^AQL\/AC180\/\d{4}\d{2,}$/.test(num), num);
  say('the file is named for it', /^AQL-AC180-\d+\.pdf$/.test(got.suggestedFilename()), got.suggestedFilename());
  say('the drawn letter carries the chosen line',
    /Package B/.test(joined), joined.slice(0, 0) + (joined.match(/Package B[^\n]*/) || [''])[0]);
  say('and not the lines that were confirmed months ago',
    !/Launch video/.test(joined));
  say('the money and the acceptance block are drawn',
    /Payable monthly|Total/.test(joined) && /Conf(ir)?rmed and accepted for and on behalf of/.test(joined));

  /* ---- The form ---------------------------------------------------------
     Text extraction cannot see a form field, so the fields are read with
     pdf-lib itself: present in the AcroForm tree, present as widgets on a
     page with real rectangles, and still editable after a fill and a save.
     A drawn line that looks like a field is the defect this is here for. */
  const PDFLib = require(require('path').resolve(process.argv[2], 'pdfx/node_modules/pdf-lib'));
  const WANT = ['acceptance_authorised_signatory', 'acceptance_name',
                'acceptance_designation', 'acceptance_date'];
  const file = process.argv[2] + '/' + got.suggestedFilename();

  const src = await PDFLib.PDFDocument.load(fs.readFileSync(file));
  const form = src.getForm();
  const names = form.getFields().map(f => f.getName());
  say('every acceptance field is in the AcroForm tree',
    WANT.every(n => names.indexOf(n) > -1), names.join(', ') || '(none)');

  const rects = {};
  let widgets = 0, offPage = 0;
  const media = src.getPage(src.getPageCount() - 1).getSize();
  WANT.forEach(n => {
    if (names.indexOf(n) < 0) return;
    const ws = form.getTextField(n).acroField.getWidgets();
    widgets += ws.length;
    ws.forEach(w => {
      const r = w.getRectangle();
      rects[n] = r;
      if (r.width <= 0 || r.height <= 0 ||
          r.x < 0 || r.y < 0 ||
          r.x + r.width > media.width + 0.5 ||
          r.y + r.height > media.height + 0.5) offPage++;
    });
  });
  say('each one is a widget on the page', widgets === WANT.length, widgets + ' widgets');
  say('and every rectangle is valid and inside the media box', offPage === 0, offPage + ' outside');
  /* A signature is a hand moving across the page, so its box is an area and
     not a line: 32mm, visibly larger than the fields under it. */
  const sig = rects['acceptance_authorised_signatory'];
  const nm = rects['acceptance_name'];
  say('the signing area clears 32mm',
    sig && sig.height >= 90, sig ? sig.height.toFixed(1) + 'pt' : 'missing');
  say('and is visibly larger than an ordinary field',
    sig && nm && sig.height > nm.height * 2, sig && nm ? sig.height.toFixed(0) + ' vs ' + nm.height.toFixed(0) : '');
  say('every field clears 10mm',
    WANT.every(n => rects[n] && rects[n].height >= 28),
    WANT.map(n => rects[n] ? Math.round(rects[n].height) : '?').join('/'));
  say('the three fields share one left edge and one width',
    ['acceptance_name', 'acceptance_designation', 'acceptance_date']
      .every(n => rects[n] && Math.abs(rects[n].x - nm.x) < 0.5 &&
                  Math.abs(rects[n].width - nm.width) < 0.5));

  // Fill it, save it, open it again: the values and their appearances persist
  // and the form is still interactive.
  form.getTextField('acceptance_name').setText('Tan Wei Ling');
  form.getTextField('acceptance_designation').setText('Director');
  form.getTextField('acceptance_date').setText('16 September 2026');
  form.getTextField('acceptance_authorised_signatory').setText('Tan Wei Ling');
  const filledBytes = await src.save();
  fs.writeFileSync(process.argv[2] + '/filled-' + got.suggestedFilename(), filledBytes);

  const back = await PDFLib.PDFDocument.load(filledBytes);
  const bf = back.getForm();
  say('a filled form reopens with its values',
    bf.getTextField('acceptance_name').getText() === 'Tan Wei Ling' &&
    bf.getTextField('acceptance_designation').getText() === 'Director' &&
    bf.getTextField('acceptance_date').getText() === '16 September 2026',
    [bf.getTextField('acceptance_name').getText(),
     bf.getTextField('acceptance_designation').getText()].join(' / '));
  say('and is still interactive',
    bf.getFields().length === WANT.length &&
    bf.getFields().every(f => !f.isReadOnly()), bf.getFields().length + ' fields');
  /* An appearance stream, not NeedAppearances: a reader that ignores the flag
     must still draw what was typed. */
  const appearances = WANT.filter(n => {
    const w = bf.getTextField(n).acroField.getWidgets()[0];
    return w && w.getNormalAppearance();
  }).length;
  say('each filled field carries its own appearance stream',
    appearances === WANT.length, appearances + ' of ' + WANT.length);
  /* An empty form is the ordinary case and has to render too. */
  const emptyForm = (await PDFLib.PDFDocument.load(fs.readFileSync(file))).getForm();
  say('an empty form is interactive as issued',
    emptyForm.getFields().length === WANT.length &&
    emptyForm.getFields().every(f => f.getName() && !f.isReadOnly()));

  console.log('errors: ' + (errs.join(' | ') || 'none'));
  await b.close();
  process.exit(errs.length ? 1 : 0);
})();
