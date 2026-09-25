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
  /* 2026-09-25, second revision: the user found the 54pt margin left too
     much white paper, and asked for the margins, the type, the line heights
     and the tables to follow the golden ratio. So every size and every space
     on the page is one step of one scale: 10pt (the body) multiplied by
     √φ, step by step, so that two steps apart is exactly φ.

       S(-2) 6.18  S(-1) 7.86  S(0) 10  S(1) 12.72  S(2) 16.18
       S(3) 20.58  S(4) 26.18  S(5) 33.30  S(6) 42.36

     The margin is S(5), 33.3pt (11.7mm), which widens the text column from
     487pt to 529pt. The head, the foot and the ink stay the rate card's. */
  var W = 595.28, H = 841.89;
  var PHI = 1.6180339887;
  var S = function (k) { return 10 * Math.pow(PHI, k / 2); };
  var M = S(5);                 // 33.3pt on every side
  var R = W - M, CW = R - M;    // the text column: 528.7pt
  var HEAD_Y = H - M - 11.6;    // the wordmark's baseline: its cap height under the top margin
  var TOP = HEAD_Y - S(5);      // the page title's baseline, one margin under the head
  var FOOT_Y = M + S(1);        // PRIVATE & CONFIDENTIAL and the page count
  var FLOOR = FOOT_Y + S(4);    // nothing draws below this; the foot is under it
  // The type roles, each a step of the scale.
  var TY = {
    cover: S(5), coverSub: S(3), coverMeta: S(1),
    title: S(3), block: S(1), lead: S(1), body: S(0), cell: S(0), small: S(-1),
    figure: S(3)
  };
  // The spaces between things, each a step of the scale.
  var SP = { tight: S(-2), line: S(-1), under: S(2), block: S(4) };

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
        if (/[\/\-?&=_.,;:!]/.test(ch(cp)) && i + 1 < list.length && list[i + 1] !== 0x20 &&
            !(/[.,]/.test(ch(cp)) && list[i + 1] >= 0x30 && list[i + 1] <= 0x39)) {   // never inside 4,381 or 0.62
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
          pdf.setTitle(String(rep.client_name || '') + ' ' + String(rep.title || 'Social Media Report') + ' ' + periodWord(rep.period_start, rep.period_end));
          pdf.setAuthor(CFG.agencyName || 'ADspace');
          pdf.setSubject('Social media report');
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
    /* Monochrome, on the rate card's own values: one ink for every word and
       every mark that carries a value, the rate card's two table greys for
       structure, and two lighter greys for the marks that are only context.
       Nothing on the page is coloured. */
    var g = function (v) { return PDF.rgb(v, v, v); };
    var INK = g(0.251);            // #404040, the rate card's one ink
    var SOFT = g(0.40);            // secondary text: captions, dates
    var MUTE = g(0.45);            // axis labels, notes
    var FILL = g(0.949);           // #f2f2f2: header row, label column, cell edges
    var FILL2 = g(0.851);          // #d9d9d9: a group heading cell
    var EDGE = g(0.949);           // the rate card draws its grid in the header grey
    var DATA2 = g(0.651);          // #a6a6a6: a second series, the ordinary bars
    var DATA3 = g(0.80);           // #cccccc: a third series
    var PAPER = g(1);
    var SERIES = [INK, DATA2, DATA3];
    var isDraft = rep.status !== 'final' || opts.proof;
    var periodW = periodWord(rep.period_start, rep.period_end);

    var pages = [];
    var pg = null, y = 0;
    var text = function (s, x, yy, size, f, color) { pg.page.drawText(String(s == null ? '' : s), { x: x, y: yy, size: size || 10.5, font: f || book, color: color || INK }); };
    var width = function (s, size, f) { return (f || book).widthOfTextAtSize(String(s == null ? '' : s), size || 10.5); };
    var right = function (s, xr, yy, size, f, color) { text(s, xr - width(s, size, f), yy, size, f, color); };
    var center = function (s, xc, yy, size, f, color) { text(s, xc - width(s, size, f) / 2, yy, size, f, color); };
    var rect = function (x, yy, w, h, color) { pg.page.drawRectangle({ x: x, y: yy, width: w, height: h, color: color, borderWidth: 0 }); };
    var frame = function (x, yy, w, h, color, thick) { pg.page.drawRectangle({ x: x, y: yy, width: w, height: h, borderColor: color || EDGE, borderWidth: thick || 0.48 }); };
    var hline = function (yy, x1, x2, color, thick, dash) {
      var o = { start: { x: x1, y: yy }, end: { x: x2, y: yy }, thickness: thick || 0.48, color: color || EDGE };
      if (dash) o.dashArray = dash;
      pg.page.drawLine(o);
    };
    var tline = function (s, x, yy, size, f, color, maxW) {
      var line = sh.linesOf(String(s == null ? '' : s), maxW || 1e6, size, f || book)[0] || [];
      sh.draw(pg.page, line, x, yy, size, color || INK);
      return sh.lineWidth(line, size);
    };
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
    var room = function () { return y - FLOOR; };
    var need = function (h) { if (y - h < FLOOR) { newPage(pg.section); return true; } return false; };
    var para = function (s, x, w, size, lh, f, color) {
      sh.linesOf(s, w, size, f || book).forEach(function (ln) { need(lh); sh.draw(pg.page, ln, x, y, size, color || INK); y -= lh; });
    };
    /* The page title in Slate Regular at S(3), the first block S(2) under
       it. Every section starts a page of its own, so a report with little in
       it is shorter by whole sections and never squeezed onto half a page. */
    var pageTitle = function (s) { tline(s, M, y, TY.title, reg, INK, CW); y -= TY.title * 0.25 + SP.under; };
    /* A block's title in Slate Regular at S(1), the block S(-1) under it.
       `y` is always the top edge of what comes next, so the space between
       two blocks is exactly S(4) whatever they are, and under a title S(2).
       `keep` is the height of what must follow it on the same page. */
    var blockTitle = function (s, keep) {
      need(TY.block + SP.line + (keep || 40));
      y -= TY.block * 0.72;
      tline(s, M, y, TY.block, reg, INK, CW); y -= TY.block * 0.28 + SP.line;
    };
    var gap = function (h) { y -= h; };
    var BLOCK = SP.block;
    /* Lines of prose from the top edge `y`: the first baseline its cap height
       down, each next one a φ line (S(2)) under it, and the block after it
       S(4) under the last line's descent. */
    var proseBlock = function (lines) {
      var last = null;
      lines.forEach(function (l) {
        if (l.gap) { if (last !== null) y -= l.gap; return; }
        if (last === null) y -= l.size * 0.72; else y -= S(2);
        need(S(2)); sh.draw(pg.page, l.ln, M, y, l.size, INK); last = l;
      });
      if (last) y -= last.size * 0.28 + BLOCK;
    };

    var groupWord = function (p) { return p._group ? p._group.label : ''; };
    var typeWord = function (p) { return TYPE_WORD[p.content_type] || (p.content_type ? String(p.content_type) : ''); };
    var shortDay = function (s) { var d = dateOf(s); return d ? d.getDate() + ' ' + MON3[d.getMonth()] : ''; };
    /* A post without a title is named by what it is and when it went out, so
       a ranking reads as a list of posts and not as "Untitled post" five
       times. Two on one day are numbered in posting order. */
    var sameDay = {};
    mdl.posts.forEach(function (p) { var k = (p._group ? p._group.key : '') + '|' + p.posted_on; (sameDay[k] = sameDay[k] || []).push(p); });
    var postName = function (p) {
      if (words(p.title).trim()) return words(p.title).trim();
      var k = (p._group ? p._group.key : '') + '|' + p.posted_on;
      var list = sameDay[k] || [p];
      var base = (typeWord(p) || 'Post') + ', ' + shortDay(p.posted_on);
      return list.length > 1 ? base + ' (' + (list.indexOf(p) + 1) + ')' : base;
    };
    var volOf = function (p) { var gg = p._group; return gg && gg.volume ? num(p[gg.volume]) : null; };
    var erOf = function (p) {
      var gg = p._group, e = engOf(p);
      if (!gg || !gg.basis || e === null) return null;
      if (gg.basis === 'followers') {
        var f = sumOf(gg.accounts, function (a) { return num(a.followers_end); });
        return f ? e / f : null;
      }
      var d = num(p[gg.basis]);
      return d ? e / d : null;
    };
    var volWord = function (gg) { return gg && gg.volume ? METRIC_WORD[gg.volume] : 'Views'; };
    var engWord = function (gg) { return gg && gg.engKey ? METRIC_WORD[gg.engKey] : 'Engagements'; };

    // ---------------------------------------------------------------- Tables
    /* The rate card's table, the one structure this document draws its data
       in: a header row in #f2f2f2, white rows, every cell edged 0.48pt in the
       same grey, the text vertically centred with 5pt at either side, and a
       label column in #f2f2f2 where a table reads by row. A row that no
       longer fits starts a new page with the header drawn again; a row of
       plain text taller than a page is split between pages. */
    /* The cell: 10pt text on a √φ line (12.72), S(-2) at either side, and a
       row of S(3) at least, so the text sits in the row with the same space
       above and below it. */
    var T = { size: TY.cell, lh: S(1), padX: S(-2), padY: (S(3) - S(1)) / 2, minH: S(3) };
    function cellLines(c, w) {
      if (c == null) return [];
      if (typeof c === 'string' || typeof c === 'number') c = { t: String(c) };
      if (c.fn) return null;
      var f = c.f || book, size = c.size || T.size;
      var out = [];
      String(c.t == null ? '' : c.t).split('\n').forEach(function (part, i) {
        if (c.items) return;
        sh.linesOf(part, w - T.padX * 2, size, f).forEach(function (ln) { out.push({ ln: ln, f: f, size: size }); });
      });
      if (c.items) {
        /* A numbered list inside a cell: the number in Slate Medium, the item
           hanging S(1) in, the row's own padding between items. */
        c.items.forEach(function (it, i) {
          var ls = sh.linesOf(it, w - T.padX * 2 - S(1), size, f);
          ls.forEach(function (ln, k) { out.push({ ln: ln, f: f, size: size, num: k === 0 ? String(i + 1) : null, indent: S(1) }); });
          if (i < c.items.length - 1) out.push({ gap: T.padY });
        });
      }
      return out;
    }
    function linesH(ls) { return ls.reduce(function (t, l) { return t + (l.gap ? l.gap : T.lh); }, 0); }
    function drawLines(ls, x, top, w, h, c) {
      var total = linesH(ls);
      /* Lists read from the top of their cell, so two columns of points start
         on one line; everything else is centred, as the rate card sets it. */
      var off = c && c.top ? T.padY : (h - total) / 2;
      var yy = top - off - (T.lh - T.size) / 2 - T.size * 0.8;
      var align = (c && c.align) || 'left';
      ls.forEach(function (l) {
        if (l.gap) { yy -= l.gap; return; }
        var lw = sh.lineWidth(l.ln, l.size);
        var lx = x + T.padX + (l.indent || 0);
        if (align === 'center') lx = x + (w - lw) / 2;
        else if (align === 'right') lx = x + w - T.padX - lw;
        if (l.num) text(l.num, x + T.padX, yy, l.size, med, INK);
        sh.draw(pg.page, l.ln, lx, yy, l.size, (c && c.color) || INK);
        yy -= T.lh;
      });
    }
    function norm(c) { return (typeof c === 'string' || typeof c === 'number') ? { t: String(c) } : (c || { t: '' }); }
    /* cols: [{ w, align }] (widths are fractions of the column when they add
       to 1 or less, else points); head: labels or null; rows: [{ cells,
       fill, minH }]. A cell is text, { t, f, size, align, color, fill },
       { items: [...] } or { fn(x, top, w, h), h }. */
    function table(cols, head, rows, o) {
      o = o || {};
      var tw = o.width || CW, x0 = o.x == null ? M : o.x;
      var tot = cols.reduce(function (t, c) { return t + c.w; }, 0);
      var ws = cols.map(function (c) { return c.w * (tw / tot); });
      var xs = []; ws.reduce(function (acc, w, i) { xs[i] = acc; return acc + w; }, x0);
      var headH = 0;
      var drawHead = function () {
        if (!head) return;
        var hl = head.map(function (hc, i) { return cellLines({ t: norm(hc).t, f: reg }, ws[i]); });
        headH = Math.max(T.minH, Math.max.apply(null, hl.map(linesH)) + T.padY * 2);
        head.forEach(function (hc, i) {
          rect(xs[i], y - headH, ws[i], headH, norm(hc).fill || FILL);
          frame(xs[i], y - headH, ws[i], headH);
          drawLines(hl[i], xs[i], y, ws[i], headH, { align: norm(hc).align || cols[i].align || 'center' });
        });
        y -= headH;
      };
      var headNeed = function () {
        if (!head) return 0;
        var hl = head.map(function (hc, i) { return cellLines({ t: norm(hc).t, f: reg }, ws[i]); });
        return Math.max(T.minH, Math.max.apply(null, hl.map(linesH)) + T.padY * 2);
      };
      var first = true;
      rows.forEach(function (row, ri) {
        var cells = row.cells.map(norm);
        var ls = cells.map(function (c, i) { return c.fn ? null : cellLines(c, ws[i]); });
        var contentH = Math.max.apply(null, cells.map(function (c, i) { return c.fn ? (c.h || 0) : linesH(ls[i]) + T.padY * 2; }));
        var h = Math.max(row.minH || T.minH, contentH);
        var pageSpace = TOP - FLOOR - headNeed();
        if (first) { need(headNeed() + (row.split ? Math.min(h, T.lh * 3 + T.padY * 2) : Math.min(h, pageSpace))); drawHead(); first = false; }
        else if (y - h < FLOOR && h <= pageSpace) { newPage(pg.section); drawHead(); }
        if (h > pageSpace || (y - h < FLOOR && row.split)) {
          /* Too tall for any page, or allowed to break: the text cells are
             split line by line, and a label column repeats with (cont.). */
          var cur = ls.map(function () { return 0; });
          var part0 = true;
          var remaining = function () { return ls.some(function (l, i) { return l && cur[i] < l.length; }); };
          while (remaining()) {
            var avail = y - FLOOR - T.padY * 2;
            if (avail < T.lh * 2) { newPage(pg.section); drawHead(); continue; }
            var part = ls.map(function (l, i) {
              if (!l) return [];
              if (o.labelCol && i === 0) {
                var lab = part0 ? l : cellLines({ t: cells[0].t + ' (cont.)', f: cells[0].f }, ws[0]);
                cur[0] = l.length;
                return lab;
              }
              var out = [], used = 0;
              while (cur[i] < l.length && used + (l[cur[i]].gap || T.lh) <= avail) { out.push(l[cur[i]]); used += l[cur[i]].gap || T.lh; cur[i]++; }
              while (out.length && out[0].gap) out.shift();
              while (out.length && out[out.length - 1].gap) out.pop();
              return out;
            });
            var ph = Math.max(T.minH, Math.max.apply(null, part.map(linesH)) + T.padY * 2);
            cells.forEach(function (c, i) {
              rect(xs[i], y - ph, ws[i], ph, c.fill || row.fill || (o.labelCol && i === 0 ? FILL : PAPER));
              frame(xs[i], y - ph, ws[i], ph);
              drawLines(part[i], xs[i], y, ws[i], ph, { align: c.align || cols[i].align || 'center', color: c.color, top: !!c.items });
            });
            y -= ph;
            part0 = false;
            if (remaining()) { newPage(pg.section); drawHead(); }
          }
          return;
        }
        cells.forEach(function (c, i) {
          rect(xs[i], y - h, ws[i], h, c.fill || row.fill || (o.labelCol && i === 0 ? FILL : PAPER));
          frame(xs[i], y - h, ws[i], h);
          if (c.fn) c.fn(xs[i], y, ws[i], h);
          else drawLines(ls[i], xs[i], y, ws[i], h, { align: c.align || cols[i].align || 'center', color: c.color, top: !!c.items });
        });
        y -= h;
      });
      if (first && head) { need(headNeed()); drawHead(); }
    }

    /* A thumbnail in a fixed frame, so a column of them is one column: the
       frame is the header grey and the image fits inside it whole. */
    function thumbIn(p, x, top, w, h) {
      rect(x, top - h, w, h, FILL);
      var img = thumbs[p.id];
      if (!img) return;
      var s = Math.min(w / img.width, h / img.height);
      var dw = img.width * s, dh = img.height * s;
      pg.page.drawImage(img, { x: x + (w - dw) / 2, y: top - h + (h - dh) / 2, width: dw, height: dh });
    }

    /* The figures that head a page: the rate card's table, a label row over a
       value row, the value in Slate Medium. */
    function figures(cells) {
      var cols = cells.map(function () { return { w: 1 / cells.length, align: 'center' }; });
      table(cols, cells.map(function (c) { return c.label; }), [{
        minH: S(5),
        cells: cells.map(function (c) {
          var na = c.value === 'Not available';
          return { fn: function (x, top, w, h) {
            var size = na ? TY.body : (String(c.value).length > 8 ? S(2) : TY.figure);
            center(c.value, x + w / 2, top - h / 2 - size * 0.34, size, na ? book : med, na ? MUTE : INK);
          }, h: S(5) };
        })
      }]);
    }

    function niceStep(raw) {
      var p = Math.pow(10, Math.floor(Math.log10(raw || 1)));
      var m = raw / p;
      var s = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10;
      return s * p;
    }
    /* The value axis every chart shares: three or four round gridlines in the
       edge grey, labels in the mute ink at their left. */
    function axis(plotX, plotW, base, plotH, maxV) {
      var step = niceStep(maxV / 3);
      var scaleMax = step * Math.ceil(maxV / step);
      for (var v = 0; v <= scaleMax + step * 0.001; v += step) {
        var yy = base + plotH * (v / scaleMax);
        hline(yy, plotX, plotX + plotW, v === 0 ? FILL2 : FILL, v === 0 ? 0.6 : 0.48);
        right(v.toLocaleString('en-GB'), plotX - S(-2), yy - 2.7, TY.small, book, MUTE);
      }
      return scaleMax;
    }
    function legend(items, x, yy) {
      var lx = x;
      items.forEach(function (it) {
        rect(lx, yy - 1, S(-1), S(-1), it.color);
        text(it.label, lx + S(1), yy, TY.small, book, INK);
        lx += S(1) + width(it.label, TY.small, book) + S(2);
      });
    }

    /* Views by week: the period in seven-day weeks, one column a week, the
       platforms stacked in the fixed order the report lists them, a 1pt paper
       gap between segments, and the week's total over its column. The job is
       change over time and share of it, so the weeks are the axis and not the
       posts: thirty bars of one post each read as noise. */
    function weeklyChart(groups, h) {
      var start = dateOf(rep.period_start), end = dateOf(rep.period_end);
      var posts = mdl.posts.filter(function (p) { return p._group && dateOf(p.posted_on) && volOf(p) !== null; });
      if (!posts.length) { text('No data.', M, y - 12, TY.body, book, MUTE); y -= 20; return; }
      if (!start || !end) { start = dateOf(posts[0].posted_on); end = dateOf(posts[posts.length - 1].posted_on); }
      var days = Math.round((end - start) / 864e5) + 1;
      var weeks = [];
      for (var d0 = 0; d0 < days; d0 += 7) {
        var a = new Date(start.getTime() + d0 * 864e5), b = new Date(start.getTime() + Math.min(days - 1, d0 + 6) * 864e5);
        weeks.push({ a: a, b: b, by: {}, total: 0,
          label: a.getDate() + (a.getMonth() !== b.getMonth() ? ' ' + MON3[a.getMonth()] : '') + ' to ' + b.getDate() + ' ' + MON3[b.getMonth()] });
      }
      posts.forEach(function (p) {
        var k = Math.floor((dateOf(p.posted_on) - start) / 864e5 / 7);
        var wk = weeks[Math.max(0, Math.min(weeks.length - 1, k))];
        wk.by[p._group.key] = (wk.by[p._group.key] || 0) + volOf(p);
        wk.total += volOf(p);
      });
      var maxV = weeks.reduce(function (m, w) { return Math.max(m, w.total); }, 0) || 1;
      need(h + 30);
      var top = y;
      if (groups.length > 1) { legend(groups.map(function (gg, i) { return { label: gg.label, color: SERIES[i] || DATA3 }; }), M, top - 6); }
      var axisW = S(6), plotX = M + axisW, plotW = CW - axisW;
      var base = top - h + 14, plotH = h - 14 - (groups.length > 1 ? 34 : 22);
      var scaleMax = axis(plotX, plotW, base, plotH, maxV);
      var slot = plotW / weeks.length, bw = Math.min(56, slot * 0.46);
      weeks.forEach(function (wk, i) {
        var cx = plotX + slot * i + slot / 2, yy = base;
        groups.forEach(function (gg, gi) {
          var v = wk.by[gg.key] || 0; if (!v) return;
          var bh = plotH * (v / scaleMax);
          rect(cx - bw / 2, yy, bw, Math.max(0.8, bh - (gi < groups.length - 1 ? 1 : 0)), SERIES[gi] || DATA3);
          yy += bh;
        });
        center(fmt(wk.total), cx, base + plotH * (wk.total / scaleMax) + 5, TY.small, med, INK);
        center(wk.label, cx, base - 11, TY.small, book, MUTE);
      });
      y = top - h - 4;
    }

    /* Views by post, in posting order: one column a post, the ordinary ones
       in the second grey and the month's best in ink with its value over it,
       and the average as a dashed ink line, so the page answers which posts
       beat the month's own mean without a sentence saying so. */
    function postsChart(gg, h) {
      var posts = gg.posts.filter(function (p) { return volOf(p) !== null; });
      if (!posts.length) return;
      var maxV = posts.reduce(function (m, p) { return Math.max(m, volOf(p)); }, 0) || 1;
      var avg = posts.reduce(function (t, p) { return t + volOf(p); }, 0) / posts.length;
      need(h + 10);
      var top = y;
      var axisW = S(6), plotX = M + axisW, plotW = CW - axisW;
      var base = top - h + 14, plotH = h - 14 - 16;
      var scaleMax = axis(plotX, plotW, base, plotH, maxV);
      var slot = plotW / posts.length, bw = Math.max(2, Math.min(22, slot - 3));
      var best = posts.reduce(function (b, p) { return volOf(p) > volOf(b) ? p : b; }, posts[0]);
      var lastDay = null, lastX = -1e9;
      posts.forEach(function (p, i) {
        var cx = plotX + slot * i + slot / 2;
        var bh = Math.max(0.8, plotH * (volOf(p) / scaleMax));
        rect(cx - bw / 2, base, bw, bh, p === best ? INK : DATA2);
        if (p === best) center(fmt(volOf(p)), cx, base + bh + 4, TY.small, med, INK);
        var day = shortDay(p.posted_on);
        var lw = width(day, TY.small, book);
        if (day !== lastDay && cx - lw / 2 > lastX + 3) { center(day, cx, base - 11, TY.small, book, MUTE); lastX = cx + lw / 2; }
        lastDay = day;
      });
      var ay = base + plotH * (avg / scaleMax);
      hline(ay, plotX, plotX + plotW, INK, 0.6, [2.5, 2]);
      var al = 'Average ' + fmt(Math.round(avg));
      var alw = width(al, TY.small, reg);
      rect(plotX + plotW - alw - 6, ay + 2, alw + 6, TY.small + 3, PAPER);
      right(al, plotX + plotW - 2, ay + 4, TY.small, reg, INK);
      y = top - h - 2;
    }

    // ---------------------------------------------------------------- Cover
    (function cover() {
      /* The rate card's cover, on the scale: the title stands in from the
         margin by S(9), 87pt, so it starts 120pt from the page's edge where
         the rate card starts its title at 126pt, with its baseline on the
         golden section of the page's height. The client and the month sit
         under it on the same indent, each line a step of the scale below the
         last. The head's wordmark stays on the margin, so the title reads as
         set in from the page and not as another line of the running head. */
      newPage('cover');
      var cx = M + S(9), cw = R - cx;
      var cy = H / PHI;
      var tlines = sh.linesOf(String(rep.title || 'Social Media Report'), cw, TY.cover, med);
      cy += (tlines.length - 1) * S(6);
      tlines.forEach(function (ln, i) { sh.draw(pg.page, ln, cx, cy, TY.cover, INK); if (i < tlines.length - 1) cy -= S(6); });
      cy -= S(6);
      sh.linesOf(String(rep.client_name || ''), cw, TY.coverSub, reg).forEach(function (ln) { sh.draw(pg.page, ln, cx, cy, TY.coverSub, INK); cy -= S(4); });
      tline(periodW, cx, cy, TY.coverMeta, book, INK, cw);
    })();

    var ins = rep.insights || {};

    // ------------------------------------------------------- Executive summary
    /* Each section below starts a page of its own and never shrinks to fit
       another onto it: a client with little to report gets fewer pages, not
       pages cut off halfway. A chart keeps one height wherever it is. */
    var CHART_WEEK = CW / (PHI * PHI);         // 201.9pt: the column over φ²
    var CHART_POSTS = CW / Math.pow(PHI, 2.5); // 158.8pt: half a step shorter
    (function summary() {
      newPage('Executive summary');
      pageTitle('Executive summary');
      var t = mdl.totals;
      var head = words(rep.headline).trim();
      var prose = [];
      if (head) sh.linesOf(head, CW, TY.lead, med).slice(0, 3).forEach(function (ln) { prose.push({ ln: ln, size: TY.lead, f: med }); });
      [rep.intro, ins.executive_summary].forEach(function (blk) {
        paragraphsOf(blk).filter(function (s) { return s.trim(); }).forEach(function (s) {
          if (prose.length) prose.push({ gap: SP.tight });
          sh.linesOf(s, CW, TY.body, book).forEach(function (ln) { prose.push({ ln: ln, size: TY.body }); });
        });
      });
      proseBlock(prose);
      figures([
        { label: 'Posts published', value: String(t.posts) },
        { label: 'Follower growth', value: signed(t.growth) },
        { label: t.volumeWords.length === 1 ? 'Total ' + t.volumeWords[0].toLowerCase() : 'Total views', value: fmt(t.views) },
        { label: t.engWords.length === 1 ? 'Total ' + t.engWords[0].toLowerCase() : 'Total engagements', value: fmt(t.eng) },
        { label: 'Engagement rate', value: pct(t.er) }
      ]);
      gap(BLOCK);
      // The split by platform, one row a platform: the table the figures total.
      if (mdl.groups.length > 1) {
        blockTitle('By platform', T.minH * (mdl.groups.length + 1));
        table([{ w: 0.26, align: 'left' }, { w: 0.1 }, { w: 0.16 }, { w: 0.14 }, { w: 0.16 }, { w: 0.18 }],
          [{ t: 'Platform', align: 'left' }, 'Posts', 'Follower growth', 'Views', 'Engagements', 'Engagement rate'],
          mdl.groups.map(function (gg) {
            return { cells: [gg.label, String(gg.posts.length), signed(gg.growth), fmt(gg.views), fmt(gg.eng), pct(gg.er)] };
          }), { labelCol: true });
        gap(BLOCK);
      }
      blockTitle((t.volumeWords.length === 1 ? t.volumeWords[0] : 'Views') + ' by week', CHART_WEEK);
      weeklyChart(mdl.groups, CHART_WEEK);
    })();

    // ------------------------------------------------ Findings and recommendations
    (function findings() {
      var obs = points(ins.performed_well);
      var acts = points(ins.next_actions);
      var more = [
        ['Performance drivers', ins.why_well],
        ['Underperformance', ins.underperformed],
        ['Opportunities', ins.opportunities],
        ['Improvements', ins.improvements]
      ].filter(function (r) { return words(r[1]).trim(); });
      if (!obs.length && words(ins.performed_well).trim()) more.unshift(['Highlights', ins.performed_well]);
      if (!obs.length && !acts.length && !more.length) return;
      newPage('Findings and recommendations');
      pageTitle('Findings and recommendations');
      if (obs.length || acts.length) {
        var one = [{ w: 0.5, align: 'left' }, { w: 0.5, align: 'left' }];
        var cells = [obs.length ? { items: obs } : { t: 'None.', color: MUTE }, acts.length ? { items: acts } : { t: 'None.', color: MUTE }];
        table(one, [{ t: 'Key findings', align: 'left' }, { t: 'Next steps', align: 'left' }], [{ cells: cells, split: true }]);
      }
      /* The rest of the team's remarks, never repeating the two lists above:
         Key findings is the Highlights field and Next steps the Action plan.
         The label in its grey column, the points numbered beside it. */
      if (more.length) {
        if (obs.length || acts.length) gap(BLOCK);
        blockTitle('Remarks and recommendations', T.minH * 2);
        table([{ w: 1 / (PHI * PHI), align: 'left' }, { w: 1 / PHI, align: 'left' }], null,
          more.map(function (r) { return { cells: [{ t: r[0], f: reg }, { items: points(r[1]) }], split: true }; }),
          { labelCol: true });
      }
    })();

    // ------------------------------------------------------- Platform pages
    mdl.groups.forEach(function (gg) {
      newPage(gg.label);
      pageTitle(gg.label);
      if (words(gg.summary).trim()) {
        proseBlock(sh.linesOf(gg.summary, CW, TY.lead, med).slice(0, 3).map(function (ln) { return { ln: ln, size: TY.lead }; }));
      }
      var cells = [{ label: 'Posts', value: String(gg.posts.length) }];
      gg.accounts.forEach(function (a) {
        cells.push({ label: (gg.accounts.length > 1 ? (PLATFORM_WORD[a.platform] || a.platform) + ' follower growth' : 'Follower growth'), value: signed(growthOf(a)) });
      });
      if (gg.volume) cells.push({ label: 'Total ' + METRIC_WORD[gg.volume].toLowerCase(), value: fmt(gg.views) });
      if (gg.engKey) cells.push({ label: 'Total ' + METRIC_WORD[gg.engKey].toLowerCase(), value: fmt(gg.eng) });
      cells.push({ label: 'Engagement rate', value: pct(gg.er) });
      figures(cells.slice(0, 6));
      gap(BLOCK);
      var movers = gg.accounts.filter(function (a) { return num(a.followers_start) !== null && num(a.followers_end) !== null; });
      if (movers.length) {
        blockTitle('Followers', T.minH * (movers.length + 1));
        table([{ w: 1 / (PHI * PHI) }, { w: 0.2 }, { w: 0.2 }, { w: 1 - 1 / (PHI * PHI) - 0.4 }].map(function (c, i) { if (!i) c.align = 'left'; return c; }),
          [{ t: 'Account', align: 'left' }, 'Start of period', 'End of period', 'Growth'],
          movers.map(function (a) { return { cells: [PLATFORM_WORD[a.platform] || a.platform, fmt(a.followers_start), fmt(a.followers_end), signed(growthOf(a))] }; }),
          { labelCol: true });
        gap(BLOCK);
      }
      if (gg.volume && gg.posts.some(function (p) { return volOf(p) !== null; })) {
        blockTitle(METRIC_WORD[gg.volume] + ' by post', CHART_POSTS);
        postsChart(gg, CHART_POSTS);
        gap(BLOCK);
      }
      // The five best, one table: the ranking and every figure it rests on.
      var ranked = gg.posts.filter(function (p) { return mdl.rankOf(p) !== null; })
        .sort(function (a, b) { return mdl.rankOf(b) - mdl.rankOf(a); }).slice(0, 5);
      if (ranked.length) {
        var topV = ranked.reduce(function (m, p) { return Math.max(m, volOf(p) || 0); }, 0) || 1;
        var ROWH = S(6);
        var TH = ROWH - S(-2) * 2, TW = TH * 0.8;
        blockTitle('Top ' + ranked.length + ' posts by ' + METRIC_WORD[mdl.rank].toLowerCase(), T.minH + ROWH * 2);
        table([{ w: 0.07 }, { w: 0.36 }, { w: 0.25 }, { w: 0.14 }, { w: 0.18 }].map(function (c, i) { if (i === 1) c.align = 'left'; return c; }),
          ['Rank', { t: 'Post', align: 'left' }, volWord(gg), engWord(gg), 'Engagement rate'],
          ranked.map(function (p, i) {
            return { minH: ROWH, cells: [
              { t: String(i + 1), f: med, align: 'center' },
              { fn: function (x, top, w, h) {
                thumbIn(p, x + T.padX, top - S(-2), TW, TH);
                var tx = x + T.padX + TW + S(-2), tw = w - T.padX * 2 - TW - S(-2);
                tline(clip(postName(p), tw, TY.body, med), tx, top - h / 2 + 2, TY.body, med, INK);
                tline([dayWord(p.posted_on), typeWord(p)].filter(Boolean).join('  ·  '), tx, top - h / 2 - S(1) + 2, TY.small, book, SOFT, tw);
              }, h: ROWH },
              { fn: function (x, top, w, h) {
                var v = volOf(p), vs = fmt(v), vw = S(6);
                var bx = x + T.padX, bwMax = w - T.padX * 2 - vw;
                rect(bx, top - h / 2 - 3, bwMax, S(-2), FILL);
                if (v !== null) rect(bx, top - h / 2 - 3, Math.max(0.8, bwMax * v / topV), S(-2), i === 0 ? INK : DATA2);
                right(vs, x + w - T.padX, top - h / 2 - 3.2, TY.body, i === 0 ? med : book, INK);
              }, h: ROWH },
              { t: fmt(engOf(p)), align: 'center' },
              { t: pct(erOf(p)), align: 'center' }
            ] };
          }));
        gap(BLOCK);
      }
      // What the month showed on this platform: three columns, the header row over them.
      var notes = [['Highlights', gg.worked], ['Areas for improvement', gg.improve], ['Recommendations', gg.actions]]
        .filter(function (b) { return words(b[1]).trim(); });
      if (notes.length) {
        var nc = notes.map(function () { return { w: 1 / notes.length, align: 'left' }; });
        var row = { cells: notes.map(function (b) { return { items: points(b[1]) }; }), split: true };
        var probeH = Math.max.apply(null, notes.map(function (b) { return linesH(cellLines({ items: points(b[1]) }, CW / notes.length)); })) + T.padY * 2;
        if (notes.length > 1 && probeH + T.minH + BLOCK <= TOP - FLOOR) {
          blockTitle('Remarks', T.minH + Math.min(probeH, 120));
          table(nc, notes.map(function (b) { return { t: b[0], align: 'left' }; }), [row]);
        } else {
          blockTitle('Remarks', 60);
          table([{ w: 1 / (PHI * PHI), align: 'left' }, { w: 1 / PHI, align: 'left' }], null,
            notes.map(function (b) { return { cells: [{ t: b[0], f: reg }, { items: points(b[1]) }], split: true }; }), { labelCol: true });
        }
      }
    });

    // ------------------------------------------------------- Top posts
    if (mdl.top.length) {
      newPage('Top posts');
      pageTitle('Top posts');
      var IMG_W = S(8), IMG_H = IMG_W * 1.25;   // 4:5, the portrait post
      var dw = CW / PHI - T.padX * 2;           // the details column: the golden major
      table([{ w: 0.1 }, { w: 1 - 1 / PHI - 0.1 }, { w: 1 / PHI, align: 'left' }],
        ['Rank', 'Post', { t: 'Details', align: 'left' }],
        mdl.top.map(function (p, i) {
          var gp = p._group;
          var cap = words(p.caption).trim() ? sh.linesOf(paragraphsOf(p.caption).filter(function (s) { return s.trim(); }).join(' '), dw, TY.small, book).slice(0, 3) : [];
          var notable = words(p.notable).trim() ? sh.linesOf(p.notable, dw, TY.body, book) : [];
          var metrics = [];
          if (gp && gp.volume) metrics.push([METRIC_WORD[gp.volume], fmt(p[gp.volume])]);
          metrics.push([engWord(gp), fmt(engOf(p))]);
          metrics.push(['Engagement rate', pct(erOf(p))]);
          // The details column, top to bottom, each offset a step of the scale.
          var NAME = S(2), META = NAME + S(2), BOX = META + S(-1), LABH = S(2), VALH = S(3);
          var AFTER = BOX + LABH + VALH + S(2);
          var textH = AFTER + (cap.length ? cap.length * S(0) + S(-2) : 0) + (notable.length ? S(0) + notable.length * S(1) : 0) + S(-2);
          var h = Math.max(IMG_H + S(-2) * 2, textH);
          return { minH: h, cells: [
            { t: String(i + 1), f: med, size: S(2), align: 'center' },
            { fn: function (x, top, w, hh) { thumbIn(p, x + (w - IMG_W) / 2, top - (hh - IMG_H) / 2, IMG_W, IMG_H); }, h: h },
            { fn: function (x, top, w, hh) {
              var tx = x + T.padX;
              tline(clip(postName(p), dw, TY.lead, med), tx, top - NAME, TY.lead, med, INK);
              tline([gp ? gp.label : '', dayWord(p.posted_on), typeWord(p)].filter(Boolean).join('  ·  '), tx, top - META, TY.small, book, SOFT, dw);
              // The figures as a small table of their own.
              var mw = Math.min(S(9), dw / metrics.length);
              var by = top - BOX;
              metrics.forEach(function (m, k) {
                var mx = tx + k * mw;
                rect(mx, by - LABH, mw, LABH, FILL); frame(mx, by - LABH, mw, LABH);
                center(m[0], mx + mw / 2, by - LABH / 2 - TY.small * 0.34, TY.small, reg, INK);
                frame(mx, by - LABH - VALH, mw, VALH);
                center(m[1], mx + mw / 2, by - LABH - VALH / 2 - TY.body * 0.34, TY.body, med, INK);
              });
              var ty = top - AFTER;
              cap.forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, TY.small, SOFT); ty -= S(0); });
              if (cap.length) ty -= S(-2);
              if (notable.length) {
                tline('Remarks', tx, ty, TY.small, reg, INK); ty -= S(1);
                notable.forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, TY.body, INK); ty -= S(1); });
              }
            }, h: h }
          ] };
        }));
    }

    // ------------------------------------------------------- Appendix
    /* All posts, one platform a page, so a platform's list always opens at
       the top of a page and closes on its own total. */
    (function appendix() {
      mdl.groups.forEach(function (gg) {
        if (!gg.posts.length) return;
        var name = 'Appendix: ' + gg.label;
        newPage(name);
        pageTitle(name);
        var hasType = gg.posts.some(function (p) { return typeWord(p); });
        var cols = [{ w: hasType ? 0.34 : 0.42, align: 'left' }, { w: 0.1 }];
        var head = [{ t: 'Post', align: 'left' }, 'Date'];
        if (hasType) { cols.push({ w: 0.1 }); head.push('Format'); }
        cols.push({ w: 0.12 }, { w: 0.16 }, { w: 0.18 });
        head.push(volWord(gg), engWord(gg), 'Engagement rate');
        var ROWH = S(7);
        var TH = ROWH - S(-2) * 2, TW = TH * 0.8;
        var rows = gg.posts.map(function (p) {
          var capTxt = paragraphsOf(p.caption).filter(function (s) { return s.trim(); }).join(' ');
          var remark = words(p.observation).trim();
          var cells = [{ fn: function (x, top, w, h) {
            thumbIn(p, x + T.padX, top - S(-2), TW, TH);
            var tx = x + T.padX + TW + S(-2), tw = w - T.padX * 2 - TW - S(-2);
            var lines = [];
            lines.push({ s: clip(postName(p), tw, TY.body, med), f: med, size: TY.body, c: INK });
            if (capTxt) sh.linesOf(capTxt, tw, TY.small, book).slice(0, remark ? 1 : 2).forEach(function (ln) { lines.push({ ln: ln, size: TY.small, c: SOFT }); });
            if (remark) lines.push({ s: clip('Remarks: ' + remark, tw, TY.small, book), f: book, size: TY.small, c: INK });
            var bh = TY.body + (lines.length - 1) * S(0);
            var ly = top - (h - bh) / 2 - TY.body * 0.8;
            lines.forEach(function (l, k) {
              if (l.ln) sh.draw(pg.page, l.ln, tx, ly, l.size, l.c); else tline(l.s, tx, ly, l.size, l.f, l.c);
              ly -= k === 0 ? S(1) : S(0);
            });
          }, h: ROWH }, shortDay(p.posted_on)];
          if (hasType) cells.push(typeWord(p) || '');
          cells.push(fmt(volOf(p)), fmt(engOf(p)), pct(erOf(p)));
          return { minH: ROWH, cells: cells };
        });
        var totalCells = [{ t: 'Total', f: reg }, ''];
        if (hasType) totalCells.push('');
        totalCells.push({ t: fmt(gg.views), f: med }, { t: fmt(gg.eng), f: med }, { t: pct(gg.er), f: med });
        rows.push({ fill: FILL, cells: totalCells });
        table(cols, head, rows);
      });
    })();

    // ------------------------------------------------------- Heads and feet
    /* The rate card's furniture on every page, the cover included, on the
       new margin: the Optima wordmark at S(2) top left and the client's name
       in small capitals on the right margin; PRIVATE & CONFIDENTIAL over the
       report's reference at the foot, the page count on the right. Slate
       Book Italic is not among the portal's fonts, so the reference is Slate
       Book slanted. */
    var n = pages.length;
    var label = String(rep.client_name || '').toUpperCase();
    var ymd = function (iso) { var d = iso ? new Date(iso) : new Date(); return d.getFullYear() + String(d.getMonth() + 1).padStart(2, '0') + String(d.getDate()).padStart(2, '0'); };
    var refLine = isDraft ? 'Draft ' + ymd(rep.generated_at) : 'v.' + (rep.version_no || 1) + ' issued ' + ymd(rep.generated_at);
    var slant = function (s, x, yy, size, f) { pg.page.drawText(String(s), { x: x, y: yy, size: size, font: f, color: INK, ySkew: PDF.degrees(12) }); };
    var markW = width('ADspace', S(2), mark);
    pages.forEach(function (p, i) {
      pg = p;
      text('ADspace', M, HEAD_Y, S(2), mark, INK);
      if (label) {
        var lab = clip(label, CW - markW - S(4), TY.small, med);
        var lw = sh.lineWidth(sh.linesOf(lab, 1e6, TY.small, med)[0] || [], TY.small);
        tline(lab, R - lw, HEAD_Y + 0.9, TY.small, med, INK);
      }
      text('PRIVATE & CONFIDENTIAL', M, FOOT_Y, TY.small, med, INK);
      if (/^[\u0000-ɏ -⁯]*$/.test(refLine)) slant(refLine, M, M, TY.small, book);
      else tline(refLine, M, M, TY.small, book, INK, CW);
      right('Page ' + (i + 1) + ' of ' + n, R, FOOT_Y, TY.small, book, INK);
    });
    return Promise.resolve(n);
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
