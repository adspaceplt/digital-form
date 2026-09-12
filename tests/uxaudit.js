/* Layout and accessibility audit. Walks every page and state at 1280 and at
   390 with a coarse pointer, and fails the sweep on anything the rules in
   CLAUDE.md forbid: sideways overflow, a cell alone on its row, a value that
   wraps or clips, buttons in one row at different heights (or widths on a
   phone), a control under 38px (44px touch), a field or icon button without
   a name, more than one green action in a view, text under 4.5:1, a control
   that takes focus without a ring. Warnings (placeholder-only labels, control
   boundaries under 3:1) are printed but do not fail. */
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const T = process.argv[2];
const STUB = fs.readFileSync(T + '/stub2.js', 'utf8');
const seedOf = f => fs.readFileSync(T + '/' + f, 'utf8').match(/const SEED = `([\s\S]*?)`;/)[1];
const CRM = seedOf('crmshot.js');
const CAMP = seedOf('head.js');
const CLIENT = seedOf('client.js');
const CPROD = seedOf('cprod.js');
const PORTAL = seedOf('portal.js');
const QR = 'window.QRCode=function(){};window.QRCode.CorrectLevel={H:2};';

const FAIL = new Set(['overflow', 'orphan', 'padding', 'cols', 'stack', 'type', 'wrap', 'clip', 'row-height', 'row-width', 'target', 'label', 'icon-label', 'accent', 'contrast', 'boundary', 'focus']);
let fails = 0, warns = 0;

