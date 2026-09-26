/*
 * Reports — the console's Reports section, and the client record's tab.
 *
 * A client's monthly report is started, entered, checked and published here,
 * in its own section (`?s=reports`), so a colleague can prepare reports
 * without reading client records. The client record's Reports tab lists the
 * finished reports only (confirmed or published), the way its Documents tab
 * lists the letters.
 *
 * A report is entered in four steps: its figures, its rows (accounts and
 * posts, or ads), the commentary, then Check and submit. The steps and who
 * may take each are the database's (`sm_report_*` in supabase/schema.sql);
 * this page draws the one next step the reader may take and names a refusal
 * in the team's words. A report is edited only while it is a draft.
 *
 *   Draft      Submit for review            reports Work
 *   In review  Confirm / Return             Manage, never the submitter
 *   Confirmed  Publish to client / Return   Manage
 *   Published  Revise, Unpublish            Work / Manage
 *
 * The PDF is drawn in the browser by js/smreport.js from the database's own
 * snapshot, so the file downloaded here is the file the client reads.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  var UI = window.ADspaceState;
  var SM = function () { return window.ADspaceSmReport; };
  function may(level) { return bridge.may ? bridge.may('reports', level) : false; }
  function me() { return bridge.me ? bridge.me() : null; }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function say(el, text, kind) {
    if (!el) return;
    el.textContent = text || ''; el.className = 'msg' + (kind ? ' ' + kind : '');
  }

  // ---- Words ----------------------------------------------------------------
  var STATUS = {
    draft: ['Draft', ''], review: ['In review', 'is-warn'],
    confirmed: ['Confirmed', ''], published: ['Published', 'is-ok']
  };
  /* The kinds of report the builder makes. Each is one engine of steps —
     draft, review, confirmed, published — with its own entry and its own
     PDF; the type is chosen when a report is started. */
  var TYPES = [{ key: 'social', name: 'Social Media Accounts Report' }, { key: 'ads', name: 'Social Media Advertising Report' }];
  var TYPE_WORD = {};
  TYPES.forEach(function (t) { TYPE_WORD[t.key] = t.name; });
  var PLATFORMS = [['facebook', 'Facebook'], ['instagram', 'Instagram'], ['tiktok', 'TikTok'], ['rednote', 'rednote'],
                   ['youtube', 'YouTube'], ['linkedin', 'LinkedIn'], ['x', 'X'], ['threads', 'Threads'], ['other', 'Other']];
  var PLATFORM_WORD = {};
  PLATFORMS.forEach(function (p) { PLATFORM_WORD[p[0]] = p[1]; });
  var METRICS = [['views', 'Views'], ['reach', 'Reach'], ['impressions', 'Impressions'], ['interactions', 'Interactions'],
                 ['engagements', 'Engagements'], ['likes', 'Likes'], ['comments', 'Comments'], ['shares', 'Shares'], ['saves', 'Saves']];
  var METRIC_WORD = {};
  METRICS.forEach(function (m) { METRIC_WORD[m[0]] = m[1]; });
  var FORMATS = [['', 'Not set'], ['reel', 'Reel'], ['video', 'Video'], ['post', 'Post'], ['photo', 'Photo'],
                 ['carousel', 'Carousel'], ['story', 'Story'], ['live', 'Live'], ['short', 'Short'], ['article', 'Article']];
  var FORMAT_WORD = {};
  FORMATS.forEach(function (f) { FORMAT_WORD[f[0]] = f[1]; });
  var BASIS = [['', 'Not calculated'], ['views', 'Views'], ['reach', 'Reach'], ['impressions', 'Impressions'], ['followers', 'Followers at period end']];
  /* The commentary a report carries: what the month was, what stood out,
     what to improve and what comes next. Every page already has its own
     heading, so nothing here asks for a title or a headline. The three
     further sections are folded, because most months do not need them. */
  var TEXT = {
    social: [['intro', 'Summary', 'Two or three sentences', 4], ['performed_well', 'Key findings', 'One point a line', 4],
             ['underperformed', 'Areas to improve', 'One point a line', 3], ['next_actions', 'Next steps', 'One point a line', 4]],
    ads:    [['intro', 'Summary', 'Two or three sentences', 4], ['worked', 'What worked', 'One point a line', 4],
             ['fix', 'What to fix', 'One point a line', 3], ['focus', 'Focus for next month', 'One point a line', 3]]
  };
  var TEXT_MORE = [['why_well', 'Performance drivers'], ['opportunities', 'Opportunities'], ['improvements', 'Improvements']];
  var SAID = {
    'denied': 'This needs a higher access level for Reports.',
    'not-found': 'This report no longer exists.',
    'exists': 'A report for this period already exists.',
    'bad-period': 'The period must end on or after the day it starts.',
    'not-draft': 'Only a draft can be submitted.',
    'no-platforms': 'Add an account before submitting.',
    'no-posts': 'Add the month\'s posts before submitting.',
    'no-ads': 'Add the period\'s ads before submitting.',
    'bad-kind': 'Reports need a database update. Run the 2026-09-25 report builder migration.',
    'note-required': 'Say what needs changing.',
    'not-returnable': 'Only a report in review or confirmed can be returned.',
    'not-in-review': 'Only a report in review can be confirmed.',
    'self-confirm': 'Somebody else confirms a report you submitted.',
    'not-confirmed': 'Confirm the report before publishing it.',
    'not-published': 'This report is not published.',
    'not-finished': 'This report is not finished yet.',
    'reason-required': 'Give a reason.',
    'has-versions': 'A report the client has seen cannot be deleted. Unpublish it instead.',
    'confirm-mismatch': 'That does not match the period.',
    'sm-not-draft': 'This report is no longer a draft, so it cannot be changed. Refresh to see where it stands.',
    'sm-status-by-function': 'The status changes only through its own step.',
    'sm-wrong-platform': 'Choose one of this report\'s accounts.'
  };
  function said(e) {
    var m = String((e && (e.error || e.message)) || e || '');
    var key = Object.keys(SAID).filter(function (k) { return m.indexOf(k) > -1; })[0];
    if (key) return SAID[key];
    if (/function .* does not exist|schema cache/i.test(m)) return 'Reports need a database update. Run the 2026-09-25 report builder migration.';
    return m || 'Not saved.';
  }

  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function periodWord(a, b) { return SM() ? SM().periodWord(a, b) : String(a) + ' to ' + String(b); }
  function dayWord(s) {
    if (!s) return '';
    var d = new Date(String(s).slice(0, 10) + 'T00:00:00');
    return isNaN(d) ? String(s) : d.getDate() + ' ' + MON[d.getMonth()] + ' ' + d.getFullYear();
  }
  function stampWord(s) {
    var d = new Date(s);
    return isNaN(d) ? '' : d.getDate() + ' ' + MON[d.getMonth()] + ' ' + d.getFullYear();
  }
  function fmt(v) { return v == null || v === '' ? '—' : Number(v).toLocaleString('en-GB'); }
  function chip(status) {
    var w = STATUS[status] || STATUS.draft;
    return '<span class="chip ' + w[1] + '">' + esc(w[0]) + '</span>';
  }
  function ymd(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : (many || one + 's')); }

  var ICON = {
    back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 18l-6-6 6-6"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    more: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>',
    file: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M12 12v6M9 15l3 3 3-3"/></svg>',
    close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    tick: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    go: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6"/></svg>'
  };

  // ---- State ----------------------------------------------------------------
  /* `host` is the editor's box in the Reports section; `client` is the open
     report's client, read with the report. */
  var st = { host: null, client: null, open: null, platforms: [], posts: [], ads: [], busy: false, step: '' };

  // ---- The client record's Reports tab: the finished reports only ------------
  function clientPane(host, client) {
    if (!host || !client) return;
    var canOpen = may('view');
    host.innerHTML = '<div class="viewhead rp-viewhead"><h3>Reports</h3>' +
      (canOpen ? '<button class="btn btn-sm" type="button" data-a="hub">Open in Reports</button>' : '') +
      '</div><div class="rp-outbox"></div><div class="msg" data-m="out"></div>';
    var hubBtn = host.querySelector('[data-a="hub"]');
    if (hubBtn) hubBtn.addEventListener('click', function () { goReport(''); });
    var box = host.querySelector('.rp-outbox');
    UI.skeleton(box, 2);
    db.rpc('sm_client_reports', { p_client: client.id }).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) { UI.failLine(box, 'reports', said(r.error || d), function () { clientPane(host, client); }); return; }
      var rows = d.reports || [];
      if (!rows.length) { UI.emptyLine(box, 'No finished reports.'); return; }
      box.innerHTML = '<div class="crm-table softpanel rp-out-table">' +
        '<div class="crm-head rp-out-row"><span>Report</span><span>Status</span><span>Version</span><span></span></div>' +
        rows.map(function (x) {
          var live = x.live_version != null;
          return '<div class="crm-row rp-out-row" data-id="' + esc(x.id) + '">' +
            '<span class="rp-name"><b>' + esc(periodWord(x.period_start, x.period_end)) + '</b><small>' + esc(TYPE_WORD[x.kind] || '') + '</small></span>' +
            '<span class="rp-state">' + chip(live ? 'published' : 'confirmed') + '</span>' +
            '<span class="rp-ver">' + (live ? 'Version ' + x.live_version + ', ' + esc(stampWord(x.published_at))
                                             : 'Version ' + x.version_no + ', not yet published') + '</span>' +
            '<span class="rp-out-act"><button class="btn btn-sm" type="button" data-a="dl">' + ICON.file + 'Download</button></span></div>';
        }).join('') + '</div>';
      var m = host.querySelector('[data-m="out"]');
      Array.prototype.forEach.call(box.querySelectorAll('[data-a="dl"]'), function (b) {
        b.addEventListener('click', function () {
          var id = b.closest('[data-id]').getAttribute('data-id');
          b.disabled = true; say(m, 'Drawing the PDF…');
          db.rpc('sm_report_file', { p_id: id }).then(function (x) {
            var got = x.data || {};
            if (x.error || got.error || !got.snapshot) throw new Error(x.error ? x.error.message : (got.error || 'not-found'));
            if (got.snapshot.error) throw new Error(got.snapshot.error);
            return saveFile(got.snapshot);
          }).then(function (warn) {
            b.disabled = false;
            say(m, warn ? 'Downloaded. ' + warn : 'Downloaded.', warn ? 'warn' : 'ok');
          }).catch(function (e) { b.disabled = false; say(m, said(e), 'err'); });
        });
      });
    });
  }

  /* Draw a snapshot and hand the browser the file. Resolves with any warning
     the engine raised (a logo it could not load), else nothing. */
  function saveFile(snap) {
    if (!SM()) return Promise.reject(new Error('The report engine did not load. Refresh the page.'));
    return SM().render(snap).then(function (out) {
      var blob = new Blob([out.bytes], { type: 'application/pdf' });
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = SM().fileName(snap);
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(function () { URL.revokeObjectURL(a.href); }, 30000);
      return out.warnings && out.warnings.length ? out.warnings.join(' ') : '';
    });
  }

  /* Open a report in the Reports section from anywhere: the address first,
     then the section, the way the bell opens a task. A blank id opens the
     list. */
  function goReport(id) {
    history.pushState(null, '', '/admin/?s=reports' + (id ? '&report=' + encodeURIComponent(id) : ''));
    if (bridge.show) bridge.show('reports');
  }

  // ---- A new report -------------------------------------------------------------
  var sheets = {};
  function sheetShell(id, title, body, foot) {
    if (sheets[id]) return sheets[id];
    var box = document.createElement('div');
    box.className = 'sheet'; box.id = id; box.hidden = true;
    box.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="' + id + 'Title">' +
      '<div class="sheet-head"><h3 id="' + id + 'Title">' + esc(title) + '</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + ICON.close + '</button></div>' +
      '<div class="sheet-body">' + body + '<div class="msg" data-m="sheet"></div></div>' +
      '<div class="sheet-foot">' + foot + '</div></div>';
    document.body.appendChild(box);
    Array.prototype.forEach.call(box.querySelectorAll('[data-a="x"], [data-a="cancel"]'), function (b) {
      b.addEventListener('click', function () { window.ADspaceSheet.close(); });
    });
    if (window.ADspaceForm) window.ADspaceForm.scan(box);
    sheets[id] = box;
    return box;
  }
  var FOOT = function (go) {
    return '<button class="btn btn-primary" type="button" data-a="go">' + esc(go) + '</button>' +
      '<button class="btn btn-quiet" type="button" data-a="cancel">Cancel</button>';
  };

  /* Start a report: the type first, as a segment, then the client and the
     month (or a custom period). */
  function newSheet(opener) {
    var box = sheetShell('rpNewSheet', 'New report',
      '<section class="fsec">' +
        '<div class="row"><div><label class="field-label" for="rpNewKind">Report type</label>' +
          '<select class="select" id="rpNewKind" data-seg>' + TYPES.map(function (t) {
            return '<option value="' + t.key + '">' + esc(t.name.replace(/ report$/, '')) + '</option>';
          }).join('') + '</select></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpNewClient">Client</label><select class="select" id="rpNewClient" aria-required="true"></select></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpNewMonth">Month</label><input class="input" id="rpNewMonth" aria-required="true" type="month"></div></div>' +
      '<details class="fmore" data-none="Whole month" data-some="Custom period"><summary>Custom period</summary>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpNewStart">Start</label><input class="input" id="rpNewStart" aria-required="true" type="date" data-hint="Select date"></div>' +
        '<div><label class="field-label" for="rpNewEnd">End</label><input class="input" id="rpNewEnd" aria-required="true" type="date" data-hint="Select date"></div></div></details>' +
      '</section>', FOOT('Create'));
    $('rpNewClient').innerHTML = '<option value="">Choose a client</option>' + hub.clients.map(function (c) {
      return '<option value="' + esc(c.id) + '">' + esc(c.name) + '</option>';
    }).join('');
    $('rpNewKind').value = ($('rhKind') && $('rhKind').value) || 'social';
    if (window.ADspaceForm) window.ADspaceForm.paint($('rpNewKind'));
    var now = new Date();
    var last = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    $('rpNewMonth').value = last.getFullYear() + '-' + String(last.getMonth() + 1).padStart(2, '0');
    $('rpNewStart').value = ''; $('rpNewEnd').value = '';
    $('rpNewEnd').min = ''; if (window.ADspaceForm) ADspaceForm.floor($('rpNewEnd'));
    /* A month or a custom period, never both: opening Custom period sets the
       Month aside, and shutting it clears the two dates and gives the Month
       back, so what is created is always what is on the screen. The end can
       never fall before the start. */
    var fold = box.querySelector('details.fmore');
    fold.open = false;
    var period = function () {
      $('rpNewMonth').disabled = fold.open;
      if (!fold.open) { $('rpNewStart').value = ''; $('rpNewEnd').value = ''; $('rpNewEnd').min = ''; if (window.ADspaceForm) ADspaceForm.floor($('rpNewEnd')); }
      if (window.ADspaceForm) { window.ADspaceForm.hint($('rpNewStart')); window.ADspaceForm.hint($('rpNewEnd')); }
    };
    fold.ontoggle = period;
    $('rpNewStart').onchange = function () {
      var a = $('rpNewStart').value;
      $('rpNewEnd').min = a || ''; if (window.ADspaceForm) ADspaceForm.floor($('rpNewEnd'));
      if (a && $('rpNewEnd').value && $('rpNewEnd').value < a) {
        $('rpNewEnd').value = '';
        if (window.ADspaceForm) window.ADspaceForm.hint($('rpNewEnd'));
      }
    };
    period();
    var sm = box.querySelector('[data-m="sheet"]');
    say(sm, '');
    var go = box.querySelector('[data-a="go"]');
    go.onclick = function () {
      var m = $('rpNewMonth').value, a = $('rpNewStart').value, b = $('rpNewEnd').value;
      var client = $('rpNewClient').value;
      if (!client) { say(sm, 'Choose a client.', 'err'); $('rpNewClient').focus(); return; }
      if (fold.open) {
        if (!a) { say(sm, 'Choose a start date.', 'err'); $('rpNewStart').focus(); return; }
        if (!b) { say(sm, 'Choose an end date.', 'err'); $('rpNewEnd').focus(); return; }
        if (b < a) { say(sm, 'The end date is before the start date.', 'err'); $('rpNewEnd').focus(); return; }
      } else {
        if (!/^\d{4}-\d{2}$/.test(m)) { say(sm, 'Choose a month.', 'err'); return; }
        var y = Number(m.slice(0, 4)), mo = Number(m.slice(5, 7));
        a = ymd(new Date(y, mo - 1, 1)); b = ymd(new Date(y, mo, 0));
      }
      go.disabled = true;
      db.rpc('sm_report_create', { p_client: client, p_start: a, p_end: b, p_kind: $('rpNewKind').value || 'social' }).then(function (r) {
        go.disabled = false;
        var d = r.data || {};
        var id = d.id;
        if (r.error || (d.error && !(d.error === 'exists' && id))) { say(sm, said(r.error || d), 'err'); return; }
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        openReport(id);
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  // ---- One report -----------------------------------------------------------------
  /* The steps a report is entered in. The last is where it is checked and
     handed on; a report that has left draft opens there, because that is
     where its next step is. */
  var STEPS = {
    social: [['accounts', 'Accounts'], ['posts', 'Posts'], ['text', 'Commentary'], ['check', 'Check and submit']],
    ads:    [['figures', 'Figures'], ['ads', 'Ads'], ['text', 'Commentary'], ['check', 'Check and submit']]
  };
  function stepsOf(r) { return STEPS[r && r.kind === 'ads' ? 'ads' : 'social']; }
  function firstStep() {
    var r = st.open;
    if (!r || r.status !== 'draft') return 'check';
    var s = stepsOf(r);
    for (var i = 0; i < s.length - 1; i++) if (!stepDone(s[i][0])) return s[i][0];
    return 'check';
  }

  function openReport(id, fromAddress) {
    var same = st.open && st.open.id === id && st.open.client_id;
    st.open = st.open && st.open.id === id ? st.open : { id: id };
    var want = new URLSearchParams(location.search).get('step');
    showEditor();
    if (!fromAddress) { st.step = ''; if (bridge.pushUrl) bridge.pushUrl(); }
    else if (want) st.step = want;
    if (same && fromAddress) { paintEditor(); return; }
    var host = st.host;
    host.innerHTML = '<button class="backlink" type="button" data-a="back">' + ICON.back + 'Reports</button><div class="rp-editbox"></div>';
    host.querySelector('[data-a="back"]').addEventListener('click', function () { st.open = null; goReport(''); });
    UI.skeleton(host.querySelector('.rp-editbox'), 4);
    Promise.all([
      db.from('sm_reports').select('*').eq('id', id).maybeSingle(),
      db.from('sm_report_platforms').select('*').eq('report_id', id).order('position', { ascending: true }),
      db.from('sm_report_posts').select('*').eq('report_id', id).order('posted_on', { ascending: true }).order('position', { ascending: true }),
      db.from('sm_report_versions').select('id, version_no, published_at, published_by, withdrawn_at, withdraw_reason').eq('report_id', id).order('version_no', { ascending: false })
    ]).then(function (got) {
      var box = host.querySelector('.rp-editbox');
      var bad = got.filter(function (r) { return r.error; })[0];
      if (bad) { UI.failLine(box, 'the report', said(bad.error), function () { openReport(id, true); }); return; }
      if (!got[0].data) { UI.emptyLine(box, 'No such report.', 'Back to Reports', function () { goReport(''); }); return; }
      st.open = got[0].data;
      st.platforms = got[1].data || [];
      st.posts = got[2].data || [];
      sortPosts();
      st.openVersions = got[3].data || [];
      st.ads = [];
      var more = [db.from('clients').select('id, name, market, slug').eq('id', st.open.client_id).maybeSingle()];
      if (st.open.kind === 'ads') more.push(db.from('sm_report_ads').select('*').eq('report_id', id).order('position', { ascending: true }));
      return Promise.all(more).then(function (x) {
        if (x[1] && x[1].error) { UI.failLine(box, 'the ads', said(x[1].error), function () { openReport(id, true); }); return; }
        st.client = (x[0] && x[0].data) || { id: st.open.client_id, name: '' };
        if (x[1]) { st.ads = x[1].data || []; sortAds(); }
        paintEditor();
      });
    });
  }

  function editable() { return st.open && st.open.status === 'draft' && may('work'); }
  function myId() { var m = me(); return m && m.id; }

  /* What each step holds, in the words its button says under its name. */
  function commentaryCount() {
    var r = st.open || {}, ins = r.insights || {};
    return TEXT[r.kind === 'ads' ? 'ads' : 'social'].filter(function (x) {
      return String((x[0] === 'intro' ? (r.intro || ins.executive_summary) : ins[x[0]]) || '').trim();
    }).length;
  }
  function stepDone(k) {
    var r = st.open || {}, t = r.ads_totals || {};
    if (k === 'accounts') return st.platforms.length > 0;
    if (k === 'posts') return st.posts.length > 0;
    if (k === 'ads') return st.ads.length > 0;
    if (k === 'figures') return t.reach != null;
    if (k === 'text') return commentaryCount() > 0;
    return r.status && r.status !== 'draft';
  }
  function stepNote(k) {
    var r = st.open || {};
    if (k === 'accounts') return st.platforms.length ? plural(st.platforms.length, 'account') : 'None yet';
    if (k === 'posts') return st.posts.length ? plural(st.posts.length, 'post') : 'None yet';
    if (k === 'ads') return st.ads.length ? plural(st.ads.length, 'ad') : 'None yet';
    if (k === 'figures') return (r.ads_totals || {}).reach != null ? 'Reach entered' : 'Reach not entered';
    if (k === 'text') { var n = commentaryCount(); return n ? n + ' of 4 written' : 'Not written'; }
    return (STATUS[r.status] || STATUS.draft)[0];
  }

  function paintEditor() {
    var r = st.open;
    var box = st.host && st.host.querySelector('.rp-editbox');
    if (!box || !r || !r.client_id) { openReport(r ? r.id : '', true); return; }
    if (!st.step || !stepsOf(r).some(function (s) { return s[0] === st.step; })) st.step = firstStep();
    var live = (st.openVersions || []).filter(function (v) { return !v.withdrawn_at; })[0];
    box.innerHTML = '<section class="panel rp-head">' +
      '<div class="rp-head-top"><div class="rp-who"><h3>' + esc(st.client.name || 'Report') + '</h3>' +
      '<p class="rp-meta">' + esc(TYPE_WORD[r.kind] || '') + ' · ' + esc(periodWord(r.period_start, r.period_end)) + ' · Version ' + r.version_no +
        (live ? ' · Version ' + live.version_no + ' on the client portal' : '') + '</p></div>' +
      '<div class="rp-ctl">' + chip(r.status) +
        '<button class="btn btn-sm" type="button" data-a="pdf">' + ICON.file + (r.status === 'published' ? 'Download PDF' : 'Preview PDF') + '</button>' +
        moreMenu(r, live) + '</div></div>' +
      (r.status === 'draft' && r.return_note ? '<p class="rp-note is-warn"><b>Returned:</b> ' + esc(r.return_note) + '</p>' : '') +
      '<div class="msg" data-m="head"></div></section>' +
      '<nav class="rp-steps" aria-label="Steps"></nav>' +
      '<div class="rp-stepbox"></div>';
    wireHead(box);
    paintSteps();
    paintStep();
  }

  function paintSteps() {
    var nav = st.host && st.host.querySelector('.rp-steps');
    if (!nav || !st.open) return;
    nav.innerHTML = stepsOf(st.open).map(function (s, i) {
      var on = s[0] === st.step, done = s[0] !== 'check' && stepDone(s[0]);
      return '<button class="rp-step' + (on ? ' is-on' : '') + (done ? ' is-done' : '') + '" type="button" data-step="' + s[0] + '"' +
        (on ? ' aria-current="step"' : '') + '>' +
        '<span class="rp-step-n" aria-hidden="true">' + (done ? ICON.tick : String(i + 1)) + '</span>' +
        '<span class="rp-step-t"><b>' + esc(s[1]) + '</b><small>' + esc(stepNote(s[0])) + '</small></span></button>';
    }).join('');
    Array.prototype.forEach.call(nav.querySelectorAll('.rp-step'), function (b) {
      b.addEventListener('click', function () { goStep(b.getAttribute('data-step')); });
    });
  }
  function goStep(k) {
    st.step = k;
    if (bridge.setUrl) bridge.setUrl();
    paintSteps();
    paintStep();
    var nav = st.host.querySelector('.rp-steps');
    if (nav && nav.getBoundingClientRect().top < 0) nav.scrollIntoView({ block: 'start' });
  }
  function nextOf(k) {
    var s = stepsOf(st.open);
    for (var i = 0; i < s.length - 1; i++) if (s[i][0] === k) return s[i + 1];
    return null;
  }

  /* One step at a time. Each ends on the move to the next, named for it. */
  function paintStep() {
    var box = st.host.querySelector('.rp-stepbox');
    if (!box) return;
    var r = st.open, ed = editable(), k = st.step;
    var head = function (title, acts) {
      return '<div class="rp-sec-head"><h3 class="ovsec-title">' + esc(title) + '</h3>' + (acts ? '<span class="rp-sec-acts">' + acts + '</span>' : '') + '</div>';
    };
    var next = nextOf(k);
    var foot = next && (!ed || (k !== 'text' && k !== 'figures'))
      ? '<div class="rp-stepfoot"><button class="btn' + (ed ? ' btn-primary' : '') + '" type="button" data-a="next">Next: ' + esc(next[1]) + '</button></div>' : '';
    if (k === 'accounts') {
      box.innerHTML = '<div class="rp-sec">' + head('Accounts', ed ? '<button class="btn btn-sm" type="button" data-a="addacc">' + ICON.plus + 'Add account</button>' : '') +
        '<div class="rp-accs"></div></div>' + foot;
      paintAccounts();
    } else if (k === 'posts') {
      box.innerHTML = '<div class="rp-sec">' + head('Posts', ed && st.platforms.length ? '<button class="btn btn-sm" type="button" data-a="paste">Import from spreadsheet</button>' +
          '<button class="btn btn-sm" type="button" data-a="addpost">' + ICON.plus + 'Add post</button>' : '') +
        (ed && st.platforms.length ? '<div class="rp-rank"><label class="field-label" for="rpRank">Top posts ranked by</label><select class="select select-sm" id="rpRank">' +
          ['views', 'reach', 'impressions', 'engagements', 'interactions'].map(function (m0) { return '<option value="' + m0 + '">' + esc(METRIC_WORD[m0]) + '</option>'; }).join('') +
          '</select><span class="msg" data-m="rank"></span></div>' : '') +
        '<div class="rp-posts"></div></div>' + foot;
      if ($('rpRank')) {
        $('rpRank').value = r.rank_metric || 'views';
        $('rpRank').addEventListener('change', function () {
          var sel = this, m = box.querySelector('[data-m="rank"]');
          db.from('sm_reports').update({ rank_metric: sel.value }).eq('id', r.id).select('*').then(function (res) {
            if (res.error || !(res.data || []).length) { say(m, said(res.error || 'The database refused the change.'), 'err'); return; }
            st.open = res.data[0]; say(m, 'Saved.', 'ok');
          });
        });
      }
      paintPosts();
    } else if (k === 'figures') {
      box.innerHTML = '<div class="rp-sec">' + head('Account figures') + '<div class="rp-totals"></div></div>' + foot;
      paintTotals();
    } else if (k === 'ads') {
      box.innerHTML = '<div class="rp-sec">' + head('Ads', ed ? '<button class="btn btn-sm" type="button" data-a="pasteads">Import from Ads Manager</button>' +
          '<button class="btn btn-sm" type="button" data-a="addad">' + ICON.plus + 'Add ad</button>' : '') +
        '<div class="rp-ads"></div></div>' + foot;
      paintAds();
    } else if (k === 'text') {
      box.innerHTML = '<div class="rp-sec">' + head('Commentary') + '<div class="rp-text"></div></div>' + foot;
      paintText();
    } else {
      paintCheck(box);
    }
    var b;
    if ((b = box.querySelector('[data-a="next"]'))) b.addEventListener('click', function () { goStep(next[0]); });
    if ((b = box.querySelector('[data-a="addacc"]'))) { var ac = b; ac.addEventListener('click', function () { accountSheet(null, ac); }); }
    if ((b = box.querySelector('[data-a="addpost"]'))) { var ab = b; ab.addEventListener('click', function () { postSheet(null, ab); }); }
    if ((b = box.querySelector('[data-a="paste"]'))) { var pb = b; pb.addEventListener('click', function () { pasteSheet(pb); }); }
    if ((b = box.querySelector('[data-a="addad"]'))) { var ad = b; ad.addEventListener('click', function () { adSheet(null, ad); }); }
    if ((b = box.querySelector('[data-a="pasteads"]'))) { var pa = b; pa.addEventListener('click', function () { pasteAdsSheet(pa); }); }
  }

  /* The last step: what the report holds, what is still missing, and the one
     step the reader may take next. Blue only where it hands the report to
     somebody else: to a reviewer, or to the client. */
  function paintCheck(box) {
    var r = st.open;
    var rows = stepsOf(r).slice(0, 3).map(function (s) {
      var need = s[0] !== 'text' && s[0] !== 'figures';
      var done = stepDone(s[0]);
      return '<div class="rp-check' + (done ? ' is-done' : need ? ' is-missing' : '') + '">' +
        '<span class="rp-check-mark" aria-hidden="true">' + (done ? ICON.tick : '') + '</span>' +
        '<span class="rp-check-t"><b>' + esc(s[1]) + '</b><small>' + esc(stepNote(s[0]) + (!done ? (need ? ' · Required' : ' · Optional') : '')) + '</small></span>' +
        '<button class="btn btn-sm btn-quiet" type="button" data-to="' + s[0] + '">' + (editable() ? 'Edit' : 'View') + '</button></div>';
    }).join('');
    var missing = stepsOf(r).slice(0, 3).filter(function (s) { return s[0] !== 'text' && s[0] !== 'figures' && !stepDone(s[0]); });
    var mine = r.submitted_by && r.submitted_by === myId();
    var acts = [], wait = '';
    if (r.status === 'draft' && may('work')) acts.push('<button class="btn btn-go" type="button" data-a="submit"' + (missing.length ? ' disabled' : '') + '>Submit for review</button>');
    if (r.status === 'review' && may('manage') && !mine) acts.push('<button class="btn btn-primary" type="button" data-a="confirm">Confirm</button>');
    if (r.status === 'confirmed' && may('manage')) acts.push('<button class="btn btn-go" type="button" data-a="publish">Publish to client</button>');
    if (r.status === 'published' && may('work')) acts.push('<button class="btn" type="button" data-a="revise">Revise</button>');
    if ((r.status === 'review' && (may('manage') || mine)) || (r.status === 'confirmed' && may('manage'))) {
      acts.push('<button class="btn" type="button" data-a="return">' + (r.status === 'review' && mine && !may('manage') ? 'Take back' : 'Return') + '</button>');
    }
    if (r.status === 'draft' && missing.length) wait = 'Add ' + missing.map(function (s) { return s[1].toLowerCase(); }).join(' and ') + ' to submit.';
    else if (r.status === 'review' && mine && may('manage')) wait = 'Waiting on another manager to confirm.';
    else if (r.status === 'review' && !may('manage')) wait = 'Waiting on a manager to confirm.';
    else if (r.status === 'confirmed' && !may('manage')) wait = 'Waiting on a manager to publish.';
    box.innerHTML = '<div class="rp-sec"><div class="rp-sec-head"><h3 class="ovsec-title">Check and submit</h3></div>' +
      '<div class="ovcard rp-checks">' + rows + '</div>' +
      (acts.length || wait ? '<div class="rp-actions">' + acts.join('') + (wait ? '<span class="rp-wait">' + esc(wait) + '</span>' : '') + '</div>' : '') +
      '<div class="msg" data-m="check"></div></div>';
    Array.prototype.forEach.call(box.querySelectorAll('[data-to]'), function (b) {
      b.addEventListener('click', function () { goStep(b.getAttribute('data-to')); });
    });
    wireSteps(box);
  }

  function moreMenu(r, live) {
    var items = [];
    if (live && may('manage')) items.push('<button class="kmenu-item is-danger" data-soft type="button" data-a="unpublish">Unpublish</button>');
    if (!(st.openVersions || []).length && may('manage')) items.push('<button class="kmenu-item is-danger" type="button" data-a="delete">Delete</button>');
    if (!items.length) return '';
    return '<span class="team-act kmenu-wrap"><button class="kmenu-btn" type="button" aria-label="More" aria-haspopup="true" aria-expanded="false" data-a="more">' + ICON.more + '</button>' +
      '<div class="kmenu" hidden>' + items.join('') + '</div></span>';
  }

  /* A step that moves the report repaints it from the database and says what
     happened under the head, where the status chip has just changed. */
  function stepCall(fn, args, done, btn, m) {
    if (btn) btn.disabled = true;
    db.rpc(fn, args).then(function (res) {
      if (btn) btn.disabled = false;
      var d = res.data || {};
      if (res.error || d.error) { say(m, said(res.error || d), 'err'); return; }
      var id = st.open.id;
      st.open = { id: id }; st.step = '';
      if (bridge.setUrl) bridge.setUrl();
      openReport(id, true);
      var tries = 0;
      (function tell() {
        var el = st.host && st.host.querySelector('.rp-head [data-m="head"]');
        if (el && st.open && st.open.client_id) { say(el, done, 'ok'); return; }
        if (++tries < 40) setTimeout(tell, 50);
      })();
    });
  }

  function wireSteps(box) {
    var r = st.open, m = box.querySelector('[data-m="check"]');
    var on = function (a, fn) { var b = box.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); };
    on('submit', function (b) {
      window.ADspaceConfirm.ask({ title: 'Submit for review?', body: 'A manager checks it before it is published. It is locked while in review.', go: 'Submit' },
        function () { stepCall('sm_report_submit', { p_id: r.id }, 'Submitted for review.', b, m); });
    });
    on('confirm', function (b) { stepCall('sm_report_confirm', { p_id: r.id }, 'Confirmed.', b, m); });
    on('publish', function (b) {
      window.ADspaceConfirm.ask({ title: 'Publish to ' + st.client.name + '?', body: 'The client can read and download it in their portal.', go: 'Publish' },
        function () { stepCall('sm_report_publish', { p_id: r.id }, 'Published to the client portal.', b, m); });
    });
    on('revise', function (b) {
      window.ADspaceConfirm.ask({ title: 'Revise this report?', body: 'Version ' + (r.version_no + 1) + ' starts as a draft. The client keeps version ' + r.version_no + ' until it is published.', go: 'Revise' },
        function () { stepCall('sm_report_revise', { p_id: r.id }, 'Version ' + (r.version_no + 1) + ' is a draft.', b, m); });
    });
    on('return', function (b) {
      window.ADspaceConfirm.ask({ title: 'Return to draft?', go: 'Return', field: { label: 'What needs changing', rows: 3, need: 'Say what needs changing.' } },
        function (note) { stepCall('sm_report_return', { p_id: r.id, p_note: note }, 'Returned to draft.', b, m); });
    });
  }

  function wireHead(box) {
    var r = st.open, m = box.querySelector('[data-m="head"]');
    var on = function (a, fn) { var b = box.querySelector('.rp-head [data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); };
    on('pdf', function (b) { downloadPdf(b, m); });
    on('more', function (b) {
      var menu = b.parentNode.querySelector('.kmenu');
      var open = menu.hidden;
      menu.hidden = !open; b.setAttribute('aria-expanded', String(open));
      if (open && window.ADspaceMenu) window.ADspaceMenu.place(b, menu);
    });
    on('unpublish', function (b) {
      b.closest('.kmenu').hidden = true;
      window.ADspaceConfirm.ask({ title: 'Unpublish this report?', body: 'The client can no longer read it. It can be published again.', go: 'Unpublish', tone: 'warn',
        field: { label: 'Reason', need: 'Give a reason.' } },
        function (why) { stepCall('sm_report_unpublish', { p_id: r.id, p_reason: why }, 'Unpublished.', null, m); });
    });
    on('delete', function (b) {
      b.closest('.kmenu').hidden = true;
      var word = periodWord(r.period_start, r.period_end);
      window.ADspaceConfirm.ask({ title: 'Delete this report?', body: (r.kind === 'ads' ? 'Its ads and text go with it.' : 'Its accounts, posts and text go with it.') + ' There is no restore.', go: 'Delete', tone: 'danger',
        field: { label: 'Type ' + word + ' to confirm', match: word, mismatch: 'That does not match the period.' } },
        function (typed) {
          db.rpc('sm_report_delete', { p_id: r.id, p_confirm: typed }).then(function (res) {
            var d = res.data || {};
            if (res.error || d.error) { say(m, said(res.error || d), 'err'); return; }
            st.open = null; goReport('');
          });
        });
    });
  }

  /* The file the client reads: a published report downloads its published
     version; anything else is a preview drawn from the rows as they stand,
     marked Draft on every page. */
  function downloadPdf(btn, m) {
    var r = st.open;
    var live = (st.openVersions || []).filter(function (v) { return !v.withdrawn_at; })[0];
    btn.disabled = true;
    say(m, 'Drawing the PDF…');
    var get = r.status === 'published' && live
      ? db.from('sm_report_versions').select('snapshot').eq('id', live.id).maybeSingle().then(function (x) {
          if (x.error || !x.data) throw new Error(x.error ? x.error.message : 'not-found');
          return x.data.snapshot;
        })
      : db.rpc('sm_report_snapshot', { p_id: r.id, p_final: false }).then(function (x) {
          if (x.error || (x.data && x.data.error)) throw new Error(x.error ? x.error.message : x.data.error);
          return x.data;
        });
    get.then(saveFile).then(function (warn) {
      btn.disabled = false;
      say(m, warn ? 'Downloaded. ' + warn : 'Downloaded.', warn ? 'warn' : 'ok');
    }).catch(function (e) {
      btn.disabled = false;
      say(m, said(e), 'err');
    });
  }


  // ---- Accounts ----------------------------------------------------------------------
  function growthOf(a) {
    if (a.growth_override != null) return Number(a.growth_override);
    if (a.followers_start != null && a.followers_end != null) return Number(a.followers_end) - Number(a.followers_start);
    return null;
  }
  function signed(n) { return n == null ? '—' : (n > 0 ? '+' : '') + Number(n).toLocaleString('en-GB'); }

  function paintAccounts() {
    paintSteps();
    var box = st.host.querySelector('.rp-accs');
    if (!box) return;
    var ed = editable();
    if (!st.platforms.length) {
      UI.emptyLine(box, 'No accounts.', ed ? 'Add an account' : null, ed ? function () { accountSheet(null, box); } : null);
      return;
    }
    box.innerHTML = '<div class="crm-table softpanel rp-acc-table">' +
      '<div class="crm-head rp-acc-row"><span>Account</span><span>Followers</span><span>Growth</span><span>Figures</span><span></span></div>' +
      st.platforms.map(function (a) {
        return '<div class="crm-row rp-acc-row" data-id="' + esc(a.id) + '">' +
          '<span class="rp-name"><b>' + esc(a.account_name || PLATFORM_WORD[a.platform] || a.platform) + '</b><small>' + esc(PLATFORM_WORD[a.platform] || a.platform) +
            (a.group_label ? ' · ' + esc(a.group_label) : '') + '</small></span>' +
          '<span class="rp-num">' + (a.followers_start != null || a.followers_end != null ? fmt(a.followers_start) + ' to ' + fmt(a.followers_end) : '<span class="mute">—</span>') + '</span>' +
          '<span class="rp-num">' + esc(signed(growthOf(a))) + '</span>' +
          '<span class="rp-figs">' + esc((a.metrics || []).map(function (k) { return METRIC_WORD[k] || k; }).join(', ')) + '</span>' +
          (ed ? rowMenu(['Edit', 'Remove']) : '<span></span>') + '</div>';
      }).join('') + '</div>';
    if (ed) wireRows(box, function (id, act, btn) {
      var a = st.platforms.filter(function (x) { return x.id === id; })[0];
      if (act === 'Edit') accountSheet(a, btn);
      if (act === 'Remove') removeAccount(a, box);
    });
  }

  function rowMenu(items) {
    return '<span class="team-act kmenu-wrap"><button class="kmenu-btn" type="button" aria-label="More" aria-haspopup="true" aria-expanded="false">' + ICON.more + '</button>' +
      '<div class="kmenu" hidden>' + items.map(function (w) {
        return '<button class="kmenu-item' + (w === 'Remove' ? ' is-danger' : '') + '" data-soft type="button" data-act="' + esc(w) + '">' + esc(w) + '</button>';
      }).join('') + '</div></span>';
  }
  function wireRows(box, fn) {
    Array.prototype.forEach.call(box.querySelectorAll('.kmenu-btn'), function (b) {
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        var menu = b.parentNode.querySelector('.kmenu');
        var open = menu.hidden;
        shutMenus();
        menu.hidden = !open; b.setAttribute('aria-expanded', String(open));
        if (open && window.ADspaceMenu) window.ADspaceMenu.place(b, menu);
      });
    });
    Array.prototype.forEach.call(box.querySelectorAll('.kmenu-item[data-act]'), function (it) {
      it.addEventListener('click', function () {
        var row = it.closest('[data-id]');
        shutMenus();
        fn(row.getAttribute('data-id'), it.getAttribute('data-act'), row.querySelector('.kmenu-btn'));
      });
    });
  }
  function shutMenus() {
    if (!st.host) return;
    Array.prototype.forEach.call(st.host.querySelectorAll('.kmenu'), function (m) {
      m.hidden = true;
      var b = m.parentNode.querySelector('.kmenu-btn'); if (b) b.setAttribute('aria-expanded', 'false');
    });
  }
  document.addEventListener('click', function (e) {
    if (st.host && !e.target.closest('.kmenu-wrap')) shutMenus();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutMenus(); });
  if (window.ADspaceMenu) window.ADspaceMenu.onScroll(shutMenus);

  function accountSheet(a, opener) {
    var box = sheetShell('rpAccSheet', 'Account',
      '<section class="fsec"><h4 class="fsec-h">Account</h4>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpAccPlatform">Platform</label><select class="select" id="rpAccPlatform">' +
          PLATFORMS.map(function (p) { return '<option value="' + p[0] + '">' + esc(p[1]) + '</option>'; }).join('') + '</select></div>' +
        '<div><label class="field-label" for="rpAccName">Account name</label><input class="input" id="rpAccName" type="text" placeholder="COMPANY NAME"></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccGroup">Report together as</label><input class="input" id="rpAccGroup" type="text" placeholder="Facebook and Instagram"></div></div></section>' +
      '<section class="fsec"><h4 class="fsec-h">Followers</h4>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpAccStart">At start of period</label><input class="input" id="rpAccStart" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpAccEnd">At end of period</label><input class="input" id="rpAccEnd" data-num="int" type="text" inputmode="numeric"></div></div>' +
        '<details class="fmore" data-none="Worked out from start and end"><summary>Recorded growth</summary>' +
          '<div class="row fgrid"><div><label class="field-label" for="rpAccGrowth">Growth as reported</label><input class="input" id="rpAccGrowth" data-num="int" type="text" inputmode="numeric"></div>' +
          '<div><label class="field-label" for="rpAccWhy">Reason</label><input class="input" id="rpAccWhy" type="text" placeholder="Optional"></div></div></details></section>' +
      '<section class="fsec"><h4 class="fsec-h">Figures reported</h4>' +
        '<div class="rp-ticks">' + METRICS.map(function (mm) {
          return '<label class="tickline"><input type="checkbox" data-metric="' + mm[0] + '"> <span>' + esc(mm[1]) + '</span></label>';
        }).join('') + '</div>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpAccBasis">Engagement rate based on</label><select class="select" id="rpAccBasis">' +
          BASIS.map(function (x) { return '<option value="' + x[0] + '">' + esc(x[1]) + '</option>'; }).join('') + '</select></div>' +
        '<div><label class="field-label" for="rpAccNote">Metric note</label><input class="input" id="rpAccNote" type="text" placeholder="Optional"></div></div></section>' +
      '<details class="fmore" data-none="Optional"><summary>Remarks for this account</summary>' +
        '<div class="row"><div><label class="field-label" for="rpAccSummary">Summary line</label><input class="input" id="rpAccSummary" type="text"></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccWorked">Highlights</label><textarea class="input" id="rpAccWorked" rows="3" placeholder="One point a line"></textarea></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccImprove">Areas for improvement</label><textarea class="input" id="rpAccImprove" rows="3" placeholder="One point a line"></textarea></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccActions">Recommendations</label><textarea class="input" id="rpAccActions" rows="3" placeholder="One point a line"></textarea></div></div></details>',
      FOOT('Save'));
    box.querySelector('h3').textContent = a ? 'Edit account' : 'Add account';
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    v('rpAccPlatform', a ? a.platform : 'instagram'); v('rpAccName', a ? a.account_name : st.client.name);
    v('rpAccGroup', a ? a.group_label : ''); v('rpAccStart', a && a.followers_start); v('rpAccEnd', a && a.followers_end);
    v('rpAccGrowth', a && a.growth_override); v('rpAccWhy', a && a.growth_reason);
    numFields(box);
    v('rpAccBasis', a ? a.er_basis : 'views'); v('rpAccNote', a && a.metric_notes);
    v('rpAccSummary', a && a.summary); v('rpAccWorked', a && a.worked); v('rpAccImprove', a && a.improve); v('rpAccActions', a && a.actions);
    var mets = a ? (a.metrics || []) : ['views', 'engagements'];
    Array.prototype.forEach.call(box.querySelectorAll('[data-metric]'), function (c) { c.checked = mets.indexOf(c.getAttribute('data-metric')) > -1; });
    var folds = box.querySelectorAll('details.fmore');
    if (folds[0]) folds[0].open = Boolean(a && a.growth_override != null);
    if (folds[1]) folds[1].open = Boolean(a && (a.summary || a.worked || a.improve || a.actions));
    if (window.ADspaceForm) box.querySelectorAll('details.fmore').forEach(function (d) { window.ADspaceForm.refresh(d); });
    var sm = box.querySelector('[data-m="sheet"]'); say(sm, '');
    var go = box.querySelector('[data-a="go"]');
    go.onclick = function () {
      var numOf = function (id) { var x = $(id).value.replace(/[, ]/g, ''); return x === '' ? null : Math.round(Number(x)); };
      var metrics = Array.prototype.filter.call(box.querySelectorAll('[data-metric]'), function (c) { return c.checked; })
        .map(function (c) { return c.getAttribute('data-metric'); });
      if (!metrics.length) { say(sm, 'Tick at least one figure.', 'err'); return; }
      var label = $('rpAccGroup').value.trim();
      var row = {
        platform: $('rpAccPlatform').value, account_name: $('rpAccName').value.trim() || null,
        group_label: label || null, group_key: label ? label.toLowerCase().replace(/[^a-z0-9]+/g, '-') : null,
        followers_start: numOf('rpAccStart'), followers_end: numOf('rpAccEnd'),
        growth_override: numOf('rpAccGrowth'), growth_reason: $('rpAccWhy').value.trim() || null,
        metrics: metrics, er_basis: $('rpAccBasis').value || null, metric_notes: $('rpAccNote').value.trim() || null,
        summary: $('rpAccSummary').value.trim() || null, worked: $('rpAccWorked').value.trim() || null,
        improve: $('rpAccImprove').value.trim() || null, actions: $('rpAccActions').value.trim() || null
      };
      go.disabled = true;
      var q = a ? db.from('sm_report_platforms').update(row).eq('id', a.id).select('*')
                : db.from('sm_report_platforms').insert(Object.assign({ report_id: st.open.id, position: st.platforms.length + 1 }, row)).select('*');
      q.then(function (res) {
        go.disabled = false;
        if (res.error || !(res.data || []).length) { say(sm, said(res.error || 'The database refused the change.'), 'err'); return; }
        var saved = res.data[0];
        if (a) st.platforms = st.platforms.map(function (x) { return x.id === a.id ? saved : x; });
        else st.platforms.push(saved);
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        paintEditor();
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  function removeAccount(a, box) {
    var n = st.posts.filter(function (p) { return p.platform_id === a.id; }).length;
    var go = function () {
      var posts = st.posts.filter(function (p) { return p.platform_id === a.id; });
      db.from('sm_report_platforms').delete().eq('id', a.id).select('id').then(function (res) {
        if (res.error || !(res.data || []).length) { say(st.host.querySelector('[data-m="head"]'), said(res.error || 'Not removed. The database refused the request.'), 'err'); return; }
        st.platforms = st.platforms.filter(function (x) { return x.id !== a.id; });
        st.posts = st.posts.filter(function (p) { return p.platform_id !== a.id; });
        paintEditor();
        undoBar((a.account_name || PLATFORM_WORD[a.platform]) + ' removed.', st.host.querySelector('.rp-accs'), function () {
          db.from('sm_report_platforms').insert(a).select('*').then(function (x) {
            if (x.error) return;
            st.platforms.push(x.data[0]);
            st.platforms.sort(function (p, q) { return p.position - q.position; });
            if (!posts.length) { paintEditor(); return; }
            db.from('sm_report_posts').insert(posts).select('*').then(function (y) {
              if (!y.error) st.posts = st.posts.concat(y.data || []);
              paintEditor();
            });
          });
        });
      });
    };
    if (!n) { go(); return; }
    window.ADspaceConfirm.ask({ title: 'Remove this account?', body: 'Its ' + n + ' post' + (n === 1 ? '' : 's') + ' go with it.', go: 'Remove', tone: 'danger' }, go);
  }

  var undoTimer = null;
  function undoBar(text, host, undo) {
    if (!host || !host.parentNode) return;
    var bar = host.parentNode.querySelector(':scope > .undobar-here');
    if (!bar) { bar = document.createElement('div'); bar.className = 'undobar undobar-here'; host.parentNode.insertBefore(bar, host.nextSibling); }
    bar.hidden = false;
    bar.innerHTML = '<span>' + esc(text) + '</span><button class="btn btn-sm" type="button">Undo</button>';
    bar.querySelector('button').addEventListener('click', function () { if (bar.parentNode) bar.parentNode.removeChild(bar); undo(); });
    clearTimeout(undoTimer);
    undoTimer = setTimeout(function () { if (bar.parentNode) bar.parentNode.removeChild(bar); }, 8000);
  }

  // ---- Posts ------------------------------------------------------------------------------
  function postName(p) {
    if (p.title && String(p.title).trim()) return String(p.title).trim();
    var d = p.posted_on ? new Date(p.posted_on + 'T00:00:00') : null;
    return (FORMAT_WORD[p.content_type] || 'Post') + (d ? ', ' + d.getDate() + ' ' + MON[d.getMonth()] : '');
  }
  function paintPosts() {
    paintSteps();
    var box = st.host.querySelector('.rp-posts');
    if (!box) return;
    var ed = editable();
    if (!st.platforms.length) { UI.emptyLine(box, 'Add an account first.'); return; }
    if (!st.posts.length) {
      UI.emptyLine(box, 'No posts.', ed ? 'Add a post' : null, ed ? function () { postSheet(null, box); } : null);
      return;
    }
    box.innerHTML = st.platforms.map(function (a) {
      var posts = st.posts.filter(function (p) { return p.platform_id === a.id; });
      if (!posts.length) return '';
      var m = (a.metrics || []).slice(0, 2);
      while (m.length < 2) m.push(null);
      return '<div class="rp-postgroup"><p class="rp-group">' + esc(a.account_name || PLATFORM_WORD[a.platform]) + ' · ' + esc(PLATFORM_WORD[a.platform] || a.platform) +
        ' <span class="mute">' + posts.length + ' post' + (posts.length === 1 ? '' : 's') + '</span></p>' +
        '<div class="crm-table softpanel rp-post-table">' +
        '<div class="crm-head rp-post-row"><span></span><span>Post</span><span>Date</span><span>' + esc(m[0] ? METRIC_WORD[m[0]] : '') + '</span><span>' + esc(m[1] ? METRIC_WORD[m[1]] : '') + '</span><span></span></div>' +
        posts.map(function (p) {
          return '<div class="crm-row rp-post-row" data-id="' + esc(p.id) + '">' +
            '<span class="rp-thumb">' + (p.thumb_data ? '<img src="' + esc(p.thumb_data) + '" alt="">' : '') + '</span>' +
            '<span class="rp-name"><b>' + esc(postName(p)) + '</b><small>' + esc([FORMAT_WORD[p.content_type] && p.content_type ? FORMAT_WORD[p.content_type] : '', p.notable ? 'Remarked' : ''].filter(Boolean).join(' · ')) + '</small></span>' +
            '<span class="rp-date">' + esc(dayWord(p.posted_on)) + '</span>' +
            '<span class="rp-num">' + (m[0] ? fmt(p[m[0]]) : '') + '</span>' +
            '<span class="rp-num">' + (m[1] ? fmt(p[m[1]]) : '') + '</span>' +
            (ed ? rowMenu(['Edit', 'Remove']) : '<span></span>') + '</div>';
        }).join('') + '</div></div>';
    }).join('');
    if (ed) wireRows(box, function (id, act, btn) {
      var p = st.posts.filter(function (x) { return x.id === id; })[0];
      if (act === 'Edit') postSheet(p, btn);
      if (act === 'Remove') removePost(p);
    });
  }

  function removePost(p) {
    db.from('sm_report_posts').delete().eq('id', p.id).select('id').then(function (res) {
      if (res.error || !(res.data || []).length) { say(st.host.querySelector('[data-m="head"]'), said(res.error || 'Not removed. The database refused the request.'), 'err'); return; }
      st.posts = st.posts.filter(function (x) { return x.id !== p.id; });
      paintPosts();
      undoBar(postName(p) + ' removed.', st.host.querySelector('.rp-posts'), function () {
        db.from('sm_report_posts').insert(p).select('*').then(function (x) {
          if (!x.error) { st.posts.push(x.data[0]); sortPosts(); paintPosts(); }
        });
      });
    });
  }
  function sortPosts() {
    st.posts.sort(function (a, b) {
      return String(a.posted_on || '9999').localeCompare(String(b.posted_on || '9999')) || (a.position - b.position);
    });
  }

  /* A thumbnail is kept in the row as a small JPEG, 320px on its longer
     side: the PDF is drawn in the browser, and a picture on the CDN cannot
     be read back into the file across origins. */
  function shrink(file) {
    return new Promise(function (ok, bad) {
      var img = new Image();
      var url = URL.createObjectURL(file);
      img.onload = function () {
        var s = Math.min(1, 320 / Math.max(img.naturalWidth, img.naturalHeight));
        var c = document.createElement('canvas');
        c.width = Math.max(1, Math.round(img.naturalWidth * s));
        c.height = Math.max(1, Math.round(img.naturalHeight * s));
        var x = c.getContext('2d');
        x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height);
        x.drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(url);
        ok(c.toDataURL('image/jpeg', 0.82));
      };
      img.onerror = function () { URL.revokeObjectURL(url); bad(new Error('That file is not an image this browser can read.')); };
      img.src = url;
    });
  }

  function postSheet(p, opener) {
    var box = sheetShell('rpPostSheet', 'Post',
      '<section class="fsec"><h4 class="fsec-h">Post</h4>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpPostAcc">Account</label><select class="select" id="rpPostAcc"></select></div>' +
        '<div><label class="field-label" for="rpPostDate">Date</label><input class="input" id="rpPostDate" aria-required="true" type="date"></div></div>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpPostTitle">Title</label><input class="input" id="rpPostTitle" type="text" placeholder="Optional"></div>' +
        '<div><label class="field-label" for="rpPostFormat">Format</label><select class="select" id="rpPostFormat">' +
          FORMATS.map(function (f) { return '<option value="' + f[0] + '">' + esc(f[1]) + '</option>'; }).join('') + '</select></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpPostThumb">Thumbnail</label>' +
          '<div class="rp-thumbfield"><span class="rp-thumb rp-thumb-lg" id="rpPostThumbShow"></span>' +
          '<input class="input" id="rpPostThumb" type="file" accept="image/*"><button class="btn btn-sm btn-quiet" type="button" id="rpPostThumbX">Remove</button></div></div></div></section>' +
      '<section class="fsec"><h4 class="fsec-h">Figures</h4><div class="row fgrid-3 fgrid" id="rpPostFigs"></div></section>' +
      '<section class="fsec"><h4 class="fsec-h">Remarks</h4>' +
        '<div class="row"><div><label class="field-label" for="rpPostNotable">Why it stood out</label><textarea class="input" id="rpPostNotable" rows="2"></textarea></div></div>' +
        '<details class="fmore" data-none="Caption, link, remarks"><summary>More details</summary>' +
          '<div class="row"><div><label class="field-label" for="rpPostCaption">Caption</label><textarea class="input" id="rpPostCaption" rows="3"></textarea></div></div>' +
          '<div class="row"><div><label class="field-label" for="rpPostUrl">Link</label><input class="input" id="rpPostUrl" type="url" placeholder="https://"></div></div>' +
          '<div class="row"><div><label class="field-label" for="rpPostObs">Remarks in the appendix</label><input class="input" id="rpPostObs" type="text"></div></div>' +
        '</details></section>',
      FOOT('Save'));
    box.querySelector('h3').textContent = p ? 'Edit post' : 'Add post';
    var acc = $('rpPostAcc');
    acc.innerHTML = st.platforms.map(function (a) {
      return '<option value="' + esc(a.id) + '">' + esc((a.account_name || '') + ' · ' + (PLATFORM_WORD[a.platform] || a.platform)) + '</option>';
    }).join('');
    acc.value = p ? p.platform_id : (st.lastAcc && st.platforms.some(function (a) { return a.id === st.lastAcc; }) ? st.lastAcc : st.platforms[0].id);
    var thumb = p ? p.thumb_data : null;
    var showThumb = function () {
      $('rpPostThumbShow').innerHTML = thumb ? '<img src="' + esc(thumb) + '" alt="">' : '';
      $('rpPostThumbX').hidden = !thumb;
    };
    var figs = function () {
      var a = st.platforms.filter(function (x) { return x.id === acc.value; })[0] || {};
      var keep = {};
      Array.prototype.forEach.call(box.querySelectorAll('[data-fig]'), function (i) { keep[i.getAttribute('data-fig')] = i.value; });
      $('rpPostFigs').innerHTML = (a.metrics || []).map(function (k) {
        return '<div><label class="field-label" for="rpFig_' + k + '">' + esc(METRIC_WORD[k] || k) + '</label>' +
          '<input class="input" id="rpFig_' + k + '" data-fig="' + k + '" data-num="int" type="text" inputmode="numeric"></div>';
      }).join('');
      (a.metrics || []).forEach(function (k) {
        $('rpFig_' + k).value = keep[k] != null ? keep[k] : (p && p[k] != null ? p[k] : '');
      });
      numFields($('rpPostFigs'));
    };
    acc.onchange = figs;
    $('rpPostFigs').innerHTML = '';
    figs();
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    v('rpPostDate', p ? p.posted_on : (st.lastDate || st.open.period_start));
    v('rpPostTitle', p && p.title); v('rpPostFormat', p ? (p.content_type || '') : (st.lastFormat || ''));
    v('rpPostNotable', p && p.notable); v('rpPostCaption', p && p.caption); v('rpPostUrl', p && p.url); v('rpPostObs', p && p.observation);
    $('rpPostThumb').value = '';
    showThumb();
    var sm = box.querySelector('[data-m="sheet"]'); say(sm, '');
    $('rpPostThumb').onchange = function () {
      var f = this.files && this.files[0];
      if (!f) return;
      shrink(f).then(function (d) { thumb = d; showThumb(); say(sm, ''); }, function (e) { say(sm, e.message, 'err'); });
    };
    $('rpPostThumbX').onclick = function () { thumb = null; $('rpPostThumb').value = ''; showThumb(); };
    var go = box.querySelector('[data-a="go"]');
    go.onclick = function () {
      var row = {
        platform_id: acc.value, posted_on: $('rpPostDate').value || null,
        title: $('rpPostTitle').value.trim() || null, content_type: $('rpPostFormat').value || null,
        thumb_data: thumb || null, notable: $('rpPostNotable').value.trim() || null,
        caption: $('rpPostCaption').value.trim() || null, url: $('rpPostUrl').value.trim() || null,
        observation: $('rpPostObs').value.trim() || null
      };
      var badFig = null;
      Array.prototype.forEach.call(box.querySelectorAll('[data-fig]'), function (i) {
        var raw = i.value.replace(/[, ]/g, '');
        if (raw !== '' && !/^\d+$/.test(raw)) badFig = badFig || i;
        row[i.getAttribute('data-fig')] = raw === '' ? null : Number(raw);
      });
      if (badFig) { say(sm, 'A figure is a whole number.', 'err'); badFig.focus(); return; }
      if (!row.posted_on) { say(sm, 'A date is required.', 'err'); $('rpPostDate').focus(); return; }
      go.disabled = true;
      var q = p ? db.from('sm_report_posts').update(row).eq('id', p.id).select('*')
                : db.from('sm_report_posts').insert(Object.assign({ report_id: st.open.id, position: st.posts.length + 1 }, row)).select('*');
      q.then(function (res) {
        go.disabled = false;
        if (res.error || !(res.data || []).length) { say(sm, said(res.error || 'The database refused the change.'), 'err'); return; }
        var saved = res.data[0];
        if (p) st.posts = st.posts.map(function (x) { return x.id === p.id ? saved : x; });
        else st.posts.push(saved);
        st.lastAcc = row.platform_id; st.lastDate = row.posted_on; st.lastFormat = row.content_type || '';
        sortPosts();
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        paintPosts();
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  /* Rows pasted from a spreadsheet: a header row naming the columns, then a
     post a row. The platforms' own export names are read as they come. */
  var HEAD = [
    [/^(date|posting date|posted|publish(ed)? (date|time)|date posted)$/, 'posted_on'],
    [/^(post|title|name|post title)$/, 'title'],
    [/^(format|type|content type|post type)$/, 'content_type'],
    [/^(link|url|permalink|post link)$/, 'url'],
    [/^(caption|description|text)$/, 'caption'],
    [/^(views?|impressions ?\/ ?views|views ?\/ ?impressions|video views|plays)$/, 'views'],
    [/^reach$/, 'reach'], [/^impressions$/, 'impressions'],
    [/^(interactions|post interactions)$/, 'interactions'], [/^(engagements?|engagement)$/, 'engagements'],
    [/^(likes|reactions)$/, 'likes'], [/^comments$/, 'comments'], [/^shares$/, 'shares'], [/^(saves|saved|favourites|favorites)$/, 'saves']
  ];
  var MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11 };
  function readDate(s, year) {
    s = String(s || '').trim();
    var m;
    if ((m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(s))) return ymd(new Date(+m[1], +m[2] - 1, +m[3]));
    if ((m = /^(\d{1,2})[\/.](\d{1,2})[\/.](\d{2,4})/.exec(s))) {
      var y = +m[3]; if (y < 100) y += 2000;
      return ymd(new Date(y, +m[2] - 1, +m[1]));
    }
    if ((m = /^(\d{1,2})[\s-]+([A-Za-z]{3,9})[\s-]*(\d{4})?/.exec(s)) && MONTHS[m[2].toLowerCase().slice(0, m[2].toLowerCase().indexOf('sept') === 0 ? 4 : 3)] != null) {
      return ymd(new Date(m[3] ? +m[3] : year, MONTHS[m[2].toLowerCase().slice(0, m[2].toLowerCase().indexOf('sept') === 0 ? 4 : 3)], +m[1]));
    }
    if ((m = /^([A-Za-z]{3,9})\s+(\d{1,2}),?\s*(\d{4})?/.exec(s)) && MONTHS[m[1].toLowerCase().slice(0, 3)] != null) {
      return ymd(new Date(m[3] ? +m[3] : year, MONTHS[m[1].toLowerCase().slice(0, 3)], +m[2]));
    }
    return null;
  }
  function parseRows(text, year) {
    var lines = String(text || '').replace(/\r/g, '').split('\n').filter(function (l) { return l.trim(); });
    if (lines.length < 2) return { error: 'Paste a header row and at least one post.' };
    var sep = lines[0].indexOf('\t') > -1 ? '\t' : ',';
    var head = lines[0].split(sep).map(function (h) {
      var k = h.trim().toLowerCase().replace(/\s+/g, ' ');
      var hit = HEAD.filter(function (x) { return x[0].test(k); })[0];
      return hit ? hit[1] : null;
    });
    if (head.indexOf('posted_on') < 0) return { error: 'The header row needs a Date column.' };
    var rows = [], skipped = 0;
    lines.slice(1).forEach(function (l) {
      var cells = l.split(sep), row = {}, ok = true;
      head.forEach(function (k, i) {
        if (!k) return;
        var v = (cells[i] || '').trim();
        if (k === 'posted_on') { row.posted_on = readDate(v, year); if (!row.posted_on) ok = false; return; }
        if (['title', 'url', 'caption'].indexOf(k) > -1) { row[k] = v || null; return; }
        if (k === 'content_type') { var f = v.toLowerCase(); row.content_type = FORMAT_WORD[f] ? f : null; return; }
        var n = v.replace(/[, ]/g, '');
        row[k] = n === '' || n === '-' ? null : (/^\d+$/.test(n) ? Number(n) : (/^\d+(\.\d+)?k$/i.test(n) ? Math.round(parseFloat(n) * 1000) : null));
      });
      if (ok) rows.push(row); else skipped++;
    });
    return { rows: rows, skipped: skipped, columns: head.filter(Boolean) };
  }

  function pasteSheet(opener) {
    var box = sheetShell('rpPasteSheet', 'Import from spreadsheet',
      '<section class="fsec"><div class="row"><div><label class="field-label" for="rpPasteAcc">Account</label><select class="select" id="rpPasteAcc"></select></div></div>' +
      '<div class="row"><div><label class="field-label" for="rpPasteText">Copy the rows from your spreadsheet, with the header row, and paste them here</label>' +
        '<textarea class="input rp-paste" id="rpPasteText" rows="8" placeholder="Date&#9;Title&#9;Views&#9;Interactions"></textarea></div></div>' +
      '<p class="rp-paste-sum" id="rpPasteSum"></p></section>', FOOT('Add posts'));
    var acc = $('rpPasteAcc');
    acc.innerHTML = st.platforms.map(function (a) {
      return '<option value="' + esc(a.id) + '">' + esc((a.account_name || '') + ' · ' + (PLATFORM_WORD[a.platform] || a.platform)) + '</option>';
    }).join('');
    $('rpPasteText').value = '';
    var sum = $('rpPasteSum'), sm = box.querySelector('[data-m="sheet"]');
    sum.textContent = ''; say(sm, '');
    var year = Number(String(st.open.period_start).slice(0, 4));
    var go = box.querySelector('[data-a="go"]');
    var read = function () {
      var out = parseRows($('rpPasteText').value, year);
      if (out.error) { sum.textContent = $('rpPasteText').value.trim() ? out.error : ''; go.disabled = true; return out; }
      sum.textContent = out.rows.length + ' post' + (out.rows.length === 1 ? '' : 's') + ' ready' +
        (out.skipped ? ', ' + out.skipped + ' without a date skipped' : '') + '. Columns: ' +
        out.columns.map(function (c) { return c === 'posted_on' ? 'Date' : c === 'content_type' ? 'Format' : (METRIC_WORD[c] || c.charAt(0).toUpperCase() + c.slice(1)); }).join(', ') + '.';
      go.disabled = !out.rows.length;
      return out;
    };
    $('rpPasteText').oninput = read;
    go.disabled = true;
    go.onclick = function () {
      var out = read();
      if (!out.rows || !out.rows.length) return;
      var n = st.posts.length;
      var rows = out.rows.map(function (r, i) { return Object.assign({ report_id: st.open.id, platform_id: acc.value, position: n + i + 1 }, r); });
      go.disabled = true;
      db.from('sm_report_posts').insert(rows).select('*').then(function (res) {
        go.disabled = false;
        if (res.error) { say(sm, said(res.error), 'err'); return; }
        st.posts = st.posts.concat(res.data || []);
        sortPosts();
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        paintPosts();
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  // ---- The report's commentary ---------------------------------------------------------------
  /* Four fields, the same for both kinds: a summary, what stood out, what to
     improve, and what comes next. A summary written as an executive summary
     before this form existed is read into the one field. The pages already
     carry their own headings, so no title or headline is asked for. */
  function paintText() {
    var box = st.host.querySelector('.rp-text');
    if (!box) return;
    var r = st.open, ins = r.insights || {}, ads = r.kind === 'ads';
    var fields = TEXT[ads ? 'ads' : 'social'];
    var valOf = function (k) {
      if (k !== 'intro') return ins[k];
      return [r.intro, ins.executive_summary].filter(function (x) { return String(x || '').trim(); }).join('\n\n');
    };
    var more = ads ? [] : TEXT_MORE;
    if (!editable()) {
      var rows = fields.concat(more).map(function (x) { return [x[1], valOf(x[0])]; })
        .filter(function (x) { return String(x[1] || '').trim(); });
      if (!rows.length) { UI.emptyLine(box, 'No commentary.'); return; }
      box.innerHTML = '<div class="ovcard"><dl class="ovfacts rp-facts">' + rows.map(function (x) {
        return '<dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]).replace(/\n/g, '<br>') + '</dd>';
      }).join('') + '</dl></div>';
      return;
    }
    var area = function (x) {
      return '<div class="row"><div><label class="field-label" for="rpT_' + x[0] + '">' + esc(x[1]) + '</label>' +
        '<textarea class="input" id="rpT_' + x[0] + '" rows="' + (x[3] || 3) + '"' + (x[2] ? ' placeholder="' + esc(x[2]) + '"' : '') + '></textarea></div></div>';
    };
    box.innerHTML = '<section class="panel rp-form">' +
      '<p class="rp-hint">' + (ads ? 'One point a line. Start a line with a dash for a sub-point.' : 'One point a line.') + '</p>' +
      fields.map(area).join('') +
      (more.length ? '<details class="fmore" data-none="Optional"><summary>More sections</summary>' +
        more.map(function (x) { return area([x[0], x[1], 'One point a line', 3]); }).join('') + '</details>' : '') +
      '<div class="rp-stepfoot"><button class="btn btn-primary" type="button" data-a="savenext">Save and continue</button>' +
        '<button class="btn" type="button" data-a="savetext">Save</button><div class="msg" data-m="text"></div></div></section>';
    fields.concat(more).forEach(function (x) { $('rpT_' + x[0]).value = valOf(x[0]) || ''; });
    var fold = box.querySelector('details.fmore');
    if (fold) fold.open = more.some(function (x) { return String(ins[x[0]] || '').trim(); });
    if (window.ADspaceForm) window.ADspaceForm.scan(box);
    var m = box.querySelector('[data-m="text"]');
    var save = function (btn, then) {
      var insights = {};
      Object.keys(ins).forEach(function (k) { insights[k] = ins[k]; });
      delete insights.executive_summary;
      fields.concat(more).forEach(function (x) {
        if (x[0] === 'intro') return;
        var v = $('rpT_' + x[0]).value.trim();
        if (v) insights[x[0]] = v; else delete insights[x[0]];
      });
      var row = { intro: $('rpT_intro').value.trim() || null, headline: null, insights: insights };
      btn.disabled = true;
      db.from('sm_reports').update(row).eq('id', r.id).select('*').then(function (res) {
        btn.disabled = false;
        if (res.error || !(res.data || []).length) { say(m, said(res.error || 'The database refused the change.'), 'err'); return; }
        st.open = res.data[0];
        paintSteps();
        if (then) { then(); return; }
        say(m, 'Saved.', 'ok');
      });
    };
    var sb = box.querySelector('[data-a="savetext"]'), sn = box.querySelector('[data-a="savenext"]');
    sb.addEventListener('click', function () { save(sb); });
    sn.addEventListener('click', function () { save(sn, function () { goStep('check'); }); });
  }

  // ---- The advertising report ------------------------------------------------------------
  /* An advertising report is the account's figures for the period, one row
     an ad and objective, and the team's words. The account's reach is typed,
     because it cannot be added up from the ads; impressions and spend are
     summed from the ads where nobody typed them. */
  var OBJECTIVES = [['leads', 'Leads', 'Leads'], ['messaging', 'Messaging', 'Messaging conversations'], ['sales', 'Sales', 'Purchases'],
                    ['traffic', 'Traffic', 'Link clicks'], ['engagement', 'Engagement', 'Post engagements'],
                    ['awareness', 'Awareness', 'Reach'], ['app', 'App promotion', 'App installs']];
  var OBJ_WORD = {};
  OBJECTIVES.forEach(function (o) { OBJ_WORD[o[0]] = o[1]; });
  var RESULT_TYPES = ['Leads', 'Messaging conversations', 'Purchases', 'Link clicks', 'Landing page views', 'Post engagements',
                      'Engagement', 'ThruPlays', 'Ad recall lift', 'Reach', 'Impressions', 'App installs'];
  var AGE_BANDS = ['18-24', '25-34', '35-44', '45-54', '55-64', '65+'];
  var RET = [['p25', '25%'], ['p50', '50%'], ['p75', '75%'], ['p95', '95%'], ['p100', '100%']];
  function money2(v) { return v == null || v === '' || isNaN(Number(v)) ? '—' : (String(st.client && st.client.market || '').toUpperCase() === 'SG' ? 'S$ ' : 'RM ') + Number(v).toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  function numIn(v) {
    var x = String(v == null ? '' : v).replace(/RM|MYR|SGD|S\$|%|,|\s/gi, '');
    return x === '' || x === '-' || isNaN(Number(x)) ? null : Number(x);
  }
  function playIn(v) {
    var x = String(v == null ? '' : v).trim();
    var m = /^(\d+):(\d{1,2})$/.exec(x);
    if (m) return Number(m[1]) * 60 + Number(m[2]);
    return numIn(x);
  }
  /* A figure is shown as it is read: a count with thousands separators, a
     percentage to one decimal, money in the client's currency (the user,
     2026-09-25). Each field is tidied when it is left and when it is filled;
     numIn reads all three shapes back, so nothing typed is lost. */
  function numOut(kind, x) {
    if (x === null) return '';
    if (kind === 'money') return money2(x);
    if (kind === 'pct') return (Math.round(x * 10) / 10).toLocaleString('en-GB', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + '%';
    return x.toLocaleString('en-GB', { maximumFractionDigits: 2 });
  }
  function numFields(root) {
    Array.prototype.forEach.call(root.querySelectorAll('input[data-num]'), function (i) {
      var kind = i.getAttribute('data-num');
      var tidy = function () { var x = numIn(i.value); if (x !== null) i.value = numOut(kind, x); };
      tidy();
      if (!i.getAttribute('data-numw')) { i.setAttribute('data-numw', '1'); i.addEventListener('blur', tidy); }
    });
  }
  function playOut(v) { if (v == null || v === '') return ''; var s = Math.round(Number(v)); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); }
  function adCpr(a) {
    if (a.cpr != null && a.cpr !== '') return Number(a.cpr);
    var reach = /reach/i.test(String(a.result_label || ''));
    if (a.spend == null || !Number(a.results)) return null;
    return Number(a.spend) / Number(a.results) * (reach ? 1000 : 1);
  }
  function sortAds() {
    var ord = {}; OBJECTIVES.forEach(function (o, i) { ord[o[0]] = i; });
    st.ads.sort(function (a, b) { return (ord[a.objective] - ord[b.objective]) || (a.position - b.position); });
  }

  /* The account's figures: typed where they cannot be added up, the rest
     summed from the ads; the previous period where this is not the first
     month, carried forward from the last advertising report. */
  function paintTotals() {
    var box = st.host.querySelector('.rp-totals');
    if (!box) return;
    var r = st.open, t = r.ads_totals || {};
    var sumSpend = st.ads.reduce(function (s0, a) { return s0 + (Number(a.spend) || 0); }, 0);
    var sumImpr = st.ads.reduce(function (s0, a) { return s0 + (Number(a.impressions) || 0); }, 0);
    var objs = OBJECTIVES.filter(function (o) { return st.ads.some(function (a) { return a.objective === o[0]; }); });
    if (!editable()) {
      var rows = [['First month', r.first_month ? 'Yes, with the reading guidance' : 'No, compared with the previous period'],
        ['Total reach', fmt(t.reach)], ['Total impressions', t.impressions != null ? fmt(t.impressions) : fmt(sumImpr) + ' (from the ads)'],
        ['Amount spent', t.spend != null ? money2(t.spend) : money2(sumSpend) + ' (from the ads)']];
      if (!r.first_month) rows.push(['Previous period', t.prev_start ? periodWord(t.prev_start, t.prev_end) : '—'],
        ['Previous reach', fmt(t.prev_reach)], ['Previous impressions', fmt(t.prev_impressions)], ['Previous amount spent', money2(t.prev_spend)]);
      box.innerHTML = '<div class="ovcard"><dl class="ovfacts rp-facts">' + rows.map(function (x) {
        return '<dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd>';
      }).join('') + '</dl></div>';
      return;
    }
    box.innerHTML = '<section class="panel rp-form">' +
      '<label class="tickline"><input type="checkbox" id="rpFirst"> First month of ads, with no comparison</label>' +
      '<section class="fsec"><h4 class="fsec-h">This period</h4>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpTReach">Total reach</label><input class="input" id="rpTReach" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpTImpr">Total impressions</label><input class="input" id="rpTImpr" data-num="int" type="text" inputmode="numeric" placeholder="' + esc(fmt(sumImpr)) + ' from the ads"></div>' +
        '<div><label class="field-label" for="rpTSpend">Amount spent</label><input class="input" id="rpTSpend" data-num="money" type="text" inputmode="decimal" placeholder="' + esc(money2(sumSpend)) + ' from the ads"></div></div></section>' +
      '<section class="fsec" id="rpPrevSec"><h4 class="fsec-h">Previous period</h4>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpPStart">Start</label><input class="input" id="rpPStart" type="date"></div>' +
        '<div><label class="field-label" for="rpPEnd">End</label><input class="input" id="rpPEnd" type="date"></div></div>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpPReach">Reach</label><input class="input" id="rpPReach" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpPImpr">Impressions</label><input class="input" id="rpPImpr" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpPSpend">Amount spent</label><input class="input" id="rpPSpend" data-num="money" type="text" inputmode="decimal"></div></div></section>' +
      (objs.length ? '<details class="fmore" data-none="Added up from the ads" data-some="Typed for some objectives"><summary>Results by objective</summary>' +
        objs.map(function (o) {
          return '<div class="row fgrid"><div><label class="field-label" for="rpGR_' + o[0] + '">' + esc(o[1]) + ' results</label>' +
            '<input class="input" id="rpGR_' + o[0] + '" data-gres="' + o[0] + '" data-num="int" type="text" inputmode="numeric" placeholder="From the ads"></div>' +
            '<div><label class="field-label" for="rpGL_' + o[0] + '">Result type</label><input class="input" id="rpGL_' + o[0] + '" data-glab="' + o[0] + '" type="text" list="rpResultTypes"></div></div>';
        }).join('') + '</details>' : '') +
      '<datalist id="rpResultTypes">' + RESULT_TYPES.map(function (x) { return '<option value="' + esc(x) + '">'; }).join('') + '</datalist>' +
      '<div class="rp-stepfoot"><button class="btn btn-primary" type="button" data-a="savenext">Save and continue</button>' +
        '<button class="btn" type="button" data-a="savetotals">Save</button><div class="msg" data-m="totals"></div></div></section>';
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    $('rpFirst').checked = !!r.first_month;
    v('rpTReach', t.reach); v('rpTImpr', t.impressions); v('rpTSpend', t.spend);
    v('rpPStart', t.prev_start); v('rpPEnd', t.prev_end); v('rpPReach', t.prev_reach); v('rpPImpr', t.prev_impressions); v('rpPSpend', t.prev_spend);
    objs.forEach(function (o) {
      var gg = (t.groups || {})[o[0]] || {};
      v('rpGR_' + o[0], gg.results); v('rpGL_' + o[0], gg.label);
    });
    numFields(box);
    var showPrev = function () { $('rpPrevSec').hidden = $('rpFirst').checked; };
    $('rpFirst').onchange = showPrev; showPrev();
    if (window.ADspaceForm) window.ADspaceForm.scan(box);
    var m = box.querySelector('[data-m="totals"]');
    var saveTotals = function (btn, then) {
      var out = {}, bad = null;
      [['reach', 'rpTReach'], ['impressions', 'rpTImpr'], ['spend', 'rpTSpend'], ['prev_reach', 'rpPReach'], ['prev_impressions', 'rpPImpr'], ['prev_spend', 'rpPSpend']].forEach(function (f) {
        var raw = $(f[1]).value.trim();
        if (!raw) return;
        var n = numIn(raw);
        if (n === null || n < 0) { bad = bad || $(f[1]); return; }
        out[f[0]] = n;
      });
      if (bad) { say(m, 'A figure is a number.', 'err'); bad.focus(); return; }
      if ($('rpPStart').value) out.prev_start = $('rpPStart').value;
      if ($('rpPEnd').value) out.prev_end = $('rpPEnd').value;
      if (out.prev_start && out.prev_end && out.prev_end < out.prev_start) { say(m, 'The previous period must end on or after the day it starts.', 'err'); return; }
      if (t.prev_groups) out.prev_groups = t.prev_groups;
      var groups = {};
      Array.prototype.forEach.call(box.querySelectorAll('[data-gres]'), function (i) {
        var k = i.getAttribute('data-gres'), n = numIn(i.value), lab = $('rpGL_' + k).value.trim();
        if (n !== null || lab) groups[k] = { results: n, label: lab || null };
      });
      if (Object.keys(groups).length) out.groups = groups;
      btn.disabled = true;
      db.from('sm_reports').update({ ads_totals: out, first_month: $('rpFirst').checked }).eq('id', r.id).select('*').then(function (res) {
        btn.disabled = false;
        if (res.error || !(res.data || []).length) { say(m, said(res.error || 'The database refused the change.'), 'err'); return; }
        st.open = res.data[0];
        paintSteps();
        if (then) { then(); return; }
        say(m, 'Saved.', 'ok');
      });
    };
    var sb = box.querySelector('[data-a="savetotals"]'), sn = box.querySelector('[data-a="savenext"]');
    sb.addEventListener('click', function () { saveTotals(sb); });
    sn.addEventListener('click', function () { saveTotals(sn, function () { goStep('ads'); }); });
  }

  function paintAds() {
    paintSteps();
    var box = st.host.querySelector('.rp-ads');
    if (!box) return;
    var ed = editable();
    if (!st.ads.length) {
      UI.emptyLine(box, 'No ads.', ed ? 'Add an ad' : null, ed ? function () { adSheet(null, box); } : null);
      return;
    }
    box.innerHTML = OBJECTIVES.map(function (o) {
      var ads = st.ads.filter(function (a) { return a.objective === o[0]; });
      if (!ads.length) return '';
      var spend = ads.reduce(function (s0, a) { return s0 + (Number(a.spend) || 0); }, 0);
      return '<div class="rp-postgroup"><p class="rp-group">' + esc(o[1]) +
        ' <span class="mute">' + ads.length + ' ad' + (ads.length === 1 ? '' : 's') + ' · ' + esc(money2(spend)) + '</span></p>' +
        '<div class="crm-table softpanel rp-ad-table">' +
        '<div class="crm-head rp-ad-row"><span></span><span>Ad</span><span>Amount spent</span><span>Results</span><span>Cost per result</span><span></span></div>' +
        ads.map(function (a) {
          var sub = [a.result_label, a.audience ? a.audience + ' audience' : '', a.starts_on ? dayWord(a.starts_on) + (a.ends_on ? ' to ' + dayWord(a.ends_on) : '') : ''].filter(Boolean).join(' · ');
          var c = adCpr(a);
          return '<div class="crm-row rp-ad-row" data-id="' + esc(a.id) + '">' +
            '<span class="rp-thumb">' + (a.thumb_data ? '<img src="' + esc(a.thumb_data) + '" alt="">' : '') + '</span>' +
            '<span class="rp-name"><b>' + esc(a.name) + '</b><small>' + esc(sub) + '</small></span>' +
            '<span class="rp-num">' + esc(money2(a.spend)) + '</span>' +
            '<span class="rp-num">' + esc(fmt(a.results)) + '</span>' +
            '<span class="rp-num">' + esc(c == null ? '—' : money2(c)) + '</span>' +
            (ed ? rowMenu(['Edit', 'Duplicate', 'Remove']) : '<span></span>') + '</div>';
        }).join('') + '</div></div>';
    }).join('');
    if (ed) wireRows(box, function (id, act, btn) {
      var a = st.ads.filter(function (x) { return x.id === id; })[0];
      if (act === 'Edit') adSheet(a, btn);
      if (act === 'Duplicate') adSheet(Object.assign({}, a, { id: null, objective: a.objective }), btn, true);
      if (act === 'Remove') removeAd(a);
    });
  }

  function removeAd(a) {
    db.from('sm_report_ads').delete().eq('id', a.id).select('id').then(function (res) {
      if (res.error || !(res.data || []).length) { say(st.host.querySelector('[data-m="head"]'), said(res.error || 'Not removed. The database refused the request.'), 'err'); return; }
      st.ads = st.ads.filter(function (x) { return x.id !== a.id; });
      paintAds(); paintTotals();
      undoBar(a.name + ' removed.', st.host.querySelector('.rp-ads'), function () {
        db.from('sm_report_ads').insert(a).select('*').then(function (x) {
          if (!x.error) { st.ads.push(x.data[0]); sortAds(); paintAds(); paintTotals(); }
        });
      });
    });
  }

  function adSheet(a, opener, copy) {
    var box = sheetShell('rpAdSheet', 'Ad',
      '<section class="fsec"><h4 class="fsec-h">Ad</h4>' +
        '<div class="row"><div><label class="field-label" for="rpAdName">Ad name</label><input class="input" id="rpAdName" aria-required="true" type="text" placeholder="As in Ads Manager"></div></div>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpAdObj">Objective</label><select class="select" id="rpAdObj">' +
          OBJECTIVES.map(function (o) { return '<option value="' + o[0] + '">' + esc(o[1]) + '</option>'; }).join('') + '</select></div>' +
        '<div><label class="field-label" for="rpAdResult">Result type</label><input class="input" id="rpAdResult" type="text" list="rpAdResultTypes"></div></div>' +
        '<datalist id="rpAdResultTypes">' + RESULT_TYPES.map(function (x) { return '<option value="' + esc(x) + '">'; }).join('') + '</datalist>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpAdAud">Audience</label><input class="input" id="rpAdAud" type="text" placeholder="Broad, Interest"></div>' +
        '<div><label class="field-label" for="rpAdStart">Starts</label><input class="input" id="rpAdStart" type="date"></div>' +
        '<div><label class="field-label" for="rpAdEnd">Ends</label><input class="input" id="rpAdEnd" type="date"></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAdThumb">Image</label>' +
          '<div class="rp-thumbfield"><span class="rp-thumb rp-thumb-lg" id="rpAdThumbShow"></span>' +
          '<input class="input" id="rpAdThumb" type="file" accept="image/*"><button class="btn btn-sm btn-quiet" type="button" id="rpAdThumbX">Remove</button></div></div></div></section>' +
      '<section class="fsec"><h4 class="fsec-h">Figures</h4>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpAdSpend">Amount spent</label><input class="input" id="rpAdSpend" data-num="money" type="text" inputmode="decimal"></div>' +
        '<div><label class="field-label" for="rpAdResults">Results</label><input class="input" id="rpAdResults" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpAdCtr">CTR (%)</label><input class="input" id="rpAdCtr" data-num="pct" type="text" inputmode="decimal"></div></div>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpAdReach">Reach</label><input class="input" id="rpAdReach" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpAdImpr">Impressions</label><input class="input" id="rpAdImpr" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpAdCpr">Cost per result</label><input class="input" id="rpAdCpr" data-num="money" type="text" inputmode="decimal" placeholder="Worked out"></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAdBasis">Cost per result is</label><select class="select" id="rpAdBasis" data-seg>' +
          '<option value="">Automatic</option><option value="result">Per result</option><option value="thousand">Per 1,000 reached</option></select></div></div></section>' +
      '<section class="fsec"><h4 class="fsec-h">Results by age (%)</h4><div class="row fgrid-3 fgrid">' +
        AGE_BANDS.map(function (b) { return '<div><label class="field-label" for="rpAge_' + b.replace('+', 'p') + '">' + esc(b) + '</label><input class="input" id="rpAge_' + b.replace('+', 'p') + '" data-age="' + esc(b) + '" data-num="pct" type="text" inputmode="decimal"></div>'; }).join('') +
      '</div><p class="rp-agesum" id="rpAgeSum"></p></section>' +
      '<section class="fsec"><h4 class="fsec-h">Video</h4>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpAdHook">Hook rate (%)</label><input class="input" id="rpAdHook" data-num="pct" type="text" inputmode="decimal"></div>' +
        '<div><label class="field-label" for="rpAdHold">Hold rate (%)</label><input class="input" id="rpAdHold" data-num="pct" type="text" inputmode="decimal"></div>' +
        '<div><label class="field-label" for="rpAdPlay">Average play time</label><input class="input" id="rpAdPlay" type="text" placeholder="0:03"></div></div>' +
        '<details class="fmore" data-none="Plays at 25%, 50%, 75%, 95% and 100%"><summary>Audience retention</summary><div class="row fgrid-3 fgrid">' +
          RET.map(function (r0) { return '<div><label class="field-label" for="rpRet_' + r0[0] + '">Still watching at ' + r0[1] + ' (%)</label><input class="input" id="rpRet_' + r0[0] + '" data-ret="' + r0[0] + '" data-num="pct" type="text" inputmode="decimal"></div>'; }).join('') +
        '</div></details></section>' +
      '<section class="fsec"><h4 class="fsec-h">Remarks</h4><div class="row"><div><label class="field-label" for="rpAdRemark">Remarks on this ad</label><textarea class="input" id="rpAdRemark" rows="2"></textarea></div></div></section>',
      FOOT('Save'));
    box.querySelector('h3').textContent = a && !copy ? 'Edit ad' : 'Add ad';
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    a = a || {};
    v('rpAdName', a.name); $('rpAdObj').value = a.objective || st.lastObj || 'leads';
    v('rpAdResult', a.result_label); v('rpAdAud', a.audience);
    v('rpAdStart', a.starts_on || (a.id || copy ? null : st.open.period_start)); v('rpAdEnd', a.ends_on || (a.id || copy ? null : st.open.period_end));
    v('rpAdSpend', a.spend); v('rpAdResults', a.results); v('rpAdCtr', a.ctr); v('rpAdReach', a.reach); v('rpAdImpr', a.impressions);
    v('rpAdCpr', a.cpr); $('rpAdBasis').value = a.cpr_basis || '';
    AGE_BANDS.forEach(function (b) { v('rpAge_' + b.replace('+', 'p'), (a.age || {})[b]); });
    v('rpAdHook', a.hook_rate); v('rpAdHold', a.hold_rate); $('rpAdPlay').value = playOut(a.avg_play);
    RET.forEach(function (r0) { v('rpRet_' + r0[0], (a.retention || {})[r0[0]]); });
    v('rpAdRemark', a.remark);
    numFields(box);
    /* The age split is a share of the results, so it adds up to 100%. The
       running total says so while it is typed. */
    var ageTotal = function () {
      var any = false, sum = 0;
      Array.prototype.forEach.call(box.querySelectorAll('[data-age]'), function (i) {
        var x = numIn(i.value); if (x !== null) { any = true; sum += x; }
      });
      return any ? Math.round(sum * 10) / 10 : null;
    };
    var paintAge = function () {
      var t = ageTotal(), el = $('rpAgeSum');
      el.textContent = t === null ? 'Adds up to 100%.' : 'Total ' + numOut('pct', t) + (Math.abs(t - 100) <= 0.5 ? '' : ', should be 100%');
      el.classList.toggle('is-warn', t !== null && Math.abs(t - 100) > 0.5);
    };
    Array.prototype.forEach.call(box.querySelectorAll('[data-age]'), function (i) { i.oninput = paintAge; });
    paintAge();
    var fillResult = function () {
      if ($('rpAdResult').value.trim()) return;
      var o = OBJECTIVES.filter(function (x) { return x[0] === $('rpAdObj').value; })[0];
      $('rpAdResult').placeholder = o ? o[2] : '';
    };
    $('rpAdObj').onchange = fillResult; fillResult();
    var thumb = a.thumb_data || null;
    var showThumb = function () { $('rpAdThumbShow').innerHTML = thumb ? '<img src="' + esc(thumb) + '" alt="">' : ''; $('rpAdThumbX').hidden = !thumb; };
    $('rpAdThumb').value = ''; showThumb();
    var sm = box.querySelector('[data-m="sheet"]'); say(sm, '');
    $('rpAdThumb').onchange = function () {
      var f = this.files && this.files[0];
      if (!f) return;
      shrink(f).then(function (d) { thumb = d; showThumb(); say(sm, ''); }, function (e) { say(sm, e.message, 'err'); });
    };
    $('rpAdThumbX').onclick = function () { thumb = null; $('rpAdThumb').value = ''; showThumb(); };
    if (window.ADspaceForm) {
      box.querySelectorAll('details.fmore').forEach(function (d) { window.ADspaceForm.refresh(d); });
      window.ADspaceForm.paint($('rpAdBasis'));
    }
    var go = box.querySelector('[data-a="go"]');
    go.onclick = function () {
      var name = $('rpAdName').value.trim();
      if (!name) { say(sm, 'An ad name is required.', 'err'); $('rpAdName').focus(); return; }
      var bad = null;
      var n = function (id, whole) {
        var raw = $(id).value.trim(); if (!raw) return null;
        var x = numIn(raw);
        if (x === null || x < 0 || (whole && x !== Math.round(x))) { bad = bad || $(id); return null; }
        return x;
      };
      var row = {
        name: name, objective: $('rpAdObj').value, result_label: $('rpAdResult').value.trim() || null,
        audience: $('rpAdAud').value.trim() || null, starts_on: $('rpAdStart').value || null, ends_on: $('rpAdEnd').value || null,
        spend: n('rpAdSpend'), results: n('rpAdResults', true), ctr: n('rpAdCtr'), reach: n('rpAdReach', true), impressions: n('rpAdImpr', true),
        cpr: n('rpAdCpr'), cpr_basis: $('rpAdBasis').value || null,
        hook_rate: n('rpAdHook'), hold_rate: n('rpAdHold'), thumb_data: thumb || null, remark: $('rpAdRemark').value.trim() || null,
        age: {}, retention: {}
      };
      var play = $('rpAdPlay').value.trim();
      row.avg_play = play ? playIn(play) : null;
      if (play && row.avg_play === null) bad = bad || $('rpAdPlay');
      Array.prototype.forEach.call(box.querySelectorAll('[data-age]'), function (i) { var x = n(i.id); if (x !== null) row.age[i.getAttribute('data-age')] = x; });
      Array.prototype.forEach.call(box.querySelectorAll('[data-ret]'), function (i) { var x = n(i.id); if (x !== null) row.retention[i.getAttribute('data-ret')] = x; });
      if (bad) { say(sm, 'A figure is a number: a whole number for results, reach and impressions.', 'err'); if (window.ADspaceForm && window.ADspaceForm.reveal) window.ADspaceForm.reveal(bad); bad.focus(); return; }
      var ageT = ageTotal();
      if (ageT !== null && Math.abs(ageT - 100) > 0.5) {
        say(sm, 'The age split must add up to 100%. It comes to ' + numOut('pct', ageT) + '.', 'err');
        box.querySelector('[data-age]').focus(); return;
      }
      if (row.starts_on && row.ends_on && row.ends_on < row.starts_on) { say(sm, 'The ad must end on or after the day it starts.', 'err'); return; }
      go.disabled = true;
      var editing = a.id && !copy;
      var q = editing ? db.from('sm_report_ads').update(row).eq('id', a.id).select('*')
                      : db.from('sm_report_ads').insert(Object.assign({ report_id: st.open.id, position: st.ads.length + 1 }, row)).select('*');
      q.then(function (res) {
        go.disabled = false;
        if (res.error || !(res.data || []).length) { say(sm, said(res.error || 'The database refused the change.'), 'err'); return; }
        var saved = res.data[0];
        if (editing) st.ads = st.ads.map(function (x) { return x.id === a.id ? saved : x; });
        else st.ads.push(saved);
        st.lastObj = row.objective;
        sortAds();
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        paintAds(); paintTotals();
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  /* Rows from an Ads Manager export, with its own header row. A breakdown
     by age comes in as one row an ad and band; those rows are gathered into
     one ad, its age split taken from its results (or its impressions where
     it has none), and its figures added up. Video plays are turned into the
     hook rate, the hold rate and the retention curve. */
  var AD_HEAD = [
    [/^(ad name|ad|name)$/, 'name'], [/^(ad set name|ad set|audience)$/, 'audience'], [/^objective$/, 'objective'],
    [/^(result type|result indicator|results? type)$/, 'result_label'], [/^results$/, 'results'],
    [/^reach$/, 'reach'], [/^impressions$/, 'impressions'], [/^amount spent/, 'spend'],
    [/^ctr/, 'ctr'], [/^cost per results?/, 'cpr'],
    [/^(reporting starts|starts?|start date|start)$/, 'starts_on'], [/^(reporting ends|ends?|end date|end)$/, 'ends_on'],
    [/^age$/, 'age'],
    [/^(3-second video plays|video plays at 3 ?s|3-second plays)$/, 'plays3'], [/^thruplays$/, 'thruplays'], [/^video plays$/, 'plays'],
    [/^video plays at 25%/, 'v25'], [/^video plays at 50%/, 'v50'], [/^video plays at 75%/, 'v75'], [/^video plays at 95%/, 'v95'], [/^video plays at 100%/, 'v100'],
    [/^video average play time/, 'avg_play'], [/^hook rate/, 'hook_rate'], [/^hold rate/, 'hold_rate']
  ];
  function objectiveOf(v) {
    var x = String(v || '').toLowerCase().replace(/^outcome_/, '').replace(/_/g, ' ').trim();
    if (!x) return null;
    if (/lead/.test(x)) return 'leads';
    if (/messag|conversation/.test(x)) return 'messaging';
    if (/sale|conversion|purchase|catalog/.test(x)) return 'sales';
    if (/traffic|link click/.test(x)) return 'traffic';
    if (/app/.test(x)) return 'app';
    if (/engage|video view|page like/.test(x)) return 'engagement';
    if (/aware|reach|brand/.test(x)) return 'awareness';
    return null;
  }
  function parseAdRows(text, year, fallbackObj) {
    var lines = String(text || '').replace(/\r/g, '').split('\n').filter(function (l) { return l.trim(); });
    if (lines.length < 2) return { error: 'Paste a header row and at least one ad.' };
    var sep = lines[0].indexOf('\t') > -1 ? '\t' : ',';
    var head = lines[0].split(sep).map(function (h) {
      var k = h.trim().toLowerCase().replace(/^"|"$/g, '').replace(/\s+/g, ' ');
      var hit = AD_HEAD.filter(function (x) { return x[0].test(k); })[0];
      return hit ? hit[1] : null;
    });
    if (head.indexOf('name') < 0) return { error: 'The header row needs an Ad name column.' };
    var byKey = {}, order = [], skipped = 0;
    lines.slice(1).forEach(function (l) {
      var cells = l.split(sep).map(function (c) { return c.trim().replace(/^"|"$/g, ''); }), raw = {};
      head.forEach(function (k, i) { if (k) raw[k] = cells[i] || ''; });
      if (!raw.name) { skipped++; return; }
      var obj = objectiveOf(raw.objective) || fallbackObj;
      var key = [raw.name, obj, raw.audience || '', raw.starts_on || ''].join('|');
      var ad = byKey[key];
      if (!ad) {
        ad = byKey[key] = { name: raw.name, objective: obj, audience: raw.audience || null, result_label: raw.result_label || null,
          starts_on: raw.starts_on ? readDate(raw.starts_on, year) : null, ends_on: raw.ends_on ? readDate(raw.ends_on, year) : null,
          _n: {}, _age: {}, _rows: 0, _ctrw: 0 };
        order.push(key);
      }
      ad._rows++;
      ['results', 'reach', 'impressions', 'spend', 'plays3', 'thruplays', 'plays', 'v25', 'v50', 'v75', 'v95', 'v100'].forEach(function (k) {
        var x = numIn(raw[k]); if (x !== null) ad._n[k] = (ad._n[k] || 0) + x;
      });
      ['cpr', 'hook_rate', 'hold_rate'].forEach(function (k) { var x = numIn(raw[k]); if (x !== null) ad._n[k] = x; });
      var pl = playIn(raw.avg_play); if (pl !== null) ad._n.avg_play = pl;
      var ctr = numIn(raw.ctr), im = numIn(raw.impressions);
      if (ctr !== null) { ad._n.ctrSum = (ad._n.ctrSum || 0) + ctr * (im || 1); ad._ctrw += (im || 1); }
      if (raw.age) {
        var band = String(raw.age).replace(/\s/g, '').replace(/–/g, '-');
        if (AGE_BANDS.indexOf(band) > -1) {
          ad._age[band] = { results: numIn(raw.results) || 0, impressions: numIn(raw.impressions) || 0 };
        }
      }
    });
    var rows = order.map(function (k) {
      var ad = byKey[k], n = ad._n;
      var out = { name: ad.name, objective: ad.objective, audience: ad.audience, result_label: ad.result_label,
        starts_on: ad.starts_on, ends_on: ad.ends_on,
        results: n.results != null ? Math.round(n.results) : null, reach: n.reach != null ? Math.round(n.reach) : null,
        impressions: n.impressions != null ? Math.round(n.impressions) : null,
        spend: n.spend != null ? Math.round(n.spend * 100) / 100 : null,
        ctr: ad._ctrw ? Math.round(n.ctrSum / ad._ctrw * 100) / 100 : null,
        cpr: ad._rows === 1 && n.cpr != null ? n.cpr : null,
        avg_play: n.avg_play != null ? n.avg_play : null, age: {}, retention: {} };
      if (n.hook_rate != null) out.hook_rate = n.hook_rate;
      else if (n.plays3 != null && n.impressions) out.hook_rate = Math.round(n.plays3 / n.impressions * 10000) / 100;
      if (n.hold_rate != null) out.hold_rate = n.hold_rate;
      else if (n.thruplays != null && n.impressions) out.hold_rate = Math.round(n.thruplays / n.impressions * 10000) / 100;
      var base = n.plays || n.plays3;
      if (base) [['p25', 'v25'], ['p50', 'v50'], ['p75', 'v75'], ['p95', 'v95'], ['p100', 'v100']].forEach(function (r0) {
        if (n[r0[1]] != null) out.retention[r0[0]] = Math.round(n[r0[1]] / base * 1000) / 10;
      });
      var bands = Object.keys(ad._age);
      if (bands.length) {
        var byRes = bands.reduce(function (t0, b) { return t0 + ad._age[b].results; }, 0);
        var f = byRes ? 'results' : 'impressions';
        var tot = bands.reduce(function (t0, b) { return t0 + ad._age[b][f]; }, 0);
        if (tot) AGE_BANDS.forEach(function (b) { out.age[b] = ad._age[b] ? Math.round(ad._age[b][f] / tot * 1000) / 10 : 0; });
      }
      return out;
    });
    return { rows: rows, skipped: skipped, columns: head.filter(Boolean), byAge: head.indexOf('age') > -1 };
  }

  function pasteAdsSheet(opener) {
    var box = sheetShell('rpPasteAdsSheet', 'Import from Ads Manager',
      '<section class="fsec"><div class="row"><div><label class="field-label" for="rpPAObj">Objective if the rows do not say</label><select class="select" id="rpPAObj">' +
        OBJECTIVES.map(function (o) { return '<option value="' + o[0] + '">' + esc(o[1]) + '</option>'; }).join('') + '</select></div></div>' +
      '<div class="row"><div><label class="field-label" for="rpPAText">Export from Ads Manager, copy the rows with the header row, and paste them here</label>' +
        '<textarea class="input rp-paste" id="rpPAText" rows="8" placeholder="Ad name&#9;Results&#9;Amount spent"></textarea></div></div>' +
      '<p class="rp-paste-sum" id="rpPASum"></p></section>', FOOT('Add ads'));
    $('rpPAText').value = '';
    var sum = $('rpPASum'), sm = box.querySelector('[data-m="sheet"]');
    sum.textContent = ''; say(sm, '');
    var year = Number(String(st.open.period_start).slice(0, 4));
    var go = box.querySelector('[data-a="go"]');
    var read = function () {
      var out = parseAdRows($('rpPAText').value, year, $('rpPAObj').value);
      if (out.error) { sum.textContent = $('rpPAText').value.trim() ? out.error : ''; go.disabled = true; return out; }
      sum.textContent = out.rows.length + ' ad' + (out.rows.length === 1 ? '' : 's') + ' ready' +
        (out.byAge ? ', the age split gathered from the rows' : '') +
        (out.skipped ? ', ' + out.skipped + ' without a name skipped' : '') + '.';
      go.disabled = !out.rows.length;
      return out;
    };
    $('rpPAText').oninput = read; $('rpPAObj').onchange = read;
    go.disabled = true;
    go.onclick = function () {
      var out = read();
      if (!out.rows || !out.rows.length) return;
      var n = st.ads.length;
      var rows = out.rows.map(function (r0, i) { return Object.assign({ report_id: st.open.id, position: n + i + 1 }, r0); });
      go.disabled = true;
      db.from('sm_report_ads').insert(rows).select('*').then(function (res) {
        go.disabled = false;
        if (res.error) { say(sm, said(res.error), 'err'); return; }
        st.ads = st.ads.concat(res.data || []);
        sortAds();
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        paintAds(); paintTotals();
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  // ---- The Reports route: every client's reports, by where each stands ------
  var hub = { rows: [], clients: [], byClient: {}, wired: false };
  var HUB_BANDS = [
    ['draft', 'Drafts'], ['review', 'In review'], ['confirmed', 'Confirmed'], ['published', 'Published']
  ];
  function showEditor() {
    st.host = $('rhEdit');
    if ($('rhHub')) $('rhHub').hidden = true;
    if (st.host) st.host.hidden = false;
  }
  function showList() {
    if ($('rhHub')) $('rhHub').hidden = false;
    if ($('rhEdit')) { $('rhEdit').hidden = true; $('rhEdit').innerHTML = ''; }
    st.open = null; st.step = '';
  }
  /* The route: the list, or one report where the address names one. */
  function enterHub() {
    var list = $('rhList');
    if (!list) return;
    var want = new URLSearchParams(location.search).get('report');
    if (!hub.wired) {
      hub.wired = true;
      $('rhFind').addEventListener('input', paintHub);
      $('rhKind').addEventListener('change', paintHub);
      $('rhNew').addEventListener('click', function () { newSheet($('rhNew')); });
    }
    $('rhKind').innerHTML = '<option value="">Every type</option>' + TYPES.map(function (t) { return '<option value="' + t.key + '">' + esc(t.name) + '</option>'; }).join('');
    $('rhNew').hidden = !may('work');
    loadClients();
    if (want) { openReport(want, true); return; }
    showList();
    UI.skeleton(list, 4);
    db.from('sm_reports').select('id, kind, client_id, period_start, period_end, status, version_no, updated_at').order('period_start', { ascending: false }).then(function (r) {
      if (r.error) { UI.failLine(list, 'reports', said(r.error), enterHub); return; }
      hub.rows = r.data || [];
      clientsReady.then(paintHub);
    });
  }
  var clientsReady = Promise.resolve();
  function loadClients() {
    clientsReady = db.from('clients').select('id, name, slug, stage').order('name', { ascending: true }).then(function (c) {
      var all = c.data || [];
      hub.byClient = {};
      all.forEach(function (x) { hub.byClient[x.id] = x; });
      /* A report is started for a client engaged now: Active only. */
      hub.clients = all.filter(function (x) { return x.stage === 'active'; });
    });
  }
  function paintHub() {
    var list = $('rhList');
    if (!list) return;
    var q = ($('rhFind').value || '').trim().toLowerCase();
    var kind = $('rhKind').value;
    var rows = hub.rows.filter(function (r) {
      if (kind && r.kind !== kind) return false;
      if (!q) return true;
      var c = hub.byClient[r.client_id] || {};
      return (String(c.name || '') + ' ' + periodWord(r.period_start, r.period_end) + ' ' + (TYPE_WORD[r.kind] || '')).toLowerCase().indexOf(q) > -1;
    });
    $('rhCount').textContent = rows.length === hub.rows.length ? plural(rows.length, 'report') : rows.length + ' of ' + hub.rows.length;
    list.innerHTML = '';
    if (!hub.rows.length) {
      UI.emptyLine(list, 'No reports.', may('work') ? 'Start the first report' : null, may('work') ? function () { newSheet($('rhNew')); } : null);
      return;
    }
    if (!rows.length) { UI.emptyLine(list, 'No matches.', 'Clear the search', function () { $('rhFind').value = ''; $('rhKind').value = ''; paintHub(); }); return; }
    var GRP = window.ADspaceGroup;
    var bands = HUB_BANDS.filter(function (bd) { return rows.some(function (r) { return r.status === bd[0]; }); });
    bands.forEach(function (bd) {
      var mine = rows.filter(function (r) { return r.status === bd[0]; });
      var lone = bands.length === 1;
      list.appendChild(GRP.section({
        route: 'reports', key: bd[0], name: bd[1], count: mine.length,
        shut: q ? false : GRP.shut('reports', bd[0], bd[0] === 'published', lone),
        table: function () {
          var t = GRP.table('rh-row', ['Client', 'Period', 'Version', 'Updated', '']);
          GRP.more(t, mine, 30, 'reports', function (r) {
            var c = hub.byClient[r.client_id] || {};
            var b2 = document.createElement('button');
            b2.type = 'button'; b2.className = 'crm-row rh-row';
            b2.innerHTML = '<span class="rp-name"><b>' + esc(c.name || '') + '</b><small>' + esc(TYPE_WORD[r.kind] || '') + '</small></span>' +
              '<span class="rp-ver">' + esc(periodWord(r.period_start, r.period_end)) + '</span>' +
              '<span class="rp-ver">v' + r.version_no + '</span>' +
              '<span class="rp-ver">' + esc(stampWord(r.updated_at)) + '</span>' +
              '<span class="rp-go" aria-hidden="true">' + ICON.go + '</span>';
            b2.addEventListener('click', function () { openReport(r.id); });
            return b2;
          });
          return t;
        }
      }));
    });
  }

  window.ADspaceReports = {
    clientPane: clientPane, parseRows: parseRows, readDate: readDate, parseAdRows: parseAdRows,
    openId: function () { return st.open && st.open.id ? st.open.id : ''; },
    /* The address while the section is open: the report, and the step where
       it is not the one the report would open on anyway. */
    urlState: function () {
      if (!st.open || !st.open.id) return {};
      return { report: st.open.id, step: st.open.client_id ? st.step : '' };
    },
    enterHub: enterHub
  };
  if (bridge.reportsReady) bridge.reportsReady();
})();
