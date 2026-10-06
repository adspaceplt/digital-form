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
 *   In review  Confirm / Send back          the named reviewer, or an admin
 *   Confirmed  Publish to client / Send back Manage
 *   Published  Revise, Unpublish            Work / Manage
 *
 * The PDF is drawn in the browser by js/smreport.js from the database's own
 * snapshot, so the file downloaded here is the file the client reads.
 */
(function () {
  'use strict';
  /* An edit carries its pen, as every Edit in the console does. */
  var PEN_MARK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  /* Clients and colleagues in a picker lead with their code (js/form.js). */
  var F = window.ADspaceForm;
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
  /* `seg` is the segment's word: the whole name did not fit a phone's
     segment ("just cut short", the user, 2026-09-28). */
  var TYPES = [{ key: 'social', name: 'Social Media Accounts Report', seg: 'Accounts Report' },
               { key: 'ads', name: 'Social Media Advertising Report', seg: 'Advertising Report' }];
  var TYPE_WORD = {};
  TYPES.forEach(function (t) { TYPE_WORD[t.key] = t.name; });
  var PLATFORMS = [['facebook', 'Facebook'], ['instagram', 'Instagram'], ['tiktok', 'TikTok'], ['rednote', 'rednote'],
                   ['youtube', 'YouTube'], ['linkedin', 'LinkedIn'], ['x', 'X'], ['threads', 'Threads'],
                   ['douyin', 'Douyin'], ['pinterest', 'Pinterest'], ['dianping', '大众点评'], ['other', 'Other']];
  var PLATFORM_WORD = {};
  PLATFORMS.forEach(function (p) { PLATFORM_WORD[p[0]] = p[1]; });
  /* A platform the database's list does not hold (2026-10-06): kept as
     `other` with its name in `platform_name`; the list offers the ones the
     team uses by name, and Other asks for the name. */
  var NAMED = { douyin: 'Douyin', pinterest: 'Pinterest', dianping: '大众点评' };
  function platWord(a) { return (a && String(a.platform_name || '').trim()) || PLATFORM_WORD[a && a.platform] || (a && a.platform) || ''; }
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
             ['fix', 'Areas to improve', 'One point a line', 3], ['focus', 'Focus for next month', 'One point a line', 3]]
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
    'no-reviewer': 'Choose who reviews it.',
    'self-review': 'Somebody else reviews a report you submitted.',
    'bad-reviewer': 'Choose a colleague at Reports Full Access.',
    'not-reviewer': 'Only its reviewer, or an admin, does this.',
    'same-reviewer': 'They already review it.',
    'month-gate': 'Its month in My Work is not in order: see the checks above.',
    'late-reason': 'Give the reason it is late.',
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
  /* Every save and every Draft with AI is filed under Reports (the user,
     2026-10-01), as the report's own steps are: the client, then the
     period and version, then what was saved. Fire and forget, as every
     page-side entry is: a filing that fails never stops the save. */
  function fileReport(action, what, r0, c0) {
    var r = r0 || st.open, c = c0 || st.client || {};
    if (!r || !window.ADspaceAdmin || !window.ADspaceAdmin.log) return;
    window.ADspaceAdmin.log(action, c.name || '',
      periodWord(r.period_start, r.period_end) + ' · v' + r.version_no + (what ? ' · ' + what : ''));
  }
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
    go: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6"/></svg>',
    out: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>'
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
  /* A tab opened at the press (2026-10-05: the user previews before saving)
     shows the file in the browser's own viewer; without one (a blocked
     pop-up) the file downloads. */
  function saveFile(snap, tab) {
    if (!SM()) return Promise.reject(new Error('The report engine did not load. Refresh the page.'));
    return SM().render(snap).then(function (out) {
      var blob = new Blob([out.bytes], { type: 'application/pdf' });
      var url = URL.createObjectURL(blob);
      if (tab && !tab.closed) tab.location.href = url;
      else {
        var a = document.createElement('a');
        a.href = url; a.download = SM().fileName(snap);
        document.body.appendChild(a); a.click(); a.remove();
      }
      setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
      return out.warnings && out.warnings.length ? out.warnings.join(' ') : '';
    });
  }
  function openTab() {
    var tab = null;
    try { tab = window.open('', '_blank'); } catch (e) { tab = null; }
    if (tab) { try { tab.document.title = 'PDF'; tab.document.body.textContent = 'Drawing the PDF…'; } catch (e) { /* still blank */ } }
    return tab;
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
            return '<option value="' + t.key + '">' + esc(t.seg) + '</option>';
          }).join('') + '</select></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpNewClient">Client</label><select class="select" id="rpNewClient" aria-required="true"></select></div></div>' +
        /* A white-label client's report is for the client itself or one of
           its brands (2026-10-07): each its own report a month. */
        '<div class="row" id="rpNewForRow" hidden><div><label class="field-label" for="rpNewFor">For</label><select class="select" id="rpNewFor"></select></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpNewMonth">Month</label><input class="input" id="rpNewMonth" aria-required="true" type="month"></div></div>' +
      '<details class="fmore" data-none="Whole month" data-some="Custom period"><summary>Custom period</summary>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpNewStart">Start</label><input class="input" id="rpNewStart" aria-required="true" type="date" data-hint="Select date"></div>' +
        '<div><label class="field-label" for="rpNewEnd">End</label><input class="input" id="rpNewEnd" aria-required="true" type="date" data-hint="Select date"></div></div></details>' +
      '</section>', FOOT('Create'));
    $('rpNewClient').innerHTML = '<option value="">Choose a client</option>' + hub.clients.map(function (c) {
      return '<option value="' + esc(c.id) + '">' + esc(F.named(c.client_code, c.name)) + '</option>';
    }).join('');
    var forSeq = 0;
    var paintFor = function () {
      var cid = $('rpNewClient').value, c = hub.byClient[cid] || {}, seq = ++forSeq;
      $('rpNewForRow').hidden = true; $('rpNewFor').innerHTML = '';
      if (!cid || !c.white_label || !(bridge.may && bridge.may('reports.whitelabel', 'work'))) return;
      db.rpc('client_brands_list', { p_client: cid }).then(function (q) {
        if (seq !== forSeq) return;
        var bs = ((q && q.data && q.data.brands) || []).filter(function (b) { return b.active; });
        if (!bs.length) return;
        $('rpNewFor').innerHTML = '<option value="">' + esc(c.name) + '</option>' +
          bs.map(function (b) { return '<option value="' + esc(b.id) + '">' + esc(b.name) + ' · White label</option>'; }).join('');
        $('rpNewForRow').hidden = false;
        if (window.ADspaceForm && window.ADspaceForm.paint) window.ADspaceForm.paint($('rpNewFor'));
      }).catch(function () {});
    };
    $('rpNewClient').onchange = paintFor;
    paintFor();
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
      var brand = $('rpNewForRow').hidden ? '' : $('rpNewFor').value;
      (brand ? db.rpc('sm_report_create_for', { p_client: client, p_start: a, p_end: b, p_kind: $('rpNewKind').value || 'social', p_brand: brand })
             : db.rpc('sm_report_create', { p_client: client, p_start: a, p_end: b, p_kind: $('rpNewKind').value || 'social' })).then(function (r) {
        go.disabled = false;
        var d = r.data || {};
        var id = d.id;
        if (r.error || (d.error && !(d.error === 'exists' && id))) {
          say(sm, d.error === 'index-pending' ? 'This needs a database update.' : d.error === 'bad-brand' ? 'That brand is no longer offered.' : said(r.error || d), 'err');
          return;
        }
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        if (d.error === 'exists') { openReport(id); return; }
        /* A new report is written in the main contact's preferred language. */
        db.from('client_contacts').select('lang').eq('client_id', client).eq('is_primary', true).limit(1).then(function (x) {
          var c = x && !x.error && (x.data || [])[0];
          if (!c || c.lang !== 'zh') return null;
          return db.from('sm_reports').update({ lang: 'zh' }).eq('id', id).select('id');
        }).catch(function () { return null; }).then(function () { openReport(id); });
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
    if (!same) st.adPick = null;
    st.open = st.open && st.open.id === id ? st.open : { id: id };
    var want = new URLSearchParams(location.search).get('step');
    showEditor();
    if (!fromAddress) { st.step = ''; if (bridge.pushUrl) bridge.pushUrl(); if (!same) window.scrollTo(0, 0); }
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
      var more = [db.from('clients').select('id, name, market, slug, handle_ig, handle_fb, handle_tiktok, handle_xhs').eq('id', st.open.client_id).maybeSingle()];
      if (st.open.kind === 'ads') more.push(db.from('sm_report_ads').select('*').eq('report_id', id).order('position', { ascending: true }));
      return Promise.all(more.concat([loadNames(), labelOf(st.open.label_client)])).then(function (x) {
        st.partner = x[x.length - 1] || null;
        if (x[1] && x[1].error) { UI.failLine(box, 'the ads', said(x[1].error), function () { openReport(id, true); }); return; }
        st.client = (x[0] && x[0].data) || { id: st.open.client_id, name: '' };
        if (x[1]) { st.ads = x[1].data || []; sortAds(); }
        paintEditor();
      });
    });
  }

  /* The white-label client whose wide logo the report carries (2026-10-07),
     while it is still ticked, or null. A refused read leaves the head as it
     was: the PDF reads its own. */
  function labelOf(cid) {
    if (!cid) return Promise.resolve(null);
    return db.from('clients').select('id, name, white_label').eq('id', cid).maybeSingle().then(function (q) {
      var c = q && !q.error && q.data;
      return c && c.white_label ? c : null;
    }).catch(function () { return null; });
  }
  function editable() { return st.open && st.open.status === 'draft' && may('work'); }
  /* Colleagues' names, read once, for the reviewer a report names. */
  var namesReady = null;
  function loadNames() {
    if (!namesReady) namesReady = db.from('team_members').select('id, name').then(function (r) {
      st.names = {};
      ((r && r.data) || []).forEach(function (m) { st.names[m.id] = m.name; });
    }).catch(function () { st.names = st.names || {}; namesReady = null; });
    return namesReady;
  }
  function nameOf(id) { return (st.names || {})[id] || ''; }
  function myId() { var m = me(); return m && m.id; }
  function isAdmin() { var m = me(); return Boolean(m && (m.is_admin || m.role === 'admin')); }
  /* A step read, not edited (a report in review and after): the record's
     own facts card, one section a group, each label beside its value
     (the user, 2026-10-02: the labels stood over their values at the card's
     edge). Text a person wrote keeps its lines. */
  function factsCard(sections) {
    return '<div class="ovcard rp-read">' + sections.filter(function (x) { return x.rows.length; }).map(function (x) {
      return '<div class="ovsec">' + (x.title ? '<div class="ovsec-head"><h3>' + esc(x.title) + '</h3></div>' : '') +
        '<dl class="ovfacts rp-facts">' + x.rows.map(function (r) {
          return '<div><dt>' + esc(r[0]) + '</dt><dd class="is-pre">' + esc(r[1]) + '</dd></div>';
        }).join('') + '</dl></div>';
    }).join('') + '</div>';
  }

  /* What each step holds, in the words its button says under its name. */
  /* What the commentary holds, against what it can hold. An accounts report
     counts its summary and one block a platform (the user, 2026-10-01:
     findings are read platform by platform); an ads report its four fields. */
  function socialGroups() {
    var M = window.ADspaceSmReport;
    if (!M || !M.model) return [];
    /* The model marks each post with its group, so it is given copies: the
       rows the page holds stay plain data. */
    var copy = function (x) { return Object.assign({}, x); };
    var mdl = M.model({ report: st.open || {}, platforms: st.platforms.map(copy), posts: st.posts.map(copy) });
    return mdl.groups.map(function (g) { return { label: g.label, lead: g.accounts[0], top: M.topOf(g, 3) }; });
  }
  var PLAT_FIELDS = [['summary', 'Summary line'], ['worked', 'What worked'], ['improve', 'Areas to improve'], ['actions', 'Focus for next month']];
  function commentaryState() {
    var r = st.open || {}, ins = r.insights || {};
    var has = function (v) { return String(v || '').trim() !== ''; };
    if (r.kind === 'ads') {
      return { n: TEXT.ads.filter(function (x) { return has(x[0] === 'intro' ? (r.intro || ins.executive_summary) : ins[x[0]]); }).length, of: 4 };
    }
    var groups = socialGroups();
    var n = has(r.intro || ins.executive_summary) ? 1 : 0;
    groups.forEach(function (g) { if (PLAT_FIELDS.some(function (f) { return has(g.lead[f[0]]); })) n++; });
    return { n: n, of: 1 + groups.length };
  }
  function commentaryCount() { return commentaryState().n; }
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
    if (k === 'text') { var cs = commentaryState(); return cs.n ? cs.n + ' of ' + cs.of + ' written' : 'Not written'; }
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
        (live ? ' · Version ' + live.version_no + ' on the client portal' : '') + (r.brand_name ? ' · For ' + esc(r.brand_name) : '') + (r.status === 'published' && r.sent_on ? ' · Sent ' + esc(dayWord(r.sent_on)) : '') + (st.partner ? ' · ' + esc(st.partner.name) + ' logo' : '') + '</p></div>' +
      '<div class="rp-ctl">' + chip(r.status) +
        /* On a narrow pane the verb gives way and the button reads PDF, so
           the state, the file and the ⋯ sit beside the name on one line. */
        '<button class="btn btn-sm btn-icon rp-pdf" type="button" data-a="pdf" aria-label="Preview PDF">' +
          '<span class="rp-pdf-long">Preview PDF</span><span class="rp-pdf-short">PDF</span> ' + ICON.out + '</button>' +
        moreMenu(r, live) + '</div></div>' +
      (r.status === 'draft' && r.return_note ? '<p class="rp-note is-warn"><b>Sent back:</b> ' + esc(r.return_note) + '</p>' : '') +
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
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(nav);
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
      box.innerHTML = '<div class="rp-sec">' + head('Posts', ed && st.platforms.length ? '<button class="btn btn-sm" type="button" data-a="pickposts">Select</button>' +
          '<button class="btn btn-sm" type="button" data-a="paste">Import from spreadsheet</button>' +
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
      box.innerHTML = '<div class="rp-sec">' + head('Ads', ed ? '<button class="btn btn-sm" type="button" data-a="pickads">Select</button>' +
          '<button class="btn btn-sm" type="button" data-a="pasteads">Import from Ads Manager</button>' +
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
    if ((b = box.querySelector('[data-a="pickads"]'))) b.addEventListener('click', function () { st.adPick = {}; paintAds(); });
    if ((b = box.querySelector('[data-a="pickposts"]'))) b.addEventListener('click', function () { st.postPick = {}; paintPosts(); });
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
        '<button class="btn btn-sm btn-quiet" type="button" data-to="' + s[0] + '">' + (editable() ? PEN_MARK + 'Edit' : 'View') + '</button></div>';
    }).join('');
    var missing = stepsOf(r).slice(0, 3).filter(function (s) { return s[0] !== 'text' && s[0] !== 'figures' && !stepDone(s[0]); });
    var mine = r.submitted_by && r.submitted_by === myId();
    /* A named reviewer confirms, or an admin in their place; a report
       submitted before reviewers keeps the earlier rule. */
    var named = r.status === 'review' && r.reviewer_id;
    var reviewing = named && r.reviewer_id === myId();
    var acts = [], wait = '';
    if (r.status === 'draft' && may('work')) acts.push('<button class="btn btn-go" type="button" data-a="submit"' + (missing.length ? ' disabled' : '') + '>Submit for review</button>');
    if (r.status === 'review' && may('manage') && (named ? (reviewing || isAdmin()) : (!mine || isAdmin()))) acts.push('<button class="btn btn-primary" type="button" data-a="confirm">Confirm</button>');
    if (r.status === 'confirmed' && may('manage')) acts.push('<button class="btn btn-go" type="button" data-a="publish">Publish to client</button>');
    if (r.status === 'published' && may('work')) acts.push('<button class="btn" type="button" data-a="revise">Revise</button>');
    var mayReturn = named ? (reviewing || mine || (isAdmin() && may('manage'))) : (may('manage') || mine);
    if ((r.status === 'review' && mayReturn) || (r.status === 'confirmed' && may('manage'))) {
      acts.push('<button class="btn" type="button" data-a="return">' + (r.status === 'review' && mine && !reviewing && !(named ? isAdmin() : may('manage')) ? 'Take back' : 'Send back') + '</button>');
    }
    if (r.status === 'draft' && missing.length) wait = 'Add ' + missing.map(function (s) { return s[1].toLowerCase(); }).join(' and ') + ' to submit.';
    else if (named && !reviewing) wait = 'Waiting for ' + (nameOf(r.reviewer_id) || 'the reviewer') + ' to confirm.';
    else if (r.status === 'review' && mine && may('manage') && !isAdmin()) wait = 'Waiting on another manager to confirm.';
    else if (r.status === 'review' && !may('manage')) wait = 'Waiting on a manager to confirm.';
    else if (r.status === 'confirmed' && !may('manage')) wait = 'Waiting on a manager to publish.';
    var gated = r.status === 'draft' && String(r.period_start || '') >= '2026-10-01';
    box.innerHTML = '<div class="rp-sec"><div class="rp-sec-head"><h3 class="ovsec-title">Check and submit</h3></div>' +
      '<div class="ovcard rp-checks">' + rows + '</div>' +
      '<div class="ovcard rp-aicheck" data-m="aicheck" hidden></div>' +
      (acts.length || wait ? '<div class="rp-actions">' + acts.join('') + (wait ? '<span class="rp-wait">' + esc(wait) + '</span>' : '') + '</div>' : '') +
      '<div class="msg" data-m="check"></div>' + keyDates(r) + '</div>';
    Array.prototype.forEach.call(box.querySelectorAll('[data-to]'), function (b) {
      b.addEventListener('click', function () { goStep(b.getAttribute('data-to')); });
    });
    wireSteps(box);
    if (gated) loadGate(box, r);
    loadCheck(box, r);
  }

  /* The figures check (the user, 2026-10-04): on the last step, the
     commentary as it stands, drafted or written by hand, is read against
     the report's own figures, and what does not hold is listed: where it
     is, the words, what the figures show, and the words to use. Kept with
     the report, so the reviewer reads the same check; a commentary changed
     since says so. A report in draft or in review may be checked; it uses
     one of the colleague's AI uses a day. */
  function commentaryNow(r) {
    var out = {}, add = function (k, v) { v = String(v == null ? '' : v).replace(/\r/g, '').trim(); if (v) out[k] = v; };
    var ins = r.insights || {};
    add('intro', r.intro);
    ((r.kind || 'social') === 'ads' ? ['worked', 'fix', 'focus'] : ['performed_well', 'underperformed', 'next_actions']).forEach(function (k) { add(k, ins[k]); });
    if ((r.kind || 'social') !== 'ads') {
      (st.platforms || []).forEach(function (p) { PLAT_FIELDS.forEach(function (f) { add('p:' + p.id + ':' + f[0], p[f[0]]); }); });
      (st.posts || []).forEach(function (p) { add('n:' + p.id, p.notable); });
    }
    return out;
  }
  function sameText(a, b) {
    var ka = Object.keys(a || {}).sort(), kb = Object.keys(b || {}).sort();
    return ka.join('|') === kb.join('|') && ka.every(function (k) { return String(a[k]).slice(0, 4000) === String(b[k]).slice(0, 4000); });
  }
  var checkRun = {};
  function loadCheck(box, r) {
    var host = box.querySelector('[data-m="aicheck"]');
    if (!host) return;
    var can = (r.status === 'draft' || r.status === 'review') && may('work');
    db.rpc('ai_check_last', { p_report: r.id }).then(function (res) {
      var d = res && res.data;
      if (st.open !== r || !host.isConnected) return;
      if (res.error || !d || d.error) { if (!can) return; d = { none: true }; }
      paintAiCheck(host, r, d.none ? null : d, can);
    }).catch(function () { if (can && st.open === r && host.isConnected) paintAiCheck(host, r, null, can); });
  }
  function paintAiCheck(host, r, last, can, said0) {
    if (!last && !can) { host.hidden = true; return; }
    var found = last && last.result && last.result.findings || [];
    var stale = last && !sameText(last.basis, commentaryNow(r));
    var mark = !last ? '' : stale ? ' is-missing' : found.length ? ' is-missing' : ' is-done';
    var meta = !last ? 'Not checked' :
      'Checked ' + stampWord(last.at) + (last.by ? ' by ' + last.by : '') + ' · ' +
      (found.length ? found.length + (found.length === 1 ? ' point' : ' points') + ' to correct' : 'Matches the figures');
    host.hidden = false;
    host.innerHTML = '<div class="rp-check' + mark + '">' +
        '<span class="rp-check-mark" aria-hidden="true">' + (mark === ' is-done' ? ICON.tick : '') + '</span>' +
        '<span class="rp-check-t"><b>Figures check</b><small>' + esc(meta) + '</small></span>' +
        (can ? '<span class="rp-aicheck-acts"><span class="rp-aileft" data-m="cleft" hidden></span>' +
          '<button class="btn btn-sm" type="button" data-a="aicheck">' + (checkRun[r.id] ? 'Checking' : last ? 'Check again' : 'Check') + '</button></span>' : '') +
      '</div>' +
      (stale ? '<p class="rp-f-note">The commentary has changed since this check.</p>' : '') +
      found.map(function (f) {
        return '<div class="rp-finding"><span class="rp-f-where">' + esc(f.where || '') + '</span>' +
          (f.quote ? '<span class="rp-f-quote">\u201c' + esc(f.quote) + '\u201d</span>' : '') +
          '<span class="rp-f-issue">' + esc(f.issue || '') + '</span>' +
          (f.fix ? '<span class="rp-f-fix"><span class="rp-f-label">Use</span>' + esc(f.fix) + '</span>' : '') + '</div>';
      }).join('') +
      '<div class="msg" data-m="cmsg"></div>';
    var m = host.querySelector('[data-m="cmsg"]');
    if (said0) say(m, said0, 'err');
    var b = host.querySelector('[data-a="aicheck"]');
    if (!b) return;
    if (checkRun[r.id]) b.disabled = true;
    /* One check a colleague a report a day (an admin's five), within the
       colleague's AI uses for the day (2026-10-05). */
    var left = null, room = null, line = host.querySelector('[data-m="cleft"]');
    db.rpc('ai_check_left', { p_report: r.id }).then(function (res) {
      var d = res && res.data;
      if (res.error || !d || d.error || d.left == null || !host.isConnected) return;
      room = d; left = d.left;
      line.hidden = false; line.textContent = left + ' left';
      line.classList.toggle('is-out', !left);
      if (!left && !checkRun[r.id]) { b.disabled = true; say(m, aiLimit(d), 'warn'); }
    }).catch(function () { /* an older database: no line */ });
    b.addEventListener('click', function () {
      var body = room && room.admin
        ? 'This uses one of your figures checks on this report today and one of your AI uses (' + room.person + ' left).'
        : 'You have one figures check on this report a day. This uses today\'s, and one of your AI uses' +
          (room ? ' (' + room.person + ' left).' : '.');
      window.ADspaceConfirm.ask({ title: 'Check against the figures?', body: body, go: 'Check' }, function () { runCheck(host, r); });
    });
  }
  function runCheck(host, r) {
    var rid = r.id;
    checkRun[rid] = true;
    var b = host.querySelector('[data-a="aicheck"]');
    if (b) { b.disabled = true; b.textContent = 'Checking'; }
    say(host.querySelector('[data-m="cmsg"]'), '');
    var asked = { r: st.open, c: st.client };
    db.functions.invoke('report-draft', { body: { report_id: rid, mode: 'check' } }).then(function (res) {
      var d = res && res.data;
      if (res.error || !d || d.error || !d.check) { var x = new Error((d && d.error) || 'ai-failed'); x.d = d; throw x; }
      return { last: { result: d.check } };
    }).catch(function (e) {
      return { said: e && e.message === 'ai-limit' ? aiLimit(e.d) : (CHECK_SAID[e && e.message] || AI_SAID[e && e.message] || said(e)) };
    }).then(function (out) {
      delete checkRun[rid];
      var n = out.last ? (out.last.result.findings || []).length : 0;
      fileReport(out.last ? 'report.ai_drafted' : 'report.ai_failed',
        out.last ? 'Figures check · ' + (n ? n + (n === 1 ? ' point' : ' points') + ' to correct' : 'matches the figures') : 'Figures check · ' + out.said,
        asked.r, asked.c);
      var box = st.open && st.open.id === rid && st.host && st.host.querySelector('[data-m="aicheck"]');
      if (!box) return;
      if (out.last) { loadCheck(st.host, st.open); return; }
      loadCheckWith(box, out.said);
    });
  }
  function loadCheckWith(host, said0) {
    var r = st.open;
    db.rpc('ai_check_last', { p_report: r.id }).then(function (res) {
      var d = res && res.data;
      paintAiCheck(host, r, d && !d.error && !d.none ? d : null, true, said0);
    }).catch(function () { paintAiCheck(host, r, null, true, said0); });
  }
  var CHECK_SAID = {
    'no-text': 'Write the commentary before checking it.',
    'not-open': 'Only a report in draft or in review can be checked.',
    'ai-failed': 'No check came back. Try again.',
    'ai-incomplete': 'No check came back. Try again.'
  };

  /* The month's gate (2026-10-04): a report from October 2026 on is
     submitted once its month in My Work asks for it, holds its report task
     and its planned content; late, it asks why. Read as rows under the
     report's own checks; Submit rests where the reader may not go past. */
  function dueWord(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return '';
    var my = new Date(d.getTime() + 8 * 3600000);
    return my.getUTCDate() + ' ' + MON[my.getUTCMonth()] + ' ' + my.getUTCFullYear();
  }
  function spanOf(m) {
    var a = new Date(m.starts + 'T00:00:00'), b = new Date(m.ends + 'T00:00:00');
    return a.getDate() + ' ' + MON[a.getMonth()] + ' to ' + b.getDate() + ' ' + MON[b.getMonth()];
  }
  function gateWords(g) {
    var out = [];
    (g.missing || []).forEach(function (k) {
      if (k === 'no-month') out.push('No month in My Work covers this period.');
      else if (k === 'not-ticked') out.push('Its month does not ask for this report.');
      else if (k === 'no-task') out.push('Its month holds no report task.');
      else if (k === 'content') out.push(g.made + ' of ' + g.planned + ' planned content tasks are in the month.');
    });
    return out;
  }
  function loadGate(box, r) {
    db.rpc('sm_report_gate', { p_id: r.id }).then(function (res) {
      var g = res && res.data;
      if (!g || res.error || g.error || !g.applies || st.open !== r || !box.isConnected) return;
      st.gate = { id: r.id, g: g };
      var miss = g.missing || [];
      var has = function (k) { return miss.indexOf(k) > -1; };
      var row = function (ok, title, note, act) {
        return '<div class="rp-check rp-gate' + (ok ? ' is-done' : ' is-missing') + '">' +
          '<span class="rp-check-mark" aria-hidden="true">' + (ok ? ICON.tick : '') + '</span>' +
          '<span class="rp-check-t"><b>' + esc(title) + '</b><small>' + esc(note) + '</small></span>' + (act || '') + '</div>';
      };
      var mo = g.month;
      var html =
        row(!has('no-month') && !has('not-ticked'), 'Month in My Work',
          !mo ? 'No month covers this period' : (MON[Number(mo.period.slice(5, 7)) - 1] + ' ' + mo.period.slice(0, 4) + ' · ' + spanOf(mo) + (has('not-ticked') ? ' · Does not ask for this report' : ''))) +
        (mo && !has('not-ticked') ? row(!has('no-task'), 'Report task',
          g.task ? '#WT' + String(g.task.task_no).padStart(5, '0') : 'Missing',
          g.task && bridge.may && bridge.may('ops', 'view') ? '<button class="btn btn-sm btn-quiet" type="button" data-a="opentask">Open' + ICON.go + '</button>' : '') : '') +
        (mo ? row(!has('content'), 'Content', g.planned ? g.made + ' of ' + g.planned + ' planned' : 'None planned') : '') +
        row(!g.late, 'Due', dueWord(g.due) + (g.late ? ' · Late: Submit asks why' : ''));
      var card = box.querySelector('.rp-checks');
      if (card) card.insertAdjacentHTML('beforeend', html);
      var open = box.querySelector('[data-a="opentask"]');
      if (open) open.addEventListener('click', function () {
        history.replaceState(null, '', '/admin/?s=work&open=' + encodeURIComponent(g.task.id));
        if (bridge.show) bridge.show('work');
      });
      if (!g.ok && !g.may_override) {
        var sub = box.querySelector('[data-a="submit"]');
        if (sub) sub.disabled = true;
        var acts = box.querySelector('.rp-actions'), w = acts && acts.querySelector('.rp-wait');
        if (acts && !w) { w = document.createElement('span'); w.className = 'rp-wait'; acts.appendChild(w); }
        if (w) w.textContent = 'Put the month in order to submit.';
      }
    }).catch(function () { /* an older database: no gate */ });
  }

  /* Key dates (the user, 2026-10-04): when the report was started,
     submitted and to whom, confirmed and by whom, and published, with the
     time each step took; a step not reached is left out. */
  function spanWord(ms) {
    var h = ms / 3600000;
    if (h < 1) return 'Under 1 h';
    if (h < 48) return Math.round(h) + ' h';
    var d = Math.floor(h / 24), rest = Math.round(h - d * 24);
    if (rest === 24) { d += 1; rest = 0; }
    return d + ' days' + (rest ? ' ' + rest + ' h' : '');
  }
  function keyDates(r) {
    var live = (st.openVersions || []).filter(function (v) { return !v.withdrawn_at; })[0];
    var marks = [
      /* Who did each step, and to whom it went (the user, 2026-10-06:
         "submitted by who is missing"). */
      ['Started', r.created_at, r.created_by && nameOf(r.created_by) ? 'by ' + nameOf(r.created_by) : ''],
      ['Submitted', r.status !== 'draft' && r.submitted_at, [r.submitted_by && nameOf(r.submitted_by) ? 'by ' + nameOf(r.submitted_by) : '',
        r.reviewer_id && nameOf(r.reviewer_id) ? 'to ' + nameOf(r.reviewer_id) : ''].filter(Boolean).join(' ')],
      ['Confirmed', r.confirmed_at, r.confirmed_by && nameOf(r.confirmed_by) ? 'by ' + nameOf(r.confirmed_by) : ''],
      ['Published', live && r.status === 'published' && live.published_at, '']
    ].filter(function (x) { return x[1]; });
    if (marks.length < 2) return '';
    var rows = marks.map(function (x, i) {
      var next = marks[i + 1];
      return '<div class="tl-row tl-stage">' +
        '<span class="tl-lead"><span class="tl-what">' + esc(x[0]) + '</span>' +
          '<span class="tl-when">' + esc(stampWord(x[1])) + '</span>' + (x[2] ? '<span class="tl-who">' + esc(x[2]) + '</span>' : '') + '</span>' +
        '<span class="tl-span">' + (next ? esc(spanWord(new Date(next[1]) - new Date(x[1]))) : '') + '</span></div>';
    });
    var last = marks[marks.length - 1][1];
    rows.push('<div class="tl-rule"></div><div class="tl-row tl-date"><span class="tl-lead"><span class="tl-what">' +
      (r.status === 'published' ? 'Total' : 'Total so far') + '</span></span><span class="tl-span">' +
      esc(spanWord((r.status === 'published' ? new Date(last) : new Date()) - new Date(marks[0][1]))) + '</span></div>');
    return '<div class="rp-sec rp-keydates"><div class="rp-sec-head"><h3 class="ovsec-title">Key dates</h3></div>' +
      '<div class="ovcard rp-timeline"><div class="ovsec tline">' + rows.join('') + '</div></div></div>';
  }

  function moreMenu(r, live) {
    var items = [];
    /* A report in review from before reviewers is given one the same way. */
    if (r.status === 'review' && may('work') &&
        (r.submitted_by === myId() || (r.reviewer_id && r.reviewer_id === myId()) || isAdmin())) {
      items.push('<button class="kmenu-item" type="button" data-a="reassign">' + (r.reviewer_id ? 'Change reviewer' : 'Assign reviewer') + '</button>');
    }
    /* A draft started under a temporary client moves to its own (an
       admin's, 2026-10-06). */
    if (r.status === 'draft' && isAdmin()) items.push('<button class="kmenu-item" type="button" data-a="move">Transfer client</button>');
    /* White-label work for a partner (2026-10-07): a client ticked White
       label lends its wide logo, and the report names the brand it covers,
       while it stays under the client who pays. */
    if (r.status !== 'published' && bridge.may && bridge.may('reports.whitelabel', 'work')) items.push('<button class="kmenu-item" type="button" data-a="whitelabel">White label</button>');
    /* Mark as sent (2026-10-07): a published report's day it went out. */
    if (r.status === 'published' && may('work')) {
      items.push('<button class="kmenu-item" type="button" data-a="sent">' + (r.sent_on ? 'Change sent date' : 'Mark as sent') + '</button>');
      if (r.sent_on) items.push('<button class="kmenu-item" type="button" data-a="unsent">Mark as not sent</button>');
    }
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
      reopen(done);
    });
  }
  function reopen(done) {
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
  }

  /* Who reviews: the colleagues the database offers (Reports Full Access or
     an admin, never the submitter), the client's last reviewer first
     chosen. One question with the reviewer as its field. */
  function pickReviewer(r, btn, m, ask, then) {
    if (btn) btn.disabled = true;
    Promise.all([db.rpc('sm_report_reviewers', { p_id: r.id }), loadNames()]).then(function (got) {
      if (btn) btn.disabled = false;
      var res = got[0], d = (res && res.data) || {};
      if (res.error || d.error) { say(m, said(res.error || d), 'err'); return; }
      var pool = (d.reviewers || []).filter(function (x) { return !ask.skip || x.id !== ask.skip; });
      if (!pool.length) { say(m, 'No colleague at Reports Full Access can review it.', 'err'); return; }
      var pick = (pool.filter(function (x) { return x.last; })[0] || pool[0]).id;
      var who = { name: 'who', label: 'Reviewer', choices: pool.map(function (x) { return [x.id, (x.code ? x.code + ' · ' : '') + x.name]; }), value: pick };
      /* A late report, or one past its month's gate, says why in the same
         question (2026-10-04). */
      if (ask.reason) {
        window.ADspaceConfirm.ask({ title: ask.title, body: ask.body, go: ask.go,
          fields: [who, { name: 'why', label: ask.reason, rows: 2, need: 'A reason is required.' }] },
          function (v) { then(v.who, v.why); });
        return;
      }
      window.ADspaceConfirm.ask({ title: ask.title, body: ask.body, go: ask.go,
        field: { label: who.label, choices: who.choices, value: who.value } },
        function (w) { then(w); });
    }).catch(function () { if (btn) btn.disabled = false; say(m, said({ message: 'Load failed' }), 'err'); });
  }

  function wireSteps(box) {
    var r = st.open, m = box.querySelector('[data-m="check"]');
    var on = function (a, fn) { var b = box.querySelector('[data-a="' + a + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); };
    on('submit', function (b) {
      var g = st.gate && st.gate.id === r.id ? st.gate.g : null;
      var past = g && g.applies && !g.ok, late = g && g.applies && g.late;
      var ask = { title: 'Submit for review?', body: 'The reviewer is told and checks it before it is published. It is locked while in review.', go: 'Submit' };
      if (past || late) {
        ask.title = past ? 'Submit past the month\'s gate?' : 'Submit late?';
        ask.body = (past ? gateWords(g).join(' ') + ' ' : '') + (late ? 'It was due ' + dueWord(g.due) + '. ' : '') +
          'The reason is kept with the report.';
        ask.reason = past && late ? 'Reason' : past ? 'Why it goes now' : 'Why it is late';
      }
      pickReviewer(r, b, m, ask, function (who, why) {
        var args = { p_id: r.id, p_reviewer: who };
        if (why) args.p_reason = why;
        stepCall('sm_report_submit', args, 'Submitted to ' + nameOf(who) + '.', b, m);
      });
    });
    on('confirm', function (b) {
      /* An admin confirming for the named reviewer says so first; the
         record files it "in place of" them (2026-10-04). */
      if (r.reviewer_id && r.reviewer_id !== myId() && r.submitted_by !== myId()) {
        window.ADspaceConfirm.ask({ title: 'Confirm in place of ' + (nameOf(r.reviewer_id) || 'the reviewer') + '?', body: 'The record notes you confirmed it in their place.', go: 'Confirm' }, function () {
          stepCall('sm_report_confirm', { p_id: r.id }, 'Confirmed.', b, m);
        });
        return;
      }
      /* An admin may confirm a report they submitted (the user, 2026-10-02:
         the hierarchy ends with them), after a question saying so. */
      if (r.submitted_by && r.submitted_by === myId()) {
        window.ADspaceConfirm.ask({ title: 'Confirm your own report?', body: 'You submitted it, so no second person will have checked it.', go: 'Confirm' }, function () {
          stepCall('sm_report_confirm', { p_id: r.id }, 'Confirmed.', b, m);
        });
        return;
      }
      stepCall('sm_report_confirm', { p_id: r.id }, 'Confirmed.', b, m);
    });
    on('publish', function (b) {
      window.ADspaceConfirm.ask({ title: 'Publish to ' + st.client.name + '?', body: 'The client can read and download it in their portal.', go: 'Publish' },
        function () { stepCall('sm_report_publish', { p_id: r.id }, 'Published to the client portal.', b, m); });
    });
    on('revise', function (b) {
      window.ADspaceConfirm.ask({ title: 'Revise this report?', body: 'Version ' + (r.version_no + 1) + ' starts as a draft. The client keeps version ' + r.version_no + ' until it is published.', go: 'Revise' },
        function () { stepCall('sm_report_revise', { p_id: r.id }, 'Version ' + (r.version_no + 1) + ' is a draft.', b, m); });
    });
    on('return', function (b) {
      window.ADspaceConfirm.ask({ title: 'Send back to draft?', go: 'Send back', field: { label: 'What needs changing', rows: 3, need: 'Say what needs changing.' } },
        function (note) { stepCall('sm_report_return', { p_id: r.id, p_note: note }, 'Sent back to draft.', b, m); });
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
    on('reassign', function (b) {
      b.closest('.kmenu').hidden = true;
      var first = !r.reviewer_id;
      pickReviewer(r, null, m, { title: first ? 'Assign reviewer?' : 'Change reviewer?', body: 'The reviewer is told.', go: first ? 'Assign' : 'Change', skip: r.reviewer_id },
        function (who) { stepCall('sm_report_assign', { p_id: r.id, p_reviewer: who }, (first ? 'Assigned to ' : 'Reviewer changed to ') + nameOf(who) + '.', null, m); });
    });
    on('move', function (b) {
      b.closest('.kmenu').hidden = true;
      clientsReady.then(function () {
        var pool = hub.clients.filter(function (c) { return c.id !== r.client_id; });
        if (!pool.length) { say(m, 'There is no other active client to transfer to.', 'err'); return; }
        window.ADspaceConfirm.ask({ title: 'Transfer to another client?', body: 'The accounts, posts, ads and commentary go with the report.', go: 'Transfer',
          field: { label: 'Client', choices: [['', 'Choose a client']].concat(pool.map(function (c) { return [c.id, F.named(c.client_code, c.name)]; })),
            value: '', need: 'Choose a client.' } },
          function (to) {
            var name = (hub.byClient[to] || {}).name || 'the client';
            db.rpc('sm_report_move', { p_id: r.id, p_client: to }).then(function (res) {
              var d = res.data || {};
              if (res.error || d.error) {
                var e = (d && d.error) || '';
                say(m, e === 'not-draft' ? 'Only a draft can be transferred.' : e === 'white-label' ? 'Set White label back to the client first.' : e === 'not-active' ? 'Choose an Active client.' :
                  e === 'exists' ? name + ' already has a report for this period.' : said(res.error || d), 'err');
                return;
              }
              reopen('Transferred to ' + name + '.');
            });
          });
      });
    });
    on('whitelabel', function (b) {
      b.closest('.kmenu').hidden = true;
      /* The report's own client's brands (2026-10-07): a white-label client
         is serviced for its brands, each its own report a period. */
      Promise.all([
        db.from('clients').select('id, name, white_label').eq('id', r.client_id).maybeSingle(),
        db.rpc('client_brands_list', { p_client: r.client_id })
      ]).then(function (x) {
        var c = (x[0] && x[0].data) || {};
        if (x[0] && x[0].error) { say(m, said(x[0].error), 'err'); return; }
        if (x[1] && x[1].error) { say(m, said(x[1].error), 'err'); return; }
        var bs = ((x[1] && x[1].data && x[1].data.brands) || []).filter(function (q) { return q.active || q.id === r.brand_id; });
        if (!c.white_label || !bs.length) {
          say(m, !c.white_label ? 'Tick White label on ' + (c.name || 'the client') + '\'s Brand first.' : 'Add a brand on ' + (c.name || 'the client') + '\'s Brand first.', 'warn');
          return;
        }
        window.ADspaceConfirm.ask({ title: 'White label', go: 'Save',
          fields: [
            { name: 'brand', label: 'For', required: false, value: r.brand_id || '',
              choices: [['', (c.name || 'Client') + ' (no white label)']].concat(bs.map(function (q) { return [q.id, q.name]; })) }
          ] },
          function (v) {
            db.rpc('sm_report_brand', { p_id: r.id, p_brand: (v && v.brand) || null }).then(function (res) {
              var d = res.data || {};
              if (res.error || d.error) {
                var e = (d && d.error) || '';
                say(m, e === 'published' ? 'A published report keeps its brand. Revise it first.' :
                  e === 'exists' ? 'That brand already has a report for this period.' :
                  e === 'bad-brand' ? 'That brand is no longer offered.' :
                  e === 'index-pending' ? 'This needs a database update.' : said(res.error || d), 'err');
                return;
              }
              reopen('Saved.');
            }).catch(function (e) { say(m, said(e), 'err'); });
          });
      }).catch(function (e) { say(m, said(e), 'err'); });
    });
    var sentCall = function (day) {
      db.rpc('sm_report_sent', { p_id: r.id, p_on: day || null }).then(function (res) {
        var d = res.data || {};
        if (res.error || d.error) {
          var e = (d && d.error) || '';
          say(m, e === 'bad-date' ? 'Choose a day from the period\'s start up to today.' : e === 'not-published' ? 'Only a published report is sent.' : said(res.error || d), 'err');
          return;
        }
        reopen(day ? 'Marked as sent.' : 'Marked as not sent.');
      }).catch(function (e) { say(m, said(e), 'err'); });
    };
    on('sent', function (b) {
      b.closest('.kmenu').hidden = true;
      var today = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
      window.ADspaceConfirm.ask({ title: r.sent_on ? 'Change sent date' : 'Mark as sent', go: 'Save',
        fields: [{ name: 'day', label: 'Sent on', type: 'date', value: r.sent_on || today, min: r.period_start, max: today, required: true }] },
        function (v) { sentCall(v && v.day); });
    });
    on('unsent', function (b) { b.closest('.kmenu').hidden = true; sentCall(null); });
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
    var tab = openTab();
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
    get.then(function (snap) { return saveFile(snap, tab); }).then(function (warn) {
      btn.disabled = false;
      say(m, warn ? (tab && !tab.closed ? 'Opened. ' : 'Downloaded. ') + warn : (tab && !tab.closed ? '' : 'Downloaded.'), warn ? 'warn' : 'ok');
    }).catch(function (e) {
      btn.disabled = false;
      if (tab && !tab.closed) tab.close();
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
      /* The section head carries Add account; the empty line does not say it twice. */
      UI.emptyLine(box, 'No accounts.');
      return;
    }
    box.innerHTML = '<div class="crm-table softpanel rp-acc-table">' +
      '<div class="crm-head rp-acc-row"><span>Account</span><span>Followers</span><span>Growth</span><span>Figures</span><span></span></div>' +
      st.platforms.map(function (a) {
        return '<div class="crm-row rp-acc-row" data-id="' + esc(a.id) + '">' +
          '<span class="rp-name"><b>' + esc(a.account_name || platWord(a)) + '</b><small>' + esc(platWord(a)) +
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
    /* A platform's remarks are written on the Commentary step, on its lead
       account, where Draft with AI fills them. An account's own remarks
       show here only where it is not its group's lead and already holds
       some (older reports), so they can still be edited or cleared. */
    var leads = socialGroups().map(function (g) { return g.lead && g.lead.id; });
    var remarksHere = !!a && leads.indexOf(a.id) < 0 &&
      ['summary', 'worked', 'improve', 'actions'].some(function (k) { return String(a[k] || '').trim(); });
    var box = sheetShell('rpAccSheet', 'Account',
      '<section class="fsec"><h4 class="fsec-h">Account</h4>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpAccPlatform">Platform</label><select class="select" id="rpAccPlatform">' +
          PLATFORMS.map(function (p) { return '<option value="' + p[0] + '">' + esc(p[1]) + '</option>'; }).join('') + '</select></div>' +
        '<div><label class="field-label" for="rpAccName">Handle</label><input class="input" id="rpAccName" type="text" autocapitalize="off" spellcheck="false" placeholder="@adspace.advertising"></div></div>' +
        '<div class="row" id="rpAccPlatNameRow" hidden><div><label class="field-label" for="rpAccPlatName">Platform name</label>' +
          '<input class="input" id="rpAccPlatName" type="text" maxlength="40" aria-required="true" autocomplete="off"></div></div>' +
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
      (remarksHere ? '<details class="fmore" data-none="Optional"><summary>Remarks for this account</summary>' +
        '<div class="row"><div><label class="field-label" for="rpAccSummary">Summary line</label><input class="input" id="rpAccSummary" type="text"></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccWorked">What worked</label><textarea class="input" id="rpAccWorked" rows="3" placeholder="One point a line"></textarea></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccImprove">Areas to improve</label><textarea class="input" id="rpAccImprove" rows="3" placeholder="One point a line"></textarea></div></div>' +
        '<div class="row"><div><label class="field-label" for="rpAccActions">Focus for next month</label><textarea class="input" id="rpAccActions" rows="3" placeholder="One point a line"></textarea></div></div></details>' : ''),
      FOOT('Save'));
    box.querySelector('h3').textContent = a ? 'Edit account' : 'Add account';
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    /* The handle is the account's own name on the platform, so two accounts
       on one platform read apart (the user, 2026-10-01); a new account
       takes the client's handle for the platform from Brand, and follows
       the platform picked while it still holds that. */
    var HANDLE_COL = { instagram: 'handle_ig', facebook: 'handle_fb', tiktok: 'handle_tiktok', rednote: 'handle_xhs' };
    var handleFor = function (pl) {
      var h = String((st.client || {})[HANDLE_COL[pl]] || '').trim();
      return h && pl !== 'facebook' && h.charAt(0) !== '@' ? '@' + h : h;
    };
    /* A named platform kept as `other` shows as itself in the list; any
       other name shows Other with the name under it. */
    var named = '';
    if (a && a.platform === 'other' && a.platform_name) {
      Object.keys(NAMED).forEach(function (k) { if (NAMED[k] === a.platform_name) named = k; });
    }
    v('rpAccPlatform', a ? (named || a.platform) : 'instagram'); v('rpAccName', a ? a.account_name : handleFor('instagram'));
    v('rpAccPlatName', a && a.platform === 'other' && !named ? a.platform_name : '');
    var nameRow = function () { $('rpAccPlatNameRow').hidden = $('rpAccPlatform').value !== 'other'; };
    nameRow();
    var lastHandle = $('rpAccName').value;
    $('rpAccPlatform').onchange = function () {
      nameRow();
      if (!a && $('rpAccName').value.trim() === lastHandle.trim()) { lastHandle = handleFor($('rpAccPlatform').value); $('rpAccName').value = lastHandle; }
    };
    v('rpAccGroup', a ? a.group_label : ''); v('rpAccStart', a && a.followers_start); v('rpAccEnd', a && a.followers_end);
    v('rpAccGrowth', a && a.growth_override); v('rpAccWhy', a && a.growth_reason);
    numFields(box);
    v('rpAccBasis', a ? a.er_basis : 'views'); v('rpAccNote', a && a.metric_notes);
    if (remarksHere) { v('rpAccSummary', a.summary); v('rpAccWorked', a.worked); v('rpAccImprove', a.improve); v('rpAccActions', a.actions); }
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
      var pick = $('rpAccPlatform').value, pName = NAMED[pick] || (pick === 'other' ? $('rpAccPlatName').value.trim() : '');
      if (pick === 'other' && !pName) { say(sm, 'Enter the platform name.', 'err'); $('rpAccPlatName').focus(); return; }
      var row = {
        platform: NAMED[pick] ? 'other' : pick, platform_name: pName || null, account_name: $('rpAccName').value.trim() || null,
        group_label: label || null, group_key: label ? label.toLowerCase().replace(/[^a-z0-9]+/g, '-') : null,
        followers_start: numOf('rpAccStart'), followers_end: numOf('rpAccEnd'),
        growth_override: numOf('rpAccGrowth'), growth_reason: $('rpAccWhy').value.trim() || null,
        metrics: metrics, er_basis: $('rpAccBasis').value || null, metric_notes: $('rpAccNote').value.trim() || null
      };
      if (remarksHere) {
        row.summary = $('rpAccSummary').value.trim() || null; row.worked = $('rpAccWorked').value.trim() || null;
        row.improve = $('rpAccImprove').value.trim() || null; row.actions = $('rpAccActions').value.trim() || null;
      }
      go.disabled = true;
      var q = a ? db.from('sm_report_platforms').update(row).eq('id', a.id).select('*')
                : db.from('sm_report_platforms').insert(Object.assign({ report_id: st.open.id, position: st.platforms.length + 1 }, row)).select('*');
      q.then(function (res) {
        go.disabled = false;
        if (res.error || !(res.data || []).length) { say(sm, said(res.error || 'The database refused the change.'), 'err'); return; }
        var saved = res.data[0];
        if (a) st.platforms = st.platforms.map(function (x) { return x.id === a.id ? saved : x; });
        else st.platforms.push(saved);
        fileReport('report.saved', (a ? 'Account edited: ' : 'Account added: ') + (saved.account_name || saved.platform || ''));
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
        undoBar((a.account_name || platWord(a)) + ' removed.', st.host.querySelector('.rp-accs'), function () {
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
  /* Select (the user, 2026-10-02, as on the Ads step): a tick on every row
     and a bar over the list, which moves the ticked posts to another account
     or removes them, each with its Undo. */
  function paintPosts() {
    paintSteps();
    var box = st.host.querySelector('.rp-posts');
    if (!box) return;
    var ed = editable();
    if (!ed || st.posts.length < 2) st.postPick = null;
    var pick = st.postPick;
    var pickBtn = st.host.querySelector('[data-a="pickposts"]');
    if (pickBtn) pickBtn.hidden = !ed || st.posts.length < 2 || !!pick;
    if (!st.platforms.length) { UI.emptyLine(box, 'Add an account first.'); return; }
    if (!st.posts.length) {
      UI.emptyLine(box, 'No posts.');
      return;
    }
    if (pick) Object.keys(pick).forEach(function (id) { if (!st.posts.some(function (p) { return p.id === id; })) delete pick[id]; });
    var tick = function (id, label, on) {
      return '<span class="rp-pick"><input class="trow-pick" type="checkbox"' + (id ? ' data-pick="' + esc(id) + '"' : ' data-pickall') +
        (on ? ' checked' : '') + ' aria-label="' + esc(label) + '"></span>';
    };
    var accWord = function (a) { return (a.account_name || platWord(a)) + ' · ' + platWord(a); };
    var bar = pick ? '<div class="bulkbar rp-adbar">' +
      '<label class="tickline bulkbar-all"><input type="checkbox" id="rpPostAll"> <span id="rpPostCount"></span></label>' +
      '<span class="bulkbar-acts">' + (st.platforms.length > 1 ? '<select class="select select-sm" id="rpPostMove" aria-label="Move to account"><option value="">Move to account</option>' +
        st.platforms.map(function (a) { return '<option value="' + esc(a.id) + '">' + esc(accWord(a)) + '</option>'; }).join('') + '</select>' : '') +
      '<button class="btn btn-sm btn-danger" id="rpPostRemove" type="button">Remove</button></span>' +
      '<button class="btn btn-sm btn-quiet bulkbar-done" id="rpPostDone" type="button">Done</button></div>' : '';
    box.innerHTML = bar + st.platforms.map(function (a) {
      var posts = st.posts.filter(function (p) { return p.platform_id === a.id; });
      if (!posts.length) return '';
      var m = (a.metrics || []).slice(0, 2);
      while (m.length < 2) m.push(null);
      return '<div class="rp-postgroup"><p class="rp-group">' + esc(accWord(a)) +
        ' <span class="mute">' + posts.length + ' post' + (posts.length === 1 ? '' : 's') + '</span></p>' +
        '<div class="crm-table softpanel rp-post-table' + (pick ? ' is-picking' : '') + '" data-acc="' + esc(a.id) + '">' +
        '<div class="crm-head rp-post-row">' + (pick ? tick(null, 'Select every ' + accWord(a) + ' post', posts.every(function (p) { return pick[p.id]; })) : '') +
          '<span></span><span>Post</span><span>Date</span><span class="rp-n1">' + esc(m[0] ? METRIC_WORD[m[0]] : '') + '</span><span class="rp-n2">' + esc(m[1] ? METRIC_WORD[m[1]] : '') + '</span><span></span></div>' +
        posts.map(function (p) {
          /* A post with no title of its own (an export's rows carry the
             caption alone) reads its caption's first line under the name. */
          var titled = p.title && String(p.title).trim();
          var line = titled ? (FORMAT_WORD[p.content_type] && p.content_type ? FORMAT_WORD[p.content_type] : '') : firstLine(p.caption);
          return '<div class="crm-row rp-post-row' + (pick && pick[p.id] ? ' is-picked' : '') + '" data-id="' + esc(p.id) + '">' +
            (pick ? tick(p.id, 'Select ' + postName(p), !!pick[p.id]) : '') +
            '<span class="rp-thumb">' + (p.thumb_data ? '<img src="' + esc(p.thumb_data) + '" alt="">' : '') + '</span>' +
            '<span class="rp-name"><b>' + esc(postName(p)) + '</b><small>' + esc([line, p.notable ? 'Remarked' : ''].filter(Boolean).join(' · ')) + '</small></span>' +
            '<span class="rp-date">' + esc(dayWord(p.posted_on)) + '</span>' +
            '<span class="rp-num rp-n1">' + (m[0] ? fmt(p[m[0]]) : '') + '</span>' +
            '<span class="rp-num rp-n2">' + (m[1] ? fmt(p[m[1]]) : '') + '</span>' +
            (ed && !pick ? rowMenu(['Edit', 'Remove']) : '<span></span>') + '</div>';
        }).join('') + '</div></div>';
    }).join('');
    if (pick) { wirePostPick(box); return; }
    if (ed) wireRows(box, function (id, act, btn) {
      var p = st.posts.filter(function (x) { return x.id === id; })[0];
      if (act === 'Edit') postSheet(p, btn);
      if (act === 'Remove') removePost(p);
    });
  }
  function firstLine(t) {
    return String(t || '').split(/\n/).map(function (x) { return x.trim(); }).filter(Boolean)[0] || '';
  }
  function wirePostPick(box) {
    var pick = st.postPick, head = function () { return st.host.querySelector('[data-m="head"]'); };
    var ids = function () { return Object.keys(pick).filter(function (k) { return pick[k]; }); };
    var count = function () {
      var n = ids().length, all = $('rpPostAll');
      $('rpPostCount').textContent = n + ' selected';
      all.checked = n === st.posts.length; all.indeterminate = n > 0 && n < st.posts.length;
      if ($('rpPostMove')) $('rpPostMove').disabled = !n;
      $('rpPostRemove').disabled = !n;
      Array.prototype.forEach.call(box.querySelectorAll('.rp-post-table'), function (t) {
        var rows = t.querySelectorAll('[data-pick]'), on = t.querySelectorAll('[data-pick]:checked').length, g = t.querySelector('[data-pickall]');
        if (g) { g.checked = on === rows.length; g.indeterminate = on > 0 && on < rows.length; }
      });
    };
    Array.prototype.forEach.call(box.querySelectorAll('[data-pick]'), function (i) {
      i.addEventListener('change', function () {
        var id = i.getAttribute('data-pick');
        if (i.checked) pick[id] = true; else delete pick[id];
        i.closest('.rp-post-row').classList.toggle('is-picked', i.checked);
        count();
      });
    });
    Array.prototype.forEach.call(box.querySelectorAll('[data-pickall]'), function (g) {
      g.addEventListener('change', function () {
        /* Read once: each row's change repaints this tick as it goes. */
        var on = g.checked;
        Array.prototype.forEach.call(g.closest('.rp-post-table').querySelectorAll('[data-pick]'), function (i) {
          if (i.checked !== on) { i.checked = on; i.dispatchEvent(new Event('change')); }
        });
      });
    });
    $('rpPostAll').addEventListener('change', function () {
      var on = $('rpPostAll').checked;
      st.posts.forEach(function (p) { if (on) pick[p.id] = true; else delete pick[p.id]; });
      paintPosts();
    });
    $('rpPostDone').addEventListener('click', function () { st.postPick = null; paintPosts(); });
    var setAccount = function (list, to) {
      return db.from('sm_report_posts').update({ platform_id: to }).in('id', list).select('id, platform_id').then(function (res) {
        if (res.error) throw res.error;
        var done = (res.data || []).map(function (x) { return x.id; });
        if (!done.length) throw new Error('Not moved. The database refused the request.');
        st.posts.forEach(function (p) { if (done.indexOf(p.id) > -1) p.platform_id = to; });
        return done;
      });
    };
    if ($('rpPostMove')) $('rpPostMove').addEventListener('change', function () {
      var to = $('rpPostMove').value;
      if (!to) return;
      var was = {};
      st.posts.forEach(function (p) { if (pick[p.id] && p.platform_id !== to) (was[p.platform_id] = was[p.platform_id] || []).push(p.id); });
      var moving = [].concat.apply([], Object.keys(was).map(function (k) { return was[k]; }));
      if (!moving.length) { $('rpPostMove').value = ''; return; }
      $('rpPostMove').disabled = true;
      var acc = st.platforms.filter(function (a) { return a.id === to; })[0];
      setAccount(moving, to).then(function () {
        st.postPick = {};
        sortPosts(); paintPosts();
        var word = moving.length + ' post' + (moving.length === 1 ? '' : 's') + ' moved to ' + (acc ? (acc.account_name || platWord(acc)) : 'another account');
        fileReport('report.saved', word);
        undoBar(word + '.', st.host.querySelector('.rp-posts'), function () {
          Object.keys(was).reduce(function (p0, k) { return p0.then(function () { return setAccount(was[k], k); }); }, Promise.resolve())
            .then(function () { sortPosts(); paintPosts(); }).catch(function (e) { say(head(), said(e), 'err'); });
        });
      }).catch(function (e) { $('rpPostMove').disabled = false; say(head(), said(e), 'err'); });
    });
    $('rpPostRemove').addEventListener('click', function () {
      var chosen = st.posts.filter(function (p) { return pick[p.id]; });
      if (!chosen.length) return;
      var n = chosen.length;
      window.ADspaceConfirm.ask({ title: 'Remove ' + n + ' post' + (n === 1 ? '' : 's') + '?', body: 'They leave this report.', go: 'Remove', tone: 'danger' }, function () {
        db.from('sm_report_posts').delete().in('id', chosen.map(function (p) { return p.id; })).select('id').then(function (res) {
          var gone = (res.data || []).map(function (x) { return x.id; });
          if (res.error || !gone.length) { say(head(), said(res.error || 'Not removed. The database refused the request.'), 'err'); return; }
          var left = chosen.filter(function (p) { return gone.indexOf(p.id) > -1; });
          st.posts = st.posts.filter(function (p) { return gone.indexOf(p.id) < 0; });
          st.postPick = st.posts.length > 1 ? {} : null;
          paintPosts();
          var word = left.length + ' post' + (left.length === 1 ? '' : 's') + ' removed';
          fileReport('report.saved', word);
          undoBar(word + '.', st.host.querySelector('.rp-posts'), function () {
            db.from('sm_report_posts').insert(left).select('*').then(function (x) {
              if (x.error) { say(head(), said(x.error), 'err'); return; }
              st.posts = st.posts.concat(x.data || []); sortPosts(); paintPosts();
            });
          });
        });
      });
    });
    count();
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
      return '<option value="' + esc(a.id) + '">' + esc((a.account_name || '') + ' · ' + platWord(a)) + '</option>';
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
        fileReport('report.saved', (p ? 'Post edited: ' : 'Post added: ') + (saved.title || saved.posted_on || ''));
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
    [/^(format|type|content type|post type|media type|media product type)$/, 'content_type'],
    [/^(link|url|permalink|post link)$/, 'url'],
    [/^(caption|description|text)$/, 'caption'],
    [/^(views?|impressions ?\/ ?views|views ?\/ ?impressions|video views|plays)$/, 'views'],
    [/^reach$/, 'reach'], [/^impressions$/, 'impressions'],
    [/^(interactions|post interactions|reactions, comments and shares)$/, 'interactions'], [/^(engagements?|engagement)$/, 'engagements'],
    [/^(likes|reactions)$/, 'likes'], [/^comments$/, 'comments'], [/^shares$/, 'shares'], [/^(saves|saved|favourites|favorites)$/, 'saves'],
    [/^(post id|media id)$/, 'post_id']
  ];
  /* Figures a day adds to a day. Reach is people, counted once each: a
     day's reach cannot be added to the next day's. */
  var ADDS = ['views', 'impressions', 'interactions', 'engagements', 'likes', 'comments', 'shares', 'saves'];
  /* An export's own word for its kind of post (Meta: Videos, Photos, IG
     reel, IG carousel…) read as the report's format. */
  function formatOf(v, url) {
    var f = String(v || '').trim().toLowerCase();
    if (FORMAT_WORD[f] && f) return f;
    if (/\/reels?\//.test(String(url || ''))) return 'reel';
    if (/reel/.test(f)) return 'reel';
    if (/carousel|album/.test(f)) return 'carousel';
    if (/stor(y|ies)/.test(f)) return 'story';
    if (/live/.test(f)) return 'live';
    if (/short/.test(f)) return 'short';
    if (/video/.test(f)) return 'video';
    if (/photo|image/.test(f)) return 'photo';
    if (/article/.test(f)) return 'article';
    if (/status|text|link|post/.test(f)) return 'post';
    return null;
  }
  var MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11 };
  /* A date written with slashes is read day first (12/09 is 12 Sept), as
     Malaysia writes it, unless the paste says otherwise: `mdy` reads it
     month first (Meta's exports: 09/01/2026 is 1 Sept). */
  function readDate(s, year, mdy) {
    s = String(s || '').trim();
    var m;
    if ((m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(s))) return ymd(new Date(+m[1], +m[2] - 1, +m[3]));
    if ((m = /^(\d{1,2})[\/.](\d{1,2})[\/.](\d{2,4})/.exec(s))) {
      var y = +m[3]; if (y < 100) y += 2000;
      var d = mdy ? +m[2] : +m[1], mo = mdy ? +m[1] : +m[2];
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      return ymd(new Date(y, mo - 1, d));
    }
    if ((m = /^(\d{1,2})[\s-]+([A-Za-z]{3,9})[\s-]*(\d{4})?/.exec(s)) && MONTHS[m[2].toLowerCase().slice(0, m[2].toLowerCase().indexOf('sept') === 0 ? 4 : 3)] != null) {
      return ymd(new Date(m[3] ? +m[3] : year, MONTHS[m[2].toLowerCase().slice(0, m[2].toLowerCase().indexOf('sept') === 0 ? 4 : 3)], +m[1]));
    }
    if ((m = /^([A-Za-z]{3,9})\s+(\d{1,2}),?\s*(\d{4})?/.exec(s)) && MONTHS[m[1].toLowerCase().slice(0, 3)] != null) {
      return ymd(new Date(m[3] ? +m[3] : year, MONTHS[m[1].toLowerCase().slice(0, 3)], +m[2]));
    }
    return null;
  }
  /* Meta writes Publish time in US Pacific time, whatever the page's own
     (2026-10-06: a post at 12:03 pm on 15 Sept in Malaysia read 14 Sept
     21:03), so its date is the Malaysian day of that moment. */
  function metaDay(s) {
    var m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2})/.exec(String(s || '').trim());
    if (!m || !window.Intl || !Intl.DateTimeFormat) return null;
    var wall = Date.UTC(+m[3], +m[1] - 1, +m[2], +m[4], +m[5]);
    var fmt = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Los_Angeles', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
    var offOf = function (t) {
      var q = {};
      fmt.formatToParts(new Date(t)).forEach(function (x) { q[x.type] = x.value; });
      return Date.UTC(+q.year, +q.month - 1, +q.day, +q.hour % 24, +q.minute) - t;
    };
    var utc = wall - offOf(wall);
    utc = wall - offOf(utc);
    var my = new Date(utc + 8 * 3600000);
    return my.getUTCFullYear() + '-' + String(my.getUTCMonth() + 1).padStart(2, '0') + '-' + String(my.getUTCDate()).padStart(2, '0');
  }
  /* Rows and cells as a spreadsheet copies them: a cell holding line
     breaks (a caption) arrives quoted, with "" for a quote inside it, and
     its breaks belong to the cell, not the table (the user, 2026-10-01). */
  function tableOf(text, sep) {
    var src = String(text || '').replace(/\r\n?/g, '\n'), rows = [], row = [], cell = '', q = false;
    for (var i = 0; i < src.length; i++) {
      var ch = src[i];
      if (q) {
        if (ch === '"' && src[i + 1] === '"') { cell += '"'; i++; }
        else if (ch === '"') q = false;
        else cell += ch;
      } else if (ch === '"' && cell === '') q = true;
      else if (ch === sep) { row.push(cell); cell = ''; }
      else if (ch === '\n') { row.push(cell); rows.push(row); row = []; cell = ''; }
      else cell += ch;
    }
    row.push(cell); rows.push(row);
    return rows.filter(function (r) { return r.some(function (c) { return String(c).trim(); }); });
  }
  /* Which way round the slashed dates in a paste run: a first part over
     12 can only be a day, a second part over 12 only a day too; a Meta
     export (Post ID and Publish time) is month first; else day first. */
  function dateOrder(dates, meta) {
    var dmy = false, mdy = false;
    dates.forEach(function (s) {
      var m = /^(\d{1,2})[\/.](\d{1,2})[\/.]\d{2,4}/.exec(String(s || '').trim());
      if (!m) return;
      if (+m[1] > 12) dmy = true;
      if (+m[2] > 12) mdy = true;
    });
    if (mdy && !dmy) return true;
    if (dmy) return false;
    return !!meta;
  }
  /* A paste, read into posts. A Meta Business Suite export is read as it
     comes (the user, 2026-10-02): its Title repeats the caption, so the
     caption is Description and the post is named by its format and date;
     the date is Publish time, month first; and each Post ID is one post.
     Its Date column says what a row holds: Lifetime (the post's figures to
     the day of the export, taken as they are) or one day (the days inside
     the report's period added up, reach left out). */
  function parseRows(text, year, period) {
    text = String(text || '').replace(/^\uFEFF/, '');
    var first = String(text || '').split(/\r?\n/)[0] || '';
    var sep = first.indexOf('\t') > -1 ? '\t' : ',';
    var table = tableOf(text, sep);
    if (table.length < 2) return { error: 'Paste a header row and at least one post.' };
    var names = table[0].map(function (h) { return h.replace(/^﻿/, '').trim().toLowerCase().replace(/\s+/g, ' '); });
    var head = names.map(function (k) {
      var hit = HEAD.filter(function (x) { return x[0].test(k); })[0];
      return hit ? hit[1] : null;
    });
    var meta = head.indexOf('post_id') > -1 && names.indexOf('publish time') > -1;
    /* Where a sheet names both a publish date and a plain Date, the plain
       one is the day a row's figures are for. */
    if (names.some(function (k) { return /^publish(ed)? (date|time)$/.test(k); })) {
      names.forEach(function (k, i) { if (head[i] === 'posted_on' && !/^publish(ed)? (date|time)$/.test(k)) head[i] = 'day'; });
    }
    /* Meta's Title repeats the caption, or holds it where Description is
       empty (a Facebook photo, 2026-10-06): it is read as the caption's
       stand-in, never as a title. */
    if (meta) names.forEach(function (k, i) { if (k === 'title') head[i] = 'alt_caption'; });
    var seen = {};
    head = head.map(function (k) { if (!k || seen[k]) return null; seen[k] = true; return k; });
    if (head.indexOf('posted_on') < 0) return { error: 'The header row needs a Date column.' };
    var col = function (k) { return head.indexOf(k); };
    var body = table.slice(1);
    var mdy = dateOrder(body.map(function (c) { return c[col('posted_on')]; })
      .concat(col('day') > -1 ? body.map(function (c) { return c[col('day')]; }) : []), meta);
    var rows = [], skipped = 0;
    body.forEach(function (cells) {
      var row = {}, ok = true;
      head.forEach(function (k, i) {
        if (!k) return;
        var v = (cells[i] || '').trim();
        if (k === 'posted_on') { row.posted_on = (meta && mdy && metaDay(v)) || readDate(v, year, mdy); if (!row.posted_on) ok = false; return; }
        if (k === 'day') { row.day = /^lifetime$/i.test(v) ? 'lifetime' : (readDate(v, year, mdy) || (v ? 'other' : null)); return; }
        if (k === 'post_id') { row.post_id = v || null; return; }
        if (k === 'caption') { var cv = String(cells[i] || '').replace(/^\s+|\s+$/g, ''); row.caption = cv || null; return; }
        if (k === 'alt_caption') { var av = String(cells[i] || '').replace(/^\s+|\s+$/g, ''); row.alt_caption = av || null; return; }
        if (['title', 'url'].indexOf(k) > -1) { row[k] = v || null; return; }
        if (k === 'content_type') { row.content_type = v; return; }
        var n = v.replace(/[, ]/g, '');
        row[k] = n === '' || n === '-' ? null : (/^\d+$/.test(n) ? Number(n) : (/^\d+(\.\d+)?k$/i.test(n) ? Math.round(parseFloat(n) * 1000) : null));
      });
      if ('alt_caption' in row) { if (!row.caption && row.alt_caption) row.caption = row.alt_caption; delete row.alt_caption; }
      var fm = formatOf(row.content_type, row.url);
      if (col('content_type') > -1 || fm) row.content_type = fm;
      if (ok) rows.push(row); else skipped++;
    });
    /* One post a Post ID (else a link). Lifetime rows stand; day rows are
       added up within the period, and a post with both keeps its lifetime. */
    var mode = null, days = 0, outside = 0, byKey = {}, out = [];
    rows.forEach(function (r) {
      var key = r.post_id || (r.day && r.url) || null;
      var daily = r.day && r.day !== 'lifetime';
      if (r.day === 'lifetime') mode = mode === 'daily' ? 'mixed' : (mode || 'lifetime');
      if (daily) mode = mode === 'lifetime' ? 'mixed' : (mode || 'daily');
      if (!key) { out.push(r); return; }
      var g = byKey[key];
      if (!g) { g = byKey[key] = { first: r, life: null, sum: null, n: 0 }; out.push(g); }
      if (r.day === 'lifetime') { g.life = r; return; }
      if (!daily) { g.life = g.life || r; return; }
      days++;
      if (period && (r.day < period[0] || r.day > period[1])) { outside++; return; }
      if (!g.sum) g.sum = {};
      ADDS.forEach(function (k) { if (r[k] != null) g.sum[k] = (g.sum[k] || 0) + r[k]; });
      g.n++;
    });
    out = out.map(function (g) {
      if (!g.first) return g;
      var base = g.life || g.first, row = {};
      Object.keys(base).forEach(function (k) { row[k] = base[k]; });
      if (!g.life) {
        ADDS.forEach(function (k) { if (k in row) row[k] = g.sum && g.sum[k] != null ? g.sum[k] : (g.sum ? 0 : null); });
        if ('reach' in row) row.reach = null;
      }
      return row;
    });
    out.forEach(function (r) { delete r.day; delete r.post_id; });
    /* Meta names no interactions or engagements column for Instagram (Likes,
       Comments, Shares, Saves) and gives Facebook's as Reactions, comments
       and shares (the user, 2026-10-02: the report read them unavailable).
       Where the paste has no interactions, they are the sum of the parts it
       has; where it has no engagements, they are the interactions, Meta's
       own measure of a post's engagement. */
    var PARTS = ['likes', 'comments', 'shares', 'saves'];
    var hasParts = PARTS.some(function (k) { return head.indexOf(k) > -1; });
    var addInter = head.indexOf('interactions') < 0 && hasParts;
    var addEng = head.indexOf('engagements') < 0 && (addInter || head.indexOf('interactions') > -1);
    out.forEach(function (r) {
      if (addInter && PARTS.some(function (k) { return r[k] != null; })) {
        r.interactions = PARTS.reduce(function (t, k) { return t + (r[k] || 0); }, 0);
      }
      if (addEng && r.interactions != null) r.engagements = r.interactions;
    });
    var columns = head.filter(function (k) { return k && k !== 'day' && k !== 'post_id' && k !== 'alt_caption' && !(mode && mode !== 'lifetime' && k === 'reach'); });
    if (addInter) columns.push('interactions');
    if (addEng) columns.push('engagements');
    return { rows: out, skipped: skipped, columns: columns, mode: mode, days: days, outside: outside, mdy: mdy };
  }

  function pasteSheet(opener) {
    var box = sheetShell('rpPasteSheet', 'Import from spreadsheet',
      '<section class="fsec"><div class="row"><div><label class="field-label" for="rpPasteAcc">Account</label><select class="select" id="rpPasteAcc"></select></div></div>' +
      '<div class="row"><div><label class="field-label" for="rpPasteText">Copy the rows from your spreadsheet, with the header row, and paste them here</label>' +
        '<textarea class="input rp-paste" id="rpPasteText" rows="8" placeholder="Date&#9;Title&#9;Views&#9;Interactions"></textarea></div></div>' +
      '<div class="row"><div><label class="field-label" for="rpPasteFile">Or choose the CSV file</label>' +
        '<input class="input" type="file" id="rpPasteFile" accept=".csv,.tsv,.txt,text/csv,text/plain"></div></div>' +
      '<p class="rp-paste-sum" id="rpPasteSum"></p></section>', FOOT('Import'));
    var acc = $('rpPasteAcc');
    acc.innerHTML = st.platforms.map(function (a) {
      return '<option value="' + esc(a.id) + '">' + esc((a.account_name || '') + ' · ' + platWord(a)) + '</option>';
    }).join('');
    $('rpPasteText').value = '';
    $('rpPasteFile').value = '';
    var sum = $('rpPasteSum'), sm = box.querySelector('[data-m="sheet"]');
    sum.textContent = ''; say(sm, '');
    var r0 = st.open, year = Number(String(r0.period_start).slice(0, 4));
    var period = r0.period_start && r0.period_end ? [String(r0.period_start).slice(0, 10), String(r0.period_end).slice(0, 10)] : null;
    var go = box.querySelector('[data-a="go"]');
    var plural = function (n, w) { return n + ' ' + w + (n === 1 ? '' : 's'); };
    /* A post already in this account is matched by its link and refreshed,
       never added twice. */
    var known = function (r) {
      if (!r.url) return null;
      return st.posts.filter(function (p) { return p.platform_id === acc.value && p.url === r.url; })[0] || null;
    };
    var read = function () {
      var out = parseRows($('rpPasteText').value, year, period);
      if (out.error) { sum.textContent = $('rpPasteText').value.trim() ? out.error : ''; go.disabled = true; return out; }
      var upd = out.rows.filter(known).length, add = out.rows.length - upd;
      var bits = [(add ? plural(add, 'post') + ' to add' : '') + (add && upd ? ', ' : '') + (upd ? plural(upd, 'post') + ' to update' : '') +
        (out.skipped ? ', ' + out.skipped + ' without a date skipped' : '') + '.'];
      if (out.mode === 'lifetime') bits.push('Lifetime figures, to the day of the export.');
      if (out.mode === 'daily' || out.mode === 'mixed') {
        bits.push(plural(out.days - out.outside, 'daily row') + ' added up' + (period ? ', ' + dayWord(period[0]) + ' to ' + dayWord(period[1]) : '') +
          (out.outside ? ' (' + out.outside + ' outside the period left out)' : '') + '. Reach is not added across days and is left blank.');
      }
      /* A file without Views or Reach (Meta's daily breakdown carries
         neither) is named before it is imported, never found empty after
         (the user, 2026-10-06). */
      var miss = ['views', 'reach'].filter(function (k) { return out.columns.indexOf(k) < 0 && !(k === 'reach' && out.mode && out.mode !== 'lifetime'); });
      if (miss.length) {
        bits.push('No ' + miss.map(function (k) { return METRIC_WORD[k]; }).join(' or ') + ' column in this file: ' +
          (miss.length > 1 ? 'those figures stay' : 'that figure stays') + ' empty. Meta\'s Lifetime export carries them.');
      }
      sum.classList.toggle('is-warn', miss.length > 0);
      bits.push('Columns: ' + out.columns.map(function (c) { return c === 'posted_on' ? 'Date' : c === 'content_type' ? 'Format' : (METRIC_WORD[c] || c.charAt(0).toUpperCase() + c.slice(1)); }).join(', ') + '.');
      sum.textContent = bits.join(' ');
      go.disabled = !out.rows.length;
      return out;
    };
    $('rpPasteText').oninput = read;
    acc.onchange = read;
    $('rpPasteFile').onchange = function () {
      var f = this.files && this.files[0];
      if (!f) return;
      var fr = new FileReader();
      fr.onload = function () { $('rpPasteText').value = String(fr.result || '').replace(/^﻿/, ''); read(); };
      fr.readAsText(f);
    };
    go.disabled = true;
    go.onclick = function () {
      var out = read();
      if (!out.rows || !out.rows.length) return;
      var n = st.posts.length, adds = [], ups = [];
      out.rows.forEach(function (r) {
        var p = known(r);
        if (p) ups.push([p, r]); else adds.push(Object.assign({ report_id: st.open.id, platform_id: acc.value, position: n + adds.length + 1 }, r));
      });
      go.disabled = true;
      var fail = function (e) { go.disabled = false; say(sm, said(e), 'err'); };
      var add = adds.length ? db.from('sm_report_posts').insert(adds).select('*') : Promise.resolve({ data: [] });
      add.then(function (res) {
        if (res.error) return fail(res.error);
        st.posts = st.posts.concat(res.data || []);
        return Promise.all(ups.map(function (u) {
          var patch = {};
          Object.keys(u[1]).forEach(function (k) { if (u[1][k] != null) patch[k] = u[1][k]; });
          return db.from('sm_report_posts').update(patch).eq('id', u[0].id).select('*');
        })).then(function (all) {
          var bad = all.filter(function (x) { return x.error || !(x.data || []).length; })[0];
          all.forEach(function (x) {
            var row = (x.data || [])[0];
            if (row) st.posts = st.posts.map(function (p) { return p.id === row.id ? row : p; });
          });
          var na = (res.data || []).length, nu = all.length - all.filter(function (x) { return x.error || !(x.data || []).length; }).length;
          if (na || nu) fileReport('report.saved', [na ? plural(na, 'post') + ' imported' : '', nu ? plural(nu, 'post') + ' updated' : ''].filter(Boolean).join(', ') +
            (out.mode === 'lifetime' ? ' (lifetime)' : out.mode ? ' (daily, added up)' : ''));
          sortPosts();
          paintPosts();
          if (bad) return fail(bad.error || { message: 'Not saved. The database refused the request.' });
          go.disabled = false;
          window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        });
      }).catch(fail);
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  // ---- The report's commentary ---------------------------------------------------------------
  /* An ads report: four fields, a summary, what worked, what to fix and the
     focus. An accounts report: the summary for the whole report, then one
     block a platform (the user, 2026-10-01: each platform's algorithm works
     differently, so it is read on its own): its line, highlights, what to
     improve and what we recommend, written to the account's own row, with
     the remarks on that platform's top three posts (each post's Why it
     stood out). What older reports wrote across all platforms is kept in a
     fold. A summary written as an executive summary before this form
     existed is read into the one field. */
  function paintText() {
    var box = st.host.querySelector('.rp-text');
    if (!box) return;
    var r = st.open, ins = r.insights || {}, ads = r.kind === 'ads';
    var fields = ads ? TEXT.ads : [TEXT.social[0]];
    var more = ads ? [] : TEXT.social.slice(1).concat(TEXT_MORE);
    var groups = ads ? [] : socialGroups();
    var valOf = function (k) {
      if (k !== 'intro') return ins[k];
      return [r.intro, ins.executive_summary].filter(function (x) { return String(x || '').trim(); }).join('\n\n');
    };
    var has = function (v) { return String(v || '').trim() !== ''; };
    if (!editable()) {
      var keep = function (rows) { return rows.filter(function (x) { return has(x[1]); }); };
      var secs = [{ title: '', rows: keep(fields.map(function (x) { return [x[1], valOf(x[0])]; })) }];
      groups.forEach(function (g) {
        secs.push({ title: g.label, rows: keep(PLAT_FIELDS.map(function (f) { return [f[1], g.lead[f[0]]]; })
          .concat(g.top.map(function (p) { return [postName(p), p.notable]; }))) });
      });
      secs.push({ title: 'Across all platforms', rows: keep(more.map(function (x) { return [x[1], valOf(x[0])]; })) });
      if (!secs.some(function (x) { return x.rows.length; })) { UI.emptyLine(box, 'No commentary.'); return; }
      box.innerHTML = factsCard(secs);
      return;
    }
    var area = function (id, label, ph, rowsN) {
      return '<div class="row"><div><label class="field-label" for="' + id + '">' + esc(label) + '</label>' +
        '<textarea class="input" id="' + id + '" rows="' + (rowsN || 3) + '"' + (ph ? ' placeholder="' + esc(ph) + '"' : '') + '></textarea></div></div>';
    };
    var platHtml = groups.map(function (g) {
      var id = g.lead.id;
      return '<section class="fsec rp-plat" data-acc="' + esc(id) + '"><h4 class="fsec-h">' + esc(g.label) + '</h4>' +
        '<div class="row"><div><label class="field-label" for="rpP_' + id + '_summary">Summary line</label><input class="input" id="rpP_' + id + '_summary" type="text"></div></div>' +
        area('rpP_' + id + '_worked', 'What worked', 'One point a line') +
        area('rpP_' + id + '_improve', 'Areas to improve', 'One point a line') +
        area('rpP_' + id + '_actions', 'Focus for next month', 'One point a line') +
        /* The posts' remarks are one a post, under a head of their own, so
           the platform's fields above read as the platform's (the user,
           2026-10-01). */
        (g.top.length ? '<h5 class="rp-tophead">Top posts</h5>' + g.top.map(function (p, i) {
          return area('rpN_' + p.id, (i + 1) + '. ' + postName(p), 'Why it stood out', 2);
        }).join('') : '') + '</section>';
    }).join('');
    /* What the AI is told (the language, the notes) sits with Write draft in
       one shaded block, apart from the report's own words below it (the
       user, 2026-10-05). */
    box.innerHTML = '<section class="panel rp-form">' +
      '<div class="rp-aidraft">' +
        '<div class="rp-airow"><div class="rp-ailang"><span class="rp-ailang-label" aria-hidden="true">Draft language</span>' +
          '<select class="select-sm" id="rpAiLang" data-seg aria-label="Draft language"><option value="en">English</option><option value="zh">中文</option></select></div>' +
        '<div class="rp-aiacts"><span class="rp-aileft" data-m="aileft" hidden></span>' +
        '<button class="btn btn-sm" type="button" data-a="aidraft">Write draft</button></div></div>' +
        '<details class="fmore rp-ainotes"><summary>Notes for the draft <span class="fmore-sum"></span></summary>' +
          '<div class="row"><div><label class="field-label" for="rpAiNotes">Reasons, changes, goal, next month\'s budget</label>' +
          '<textarea class="input" id="rpAiNotes" rows="3" data-none="Optional" data-some="Written"></textarea></div></div></details></div>' +
      '<div class="msg" data-m="ai"></div>' +
      '<p class="rp-hint">' + (ads ? 'One point a line. Start a line with a dash for a sub-point.' : 'One point a line.') + '</p>' +
      fields.map(function (x) { return area('rpT_' + x[0], x[1], x[2], x[3]); }).join('') +
      platHtml +
      /* What older reports wrote across all platforms stays editable there;
         a report with none of it shows no fold. */
      (more.some(function (x) { return has(valOf(x[0])); }) ? '<details class="fmore rp-across"><summary>Across all platforms <span class="fmore-sum"></span></summary>' +
        more.map(function (x) { return area('rpT_' + x[0], x[1], 'One point a line', 3).replace('<textarea ', '<textarea data-none="Optional" data-some="Written" '); }).join('') + '</details>' : '') +
      '<div class="rp-stepfoot"><button class="btn btn-primary" type="button" data-a="savenext">Save and continue</button>' +
        '<button class="btn" type="button" data-a="savetext">Save</button><div class="msg" data-m="text"></div></div></section>';
    fields.concat(more).forEach(function (x) { var el = $('rpT_' + x[0]); if (el) el.value = valOf(x[0]) || ''; });
    groups.forEach(function (g) {
      PLAT_FIELDS.forEach(function (f) { $('rpP_' + g.lead.id + '_' + f[0]).value = g.lead[f[0]] || ''; });
      g.top.forEach(function (p) { $('rpN_' + p.id).value = p.notable || ''; });
    });
    var fold = box.querySelector('details.rp-across');
    if (fold) fold.open = more.some(function (x) { return has(ins[x[0]]); });
    if (window.ADspaceForm) window.ADspaceForm.scan(box);
    var m = box.querySelector('[data-m="text"]');
    /* Every field the step shows, for Draft with AI's question before it
       replaces what is written. */
    var allIds = function () {
      var ids = fields.map(function (x) { return 'rpT_' + x[0]; });
      groups.forEach(function (g) {
        PLAT_FIELDS.forEach(function (f) { ids.push('rpP_' + g.lead.id + '_' + f[0]); });
        g.top.forEach(function (p) { ids.push('rpN_' + p.id); });
      });
      return ids;
    };
    var save = function (btn, then) {
      var insights = {};
      Object.keys(ins).forEach(function (k) { insights[k] = ins[k]; });
      delete insights.executive_summary;
      fields.concat(more).forEach(function (x) {
        if (x[0] === 'intro') return;
        var el = $('rpT_' + x[0]);
        if (!el) return;
        var v = el.value.trim();
        if (v) insights[x[0]] = v; else delete insights[x[0]];
      });
      var row = { intro: $('rpT_intro').value.trim() || null, headline: null, insights: insights };
      /* A platform's row and a post's remark are written only where they
         changed; each answer is read back, so a refusal is named. */
      var jobs = [];
      groups.forEach(function (g) {
        var patch = {}, changed = false;
        PLAT_FIELDS.forEach(function (f) {
          var v = $('rpP_' + g.lead.id + '_' + f[0]).value.trim() || null;
          patch[f[0]] = v;
          if ((g.lead[f[0]] || null) !== v) changed = true;
        });
        if (changed) jobs.push(db.from('sm_report_platforms').update(patch).eq('id', g.lead.id).select('*').then(function (res) {
          if (res.error || !(res.data || []).length) throw res.error || new Error('The database refused the change.');
          st.platforms = st.platforms.map(function (x) { return x.id === res.data[0].id ? res.data[0] : x; });
        }));
        g.top.forEach(function (p) {
          var v = $('rpN_' + p.id).value.trim() || null;
          if ((p.notable || null) === v) return;
          jobs.push(db.from('sm_report_posts').update({ notable: v }).eq('id', p.id).select('*').then(function (res) {
            if (res.error || !(res.data || []).length) throw res.error || new Error('The database refused the change.');
            st.posts = st.posts.map(function (x) { return x.id === res.data[0].id ? res.data[0] : x; });
          }));
        });
      });
      btn.disabled = true;
      jobs.unshift(db.from('sm_reports').update(row).eq('id', r.id).select('*').then(function (res) {
        if (res.error || !(res.data || []).length) throw res.error || new Error('The database refused the change.');
        st.open = res.data[0];
      }));
      Promise.all(jobs).then(function () {
        btn.disabled = false;
        fileReport('report.saved', 'Commentary');
        paintSteps();
        if (then) { then(); return; }
        say(m, 'Saved.', 'ok');
      }).catch(function (e) {
        btn.disabled = false;
        say(m, said(e), 'err');
      });
    };
    var sb = box.querySelector('[data-a="savetext"]'), sn = box.querySelector('[data-a="savenext"]');
    sb.addEventListener('click', function () { save(sb); });
    sn.addEventListener('click', function () { save(sn, function () { goStep('check'); }); });
    /* Draft with AI (the user, 2026-10-01): the report's own figures are sent
       to the report-draft function, and its draft fills the fields for the
       team to read and edit. Nothing is saved until Save; what is already
       written is replaced only once the person says so. An accounts report
       names the platforms and posts this step shows, so the draft answers
       for exactly these. */
    var ab = box.querySelector('[data-a="aidraft"]'), am = box.querySelector('[data-m="ai"]');
    /* What the figures cannot show (why spend moved, a form changed, an ad
       paused, the goal, next month's budget) is typed here and sent with the
       draft. It is never saved with the report, so it never reaches the
       client; this browser keeps it for the report until it is cleared. */
    var notes = $('rpAiNotes'), noteKey = 'adspace-draft-notes:' + r.id;
    try { notes.value = localStorage.getItem(noteKey) || ''; } catch (e) { /* storage refused */ }
    var notesFold = notes.closest('details');
    if (notes.value) notesFold.open = true;
    if (notesFold.__paint) notesFold.__paint();
    notes.addEventListener('input', function () {
      try { if (notes.value.trim()) localStorage.setItem(noteKey, notes.value); else localStorage.removeItem(noteKey); } catch (e) { /* storage refused */ }
    });
    /* The report's language (`sm_reports.lang`, the user, 2026-10-01): the
       draft is written in it and the PDF prints in it, the cover and the
       file name staying English. Set beside Draft with AI and saved at once;
       a new report takes the main contact's preferred language. */
    var lang = $('rpAiLang'), langReady = false;
    lang.addEventListener('change', function () {
      if (!langReady) return;
      var v = lang.value === 'zh' ? 'zh' : 'en', was = r.lang === 'zh' ? 'zh' : 'en';
      if (v === was) return;
      db.from('sm_reports').update({ lang: v }).eq('id', r.id).select('id').then(function (x) {
        if (x.error || !(x.data || []).length) throw x.error || new Error('The database refused the change.');
        r.lang = v; if (st.open && st.open.id === r.id) st.open.lang = v;
      }).catch(function (err) {
        lang.value = was; lang.dispatchEvent(new Event('change'));
        say(am, said(err), 'err');
      });
    });
    lang.value = r.lang === 'zh' ? 'zh' : 'en';
    lang.dispatchEvent(new Event('change'));
    langReady = true;
    var fill = function (id, v) { var el = $(id); if (el && typeof v === 'string') el.value = v; };
    var put = function (dr) {
      fields.forEach(function (x) { fill('rpT_' + x[0], dr[x[0]]); });
      (dr.platforms || []).forEach(function (pl) {
        PLAT_FIELDS.forEach(function (f) { fill('rpP_' + pl.ref + '_' + f[0], pl[f[0]]); });
      });
      (dr.posts || []).forEach(function (pp) { fill('rpN_' + pp.ref, pp.remark); });
    };
    /* The step on screen for this report, or nothing once the person has
       moved on: a draft answers wherever they are now, not where they
       pressed. */
    var rid = r.id;
    var here = function () {
      var b = st.open && st.open.id === rid && st.host && st.host.querySelector('.rp-text [data-a="aidraft"]');
      return b ? { b: b, m: st.host.querySelector('.rp-text [data-m="ai"]') } : null;
    };
    var draft = function () {
      ab.disabled = true; ab.textContent = 'Drafting';
      say(am, '');
      aiRun[rid] = true;
      var body = { report_id: rid, notes: notes.value.trim(), lang: lang.value };
      var asked = { r: st.open, c: st.client, lang: lang.value === 'zh' ? 'Chinese' : 'English' };
      if (!ads) {
        body.platforms = groups.map(function (g) { return g.lead.id; });
        body.posts = [].concat.apply([], groups.map(function (g) { return g.top.map(function (p) { return p.id; }); }));
      }
      db.functions.invoke('report-draft', { body: body }).then(function (res) {
        var d = res && res.data;
        if (res.error || !d || d.error || !d.draft) { var x = new Error((d && d.error) || 'ai-failed'); x.d = d; throw x; }
        return storeDraft(rid, d.draft).then(function (before) { return { draft: d.draft, before: before }; },
          function (err) { return { draft: d.draft, unsaved: said(err) }; });
      }).catch(function (e) {
        return { said: e && e.message === 'ai-limit' ? aiLimit(e.d) : (AI_SAID[e && e.message] || said(e)) };
      }).then(function (out) {
        delete aiRun[rid];
        if (out.draft) fileReport('report.ai_drafted', 'Draft · ' + asked.lang, asked.r, asked.c);
        else fileReport('report.ai_failed', 'Draft · ' + out.said, asked.r, asked.c);
        var h = here();
        /* Away from the step: the answer waits for this report and is put
           in the fields when the step is painted again, so a paid draft is
           never lost to a change of screen. */
        if (!h) { aiKept[rid] = out; return; }
        h.b.disabled = false; h.b.textContent = 'Write draft';
        if (out.draft) told(out, h.m); else say(h.m, out.said, 'err');
        paintLeft();
      });
    };
    /* Drafted and saved, with Undo; or drafted and refused, kept in the
       fields to save by hand. */
    var told = function (out, m) {
      put(out.draft);
      if (out.unsaved) { say(m, 'Drafted, but not saved: ' + out.unsaved + ' Save before leaving.', 'err'); return; }
      Object.assign(st.open, { intro: out.draft.intro != null ? out.draft.intro : st.open.intro });
      say(m, 'Drafted and saved.', 'ok');
      undoBar('Draft saved.', m, function () {
        /* Read the report again: the page's copy still holds the draft. */
        restoreDraft(rid, out.before).then(function () {
          if (st.open && st.open.id === rid) st.open = { id: rid };
          openReport(rid, true);
        }).catch(function (e) { say(m, said(e), 'err'); });
      });
    };
    /* What is left, beside the button, as `1 left` (the user, 2026-10-01):
       read from the database as it counts a press, so the figure is the one
       a press would meet. At 0 the button rests and the line under it says
       why and when the next is free. */
    var lastLeft = null;
    var paintLeft = function () {
      db.rpc('ai_draft_left', { p_report: rid }).then(function (res) {
        var d = res && res.data, h = here();
        if (!h) return;
        var line = st.host.querySelector('.rp-text [data-m="aileft"]');
        if (!line) return;
        if (res.error || !d || d.error || d.left == null) { line.hidden = true; return; }
        line.hidden = false;
        lastLeft = d.left;
        line.textContent = d.left + ' left';
        line.classList.toggle('is-out', !d.left);
        if (aiRun[rid]) return;
        h.b.disabled = !d.left;
        if (!d.left && !h.m.textContent) say(h.m, aiLimit(d), 'warn');
      }).catch(function () { /* an older database: no line */ });
    };
    if (aiRun[rid]) { ab.disabled = true; ab.textContent = 'Drafting'; }
    if (aiKept[rid]) {
      var kept = aiKept[rid]; delete aiKept[rid];
      if (kept.draft) told(kept, am); else say(am, kept.said, 'err');
    }
    paintLeft();
    /* Every press asks first (the user, 2026-10-01: a draft is counted, so
       a stray click must not spend one). */
    ab.addEventListener('click', function () {
      var written = allIds().some(function (id) { return $(id) && $(id).value.trim(); });
      var uses = 'This uses one draft' + (lastLeft != null ? ' (' + lastLeft + ' left).' : '.');
      window.ADspaceConfirm.ask(written
        ? { title: 'Replace the commentary?', body: uses + ' The draft replaces what is written and is saved as it arrives; Undo puts the earlier text back.', go: 'Replace' }
        : { title: 'Write a draft?', body: uses + ' The draft is saved to the report as it arrives.', go: 'Draft' }, draft);
    });
  }
  /* A draft is saved to the report the moment it arrives (the user,
     2026-10-04: a draft left unsaved was lost on Back, and paid for all the
     same). What it replaces is kept, so Undo puts it back. Written from the
     report's own rows, not the screen, so it holds wherever the person is. */
  function storeDraft(rid, dr) {
    return Promise.all([
      db.from('sm_reports').select('id, intro, insights').eq('id', rid).maybeSingle(),
      db.from('sm_report_platforms').select('id, summary, worked, improve, actions').eq('report_id', rid),
      db.from('sm_report_posts').select('id, notable').eq('report_id', rid)
    ]).then(function (got) {
      var bad = got.filter(function (x) { return x.error; })[0];
      if (bad) throw bad.error;
      var rep = got[0].data;
      if (!rep) throw new Error('not-found');
      var before = { intro: rep.intro, insights: rep.insights || {}, platforms: {}, posts: {} };
      var ins = Object.assign({}, rep.insights || {}), row = { insights: ins };
      Object.keys(dr).forEach(function (k) {
        if (typeof dr[k] !== 'string') return;
        if (k === 'intro') row.intro = dr[k]; else ins[k] = dr[k];
      });
      var ok = function (res) { if (res.error || !(res.data || []).length) throw res.error || new Error('The database refused the change.'); };
      var jobs = [db.from('sm_reports').update(row).eq('id', rid).select('id').then(ok)];
      var plats = got[1].data || [], posts = got[2].data || [];
      (dr.platforms || []).forEach(function (pl) {
        var was = plats.filter(function (x) { return x.id === pl.ref; })[0];
        if (!was) return;
        var patch = {};
        PLAT_FIELDS.forEach(function (f) { if (typeof pl[f[0]] === 'string') patch[f[0]] = pl[f[0]]; });
        before.platforms[was.id] = { summary: was.summary, worked: was.worked, improve: was.improve, actions: was.actions };
        jobs.push(db.from('sm_report_platforms').update(patch).eq('id', was.id).select('id').then(ok));
      });
      (dr.posts || []).forEach(function (pp) {
        var was = posts.filter(function (x) { return x.id === pp.ref; })[0];
        if (!was || typeof pp.remark !== 'string') return;
        before.posts[was.id] = was.notable;
        jobs.push(db.from('sm_report_posts').update({ notable: pp.remark }).eq('id', was.id).select('id').then(ok));
      });
      return Promise.all(jobs).then(function () { return before; });
    });
  }
  function restoreDraft(rid, before) {
    var ok = function (res) { if (res.error || !(res.data || []).length) throw res.error || new Error('The database refused the change.'); };
    var jobs = [db.from('sm_reports').update({ intro: before.intro, insights: before.insights }).eq('id', rid).select('id').then(ok)];
    Object.keys(before.platforms).forEach(function (id) { jobs.push(db.from('sm_report_platforms').update(before.platforms[id]).eq('id', id).select('id').then(ok)); });
    Object.keys(before.posts).forEach(function (id) { jobs.push(db.from('sm_report_posts').update({ notable: before.posts[id] }).eq('id', id).select('id').then(ok)); });
    return Promise.all(jobs);
  }
  /* A draft is paid for once Claude is asked, whatever happens to the page.
     While one is being written, closing or reloading the tab asks first
     (the browser's own question), and an answer that arrives after the
     person has moved to another screen is kept for its report
     (`aiKept`) and filled in when its Commentary step is next shown. */
  var aiRun = {}, aiKept = {};
  window.addEventListener('beforeunload', function (e) {
    if (!Object.keys(aiRun).length) return;
    e.preventDefault();
    e.returnValue = '';
  });
  /* The database counts every press (2026-10-05): a colleague has one draft
     and one figures check on a report a day, an admin five of each, all
     within ten AI uses a day (an admin's twenty), reset at 12:00 am. A
     refusal says which and when the next is free. */
  function aiLimit(d) {
    d = d || {};
    var at = d.next ? new Date(d.next) : null;
    var when = at && !isNaN(at.getTime())
      ? at.getDate() + ' ' + ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'][at.getMonth()] + ', ' +
        ((at.getHours() % 12) || 12) + ':' + String(at.getMinutes()).padStart(2, '0') + (at.getHours() < 12 ? 'am' : 'pm')
      : '';
    if (d.scope === 'stopped') return 'AI is turned off for you. An admin can turn it on.';
    var n = d.limit == null ? 1 : d.limit;
    var who = d.scope === 'report' ? (n === 0 ? 'Drafts are turned off.' : 'You have used ' + (n === 1 ? 'today\'s draft' : 'your ' + n + ' drafts') + ' on this report.')
      : d.scope === 'report_check' ? (n === 0 ? 'Figures checks are turned off.' : 'You have used ' + (n === 1 ? 'today\'s figures check' : 'your ' + n + ' figures checks') + ' on this report.')
      : 'You have used your ' + (d.limit || 10) + ' AI uses for today.';
    return who + (at && !isNaN(at.getTime()) ? ' Resets at ' + aiClock(d.next) + '.' : '');
  }
  var AI_SAID = {
    'needs-update': 'This needs a database update.',
    'ai-not-set-up': 'AI needs its key in Supabase.',
    'ai-key': 'The AI key was refused. Check it in Supabase.',
    'ai-busy': 'The AI service is busy. Try again in a minute.',
    'ai-credit': 'The AI account has no credit. Top up in the Claude Console.',
    'ai-model': 'The AI model name in Supabase is not recognised.',
    'ai-failed': 'No draft came back. Try again.',
    'ai-incomplete': 'No draft came back. Try again.',
    'no-ads': 'Add the period\'s ads before drafting.',
    'no-posts': 'Add the month\'s posts before drafting.',
    'not-draft': 'Only a draft can be drafted.',
    'denied': 'This needs a higher access level for Reports.',
    'not-found': 'This report no longer exists.'
  };

  // ---- The advertising report ------------------------------------------------------------
  /* An advertising report is the account's figures for the period, one row
     an ad and objective, and the team's words. The account's reach is typed,
     because it cannot be added up from the ads; impressions and spend are
     summed from the ads where nobody typed them. */
  var OBJECTIVES = [['leads', 'Leads', 'Leads'], ['messaging', 'Messaging', 'Messaging conversations'], ['sales', 'Sales', 'Purchases'],
                    ['traffic', 'Traffic', 'Link clicks'], ['engagement', 'Engagement', 'Engagements'],
                    ['awareness', 'Awareness', 'Reach'], ['app', 'App promotion', 'App installs']];
  var OBJ_WORD = {};
  OBJECTIVES.forEach(function (o) { OBJ_WORD[o[0]] = o[1]; });
  /* Platforms (2026-10-05): one Advertising Report holds Meta's ads and
     TikTok's. A row names its platform; a row that names none is Meta's. */
  var AD_PLATS = [['meta', 'Meta'], ['tiktok', 'TikTok']];
  function adPlat(a) { return a && a.platform === 'tiktok' ? 'tiktok' : 'meta'; }
  function adPlatWord(k) { return k === 'tiktok' ? 'TikTok' : 'Meta'; }
  function adPlatsHeld() { return AD_PLATS.filter(function (p) { return st.ads.some(function (a) { return adPlat(a) === p[0]; }); }).map(function (p) { return p[0]; }); }
  function hasTikTok() { return st.ads.some(function (a) { return adPlat(a) === 'tiktok'; }) || !!((st.open || {}).ads_totals || {}).tiktok; }
  var RESULT_TYPES = ['Leads', 'Messaging conversations', 'Purchases', 'Link clicks', 'Landing page views', 'Engagements',
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
  /* Ads Manager's own key for a result reads as its word (js/smreport.js). */
  function adName(x) { var AN = window.ADspaceSmReport && window.ADspaceSmReport.adName; return AN ? AN(x) : (x || ''); }
  function resultWord(x) { var RW = window.ADspaceSmReport && window.ADspaceSmReport.resultWord; return RW ? RW(x) : (x || ''); }
  /* The row reads the short word the PDF prints: Leads, never Leads (form). */
  function adCpr(a) {
    if (a.cpr != null && a.cpr !== '') return Number(a.cpr);
    var reach = /reach/i.test(String(a.result_label || ''));
    if (a.spend == null || !Number(a.results)) return null;
    return Number(a.spend) / Number(a.results) * (reach ? 1000 : 1);
  }
  /* Each objective's ads in the order the PDF ranks them (the user,
     2026-10-01): cheapest cost per result first, then those with no result
     by what they spent, most first; the paste order only breaks a tie. */
  function sortAds() {
    var ord = {}; OBJECTIVES.forEach(function (o, i) { ord[o[0]] = i; });
    st.ads.sort(function (a, b) {
      var d = (adPlat(a) === 'tiktok') - (adPlat(b) === 'tiktok') || ord[a.objective] - ord[b.objective];
      if (d) return d;
      var ca = adCpr(a), cb = adCpr(b);
      if (ca === null && cb !== null) return 1;
      if (cb === null && ca !== null) return -1;
      if (ca !== null && cb !== null && ca !== cb) return ca - cb;
      if (ca === null && cb === null && Number(b.spend || 0) !== Number(a.spend || 0)) return Number(b.spend || 0) - Number(a.spend || 0);
      return a.position - b.position;
    });
  }

  /* The account's figures: typed where they cannot be added up, the rest
     summed from the ads; the previous period where this is not the first
     month, carried forward from the last advertising report. */
  function paintTotals() {
    var box = st.host.querySelector('.rp-totals');
    if (!box) return;
    var r = st.open, t = r.ads_totals || {};
    /* TikTok's figures are its own (`ads_totals.tiktok`): reach is never
       added across platforms, so Step 1 asks each platform for its own. The
       figures at the top level, the objectives' and the previous period's
       are Meta's, as every report before TikTok holds them. */
    var tk = hasTikTok(), tt = t.tiktok || {};
    var metaAds = st.ads.filter(function (a) { return adPlat(a) === 'meta'; });
    var tkAds = st.ads.filter(function (a) { return adPlat(a) === 'tiktok'; });
    var sumOf = function (list, f) { return list.reduce(function (s0, a) { return s0 + (Number(a[f]) || 0); }, 0); };
    var sumSpend = sumOf(metaAds, 'spend'), sumImpr = sumOf(metaAds, 'impressions');
    var objs = OBJECTIVES.filter(function (o) { return metaAds.some(function (a) { return a.objective === o[0]; }); });
    var on = function (w) { return tk ? w + ' · Meta' : w; };
    /* An objective's results as the PDF adds them from its ads, shown in its
       fields until a figure is typed (the user, 2026-10-02: Step 1 filled
       reach, impressions and spend and left these blank). Read live, so an
       edited or re-imported ad is in step; a mix of result types is named
       part by part, since the PDF adds them as one. */
    var SR = window.ADspaceSmReport;
    var objSum = function (k) {
      var by = {}, order = [], spent = 0;
      metaAds.forEach(function (a) {
        if (a.objective !== k) return;
        spent += Number(a.spend) || 0;
        var w = a.result_label && SR && SR.shortResult ? SR.shortResult(a.result_label) : 'Results';
        if (!(w in by)) { by[w] = 0; order.push(w); }
        by[w] += Number(a.results) || 0;
      });
      var parts = order.map(function (w) { return [w, by[w]]; });
      return {
        total: parts.reduce(function (n, x) { return n + x[1]; }, 0), spent: spent,
        type: parts.length === 1 ? parts[0][0] : 'Results',
        line: parts.length === 1 ? fmt(parts[0][1]) + ' from the ads' : parts.map(function (x) { return fmt(x[1]) + ' ' + x[0]; }).join(' + ')
      };
    };
    if (!editable()) {
      var now = [['Total reach', fmt(t.reach)], ['Total impressions', t.impressions != null ? fmt(t.impressions) : fmt(sumImpr) + ' (from the ads)'],
        ['Amount spent', t.spend != null ? money2(t.spend) : money2(sumSpend) + ' (from the ads)']];
      var byObj = objs.map(function (o) {
        var gg = (t.groups || {})[o[0]] || {}, sm = objSum(o[0]);
        /* A count alone, as the PDF prints it; only a mix names its parts. */
        var res = gg.results != null ? fmt(gg.results) : (sm.line.indexOf(' from the ads') > -1 ? fmt(sm.total) : sm.line);
        return [o[1], res + ' · ' + money2(sm.spent).replace(/ /g, '\u00a0')];
      });
      var before = r.first_month ? [['Comparison', 'First month of ads, with the reading guidance']] :
        [['Period', t.prev_start ? periodWord(t.prev_start, t.prev_end) : '—'], ['Reach', fmt(t.prev_reach)],
          ['Impressions', fmt(t.prev_impressions)], ['Amount spent', money2(t.prev_spend)]];
      var cards = [{ title: on('This period'), rows: now }, { title: on('Results by objective'), rows: byObj }, { title: on('Previous period'), rows: before }];
      if (tk) {
        cards.push({ title: 'This period · TikTok', rows: [['Total reach', fmt(tt.reach)],
          ['Total impressions', tt.impressions != null ? fmt(tt.impressions) : fmt(sumOf(tkAds, 'impressions')) + ' (from the ads)'],
          ['Amount spent', tt.spend != null ? money2(tt.spend) : money2(sumOf(tkAds, 'spend')) + ' (from the ads)']] });
        if (!r.first_month) cards.push({ title: 'Previous period · TikTok', rows: [['Reach', fmt(tt.prev_reach)], ['Impressions', fmt(tt.prev_impressions)], ['Amount spent', money2(tt.prev_spend)]] });
      }
      box.innerHTML = factsCard(cards);
      return;
    }
    box.innerHTML = '<section class="panel rp-form">' +
      '<label class="tickline"><input type="checkbox" id="rpFirst"> First month of ads, with no comparison</label>' +
      '<section class="fsec"><h4 class="fsec-h">' + on('This period') + '</h4>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpTReach">Total reach</label><input class="input" id="rpTReach" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpTImpr">Total impressions</label><input class="input" id="rpTImpr" data-num="int" type="text" inputmode="numeric" placeholder="' + esc(fmt(sumImpr)) + ' from the ads"></div>' +
        '<div><label class="field-label" for="rpTSpend">Amount spent</label><input class="input" id="rpTSpend" data-num="money" type="text" inputmode="decimal" placeholder="' + esc(money2(sumSpend)) + ' from the ads"></div></div></section>' +
      (tk ? '<section class="fsec" id="rpTkSec"><h4 class="fsec-h">This period · TikTok</h4>' +
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpKReach">Total reach</label><input class="input" id="rpKReach" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpKImpr">Total impressions</label><input class="input" id="rpKImpr" data-num="int" type="text" inputmode="numeric" placeholder="' + esc(fmt(sumOf(tkAds, 'impressions'))) + ' from the ads"></div>' +
        '<div><label class="field-label" for="rpKSpend">Amount spent</label><input class="input" id="rpKSpend" data-num="money" type="text" inputmode="decimal" placeholder="' + esc(money2(sumOf(tkAds, 'spend'))) + ' from the ads"></div></div></section>' : '') +
      '<section class="fsec" id="rpPrevSec"><h4 class="fsec-h">Previous period</h4>' +
        '<div class="row fgrid"><div><label class="field-label" for="rpPStart">Start</label><input class="input" id="rpPStart" type="date"></div>' +
        '<div><label class="field-label" for="rpPEnd">End</label><input class="input" id="rpPEnd" type="date"></div></div>' +
        /* With TikTok held each field names its platform, so the rows keep
           the form's own rhythm. */
        '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpPReach">' + (tk ? 'Meta reach' : 'Reach') + '</label><input class="input" id="rpPReach" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpPImpr">' + (tk ? 'Meta impressions' : 'Impressions') + '</label><input class="input" id="rpPImpr" data-num="int" type="text" inputmode="numeric"></div>' +
        '<div><label class="field-label" for="rpPSpend">' + (tk ? 'Meta amount spent' : 'Amount spent') + '</label><input class="input" id="rpPSpend" data-num="money" type="text" inputmode="decimal"></div></div>' +
        (tk ? '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpKPReach">TikTok reach</label><input class="input" id="rpKPReach" data-num="int" type="text" inputmode="numeric"></div>' +
          '<div><label class="field-label" for="rpKPImpr">TikTok impressions</label><input class="input" id="rpKPImpr" data-num="int" type="text" inputmode="numeric"></div>' +
          '<div><label class="field-label" for="rpKPSpend">TikTok amount spent</label><input class="input" id="rpKPSpend" data-num="money" type="text" inputmode="decimal"></div></div>' : '') +
      '</section>' +
      (objs.length ? '<details class="fmore" data-none="Added up from the ads" data-some="Typed for some objectives"><summary>' + on('Results by objective') + '</summary>' +
        objs.map(function (o) {
          var sm = objSum(o[0]);
          return '<div class="row fgrid-3 fgrid"><div><label class="field-label" for="rpGR_' + o[0] + '">' + esc(o[1]) + ' results</label>' +
            '<input class="input" id="rpGR_' + o[0] + '" data-gres="' + o[0] + '" data-num="int" type="text" inputmode="numeric" placeholder="' + esc(sm.line) + '"></div>' +
            '<div><label class="field-label" for="rpGL_' + o[0] + '">Result type</label><input class="input" id="rpGL_' + o[0] + '" data-glab="' + o[0] + '" type="text" list="rpResultTypes" placeholder="' + esc(sm.type) + '"></div>' +
            /* What the objective spent, added up from its ads, as the PDF's
               table prints it beside the results (the user, 2026-10-02). */
            '<div><span class="field-label" id="rpGS_' + o[0] + 'L">Amount spent</span><div class="readfield" id="rpGS_' + o[0] + '" aria-labelledby="rpGS_' + o[0] + 'L">' + esc(money2(sm.spent)) + '</div></div></div>';
        }).join('') + '</details>' : '') +
      '<datalist id="rpResultTypes">' + RESULT_TYPES.map(function (x) { return '<option value="' + esc(x) + '">'; }).join('') + '</datalist>' +
      '<div class="rp-stepfoot"><button class="btn btn-primary" type="button" data-a="savenext">Save and continue</button>' +
        '<button class="btn" type="button" data-a="savetotals">Save</button><div class="msg" data-m="totals"></div></div></section>';
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    $('rpFirst').checked = !!r.first_month;
    v('rpTReach', t.reach); v('rpTImpr', t.impressions); v('rpTSpend', t.spend);
    v('rpPStart', t.prev_start); v('rpPEnd', t.prev_end); v('rpPReach', t.prev_reach); v('rpPImpr', t.prev_impressions); v('rpPSpend', t.prev_spend);
    if (tk) { v('rpKReach', tt.reach); v('rpKImpr', tt.impressions); v('rpKSpend', tt.spend); v('rpKPReach', tt.prev_reach); v('rpKPImpr', tt.prev_impressions); v('rpKPSpend', tt.prev_spend); }
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
      var kt = {};
      if (tk) [['reach', 'rpKReach'], ['impressions', 'rpKImpr'], ['spend', 'rpKSpend'], ['prev_reach', 'rpKPReach'], ['prev_impressions', 'rpKPImpr'], ['prev_spend', 'rpKPSpend']].forEach(function (f) {
        var raw = $(f[1]).value.trim();
        if (!raw) return;
        var n = numIn(raw);
        if (n === null || n < 0) { bad = bad || $(f[1]); return; }
        kt[f[0]] = n;
      });
      if (bad) { say(m, 'A figure is a number.', 'err'); bad.focus(); return; }
      if (Object.keys(kt).length) out.tiktok = kt;
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
        fileReport('report.saved', 'Figures');
        paintSteps();
        if (then) { then(); return; }
        say(m, 'Saved.', 'ok');
      });
    };
    var sb = box.querySelector('[data-a="savetotals"]'), sn = box.querySelector('[data-a="savenext"]');
    sb.addEventListener('click', function () { saveTotals(sb); });
    sn.addEventListener('click', function () { saveTotals(sn, function () { goStep('ads'); }); });
  }

  /* Several ads at once (the user, 2026-10-01): Select puts a tick on every
     row and a bar over the list, which moves the ticked ads to another
     objective or removes them, each with its Undo. */
  function paintAds() {
    paintSteps();
    var box = st.host.querySelector('.rp-ads');
    if (!box) return;
    var ed = editable();
    var pickBtn = st.host.querySelector('[data-a="pickads"]');
    if (!ed || st.ads.length < 2) st.adPick = null;
    if (pickBtn) pickBtn.hidden = !ed || st.ads.length < 2 || !!st.adPick;
    if (!st.ads.length) {
      UI.emptyLine(box, 'No ads.');
      return;
    }
    var pick = st.adPick;
    if (pick) Object.keys(pick).forEach(function (id) { if (!st.ads.some(function (a) { return a.id === id; })) delete pick[id]; });
    var tick = function (id, label, on) {
      return '<span class="rp-pick"><input class="trow-pick" type="checkbox"' + (id ? ' data-pick="' + esc(id) + '"' : ' data-pickall') +
        (on ? ' checked' : '') + ' aria-label="' + esc(label) + '"></span>';
    };
    var bar = pick ? '<div class="bulkbar rp-adbar">' +
      '<label class="tickline bulkbar-all"><input type="checkbox" id="rpAdAll"> <span id="rpAdCount"></span></label>' +
      '<span class="bulkbar-acts"><select class="select select-sm" id="rpAdMove" aria-label="Move to objective"><option value="">Move to objective</option>' +
        OBJECTIVES.map(function (o) { return '<option value="' + o[0] + '">' + esc(o[1]) + '</option>'; }).join('') + '</select>' +
      '<button class="btn btn-sm btn-danger" id="rpAdRemove" type="button">Remove</button></span>' +
      '<button class="btn btn-sm btn-quiet bulkbar-done" id="rpAdDone" type="button">Done</button></div>' : '';
    /* A table an objective; with both platforms, an objective a platform
       (Traffic · TikTok), as the PDF heads them. */
    var held = adPlatsHeld(), multi = held.length > 1;
    box.innerHTML = bar + (held.length ? held : ['meta']).map(function (pk) { return OBJECTIVES.map(function (o) {
      var ads = st.ads.filter(function (a) { return a.objective === o[0] && adPlat(a) === pk; });
      if (!ads.length) return '';
      var spend = ads.reduce(function (s0, a) { return s0 + (Number(a.spend) || 0); }, 0);
      return '<div class="rp-postgroup"><p class="rp-group">' + esc(o[1] + (multi ? ' · ' + adPlatWord(pk) : '')) +
        ' <span class="mute">' + ads.length + ' ad' + (ads.length === 1 ? '' : 's') + ' · ' + esc(money2(spend)) + '</span></p>' +
        '<div class="crm-table softpanel rp-ad-table' + (pick ? ' is-picking' : '') + '" data-obj="' + o[0] + '">' +
        '<div class="crm-head rp-ad-row">' + (pick ? tick(null, 'Select every ' + o[1] + ' ad', ads.every(function (a) { return pick[a.id]; })) : '') +
          '<span></span><span>Ad</span><span>Amount spent</span><span>Results</span><span>Cost per result</span><span></span></div>' +
        ads.map(function (a) {
          /* No result word on the row (the user, 2026-10-02): the objective
             heads the table, as in the PDF. */
          var sub = [a.audience ? a.audience + ' audience' : '', a.starts_on ? dayWord(a.starts_on) + (a.ends_on ? ' to ' + dayWord(a.ends_on) : '') : ''].filter(Boolean).join(' · ');
          var c = adCpr(a);
          return '<div class="crm-row rp-ad-row' + (pick && pick[a.id] ? ' is-picked' : '') + '" data-id="' + esc(a.id) + '">' +
            (pick ? tick(a.id, 'Select ' + a.name, !!pick[a.id]) : '') +
            '<span class="rp-thumb">' + (a.thumb_data ? '<img src="' + esc(a.thumb_data) + '" alt="">' : '') + '</span>' +
            '<span class="rp-name"><b>' + esc(adName(a.name)) + '</b><small>' + esc(sub) + '</small>' + adIdsHtml(a) + '</span>' +
            '<span class="rp-num rp-spend">' + esc(money2(a.spend)) + '</span>' +
            '<span class="rp-num rp-res">' + esc(fmt(a.results)) + '</span>' +
            '<span class="rp-num rp-cpr">' + esc(c == null ? '—' : money2(c)) + '</span>' +
            (!pick && (ed || (a.ad_ids || []).length) ? rowMenu((ed ? ['Edit', 'Duplicate'] : []).concat((a.ad_ids || []).length && adPlat(a) === 'meta' ? ['Open in Ads Manager'] : []).concat(ed ? ['Remove'] : [])) : '<span></span>') + '</div>';
        }).join('') + '</div></div>';
    }).join(''); }).join('');
    if (pick) { wirePick(box); return; }
    /* A row names how many Ad IDs it holds; the IDs open over it. */
    Array.prototype.forEach.call(box.querySelectorAll('[data-a="adids"]'), function (c) {
      c.addEventListener('click', function (e) {
        e.stopPropagation();
        idsOpen(c, st.ads.filter(function (x) { return x.id === c.getAttribute('data-id'); })[0]);
      });
    });
    wireRows(box, function (id, act, btn) {
      var a = st.ads.filter(function (x) { return x.id === id; })[0];
      if (act === 'Open in Ads Manager') { window.open(adsManagerUrl(a), '_blank', 'noopener'); return; }
      if (!ed) return;
      if (act === 'Edit') adSheet(a, btn);
      if (act === 'Duplicate') adSheet(Object.assign({}, a, { id: null, objective: a.objective }), btn, true);
      if (act === 'Remove') removeAd(a);
    });
  }

  /* The team's reference to the ads a row was built from (the console's
     only; the PDF never prints it): a quiet control naming how many, which
     opens the IDs over the row (the user, 2026-10-01: eighteen-digit IDs in
     a line under every ad read as a mess). */
  function idsWord(ids) { return ids.length === 1 ? '1 Ad ID' : ids.length + ' Ad IDs'; }
  function adIdsHtml(a) {
    var ids = a.ad_ids || [];
    if (!ids.length) return '';
    return '<small class="rp-adref"><button class="linkbtn" type="button" data-a="adids" data-id="' + esc(a.id) +
      '" aria-haspopup="dialog" aria-expanded="false">' + esc(idsWord(ids)) + '</button></small>';
  }
  /* One card for every row and the Edit sheet, laid by the one copy of where
     a popover opens: each ID a copy control, Copy all where there are
     several (Ads Manager's search takes them comma separated), and Open in
     Ads Manager. */
  var idsPop = null, idsBtn = null;
  function idsShut(back) {
    if (!idsPop || idsPop.hidden) return;
    idsPop.hidden = true;
    if (idsBtn) { idsBtn.setAttribute('aria-expanded', 'false'); if (back) idsBtn.focus(); }
  }
  function idsOpen(btn, a) {
    var ids = (a && a.ad_ids) || [];
    if (!ids.length) return;
    if (idsPop && !idsPop.hidden && idsBtn === btn) { idsShut(); return; }
    if (!idsPop) {
      idsPop = document.createElement('div');
      idsPop.className = 'kmenu rp-idspop'; idsPop.id = 'rpIdsPop'; idsPop.hidden = true; idsPop.tabIndex = -1;
      idsPop.setAttribute('role', 'dialog'); idsPop.setAttribute('aria-labelledby', 'rpIdsTitle');
      document.body.appendChild(idsPop);
      idsPop.addEventListener('click', function (e) { e.stopPropagation(); });
      document.addEventListener('click', function () { idsShut(); });
      // It answers Escape before the sheet under it does.
      window.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && idsPop && !idsPop.hidden) { e.stopImmediatePropagation(); e.preventDefault(); idsShut(true); }
      }, true);
      if (window.ADspaceMenu) window.ADspaceMenu.onScroll(function () { idsShut(); });
    }
    if (idsBtn && idsBtn !== btn) idsBtn.setAttribute('aria-expanded', 'false');
    idsBtn = btn;
    idsPop.innerHTML = '<div class="popcard-head"><p class="rp-idspop-title" id="rpIdsTitle">' + esc(idsWord(ids)) + '</p>' +
      '<button class="iconbtn popcard-x" type="button" data-a="x" aria-label="Close">' + ICON.close + '</button></div>' +
      '<ul class="rp-idslist">' + ids.map(function (x) {
        return '<li><button class="serial-copy" type="button" data-id="' + esc(x) + '" aria-label="Copy Ad ID ' + esc(x) + '">' + esc(x) + '</button></li>';
      }).join('') + '</ul>' +
      '<div class="rp-idspop-acts">' +
        (ids.length > 1 ? '<button class="btn btn-sm" type="button" data-a="all">Copy all</button>' : '') +
        (adPlat(a) === 'meta' ? '<button class="btn btn-sm btn-icon" type="button" data-a="open">Open in Ads Manager ' + ICON.out + '</button>' : '') + '</div>';
    var copy = function (el, text) { if (window.ADspaceCopy) window.ADspaceCopy.to(el, text); };
    Array.prototype.forEach.call(idsPop.querySelectorAll('.serial-copy'), function (c) {
      c.onclick = function () { copy(c, c.getAttribute('data-id')); };
    });
    var all = idsPop.querySelector('[data-a="all"]');
    if (all) all.onclick = function () { copy(all, ids.join(',')); };
    var openBtn = idsPop.querySelector('[data-a="open"]');
    if (openBtn) openBtn.onclick = function () { window.open(adsManagerUrl(a), '_blank', 'noopener'); idsShut(); };
    idsPop.querySelector('[data-a="x"]').onclick = function () { idsShut(true); };
    idsPop.hidden = false;
    btn.setAttribute('aria-expanded', 'true');
    if (window.ADspaceMenu) window.ADspaceMenu.pop(btn, idsPop, 'left');
    try { idsPop.focus({ preventScroll: true }); } catch (e) { idsPop.focus(); }
  }
  /* Ads Manager on these ads: the account where it is known, the ads chosen. */
  function adsManagerUrl(a) {
    var q = [];
    if (a.ad_account) q.push('act=' + encodeURIComponent(a.ad_account));
    q.push('selected_ad_ids=' + encodeURIComponent((a.ad_ids || []).join(',')));
    return 'https://adsmanager.facebook.com/adsmanager/manage/ads?' + q.join('&');
  }

  function wirePick(box) {
    var pick = st.adPick;
    var ids = function () { return Object.keys(pick).filter(function (k) { return pick[k]; }); };
    var count = function () {
      var n = ids().length, all = $('rpAdAll');
      $('rpAdCount').textContent = n + ' selected';
      all.checked = n === st.ads.length; all.indeterminate = n > 0 && n < st.ads.length;
      $('rpAdMove').disabled = !n; $('rpAdRemove').disabled = !n;
      Array.prototype.forEach.call(box.querySelectorAll('.rp-ad-table'), function (t) {
        var rows = t.querySelectorAll('[data-pick]'), on = t.querySelectorAll('[data-pick]:checked').length, g = t.querySelector('[data-pickall]');
        if (g) { g.checked = on === rows.length; g.indeterminate = on > 0 && on < rows.length; }
      });
    };
    Array.prototype.forEach.call(box.querySelectorAll('[data-pick]'), function (i) {
      i.addEventListener('change', function () {
        var id = i.getAttribute('data-pick');
        if (i.checked) pick[id] = true; else delete pick[id];
        i.closest('.rp-ad-row').classList.toggle('is-picked', i.checked);
        count();
      });
    });
    Array.prototype.forEach.call(box.querySelectorAll('[data-pickall]'), function (g) {
      g.addEventListener('change', function () {
        Array.prototype.forEach.call(g.closest('.rp-ad-table').querySelectorAll('[data-pick]'), function (i) {
          if (i.checked !== g.checked) { i.checked = g.checked; i.dispatchEvent(new Event('change')); }
        });
      });
    });
    $('rpAdAll').addEventListener('change', function () {
      var on = $('rpAdAll').checked;
      st.ads.forEach(function (a) { if (on) pick[a.id] = true; else delete pick[a.id]; });
      paintAds();
    });
    $('rpAdDone').addEventListener('click', function () { st.adPick = null; paintAds(); });
    $('rpAdMove').addEventListener('change', function () {
      var to = $('rpAdMove').value, chosen = ids();
      if (!to || !chosen.length) return;
      var was = {};
      st.ads.forEach(function (a) { if (pick[a.id] && a.objective !== to) (was[a.objective] = was[a.objective] || []).push(a.id); });
      var moving = [].concat.apply([], Object.keys(was).map(function (k) { return was[k]; }));
      if (!moving.length) { $('rpAdMove').value = ''; return; }
      $('rpAdMove').disabled = true;
      setObjective(moving, to).then(function () {
        var word = OBJ_WORD[to] || to;
        st.adPick = {};
        paintAds(); paintTotals();
        undoBar(moving.length + ' ad' + (moving.length === 1 ? '' : 's') + ' moved to ' + word + '.', st.host.querySelector('.rp-ads'), function () {
          Object.keys(was).reduce(function (p0, k) { return p0.then(function () { return setObjective(was[k], k); }); }, Promise.resolve())
            .then(function () { paintAds(); paintTotals(); }).catch(function (e) { say(st.host.querySelector('[data-m="head"]'), said(e), 'err'); });
        });
      }).catch(function (e) { $('rpAdMove').disabled = false; say(st.host.querySelector('[data-m="head"]'), said(e), 'err'); });
    });
    $('rpAdRemove').addEventListener('click', function () {
      var chosen = st.ads.filter(function (a) { return pick[a.id]; });
      if (!chosen.length) return;
      var n = chosen.length;
      window.ADspaceConfirm.ask({ title: 'Remove ' + n + ' ad' + (n === 1 ? '' : 's') + '?', body: 'They leave this report.', go: 'Remove', tone: 'danger' }, function () {
        db.from('sm_report_ads').delete().in('id', chosen.map(function (a) { return a.id; })).select('id').then(function (res) {
          var gone = (res.data || []).map(function (x) { return x.id; });
          if (res.error || !gone.length) { say(st.host.querySelector('[data-m="head"]'), said(res.error || 'Not removed. The database refused the request.'), 'err'); return; }
          var left = chosen.filter(function (a) { return gone.indexOf(a.id) > -1; });
          st.ads = st.ads.filter(function (a) { return gone.indexOf(a.id) < 0; });
          st.adPick = st.ads.length > 1 ? {} : null;
          paintAds(); paintTotals();
          undoBar(left.length + ' ad' + (left.length === 1 ? '' : 's') + ' removed.', st.host.querySelector('.rp-ads'), function () {
            db.from('sm_report_ads').insert(left).select('*').then(function (x) {
              if (x.error) { say(st.host.querySelector('[data-m="head"]'), said(x.error), 'err'); return; }
              st.ads = st.ads.concat(x.data || []); sortAds(); paintAds(); paintTotals();
            });
          });
        });
      });
    });
    count();
  }
  /* One objective for several ads; the answer names every ad it moved. */
  function setObjective(ids, to) {
    return db.from('sm_report_ads').update({ objective: to }).in('id', ids).select('id, objective').then(function (res) {
      if (res.error) throw res.error;
      var done = (res.data || []).map(function (x) { return x.id; });
      if (!done.length) throw new Error('Not moved. The database refused the request.');
      st.ads.forEach(function (a) { if (done.indexOf(a.id) > -1) a.objective = to; });
      sortAds();
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
        '<div class="row"><div><label class="field-label" for="rpAdPlat">Platform</label><select class="select" id="rpAdPlat" data-seg>' +
          AD_PLATS.map(function (p) { return '<option value="' + p[0] + '">' + esc(p[1]) + '</option>'; }).join('') + '</select></div></div>' +
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
          '<option value="">Automatic</option><option value="result">Per result</option><option value="thousand">Per 1,000 reach</option></select></div></div></section>' +
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
      FOOT('Save') + '<span class="rp-adfoot" id="rpAdRef" hidden></span>');
    box.querySelector('h3').textContent = a && !copy ? 'Edit ad' : 'Add ad';
    var v = function (id, x) { $(id).value = x == null ? '' : x; };
    a = a || {};
    v('rpAdName', a.name); $('rpAdObj').value = a.objective || st.lastObj || 'leads';
    $('rpAdPlat').value = a.platform || st.lastPlat || 'meta';
    v('rpAdResult', resultWord(a.result_label)); v('rpAdAud', a.audience);
    v('rpAdStart', a.starts_on || (a.id || copy ? null : st.open.period_start)); v('rpAdEnd', a.ends_on || (a.id || copy ? null : st.open.period_end));
    v('rpAdSpend', a.spend); v('rpAdResults', a.results); v('rpAdCtr', a.ctr); v('rpAdReach', a.reach); v('rpAdImpr', a.impressions);
    v('rpAdCpr', a.cpr); $('rpAdBasis').value = a.cpr_basis || '';
    AGE_BANDS.forEach(function (b) { v('rpAge_' + b.replace('+', 'p'), (a.age || {})[b]); });
    v('rpAdHook', a.hook_rate); v('rpAdHold', a.hold_rate); $('rpAdPlay').value = playOut(a.avg_play);
    RET.forEach(function (r0) { v('rpRet_' + r0[0], (a.retention || {})[r0[0]]); });
    v('rpAdRemark', a.remark);
    /* The Ad IDs sit in the foot, left of Cancel and Save, the same control
       as the row's; a copy is a new ad and carries none. */
    var ref = $('rpAdRef'), held = a.id && !copy ? a : null;
    ref.innerHTML = held ? adIdsHtml(held) : '';
    ref.hidden = !ref.innerHTML;
    var refBtn = ref.querySelector('[data-a="adids"]');
    if (refBtn) refBtn.onclick = function (e) { e.stopPropagation(); idsOpen(refBtn, held); };
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
      window.ADspaceForm.paint($('rpAdPlat'));
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
        name: name, platform: $('rpAdPlat').value === 'tiktok' ? 'tiktok' : 'meta', objective: $('rpAdObj').value, result_label: $('rpAdResult').value.trim() || null,
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
        fileReport('report.saved', (editing ? 'Ad edited: ' : 'Ad added: ') + (SM() && SM().adName ? SM().adName(saved.name || '') : (saved.name || '')));
        st.lastObj = row.objective; st.lastPlat = row.platform;
        sortAds();
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        paintAds(); paintTotals();
        /* One image a creative (the user, 2026-10-01): an image added or
           changed here goes on the creative's other rows too, the other
           objectives it ran under. */
        if ((saved.thumb_data || null) !== (a.thumb_data || null) && saved.thumb_data) {
          var sibs = st.ads.filter(function (x) { return x.id !== saved.id && adName(x.name) === adName(saved.name) && x.thumb_data !== saved.thumb_data; });
          if (!sibs.length) return;
          db.from('sm_report_ads').update({ thumb_data: saved.thumb_data }).in('id', sibs.map(function (x) { return x.id; })).select('id').then(function (r2) {
            var done = (r2.data || []).map(function (x) { return x.id; });
            st.ads.forEach(function (x) { if (done.indexOf(x.id) > -1) x.thumb_data = saved.thumb_data; });
            paintAds();
          });
        }
      });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  /* Rows from an Ads Manager export, with its own header row. A breakdown
     by age comes in as one row an ad and band; those rows are gathered into
     one ad, its age split taken from its results (or its impressions where
     it has none), and its figures added up. Video plays are turned into the
     hook rate, the hold rate and the retention curve; a rate Ads Manager
     sends itself (a custom Hook rate column) is kept, weighted by
     impressions across the rows, so it reads as it does there.
     The dates an ad ran (the user, 2026-10-01): an export by day (or week)
     gives the first and last day the ad delivered, and its reach is left to
     be typed, since a daily reach counts a person again each day. Otherwise
     the ad's own Starts and Ends, held inside the report's period; an ad
     still running reads to the period's last day. Reporting starts and ends
     only repeat the range that was exported, so they are the last resort. */
  /* TikTok Ads Manager's own words sit beside Meta's (2026-10-05, provisional
     until the team's first TikTok export is read): an ad group is the ad set,
     Cost the amount spent, 2-second views the opening that stopped a viewer
     (the hook, over impressions) and 6-second views the ones that stayed
     (the hold, over 2-second views). */
  var AD_HEAD = [
    [/^(ad name|ad|name)$/, 'name'], [/^(ad set name|ad set|ad group name|ad group|audience)$/, 'audience'], [/^(objective|campaign objective|advertising objective)$/, 'objective'],
    [/^(account name|ad account name|ad account|advertiser name)$/, 'account'], [/^ad id$/, 'ad_id'], [/^(account id|ad account id|advertiser id)$/, 'account_id'],
    [/^(result type|result indicator|results? type|optimi[sz]ation event)$/, 'result_label'], [/^(results?|conversions)$/, 'results'],
    [/^reach$/, 'reach'], [/^impressions$/, 'impressions'], [/^(amount spent|cost$|total cost$)/, 'spend'],
    [/^ctr/, 'ctr'], [/^cost per (results?|conversion)/, 'cpr'],
    [/^reporting starts$/, 'rep_start'], [/^reporting ends$/, 'rep_end'], [/^(day|week|month|date|by day)$/, 'day'],
    [/^(starts?|start date|start time)$/, 'starts_on'], [/^(ends?|end date|end time|stop time)$/, 'ends_on'],
    [/^age$/, 'age'],
    [/^(3-second video plays|video plays at 3 ?s(econds)?|3-second plays|2-second video views)$/, 'plays3'], [/^(thruplays|6-second video views)$/, 'thruplays'], [/^video (plays|views)$/, 'plays'],
    [/^video (plays|views) at 25%/, 'v25'], [/^video (plays|views) at 50%/, 'v50'], [/^video (plays|views) at 75%/, 'v75'], [/^video plays at 95%/, 'v95'], [/^video (plays|views) at 100%/, 'v100'],
    [/^(video average play time|average play time per video view)/, 'avg_play'], [/^(hook rate|thumb ?stop)/, 'hook_rate'], [/^hold rate/, 'hold_rate']
  ];
  /* Headers only TikTok's export carries, so a paste names its platform. */
  var TIKTOK_HEAD = /^(ad group name|ad group|advertiser id|advertiser name|cost|2-second video views|6-second video views|average play time per video view|video views at \d+%)$/;
  function objectiveOf(v) {
    var x = String(v || '').toLowerCase().replace(/^outcome_/, '').replace(/_/g, ' ').trim();
    if (!x) return null;
    if (/lead/.test(x)) return 'leads';
    if (/messag|conversation/.test(x)) return 'messaging';
    if (/sale|conversion|purchase|catalog/.test(x)) return 'sales';
    if (/traffic|link click/.test(x)) return 'traffic';
    if (/app/.test(x)) return 'app';
    if (/engage|video view|page like|communit|follow|profile visit/.test(x)) return 'engagement';
    if (/aware|reach|brand/.test(x)) return 'awareness';
    return null;
  }
  /* A date in the period's terms: before it starts reads as its first day,
     after it ends (or not ended) as its last. */
  function clip(d, lo, hi) { return !d ? d : (lo && d < lo ? lo : hi && d > hi ? hi : d); }
  function parseAdRows(text, period, fallbackObj) {
    period = period || {};
    var year = period.year || new Date().getFullYear(), lo = period.start || null, hi = period.end || null;
    var lines = String(text || '').replace(/\r/g, '').split('\n').filter(function (l) { return l.trim(); });
    if (lines.length < 2) return { error: 'Paste a header row and at least one ad.' };
    var sep = lines[0].indexOf('\t') > -1 ? '\t' : ',';
    var head = lines[0].split(sep).map(function (h) {
      var k = h.trim().toLowerCase().replace(/^"|"$/g, '').replace(/\s+/g, ' ');
      var hit = AD_HEAD.filter(function (x) { return x[0].test(k); })[0];
      return hit ? hit[1] : null;
    });
    if (head.indexOf('name') < 0) return { error: 'The header row needs an Ad name column.' };
    var byKey = {}, order = [], skipped = 0, daily = 0, accounts = {};
    var RW = window.ADspaceSmReport && window.ADspaceSmReport.resultWord, AN = window.ADspaceSmReport && window.ADspaceSmReport.adName;
    var hasAge = head.indexOf('age') > -1;
    var NUMS = ['results', 'reach', 'impressions', 'spend', 'plays3', 'thruplays', 'plays', 'v25', 'v50', 'v75', 'v95', 'v100'];
    var acc0 = function () { return { n: {}, w: {}, rows: [], count: 0, ctrw: 0 }; };
    /* One row's figures into an ad's tally. */
    var tally = function (a, raw) {
      a.count++;
      var im = numIn(raw.impressions), row = { hook_rate: numIn(raw.hook_rate), hold_rate: numIn(raw.hold_rate) };
      NUMS.forEach(function (k) { var x = numIn(raw[k]); row[k] = x; if (x !== null) a.n[k] = (a.n[k] || 0) + x; });
      a.rows.push(row);
      var c = numIn(raw.cpr); if (c !== null) a.n.cpr = c;
      var pl = playIn(raw.avg_play), pw = numIn(raw.plays) || numIn(raw.plays3) || im || 1;
      if (pl !== null) { a.n.avg_play = (a.n.avg_play || 0) + pl * pw; a.w.avg_play = (a.w.avg_play || 0) + pw; }
      var ctr = numIn(raw.ctr);
      if (ctr !== null) { a.n.ctrSum = (a.n.ctrSum || 0) + ctr * (im || 1); a.ctrw += (im || 1); }
    };
    var cellsOf = function (l) {
      var cells = l.split(sep).map(function (c) { return c.trim().replace(/^"|"$/g, ''); }), raw = {};
      head.forEach(function (k, i) { if (k && raw[k] == null) raw[k] = cells[i] || ''; });
      return raw;
    };
    var named = function (v) { return v && !/^mixed$/i.test(String(v).trim()) ? String(v).trim() : ''; };
    /* Which ads are one row on the report (the user, 2026-10-01). An ad's
       result type is read from its rows that name one (a row with no results
       names none). Ads are combined only where they are the same creative
       (the name without the creator code), objective, ad set and result
       type: two ads of one creative with different results (Post
       engagements, Interactions) are never added together. With Ad ID each
       row is known to its ad; without it, rows of one name and objective
       that name two result types cannot be told apart, and are refused. */
    var groupOf = {}, idLabel = {}, idBase = {}, noIdLabels = {};
    var CN = function (x) { return AN ? AN(x) : x; };
    lines.slice(1).forEach(function (l) {
      var raw = cellsOf(l);
      if (!raw.name) return;
      var obj = objectiveOf(raw.objective) || fallbackObj, base = [CN(raw.name), obj, raw.audience || ''].join('|');
      if (raw.ad_id) {
        var id = raw.ad_id + '|' + raw.name;
        idBase[id] = base;
        if (!idLabel[id] && named(raw.result_label)) idLabel[id] = named(raw.result_label);
      } else if (named(raw.result_label)) {
        (noIdLabels[base] = noIdLabels[base] || {})[named(raw.result_label)] = true;
      }
    });
    var clash = Object.keys(noIdLabels).filter(function (b) { return Object.keys(noIdLabels[b]).length > 1; })[0];
    if (clash) return { error: clash.split('|')[0] + ' has more than one kind of result (' + Object.keys(noIdLabels[clash]).join(', ') + '). Add the Ad ID column so each ad stays its own.' };
    var labelsAt = {};
    Object.keys(idBase).forEach(function (id) { if (idLabel[id]) (labelsAt[idBase[id]] = labelsAt[idBase[id]] || {})[idLabel[id]] = true; });
    Object.keys(idBase).forEach(function (id) {
      var b = idBase[id], lab = idLabel[id], kinds = Object.keys(labelsAt[b] || {});
      /* An ad with no results joins its creative's one kind of result (or
         the creative's other ads with none), and stands alone where the
         creative has more than one kind. */
      groupOf[id] = lab ? b + '|' + lab : kinds.length === 1 ? b + '|' + kinds[0] : kinds.length ? 'id:' + id : b + '|';
    });
    /* Ads Manager's first row under the header has no ad name: it is the
       account's own figures for the period, reach counted once across every
       ad (and every day), which no adding up of the ads can give. It fills
       Step 1 (the user, 2026-10-01). */
    var summary = null;
    lines.slice(1).forEach(function (l, li) {
      var raw = cellsOf(l);
      if (!raw.name && li === 0 && !String(raw.age || '').trim()) {
        var sr = numIn(raw.reach), si = numIn(raw.impressions), ss = numIn(raw.spend);
        if (sr !== null || si !== null || ss !== null) {
          summary = {};
          if (sr !== null) summary.reach = Math.round(sr);
          if (si !== null) summary.impressions = Math.round(si);
          if (ss !== null) summary.spend = Math.round(ss * 100) / 100;
          return;
        }
      }
      if (!raw.name) { skipped++; return; }
      if (raw.account) accounts[raw.account] = true;
      var obj = objectiveOf(raw.objective) || fallbackObj;
      /* An age band or a day of an ad is gathered into its row (Ad ID with
         the name, as a spreadsheet can round a long ID). */
      var key = raw.ad_id ? groupOf[raw.ad_id + '|' + raw.name] : [CN(raw.name), obj, raw.audience || ''].join('|');
      var ad = byKey[key];
      if (!ad) {
        ad = byKey[key] = { name: AN ? AN(raw.name) : raw.name, objective: obj, audience: raw.audience || null,
          result_label: null,
          own_start: null, own_end: null, rep_start: null, rep_end: null, days: {}, ran_from: null, ran_to: null,
          band: acc0(), total: acc0(), _age: {}, ids: [], account: null };
        order.push(key);
      }
      /* The Ad IDs and the account's ID, as the team's references (the
         user, 2026-10-01): kept only where whole, since a spreadsheet can
         round a long ID into 1.20E+17. */
      var aid = String(raw.ad_id || '').trim();
      if (/^\d{5,25}$/.test(aid) && ad.ids.indexOf(aid) < 0) ad.ids.push(aid);
      var acct = String(raw.account_id || '').trim().replace(/^act_/, '');
      if (/^\d{5,25}$/.test(acct)) ad.account = acct;
      /* The result type from the first row that names one: a row with no
         results names none, and Meta's `mixed` names nothing. */
      if (!ad.result_label && raw.result_label && !/^mixed$/i.test(raw.result_label.trim())) ad.result_label = RW ? RW(raw.result_label) : raw.result_label;
      var im = numIn(raw.impressions);
      /* A report laid out as a table by age carries a row for the ad with no
         age (its total) above its bands: the total is the ad's figures, the
         bands only its split. Raw rows have no such row. */
      tally(hasAge && !String(raw.age || '').trim() ? ad.total : ad.band, raw);
      var os = raw.starts_on ? readDate(raw.starts_on, year) : null, oe = raw.ends_on ? readDate(raw.ends_on, year) : null;
      if (os && (!ad.own_start || os < ad.own_start)) ad.own_start = os;
      if (oe && (!ad.own_end || oe > ad.own_end)) ad.own_end = oe;
      var rs = raw.day ? readDate(raw.day, year) : raw.rep_start ? readDate(raw.rep_start, year) : null;
      var re = raw.rep_end ? readDate(raw.rep_end, year) : rs;
      if (rs) {
        ad.days[rs] = true;
        if (!ad.rep_start || rs < ad.rep_start) ad.rep_start = rs;
        if (re && (!ad.rep_end || re > ad.rep_end)) ad.rep_end = re;
        if (im === null || im > 0) {
          if (!ad.ran_from || rs < ad.ran_from) ad.ran_from = rs;
          if (re && (!ad.ran_to || re > ad.ran_to)) ad.ran_to = re;
        }
      }
      if (raw.age) {
        var band = String(raw.age).replace(/\s/g, '').replace(/–/g, '-');
        if (AGE_BANDS.indexOf(band) > -1) {
          var ab = ad._age[band] || (ad._age[band] = { results: 0, impressions: 0 });
          ab.results += numIn(raw.results) || 0; ab.impressions += im || 0;
        }
      }
    });
    if (Object.keys(accounts).length > 1) return { error: 'These rows come from ' + Object.keys(accounts).length + ' ad accounts. Export one client\'s account.' };
    /* A rate Ads Manager sends (a custom Hook rate or Hold rate column) is a
       formula over the ad's figures. Its formula is found from the rows
       themselves, then worked out on the ad's whole figures, so the rate
       reads as Ads Manager shows it for the ad, whatever the formula. */
    var FORM_N = ['plays3', 'thruplays', 'plays', 'v25', 'v50', 'v75', 'v95', 'v100'], FORM_D = ['impressions', 'reach', 'plays3', 'plays'];
    var rateOf = function (a, k) {
      var got = a.rows.filter(function (r) { return r[k] !== null; });
      if (!got.length) return null;
      if (a.rows.length === 1) return got[0][k];
      for (var i = 0; i < FORM_N.length; i++) for (var j = 0; j < FORM_D.length; j++) {
        var nk = FORM_N[i], dk = FORM_D[j];
        if (nk === dk || !a.n[dk]) continue;
        var fits = got.every(function (r) {
          if (r[nk] === null || !r[dk]) return r[k] === 0 || r[dk] === 0;
          var v = r[nk] / r[dk];
          return Math.abs(v * 100 - r[k]) <= Math.max(0.06, Math.abs(r[k]) * 0.003) || Math.abs(v - r[k]) <= 0.0006;
        });
        if (fits) return Math.round((a.n[nk] || 0) / a.n[dk] * 10000) / 100;
      }
      var sw = 0, sx = 0;
      got.forEach(function (r) { var w0 = r.impressions || 1; sw += w0; sx += r[k] * w0; });
      return Math.round(sx / sw * 100) / 100;
    };
    var rows = order.map(function (k) {
      var ad = byKey[k];
      var a = ad.total.count ? ad.total : ad.band, n = a.n, w = a.w;
      var byDay = Object.keys(ad.days).length > 1;
      if (byDay) daily++;
      var from, to;
      if (byDay) { from = ad.ran_from || ad.rep_start; to = ad.ran_to || ad.rep_end; }
      else if (ad.own_start || ad.own_end) { from = clip(ad.own_start || lo, lo, hi); to = clip(ad.own_end || hi, lo, hi); }
      else { from = ad.rep_start; to = ad.rep_end; }
      var out = { name: ad.name, objective: ad.objective, audience: ad.audience, result_label: ad.result_label,
        ad_ids: ad.ids.length ? ad.ids : null, ad_account: ad.account,
        starts_on: from || null, ends_on: to || null,
        results: n.results != null ? Math.round(n.results) : null,
        reach: n.reach != null && !byDay ? Math.round(n.reach) : null,
        impressions: n.impressions != null ? Math.round(n.impressions) : null,
        spend: n.spend != null ? Math.round(n.spend * 100) / 100 : null,
        ctr: a.ctrw ? Math.round(n.ctrSum / a.ctrw * 100) / 100 : null,
        cpr: a.count === 1 && n.cpr != null ? n.cpr : null,
        avg_play: w.avg_play ? Math.round(n.avg_play / w.avg_play * 10) / 10 : null, age: {}, retention: {} };
      if (byDay) out._daily = true;
      /* Without a rate of Ads Manager's own: the hook is 3-second plays over
         impressions, the hold ThruPlays over 3-second plays (of those the
         opening stopped, how many stayed; the user, 2026-10-01). */
      var hk = rateOf(a, 'hook_rate'), hd = rateOf(a, 'hold_rate');
      if (hk !== null) out.hook_rate = hk;
      else if (n.plays3 != null && n.impressions) out.hook_rate = Math.round(n.plays3 / n.impressions * 10000) / 100;
      if (hd !== null) out.hold_rate = hd;
      else if (n.thruplays != null && n.plays3) out.hold_rate = Math.round(n.thruplays / n.plays3 * 10000) / 100;
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
    var tiktok = lines[0].split(sep).some(function (h) { return TIKTOK_HEAD.test(h.trim().toLowerCase().replace(/^"|"$/g, '').replace(/\s+/g, ' ')); });
    return { rows: rows, skipped: skipped, daily: daily, columns: head.filter(Boolean), byAge: head.indexOf('age') > -1, summary: summary, tiktok: tiktok };
  }

  function pasteAdsSheet(opener) {
    var box = sheetShell('rpPasteAdsSheet', 'Import from Ads Manager',
      '<section class="fsec"><div class="row"><div><label class="field-label" for="rpPAPlat">Platform</label><select class="select" id="rpPAPlat" data-seg>' +
        AD_PLATS.map(function (x) { return '<option value="' + x[0] + '">' + x[1] + '</option>'; }).join('') + '</select></div></div>' +
      '<div class="row"><div><label class="field-label" for="rpPAObj">Objective if the rows do not say</label><select class="select" id="rpPAObj">' +
        OBJECTIVES.map(function (o) { return '<option value="' + o[0] + '">' + esc(o[1]) + '</option>'; }).join('') + '</select></div></div>' +
      '<div class="row"><div><label class="field-label" for="rpPAText">Export from Ads Manager, copy the rows with the header row, and paste them here</label>' +
        '<textarea class="input rp-paste" id="rpPAText" rows="8" placeholder="Ad name&#9;Results&#9;Amount spent"></textarea></div></div>' +
      '<p class="rp-paste-sum" id="rpPASum"></p></section>', FOOT('Add ads'));
    $('rpPAText').value = '';
    /* The platform follows the paste (TikTok's own headers) until the
       person picks one. */
    var platTouched = false;
    $('rpPAPlat').value = 'meta';
    if (window.ADspaceForm && window.ADspaceForm.paint) window.ADspaceForm.paint($('rpPAPlat'));
    var plat = function () { return $('rpPAPlat').value === 'tiktok' ? 'tiktok' : 'meta'; };
    var sum = $('rpPASum'), sm = box.querySelector('[data-m="sheet"]');
    sum.textContent = ''; say(sm, '');
    var year = Number(String(st.open.period_start).slice(0, 4));
    var go = box.querySelector('[data-a="go"]');
    /* A paste naming ads already in this report updates them with what it
       holds, and adds the rest (the user, 2026-10-01): an export by day sets
       the days each ran; an export by age the age split; an export with
       neither the figures, reach included, exactly as Ads Manager counts
       them per ad (reach added up from age rows counts a person once per
       age group, not once per ad). */
    /* A paste matches only ads of its own platform. */
    var mine = function () { var pk = plat(); return st.ads.filter(function (a) { return adPlat(a) === pk; }); };
    var already = function (r0) {
      var list = mine();
      /* An ad named by its Ad ID is that row, whatever its name reads. */
      if (r0.ad_ids) {
        var byId = list.filter(function (a) { return (a.ad_ids || []).some(function (x) { return r0.ad_ids.indexOf(x) > -1; }); });
        if (byId.length === 1) return byId[0];
      }
      var same = list.filter(function (a) { return adName(a.name) === r0.name; });
      if (same.length > 1 && r0.audience) same = same.filter(function (a) { return (a.audience || '') === r0.audience; });
      if (same.length > 1) same = same.filter(function (a) { return a.objective === r0.objective; });
      if (same.length > 1 && r0.result_label) same = same.filter(function (a) { return resultWord(a.result_label) === r0.result_label; });
      return same.length === 1 ? same[0] : null;
    };
    var named = function (r0) { return mine().some(function (a) { return adName(a.name) === r0.name; }); };
    var FIGS = ['result_label', 'results', 'reach', 'impressions', 'spend', 'ctr', 'cpr', 'hook_rate', 'hold_rate', 'avg_play', 'retention'];
    var patchOf = function (r0, out) {
      if (r0._daily) return { starts_on: r0.starts_on, ends_on: r0.ends_on };
      if (out.byAge) return Object.keys(r0.age || {}).length ? { age: r0.age } : null;
      var p0 = {};
      FIGS.forEach(function (k) { if (r0[k] != null && !(k === 'retention' && !Object.keys(r0[k]).length)) p0[k] = r0[k]; });
      return p0;
    };
    var read = function () {
      var out = parseAdRows($('rpPAText').value, { year: year, start: st.open.period_start, end: st.open.period_end }, $('rpPAObj').value);
      if (out.error) { sum.textContent = $('rpPAText').value.trim() ? out.error : ''; go.disabled = true; return out; }
      if (!platTouched && (out.tiktok ? 'tiktok' : 'meta') !== plat()) {
        $('rpPAPlat').value = out.tiktok ? 'tiktok' : 'meta';
        if (window.ADspaceForm && window.ADspaceForm.paint) window.ADspaceForm.paint($('rpPAPlat'));
      }
      out.platform = plat();
      out.rows.forEach(function (r0) { r0.platform = out.platform; });
      out.updates = []; out.unclear = []; out.fresh = [];
      out.rows.forEach(function (r0) {
        var a = already(r0);
        if (a) {
          var p0 = patchOf(r0, out);
          /* A paste carrying Ad IDs a row does not hold yet adds them. */
          var more = (r0.ad_ids || []).filter(function (x) { return (a.ad_ids || []).indexOf(x) < 0; });
          if (more.length) { p0 = p0 || {}; p0.ad_ids = (a.ad_ids || []).concat(more); }
          if (r0.ad_account && !a.ad_account) { p0 = p0 || {}; p0.ad_account = r0.ad_account; }
          if (p0) out.updates.push({ ad: a, patch: p0 });
          return;
        }
        /* A day's or an age group's rows for a name several ads here share
           cannot say which ad they belong to, so they add nothing. */
        if ((r0._daily || out.byAge) && named(r0)) { out.unclear.push(r0); return; }
        out.fresh.push(r0);
      });
      var what = out.rows.some(function (r0) { return r0._daily; }) ? 'take the days they ran'
        : out.byAge ? 'take their age split' : 'take Ads Manager\'s figures';
      var parts = [];
      if (out.fresh.length) parts.push(out.fresh.length + ' ad' + (out.fresh.length === 1 ? '' : 's') + ' ready');
      if (out.updates.length) parts.push(out.updates.length + ' ad' + (out.updates.length === 1 ? '' : 's') + ' already here ' + what);
      if (out.fresh.length && out.byAge) parts.push('the age split gathered from the rows');
      if (out.fresh.some(function (r0) { return r0._daily; })) parts.push('dates from the days each ad delivered');
      if (out.unclear.length) parts.push(out.unclear.length + ' left out: more than one ad here has that name');
      if (out.skipped) parts.push(out.skipped + ' without a name skipped');
      /* The account's figures fill Step 1 where it is empty; a figure the
         team typed is kept. */
      var t0 = out.platform === 'tiktok' ? (st.open.ads_totals || {}).tiktok || {} : st.open.ads_totals || {};
      out.fill = {}; out.kept = [];
      if (out.summary) Object.keys(out.summary).forEach(function (k) {
        if (t0[k] == null || t0[k] === '') out.fill[k] = out.summary[k];
        else if (Number(t0[k]) !== out.summary[k]) out.kept.push(k);
      });
      var TW = { reach: 'reach', impressions: 'impressions', spend: 'amount spent' };
      var fk = Object.keys(out.fill);
      if (fk.length) parts.push('the account\'s ' + fk.map(function (k) { return TW[k]; }).join(', ').replace(/, ([^,]*)$/, ' and $1') + ' to Step 1');
      if (out.kept.length) parts.push('Step 1 keeps its typed ' + out.kept.map(function (k) { return TW[k]; }).join(', ').replace(/, ([^,]*)$/, ' and $1'));
      sum.textContent = parts.join(', ').replace(/^./, function (c) { return c.toUpperCase(); }) + '.' +
        (out.fresh.some(function (r0) { return r0._daily; }) ? ' Reach is left to type: a daily export counts a person again each day.' : '');
      go.disabled = !(out.fresh.length + out.updates.length + Object.keys(out.fill).length);
      return out;
    };
    $('rpPAText').oninput = read; $('rpPAObj').onchange = read;
    $('rpPAPlat').onchange = function () { platTouched = true; read(); };
    go.disabled = true;
    go.onclick = function () {
      var out = read();
      var fill = out.fill || {};
      if (!out.rows || !(out.fresh.length + out.updates.length + Object.keys(fill).length)) return;
      var n = st.ads.length;
      var rows = out.fresh.map(function (r0, i) { var x = Object.assign({ report_id: st.open.id, position: n + i + 1 }, r0); delete x._daily; return x; });
      go.disabled = true;
      var ups = out.updates.map(function (u) {
        return db.from('sm_report_ads').update(u.patch).eq('id', u.ad.id).select('*').then(function (res) {
          if (res.error) throw res.error;
          if (!(res.data || []).length) throw new Error('Not saved. The database refused the request.');
          st.ads = st.ads.map(function (x) { return x.id === u.ad.id ? res.data[0] : x; });
        });
      });
      var add = rows.length ? db.from('sm_report_ads').insert(rows).select('*').then(function (res) {
        if (res.error) throw res.error;
        st.ads = st.ads.concat(res.data || []);
      }) : Promise.resolve();
      var t1 = Object.assign({}, st.open.ads_totals || {});
      if (out.platform === 'tiktok') t1.tiktok = Object.assign({}, t1.tiktok || {}, fill); else Object.assign(t1, fill);
      var tot = Object.keys(fill).length ? db.from('sm_reports').update({ ads_totals: t1 })
        .eq('id', st.open.id).select('*').then(function (res) {
          if (res.error) throw res.error;
          if (!(res.data || []).length) throw new Error('Not saved. The database refused the request.');
          st.open = res.data[0];
        }) : Promise.resolve();
      Promise.all(ups.concat([add, tot])).then(function () {
        go.disabled = false;
        var parts = [];
        if (rows.length) parts.push(rows.length + (rows.length === 1 ? ' ad added' : ' ads added'));
        if (out.updates.length) parts.push(out.updates.length + (out.updates.length === 1 ? ' ad updated' : ' ads updated'));
        if (Object.keys(fill).length) parts.push('account figures filled');
        fileReport('report.saved', 'Imported from Ads Manager: ' + parts.join(', '));
        sortAds();
        window.ADspaceSheet.clean(); window.ADspaceSheet.close();
        paintAds(); paintTotals(); paintSteps();
      }).catch(function (e) { go.disabled = false; sortAds(); paintAds(); paintTotals(); paintSteps(); say(sm, said(e), 'err'); });
    };
    window.ADspaceSheet.show(box, { opener: opener });
  }

  // ---- Draft with AI usage: an admin's view of every colleague's drafts ------
  /* Like a usage page (the user, 2026-10-04): when it resets, then used
     today over the limit with a bar, for the whole team, each group and
     each colleague (a group's and the team's are their colleagues' added
     up), then the limits. Edit limits holds the six standards in three
     pairs; a colleague's own limit is set from their row (empty is the
     standard, 0 stops it; the user, 2026-10-05: no long list). Read
     again on every open. */
  var AI_STD = { person: 10, admin: 20, report: 1, report_admin: 5, check: 1, check_admin: 5 };
  function aiClock(iso) {
    var at = new Date(iso);
    if (isNaN(at.getTime())) return '';
    try {
      return at.toLocaleString('en-GB', { timeZone: 'Asia/Kuala_Lumpur', hour: 'numeric', minute: '2-digit', hour12: true })
        .replace(/\s?([ap])\.?m\.?$/i, function (x, c) { return ' ' + c.toLowerCase() + 'm'; });
    } catch (e) { return ''; }
  }
  function aiBar(used, cap) {
    var pct = cap > 0 ? Math.min(100, Math.round(used / cap * 100)) : 0;
    return '<div class="aiu-bar' + (cap > 0 && used >= cap ? ' is-full' : '') + '" role="meter" aria-valuemin="0" aria-valuemax="' + cap +
      '" aria-valuenow="' + Math.min(used, cap) + '" aria-label="' + fmt(used) + ' of ' + cap + ' used today"><i style="--p:' + pct + '%"></i></div>';
  }
  /* A colleague's row is the one control for their own limit: pressed, it
     asks for that one value. Every other row only reads. */
  function aiUseRow(o) {
    var shown = o.text != null ? o.text : o.cap === 0 ? 'Stopped' : fmt(o.used) + '/' + o.cap;
    var tag = o.id ? 'button' : 'div';
    return '<' + tag + ' class="aiu-row' + (o.sum ? ' is-sum' : '') + (o.id ? ' is-set' : '') + '"' +
      (o.id ? ' type="button" data-scope="' + esc(o.id) + '" aria-label="' + esc(o.name + ', ' + shown + '. Set limit') + '"' : '') + '>' +
      '<div class="aiu-name"><b>' + esc(o.name) + (o.code ? ' <span class="aiu-code">' + esc(o.code) + '</span>' : '') + '</b></div>' +
      '<span class="aiu-cap' + (o.own ? ' is-own' : '') + (o.cap === 0 ? ' is-stopped' : '') + '">' + esc(shown) + '</span>' +
      (o.text != null || o.cap === 0 ? '' : aiBar(o.used, o.cap)) +
    '</' + tag + '>';
  }
  function aiUseSheet(opener) {
    var box = sheetShell('rpAiUseSheet', 'AI usage',
      '<div data-m="aiuse"></div>',
      '<button class="btn" type="button" data-a="limits">' + PEN_MARK + 'Edit limits</button>' +
      '<button class="btn btn-quiet" type="button" data-a="cancel">Close</button>');
    box.querySelector('.sheet-card').setAttribute('data-narrow', '560');
    var host = box.querySelector('[data-m="aiuse"]'), m = box.querySelector('[data-m="sheet"]');
    var edit = box.querySelector('[data-a="limits"]');
    var d = null, people = [];
    var paint = function () {
      UI.skeleton(host, 3);
      edit.disabled = true;
      db.rpc('ai_draft_usage').then(function (r) {
        d = r.data || {};
        if (r.error || d.error) {
          UI.failLine(host, 'AI usage', r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : said(r.error)) : (d.error === 'denied' ? 'Only an admin sees this.' : said(d.error)), paint);
          return;
        }
        edit.disabled = false;
        people = (d.people || []).map(function (p) {
          var cap = p.cap != null ? p.cap : (p.limit != null ? p.limit : d.person);
          return { id: p.id, name: p.name, code: p.code, used: p.day || 0, cap: cap, limit: p.limit, own: p.limit != null, group: p.group || 'No group' };
        });
        var sum = function (list) {
          return { used: list.reduce(function (t, p) { return t + p.used; }, 0), cap: list.reduce(function (t, p) { return t + p.cap; }, 0) };
        };
        var groups = {};
        people.forEach(function (p) { (groups[p.group] = groups[p.group] || []).push(p); });
        var names = Object.keys(groups).sort(function (x, y) { return x.localeCompare(y); });
        var all = sum(people);
        var setting = function (k) { return d[k] != null ? d[k] : AI_STD[k]; };
        var rep = setting('report'), adm = setting('report_admin'), chk = setting('check'), chkA = setting('check_admin'), admDay = setting('admin');
        var dayWord = function (v) { return v === 0 ? 'Stopped' : v + ' a day'; };
        host.innerHTML =
          (d.resets_at ? '<p class="aiu-reset">Resets at ' + esc(aiClock(d.resets_at)) + '</p>' : '') +
          '<div class="aiu-list">' + aiUseRow({ name: 'Whole team', used: all.used, cap: all.cap, sum: true }) + '</div>' +
          names.map(function (g) {
            var list = groups[g].slice().sort(function (x, y) { return y.used - x.used || String(x.name).localeCompare(String(y.name)); });
            var t = sum(list);
            return '<section class="fsec"><div class="aiu-list">' + aiUseRow({ name: g, used: t.used, cap: t.cap, sum: true }) +
              list.map(aiUseRow).join('') + '</div></section>';
          }).join('') +
          '<section class="fsec"><h4 class="fsec-h">Limits</h4><div class="aiu-list">' +
            aiUseRow({ name: 'Each colleague', text: dayWord(d.person), own: d.person !== AI_STD.person, cap: d.person }) +
            aiUseRow({ name: 'Each admin', text: dayWord(admDay), own: admDay !== AI_STD.admin, cap: admDay }) +
            aiUseRow({ name: 'Each colleague, each report', text: rep === 0 && chk === 0 ? 'Stopped' : rep + (rep === 1 ? ' draft' : ' drafts') + ' and ' + chk + (chk === 1 ? ' check' : ' checks') + ' a day',
              own: rep !== AI_STD.report || chk !== AI_STD.check, cap: rep }) +
            aiUseRow({ name: 'Each admin, each report', text: adm === 0 && chkA === 0 ? 'Stopped' : adm + (adm === 1 ? ' draft' : ' drafts') + ' and ' + chkA + (chkA === 1 ? ' check' : ' checks') + ' a day',
              own: adm !== AI_STD.report_admin || chkA !== AI_STD.check_admin, cap: adm }) +
          '</div></section>';
        if (window.ADspaceState && window.ADspaceState.fit) window.ADspaceState.fit();
      }).catch(function (e) { UI.failLine(host, 'AI usage', said(e), paint); });
    };
    var STD_KEYS = ['person', 'admin', 'report', 'check', 'report_admin', 'check_admin'];
    var setLimit = function (jobs) {
      var fails = [];
      return jobs.reduce(function (chain, j) {
        return chain.then(function () {
          return db.rpc('ai_draft_set_limit', { p_scope: j.scope, p_daily: j.daily }).then(function (res) {
            var out = res.data || {};
            if (res.error || out.error) fails.push(res.error ? said(res.error) : out.error === 'denied' ? 'Only an admin sets this.' : out.error === 'bad-limit' ? 'A limit is 0 to 500.' : said(out.error));
          });
        });
      }, Promise.resolve()).then(function () {
        say(m, fails.length ? fails[0] : 'Saved.', fails.length ? 'err' : 'ok');
        paint();
      }).catch(function (e) { say(m, said(e), 'err'); paint(); });
    };
    var limitOk = function (v) {
      var bad = Object.keys(v).filter(function (k) { var x = String(v[k] == null ? '' : v[k]).trim(); return x !== '' && !/^\d{1,3}$/.test(x) || Number(x) > 500; });
      return bad.length ? 'A limit is a whole number from 0 to 500.' : '';
    };
    var num = function (v) { return v == null ? '' : String(v); };
    /* The six standards, a day each, in three pairs: one form, one Save. */
    edit.onclick = function () {
      if (!d) return;
      var LBL = { person: 'Each colleague', admin: 'Each admin', report: 'Drafts a report', check: 'Checks a report',
        report_admin: 'Admin drafts a report', check_admin: 'Admin checks a report' };
      var fields = STD_KEYS.map(function (k) {
        return { name: k, label: LBL[k], type: 'number', min: '0', required: false, value: num(d[k] != null ? d[k] : AI_STD[k]), placeholder: String(AI_STD[k]), half: true };
      });
      window.ADspaceConfirm.ask({ title: 'Limits a day', go: 'Save', fields: fields, check: limitOk }, function (v) {
        var jobs = STD_KEYS.map(function (k) {
          var x = String(v[k] == null ? '' : v[k]).trim();
          var want = x === '' || Number(x) === AI_STD[k] ? null : Number(x);
          var was = d[k] != null ? d[k] : AI_STD[k];
          var now = was === AI_STD[k] ? null : was;
          return want === now ? null : { scope: k, daily: want };
        }).filter(Boolean);
        if (!jobs.length) { say(m, 'No change.', 'ok'); return; }
        setLimit(jobs);
      });
    };
    /* A colleague's own limit, from their row: one value, empty for the standard. */
    host.addEventListener('click', function (e) {
      var row = e.target.closest('.aiu-row[data-scope]');
      if (!row || !d) return;
      var p = people.filter(function (x) { return x.id === row.getAttribute('data-scope'); })[0];
      if (!p) return;
      var std = d.person != null ? d.person : AI_STD.person;
      window.ADspaceConfirm.ask({
        title: p.name, go: 'Save', check: limitOk,
        fields: [{ name: 'limit', label: 'Limit a day', type: 'number', min: '0', required: false, value: num(p.limit), placeholder: 'Standard, ' + std }]
      }, function (v) {
        var x = String(v.limit == null ? '' : v.limit).trim();
        var want = x === '' ? null : Number(x);
        if (want === (p.limit == null ? null : p.limit)) { say(m, 'No change.', 'ok'); return; }
        setLimit([{ scope: p.id, daily: want }]);
      });
    });
    say(m, '', '');
    paint();
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
      $('rhPeriod').addEventListener('change', paintHub);
      var strip = $('rhTabs');
      strip.addEventListener('click', function (e) {
        var b = e.target.closest && e.target.closest('.tab');
        if (b) { hub.tab = b.getAttribute('data-tab'); paintHub(); if (bridge.setUrl) bridge.setUrl(); }
      });
      strip.addEventListener('keydown', function (e) {
        var tabs = Array.prototype.slice.call(strip.querySelectorAll('.tab:not([hidden])'));
        var i = tabs.indexOf(document.activeElement);
        if (i < 0) return;
        var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
        if (to === null || !tabs[to]) return;
        e.preventDefault();
        tabs[to].click(); tabs[to].focus();
      });
      $('rhNew').addEventListener('click', function () { newSheet($('rhNew')); });
      /* The bar's ⋯, an admin's: Draft with AI usage. */
      var mw = $('rhMoreWrap'), mb = $('rhMoreBtn'), mm = $('rhMore');
      if (mw && mb && mm) {
        var shutM = function () { mm.hidden = true; mb.setAttribute('aria-expanded', 'false'); };
        mb.addEventListener('click', function (e) {
          e.stopPropagation();
          var open = mm.hidden;
          mm.hidden = !open;
          mb.setAttribute('aria-expanded', String(open));
          if (open && window.ADspaceMenu) window.ADspaceMenu.place(mb, mm);
        });
        document.addEventListener('click', function (e) { if (!e.target.closest || !e.target.closest('#rhMoreWrap')) shutM(); });
        if (window.ADspaceMenu && window.ADspaceMenu.onScroll) window.ADspaceMenu.onScroll(shutM);
        mm.addEventListener('click', function (e) {
          var it = e.target.closest('.kmenu-item');
          if (!it) return;
          shutM();
          if (it.getAttribute('data-a') === 'aiuse') aiUseSheet(mb);
        });
      }
    }
    /* The bar's ⋯: AI usage, an admin's. */
    if ($('rhMoreWrap')) $('rhMoreWrap').hidden = !isAdmin();
    if ($('rhMore')) {
      var aiIt = $('rhMore').querySelector('[data-a="aiuse"]');
      if (aiIt) aiIt.hidden = !isAdmin();
    }
    $('rhKind').innerHTML = '<option value="">All types</option>' + TYPES.map(function (t) { return '<option value="' + t.key + '">' + esc(t.name) + '</option>'; }).join('');
    $('rhNew').hidden = !may('work');
    loadClients();
    var wantTab = new URLSearchParams(location.search).get('tab');
    if (HUB_BANDS.some(function (bd) { return bd[0] === wantTab; })) hub.tab = wantTab;
    if (want) { openReport(want, true); return; }
    showList();
    UI.skeleton(list, 4);
    db.from('sm_reports').select('id, kind, client_id, period_start, period_end, status, version_no, updated_at, reviewer_id, brand_id, brand_name, sent_on').order('period_start', { ascending: false }).then(function (r) {
      if (r.error) { UI.failLine(list, 'reports', said(r.error), enterHub); return; }
      hub.rows = r.data || [];
      Promise.all([clientsReady, loadNames()]).then(paintHub);
    });
  }
  var clientsReady = Promise.resolve();
  function loadClients() {
    clientsReady = db.from('clients').select('id, name, slug, stage, client_code, white_label').order('name', { ascending: true }).then(function (c) {
      var all = c.data || [];
      hub.byClient = {};
      all.forEach(function (x) { hub.byClient[x.id] = x; });
      /* A report is started for a client engaged now: Active only. */
      hub.clients = all.filter(function (x) { return x.stage === 'active'; }).sort(F.byClient);
    });
  }
  /* The list (the user, 2026-10-05: "still missing the sliding tab", and
     after 35 months of 10 clients a run of 350 reports): one tab a stage,
     each with its count, the list under it in cards by the month a report
     covers, newest first. Published is held to a period (the last three
     months unless chosen), so it never grows into one long list; a search
     looks through every report, whatever the tab and the period. */
  var PERIOD_MONTHS = { '3m': 3, '12m': 12, year: 0, all: -1 };
  function monthKey(r) { return String(r.period_start || '').slice(0, 7); }
  function monthName(k) {
    if (!k) return 'No period';
    var d = new Date(k + '-01T00:00:00');
    return isNaN(d) ? k : d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  }
  function inPeriod(r, p) {
    var n = PERIOD_MONTHS[p];
    if (n === -1 || n == null) return true;
    var now = new Date(Date.now() + 8 * 3600000), y = now.getUTCFullYear(), m = now.getUTCMonth();
    var from = n === 0 ? new Date(Date.UTC(y, 0, 1)) : new Date(Date.UTC(y, m - n, 1));
    return monthKey(r) >= from.toISOString().slice(0, 7);
  }
  function paintHub() {
    var list = $('rhList'), strip = $('rhTabs');
    if (!list || !strip) return;
    var q = ($('rhFind').value || '').trim().toLowerCase();
    var kind = $('rhKind').value;
    var period = $('rhPeriod').value || '3m';
    var rows = hub.rows.filter(function (r) {
      if (kind && r.kind !== kind) return false;
      if (!q) return true;
      var c = hub.byClient[r.client_id] || {};
      return (String(c.name || '') + ' ' + String(r.brand_name || '') + ' ' + String(c.client_code || '') + ' ' + periodWord(r.period_start, r.period_end) + ' ' + (TYPE_WORD[r.kind] || '')).toLowerCase().indexOf(q) > -1;
    });
    var byTab = {};
    HUB_BANDS.forEach(function (bd) {
      byTab[bd[0]] = rows.filter(function (r) {
        return r.status === bd[0] && (bd[0] !== 'published' || q || inPeriod(r, period));
      });
    });
    /* The tab chosen stays; opened first on the stage with the most to do
       next (Drafts, then In review, Confirmed, Published), and a search
       that finds nothing here moves to the first stage where it does. */
    if (!hub.tab || (q && !byTab[hub.tab].length)) {
      hub.tab = (HUB_BANDS.filter(function (bd) { return byTab[bd[0]].length; })[0] || HUB_BANDS[0])[0];
    }
    strip.hidden = !hub.rows.length;
    strip.innerHTML = HUB_BANDS.map(function (bd) {
      var on = bd[0] === hub.tab, n = byTab[bd[0]].length;
      return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" data-tab="' + bd[0] + '" id="rhTab-' + bd[0] + '"' +
        ' aria-selected="' + on + '" aria-controls="rhList" tabindex="' + (on ? 0 : -1) + '">' +
        '<span>' + esc(bd[1]) + '</span><span class="tab-n"' + (n ? '' : ' hidden') + '>' + n + '</span></button>';
    }).join('');
    if (window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(strip);
    /* The period is a question only Published asks, and a search sets it aside. */
    $('rhPeriod').hidden = hub.tab !== 'published' || Boolean(q);
    list.setAttribute('aria-labelledby', 'rhTab-' + hub.tab);
    var mine = byTab[hub.tab];
    var shown = HUB_BANDS.reduce(function (t, bd) { return t + byTab[bd[0]].length; }, 0);
    $('rhCount').textContent = !q && !kind && shown === hub.rows.length ? plural(hub.rows.length, 'report') : shown + ' of ' + hub.rows.length;
    list.innerHTML = '';
    if (!hub.rows.length) {
      UI.emptyLine(list, 'No reports.', may('work') ? 'Start the first report' : null, may('work') ? function () { newSheet($('rhNew')); } : null);
      return;
    }
    if (!rows.length) { UI.emptyLine(list, 'No matches.', 'Clear the search', function () { $('rhFind').value = ''; $('rhKind').value = ''; paintHub(); }); return; }
    if (!mine.length) {
      if (hub.tab === 'published' && period !== 'all') {
        UI.emptyLine(list, 'None published in this period.', 'Show all', function () { $('rhPeriod').value = 'all'; paintHub(); });
      } else UI.emptyLine(list, 'No reports.');
      return;
    }
    var GRP = window.ADspaceGroup;
    var months = [];
    mine.forEach(function (r) { var k = monthKey(r); if (months.indexOf(k) < 0) months.push(k); });
    months.sort().reverse();
    months.forEach(function (k, i) {
      var inMonth = mine.filter(function (r) { return monthKey(r) === k; });
      list.appendChild(GRP.section({
        route: 'reports', key: hub.tab + ':' + k, name: monthName(k), count: inMonth.length,
        /* Published keeps its newest month open and the rest shut; the
           working stages are short and open. A search opens every card. */
        shut: q ? false : GRP.shut('reports', hub.tab + ':' + k, hub.tab === 'published' && i > 0, months.length === 1),
        table: function () {
          var t = GRP.table('rh-row', ['Client', 'Period', 'Version', 'Updated', '']);
          GRP.more(t, inMonth, 30, 'reports', function (r) {
            var c = hub.byClient[r.client_id] || {};
            var b2 = document.createElement('button');
            b2.type = 'button'; b2.className = 'crm-row rh-row';
            /* A white-label report is named by its brand and marked so,
               the client it is billed to under it (2026-10-07). */
            var wl = r.brand_id && r.brand_name;
            b2.innerHTML = '<span class="rp-name"><b>' + esc(wl ? r.brand_name : (c.name || '')) + (wl ? '<span class="chip rp-wl">White label</span>' : '') +
                '</b><small>' + esc((wl ? (c.name || '') + ' · ' : '') + (TYPE_WORD[r.kind] || '') +
                (r.status === 'review' && r.reviewer_id && nameOf(r.reviewer_id) ? ' · With ' + nameOf(r.reviewer_id) : '') +
                (r.status === 'published' ? (r.sent_on ? ' · Sent ' + dayWord(r.sent_on) : ' · Not sent') : '')) + '</small></span>' +
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
      if (!st.open || !st.open.id) return { tab: hub.tab && hub.tab !== 'draft' ? hub.tab : '' };
      return { report: st.open.id, step: st.open.client_id ? st.step : '' };
    },
    enterHub: enterHub
  };
  if (bridge.reportsReady) bridge.reportsReady();
})();