/* Runs inside the page. Returns [[kind, detail], ...]. */
function inPage(coarse) {
  const F = [];
  // The review page's post mockups (.card-stage) reproduce each platform's
  // own UI and are not portal controls, so they are outside the audit.
  const vis = el => {
    if (!el || el.closest('[hidden], .card-stage')) return false;
    const r = el.getBoundingClientRect(); const cs = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none' && parseFloat(cs.opacity) > 0.05;
  };
  const desc = el => {
    let s = el.tagName.toLowerCase();
    if (el.id) s += '#' + el.id;
    else if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.');
    const t = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 28);
    return t ? s + ' "' + t + '"' : s;
  };

  // 1 sideways overflow
  const de = document.documentElement;
  if (de.scrollWidth > de.clientWidth + 1) F.push(['overflow', 'page scrolls sideways by ' + (de.scrollWidth - de.clientWidth) + 'px']);

  // 2 a cell alone on the last row of a grid
  document.querySelectorAll('.tally').forEach(g => {
    if (!vis(g)) return;
    const cells = [...g.children].filter(vis);
    if (cells.length < 2) return;
    const cols = getComputedStyle(g).gridTemplateColumns.trim().split(/\s+/).length;
    const rows = {};
    cells.forEach(c => { const t = Math.round(c.getBoundingClientRect().top); (rows[t] = rows[t] || []).push(c); });
    const tops = Object.keys(rows).map(Number).sort((a, b) => a - b);
    if (tops.length < 2) return;
    const last = rows[tops[tops.length - 1]];
    const gw = g.getBoundingClientRect().width;
    const lw = last.reduce((s, c) => s + c.getBoundingClientRect().width, 0);
    if (last.length < cols && lw < gw * 0.9) F.push(['orphan', desc(g) + ': ' + last.length + ' of ' + cols + ' cells on the last row']);
  });

  // 2b a card's rows sit as far from its top as from its bottom
  document.querySelectorAll('.crm-table, .team-table').forEach(t => {
    if (!vis(t)) return;
    const kids = [...t.children].filter(vis).filter(k => !k.matches('.crm-head, .team-head, .group-head'));
    if (kids.length < 1 || t.querySelector(':scope > .crm-head, :scope > .team-head, :scope > .group-head')) return;
    const tr = t.getBoundingClientRect(), fr = kids[0].getBoundingClientRect(), lr = kids[kids.length - 1].getBoundingClientRect();
    const top = fr.top - tr.top, bottom = tr.bottom - lr.bottom;
    if (Math.abs(top - bottom) > 2) F.push(['padding', desc(t) + ': ' + Math.round(top) + 'px above the first row, ' + Math.round(bottom) + 'px below the last']);
  });

  // 2c a header cell sits over its column: same left edge as the first row's cell
  document.querySelectorAll('.crm-table > .crm-head, .team-table > .team-head').forEach(h => {
    if (!vis(h)) return;
    const row = [...h.parentElement.children].find(k => k !== h && vis(k) && k.matches('.crm-row, .svc-row, .team-row'));
    if (!row) return;
    const shown = el => getComputedStyle(el).display !== 'none';
    const hc = [...h.children].filter(shown), rc = [...row.children].filter(shown);
    if (hc.length !== rc.length) { F.push(['cols', desc(h) + ': ' + hc.length + ' header cells over ' + rc.length + ' row cells']); return; }
    hc.forEach((c, i) => {
      if (!c.textContent.trim()) return;
      const a = c.getBoundingClientRect(), b = rc[i].getBoundingClientRect();
      if (Math.abs(a.left - b.left) > 2 || Math.abs(a.right - b.right) > 2) F.push(['cols', desc(h) + ': "' + c.textContent.trim() + '" at ' + Math.round(a.left) + '..' + Math.round(a.right) + 'px over a column at ' + Math.round(b.left) + '..' + Math.round(b.right) + 'px']);
    });
  });

  // 3 values that wrap or clip
  document.querySelectorAll('.tally-cell b, .stat b, .chip-state, .kcard-sum, .facts dd').forEach(el => {
    if (!vis(el)) return;
    const cs = getComputedStyle(el);
    const lh = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.4;
    if (!el.matches('.facts dd') && el.getBoundingClientRect().height > lh * 1.6) F.push(['wrap', desc(el) + ' wraps']);
    if (el.scrollWidth > el.clientWidth + 1 && cs.overflow !== 'visible') F.push(['clip', desc(el) + ' is clipped']);
  });

  // 4 buttons sharing a row: same height always, same width on a phone
  document.querySelectorAll('.row, .kactions, .linkbox, .viewhead, .filterbar, .booking-cta, .sheet-actions, .cover-panel form, .actions, .crm-engage-actions').forEach(row => {
    if (!vis(row)) return;
    const btns = [...row.querySelectorAll(':scope > .btn, :scope > button, :scope > a.btn')].filter(b => vis(b) && !b.matches('.btn-quiet'));
    if (btns.length < 2) return;
    const lines = {};
    btns.forEach(b => { const r = b.getBoundingClientRect(); const k = Math.round(r.top / 6); (lines[k] = lines[k] || []).push(r); });
    Object.values(lines).forEach(rs => {
      if (rs.length < 2) return;
      const hs = rs.map(r => Math.round(r.height));
      if (Math.max(...hs) - Math.min(...hs) > 1) F.push(['row-height', desc(row) + ': ' + hs.join('/') + 'px tall in one row']);
      if (coarse) {
        const ws = rs.map(r => Math.round(r.width));
        if (Math.max(...ws) - Math.min(...ws) > 2) F.push(['row-width', desc(row) + ': ' + ws.join('/') + 'px wide in one row']);
      }
    });
  });

  // 4b the stack: every block that follows a section head sits the same distance from the next
  document.querySelectorAll('.viewhead').forEach(h => {
    if (!vis(h)) return;
    // A label (.kstep-title, .field-label) belongs to the block under it.
    const blocks = [];
    let n = h.nextElementSibling, labelTop = null;
    while (n) {
      if (n.matches('.viewhead') || n.querySelector('.viewhead')) break;
      const r = n.getBoundingClientRect();
      if (vis(n) && r.height > 1) {
        if (n.matches('.kstep-title, .field-label, .sectionlabel')) { if (labelTop === null) labelTop = r.top; }
        else { blocks.push({ top: labelTop === null ? r.top : labelTop, bottom: r.bottom }); labelTop = null; }
      }
      n = n.nextElementSibling;
    }
    const gaps = [];
    for (let i = 1; i < blocks.length; i++) gaps.push(Math.round(blocks[i].top - blocks[i - 1].bottom));
    if (gaps.length > 1 && Math.max(...gaps) - Math.min(...gaps) > 2) F.push(['stack', desc(h) + ': blocks below it sit ' + gaps.join(' / ') + 'px apart']);
    if (blocks.length && Math.round(blocks[0].top - h.getBoundingClientRect().bottom) > 16) F.push(['stack', desc(h) + ': first block ' + Math.round(blocks[0].top - h.getBoundingClientRect().bottom) + 'px under the head']);
  });

  // 4c type floor: no text under 11px in the portal (the mockups are the platforms' own UI)
  document.querySelectorAll('body *').forEach(el => {
    if (!vis(el) || el.closest('.card-stage, svg, [aria-hidden="true"]')) return;
    const own = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    if (!own) return;
    const fs = parseFloat(getComputedStyle(el).fontSize);
    if (fs < 10.9) F.push(['type', desc(el) + ' is ' + fs + 'px']);
  });

  // 5 target size
  const min = coarse ? 44 : 38, minSm = coarse ? 44 : 32;
  document.querySelectorAll('button, a.btn, input:not([type=checkbox]):not([type=radio]):not([type=hidden]):not([type=file]), select, textarea').forEach(el => {
    if (!vis(el) || el.closest('.portalfoot')) return;
    const r = el.getBoundingClientRect();
    const need = el.matches('.btn-sm, .input-sm, .select-sm') ? minSm : min;
    const short = r.height < need - 0.5;
    const narrow = el.matches('button, a.btn') && !el.matches('.btn-quiet, .kfold, .batch-head') && r.width < need - 0.5;
    if (short || narrow) F.push(['target', desc(el) + ' is ' + Math.round(r.width) + '×' + Math.round(r.height) + 'px, min ' + need]);
  });

  // 6 names on fields and icon buttons
  document.querySelectorAll('input:not([type=hidden]):not([type=submit]):not([type=button]), select, textarea').forEach(el => {
    if (!vis(el)) return;
    const named = el.getAttribute('aria-label') || el.getAttribute('aria-labelledby') || el.getAttribute('title') ||
      (el.id && document.querySelector('label[for="' + CSS.escape(el.id) + '"]')) || el.closest('label');
    if (!named) F.push([el.getAttribute('placeholder') ? 'label-placeholder' : 'label', desc(el) + ' has no label']);
  });
  document.querySelectorAll('button, a.btn, [role=button]').forEach(el => {
    if (!vis(el)) return;
    const text = (el.textContent || '').trim();
    if (!text && !el.getAttribute('aria-label') && !el.getAttribute('aria-labelledby') && !el.getAttribute('title')) F.push(['icon-label', desc(el) + ' icon-only without a name']);
  });

  // 7 one green action per view
  const goes = [...document.querySelectorAll('.btn-go')].filter(vis);
  const scopeOf = el => el.closest('.kcard, .booking, .crow, .bigcard, .card, .crm-row, .team-row, .sheet, .drawer, .batch, .panel, section, .console-body, main') || document.body;
  const by = new Map();
  goes.forEach(g => { const s = scopeOf(g); by.set(s, (by.get(s) || 0) + 1); });
  by.forEach((n, s) => { if (n > 1) F.push(['accent', desc(s) + ' shows ' + n + ' green actions']); });

  // 8 contrast
  const parse = c => { const m = (c || '').match(/rgba?\(([^)]+)\)/); if (!m) return null; const a = m[1].split(/[,\s/]+/).map(parseFloat); return { r: a[0], g: a[1], b: a[2], a: a.length > 3 ? a[3] : 1 }; };
  const lum = c => { const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b); };
  const ratio = (a, b) => { const la = lum(a), lb = lum(b); return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05); };
  const blend = (fg, bg) => ({ r: fg.r * fg.a + bg.r * (1 - fg.a), g: fg.g * fg.a + bg.g * (1 - fg.a), b: fg.b * fg.a + bg.b * (1 - fg.a), a: 1 });
  const bgOf = el => {
    const chain = []; let n = el;
    while (n && n.nodeType === 1) { const c = parse(getComputedStyle(n).backgroundColor); if (c && c.a > 0) { chain.push(c); if (c.a >= 1) break; } n = n.parentElement; }
    let out = { r: 255, g: 255, b: 255, a: 1 };
    for (let i = chain.length - 1; i >= 0; i--) out = blend(chain[i], out);
    return out;
  };
  const hex = c => '#' + [c.r, c.g, c.b].map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
  const pairs = new Set();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const seen = new Set(); let t;
  while ((t = walker.nextNode())) {
    if (!t.nodeValue.trim()) continue;
    const el = t.parentElement;
    if (!el || seen.has(el) || !vis(el) || el.closest('script, style, svg, [disabled], .portalfoot')) continue;
    seen.add(el);
    const cs = getComputedStyle(el); const fg = parse(cs.color); if (!fg) continue;
    const bg = bgOf(el); const fgc = fg.a < 1 ? blend(fg, bg) : fg;
    const size = parseFloat(cs.fontSize); const bold = parseInt(cs.fontWeight, 10) >= 700;
    const need = (size >= 24 || (size >= 18.66 && bold)) ? 3 : 4.5;
    const r = ratio(fgc, bg);
    if (r < need) {
      const key = hex(fgc) + '/' + hex(bg);
      if (pairs.has(key)) continue; pairs.add(key);
      F.push(['contrast', desc(el) + ' ' + r.toFixed(2) + ':1, ' + hex(fgc) + ' on ' + hex(bg) + ', needs ' + need]);
    }
  }
  // control boundaries (warning)
  const bpairs = new Set();
  document.querySelectorAll('input:not([type=checkbox]):not([type=radio]), select, textarea, .btn:not(.btn-primary):not(.btn-go)').forEach(el => {
    if (!vis(el)) return;
    const cs = getComputedStyle(el); const bc = parse(cs.borderTopColor); if (!bc || bc.a === 0 || parseFloat(cs.borderTopWidth) === 0) return;
    const bg = bgOf(el.parentElement); const r = ratio(bc.a < 1 ? blend(bc, bg) : bc, bg);
    if (r < 3) { const key = hex(bc) + '/' + hex(bg); if (bpairs.has(key)) return; bpairs.add(key); F.push(['boundary', desc(el) + ' border ' + r.toFixed(2) + ':1, ' + hex(bc) + ' on ' + hex(bg) + ', needs 3']); }
  });
  return F;
}

