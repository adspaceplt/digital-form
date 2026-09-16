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
  say('every page but the last carries an initials line', has(/Initials/g) === pageCount - 1,
    has(/Initials/g) + ' of ' + (pageCount - 1));
  /* And the signed page says what it is signing, so a substituted page
     disagrees with it. */
  /* The wrapped tail of a sentence is a short run, and a short run is the one
     case where two subsets both decode it cleanly, so the assertion is on the
     part that carries the meaning rather than on the last few words. */
  say('the signature page names the letter, the pages and the figure',
    /This acceptance relates to Letter of Of+er/.test(joined) &&
    new RegExp('Of+er ' + num.replace(/\//g, '.')).test(joined) &&
    /comprising \d+ pages/.test(joined) &&
    /at RM ?[\d,]+|totalling RM/.test(joined));
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

  console.log('errors: ' + (errs.join(' | ') || 'none'));
  await b.close();
  process.exit(errs.length ? 1 : 0);
})();
