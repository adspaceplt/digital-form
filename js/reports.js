/*
 * Social media reports — the client record's Reports pane.
 *
 * A client's monthly report is prepared here, checked by somebody else,
 * and only then published to the client's own portal. The steps and who may
 * take each are the database's (`sm_report_*` in supabase/schema.sql); this
 * page draws the one next step the reader may take and names a refusal in
 * the team's words. A report is edited only while it is a draft: the
 * database refuses the rest, and the page draws it read only.
 *
 *   Draft      Submit for review            clients.reports Work
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
  function may(level) { return bridge.may ? bridge.may('clients.reports', level) : false; }
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
     PDF; the type is chosen when a report is started. The advertising
     report is next and joins this list when its entry and PDF are built. */
  var TYPES = [{ key: 'social', name: 'Social media report' }];
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
  var INSIGHTS = [
    ['executive_summary', 'Executive summary', 'One or two sentences on the month.', 3],
    ['performed_well', 'Key findings', 'One point a line.', 4],
    ['next_actions', 'Next steps', 'One point a line.', 4],
    ['why_well', 'Performance drivers', 'One point a line.', 3],
    ['underperformed', 'Underperformance', 'One point a line.', 3],
    ['opportunities', 'Opportunities', 'One point a line.', 3],
    ['improvements', 'Improvements', 'One point a line.', 3]
  ];
  var SAID = {
    'denied': 'This needs a higher access level for Social media reports.',
    'not-found': 'This report no longer exists.',
    'exists': 'A report for this period already exists.',
    'bad-period': 'The period must end on or after the day it starts.',
    'not-draft': 'Only a draft can be submitted.',
    'no-platforms': 'Add an account before submitting.',
    'no-posts': 'Add the month\'s posts before submitting.',
    'note-required': 'Say what needs changing.',
    'not-returnable': 'Only a report in review or confirmed can be returned.',
    'not-in-review': 'Only a report in review can be confirmed.',
    'self-confirm': 'Somebody else confirms a report you submitted.',
    'not-confirmed': 'Confirm the report before publishing it.',
    'not-published': 'This report is not published.',
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
    if (/function .* does not exist|schema cache/i.test(m)) return 'Reports need a database update. Run the 2026-09-25 migration.';
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

  var ICON = {
    back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 18l-6-6 6-6"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    more: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>',
    file: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M12 12v6M9 15l3 3 3-3"/></svg>',
    close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>'
  };

  // ---- State ----------------------------------------------------------------
  var st = { host: null, client: null, list: [], versions: {}, open: null, platforms: [], posts: [], busy: false };

  // ---- The pane ---------------------------------------------------------------
  function clientPane(host, client) {
    if (!host || !client) return;
    var same = st.client && st.client.id === client.id && st.host === host;
    st.host = host; st.client = client;
    var want = new URLSearchParams(location.search).get('report');
    if (want && (!st.open || st.open.id !== want)) { openReport(want, true); return; }
    if (!want && st.open && same) { paintEditor(); return; }
    st.open = null;
    loadList();
  }

  function loadList() {
    var host = st.host;
    host.innerHTML = '<div class="viewhead rp-viewhead"><h3>Reports</h3>' +
      (may('work') ? '<button class="btn btn-primary" type="button" data-a="new">' + ICON.plus + 'New report</button>' : '') +
      '</div><div class="rp-listbox"></div><div class="msg" data-m="list"></div>';
    var btn = host.querySelector('[data-a="new"]');
    if (btn) btn.addEventListener('click', function () { newSheet(btn); });
    var box = host.querySelector('.rp-listbox');
    UI.skeleton(box, 3);
    db.from('sm_reports').select('id, title, period_start, period_end, status, version_no, updated_at, return_note')
      .eq('client_id', st.client.id).order('period_start', { ascending: false }).then(function (r) {
        if (r.error) { UI.failLine(box, 'reports', said(r.error), loadList); return; }
        st.list = r.data || [];
        var ids = st.list.map(function (x) { return x.id; });
        if (!ids.length) { paintList(); return; }
        db.from('sm_report_versions').select('id, report_id, version_no, published_at, withdrawn_at')
          .in('report_id', ids).then(function (v) {
            st.versions = {};
            (v.data || []).forEach(function (x) {
              if (x.withdrawn_at) return;
              var cur = st.versions[x.report_id];
              if (!cur || x.version_no > cur.version_no) st.versions[x.report_id] = x;
            });
            paintList();
          });
      });
  }

  function paintList() {
    var box = st.host.querySelector('.rp-listbox');
    if (!box) return;
    if (!st.list.length) {
      UI.emptyLine(box, 'No reports.', may('work') ? 'Start the first report' : null, may('work') ? function () { newSheet(st.host.querySelector('[data-a="new"]')); } : null);
      return;
    }
    box.innerHTML = '<div class="crm-table softpanel rp-table">' +
      '<div class="crm-head rp-row"><span>Period</span><span>Version</span><span>On the client portal</span><span>Status</span><span></span></div>' +
      st.list.map(function (x) {
        var live = st.versions[x.id];
        return '<button class="crm-row rp-row" type="button" data-id="' + esc(x.id) + '">' +
          '<span class="rp-name"><b>' + esc(periodWord(x.period_start, x.period_end)) + '</b><small>' + esc(x.title) + '</small></span>' +
          '<span class="rp-ver">v' + x.version_no + '</span>' +
          '<span class="rp-live">' + (live ? 'Version ' + live.version_no + ', ' + esc(stampWord(live.published_at)) : '<span class="mute">Not published</span>') + '</span>' +
          '<span class="rp-state">' + chip(x.status) + '</span>' +
          '<span class="rp-go" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg></span>' +
          '</button>';
      }).join('') + '</div>';
    Array.prototype.forEach.call(box.querySelectorAll('.rp-row[data-id]'), function (b) {
      b.addEventListener('click', function () { openReport(b.getAttribute('data-id')); });
    });
  }

  /* The open report is in the address through the record's own writer, and
     opening one is a move somebody made, so it pushes an entry. */
  function setAddress() { if (bridge.pushUrl) bridge.pushUrl(); }

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

  /* Start a report: its type (drawn once there is more than one), the
     client where it is started from the Reports route, and the month or a
     custom period. From a client's record the client is that record. */
  function newSheet(opener, o) {
    o = o || {};
    var box = sheetShell('rpNewSheet', 'New report',
      '<section class="fsec">' +
        '<div class="row" id="rpNewKindRow"><div><label class="field-label" for="rpNewKind">Report type</label>' +
          '<select class="select" id="rpNewKind">' + TYPES.map(function (t) { return '<option value="' + t.key + '">' + esc(t.name) + '</option>'; }).join('') + '</select></div></div>' +
        '<div class="row" id="rpNewClientRow"><div><label class="field-label" for="rpNewClient">Client</label><select class="select" id="rpNewClient"></select></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpNewMonth">Month</label><input class="input" id="rpNewMonth" type="month"></div></div>' +
      '<details class="fmore" data-none="Whole month" data-some="Custom period"><summary>Custom period</summary>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpNewStart">Start</label><input class="input" id="rpNewStart" type="date"></div>' +
        '<div><label class="field-label" for="rpNewEnd">End</label><input class="input" id="rpNewEnd" type="date"></div></div></details>' +
      '</section>', FOOT('Create'));
    $('rpNewKindRow').hidden = TYPES.length < 2;
    $('rpNewClientRow').hidden = !o.clients;
    if (o.clients) {
      $('rpNewClient').innerHTML = '<option value="">Choose a client</option>' + o.clients.map(function (c) {
        return '<option value="' + esc(c.id) + '">' + esc(c.name) + '</option>';
      }).join('');
    }
    var now = new Date();
    var last = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    $('rpNewMonth').value = last.getFullYear() + '-' + String(last.getMonth() + 1).padStart(2, '0');
    $('rpNewStart').value = ''; $('rpNewEnd').value = '';
    var sm = box.querySelector('[data-m="sheet"]');
    say(sm, '');
    var go = box.querySelector('[data-a="go"]');
    go.onclick = function () {
      var m = $('rpNewMonth').value, a = $('rpNewStart').value, b = $('rpNewEnd').value;
      var client = o.clients ? $('rpNewClient').value : (st.client && st.client.id);
      if (!client) { say(sm, 'Choose a client.', 'err'); $('rpNewClient').focus(); return; }
      if (!a || !b) {
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
        if (o.clients) { openFromHub(client, id); return; }
        openReport(id);
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  // ---- One report -----------------------------------------------------------------
  function openReport(id, fromAddress) {
    st.open = { id: id };
    if (!fromAddress) setAddress();
    var host = st.host;
    host.innerHTML = '<button class="backlink" type="button" data-a="back">' + ICON.back + 'Reports</button><div class="rp-editbox"></div>';
    host.querySelector('[data-a="back"]').addEventListener('click', function () { st.open = null; setAddress(); loadList(); });
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
      if (!got[0].data || got[0].data.client_id !== st.client.id) { UI.emptyLine(box, 'No such report.'); return; }
      st.open = got[0].data;
      st.platforms = got[1].data || [];
      st.posts = got[2].data || [];
      sortPosts();
      st.openVersions = got[3].data || [];
      paintEditor();
    });
  }

  function editable() { return st.open && st.open.status === 'draft' && may('work'); }
  function myId() { var m = me(); return m && m.id; }

  function paintEditor() {
    var r = st.open;
    var box = st.host.querySelector('.rp-editbox');
    if (!box) { openReport(r.id, true); return; }
    var live = (st.openVersions || []).filter(function (v) { return !v.withdrawn_at; })[0];
    var ed = editable();
    var head = '<section class="panel rp-head">' +
      '<div class="rp-head-top"><div class="rp-who"><h3>' + esc(periodWord(r.period_start, r.period_end)) + '</h3>' +
      '<p class="rp-meta">' + esc(r.title) + ' · Version ' + r.version_no +
        (live ? ' · On the client portal: version ' + live.version_no + ', ' + esc(stampWord(live.published_at)) : '') + '</p></div>' +
      '<div class="rp-ctl">' + chip(r.status) + moreMenu(r, live) + '</div></div>' +
      (r.status === 'draft' && r.return_note ? '<p class="rp-note is-warn"><b>Returned:</b> ' + esc(r.return_note) + '</p>' : '') +
      '<div class="rp-actions">' + actions(r) + '</div><div class="msg" data-m="head"></div></section>';
    box.innerHTML = head +
      '<div class="rp-sec"><div class="rp-sec-head"><h3 class="ovsec-title">Accounts</h3>' +
        (ed ? '<button class="btn btn-sm" type="button" data-a="addacc">' + ICON.plus + 'Add account</button>' : '') + '</div>' +
        '<div class="rp-accs"></div></div>' +
      '<div class="rp-sec"><div class="rp-sec-head"><h3 class="ovsec-title">Posts</h3>' +
        (ed && st.platforms.length ? '<span class="rp-sec-acts"><button class="btn btn-sm" type="button" data-a="paste">Paste rows</button>' +
          '<button class="btn btn-sm" type="button" data-a="addpost">' + ICON.plus + 'Add post</button></span>' : '') + '</div>' +
        '<div class="rp-posts"></div></div>' +
      '<div class="rp-sec"><h3 class="ovsec-title">Report text</h3><div class="rp-text"></div></div>';
    paintAccounts(); paintPosts(); paintText();
    wireHead(box);
    var b;
    if ((b = box.querySelector('[data-a="addacc"]'))) b.addEventListener('click', function () { accountSheet(null, b); });
    if ((b = box.querySelector('[data-a="addpost"]'))) { var ab = b; ab.addEventListener('click', function () { postSheet(null, ab); }); }
    if ((b = box.querySelector('[data-a="paste"]'))) { var pb = b; pb.addEventListener('click', function () { pasteSheet(pb); }); }
  }

  /* One next step, named for what pressing it does. Blue only where it hands
     the report to somebody else: to a reviewer, or to the client. */
  function actions(r) {
    var out = [];
    var mine = r.submitted_by && r.submitted_by === myId();
    if (r.status === 'draft' && may('work')) out.push('<button class="btn btn-go" type="button" data-a="submit">Submit for review</button>');
    if (r.status === 'review' && may('manage') && !mine) out.push('<button class="btn btn-primary" type="button" data-a="confirm">Confirm</button>');
    if (r.status === 'confirmed' && may('manage')) out.push('<button class="btn btn-go" type="button" data-a="publish">Publish to client</button>');
    if (r.status === 'published' && may('work')) out.push('<button class="btn" type="button" data-a="revise">Revise</button>');
    if ((r.status === 'review' && (may('manage') || mine)) || (r.status === 'confirmed' && may('manage'))) {
      out.push('<button class="btn" type="button" data-a="return">' + (r.status === 'review' && mine && !may('manage') ? 'Take back' : 'Return') + '</button>');
    }
    out.push('<button class="btn" type="button" data-a="pdf">' + ICON.file + (r.status === 'published' ? 'Download PDF' : 'Preview PDF') + '</button>');
    if (r.status === 'review' && mine && may('manage')) out.push('<span class="rp-wait">Waiting on another manager to confirm.</span>');
    else if (r.status === 'review' && !may('manage')) out.push('<span class="rp-wait">Waiting on a manager to confirm.</span>');
    return out.join('');
  }
  function moreMenu(r, live) {
    var items = [];
    if (live && may('manage')) items.push('<button class="kmenu-item is-danger" data-soft type="button" data-a="unpublish">Unpublish</button>');
    if (!(st.openVersions || []).length && may('manage')) items.push('<button class="kmenu-item is-danger" type="button" data-a="delete">Delete</button>');
    if (!items.length) return '';
    return '<span class="team-act kmenu-wrap"><button class="kmenu-btn" type="button" aria-label="More" aria-haspopup="true" aria-expanded="false" data-a="more">' + ICON.more + '</button>' +
      '<div class="kmenu" hidden>' + items.join('') + '</div></span>';
  }

  function wireHead(box) {
    var r = st.open, m = box.querySelector('[data-m="head"]');
    var on = function (a, fn) { var b = box.querySelector('.rp-head [data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); };
    var step = function (fn, args, done, btn) {
      if (btn) btn.disabled = true;
      db.rpc(fn, args).then(function (res) {
        if (btn) btn.disabled = false;
        var d = res.data || {};
        if (res.error || d.error) { say(m, said(res.error || d), 'err'); return; }
        openReport(r.id, true);
        setTimeout(function () { say(st.host.querySelector('[data-m="head"]'), done, 'ok'); }, 0);
      });
    };
    on('submit', function (b) {
      window.ADspaceConfirm.ask({ title: 'Submit for review?', body: 'A manager checks it before it can be published. It cannot be edited while it is in review.', go: 'Submit' },
        function () { step('sm_report_submit', { p_id: r.id }, 'Submitted for review.', b); });
    });
    on('confirm', function (b) { step('sm_report_confirm', { p_id: r.id }, 'Confirmed.', b); });
    on('publish', function (b) {
      window.ADspaceConfirm.ask({ title: 'Publish to ' + st.client.name + '?', body: 'The client can read and download this version in their portal.', go: 'Publish' },
        function () { step('sm_report_publish', { p_id: r.id }, 'Published to the client portal.', b); });
    });
    on('revise', function (b) {
      window.ADspaceConfirm.ask({ title: 'Revise this report?', body: 'A new draft, version ' + (r.version_no + 1) + '. The client keeps reading version ' + r.version_no + ' until the revision is published.', go: 'Revise' },
        function () { step('sm_report_revise', { p_id: r.id }, 'Version ' + (r.version_no + 1) + ' is a draft.', b); });
    });
    on('return', function (b) {
      window.ADspaceConfirm.ask({ title: 'Return to draft?', go: 'Return', field: { label: 'What needs changing', rows: 3, need: 'Say what needs changing.' } },
        function (note) { step('sm_report_return', { p_id: r.id, p_note: note }, 'Returned to draft.', b); });
    });
    on('pdf', function (b) { downloadPdf(b, m); });
    on('more', function (b) {
      var menu = b.parentNode.querySelector('.kmenu');
      var open = menu.hidden;
      menu.hidden = !open; b.setAttribute('aria-expanded', String(open));
      if (open && window.ADspaceMenu) window.ADspaceMenu.place(b, menu);
    });
    on('unpublish', function (b) {
      b.closest('.kmenu').hidden = true;
      window.ADspaceConfirm.ask({ title: 'Unpublish this report?', body: 'The client can no longer read it in their portal. It can be published again.', go: 'Unpublish', tone: 'warn',
        field: { label: 'Reason', need: 'Give a reason.' } },
        function (why) { step('sm_report_unpublish', { p_id: r.id, p_reason: why }, 'Unpublished.', null); });
    });
    on('delete', function (b) {
      b.closest('.kmenu').hidden = true;
      var word = periodWord(r.period_start, r.period_end);
      window.ADspaceConfirm.ask({ title: 'Delete this report?', body: 'Its accounts, posts and text go with it. There is no restore.', go: 'Delete', tone: 'danger',
        field: { label: 'Type ' + word + ' to confirm', match: word, mismatch: 'That does not match the period.' } },
        function (typed) {
          db.rpc('sm_report_delete', { p_id: r.id, p_confirm: typed }).then(function (res) {
            var d = res.data || {};
            if (res.error || d.error) { say(m, said(res.error || d), 'err'); return; }
            st.open = null; setAddress(); loadList();
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
    if (!SM()) { say(m, 'The report engine did not load. Refresh the page.', 'err'); return; }
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
    get.then(function (snap) {
      return SM().render(snap).then(function (out) {
        var blob = new Blob([out.bytes], { type: 'application/pdf' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = SM().fileName(snap, snap.report && snap.report.version_no).replace(/\.pdf$/, r.status === 'published' ? '.pdf' : '-draft.pdf');
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(function () { URL.revokeObjectURL(a.href); }, 30000);
        btn.disabled = false;
        say(m, out.warnings && out.warnings.length ? 'Downloaded. ' + out.warnings.join(' ') : 'Downloaded.', out.warnings && out.warnings.length ? 'warn' : 'ok');
      });
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
        '<div class="row fgrid"><div><label class="field-label" for="rpAccStart">At start of period</label><input class="input" id="rpAccStart" type="number" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpAccEnd">At end of period</label><input class="input" id="rpAccEnd" type="number" inputmode="numeric"></div></div>' +
        '<details class="fmore" data-none="Worked out from start and end"><summary>Recorded growth</summary>' +
          '<div class="row fgrid"><div><label class="field-label" for="rpAccGrowth">Growth as reported</label><input class="input" id="rpAccGrowth" type="number" inputmode="numeric"></div>' +
          '<div><label class="field-label" for="rpAccWhy">Reason</label><input class="input" id="rpAccWhy" type="text" placeholder="Platform reports growth only"></div></div></details></section>' +
      '<section class="fsec"><h4 class="fsec-h">Figures reported</h4>' +
        '<div class="rp-ticks">' + METRICS.map(function (mm) {
          return '<label class="tickline"><input type="checkbox" data-metric="' + mm[0] + '"> <span>' + esc(mm[1]) + '</span></label>';
        }).join('') + '</div>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpAccBasis">Engagement rate based on</label><select class="select" id="rpAccBasis">' +
          BASIS.map(function (x) { return '<option value="' + x[0] + '">' + esc(x[1]) + '</option>'; }).join('') + '</select></div>' +
        '<div><label class="field-label" for="rpAccNote">Metric note</label><input class="input" id="rpAccNote" type="text" placeholder="Meta reports this as Impressions/Views"></div></div></section>' +
      '<section class="fsec"><h4 class="fsec-h">Remarks</h4>' +
        '<div class="row"><div><label class="field-label" for="rpAccSummary">Summary line</label><input class="input" id="rpAccSummary" type="text"></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccWorked">Highlights</label><textarea class="input" id="rpAccWorked" rows="3" placeholder="One point a line"></textarea></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccImprove">Areas for improvement</label><textarea class="input" id="rpAccImprove" rows="3" placeholder="One point a line"></textarea></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccActions">Recommendations</label><textarea class="input" id="rpAccActions" rows="3" placeholder="One point a line"></textarea></div></div></section>',
      FOOT('Save'));
    box.querySelector('h3').textContent = a ? 'Edit account' : 'Add account';
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    v('rpAccPlatform', a ? a.platform : 'instagram'); v('rpAccName', a ? a.account_name : st.client.name);
    v('rpAccGroup', a ? a.group_label : ''); v('rpAccStart', a && a.followers_start); v('rpAccEnd', a && a.followers_end);
    v('rpAccGrowth', a && a.growth_override); v('rpAccWhy', a && a.growth_reason);
    v('rpAccBasis', a ? a.er_basis : 'views'); v('rpAccNote', a && a.metric_notes);
    v('rpAccSummary', a && a.summary); v('rpAccWorked', a && a.worked); v('rpAccImprove', a && a.improve); v('rpAccActions', a && a.actions);
    var mets = a ? (a.metrics || []) : ['views', 'engagements'];
    Array.prototype.forEach.call(box.querySelectorAll('[data-metric]'), function (c) { c.checked = mets.indexOf(c.getAttribute('data-metric')) > -1; });
    var more = box.querySelector('details.fmore');
    if (more) more.open = Boolean(a && a.growth_override != null);
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
        '<div><label class="field-label" for="rpPostDate">Date</label><input class="input" id="rpPostDate" type="date"></div></div>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpPostTitle">Title</label><input class="input" id="rpPostTitle" type="text" placeholder="Named by its format and date when blank"></div>' +
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
          '<input class="input" id="rpFig_' + k + '" data-fig="' + k + '" type="text" inputmode="numeric"></div>';
      }).join('');
      (a.metrics || []).forEach(function (k) {
        $('rpFig_' + k).value = keep[k] != null ? keep[k] : (p && p[k] != null ? p[k] : '');
      });
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
    var box = sheetShell('rpPasteSheet', 'Paste rows',
      '<section class="fsec"><div class="row"><div><label class="field-label" for="rpPasteAcc">Account</label><select class="select" id="rpPasteAcc"></select></div></div>' +
      '<div class="row"><div><label class="field-label" for="rpPasteText">Rows from a spreadsheet, with the header row</label>' +
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

  // ---- The report's own text ----------------------------------------------------------------
  function paintText() {
    var box = st.host.querySelector('.rp-text');
    if (!box) return;
    var r = st.open, ins = r.insights || {};
    if (!editable()) {
      var rows = [['Title', r.title], ['Headline', r.headline], ['Introduction', r.intro]]
        .concat(INSIGHTS.map(function (x) { return [x[1], ins[x[0]]]; }))
        .filter(function (x) { return String(x[1] || '').trim(); });
      box.innerHTML = rows.length ? '<div class="ovcard"><dl class="ovfacts rp-facts">' + rows.map(function (x) {
        return '<dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]).replace(/\n/g, '<br>') + '</dd>';
      }).join('') + '</dl></div>' : '';
      if (!rows.length) UI.emptyLine(box, 'No text.');
      return;
    }
    box.innerHTML = '<section class="panel rp-textform">' +
      '<section class="fsec"><h4 class="fsec-h">Opening</h4>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpTitle">Title</label><input class="input" id="rpTitle" type="text"></div>' +
        '<div><label class="field-label" for="rpRank">Rank top posts by</label><select class="select" id="rpRank">' +
          ['views', 'reach', 'impressions', 'engagements', 'interactions'].map(function (k) { return '<option value="' + k + '">' + esc(METRIC_WORD[k]) + '</option>'; }).join('') +
        '</select></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpHeadline">Headline</label><input class="input" id="rpHeadline" type="text"></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpIntro">Introduction</label><textarea class="input" id="rpIntro" rows="3"></textarea></div></div></section>' +
      '<section class="fsec"><h4 class="fsec-h">Findings and recommendations</h4>' +
        INSIGHTS.map(function (x) {
          return '<div class="row"><div><label class="field-label" for="rpIns_' + x[0] + '">' + esc(x[1]) + '</label>' +
            '<textarea class="input" id="rpIns_' + x[0] + '" rows="' + x[3] + '" placeholder="' + esc(x[2]) + '"></textarea></div></div>';
        }).join('') + '</section>' +
      '<div class="rp-textfoot"><button class="btn btn-primary" type="button" data-a="savetext">Save</button><div class="msg" data-m="text"></div></div></section>';
    $('rpTitle').value = r.title || '';
    $('rpRank').value = r.rank_metric || 'views';
    $('rpHeadline').value = r.headline || '';
    $('rpIntro').value = r.intro || '';
    INSIGHTS.forEach(function (x) { $('rpIns_' + x[0]).value = ins[x[0]] || ''; });
    var btn = box.querySelector('[data-a="savetext"]'), m = box.querySelector('[data-m="text"]');
    btn.addEventListener('click', function () {
      var title = $('rpTitle').value.trim();
      if (!title) { say(m, 'A title is required.', 'err'); $('rpTitle').focus(); return; }
      var insights = {};
      INSIGHTS.forEach(function (x) { var v = $('rpIns_' + x[0]).value.trim(); if (v) insights[x[0]] = v; });
      var row = { title: title, rank_metric: $('rpRank').value, headline: $('rpHeadline').value.trim() || null,
                  intro: $('rpIntro').value.trim() || null, insights: insights };
      btn.disabled = true;
      db.from('sm_reports').update(row).eq('id', r.id).select('*').then(function (res) {
        btn.disabled = false;
        if (res.error || !(res.data || []).length) { say(m, said(res.error || 'The database refused the change.'), 'err'); return; }
        st.open = res.data[0];
        say(m, 'Saved.', 'ok');
      });
    });
  }

  // ---- The Reports route: every client's reports, by where each stands ------
  var hub = { rows: [], clients: [], wired: false };
  var HUB_BANDS = [
    ['review', 'In review'], ['confirmed', 'Confirmed'], ['draft', 'Drafts'], ['published', 'Published']
  ];
  function enterHub() {
    var list = $('rhList');
    if (!list) return;
    if (!hub.wired) {
      hub.wired = true;
      $('rhFind').addEventListener('input', paintHub);
      $('rhKind').addEventListener('change', paintHub);
      $('rhNew').addEventListener('click', function () { newSheet($('rhNew'), { clients: hub.clients }); });
    }
    /* The type filter is drawn once there is more than one type. */
    $('rhKind').hidden = TYPES.length < 2;
    $('rhKind').innerHTML = '<option value="">Every type</option>' + TYPES.map(function (t) { return '<option value="' + t.key + '">' + esc(t.name) + '</option>'; }).join('');
    $('rhNew').hidden = !may('work');
    UI.skeleton(list, 4);
    Promise.all([
      db.from('sm_reports').select('id, kind, title, client_id, period_start, period_end, status, version_no, updated_at').order('period_start', { ascending: false }),
      db.from('clients').select('id, name, slug, stage').order('name', { ascending: true })
    ]).then(function (got) {
      if (got[0].error) { UI.failLine(list, 'reports', said(got[0].error), enterHub); return; }
      hub.rows = got[0].data || [];
      hub.clients = (got[1].data || []).filter(function (c) { return c.stage !== 'lead'; });
      if (!hub.clients.length) hub.clients = got[1].data || [];
      hub.byClient = {};
      (got[1].data || []).forEach(function (c) { hub.byClient[c.id] = c; });
      paintHub();
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
    $('rhCount').textContent = rows.length === hub.rows.length ? rows.length + ' report' + (rows.length === 1 ? '' : 's') : rows.length + ' of ' + hub.rows.length;
    list.innerHTML = '';
    if (!hub.rows.length) {
      UI.emptyLine(list, 'No reports.', may('work') ? 'Start the first report' : null, may('work') ? function () { newSheet($('rhNew'), { clients: hub.clients }); } : null);
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
          var t = GRP.table('rh-row', ['Client', 'Report', 'Version', 'Updated', '']);
          GRP.more(t, mine, 30, 'reports', function (r) {
            var c = hub.byClient[r.client_id] || {};
            var b2 = document.createElement('button');
            b2.type = 'button'; b2.className = 'crm-row rh-row';
            b2.innerHTML = '<span class="rp-name"><b>' + esc(c.name || '') + '</b><small>' + esc(TYPE_WORD[r.kind] || '') + '</small></span>' +
              '<span class="rp-ver">' + esc(periodWord(r.period_start, r.period_end)) + '</span>' +
              '<span class="rp-ver">v' + r.version_no + '</span>' +
              '<span class="rp-ver">' + esc(stampWord(r.updated_at)) + '</span>' +
              '<span class="rp-go" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg></span>';
            b2.addEventListener('click', function () { openFromHub(r.client_id, r.id); });
            return b2;
          });
          return t;
        }
      }));
    });
  }
  /* A report opens on its client's record, where it is edited: the address
     is written first, then the record is shown, the way the bell opens a
     task. */
  function openFromHub(clientId, reportId) {
    var c = hub.byClient && hub.byClient[clientId];
    var key = c && (c.slug || c.id) || clientId;
    history.pushState(null, '', '/admin/?client=' + encodeURIComponent(key) + '&tab=reports&report=' + encodeURIComponent(reportId));
    if (bridge.show) bridge.show('clients');
  }

  window.ADspaceReports = {
    clientPane: clientPane, parseRows: parseRows, readDate: readDate,
    openId: function () { return st.open && st.open.id ? st.open.id : ''; },
    enterHub: enterHub
  };
  if (bridge.reportsReady) bridge.reportsReady();
})();