async function focusRing(p) {
  const out = [];
  const seen = new Set();
  for (let i = 0; i < 60; i++) {
    await p.keyboard.press('Tab');
    const r = await p.evaluate(() => {
      const el = document.activeElement;
      if (!el || el === document.body) return null;
      const cs = getComputedStyle(el);
      const ring = (cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0) || (cs.boxShadow && cs.boxShadow !== 'none');
      let s = el.tagName.toLowerCase(); if (el.id) s += '#' + el.id; else if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\s+/)[0];
      return { key: s + '|' + (el.textContent || '').trim().slice(0, 20), ring, desc: s + ' "' + (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 24) + '"' };
    });
    if (!r) break;
    if (seen.has(r.key)) break;
    seen.add(r.key);
    if (!r.ring) out.push(['focus', r.desc + ' takes focus without a ring']);
  }
  return out;
}

async function report(name, p, coarse) {
  // SHOTS=1 turns the walk into a picture of every state for a human
  // review and measures nothing: a full page capture resizes the phone
  // viewport and skews every measurement after it. The audit runs
  // separately without SHOTS.
  if (process.env.SHOTS) {
    fs.mkdirSync(T + '/walk', { recursive: true });
    await p.screenshot({ path: T + '/walk/' + name.replace(/[^a-z0-9]+/gi, '-') + '.png', fullPage: true }).catch(() => {});
    console.log('shot ' + name);
    return;
  }
  const F = await p.evaluate(inPage, coarse);
  F.push(...await focusRing(p));
  const bad = F.filter(f => FAIL.has(f[0])), warn = F.filter(f => !FAIL.has(f[0]));
  fails += bad.length; warns += warn.length;
  console.log((bad.length ? 'FAIL ' : 'ok   ') + name + (bad.length ? ' (' + bad.length + ')' : '') + (warn.length ? ' warn ' + warn.length : ''));
  bad.forEach(f => console.log('       ' + f[0] + ': ' + f[1]));
  warn.forEach(f => console.log('       ~' + f[0] + ': ' + f[1]));
}

