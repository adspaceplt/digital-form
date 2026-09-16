/*
 * The letter, rendered as pixels and read.
 *
 * tests/pdfreal.js decodes the text streams, which proves what the letter says
 * and nothing about where it sits. A closing stranded at the top of a page, a
 * page number under an initials field, a signing area too shallow to sign in:
 * every one of those decodes perfectly. So the pages are rasterised here with
 * pdf.js and written out to be looked at.
 *
 * Usage: node tests/pdfshot.js tests [file.pdf ...]
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const path = require('path');
const T = process.argv[2];
const files = process.argv.slice(3);
const OUT = process.env.OUT || (T + '/');
/* pdf.js is served off the same local server the suites already use, not off
   a CDN: the sandbox cannot reach one, and a visual check that silently skips
   is a visual check nobody does. `npm i` in tests/pdfx puts it there. */
const BASE = 'http://127.0.0.1:8899/tests/pdfx/node_modules/pdfjs-dist/build/';
const PDFJS = BASE + 'pdf.min.js';
const WORKER = BASE + 'pdf.worker.min.js';

(async () => {
  if (!files.length) { console.log('pdfshot: no files given'); process.exit(0); }
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await (await b.newContext({ viewport: { width: 1000, height: 1400 } })).newPage();
  p.on('pageerror', e => console.log('PAGEERROR ' + e.message));
  await p.setContent('<body style="margin:0;background:#888"><div id="out"></div></body>');
  try {
    await p.addScriptTag({ url: PDFJS });
  } catch (e) {
    console.log('pdfshot: SKIP, pdf.js could not be loaded (' + e.message + ')');
    console.log('  run: npm i pdfjs-dist@3.11.174 --prefix tests/pdfx, and start the server');
    await b.close(); process.exit(0);
  }
  let made = 0;
  for (const f of files) {
    const bytes = fs.readFileSync(f).toString('base64');
    const n = await p.evaluate(async ([data, worker]) => {
      window.pdfjsLib.GlobalWorkerOptions.workerSrc = worker;
      const raw = atob(data);
      const arr = new Uint8Array(raw.length);
      for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      const doc = await window.pdfjsLib.getDocument({ data: arr }).promise;
      const out = document.getElementById('out');
      out.innerHTML = '';
      for (let i = 1; i <= doc.numPages; i++) {
        const pg = await doc.getPage(i);
        // 2x, so a 8.5pt label is legible when the page is read.
        const vp = pg.getViewport({ scale: 2 });
        const c = document.createElement('canvas');
        c.width = vp.width; c.height = vp.height;
        c.id = 'pg' + i;
        c.style.cssText = 'display:block;margin:0 auto';
        out.appendChild(c);
        await pg.render({ canvasContext: c.getContext('2d'), viewport: vp }).promise;
      }
      return doc.numPages;
    }, [bytes, WORKER]);
    const base = path.basename(f).replace(/\.pdf$/i, '');
    for (let i = 1; i <= n; i++) {
      const out = OUT + base + '-p' + i + '.png';
      await p.locator('#pg' + i).screenshot({ path: out });
      console.log('shot ' + path.basename(out));
      made++;
    }
  }
  await b.close();
  console.log('pdfshot: ' + made + ' pages');
})();
