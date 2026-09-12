/*
 * Client Portal — what a client sees of its own record.
 *
 * One sign-in by email link, one client on the page: the company as
 * registered, the people, the confirmed and quoted services, the letters
 * issued, the Content Review and Creator Campaign pages, and the requests
 * the client has raised. The console is the source of truth; nothing here
 * edits a record. A request is a row the team acts on.
 *
 * The page reads and writes through three functions (get_portal,
 * portal_request, portal_withdraw); the database decides what this email
 * may see on every call.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  var MON = window.ADspaceMoney;
  var ORG = window.ADSPACE_ORG || {};
  var DOCS = window.ADspaceDocs;
  var $   = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  // The one extra control in the header, moved into the chrome's slot.
  (function () {
    var slot = window.ADspaceChrome && window.ADspaceChrome.actions();
    var extra = $('chromeExtra');
    if (slot && extra) slot.insertBefore(extra.content.cloneNode(true), slot.firstChild);
  })();

  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  var EXT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';

  // ---- Words, in both languages ------------------------------------------
  var T = {
    en: {
      kicker: 'Client Portal', lang: '中文', signOut: 'Sign out',
      signTitle: 'Client sign-in', signText: 'Enter the email address on file with ADspace.', sendLink: 'Send link',
      sentTitle: 'Check your email', sentText: function (e) { return 'A sign-in link has been sent to ' + e + '.'; },
      emailNeeded: 'An email is required.', noAccess: 'Access not assigned', noAccessText: 'Please contact your ADspace account manager.',
      failTitle: 'Unable to load', failText: 'Please refresh, or contact your ADspace account manager.',
      overview: 'Overview', requestChange: 'Request change', services: 'Services', requests: 'Requests', letters: 'Letters',
      engagements: 'Engagements', payment: 'Payment', account: 'Account',
      legalName: 'Registered name', regNo: 'Registration no.', address: 'Billing address', market: 'Market',
      manager: 'Account manager', status: 'Status', notSet: 'Not set',
      my: 'Malaysia', sg: 'Singapore',
      stage: { lead: 'Lead', contacted: 'Contacted', proposal: 'Proposal sent', active: 'Active', paused: 'Paused', past: 'Past' },
      contact: 'Contact', reach: 'Reach', mainContact: 'Main contact', portal: 'Portal', noContacts: 'No contacts.',
      service: 'Service', qtyRate: 'Qty × rate', amount: 'Amount', state: 'State', noServices: 'No services.',
      svState: { quoted: 'Quoted', confirmed: 'Confirmed' }, months: function (n) { return n + ' months'; }, from: 'from', mo: 'mo',
      quotedTotal: 'Quoted', confirmedTotal: 'Confirmed',
      upgrade: 'Upgrade', downgrade: 'Downgrade', cancel: 'Cancel', details: 'Change of details',
      request: 'Request', fee: 'Fee', noRequests: 'No requests.', withdraw: 'Withdraw', undo: 'Undo',
      withdrawn: 'Withdrawn', withdrawnSay: 'Request withdrawn.',
      rqState: { requested: 'Requested', reviewing: 'Reviewing', approved: 'Approved', declined: 'Declined', applied: 'Applied' },
      reply: 'Reply', more: 'More actions',
      document: 'Document', total: 'Total', issued: 'Issued', download: 'Download', noLetters: 'No letters.', offer: 'Letter of Offer',
      review: 'Content Review', open: 'Open', campaign: 'Creator campaign',
      campState: { open: 'Open', production: 'In production', completed: 'Completed' },
      bank: 'Bank', reference: 'Payment reference', person: 'Person', email: 'Email', noAccessRows: 'No entries.',
      reqTitle: function (k) { return T.en[k]; }, line: 'Service', note: 'Note', noteFor: { upgrade: 'What to change to', downgrade: 'What to change to', cancel: 'Reason (optional)', details: 'What to change' },
      send: 'Send request', close: 'Cancel', sent: 'Sent.', noteNeeded: 'A note is required.', company: 'Company'
    },
    zh: {
      kicker: '客户平台', lang: 'EN', signOut: '退出',
      signTitle: '客户登录', signText: '请输入在 ADspace 登记的电子邮箱。', sendLink: '发送链接',
      sentTitle: '请查收邮件', sentText: function (e) { return '登录链接已发送至 ' + e + '。'; },
      emailNeeded: '请输入电子邮箱。', noAccess: '尚未开通访问', noAccessText: '请联系您的 ADspace 客户经理。',
      failTitle: '无法加载', failText: '请刷新页面，或联系您的 ADspace 客户经理。',
      overview: '公司概览', requestChange: '申请修改', services: '服务', requests: '申请', letters: '函件',
      engagements: '进行中的项目', payment: '付款', account: '账户',
      legalName: '注册名称', regNo: '注册号码', address: '账单地址', market: '市场',
      manager: '客户经理', status: '状态', notSet: '未填写',
      my: '马来西亚', sg: '新加坡',
      stage: { lead: '潜在客户', contacted: '已联系', proposal: '已发提案', active: '合作中', paused: '暂停', past: '已结束' },
      contact: '联系人', reach: '联系方式', mainContact: '主要联系人', portal: '平台', noContacts: '暂无联系人。',
      service: '服务', qtyRate: '数量 × 单价', amount: '金额', state: '状态', noServices: '暂无服务。',
      svState: { quoted: '已报价', confirmed: '已确认' }, months: function (n) { return n + ' 个月'; }, from: '起', mo: '个月',
      quotedTotal: '已报价', confirmedTotal: '已确认',
      upgrade: '升级', downgrade: '降级', cancel: '取消', details: '资料变更',
      request: '申请', fee: '费用', noRequests: '暂无申请。', withdraw: '撤回', undo: '撤销',
      withdrawn: '已撤回', withdrawnSay: '申请已撤回。',
      rqState: { requested: '已提交', reviewing: '审核中', approved: '已批准', declined: '未批准', applied: '已生效' },
      reply: '回复', more: '更多操作',
      document: '文件', total: '总额', issued: '已签发', download: '下载', noLetters: '暂无函件。', offer: '报价函',
      review: '内容审阅', open: '打开', campaign: '博主推广',
      campState: { open: '进行中', production: '制作中', completed: '已完成' },
      bank: '银行', reference: '付款备注', person: '姓名', email: '电子邮箱', noAccessRows: '暂无记录。',
      reqTitle: function (k) { return T.zh[k]; }, line: '服务', note: '备注', noteFor: { upgrade: '希望更改为', downgrade: '希望更改为', cancel: '原因（可选）', details: '需要修改的内容' },
      send: '提交申请', close: '取消', sent: '已提交。', noteNeeded: '请填写备注。', company: '公司'
    }
  };
  var lang = 'en';
  function t() { return T[lang]; }
  var LANG_KEY = 'adspace.portal.lang';
  try { var saved = localStorage.getItem(LANG_KEY); if (saved && T[saved]) lang = saved; } catch (e) {}

  function setLang(next) {
    lang = next;
    try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
    document.documentElement.lang = lang === 'zh' ? 'zh' : 'en';
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    if ($('kicker')) $('kicker').textContent = t().kicker;
    $('portalOutWord').textContent = t().signOut;
    $('signGo').textContent = t().sendLink;
    $('signEmail').setAttribute('aria-label', t().email);
    if (feed) build(); else if (shownState) showState.apply(null, shownState);
  }
  if ($('langToggle')) $('langToggle').addEventListener('click', function () { setLang(lang === 'en' ? 'zh' : 'en'); });

  // ---- Helpers -------------------------------------------------------------
  function msg(id, text, kind) {
    var el = $(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind ? ' ' + kind : '');
  }
  function niceDate(d) {
    if (!d) return '';
    var dt = new Date(String(d).slice(0, 10) + 'T00:00:00');
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleDateString(lang === 'zh' ? 'zh-CN' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  function amountOf(l) { return Number(l.qty || 0) * Number(l.rate || 0) * Math.max(1, Number(l.tenure || 1)); }
  function startDay(s) { s = String(s || ''); return s.length === 7 ? s + '-01' : s; }
  function termWord(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (n === 1 && !l.start_on) return '';
    return (n > 1 ? t().months(n) : '') + (l.start_on ? ' ' + t().from + ' ' + niceDate(startDay(l.start_on)) : '');
  }
  function mkt() { return (feed && feed.client && feed.client.market) || 'MY'; }
  function money2(n) { return MON.money2(n, mkt()); }
  function chip(word, tone) { return '<span class="chip-state' + (tone ? ' ' + tone : '') + '">' + esc(word) + '</span>'; }
  function table(head) {
    var el = document.createElement('div');
    el.className = 'crm-table';
    if (head) el.innerHTML = head;
    return el;
  }
  function empty(box, word) { box.innerHTML = '<div class="empty">' + esc(word) + '</div>'; }

  /* A menu in a table row is placed on the viewport under its button, as in
     the console, so the table never clips it. */
  function wireMenu(row) {
    var menu = row.querySelector('[data-menu]');
    var btn = row.querySelector('[data-a="menu"]');
    if (!menu || !btn) return;
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) {
        var r = btn.getBoundingClientRect();
        menu.style.position = 'fixed';
        menu.style.top = (r.bottom + 4) + 'px';
        menu.style.right = 'auto';
        menu.style.left = Math.max(8, r.right - menu.offsetWidth) + 'px';
      }
    });
  }
  document.addEventListener('click', function (e) {
    if (e.target.closest('.kmenu, .team-act')) return;
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
  });
  window.addEventListener('scroll', function () {
    Array.prototype.forEach.call(document.querySelectorAll('.team-act .kmenu'), function (m) { m.hidden = true; });
  }, true);
  function menuCell(items) {
    if (!items.length) return '<span class="team-act"></span>';
    return '<span class="team-act">' +
      '<button class="kmenu-btn" data-a="menu" type="button" aria-label="' + esc(t().more) + '" aria-expanded="false">' + DOTS + '</button>' +
      '<div class="kmenu" data-menu hidden>' + items.map(function (it) {
        return '<button class="kmenu-item' + (it[2] ? ' is-danger' : '') + '" data-a="' + it[0] + '" type="button"><b>' + esc(it[1]) + '</b></button>';
      }).join('') + '</div></span>';
  }
  var undoTimer = null;
  function undoBar(text, undo) {
    var bar = $('rqUndo');
    bar.hidden = false;
    bar.innerHTML = '<span>' + esc(text) + '</span><button class="btn btn-sm" type="button">' + esc(t().undo) + '</button>';
    bar.querySelector('button').addEventListener('click', function () { bar.hidden = true; undo(); });
    clearTimeout(undoTimer);
    undoTimer = setTimeout(function () { bar.hidden = true; }, 8000);
  }

  // ---- Whole-page states ---------------------------------------------------
  var shownState = null;
  function showState(kind, extra) {
    shownState = [kind, extra];
    $('app').hidden = true;
    $('stateBox').hidden = false;
    $('signForm').hidden = kind !== 'sign';
    $('portalOut').hidden = kind === 'sign' || kind === 'sent';
    document.body.classList.add('is-plain');
    var w = t();
    var title = { sign: w.signTitle, sent: w.sentTitle, none: w.noAccess, fail: w.failTitle }[kind];
    var text = { sign: w.signText, sent: w.sentText(extra || ''), none: w.noAccessText, fail: w.failText }[kind];
    $('stateTitle').textContent = title;
    $('stateText').textContent = text;
    msg('stateMsg', kind === 'fail' && extra ? extra : '');
    if (kind === 'sign') $('signEmail').focus();
  }

  // ---- Sign in ---------------------------------------------------------------
  function sendLink() {
    var email = ($('signEmail').value || '').trim().toLowerCase();
    if (!email) { msg('stateMsg', t().emailNeeded, 'err'); $('signEmail').focus(); return; }
    $('signGo').disabled = true;
    db.auth.signInWithOtp({ email: email, options: { emailRedirectTo: location.origin + '/client/' } })
      .then(function (r) {
        $('signGo').disabled = false;
        if (r.error) { msg('stateMsg', r.error.message, 'err'); return; }
        showState('sent', email);
      }, function (e) { $('signGo').disabled = false; msg('stateMsg', (e && e.message) || String(e), 'err'); });
  }
  $('signGo').addEventListener('click', sendLink);
  $('signForm').addEventListener('submit', sendLink);
  $('portalOut').addEventListener('click', function () {
    db.auth.signOut().then(function () { location.reload(); });
  });

  // ---- Load ------------------------------------------------------------------
  var feed = null;
  var wanted = null;   // the client chosen from the select, when there are several
  function load() {
    db.rpc('get_portal', { p_client: wanted }).then(function (r) {
      if (r.error) { showState('fail', r.error.message); return; }
      var d = r.data || {};
      if (d.error === 'no-access' || d.error === 'not-signed-in') { showState('none'); return; }
      if (d.error) { showState('fail', d.error); return; }
      feed = d;
      shownState = null;
      build();
    }, function (e) { showState('fail', (e && e.message) || String(e)); });
  }

  var session = null;
  function gate(s) {
    session = s;
    if (!s) { feed = null; showState('sign'); return; }
    load();
  }
  if (!db) {
    showState('fail', 'Not configured.');
  } else {
    db.auth.getSession().then(function (r) { gate(r.data.session); });
    db.auth.onAuthStateChange(function (_e, s) {
      // A token refresh is not a change of person; a reload would wipe what is on screen.
      if (s && session && s.user && session.user && s.user.email === session.user.email) { session = s; return; }
      gate(s);
    });
  }

  // ---- Build ---------------------------------------------------------------
  function build() {
    var w = t();
    var c = feed.client || {};
    document.body.classList.remove('is-plain');
    $('stateBox').hidden = true;
    $('app').hidden = false;
    $('portalOut').hidden = false;
    if ($('kicker')) $('kicker').textContent = w.kicker;
    if ($('langToggle')) $('langToggle').textContent = w.lang;
    if (window.ADspaceChrome) window.ADspaceChrome.preparedFor('', '');

    ['ovHead:overview', 'svcHead:services', 'rqHead:requests', 'docHead:letters', 'engHead:engagements',
     'payHead:payment', 'accHead:account'].forEach(function (p) {
      var a = p.split(':'); $(a[0]).textContent = w[a[1]];
    });
    $('ovRequestWord').textContent = w.requestChange;

    // Several companies on one email: a select on the head; otherwise nothing.
    var pick = $('clientPick');
    var many = (feed.clients || []).length > 1;
    pick.hidden = !many;
    if (many) {
      pick.innerHTML = feed.clients.map(function (x) {
        return '<option value="' + esc(x.id) + '"' + (x.id === c.id ? ' selected' : '') + '>' + esc(x.name) + '</option>';
      }).join('');
      pick.setAttribute('aria-label', w.company);
    }

    // Overview
    var st = w.stage[c.stage] || c.stage || '';
    var stTone = c.stage === 'active' ? 'is-ok' : (c.stage === 'paused' || c.stage === 'proposal') ? 'is-warn' : '';
    var mute = function (s) { return '<span class="muted">' + esc(s) + '</span>'; };
    $('ovFacts').innerHTML = [
      [w.legalName, c.legal_name ? esc(c.legal_name) : mute(w.notSet)],
      [w.regNo, c.company_no ? esc(c.company_no) : mute(w.notSet)],
      [w.address, c.billing_address ? esc(c.billing_address) : mute(w.notSet)],
      [w.market, esc((c.market === 'SG' ? w.sg : w.my) + ' · ' + MON.sign(c.market))],
      [w.manager, c.owner ? esc(c.owner) : mute(w.notSet)],
      [w.status, chip(st, stTone)]
    ].map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + f[1] + '</dd></div>'; }).join('');

    // Contacts, read only: who, how to reach them.
    var cbox = $('ovContacts');
    var contacts = feed.contacts || [];
    if (!contacts.length) empty(cbox, w.noContacts);
    else {
      var ct = table('<div class="crm-head svc-row ct-row"><span>' + esc(w.contact) + '</span><span>' + esc(w.reach) + '</span><span></span></div>');
      contacts.forEach(function (k) {
        var row = document.createElement('div');
        row.className = 'svc-row ct-row';
        var wa = String(k.phone || '').replace(/[^0-9]/g, '');
        row.innerHTML =
          '<span class="svc-name"><b>' + esc(k.name) +
            (k.is_primary ? ' <span class="tone is-ok">' + esc(w.mainContact) + '</span>' : '') +
            (k.portal_access ? ' <span class="tone">' + esc(w.portal) + '</span>' : '') + '</b>' +
            (k.role ? '<small>' + esc(k.role) + '</small>' : '') + '</span>' +
          '<span class="crm-reach">' +
            (k.phone ? '<a class="plink" href="tel:' + esc(k.phone) + '">' + esc(k.phone) + '</a>' : '') +
            (wa ? '<a class="plink" href="https://wa.me/' + esc(wa) + '" target="_blank" rel="noopener">WhatsApp</a>' : '') +
            (k.email ? '<a class="plink" href="mailto:' + esc(k.email) + '">' + esc(k.email) + '</a>' : '') +
          '</span><span class="team-act"></span>';
        ct.appendChild(row);
      });
      cbox.innerHTML = ''; cbox.appendChild(ct);
    }

    // Services: the confirmed lines, and the quoted ones still to sign.
    var sbox = $('svcBox');
    var lines = feed.services || [];
    if (!lines.length) empty(sbox, w.noServices);
    else {
      var stb = table('<div class="crm-head svc-row csv-row"><span>' + esc(w.service) + '</span><span class="svc-rate">' + esc(w.qtyRate) +
        '</span><span class="svc-rate">' + esc(w.amount) + '</span><span>' + esc(w.state) + '</span><span></span></div>');
      lines.forEach(function (l) {
        var row = document.createElement('div');
        row.className = 'svc-row csv-row';
        var sub = [l.unit, termWord(l), l.note].filter(Boolean).join(' · ');
        var items = l.state === 'confirmed' ? [['upgrade', w.upgrade], ['downgrade', w.downgrade], ['cancel', w.cancel, true]] : [];
        row.innerHTML =
          '<span class="svc-name"><b>' + esc(l.label) + '</b>' + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span>' +
          '<span class="svc-rate svc-calc">' + esc(Number(l.qty) + ' × ' + money2(l.rate) + (Number(l.tenure || 1) > 1 ? ' × ' + Number(l.tenure) + ' ' + w.mo : '')) + '</span>' +
          '<span class="svc-rate svc-amt"><b>' + esc(money2(amountOf(l))) + '</b></span>' +
          '<span class="svc-state">' + chip(w.svState[l.state] || l.state, l.state === 'confirmed' ? 'is-ok' : 'is-warn') + '</span>' +
          menuCell(items);
        wireMenu(row);
        items.forEach(function (it) {
          row.querySelector('[data-a="' + it[0] + '"]').addEventListener('click', function () { openRequest(it[0], l); });
        });
        stb.appendChild(row);
      });
      var sum = function (s) { return lines.filter(function (l) { return l.state === s; }).reduce(function (a, l) { return a + amountOf(l); }, 0); };
      var quoted = sum('quoted'), confirmed = sum('confirmed');
      var tot = document.createElement('div');
      tot.className = 'csv-total';
      tot.innerHTML = (quoted ? '<span>' + esc(w.quotedTotal) + '<b>' + esc(money2(quoted)) + '</b></span>' : '') +
        '<span class="is-total">' + esc(w.confirmedTotal) + '<b>' + esc(money2(confirmed)) + '</b></span>';
      stb.appendChild(tot);
      sbox.innerHTML = ''; sbox.appendChild(stb);
    }

    // Requests, once there is one.
    var reqs = feed.requests || [];
    $('rqWrap').hidden = !reqs.length;
    var rbox = $('rqBox');
    if (reqs.length) {
      var rtb = table('<div class="crm-head svc-row doc-row"><span>' + esc(w.request) + '</span><span class="svc-rate">' + esc(w.fee) +
        '</span><span>' + esc(w.state) + '</span><span></span></div>');
      reqs.forEach(function (r) {
        var row = document.createElement('div');
        var gone = Boolean(r.withdrawn_at);
        row.className = 'svc-row doc-row' + (gone ? ' is-off' : '');
        var tone = gone ? '' : (r.state === 'approved' || r.state === 'applied') ? 'is-ok' : (r.state === 'declined') ? '' : 'is-warn';
        var sub = [niceDate(r.created_at), r.note].filter(Boolean).join(' · ');
        var items = (!gone && r.state === 'requested') ? [['withdraw', w.withdraw, true]] : [];
        row.innerHTML =
          '<span class="svc-name"><b>' + esc((w[r.kind] || r.kind) + (r.service_label ? ' · ' + r.service_label : '')) + '</b>' +
            (sub ? '<small>' + esc(sub) + '</small>' : '') +
            (r.reply ? '<small>' + esc(w.reply + ': ' + r.reply) + '</small>' : '') + '</span>' +
          '<span class="svc-rate svc-amt">' + (r.fee != null && r.fee !== '' ? '<b>' + esc(money2(r.fee)) + '</b>' : '<span class="muted">' + esc(MON.sign(mkt())) + '</span>') + '</span>' +
          '<span class="svc-state">' + chip(gone ? w.withdrawn : (w.rqState[r.state] || r.state), tone) + '</span>' +
          menuCell(items);
        wireMenu(row);
        if (items.length) row.querySelector('[data-a="withdraw"]').addEventListener('click', function () { withdraw(r); });
        rtb.appendChild(row);
      });
      rbox.innerHTML = ''; rbox.appendChild(rtb);
    } else rbox.innerHTML = '';

    // Letters
    var dbox = $('docBox');
    var docs = feed.documents || [];
    if (!docs.length) empty(dbox, w.noLetters);
    else {
      var dtb = table('<div class="crm-head svc-row doc-row"><span>' + esc(w.document) + '</span><span class="svc-rate">' + esc(w.total) +
        '</span><span>' + esc(w.state) + '</span><span></span></div>');
      docs.forEach(function (d) {
        var row = document.createElement('div');
        row.className = 'svc-row doc-row';
        var items = DOCS ? [['download', w.download]] : [];
        row.innerHTML =
          '<span class="svc-name"><b>' + esc(d.number) + '</b><small>' + esc(w.offer + ' · ' + niceDate(d.issued_at)) + '</small></span>' +
          '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(d.total, d.market)) + '</b></span>' +
          '<span class="svc-state">' + chip(w.issued, 'is-ok') + '</span>' +
          menuCell(items);
        wireMenu(row);
        if (items.length) row.querySelector('[data-a="download"]').addEventListener('click', function () {
          DOCS.download(d, function (warn) { msg('docMsg', warn || '', warn ? 'err' : ''); });
        });
        dtb.appendChild(row);
      });
      dbox.innerHTML = ''; dbox.appendChild(dtb);
    }

    // Engagements: the two client pages, opened with their own links.
    var eng = [];
    if (feed.review && feed.review.token) eng.push({ name: w.review, url: '/review/?k=' + encodeURIComponent(feed.review.token) });
    (feed.campaigns || []).forEach(function (m) {
      eng.push({ name: (lang === 'zh' && m.title_zh) ? m.title_zh : m.title, sub: w.campaign + (w.campState[m.state] ? ' · ' + w.campState[m.state] : ''),
        url: '/creators/?k=' + encodeURIComponent(m.token) });
    });
    $('engWrap').hidden = !eng.length;
    var ebox = $('engBox');
    if (eng.length) {
      var etb = table('');
      eng.forEach(function (e) {
        var row = document.createElement('div');
        row.className = 'svc-row ct-row';
        row.innerHTML = '<span class="svc-name"><b>' + esc(e.name) + '</b>' + (e.sub ? '<small>' + esc(e.sub) + '</small>' : '') + '</span>' +
          '<span class="crm-reach"><a class="plink" href="' + esc(e.url) + '" target="_blank" rel="noopener">' + esc(w.open) + ' ' + EXT + '</a></span>' +
          '<span class="team-act"></span>';
        etb.appendChild(row);
      });
      ebox.innerHTML = ''; ebox.appendChild(etb);
    } else ebox.innerHTML = '';

    // Payment guidance, only once the bank line is set.
    $('payWrap').hidden = !ORG.bank;
    if (ORG.bank) {
      $('payFacts').innerHTML = [[w.bank, ORG.bank], [w.reference, c.legal_name || c.name || '']]
        .map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('');
    }

    // Account: who can sign in. Managed by ADspace.
    var abox = $('accBox');
    var acc = feed.access || [];
    if (!acc.length) empty(abox, w.noAccessRows);
    else {
      var atb = table('<div class="crm-head svc-row ct-row"><span>' + esc(w.person) + '</span><span>' + esc(w.email) + '</span><span></span></div>');
      acc.forEach(function (a) {
        var row = document.createElement('div');
        row.className = 'svc-row ct-row';
        row.innerHTML = '<span class="svc-name"><b>' + esc(a.name) + '</b></span>' +
          '<span class="crm-reach"><a class="plink" href="mailto:' + esc(a.email) + '">' + esc(a.email) + '</a></span><span class="team-act"></span>';
        atb.appendChild(row);
      });
      abox.innerHTML = ''; abox.appendChild(atb);
    }
  }

  $('clientPick').addEventListener('change', function () { wanted = this.value; load(); });

  // ---- Requests ------------------------------------------------------------
  var req = null;   // { kind, line }
  function openRequest(kind, line) {
    var w = t();
    req = { kind: kind, line: line || null };
    $('reqHeading').textContent = w[kind];
    $('reqFacts').innerHTML = [
      [w.company, feed.client.name],
      line ? [w.line, line.label] : null
    ].filter(Boolean).map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('');
    $('reqNoteLabel').textContent = w.noteFor[kind] || w.note;
    $('reqNote').value = '';
    $('reqGo').textContent = w.send;
    $('reqCancel').textContent = w.close;
    msg('reqMsg', '');
    $('reqSheet').hidden = false;
    $('reqNote').focus();
  }
  function shutRequest() { $('reqSheet').hidden = true; req = null; }
  $('ovRequest').addEventListener('click', function () { openRequest('details', null); });
  $('reqCancel').addEventListener('click', shutRequest);
  $('reqSheet').addEventListener('click', function (e) { if (e.target === this) shutRequest(); });
  $('reqGo').addEventListener('click', function () {
    if (!req) return;
    var note = ($('reqNote').value || '').trim();
    if (req.kind !== 'cancel' && !note) { msg('reqMsg', t().noteNeeded, 'err'); $('reqNote').focus(); return; }
    $('reqGo').disabled = true;
    db.rpc('portal_request', { p_client: feed.client.id, p_kind: req.kind, p_service: req.line ? req.line.id : null, p_note: note || null })
      .then(function (r) {
        $('reqGo').disabled = false;
        var d = r.data || {};
        if (r.error || d.error) { msg('reqMsg', r.error ? r.error.message : (d.error === 'note-required' ? t().noteNeeded : d.error), 'err'); return; }
        shutRequest();
        msg('rqMsg', t().sent, 'ok');
        load();
      }, function (e) { $('reqGo').disabled = false; msg('reqMsg', (e && e.message) || String(e), 'err'); });
  });

  function withdraw(r) {
    db.rpc('portal_withdraw', { p_id: r.id, p_undo: false }).then(function (res) {
      var d = res.data || {};
      if (res.error || d.error) { msg('rqMsg', res.error ? res.error.message : d.error, 'err'); return; }
      msg('rqMsg', '');
      load();
      undoBar(t().withdrawnSay, function () {
        db.rpc('portal_withdraw', { p_id: r.id, p_undo: true }).then(function () { load(); });
      });
    });
  }

  setLang(lang);
})();