async function walk(b, coarse) {
  const tag = coarse ? '390' : '1280';
  const ctx = await b.newContext(coarse
    ? { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true }
    : { viewport: { width: 1280, height: 900 } });
  const errs = [];
  const page = async (seed) => {
    const p = await ctx.newPage();
    p.on('pageerror', e => errs.push(tag + ' PAGEERROR ' + e.message));
    await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: STUB + seed }));
    await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
    await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
    return p;
  };
  const nav = async (p, sec) => {
    if (coarse) { await p.locator('#navToggle').click(); await p.waitForTimeout(300); }
    await p.locator('.navitem[data-section="' + sec + '"]').click(); await p.waitForTimeout(600);
  };

  // Console
  let p = await page(CRM + CAMP + PORTAL);
  await p.goto('http://127.0.0.1:8899/admin/', { waitUntil: 'networkidle' });
  await report('admin sign-in ' + tag, p, coarse);
  await p.evaluate(() => window.__signIn('adspacestudios@gmail.com'));
  await p.waitForTimeout(700);
  if (coarse) console.log('     pointer coarse: ' + await p.evaluate(() => matchMedia('(pointer: coarse)').matches));
  await report('admin clients ' + tag, p, coarse);
  await p.locator('.crm-row').first().click(); await p.waitForTimeout(700);
  await report('admin client record ' + tag, p, coarse);
  // The record with contacts, lines, a letter and a request from the portal.
  await p.evaluate(() => window.__DB.client_requests.length || window.__DB.client_requests.push({ id: 'rqa', client_id: 'c1', kind: 'cancel', service_id: 'pv1', service_label: 'Package B · 2 platforms · 4 contents', note: 'Ending in December.', state: 'requested', contact_name: 'Mr Lim', created_at: '2026-09-12T00:00:00Z', withdrawn_at: null }) && window.__persist());
  await p.locator('#crmBack').click(); await p.waitForTimeout(400);
  await p.locator('.crm-row', { hasText: 'Laman Citra' }).first().click(); await p.waitForTimeout(700);
  await report('admin client record full ' + tag, p, coarse);
  await nav(p, 'review');
  await report('admin content review ' + tag, p, coarse);
  await nav(p, 'campaigns');
  await report('admin campaigns ' + tag, p, coarse);
  await p.locator('#campCards .bigcard').first().click(); await p.waitForTimeout(700);
  await report('admin campaign head ' + tag, p, coarse);
  if (await p.locator('#campLock').isVisible().catch(() => false)) {
    await p.locator('#campLock').click(); await p.waitForTimeout(300);
    if (await p.locator('#lockGo').isVisible().catch(() => false)) {
      await report('admin confirm sheet ' + tag, p, coarse);
      await p.locator('#lockGo').click(); await p.waitForTimeout(900);
    }
  }
  if (await p.locator('.kcard .kfold').count()) { await p.locator('.kcard').first().locator('.kfold').click(); await p.waitForTimeout(300); }
  await report('admin campaign cards ' + tag, p, coarse);
  await nav(p, 'links');
  await report('admin short links ' + tag, p, coarse);
  await nav(p, 'services');
  await report('admin rate card ' + tag, p, coarse);
  await nav(p, 'clients');
  if (await p.locator('#crmBack').isVisible().catch(() => false)) { await p.locator('#crmBack').click(); await p.waitForTimeout(400); }
  await p.locator('#crmNew').click(); await p.waitForTimeout(400);
  await report('admin new lead ' + tag, p, coarse);
  await p.locator('#crmCancel').click(); await p.waitForTimeout(200);
  await nav(p, 'team');
  await report('admin team ' + tag, p, coarse);
  await p.close();

  // Client portal
  p = await page(PORTAL);
  await p.route('**/pdf-lib*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.PDFLib={};' }));
  await p.route('**/fontkit*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.goto('http://127.0.0.1:8899/client/', { waitUntil: 'networkidle' }); await p.waitForTimeout(400);
  await report('client sign-in ' + tag, p, coarse);
  await p.evaluate(() => window.__signIn('lim@lc.com')); await p.waitForTimeout(700);
  await p.evaluate(() => window.__DB.client_requests.length || window.supabase.createClient().rpc('portal_request', { p_client: 'c1', p_kind: 'cancel', p_service: 'pv1', p_note: 'Ending in December.' }));
  await p.goto('http://127.0.0.1:8899/client/', { waitUntil: 'networkidle' });
  await p.evaluate(() => window.__signIn('lim@lc.com')); await p.waitForTimeout(700);
  await report('client portal ' + tag, p, coarse);
  await p.locator('#ovRequest').click(); await p.waitForTimeout(300);
  await report('client request sheet ' + tag, p, coarse);
  await p.locator('#reqCancel').click(); await p.waitForTimeout(200);
  await p.close();

  // Client-facing
  p = await page(CLIENT);
  await p.goto('http://127.0.0.1:8899/creators/?k=TESTTOKEN', { waitUntil: 'networkidle' }); await p.waitForTimeout(600);
  await report('creators selection ' + tag, p, coarse);
  await p.close();
  p = await page(CPROD);
  await p.goto('http://127.0.0.1:8899/creators/?k=CPROD', { waitUntil: 'networkidle' }); await p.waitForTimeout(600);
  await report('creators progress ' + tag, p, coarse);
  await p.close();
  p = await page('');
  await p.goto('http://127.0.0.1:8899/creators/?k=NOPE', { waitUntil: 'networkidle' }); await p.waitForTimeout(400);
  await report('creators cover ' + tag, p, coarse);
  await p.close();
  p = await ctx.newPage();
  p.on('pageerror', e => errs.push(tag + ' PAGEERROR ' + e.message));
  await p.route('**/supabase-js*/**', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await p.route('**/qrcode*.js', r => r.fulfill({ contentType: 'application/javascript', body: QR }));
  await p.route('https://mycdn.adspace.me/**', r => r.fulfill({ status: 404, body: '' }));
  await p.goto('http://127.0.0.1:8899/review/?k=demo', { waitUntil: 'networkidle' }); await p.waitForTimeout(900);
  await report('review ' + tag, p, coarse);
  await p.close();
  await ctx.close();
  return errs;
}

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errs = [...await walk(b, false), ...await walk(b, true)];
  await b.close();
  console.log('=== errors ===\n' + (errs.join('\n') || 'none'));
  console.log(fails ? 'uxaudit: PROBLEM (' + fails + ' fail, ' + warns + ' warn)' : 'uxaudit: ok (' + warns + ' warn)');
  process.exit(fails || errs.length ? 1 : 0);
})();
