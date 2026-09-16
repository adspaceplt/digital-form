/*
 * The Review Canvas. The gallery is how a client sees the month; the canvas is
 * how they decide on one post. The blocks are moved out of the card and put
 * back on close, so there is one approve control in the page and it cannot
 * drift from the one in the gallery — this suite is what proves the move and
 * the return, at both widths and from the keyboard.
 */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
let bad = 0;
const check = (l, ok, x) => { console.log((ok ? 'ok   ' : 'FAIL ') + l + (x ? '  ' + x : '')); if (!ok) bad++; };

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errs = [];

  for (const [w, h, tag] of [[1280, 1000, '1280'], [390, 1100, '390']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h },
      hasTouch: tag === '390', isMobile: tag === '390' });
    const p = await ctx.newPage();
    p.on('pageerror', e => errs.push(tag + ' PAGEERROR ' + e.message));
    // The demo feed: the review page reads /demo/sample.json when Supabase is
    // not configured, which is the same shape a real set arrives in.
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};' }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    await p.goto('http://127.0.0.1:8899/review/?k=demo', { waitUntil: 'networkidle' });
    await p.waitForTimeout(1100);

    console.log('=== ' + tag + ' ===');
    const cards = await p.locator('#content .card').count();
    check('the gallery is still the gallery', cards > 1, String(cards));
    check('and the canvas is shut until it is asked for',
      await p.locator('#canvas').evaluate(e => e.hidden));

    // The mockup is the thing they are already looking at, so it is what opens.
    await p.locator('#content .card .card-stage').first().click();
    await p.waitForTimeout(500);
    check('the mockup opens the canvas', !(await p.locator('#canvas').evaluate(e => e.hidden)));
    check('the post is named, with its dimensions',
      (await p.locator('#canvasTitle').innerText()).length > 0 &&
      /\d+\s*x\s*\d+/.test(await p.locator('#canvasDims').innerText()),
      await p.locator('#canvasTitle').innerText() + ' / ' + await p.locator('#canvasDims').innerText());
    check('and where it sits in the set', (await p.locator('#canvasPos').innerText()) === '1 of ' + cards,
      await p.locator('#canvasPos').innerText());

    // Everything the decision rests on, in one rail, with one decision area.
    check('the mockup is on the stage', await p.locator('#canvasStage .card-stage').count() === 1);
    check('the status is in the rail', await p.locator('#canvasRail .badge').count() === 1);
    check('the copy in full is in the rail', await p.locator('#canvasRail .copyblock').count() === 1);
    check('and the one decision area', await p.locator('#canvasRail .approve').count() === 1);
    /* The decision in the canvas is the card's own control, moved, not a
       second one built beside it: the card it belongs to has none while the
       canvas is open. */
    check('the open card gave its decision to the canvas',
      await p.locator('#content .card .approve').count() === cards - 1,
      String(await p.locator('#content .card .approve').count()));

    // Stepping through the set.
    check('Previous is refused on the first post',
      await p.locator('#canvasPrev').isDisabled());
    await p.locator('#canvasNext').click(); await p.waitForTimeout(450);
    check('Next moves on', (await p.locator('#canvasPos').innerText()) === '2 of ' + cards,
      await p.locator('#canvasPos').innerText());
    check('and the post that was open went back to the gallery',
      await p.locator('#content .card .card-stage').count() === cards - 1,
      String(await p.locator('#content .card .card-stage').count()));
    // The arrow keys are the same move, because this is a lightbox and that is
    // what a lightbox does.
    await p.keyboard.press('ArrowLeft'); await p.waitForTimeout(450);
    check('the arrow keys step too', (await p.locator('#canvasPos').innerText()) === '1 of ' + cards,
      await p.locator('#canvasPos').innerText());

    // Closing puts every block back where it came from.
    await p.keyboard.press('Escape'); await p.waitForTimeout(450);
    check('Escape closes it', await p.locator('#canvas').evaluate(e => e.hidden));
    check('every mockup is back in its card',
      await p.locator('#content .card .card-stage').count() === cards,
      String(await p.locator('#content .card .card-stage').count()));
    check('and every decision with it',
      await p.locator('#content .card .approve').count() === cards,
      String(await p.locator('#content .card .approve').count()));
    check('and the copy', await p.locator('#content .card .copyblock').count() > 0);
    check('nothing is left behind in the canvas',
      await p.locator('#canvasStage .card-stage').count() === 0 &&
      await p.locator('#canvasRail .approve').count() === 0);
    check('no sideways overflow', await p.evaluate(() =>
      document.documentElement.scrollWidth <= window.innerWidth));

    /* A decision taken in the canvas is the gallery's decision, because it is
       the gallery's control: the same node, moved. */
    await p.locator('#content .card .card-stage').first().click();
    await p.waitForTimeout(450);
    /* An approval with nobody's name on it is worth nothing, so the page asks
       for one. The canvas inherits that because it is the same control. */
    p.once('dialog', d => d.accept('Wei Ling'));
    await p.locator('#canvasRail .btn-approve').click();
    await p.waitForTimeout(900);
    check('approving in the canvas settles the post',
      (await p.locator('#canvasRail .badge').innerText()).toLowerCase().includes('approved'),
      await p.locator('#canvasRail .badge').innerText());
    await p.keyboard.press('Escape'); await p.waitForTimeout(450);
    check('and the gallery card carries the decision home',
      (await p.locator('#content .card').first().innerText()).toLowerCase().includes('approved'),
      (await p.locator('#content .card').first().innerText()).replace(/\n/g, ' | ').slice(0, 90));

    await ctx.close();
  }

  console.log('=== errors ===');
  console.log(errs.length ? errs.join('\n') : 'none');
  if (errs.length) bad += errs.length;
  await b.close();
  console.log(bad ? 'canvas: ' + bad + ' FAIL' : 'canvas: ok');
  if (bad) process.exit(1);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
