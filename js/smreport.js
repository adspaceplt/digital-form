/*
 * The social media report as a PDF.
 *
 * One function, `render(snapshot)`, draws the whole report from a snapshot
 * of the saved data (the report, its accounts, its posts) and answers the
 * bytes, the page count and any warnings. The snapshot is the database's
 * (`sm_report_snapshot`), so a version drawn today and the same version
 * drawn again next year are the same file; nothing here reads a table.
 *
 * It is drawn with pdf-lib in the browser, like the letters: text stays
 * selectable, the fonts are embedded, every page break is decided here and
 * nothing depends on a print dialog or on the machine it runs on. The
 * portal's hosting (GitHub Pages and Supabase) has no server that can run a
 * browser, so an HTML template rendered server-side is not available; this
 * is the deterministic renderer that is.
 *
 * Three faces and an image: Slate for Latin text, the Chinese face the
 * letters already embed for every glyph Slate lacks, and an emoji drawn by
 * the browser to a canvas and placed as a small image, because no embedded
 * font carries colour emoji. Each character picks its face by whether the
 * face has the glyph, so a caption that mixes English, Chinese, hashtags and
 * emoji is one paragraph and not three.
 */
(function () {
  var ORG = window.ADSPACE_ORG || {};
  var CFG = window.ADSPACE_CONFIG || {};

  // ---- Page geometry ----------------------------------------------------------
  /* Every measurement below is the ADspace Rate Card & Packages template's
     own (v2.0.5, read off the file the user sent on 2026-09-23): a 54pt
     margin, the Optima wordmark and a small capitals label on one line at the
     head, PRIVATE & CONFIDENTIAL over an italic reference line and the page
     count at the foot, the page title in Slate Regular 18pt, all text in the
     one ink #404040. The report is an ADspace document, so it wears the same
     paper as the rate card and the packages. */
  var W = 595.28, H = 841.89;
  var M = 54;                   // 0.75in, the rate card's margin
  var R = W - M, CW = R - M;    // the text column: 487.3pt
  var PHI = 0.618;
  var HEAD_Y = 781.7;           // the wordmark's baseline
  var LABEL_X = 264.5;          // the head label, where the rate card sets FOR INTERNAL USE
  var TOP = H - 88.1;           // the page title's baseline, as the rate card's Ala Carté
  var FLOOR = 74;               // nothing draws below this; the foot is under it
  var GUT = 20;

  // ---- Words ------------------------------------------------------------------
  var PLATFORM_WORD = {
    facebook: 'Facebook', instagram: 'Instagram', tiktok: 'TikTok', rednote: 'rednote', xhs: 'rednote',
    youtube: 'YouTube', linkedin: 'LinkedIn', x: 'X', threads: 'Threads', wechat: 'WeChat', other: 'Other'
  };
  var TYPE_WORD = {
    reel: 'Reel', video: 'Video', post: 'Post', photo: 'Photo', carousel: 'Carousel', story: 'Story',
    live: 'Live', short: 'Short', article: 'Article', other: ''
  };
  var METRIC_WORD = {
    views: 'Views', reach: 'Reach', impressions: 'Impressions', interactions: 'Interactions',
    engagements: 'Engagements', likes: 'Likes', comments: 'Comments', shares: 'Shares', saves: 'Saves'
  };
  var METRICS = ['views', 'reach', 'impressions', 'interactions', 'engagements', 'likes', 'comments', 'shares', 'saves'];
  var VOLUME = ['views', 'reach', 'impressions'];
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  var MON3 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

  function num(v) { return v === null || v === undefined || v === '' || isNaN(Number(v)) ? null : Number(v); }
  function fmt(v) {
    var n = num(v);
    if (n === null) return 'Not available';
    return n.toLocaleString('en-GB');
  }
  function signed(n) { n = num(n); if (n === null) return 'Not available'; return (n > 0 ? '+' : '') + n.toLocaleString('en-GB'); }
  function pct(v) { return v === null || v === undefined ? 'Not available' : (Math.round(v * 10000) / 100).toFixed(2) + '%'; }
  function dateOf(s) { var d = new Date(String(s || '').slice(0, 10) + 'T00:00:00'); return isNaN(d.getTime()) ? null : d; }
  function dayWord(s) { var d = dateOf(s); return d ? d.getDate() + ' ' + MON3[d.getMonth()] + ' ' + d.getFullYear() : String(s || ''); }
  function longDate(s) { var d = dateOf(s); return d ? d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear() : String(s || ''); }
  function stampWord(iso) { var d = iso ? new Date(iso) : null; return d && !isNaN(d.getTime()) ? d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear() : ''; }
  /* "August 2026" for a calendar month, "1 to 15 August 2026" for part of one,
     "28 July to 3 August 2026" across two. */
  function periodWord(a, b) {
    var da = dateOf(a), db = dateOf(b);
    if (!da || !db) return '';
    var last = new Date(da.getFullYear(), da.getMonth() + 1, 0).getDate();
    if (da.getMonth() === db.getMonth() && da.getFullYear() === db.getFullYear()) {
      if (da.getDate() === 1 && db.getDate() === last) return MONTHS[da.getMonth()] + ' ' + da.getFullYear();
      return da.getDate() + ' to ' + db.getDate() + ' ' + MONTHS[da.getMonth()] + ' ' + da.getFullYear();
    }
    return da.getDate() + ' ' + MONTHS[da.getMonth()] + (da.getFullYear() !== db.getFullYear() ? ' ' + da.getFullYear() : '') +
      ' to ' + db.getDate() + ' ' + MONTHS[db.getMonth()] + ' ' + db.getFullYear();
  }
  function hexRgb(PDF, hex, fallback) {
    var m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
    if (!m) return fallback;
    var v = parseInt(m[1], 16);
    return PDF.rgb(((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255);
  }
  function mix(PDF, c, white) {
    return PDF.rgb(c.red + (1 - c.red) * white, c.green + (1 - c.green) * white, c.blue + (1 - c.blue) * white);
  }
  function words(s) { return String(s == null ? '' : s).replace(/\r/g, ''); }
  /* One point a line: an insights field holds several, one per line, and a
     line that is only whitespace is not a point. Accidental repeated blank
     lines are collapsed; a single blank line still divides two points. */
  function points(s) {
    return words(s).split(/\n/).map(function (l) { return l.trim(); }).filter(Boolean);
  }
  /* A caption keeps its paragraphs exactly, collapsing only a run of three or
     more line breaks (two or more empty lines) to one paragraph break. */
  function paragraphsOf(s) {
    var t = words(s).replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
    return t.split('\n');
  }

  // ---- The model: what the numbers say ---------------------------------------
  function engOf(p) { var e = num(p.engagements); if (e !== null) return e; return num(p.interactions); }
  function growthOf(a) {
    var o = num(a.growth_override);
    if (o !== null) return o;
    var s = num(a.followers_start), e = num(a.followers_end);
    return s !== null && e !== null ? e - s : null;
  }
  function sumOf(rows, f) {
    var any = false, t = 0;
    rows.forEach(function (r) { var v = f(r); if (v !== null && v !== undefined) { any = true; t += v; } });
    return any ? t : null;
  }
  function metricsOf(acc, posts) {
    var m = (acc.metrics || []).filter(function (k) { return METRICS.indexOf(k) > -1; });
    if (m.length) return m;
    /* None stated: the metrics the posts actually carry, in the canonical order. */
    return METRICS.filter(function (k) { return posts.some(function (p) { return num(p[k]) !== null; }); });
  }
  function volumeMetric(metrics) {
    for (var i = 0; i < VOLUME.length; i++) if (metrics.indexOf(VOLUME[i]) > -1) return VOLUME[i];
    return null;
  }
  function engMetric(metrics) {
    if (metrics.indexOf('engagements') > -1) return 'engagements';
    if (metrics.indexOf('interactions') > -1) return 'interactions';
    return null;
  }
  function byPost(a, b) {
    var da = String(a.posted_on || ''), db = String(b.posted_on || '');
    if (da !== db) return da < db ? -1 : 1;
    return (Number(a.position) || 0) - (Number(b.position) || 0);
  }
  /* Accounts reported together (Facebook and Instagram, as Meta reports
     cross-posted content) are one group with both accounts' follower figures
     and one set of posts; an account on its own is a group of one. */
  function model(snap) {
    var rep = snap.report || {};
    var accs = (snap.platforms || []).slice().sort(function (a, b) { return (Number(a.position) || 0) - (Number(b.position) || 0); });
    var posts = (snap.posts || []).slice().sort(byPost);
    var groups = [], byKey = {};
    accs.forEach(function (a) {
      var key = a.group_key || ('acc:' + a.id);
      var g = byKey[key];
      if (!g) {
        g = { key: key, accounts: [], posts: [], label: a.group_label || PLATFORM_WORD[a.platform] || a.platform };
        byKey[key] = g; groups.push(g);
      }
      g.accounts.push(a);
    });
    posts.forEach(function (p) {
      var a = accs.filter(function (x) { return x.id === p.platform_id; })[0];
      var key = a ? (a.group_key || ('acc:' + a.id)) : null;
      var g = key && byKey[key];
      if (g) { p._group = g; g.posts.push(p); }
    });
    var rank = rep.rank_metric || 'views';
    groups.forEach(function (g) {
      var lead = g.accounts[0];
      g.metrics = metricsOf(lead, g.posts);
      g.volume = volumeMetric(g.metrics);
      g.engKey = engMetric(g.metrics);
      g.views = g.volume ? sumOf(g.posts, function (p) { return num(p[g.volume]); }) : null;
      g.eng = sumOf(g.posts, engOf);
      g.growth = sumOf(g.accounts, growthOf);
      g.basis = (g.accounts.filter(function (a) { return a.er_basis; })[0] || {}).er_basis || null;
      var denom = null;
      if (g.basis === 'followers') denom = sumOf(g.accounts, function (a) { return num(a.followers_end); });
      else if (g.basis) denom = sumOf(g.posts, function (p) { return num(p[g.basis]); });
      g.er = (g.basis && denom && g.eng !== null) ? g.eng / denom : null;
      g.rank = lead.rank_metric || rank;
      var withVol = g.posts.filter(function (p) { return g.volume && num(p[g.volume]) !== null; });
      g.mostViewed = withVol.slice().sort(function (a, b) { return num(b[g.volume]) - num(a[g.volume]); }).slice(0, 3);
      var withEng = g.posts.filter(function (p) { return engOf(p) !== null; });
      g.mostEngaged = withEng.slice().sort(function (a, b) { return engOf(b) - engOf(a); }).slice(0, 3);
      g.summary = (g.accounts.filter(function (a) { return words(a.summary).trim(); })[0] || {}).summary || '';
      g.worked = g.accounts.map(function (a) { return a.worked; }).filter(function (s) { return words(s).trim(); }).join('\n');
      g.improve = g.accounts.map(function (a) { return a.improve; }).filter(function (s) { return words(s).trim(); }).join('\n');
      g.actions = g.accounts.map(function (a) { return a.actions; }).filter(function (s) { return words(s).trim(); }).join('\n');
      g.notes = g.accounts.map(function (a) { return a.metric_notes; }).filter(function (s) { return words(s).trim(); }).join(' ');
    });
    var rankOf = function (p) { return rank === 'engagements' || rank === 'interactions' ? engOf(p) : num(p[rank]); };
    var ranked = posts.filter(function (p) { return p._group && rankOf(p) !== null; })
      .sort(function (a, b) { return rankOf(b) - rankOf(a); });
    var totals = {
      posts: posts.filter(function (p) { return p._group; }).length,
      growth: sumOf(groups, function (g) { return g.growth; }),
      views: sumOf(groups, function (g) { return g.views; }),
      eng: sumOf(groups, function (g) { return g.eng; }),
      volumeWords: uniq(groups.map(function (g) { return g.volume ? METRIC_WORD[g.volume] : null; }).filter(Boolean)),
      engWords: uniq(groups.map(function (g) { return g.engKey ? METRIC_WORD[g.engKey] : null; }).filter(Boolean)),
      er: null, basis: null
    };
    var bases = uniq(groups.map(function (g) { return g.basis; }).filter(Boolean));
    if (bases.length === 1 && groups.every(function (g) { return g.er !== null; })) {
      var e = 0, d = 0;
      groups.forEach(function (g) { e += g.eng; d += g.eng / g.er; });
      totals.er = d ? e / d : null; totals.basis = bases[0];
    }
    return { rep: rep, accounts: accs, posts: posts, groups: groups, totals: totals, rank: rank, rankOf: rankOf,
             best: ranked[0] || null, top: ranked.slice(0, 5),
             mostEngaged: posts.filter(function (p) { return engOf(p) !== null; }).sort(function (a, b) { return engOf(b) - engOf(a); })[0] || null };
  }
  function uniq(a) { var o = []; a.forEach(function (x) { if (o.indexOf(x) < 0) o.push(x); }); return o; }
  function listWords(items) {
    if (!items.length) return '';
    if (items.length === 1) return items[0];
    var own = items.some(function (s) { return / and /.test(s); });
    return items.slice(0, -1).join(', ') + (own ? ', and ' : ' and ') + items[items.length - 1];
  }

  // ---- Assets -----------------------------------------------------------------
  var bytesCache = {};
  function fetchBytes(url) {
    if (!url) return Promise.reject(new Error('none'));
    if (bytesCache[url]) return bytesCache[url];
    bytesCache[url] = fetch(url, { mode: 'cors' }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.arrayBuffer();
    });
    bytesCache[url].catch(function () { delete bytesCache[url]; });
    return bytesCache[url];
  }
  function isJpeg(u8) { return u8.length > 3 && u8[0] === 0xff && u8[1] === 0xd8 && u8[2] === 0xff; }
  function isPng(u8) { return u8.length > 8 && u8[0] === 0x89 && u8[1] === 0x50 && u8[2] === 0x4e && u8[3] === 0x47; }
  /* Any image the browser can decode becomes a PNG at up to 1400px on its long
     side, which keeps print quality at the sizes this report draws while a
     phone photo of four thousand pixels does not make a forty megabyte file. A
     JPEG or PNG within that size is embedded as it is. */
  function embedImage(pdf, url, warn) {
    if (!url) return Promise.resolve(null);
    return fetchBytes(url).then(function (buf) {
      var u8 = new Uint8Array(buf);
      var big = u8.length > 2.5e6;
      if (isJpeg(u8) && !big) return pdf.embedJpg(u8).catch(function () { return viaCanvas(pdf, buf); });
      if (isPng(u8) && !big) return pdf.embedPng(u8).catch(function () { return viaCanvas(pdf, buf); });
      return viaCanvas(pdf, buf);
    }).catch(function (e) {
      if (warn) warn('An image could not be loaded: ' + url.split('?')[0].split('/').pop() + ' (' + ((e && e.message) || e) + ').');
      return null;
    });
  }
  function viaCanvas(pdf, buf) {
    if (typeof createImageBitmap !== 'function') return Promise.reject(new Error('unsupported image'));
    return createImageBitmap(new Blob([buf])).then(function (bmp) {
      var max = 1400, s = Math.min(1, max / Math.max(bmp.width, bmp.height));
      var c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(bmp.width * s)); c.height = Math.max(1, Math.round(bmp.height * s));
      c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
      return new Promise(function (ok, bad) {
        c.toBlob(function (b) { if (!b) { bad(new Error('encode')); return; } b.arrayBuffer().then(function (ab) { ok(pdf.embedPng(new Uint8Array(ab))); }, bad); }, 'image/png');
      });
    });
  }

  // ---- Text: three faces and an image -----------------------------------------
  function hasGlyph(pdfFont, cp) {
    if (!pdfFont) return false;
    var f = pdfFont.embedder && pdfFont.embedder.font;
    if (f && typeof f.hasGlyphForCodePoint === 'function') return f.hasGlyphForCodePoint(cp);
    return cp >= 0x20 && cp <= 0x7e;   // a standard font: ASCII only
  }
  function isEmojiCp(cp) {
    return (cp >= 0x1f000 && cp <= 0x1faff) || (cp >= 0x2600 && cp <= 0x27bf) || (cp >= 0x2b00 && cp <= 0x2bff) ||
      cp === 0x3030 || cp === 0x303d || cp === 0x3297 || cp === 0x3299 || cp === 0x00a9 || cp === 0x00ae ||
      cp === 0x2122 || cp === 0x2139 || (cp >= 0x2194 && cp <= 0x21aa) || cp === 0x231a || cp === 0x231b ||
      cp === 0x2328 || cp === 0x23cf || (cp >= 0x23e9 && cp <= 0x23fa) || cp === 0x24c2 || cp === 0x25aa ||
      cp === 0x25ab || cp === 0x25b6 || cp === 0x25c0 || (cp >= 0x25fb && cp <= 0x25fe);
  }
  function isEmojiJoiner(cp) {
    return cp === 0x200d || cp === 0xfe0f || cp === 0xfe0e || cp === 0x20e3 || (cp >= 0x1f3fb && cp <= 0x1f3ff) ||
      (cp >= 0xe0020 && cp <= 0xe007f);
  }
  function isRegional(cp) { return cp >= 0x1f1e6 && cp <= 0x1f1ff; }
  function isCjkCp(cp) {
    return (cp >= 0x2e80 && cp <= 0x9fff) || (cp >= 0xac00 && cp <= 0xd7af) || (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0xff00 && cp <= 0xffef) || (cp >= 0x3000 && cp <= 0x303f) || (cp >= 0x20000 && cp <= 0x2fa1f);
  }
  /* A caption is walked code point by code point into atoms: a run of Latin
     that only breaks at a space or inside a long token, one Chinese character
     (Chinese breaks anywhere), one emoji cluster (a base, its skin tone, its
     joiners and what they join), or a space. Each atom knows which face
     draws it and how wide it is. */
  function Shaper(PDF, pdf, fonts, warn) {
    var emojiCache = {};
    var pending = [];
    function cps(s) {
      var out = [];
      for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
          var d = s.charCodeAt(i + 1);
          if (d >= 0xdc00 && d <= 0xdfff) { out.push(((c - 0xd800) << 10) + (d - 0xdc00) + 0x10000); i++; continue; }
        }
        out.push(c);
      }
      return out;
    }
    function ch(cp) { return String.fromCodePoint(cp); }
    /* Which face draws a code point: Slate where it has the glyph, the Chinese
       face where Slate does not, and an image where neither does. */
    function faceOf(cp, face) {
      if (cp === 0xfe0f || cp === 0xfe0e || cp === 0x200d) return null;   // invisible on their own
      if (hasGlyph(face, cp) && !(isEmojiCp(cp) && cp > 0x2000)) return face;
      if (fonts.cjk && hasGlyph(fonts.cjk, cp) && !isEmojiCp(cp)) return fonts.cjk;
      return 'emoji';
    }
    /* An emoji drawn by the browser at 96px and kept once per cluster. The
       canvas is measured for its ink so a wide flag and a narrow heart each
       take the room they need. */
    function emojiImage(text) {
      if (emojiCache[text]) return emojiCache[text];
      var entry = { img: null, ratio: 1, ok: false };
      emojiCache[text] = entry;
      try {
        var size = 96, pad = 12;
        var c = document.createElement('canvas');
        c.width = size * 2; c.height = size + pad * 2;
        var x = c.getContext('2d');
        x.font = (size - pad) + 'px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji","Twemoji Mozilla",sans-serif';
        x.textBaseline = 'top';
        x.fillText(text, pad, pad);
        var d = x.getImageData(0, 0, c.width, c.height).data;
        var minx = c.width, maxx = -1, miny = c.height, maxy = -1;
        for (var yy = 0; yy < c.height; yy++) for (var xx = 0; xx < c.width; xx++) {
          if (d[(yy * c.width + xx) * 4 + 3] > 8) { if (xx < minx) minx = xx; if (xx > maxx) maxx = xx; if (yy < miny) miny = yy; if (yy > maxy) maxy = yy; }
        }
        if (maxx < 0) return entry;
        var cw = maxx - minx + 1, chh = maxy - miny + 1;
        var o = document.createElement('canvas');
        o.width = cw; o.height = chh;
        o.getContext('2d').drawImage(c, minx, miny, cw, chh, 0, 0, cw, chh);
        entry.ratio = cw / chh;
        entry.ok = true;
        pending.push(new Promise(function (ok) {
          o.toBlob(function (b) {
            if (!b) { entry.ok = false; ok(); return; }
            b.arrayBuffer().then(function (ab) {
              return pdf.embedPng(new Uint8Array(ab)).then(function (img) { entry.img = img; ok(); });
            }).catch(function () { entry.ok = false; ok(); });
          }, 'image/png');
        }));
      } catch (e) { entry.ok = false; }
      return entry;
    }
    /* A run's width at a size: text through its face, an emoji by its ratio. */
    function runWidth(run, size) {
      if (run.f === 'emoji') return run.ok ? size * 1.06 * run.ratio + size * 0.12 : size * 1.1;
      return run.font.widthOfTextAtSize(run.s, size);
    }
    function atomsOf(text, face) {
      var list = cps(words(text).replace(/\t/g, ' '));
      var atoms = [];
      var cur = null;    // the Latin atom being built
      var flush = function () { if (cur) { atoms.push(cur); cur = null; } };
      var latinRun = function (font) {
        if (!cur) cur = { runs: [], space: false, brk: false };
        var last = cur.runs[cur.runs.length - 1];
        if (!last || last.font !== font) { last = { f: 'text', font: font, s: '' }; cur.runs.push(last); }
        return last;
      };
      for (var i = 0; i < list.length; i++) {
        var cp = list[i];
        if (cp === 0x20 || cp === 0xa0 || cp === 0x3000) { flush(); atoms.push({ runs: [{ f: 'text', font: face, s: ' ' }], space: true, brk: true }); continue; }
        if (cp < 0x20) continue;
        var f = faceOf(cp, face);
        if (f === null) continue;
        if (f === 'emoji' || (isRegional(cp))) {
          /* Gather the cluster: joiners, modifiers, a second regional indicator,
             and whatever a zero-width joiner joins. */
          var s = ch(cp), j = i + 1;
          if (isRegional(cp) && j < list.length && isRegional(list[j])) { s += ch(list[j]); j++; }
          while (j < list.length) {
            var n = list[j];
            if (isEmojiJoiner(n)) { s += ch(n); j++; if (n === 0x200d && j < list.length) { s += ch(list[j]); j++; } continue; }
            break;
          }
          i = j - 1;
          var e = emojiImage(s);
          flush();
          atoms.push({ runs: [{ f: 'emoji', s: s, entry: e, ok: e.ok, ratio: e.ratio }], space: false, brk: true });
          if (!e.ok && warn) warn('An emoji could not be drawn: ' + s);
          continue;
        }
        if (f === fonts.cjk && isCjkCp(cp)) {
          /* One character an atom; a closing punctuation mark stays with the
             character before it. */
          var punct = /[、。，．：；？！」』】〕）’”]/.test(ch(cp));
          if (punct && atoms.length && !cur && !atoms[atoms.length - 1].space) {
            atoms[atoms.length - 1].runs.push({ f: 'text', font: f, s: ch(cp) });
            continue;
          }
          flush();
          atoms.push({ runs: [{ f: 'text', font: f, s: ch(cp) }], space: false, brk: true });
          continue;
        }
        var r = latinRun(f);
        r.s += ch(cp);
        /* Inside a long token a break is allowed after a slash, a hyphen and
           the marks a web address is built from, so a link wraps at a
           sensible place rather than being cut mid word. */
        if (/[\/\-?&=_.,;:!]/.test(ch(cp)) && i + 1 < list.length && list[i + 1] !== 0x20) {
          cur.brk = true; flush();
        }
      }
      flush();
      atoms.forEach(function (a) {
        a.w = function (size) { return a.runs.reduce(function (t, r) { return t + runWidth(r, size); }, 0); };
      });
      return atoms;
    }
    /* Greedy line filling, with an atom wider than the line cut by character. */
    function linesOf(text, max, size, face) {
      var atoms = atomsOf(text, face);
      var lines = [], line = [], lw = 0;
      var push = function () { while (line.length && line[line.length - 1].space) line.pop(); lines.push(line); line = []; lw = 0; };
      for (var i = 0; i < atoms.length; i++) {
        var a = atoms[i], w = a.w(size);
        if (a.space && !line.length) continue;
        if (lw + w <= max + 0.01 || !line.length && w <= max) { line.push(a); lw += w; continue; }
        if (w > max) {
          /* Cut the long token where it stops fitting, run by run. */
          var parts = splitAtom(a, max - (line.length ? lw : 0), max, size);
          if (parts.head) { line.push(parts.head); }
          push();
          parts.rest.forEach(function (p, k) { if (k < parts.rest.length - 1) { lines.push([p]); } else { line = [p]; lw = p.w(size); } });
          continue;
        }
        push();
        line.push(a); lw = w;
      }
      if (line.length) push();
      if (!lines.length) lines.push([]);
      return lines;
    }
    function splitAtom(a, first, max, size) {
      var out = { head: null, rest: [] };
      var chunks = [];
      a.runs.forEach(function (r) {
        if (r.f === 'emoji') { chunks.push({ runs: [r] }); return; }
        cps(r.s).forEach(function (cp) { chunks.push({ runs: [{ f: 'text', font: r.font, s: ch(cp) }] }); });
      });
      var mk = function (rs) { var x = { runs: rs, space: false, brk: true }; x.w = function (sz) { return rs.reduce(function (t, r) { return t + runWidth(r, sz); }, 0); }; return x; };
      var cur = [], curW = 0, limit = first > size ? first : 0, started = false;
      chunks.forEach(function (c) {
        var w = runWidth(c.runs[0], size);
        var cap = started ? max : (limit || max);
        if (curW + w > cap && cur.length) {
          if (!started && limit) { out.head = mk(cur); } else { out.rest.push(mk(cur)); }
          started = true; cur = []; curW = 0;
        }
        cur.push(c.runs[0]); curW += w;
      });
      if (cur.length) { if (!started && limit) out.head = mk(cur); else out.rest.push(mk(cur)); }
      if (!out.rest.length && out.head) { out.rest.push(out.head); out.head = null; }
      return out;
    }
    function lineWidth(line, size) { return line.reduce(function (t, a) { return t + a.w(size); }, 0); }
    function draw(page, line, x, y, size, color) {
      var cx = x;
      line.forEach(function (a) {
        a.runs.forEach(function (r) {
          var w = runWidth(r, size);
          if (r.f === 'emoji') {
            if (r.entry && r.entry.img) {
              var h = size * 1.06, ww = h * r.entry.ratio;
              page.drawImage(r.entry.img, { x: cx + size * 0.06, y: y - size * 0.22, width: ww, height: h });
            }
          } else if (r.s) {
            page.drawText(r.s, { x: cx, y: y, size: size, font: r.font, color: color });
          }
          cx += w;
        });
      });
    }
    return { linesOf: linesOf, lineWidth: lineWidth, draw: draw, ready: function () { return Promise.all(pending); } };
  }

  // ---- Rendering ---------------------------------------------------------------
  function render(snap, opts) {
    opts = opts || {};
    var PDF = window.PDFLib;
    var DOCS = window.ADspaceDocs;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    if (!DOCS) return Promise.reject(new Error('The document engine (js/documents.js) is not loaded'));
    var warnings = [];
    var warn = function (s) { if (warnings.indexOf(s) < 0) warnings.push(s); };
    var mdl = model(snap);
    var rep = mdl.rep;
    var everyText = [rep.title, rep.intro, rep.headline, rep.client_name].concat(
      Object.keys(rep.insights || {}).map(function (k) { return rep.insights[k]; }),
      mdl.accounts.map(function (a) { return [a.account_name, a.summary, a.worked, a.improve, a.actions, a.metric_notes].join(' '); }),
      mdl.posts.map(function (p) { return [p.title, p.caption, p.observation, p.notable, p.theme].join(' '); })).join(' ');
    var needsCjk = /[⺀-鿿가-힯豈-﫿＀-￯]/.test(everyText);
    var pdf, fonts, logo, sh;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      return Promise.all([DOCS.embedFonts(pdf, PDF, { cjk: needsCjk }), DOCS.embedLogo(pdf)]);
    }).then(function (got) {
      fonts = got[0]; logo = got[1];
      if (needsCjk && !fonts.cjk) {
        throw new Error('The Chinese font could not be loaded, so the Chinese text in this report cannot be drawn. Check fontCjk in js/config.js.');
      }
      sh = Shaper(PDF, pdf, fonts, warn);
      var thumbJobs = {};
      mdl.posts.forEach(function (p) {
        var u = p.thumb_url || p.thumb_signed_url || null;
        if (u) thumbJobs[p.id] = embedImage(pdf, u, warn);
      });
      var logoJob = rep.client_logo_url ? embedImage(pdf, rep.client_logo_url, null) : Promise.resolve(null);
      return Promise.all([Promise.all(Object.keys(thumbJobs).map(function (id) { return thumbJobs[id].then(function (img) { return [id, img]; }); })), logoJob]);
    }).then(function (got) {
      var thumbs = {};
      got[0].forEach(function (pair) { thumbs[pair[0]] = pair[1]; });
      var clientLogo = got[1];
      return draw(PDF, pdf, fonts, logo, clientLogo, sh, mdl, thumbs, warn, opts).then(function (pages) {
        return sh.ready().then(function () {
          pdf.setTitle(String(rep.client_name || '') + ' ' + String(rep.title || 'Social Media Accounts Report') + ' ' + periodWord(rep.period_start, rep.period_end));
          pdf.setAuthor(CFG.agencyName || 'ADspace');
          pdf.setSubject('Social media performance report');
          pdf.setCreator('ADspace Digital Portal');
          pdf.setProducer('ADspace Digital Portal');
          return pdf.save({ useObjectStreams: true }).then(function (bytes) {
            return { bytes: bytes, pages: pages, warnings: warnings };
          });
        });
      });
    });
  }

  function draw(PDF, pdf, fonts, logo, clientLogo, sh, mdl, thumbs, warn, opts) {
    var rep = mdl.rep;
    var book = fonts.font, reg = fonts.bold, med = fonts.med || reg, mark = fonts.mark || med;
    var INK = PDF.rgb(0.251, 0.251, 0.251), SOFT = PDF.rgb(0.32, 0.31, 0.28), MUTE = PDF.rgb(0.42, 0.40, 0.38);
    var LINE = PDF.rgb(0.85, 0.84, 0.82), HAIR = PDF.rgb(0.90, 0.89, 0.87), PAPER = PDF.rgb(1, 1, 1);
    var ACCENT = hexRgb(PDF, rep.accent, PDF.rgb(0.043, 0.341, 0.816));
    var ACCENT_SOFT = mix(PDF, ACCENT, 0.86);
    var FIELD = PDF.rgb(0.106, 0.102, 0.090);
    var isDraft = rep.status !== 'final' || opts.proof;
    var periodW = periodWord(rep.period_start, rep.period_end);
    var runHead = [rep.client_name, rep.title || 'Social Media Accounts Report', periodW].filter(Boolean).join('  ·  ');

    var pages = [];   // { page, kind, section }
    var pg = null, y = 0;
    var text = function (s, x, yy, size, f, color) { pg.page.drawText(String(s == null ? '' : s), { x: x, y: yy, size: size || 10.5, font: f || book, color: color || INK }); };
    var width = function (s, size, f) { return (f || book).widthOfTextAtSize(String(s == null ? '' : s), size || 10.5); };
    var right = function (s, xr, yy, size, f, color) { text(s, xr - width(s, size, f), yy, size, f, color); };
    var rule = function (yy, x1, x2, color, thick) { pg.page.drawLine({ start: { x: x1 == null ? M : x1, y: yy }, end: { x: x2 == null ? R : x2, y: yy }, thickness: thick || 0.6, color: color || LINE }); };
    var rect = function (x, yy, w, h, color, opacity) { pg.page.drawRectangle({ x: x, y: yy, width: w, height: h, color: color, borderWidth: 0, opacity: opacity == null ? 1 : opacity }); };
    /* Latin-only strings (labels, numbers) go straight to the face; anything a
       person typed goes through the shaper. */
    var safe = function (s) { return sh.linesOf(String(s == null ? '' : s), 1e6, 10, book)[0]; };
    var tline = function (s, x, yy, size, f, color, maxW) {
      var line = sh.linesOf(String(s == null ? '' : s), maxW || 1e6, size, f || book)[0] || [];
      sh.draw(pg.page, line, x, yy, size, color || INK);
      return sh.lineWidth(line, size);
    };
    var tright = function (s, xr, yy, size, f, color) {
      var line = sh.linesOf(String(s == null ? '' : s), 1e6, size, f || book)[0] || [];
      sh.draw(pg.page, line, xr - sh.lineWidth(line, size), yy, size, color || INK);
    };
    /* One line, ellipsised to a width. */
    var clip = function (s, maxW, size, f) {
      var str = String(s == null ? '' : s);
      var line = sh.linesOf(str, 1e6, size, f || book)[0] || [];
      if (sh.lineWidth(line, size) <= maxW) return str;
      var lo = 0, hi = str.length;
      while (lo < hi) {
        var mid = Math.ceil((lo + hi) / 2);
        var l2 = sh.linesOf(str.slice(0, mid).trim() + '…', 1e6, size, f || book)[0] || [];
        if (sh.lineWidth(l2, size) <= maxW) lo = mid; else hi = mid - 1;
      }
      return str.slice(0, lo).trim() + '…';
    };
    var newPage = function (section) {
      pg = { page: pdf.addPage([W, H]), section: section || '' };
      pages.push(pg);
      y = TOP;
    };
    var need = function (h) { if (y - h < FLOOR) { newPage(pg.section); return true; } return false; };
    /* Paragraphs: wrapped, drawn, page breaks inside them allowed, a widow of
       one line at the top of a page avoided where the paragraph has more
       than two lines. */
    var para = function (s, x, w, size, lh, f, color, keepFirst) {
      var lines = sh.linesOf(s, w, size, f || book);
      lines.forEach(function (ln, i) {
        if (i === 0 && keepFirst) need(lh * Math.min(2, lines.length));
        else need(lh);
        sh.draw(pg.page, ln, x, y, size, color || INK);
        y -= lh;
      });
      return lines.length;
    };
    var paraBlock = function (s, x, w, size, lh, f, color, gap) {
      var ps = paragraphsOf(s);
      ps.forEach(function (p, i) {
        if (!p.trim()) { y -= (gap == null ? lh * 0.6 : gap); return; }
        para(p, x, w, size, lh, f, color, true);
      });
    };
    var sectionLabel = function (s, x, yy, color) { tline(String(s || ''), x, yy, 8.5, reg, color || MUTE, R - x); };
    var pageTitle = function (s, sub) {
      tline(s, M, y, 18, reg, INK, CW); y -= 20;
      if (sub) { tline(sub, M, y, 9.5, book, MUTE, CW); y -= 16; }
      y -= 10;
    };
    var subTitle = function (s) {
      need(34);
      y -= 8;
      tline(s, M, y, 11.04, reg, INK, CW); y -= 16;
    };
    var fitImage = function (img, boxW, boxH) {
      var s = Math.min(boxW / img.width, boxH / img.height);
      return { w: img.width * s, h: img.height * s };
    };
    var thumbBox = function (img, x, yTop, boxW, boxH, label) {
      if (img) {
        var d = fitImage(img, boxW, boxH);
        pg.page.drawImage(img, { x: x, y: yTop - d.h, width: d.w, height: d.h });
        return d;
      }
      var hh = Math.min(boxH, boxW * 1.1);
      rect(x, yTop - hh, boxW, hh, HAIR);
      var wds = sh.linesOf(label || 'No image', boxW - 12, 7.5, book);
      var ly = yTop - hh / 2 + (wds.length * 10) / 2 - 8;
      wds.forEach(function (ln) { sh.draw(pg.page, ln, x + 6, ly, 7.5, MUTE); ly -= 10; });
      return { w: boxW, h: hh };
    };
    var groupWord = function (p) { return p._group ? p._group.label : ''; };
    var typeWord = function (p) { return TYPE_WORD[p.content_type] || (p.content_type ? String(p.content_type) : ''); };
    var metricPairs = function (p, g) {
      var keys = g ? g.metrics : METRICS.filter(function (k) { return num(p[k]) !== null; });
      return keys.map(function (k) { return { label: METRIC_WORD[k], value: fmt(p[k]), na: num(p[k]) === null }; });
    };

    // ---------------------------------------------------------------- Cover
    (function cover() {
      /* The rate card's cover, and nothing else on it: the head and the foot
         every page carries, and the title set in Slate Medium on the page's
         golden axis, indented one step from the margin. Under it, whose report
         and which month. What the month achieved is the executive summary's
         to say, on the next page. */
      newPage('cover');
      var cx = M + 72, cw = R - cx;
      var cy = 497;
      var tlines = sh.linesOf(String(rep.title || 'Social Media Accounts Report'), cw, 25.92, med);
      cy += (tlines.length - 1) * 31;
      tlines.forEach(function (ln) { sh.draw(pg.page, ln, cx, cy, 25.92, INK); cy -= 31; });
      cy -= 2;
      sh.linesOf(String(rep.client_name || ''), cw, 14, reg).forEach(function (ln) { sh.draw(pg.page, ln, cx, cy, 14, INK); cy -= 19; });
      tline(periodW, cx, cy, 11.04, book, INK, cw);
    })();

    // ------------------------------------------------------- Executive summary
    (function summary() {
      newPage('Executive summary');
      pageTitle('Executive summary', periodW + '  ·  ' + listWords(mdl.groups.map(function (g) { return g.label; })) + '  ·  ' + mdl.totals.posts + (mdl.totals.posts === 1 ? ' post' : ' posts'));
      var t = mdl.totals;
      var head = words(rep.headline).trim();
      if (!head) {
        var bits = [];
        bits.push(t.posts + (t.posts === 1 ? ' post' : ' posts') + ' across ' + listWords(mdl.groups.map(function (g) { return g.label; })));
        if (t.views !== null) bits.push(fmt(t.views) + ' ' + (t.volumeWords.length === 1 ? t.volumeWords[0].toLowerCase() : 'views, reach and impressions'));
        if (t.eng !== null) bits.push(fmt(t.eng) + ' ' + (t.engWords.length === 1 ? t.engWords[0].toLowerCase() : 'engagements and interactions'));
        if (t.growth !== null) bits.push(signed(t.growth) + ' followers');
        head = bits.join(', ') + ' in ' + periodW + '.';
      }
      sh.linesOf(head, CW, 14.5, med).slice(0, 4).forEach(function (ln) { sh.draw(pg.page, ln, M, y, 14.5, INK); y -= 20; });
      y -= 4;
      if (words(rep.intro).trim()) { paraBlock(rep.intro, M, CW, 10.5, 15.5, book, SOFT); }
      y -= 8;
      // The band: five figures, hairlines above and below, nothing boxed.
      var cells = [
        { label: 'Content published', value: String(t.posts) },
        { label: 'Net follower growth', value: signed(t.growth), note: mdl.groups.length > 1 ? 'across ' + mdl.accounts.length + ' accounts' : '' },
        { label: t.volumeWords.length === 1 ? 'Total ' + t.volumeWords[0].toLowerCase() : 'Total views, reach and impressions', value: fmt(t.views) },
        { label: t.engWords.length === 1 ? 'Total ' + t.engWords[0].toLowerCase() : 'Total engagements', value: fmt(t.eng), note: t.engWords.length > 1 ? t.engWords.map(function (w) { return w.toLowerCase(); }).join(' and ') : '' },
        { label: 'Engagement rate', value: pct(t.er), note: t.basis ? 'of ' + t.basis : 'basis differs by platform' }
      ];
      band(cells);
      y -= 8;
      // One chart: the month, post by post.
      subTitle(t.volumeWords.length === 1 ? t.volumeWords[0] + ' per post through the month' : 'Views, reach and impressions per post through the month');
      chartByDate(M, y, CW, 104, mdl.posts.filter(function (p) { return p._group; }), mdl.groups);
      y -= 104 + 26;
      // The featured post and the two lists, side by side where there is room.
      need(150);
      var best = mdl.best;
      var colL = CW * 0.5 - GUT / 2, colR = CW * 0.5 - GUT / 2, xr = M + colL + GUT;
      var yTop = y;
      if (best) {
        sectionLabel('Best-performing post', M, y); y -= 14;
        var img = thumbs[best.id];
        var d = thumbBox(img, M, y, 72, 96, best.title);
        var tx = M + 84, tw = colL - 84, ty = y - 9;
        sh.linesOf(best.title || 'Untitled post', tw, 11, med).slice(0, 3).forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, 11, INK); ty -= 14.5; });
        tline([groupWord(best), dayWord(best.posted_on), typeWord(best)].filter(Boolean).join('  ·  '), tx, ty, 8.5, book, MUTE, tw); ty -= 13;
        var g = best._group;
        var ml = [];
        if (g && g.volume) ml.push(fmt(best[g.volume]) + ' ' + METRIC_WORD[g.volume].toLowerCase());
        if (engOf(best) !== null) ml.push(fmt(engOf(best)) + ' ' + (g && g.engKey ? METRIC_WORD[g.engKey].toLowerCase() : 'engagements'));
        tline(ml.join('  ·  '), tx, ty, 9.5, reg, INK, tw); ty -= 14;
        if (words(best.notable).trim()) {
          sh.linesOf(best.notable, tw, 9, book).slice(0, 4).forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, 9, SOFT); ty -= 12.5; });
        }
        y = Math.min(y - d.h - 6, ty - 4);
      }
      var obs = points(rep.insights && (rep.insights.performed_well || rep.insights.executive_summary)).slice(0, 3);
      var acts = points(rep.insights && rep.insights.next_actions).slice(0, 3);
      var ly = yTop;
      /* The two lists stand beside the featured post only where they fit on
         the page; otherwise they follow it across the full column, breaking
         over the page like any paragraph. They ran into the foot before. */
      var listH = function (items, w) {
        return 15 + (items.length ? items.reduce(function (t, it) { return t + sh.linesOf(it, w - 16, 9.5, book).length * 13 + 4; }, 0) : 14);
      };
      var halfW = (CW - GUT) / 2;
      if (yTop - listH(obs, colR) - 6 - listH(acts, colR) < FLOOR &&
          y - 14 - Math.max(listH(obs, halfW), listH(acts, halfW)) >= FLOOR) {
        /* Under the featured post, the two lists side by side. */
        y -= 14;
        var yCols = y, low = y;
        [[obs, 'Three observations', M], [acts, 'Three next actions', M + halfW + GUT]].forEach(function (c) {
          ly = yCols;
          list(c[1], c[0], c[2], halfW);
          low = Math.min(low, ly);
        });
        y = low - 6;
        return;
      }
      if (yTop - listH(obs, colR) - 6 - listH(acts, colR) < FLOOR) {
        var flow = function (title, items) {
          var first = items.length ? sh.linesOf(items[0], CW - 16, 9.5, book).length : 1;
          need(29 + (first <= 4 ? first : 2) * 13); y -= 14;
          sectionLabel(title, M, y); y -= 15;
          if (!items.length) { text('None recorded.', M, y, 9.5, book, MUTE); y -= 14; return; }
          items.forEach(function (it, i) {
            var lines = sh.linesOf(it, CW - 16, 9.5, book);
            need((lines.length <= 4 ? lines.length : 2) * 13);   // a short item is never split
            text(String(i + 1), M, y, 9.5, med, ACCENT);
            lines.forEach(function (ln) { need(13); sh.draw(pg.page, ln, M + 16, y, 9.5, INK); y -= 13; });
            y -= 4;
          });
        };
        flow('Three observations', obs);
        flow('Three next actions', acts);
        return;
      }
      function list(title, items, x, w) {
        sectionLabel(title, x, ly); ly -= 15;
        if (!items.length) { text('None recorded.', x, ly, 9.5, book, MUTE); ly -= 14; return; }
        items.forEach(function (it, i) {
          var lines = sh.linesOf(it, w - 16, 9.5, book);
          text(String(i + 1), x, ly, 9.5, med, ACCENT);
          lines.forEach(function (ln) { sh.draw(pg.page, ln, x + 16, ly, 9.5, INK); ly -= 13; });
          ly -= 4;
        });
      }
      list('Three observations', obs, xr, colR);
      ly -= 6;
      list('Three next actions', acts, xr, colR);
      y = Math.min(y, ly) - 6;
    })();

    // ------------------------------------------------------- Platform pages
    mdl.groups.forEach(function (g) {
      newPage(g.label);
      var accLine = g.accounts.map(function (a) {
        var w = PLATFORM_WORD[a.platform] || a.platform;
        return w + (a.handle ? ' @' + String(a.handle).replace(/^@/, '') : (a.account_name ? ' · ' + a.account_name : ''));
      }).join('  ·  ');
      pageTitle(g.label, accLine);
      if (words(g.summary).trim()) {
        sh.linesOf(g.summary, CW, 13, med).slice(0, 4).forEach(function (ln) { sh.draw(pg.page, ln, M, y, 13, INK); y -= 18; });
        y -= 6;
      }
      var cells = [{ label: 'Posts', value: String(g.posts.length) }];
      g.accounts.forEach(function (a) {
        var gr = growthOf(a);
        var note = num(a.followers_start) !== null && num(a.followers_end) !== null ? fmt(a.followers_start) + ' to ' + fmt(a.followers_end) : (num(a.growth_override) !== null ? 'recorded growth' : '');
        cells.push({ label: (g.accounts.length > 1 ? (PLATFORM_WORD[a.platform] || a.platform) + ' followers' : 'Follower growth'), value: signed(gr), note: note });
      });
      if (g.volume) cells.push({ label: 'Total ' + METRIC_WORD[g.volume].toLowerCase(), value: fmt(g.views) });
      if (g.engKey) cells.push({ label: 'Total ' + METRIC_WORD[g.engKey].toLowerCase(), value: fmt(g.eng) });
      cells.push({ label: 'Engagement rate', value: pct(g.er), note: g.basis ? 'of ' + g.basis : 'no basis set' });
      band(cells.slice(0, 6));
      y -= 8;
      // Follower movement where both ends are known.
      var movers = g.accounts.filter(function (a) { return num(a.followers_start) !== null && num(a.followers_end) !== null; });
      if (movers.length) {
        subTitle('Follower movement');
        movers.forEach(function (a) {
          need(24);
          var s = num(a.followers_start), e = num(a.followers_end), maxv = Math.max(s, e, 1);
          var lx = M + 120, lw = CW - 120 - 70;
          text(PLATFORM_WORD[a.platform] || a.platform, M, y, 9.5, reg, INK);
          rect(lx, y - 2, lw * (s / maxv), 8, HAIR);
          rect(lx, y - 2, lw * (e / maxv), 4, ACCENT);
          right(fmt(s) + ' to ' + fmt(e), R, y, 9, book, SOFT);
          y -= 20;
        });
        y -= 6;
      }
      if (g.volume && g.posts.some(function (p) { return num(p[g.volume]) !== null; })) {
        subTitle(METRIC_WORD[g.volume] + ' per post, by posting date');
        need(140);
        chartByDate(M, y, CW, 120, g.posts, [g]);
        y -= 120 + 26;
      }
      if (g.engKey && g.posts.some(function (p) { return engOf(p) !== null; })) {
        subTitle(METRIC_WORD[g.engKey] + ', the five highest posts');
        var rows = g.posts.filter(function (p) { return engOf(p) !== null; }).sort(function (a, b) { return engOf(b) - engOf(a); }).slice(0, 5);
        hbars(rows.map(function (p) { return { label: p.title || 'Untitled post', value: engOf(p), sub: dayWord(p.posted_on) }; }));
        y -= 8;
      }
      // Most viewed and most engaged, side by side.
      if (g.mostViewed.length || g.mostEngaged.length) {
        need(120);
        var colW = CW * 0.5 - GUT / 2, yTop = y, yL = y, yR = y;
        var mini = function (title, list, metric, x, yy) {
          sectionLabel(title, x, yy); yy -= 14;
          list.forEach(function (p, i) {
            var img = thumbs[p.id];
            var d = thumbBox(img, x, yy, 30, 40, '');
            var tx = x + 40, tw = colW - 40;
            text(String(i + 1), x + 34, yy - 9, 8, med, ACCENT);
            tline(clip(p.title || 'Untitled post', tw - 10, 9.5, med), tx + 10, yy - 9, 9.5, med, INK);
            tline(dayWord(p.posted_on) + '  ·  ' + fmt(metric(p)) + ' ' + (metric === engOf ? (g.engKey ? METRIC_WORD[g.engKey].toLowerCase() : 'engagements') : METRIC_WORD[g.volume].toLowerCase()), tx + 10, yy - 22, 8.5, book, MUTE, tw - 10);
            yy -= Math.max(d.h, 30) + 10;
          });
          return yy;
        };
        if (g.mostViewed.length) yL = mini('Most ' + (g.volume === 'views' ? 'viewed' : g.volume === 'reach' ? 'reach' : 'impressions'), g.mostViewed, function (p) { return num(p[g.volume]); }, M, yTop);
        if (g.mostEngaged.length) yR = mini('Most ' + (g.engKey === 'interactions' ? 'interacted' : 'engaged'), g.mostEngaged, engOf, M + colW + GUT, yTop);
        y = Math.min(yL, yR) - 4;
      }
      var block = function (title, s) {
        if (!words(s).trim()) return;
        subTitle(title);
        var ps = points(s);
        ps.forEach(function (p) { para(p, M, CW, 10.5, 15.5, book, INK, true); y -= 4; });
        y -= 4;
      };
      /* The notes a platform page ends on are short, so they stand side by
         side in columns where they fit on the page, rather than one or two
         lines spilling onto a page of their own; long ones stack. */
      var notes = [['What worked', g.worked], ['What should improve', g.improve], ['Recommended next actions', g.actions]]
        .filter(function (b) { return words(b[1]).trim(); });
      if (notes.length > 1) {
        var nw = (CW - GUT * (notes.length - 1)) / notes.length;
        var laid = notes.map(function (b) {
          var ls = []; points(b[1]).forEach(function (pt) { ls = ls.concat(sh.linesOf(pt, nw, 10, book)); ls.push(null); });
          return { title: b[0], lines: ls };
        });
        var tallest = laid.reduce(function (m, b) { return Math.max(m, 24 + b.lines.length * 14); }, 0);
        if (y - 8 - tallest >= FLOOR) {
          y -= 8;
          laid.forEach(function (b, k) {
            var x = M + k * (nw + GUT), yy = y;
            tline(b.title, x, yy, 11.04, reg, INK, nw); yy -= 16;
            b.lines.forEach(function (ln) { if (ln === null) { yy -= 4; return; } sh.draw(pg.page, ln, x, yy, 10, INK); yy -= 14; });
          });
          y -= tallest;
          return;
        }
      }
      notes.forEach(function (b) { need(52); block(b[0], b[1]); });
    });

    // ------------------------------------------------------- Top posts
    if (mdl.top.length) {
      newPage('Top-performing posts');
      pageTitle('Top-performing posts', 'Ranked by ' + METRIC_WORD[mdl.rank].toLowerCase() + ' across every platform  ·  full captions in the appendix');
      mdl.top.forEach(function (p, i) {
        var g = p._group;
        var img = thumbs[p.id];
        var thumbW = 78, thumbH = 100;
        var tx = M + 44 + thumbW + 14, tw = R - tx;
        var excerpt = words(p.caption).trim() ? sh.linesOf(paragraphsOf(p.caption).filter(function (s) { return s.trim(); }).join(' '), tw, 9.5, book) : [];
        var ex = excerpt.slice(0, 4);
        var notable = words(p.notable).trim() ? sh.linesOf(p.notable, tw, 9.5, book) : [];
        var textH = 16 + 13 + 14 + ex.length * 13 + (ex.length ? 6 : 0) + notable.length * 13 + (notable.length ? 6 : 0);
        var entryH = Math.max(thumbH, textH) + 18;
        need(entryH);
        var top = y;
        text(String(i + 1), M, top - 22, 26, med, ACCENT);
        thumbBox(img, M + 44, top, thumbW, thumbH, p.title);
        var ty = top - 9;
        sh.linesOf(p.title || 'Untitled post', tw, 12, med).slice(0, 2).forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, 12, INK); ty -= 15; });
        tline([g ? g.label : '', dayWord(p.posted_on), typeWord(p)].filter(Boolean).join('  ·  '), tx, ty, 8.5, book, MUTE, tw); ty -= 13;
        var ml = metricPairs(p, g).filter(function (m) { return !m.na; }).map(function (m) { return m.value + ' ' + m.label.toLowerCase(); });
        tline(ml.join('  ·  '), tx, ty, 9.5, reg, INK, tw); ty -= 15;
        if (ex.length) {
          ex.forEach(function (ln, k) {
            if (k === ex.length - 1 && excerpt.length > ex.length) { sh.draw(pg.page, ln, tx, ty, 9.5, SOFT); }
            else sh.draw(pg.page, ln, tx, ty, 9.5, SOFT);
            ty -= 13;
          });
          if (excerpt.length > ex.length) { text('Continued in the appendix.', tx, ty, 8.5, book, MUTE); ty -= 13; }
          ty -= 3;
        }
        if (notable.length) {
          sectionLabel('Why it stood out', tx, ty); ty -= 12;
          notable.forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, 9.5, INK); ty -= 13; });
        }
        y = top - entryH;
        rule(y + 8, M, R, HAIR, 0.5);
      });
      if (mdl.mostEngaged && mdl.top.indexOf(mdl.mostEngaged) < 0) {
        need(30);
        y -= 4;
        tline('Most engaged post of the month: ' + (mdl.mostEngaged.title || 'Untitled post') + ' (' + fmt(engOf(mdl.mostEngaged)) + ' ' + ((mdl.mostEngaged._group && mdl.mostEngaged._group.engKey) ? METRIC_WORD[mdl.mostEngaged._group.engKey].toLowerCase() : 'engagements') + ', ' + dayWord(mdl.mostEngaged.posted_on) + ').', M, y, 9.5, book, SOFT, CW);
        y -= 14;
      }
    }

    // ------------------------------------------------------- Remarks
    (function remarks() {
      var ins = rep.insights || {};
      var sections = [
        ['What performed well', ins.performed_well],
        ['Why it performed well', ins.why_well],
        ['What underperformed', ins.underperformed],
        ['Opportunities', ins.opportunities],
        ['Recommended improvements', ins.improvements],
        ['Actions for the following month', ins.next_actions]
      ].filter(function (s) { return words(s[1]).trim(); });
      if (!sections.length) return;
      newPage('Remarks and recommendations');
      pageTitle('Remarks and recommendations', periodW);
      if (words(ins.executive_summary).trim()) { paraBlock(ins.executive_summary, M, CW, 11, 16, book, INK); y -= 6; }
      sections.forEach(function (s) {
        subTitle(s[0]);
        var ps = points(s[1]);
        ps.forEach(function (p, i) {
          var lines = sh.linesOf(p, CW - 22, 10.5, book);
          need(15.5 * Math.min(2, lines.length));
          text(String(i + 1), M, y, 10.5, med, ACCENT);
          lines.forEach(function (ln, k) { if (k) need(15.5); sh.draw(pg.page, ln, M + 22, y, 10.5, INK); y -= 15.5; });
          y -= 5;
        });
        y -= 4;
      });
    })();

    // ------------------------------------------------------- Appendix
    (function appendix() {
      var all = mdl.groups.reduce(function (a, g) { return a.concat(g.posts); }, []);
      if (!all.length) return;
      newPage('Appendix: every post');
      pageTitle('Appendix: every post', mdl.totals.posts + (mdl.totals.posts === 1 ? ' post' : ' posts') + '  ·  ' + periodW + '  ·  full captions as published');
      var thumbW = Math.round(CW * 0.3), thumbHMax = 170;
      var tx = M + thumbW + GUT, tw = R - tx;
      var current = null;
      mdl.groups.forEach(function (g) {
        g.posts.forEach(function (p, idx) {
          var img = thumbs[p.id];
          var d = img ? fitImage(img, thumbW, thumbHMax) : { w: thumbW, h: Math.min(thumbHMax, thumbW * 1.1) };
          var ctx = [g.label, dayWord(p.posted_on), typeWord(p), p.theme].filter(function (s) { return words(s).trim(); }).join('  ·  ');
          var titleLines = sh.linesOf(p.title || 'Untitled post', tw, 12, med);
          var capParas = paragraphsOf(p.caption);
          var capLines = [];
          capParas.forEach(function (cp) {
            if (!cp.trim()) { capLines.push(null); return; }
            sh.linesOf(cp, tw, 10, book).forEach(function (ln) { capLines.push(ln); });
          });
          while (capLines.length && capLines[capLines.length - 1] === null) capLines.pop();
          var pairs = metricPairs(p, g);
          var headH = 12 + titleLines.length * 15 + 4;
          var bandH = pairs.length ? 34 : 0;
          var obsLines = words(p.observation).trim() ? sh.linesOf(p.observation, tw, 9.5, book) : [];
          var urlLines = words(p.url).trim() ? sh.linesOf(p.url, tw, 8.5, book) : [];
          var LH = 14.5;
          /* The heading stays with at least the first two caption lines, and a
             thumbnail never stands at the foot of a page on its own. */
          var firstBlock = Math.max(headH + Math.min(2, capLines.length) * LH + (capLines.length ? 0 : bandH), d.h + 4);
          if (current !== g.key) {
            need(firstBlock + 30);
            rule(y + 4, M, R, LINE, 0.6); y -= 16;
            sectionLabel(g.label, M, y); y -= 18;
            current = g.key;
          } else need(firstBlock + 8);
          var top = y;
          if (img) pg.page.drawImage(img, { x: M, y: top - d.h, width: d.w, height: d.h });
          else thumbBox(null, M, top, thumbW, d.h, 'No thumbnail');
          var ty = top - 8;
          sectionLabel(ctx, tx, ty); ty -= 15;
          titleLines.forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, 12, INK); ty -= 15; });
          ty -= 4;
          var pageOfTop = pg;
          // The caption, continuing over the page where it must.
          for (var i = 0; i < capLines.length; i++) {
            var ln = capLines[i];
            if (ty - LH < FLOOR) {
              newPage(pg.section);
              ty = y;
              sectionLabel('Continued  ·  ' + clip(p.title || 'Untitled post', tw - 60, 7.5, reg) + '  ·  ' + g.label, tx, ty, MUTE); ty -= 16;
            }
            if (ln === null) { ty -= LH * 0.55; continue; }
            sh.draw(pg.page, ln, tx, ty, 10, INK);
            ty -= LH;
          }
          if (!capLines.length) { text('No caption recorded.', tx, ty, 9, book, MUTE); ty -= 14; }
          ty -= 4;
          // Metrics as a compact band under the caption.
          if (pairs.length) {
            if (ty - bandH < FLOOR) { newPage(pg.section); ty = y; sectionLabel('Continued  ·  ' + clip(p.title || 'Untitled post', tw - 60, 7.5, reg), tx, ty, MUTE); ty -= 16; }
            rule(ty + 2, tx, R, HAIR, 0.5); ty -= 14;
            var cellW = Math.min(88, tw / pairs.length);
            pairs.forEach(function (m, k) {
              var cx = tx + k * cellW;
              text(m.value, cx, ty, 11, m.na ? book : med, m.na ? MUTE : INK);
              sectionLabel(m.label, cx, ty - 11, MUTE);
            });
            ty -= 24;
          }
          if (urlLines.length) { urlLines.forEach(function (ln) { if (ty - 12 < FLOOR) { newPage(pg.section); ty = y; } sh.draw(pg.page, ln, tx, ty, 8.5, MUTE); ty -= 12; }); ty -= 2; }
          if (obsLines.length) {
            if (ty - 14 - obsLines.length * 13 < FLOOR) { newPage(pg.section); ty = y; }
            sectionLabel('Observation', tx, ty); ty -= 13;
            obsLines.forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, 9.5, INK); ty -= 13; });
          }
          var bottom = (pg === pageOfTop) ? Math.min(ty, top - d.h - 4) : ty;
          y = bottom - 10;
          if (y - 20 > FLOOR) { rule(y + 2, M, R, HAIR, 0.5); y -= 14; }
        });
      });
    })();

    // ------------------------------------------------------- Methodology
    (function method() {
      newPage('Methodology and data notes');
      pageTitle('Methodology and data notes', periodW);
      var lines = [];
      lines.push('Figures are the platforms’ own, read from Meta Business Suite, TikTok and each platform’s analytics for the posts published in ' + periodW + ', and entered into the ADspace Digital Portal by the account team.');
      lines.push('A metric printed as 0 was measured and was zero. A metric printed as Not available was not provided by the platform for that post, and is left out of every total it would otherwise be part of.');
      lines.push('Views, reach and impressions are kept apart and never added together: each platform is totalled on the metric it reports, named on its own page.');
      mdl.groups.forEach(function (g) {
        var parts = [];
        if (g.volume) parts.push(METRIC_WORD[g.volume].toLowerCase());
        if (g.engKey) parts.push(METRIC_WORD[g.engKey].toLowerCase());
        var s = g.label + ': ' + (parts.length ? parts.join(' and ') + ' per post' : 'no post metrics recorded') +
          (g.basis ? '. Engagement rate is ' + (g.engKey ? METRIC_WORD[g.engKey].toLowerCase() : 'engagements') + ' divided by ' + (g.basis === 'followers' ? 'followers at the end of the period' : 'total ' + g.basis) + '.' : '. No engagement-rate basis was set.') +
          (g.notes ? ' ' + g.notes : '');
        lines.push(s);
        g.accounts.forEach(function (a) {
          if (num(a.growth_override) !== null) lines.push((PLATFORM_WORD[a.platform] || a.platform) + ' follower growth of ' + signed(a.growth_override) + ' is a recorded figure' + (words(a.growth_reason).trim() ? ': ' + words(a.growth_reason).trim() : '.') );
        });
      });
      lines.push('Best-performing posts are ranked by ' + METRIC_WORD[mdl.rank].toLowerCase() + '; where a platform ranks on a different metric its own page says so. The reasons a post stood out are the account team’s observations, not generated.');
      lines.push((isDraft ? 'This is a draft generated for internal review on ' : 'Version ' + (rep.version_no || 1) + ' of this report was issued on ') + (stampWord(rep.generated_at) || longDate(new Date().toISOString().slice(0, 10))) + (rep.generated_by_name ? ' by ' + rep.generated_by_name : '') + '. Each issued version is kept with the data it was drawn from.');
      lines.forEach(function (s) { para(s, M, CW, 10, 14.5, book, INK, true); y -= 8; });
    })();

    // ------------------------------------------------------- Heads and feet
    /* The rate card's furniture on every page, the cover included. The head
       label names whose report this is, where the rate card names its
       audience; the italic line under PRIVATE & CONFIDENTIAL is the report's
       reference, where the rate card prints its version. Slate Book Italic is
       not among the portal's fonts, so the line is Slate Book slanted. */
    var n = pages.length;
    var label = String(rep.client_name || '').toUpperCase();
    var refLine = [rep.title || 'Social Media Accounts Report', periodW,
      isDraft ? 'Draft for internal review, generated ' + (stampWord(rep.generated_at) || longDate(new Date().toISOString().slice(0, 10)))
              : 'Version ' + (rep.version_no || 1) + ', issued ' + stampWord(rep.generated_at)].filter(Boolean).join('  ·  ');
    var slant = function (s, x, yy, size, f) { pg.page.drawText(String(s), { x: x, y: yy, size: size, font: f, color: INK, ySkew: PDF.degrees(12) }); };
    pages.forEach(function (p, i) {
      pg = p;
      text('ADspace', M, HEAD_Y, 16.08, mark, INK);
      if (label) tline(clip(label, R - LABEL_X, 7.92, med), LABEL_X, 782.6, 7.92, med, INK);
      text('PRIVATE & CONFIDENTIAL', M, 49, 7.92, med, INK);
      /* A title typed in Chinese goes through the shaper upright; Latin is
         slanted, as the rate card's reference line is set. */
      if (/^[\u0000-\u024f\u2000-\u206f]*$/.test(refLine)) slant(refLine, M, 30.7, 7.92, book);
      else tline(refLine, M, 30.7, 7.92, book, INK, CW);
      right('Page ' + (i + 1) + ' of ' + n, R, 47, 7.92, book, INK);
    });
    return Promise.resolve(n);

    // ---- Components -----------------------------------------------------------
    /* Five figures across the column, nothing boxed. */
    function band(cells) {
      need(70);
      var cw = CW / cells.length;
      rule(y + 6, M, R, LINE, 0.6);
      y -= 26;
      cells.forEach(function (c, i) {
        var x = M + i * cw;
        var v = String(c.value);
        var size = v.length > 9 ? 16 : (v.length > 7 ? 19 : 22);
        var na = v === 'Not available';
        text(na ? 'Not available' : v, x, y, na ? 11 : size, na ? book : med, na ? MUTE : INK);
        var ll = sh.linesOf(String(c.label || ''), cw - 10, 8.5, reg).slice(0, 2);
        var ly = y - 15;
        ll.forEach(function (ln) { sh.draw(pg.page, ln, x, ly, 8.5, MUTE); ly -= 11; });
        if (c.note) sh.linesOf(c.note, cw - 10, 8, book).slice(0, 2).forEach(function (ln) { sh.draw(pg.page, ln, x, ly, 8, MUTE); ly -= 10; });
      });
      y -= 48;
      rule(y + 6, M, R, LINE, 0.6);
      y -= 10;
    }
    /* Bars by posting date across the period; several posts on one day sit
       side by side. The tallest bar carries its title and value. */
    function chartByDate(x, top, w, h, posts, groups) {
      var start = dateOf(rep.period_start), end = dateOf(rep.period_end);
      var dated = posts.filter(function (p) { return dateOf(p.posted_on); });
      if (!dated.length) { text('No dated posts.', x, top - 12, 9.5, book, MUTE); return; }
      if (!start || !end) { start = dateOf(dated[0].posted_on); end = dateOf(dated[dated.length - 1].posted_on); }
      var days = Math.max(1, Math.round((end - start) / 864e5) + 1);
      var valueOf = function (p) { var g = p._group; return g && g.volume ? num(p[g.volume]) : null; };
      var maxV = 0;
      dated.forEach(function (p) { var v = valueOf(p); if (v !== null && v > maxV) maxV = v; });
      if (!maxV) { text('No values to chart.', x, top - 12, 9.5, book, MUTE); return; }
      var axisW = 40, plotX = x + axisW, plotW = w - axisW, base = top - h + 16, plotH = h - 30;
      // Three gridlines with round labels.
      var step = niceStep(maxV / 3);
      for (var v = 0; v <= maxV + step * 0.001; v += step) {
        var yy = base + plotH * (v / (step * Math.ceil(maxV / step)));
        pg.page.drawLine({ start: { x: plotX, y: yy }, end: { x: x + w, y: yy }, thickness: 0.4, color: HAIR });
        right(v.toLocaleString('en-GB'), plotX - 6, yy - 3, 7.5, book, MUTE);
      }
      var scaleMax = step * Math.ceil(maxV / step);
      var slot = plotW / days;
      var byDay = {};
      dated.forEach(function (p) { var k = Math.round((dateOf(p.posted_on) - start) / 864e5); (byDay[k] = byDay[k] || []).push(p); });
      var tones = {};
      groups.forEach(function (g, i) { tones[g.key] = i === 0 ? ACCENT : (i === 1 ? PDF.rgb(0.33, 0.31, 0.28) : mix(PDF, ACCENT, 0.5)); });
      var peak = null;
      Object.keys(byDay).forEach(function (k) {
        var list = byDay[k], gap = 1.2;
        var bw = Math.max(1.5, (slot - 2 - gap * (list.length - 1)) / list.length);
        list.forEach(function (p, j) {
          var v = valueOf(p); if (v === null) return;
          var bx = plotX + Number(k) * slot + 1 + j * (bw + gap);
          var bh = Math.max(0.8, plotH * (v / scaleMax));
          rect(bx, base, bw, bh, tones[p._group.key] || ACCENT);
          if (v === maxV && !peak) peak = { x: bx + bw / 2, y: base + bh, p: p };
        });
      });
      // Month axis: the 1st, then every fifth day.
      for (var dd = 0; dd < days; dd++) {
        var d = new Date(start.getTime() + dd * 864e5);
        if (dd === 0 || (dd + 1) % 5 === 0 || dd === days - 1) {
          text(String(d.getDate()) + (dd === 0 ? ' ' + MON3[d.getMonth()] : ''), plotX + dd * slot + 1, base - 11, 7.5, book, MUTE);
        }
      }
      pg.page.drawLine({ start: { x: plotX, y: base }, end: { x: x + w, y: base }, thickness: 0.6, color: LINE });
      if (peak) {
        var label = clip((peak.p.title || 'Untitled post') + ', ' + fmt(valueOf(peak.p)), 200, 8, reg);
        var lw = width(label, 8, reg);
        var lx = Math.min(Math.max(peak.x - lw / 2, plotX), x + w - lw);
        text(label, lx, peak.y + 5, 8, reg, INK);
      }
      // Legend, top right of the plot, where more than one group is drawn.
      if (groups.length > 1) {
        var lxx = x + w;
        groups.slice().reverse().forEach(function (g) {
          var lab = g.label, lw2 = width(lab, 7.5, book);
          lxx -= lw2;
          text(lab, lxx, top - 2, 7.5, book, MUTE);
          lxx -= 12;
          rect(lxx, top - 1, 8, 6, tones[g.key]);
          lxx -= 14;
        });
      }
    }
    function niceStep(raw) {
      var p = Math.pow(10, Math.floor(Math.log10(raw || 1)));
      var m = raw / p;
      var s = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10;
      return s * p;
    }
    /* Horizontal bars, label left, value right. */
    function hbars(rows) {
      var maxV = rows.reduce(function (m, r) { return Math.max(m, r.value); }, 0) || 1;
      var labelW = 200, valW = 50, bx = M + labelW + 10, bw = CW - labelW - 10 - valW;
      rows.forEach(function (r) {
        need(18);
        tline(clip(r.label, labelW - 4, 9, book), M, y, 9, book, INK);
        var len = Math.max(0.8, bw * (r.value / maxV));
        rect(bx, y - 1.5, len, 8, ACCENT, r.value === maxV ? 1 : 0.55);
        right(fmt(r.value), R, y, 9, reg, INK);
        y -= 16;
      });
    }
  }

  function fileName(snap, versionNo) {
    var rep = (snap && snap.report) || {};
    var slug = function (s) { return String(s || '').normalize('NFKD').replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-'); };
    var d = dateOf(rep.period_start);
    var when = d ? MON3[d.getMonth()].slice(0, 3) + '-' + d.getFullYear() : '';
    return [slug(rep.client_name), 'Social-Media-Report', when, 'v' + (versionNo || rep.version_no || 1)].filter(Boolean).join('-') + '.pdf';
  }

  window.ADspaceSmReport = {
    render: render, model: model, fileName: fileName, periodWord: periodWord,
    engOf: engOf, growthOf: growthOf, fmt: fmt, PLATFORM_WORD: PLATFORM_WORD, TYPE_WORD: TYPE_WORD, METRIC_WORD: METRIC_WORD, METRICS: METRICS
  };
})();
