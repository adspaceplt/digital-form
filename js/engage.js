/*
 * The client record's Engagements pane (2026-10-10).
 *
 * The user, 2026-10-09: "Do you think client reports worth going into the
 * client file > Engagements so we have one less tab to monitor?" One pane
 * holds a client's work by content month, newest first: the month's content
 * in My Work, its Content Review sets, its Video Scripts, its creator
 * campaigns and its reports, each opening where it is worked. The record's
 * Reports tab is gone; `tab=reports` lands here.
 *
 * A month is a content month: the span `ops_month_span` gives a month that
 * starts on its `start_day` (the 16th runs to the 15th). A report belongs to
 * the month whose span holds its last day, as `sm_report_gate` finds it; a
 * set and a campaign to the month whose span holds the day they were made
 * (Malaysia time); a script to its own `period`. With no month in My Work
 * holding the day, the calendar month does.
 *
 * Each block asks its own permission before it reads, and each is read once
 * for the client in one request (never one a month or a row). A block whose
 * read is refused says so in its own line above the months; the others draw.
 * The month line under the record's name (js/crm.js) is read from the same
 * answer, so the record pays for one read of the months.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var bridge = window.ADspaceAdmin || {};
  var UI = window.ADspaceState;
  var GRP = window.ADspaceGroup;
  var W = window.ADspaceWords;
  var SM = function () { return window.ADspaceSmReport; };

  function may(key) { return Boolean(bridge.may && bridge.may(key, 'view')); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : (many || one + 's')); }

  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
                'August', 'September', 'October', 'November', 'December'];
  function shortMon(i) { return MONTHS[i].slice(0, 3).replace(/\bSep\b/, 'Sept'); }
  /* Today, and any stamp, as a day in Malaysia. */
  function dayMy(t) {
    var ms = t == null ? Date.now() : Date.parse(t);
    return isNaN(ms) ? '' : new Date(ms + 8 * 3600000).toISOString().slice(0, 10);
  }
  function addDays(day, n) { return new Date(Date.parse(day + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10); }
  function dayShort(day) { var d = new Date(day + 'T00:00:00Z'); return d.getUTCDate() + ' ' + shortMon(d.getUTCMonth()); }
  function dayLong(day) { var d = new Date(String(day).slice(0, 10) + 'T00:00:00Z'); return isNaN(d) ? '' : dayShort(String(day).slice(0, 10)) + ' ' + d.getUTCFullYear(); }

  /* A month's span: its first and last day. A month in My Work starts on its
     own day; any other is the calendar month. */
  function spanOf(period, startDay) {
    var y = Number(String(period).slice(0, 4)), mo = Number(String(period).slice(5, 7)) - 1;
    var d = Math.max(1, Math.min(28, Number(startDay) || 1));
    return { a: new Date(Date.UTC(y, mo, d)).toISOString().slice(0, 10),
             z: new Date(Date.UTC(y, mo + 1, d - 1)).toISOString().slice(0, 10), day: d };
  }
  function monthName(period) {
    return MONTHS[Number(String(period).slice(5, 7)) - 1] + ' ' + String(period).slice(0, 4);
  }

  var TYPE = { social: 'Accounts Report', ads: 'Advertising Report' };
  var STATUS = { draft: ['Draft', 'is-off'], review: ['In review', 'is-warn'],
                 confirmed: ['Confirmed', 'is-warn'], published: ['Published', 'is-ok'] };
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';
  var FILE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M12 12v6M9 15l3 3 3-3"/></svg>';
  /* What each block is called where its read is refused. */
  var BLOCK = { content: 'Content', reports: 'Reports', sets: 'Content Review sets',
                camps: 'Creator campaigns', scripts: 'Video Scripts' };

  // ---- Reading -----------------------------------------------------------------
  /* One answer a client, kept until the record reads again: a repaint (a save
     elsewhere on the record) draws from it and asks nothing. */
  var kept = { client: null, data: null, seq: 0 };
  function failed(r) { return r && (r.error || (r.data && r.data.error)); }
  function why(r) {
    var e = failed(r);
    return String((e && (e.message || e)) || 'The database refused the request.');
  }

  var READ = {
    /* My Work: the client's months, how far each is, and what is past its
       final date among the open tasks the reader sees. */
    content: function (c, out) {
      return db.from('ops_engagements').select('id, period, start_day, reports, status')
        .eq('client_id', c.id).order('period', { ascending: false })
        .then(function (r) {
          if (failed(r)) throw new Error(why(r));
          out.eng = r.data || [];
          var ids = out.eng.map(function (e) { return e.id; });
          if (!ids.length) { out.counts = {}; out.late = {}; return null; }
          return Promise.all([
            db.rpc('ops_engagement_counts', { p_engagements: ids }),
            db.from('ops_tasks').select('id, engagement_id, current_final_due_at').in('engagement_id', ids)
              .is('archived_at', null).is('cancelled_at', null).is('completed_at', null)
          ]).then(function (both) {
            if (failed(both[0])) throw new Error(why(both[0]));
            if (failed(both[1])) throw new Error(why(both[1]));
            out.counts = {}; out.late = {};
            (both[0].data || []).forEach(function (x) { out.counts[x.engagement_id] = x; });
            var today = dayMy();
            (both[1].data || []).forEach(function (t) {
              if (t.current_final_due_at && dayMy(t.current_final_due_at) < today) {
                out.late[t.engagement_id] = (out.late[t.engagement_id] || 0) + 1;
              }
            });
          });
        });
    },
    /* Reports View: every report of the client, with where it stands. */
    reports: function (c, out) {
      return db.from('sm_reports')
        .select('id, kind, period_start, period_end, status, version_no, brand_id, brand_name, sent_on, on_request')
        .eq('client_id', c.id).order('period_start', { ascending: false })
        .then(function (r) { if (failed(r)) throw new Error(why(r)); out.reports = r.data || []; });
    },
    /* Clients View without Reports: the finished reports, as the record's
       Reports tab listed them, each with Download. */
    finished: function (c, out) {
      return db.rpc('sm_client_reports', { p_client: c.id })
        .then(function (r) { if (failed(r)) throw new Error(why(r)); out.finished = (r.data || {}).reports || []; });
    },
    sets: function (c, out) {
      return db.from('batches').select('id, title, published, created_at, period').eq('client_id', c.id)
        .order('created_at', { ascending: false })
        .then(function (r) { if (failed(r)) throw new Error(why(r)); out.sets = r.data || []; });
    },
    camps: function (c, out) {
      return db.from('campaigns').select('id, title, state, slots, created_at').eq('client_id', c.id)
        .order('created_at', { ascending: false })
        .then(function (r) { if (failed(r)) throw new Error(why(r)); out.camps = r.data || []; });
    },
    scripts: function (c, out) {
      return db.from('video_scripts').select('id, period, seq, status').eq('client_id', c.id)
        .order('period', { ascending: false })
        .then(function (r) { if (failed(r)) throw new Error(why(r)); out.scripts = r.data || []; });
    }
  };
  /* Which blocks this reader is given, each behind its own permission. */
  function blocks() {
    var out = [];
    if (may('ops')) out.push('content');
    out.push(may('reports') ? 'reports' : 'finished');
    if (may('review.sets')) out.push('sets');
    if (may('campaigns.campaigns')) out.push('camps');
    if (may('scripts')) out.push('scripts');
    return out;
  }
  function readBlock(key, c, out) {
    delete out.fail[key === 'finished' ? 'reports' : key];
    return READ[key](c, out).catch(function (e) {
      out.fail[key === 'finished' ? 'reports' : key] = (e && e.message) || String(e);
    });
  }
  /* A reader of Reports who does not read My Work still files a report in
     the month its gate would: the months' spans come with the report months
     (`sm_report_months`, Reports View). A refusal there is no list, so it
     says nothing: the calendar month stands in. */
  function readSpans(c, out) {
    return db.rpc('sm_report_months', { p_client: c.id, p_kind: 'social' }).then(function (r) {
      if (!failed(r)) out.spans = (r.data || {}).months || [];
    }).catch(function () { return null; });
  }
  function read(c) {
    var out = { client: c.id, fail: {}, keys: blocks() };
    var jobs = out.keys.map(function (k) { return readBlock(k, c, out); });
    if (out.keys.indexOf('reports') > -1 && out.keys.indexOf('content') < 0) jobs.push(readSpans(c, out));
    return Promise.all(jobs).then(function () { return out; });
  }

  // ---- The months ---------------------------------------------------------------
  /* The spans a day is filed by: My Work's months that stand (as the gate
     reads them, cancelled left out), else the report months' spans. */
  function spansOf(d) {
    var src = d.eng || d.spans || [];
    return src.filter(function (e) { return e.status !== 'cancelled'; }).map(function (e) {
      var s = spanOf(e.period, e.start_day);
      return { period: e.period, a: s.a, z: s.z };
    });
  }
  function monthOf(day, spans) {
    day = String(day || '').slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return '';
    var hit = spans.filter(function (s) { return s.a <= day && day <= s.z; })
      .sort(function (x, y) { return x.period < y.period ? 1 : -1; })[0];
    return hit ? hit.period : day.slice(0, 7);
  }

  /* The month line's facts, and the Content row's: the month's content
     tasks done of those it holds, how many open ones are past their final
     date, and the day its report is owed (its last day plus
     `report_due_days`) while that day is ahead. */
  function factsOf(e, d) {
    var counts = (d.counts || {})[e.id];
    if (!counts) return null;
    var held = Number(counts.content != null ? counts.content : counts.live) || 0;
    var sp = spanOf(e.period, e.start_day);
    /* The setting as it stood on the month's last day, as the gate reads it. */
    var MON = window.ADspaceMoney;
    var days = (e.reports || []).length && MON && MON.setting ? Number(MON.setting('report_due_days', sp.z)) : NaN;
    var due = isNaN(days) ? '' : addDays(sp.z, days);
    return { held: held, done: Math.min(Number(counts.done) || 0, held), late: (d.late || {})[e.id] || 0,
             due: due, word: MONTHS[Number(e.period.slice(5, 7)) - 1], span: sp };
  }
  /* The month whose span holds today, for the line under the record's name. */
  function monthNow(clientId) {
    var d = kept.client === clientId ? kept.data : null;
    if (!d || !d.eng || d.fail.content) return null;
    var today = dayMy();
    var e = d.eng.filter(function (x) {
      if (x.status === 'cancelled') return false;
      var sp = spanOf(x.period, x.start_day);
      return sp.a <= today && today <= sp.z;
    })[0];
    return e ? factsOf(e, d) : null;
  }

  /* Every month the reader may see something in, newest first, each with
     its rows in the rail's order: My Work, Content Review, Video Scripts,
     Creator Campaigns, Reports. */
  function monthsOf(c, d) {
    var spans = spansOf(d), byKey = {};
    var month = function (k) {
      if (!byKey[k]) byKey[k] = { period: k, content: null, sets: [], scripts: [], camps: [], reports: [], files: [] };
      return byKey[k];
    };
    (d.eng && !d.fail.content ? d.eng : []).forEach(function (e) { month(e.period).content = e; });
    /* A set by the month it names (2026-10-10); an Ad hoc set by the day it
       was made. */
    (d.sets || []).forEach(function (s) { var k = /^\d{4}-\d{2}$/.test(s.period || '') ? s.period : monthOf(dayMy(s.created_at), spans); if (k) month(k).sets.push(s); });
    (d.scripts || []).forEach(function (s) { if (/^\d{4}-\d{2}$/.test(s.period || '')) month(s.period).scripts.push(s); });
    (d.camps || []).forEach(function (k0) { var k = monthOf(dayMy(k0.created_at), spans); if (k) month(k).camps.push(k0); });
    (d.reports || []).forEach(function (r) { var k = monthOf(r.period_end, spans); if (k) month(k).reports.push(r); });
    (d.finished || []).forEach(function (r) { var k = monthOf(r.period_end, spans); if (k) month(k).files.push(r); });
    return Object.keys(byKey).sort().reverse().map(function (k) {
      var m = byKey[k];
      /* The span the card states: its month in My Work, else the report
         months', else the calendar month. */
      var own = m.content || (d.spans || []).filter(function (s) { return s.period === k; })[0];
      m.span = spanOf(k, own ? own.start_day : 1);
      m.rows = rowsOf(c, d, m);
      return m;
    }).filter(function (m) { return m.rows.length; });
  }

  // ---- Rows -------------------------------------------------------------------
  function glyph(section) { return bridge.glyph ? bridge.glyph(section) : ''; }
  function parts(list) {
    return list.filter(Boolean).map(function (p, i) {
      return '<span class="part">' + (i ? '<span aria-hidden="true">· </span>' : '') + p + '</span>';
    }).join(' ');
  }
  function state(word, tone) { return '<span class="tone ' + (tone || 'is-off') + '">' + esc(word) + '</span>'; }
  function named(t, fallback) {
    var v = String(t == null ? '' : t).trim();
    return (!v || v === '0' || v === 'null' || v === 'undefined') ? fallback : v;
  }
  function periodWord(a, b) {
    return SM() && SM().periodWord ? SM().periodWord(a, b) : dayLong(a) + ' to ' + dayLong(b);
  }
  function rowsOf(c, d, m) {
    var rows = [], key = encodeURIComponent((c && (c.slug || c.id)) || '');
    var today = dayMy();
    if (m.content) {
      var e = m.content, f = factsOf(e, d);
      var st = e.status === 'cancelled' ? state('Cancelled', 'is-off')
        : e.status === 'completed' ? state('Completed', 'is-ok')
        : !f || !f.held ? state('No tasks', 'is-off')
        : state(f.done + ' of ' + f.held + ' done', f.late ? 'is-danger' : f.done >= f.held ? 'is-ok' : 'is-warn');
      rows.push({ kind: 'content', glyph: 'work', name: 'Content',
        meta: parts(['My Work', f && f.due && f.due >= today && e.status !== 'cancelled' ? 'Report due ' + esc(dayShort(f.due)) : '']),
        state: st, late: f ? f.late : 0,
        url: '/admin/?s=work&view=months&wc=' + key, section: 'work' });
    }
    m.sets.forEach(function (s) {
      rows.push({ kind: 'set', glyph: 'review', name: named(s.title, 'Content set'), meta: parts(['Content Review']),
        state: s.published ? state('Published', 'is-ok') : state('Draft', 'is-off'),
        url: '/admin/?s=review&client=' + key + '&set=' + encodeURIComponent(s.id), section: 'review' });
    });
    if (m.scripts.length) {
      var list = m.scripts.slice().sort(function (a, b) { return (Number(a.seq) || 0) - (Number(b.seq) || 0); });
      var pub = list.filter(function (s) { return s.status === 'shared'; }).length;
      rows.push({ kind: 'scripts', glyph: 'scripts', name: 'Video Scripts',
        meta: parts([plural(list.length, 'script'), pub + ' published']),
        state: pub === list.length ? state('Published', 'is-ok') : state('Draft', 'is-off'),
        url: '/admin/?s=scripts&month=' + encodeURIComponent(list[0].id), section: 'scripts' });
    }
    m.camps.forEach(function (k) {
      rows.push({ kind: 'campaign', glyph: 'campaigns', name: named(k.title, W.en.untitled),
        meta: parts(['Creator campaign', plural(Number(k.slots) || 0, 'creator')]),
        state: state(W.en.campState[k.state] || k.state, W.tone(k.state)),
        url: '/admin/?s=campaigns&campaign=' + encodeURIComponent(k.id), section: 'campaigns' });
    });
    m.reports.forEach(function (r) {
      var wl = r.brand_id && r.brand_name, s = STATUS[r.status] || STATUS.draft;
      rows.push({ kind: 'report', glyph: 'reports', name: wl ? r.brand_name : (TYPE[r.kind] || TYPE.social),
        chips: [wl ? 'White label' : '', r.on_request ? 'On request' : ''],
        meta: parts([wl ? esc(TYPE[r.kind] || TYPE.social) : '', esc(periodWord(r.period_start, r.period_end)),
          r.status === 'published' ? (r.sent_on ? 'Sent ' + esc(dayLong(r.sent_on)) : 'Not sent') : '']),
        state: state(s[0], s[1]),
        url: '/admin/?s=reports&report=' + encodeURIComponent(r.id), section: 'reports' });
    });
    m.files.forEach(function (r) {
      var live = r.live_version != null;
      rows.push({ kind: 'file', glyph: 'reports', name: TYPE[r.kind] || TYPE.social, id: r.id,
        meta: parts([esc(periodWord(r.period_start, r.period_end)),
          live ? 'Version ' + r.live_version + ', ' + esc(dayLong(dayMy(r.published_at))) : 'Version ' + r.version_no + ', not published']),
        state: live ? state('Published', 'is-ok') : state('Confirmed', 'is-warn') });
    });
    return rows;
  }

  /* A row opens its record where it is worked, the way search and the
     Overview open one: the address first, then the section. */
  function go(url, section) {
    history.replaceState(null, '', url);
    if (section === 'review' && bridge.restore) bridge.restore();
    else if (bridge.show) bridge.show(section);
  }
  function rowEl(row, c, msgEl) {
    var file = row.kind === 'file';
    var el = document.createElement(file ? 'div' : 'button');
    if (!file) el.type = 'button';
    el.className = 'crm-row cmonth-row' + (file ? ' is-file' : '');
    el.setAttribute('data-kind', row.kind);
    el.innerHTML =
      '<span class="cmonth-tile" aria-hidden="true">' + glyph(row.glyph) + '</span>' +
      '<span class="cmonth-what"><b><span class="cmonth-name">' + esc(row.name) + '</span>' +
        (row.chips || []).filter(Boolean).map(function (x) { return '<span class="chip">' + esc(x) + '</span>'; }).join('') +
        '</b><small>' + row.meta + '</small></span>' +
      '<span class="cmonth-state">' + row.state + '</span>' +
      '<span class="cmonth-end">' + (file
        ? '<button class="btn btn-sm" type="button" data-a="dl">' + FILE + 'Download</button>'
        : CHEV) + '</span>';
    if (!file) {
      el.addEventListener('click', function () { go(row.url, row.section); });
      return el;
    }
    var b = el.querySelector('[data-a="dl"]');
    b.addEventListener('click', function () {
      var R = window.ADspaceReports;
      if (!R || !R.clientFile) return;
      b.disabled = true;
      say(msgEl, 'Drawing the PDF…');
      R.clientFile(row.id, c.id).then(function (warn) {
        b.disabled = false;
        say(msgEl, warn ? 'Downloaded. ' + warn : 'Downloaded.', warn ? 'warn' : 'ok');
      }).catch(function (e) { b.disabled = false; say(msgEl, (e && e.message) || String(e), 'err'); });
    });
    return el;
  }
  function say(el, text, kind) {
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind ? ' ' + kind : '');
  }

  // ---- Drawing ------------------------------------------------------------------
  /* The pane: a line for each block whose read was refused, then a card a
     month, newest first. A month from today's on is open; an older one is
     shut until somebody opens it, and remembered. */
  function paint(host, c, msgEl) {
    if (!host || !c) return;
    var d = kept.client === c.id ? kept.data : null;
    if (!d) { UI.skeleton(host, 3); return; }
    host.innerHTML = '';
    Object.keys(BLOCK).forEach(function (k) {
      if (!d.fail[k]) return;
      var line = document.createElement('div');
      line.className = 'cmonth-fail';
      host.appendChild(line);
      UI.failLine(line, BLOCK[k], d.fail[k], function () {
        var keys = k === 'reports' ? d.keys.filter(function (x) { return x === 'reports' || x === 'finished'; }) : [k];
        UI.skeleton(line, 1);
        var seq = kept.seq;
        Promise.all(keys.map(function (x) { return readBlock(x, c, d); })).then(function () {
          if (seq !== kept.seq || kept.data !== d) return;
          paint(host, c, msgEl);
          if (kept.onData) kept.onData(c);
        });
      });
    });
    var months = monthsOf(c, d);
    if (!months.length) {
      if (!Object.keys(d.fail).length) UI.emptyLine(host, 'No engagements.');
      return;
    }
    var today = dayMy();
    months.forEach(function (m) {
      var late = m.rows.reduce(function (n, r) { return n + (r.late || 0); }, 0);
      var marks = (late ? '<span class="tone is-danger crm-band-late">' + late + ' overdue</span>' : '') +
        (m.span.day !== 1 ? '<span class="crm-band-worth">' + esc(dayShort(m.span.a) + ' to ' + dayShort(m.span.z)) + '</span>' : '');
      var hasFile = m.rows.some(function (r) { return r.kind === 'file'; });
      host.appendChild(GRP.section({
        route: 'client-months', key: m.period, name: monthName(m.period), count: m.rows.length, marks: marks,
        shut: GRP.shut('client-months', m.period, m.span.z < today, months.length === 1),
        table: function () {
          var t = document.createElement('div');
          t.className = 'crm-table softpanel cmonth-table' + (hasFile ? ' has-file' : '');
          GRP.more(t, m.rows, 30, '', function (row) { return rowEl(row, c, msgEl); });
          return t;
        }
      }));
    });
  }

  /* Whether the record draws the tab at all: a client engaged now or
     before, or one holding anything here (or a read that could not say). */
  function holds(clientId) {
    var d = kept.client === clientId ? kept.data : null;
    if (!d) return false;
    if (Object.keys(d.fail).length) return true;
    return ['eng', 'reports', 'finished', 'sets', 'camps', 'scripts'].some(function (k) { return (d[k] || []).length; });
  }

  /* Read the client's blocks again and hand the answer to `then`; a read
     overtaken by another, or by another client, is thrown away. */
  function load(c, then) {
    var seq = ++kept.seq;
    if (kept.client !== c.id) kept.data = null;
    kept.client = c.id;
    return read(c).then(function (d) {
      if (seq !== kept.seq) return;
      kept.data = d;
      if (then) then(c);
    });
  }

  window.ADspaceEngage = {
    load: load,
    paint: paint,
    holds: holds,
    monthNow: monthNow,
    loaded: function (clientId) { return kept.client === clientId && Boolean(kept.data); },
    /* What the record asks after a block read again by Try again. */
    onData: function (fn) { kept.onData = fn; }
  };
})();
