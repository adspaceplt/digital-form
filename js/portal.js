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
  /* FIRST-VISIT GUIDE (js/guide.js, the user, 2026-10-07): offered once in
     this browser, the moment the page shows what it is for. */
  var GUIDE = { name: { en: 'Your portal', zh: '客户门户' }, steps: [
    { at: '#cpTabs', text: { en: 'Your content, reports, services and meetings are each on their own tab.', zh: '内容、报告、服务与会议，各在一个分页。' } },
    { at: '#ovRequest', text: { en: 'Use Request change to ask your account manager for an upgrade, a downgrade or a change of details.', zh: '如需升级、降级或更新资料，请点击「申请修改」，客户经理将为您跟进。' } }] };
  var db  = API && API.client;
  var MON = window.ADspaceMoney;
  /* The shared list and record primitives: the same `initials` both console
     records draw their mark from, so one reading serves all three pages. */
  var UI  = window.ADspaceState;
  var ORG = window.ADSPACE_ORG || {};
  var CFG = window.ADSPACE_CONFIG || {};
  /* The PDF scripts are fetched on first ask (js/chrome.js need): where a
     letter's or a report's Download is drawn, and at its press if still
     on its way, so a visit with nothing to download fetches neither. */
  var need = function (keys) { return window.ADspaceChrome.need(keys); };
  var $   = function (id) { return document.getElementById(id); };
  /* The page's worker holds a drawn PDF under its own name, so an iPhone's
     Save to Files keeps it (client/sw.js, js/file-sw.js; 2026-10-07). */
  try {
    if ('serviceWorker' in navigator && location.protocol !== 'file:') {
      window.addEventListener('load', function () {
        navigator.serviceWorker.register('/client/sw.js', { scope: '/client/' }).catch(function () {});
      });
    }
  } catch (e) { /* no worker: the share sheet stands in */ }

  function esc(s) { return window.ADspaceWords.esc(s); }

  // The one extra control in the header, moved into the chrome's slot.
  (function () {
    var slot = window.ADspaceChrome && window.ADspaceChrome.actions();
    var extra = $('chromeExtra');
    if (slot && extra) slot.insertBefore(extra.content.cloneNode(true), document.getElementById('langToggle'));
  })();

  var DOTS = window.ADspaceIcons.glyph('more');
  /* The leaving mark from the client pages' one icon set (js/icons.js). */
  var EXT = window.ADspaceIcons ? window.ADspaceIcons.svg('out') : '';
  /* A way to another page in this tab carries the chevron after its words. */
  var GO = window.ADspaceIcons ? window.ADspaceIcons.svg('chevron') : '';
  /* Download carries the console's own mark (Reports' Download). */
  var FILE = window.ADspaceIcons.glyph('file');

  // ---- Words, in both languages ------------------------------------------
  var T = window.ADspaceWords.of({
    en: {
      kicker: 'Client Portal', lang: '中文', signOut: 'Sign out',
      signTitle: 'Client sign-in', signText: 'Enter the email address on file with ADspace.', sendLink: 'Continue',
      sentTitle: 'Check your email', sentText: function (e) { return window.ADspaceWords.line.codeSent.replace('{email}', e); },
      code: 'Sign-in code', signIn: 'Sign in', otherEmail: 'Use another email',
      codeNeeded: 'Enter the code from the email.', codeWrong: 'The code is incorrect or has expired. Please request a new code.',
      codeWait: 'Too many attempts. Please wait a few minutes, then request a new code.', codeFail: 'Sign-in was unsuccessful. Please try again.',
      emailNeeded: 'Please enter your email address.',
      emailBad: 'Enter a valid email address.',
      signFail: 'The email could not be sent. Please try again in a minute, or contact your ADspace account manager.',
      overview: 'Overview', requestChange: 'Request change', services: 'Services', requests: 'Requests', letters: 'Letters',
      engagements: 'Engagements', payment: 'Payment', account: 'Portal access',
      addCal: 'Add to calendar', monthOf: function (a, b) { return 'Month ' + a + ' of ' + b; }, endsOn: function (d) { return 'Ends ' + d; },
      legalName: 'Registered Company Name', regNo: 'Business Registration No.', address: 'Billing address', market: 'Market',
      manager: 'Account manager', status: 'Status', notSet: 'Not set',
      my: 'Malaysia', sg: 'Singapore',
      contact: 'Contact', reach: 'Contact details', contacts: 'Contacts',
      mainContact: 'Primary contact', portal: 'Portal', noContacts: 'No contacts.',
      service: 'Service', qtyRate: 'Qty × rate', amount: 'Amount', state: 'Status', noServices: 'No services.',
      months: function (n) { return n + ' months'; }, from: function (d) { return 'from ' + d; }, fromAlone: function (d) { return 'From ' + d; }, mo: 'months',
      quotedTotal: 'To quote', confirmedTotal: 'Confirmed',
      /* Cancel service, never Cancel: the sheet's foot holds Cancel, which
         shuts it (2026-10-31, POR-2). The stored kind stays `cancel`. */
      upgrade: 'Upgrade', downgrade: 'Downgrade', cancel: 'Cancel service', details: 'Change of details',
      request: 'Request', fee: 'Fee', noRequests: 'No requests.', withdraw: 'Withdraw', undo: 'Undo',
      withdrawn: 'Withdrawn', withdrawnSay: 'Request withdrawn.',
      reply: 'Reply', more: 'More actions',
      document: 'Document', total: 'Total', issued: 'Issued', download: 'Download', noLetters: 'No letters.', offer: 'Letter of Offer',
      reports: 'Reports', report: 'Report', published: 'Published', version: 'Version',
      meetings: 'Meetings', meeting: 'Meeting', when: 'Date and time', upcoming: 'Upcoming', held: 'Completed',
      join: 'Join meeting', discussion: 'content discussion', discussionAlone: 'Content discussion', to: 'to',
      channel: { onsite: 'On site', google_meet: 'Google Meet', zoom: 'Zoom', other: 'Online' },
      review: 'Content Review', open: 'Open', campaign: 'Creator campaign',
      bank: 'Bank', reference: 'Payment reference', person: 'Person', email: 'Email',
      signInEmail: 'Sign-in email', noAccessRows: 'No entries.',
      reqTitle: function (k) { return T.en[k]; }, reqKind: 'Request', line: 'Service', note: 'Note', noteFor: { upgrade: 'Requested change', downgrade: 'Requested change', cancel: 'Reason (optional)', details: 'Details to update' },
      send: 'Send request', close: 'Cancel', closeMark: 'Close', sent: 'Sent.', noteNeeded: 'Please describe the change required.', company: 'Company',
      tabsLabel: 'Portal sections', sideLabel: 'Account manager and company',
      tabs: { overview: 'Overview', content: 'Content', review: 'Content Review', scripts: 'Video Scripts', campaigns: 'Creator Campaigns',
        services: 'Services', letters: 'Letters', reports: 'Reports', meetings: 'Meetings', feedback: 'Feedback', account: 'Account' },
      rateTitle: 'Rate your experience', fbRequested: 'Requested {d}', fbSubmit: 'Submit',
      loadFail: '{x} could not be loaded.', tryAgain: 'Try again',
      fbBy: 'Submitted {d} by {n}', fbOn: 'Submitted {d}', fbScore: '{v} of {m}',
      posts: function (n) { return n === 1 ? '1 post' : n + ' posts'; },
      toReview: function (n) { return n + ' to review'; }, changesAsked: 'Changes requested', allApproved: 'Approved', toReviewWord: 'To review',
      noPosts: 'No posts', shoot: function (d) { return 'Shooting on ' + d; }, noMonth: 'Month not set',
      scriptKind: { scenes: 'Detailed scenes', products: 'Products and scenes', story: 'Story and voice-over' },
      viewAll: 'View all', nextMeeting: 'Next meeting', latestReport: 'Latest report', yourManager: 'Your account manager', contactUs: 'Contact ADspace',
      lines: function (n) { return n === 1 ? '1 service' : n + ' services'; }, openRequests: 'Open requests', whatsapp: 'WhatsApp',
      invoices: 'Invoices', invoice: 'Invoice', dueOn: function (d) { return 'Due ' + d; }, balanceOf: function (v) { return 'Balance ' + v; },
      invState: { paid: 'Paid', outstanding: 'Outstanding', overdue: 'Overdue' }, downloadPdf: 'Download PDF'
    },
    zh: {
      kicker: '客户门户', lang: 'EN', signOut: '退出登录',
      signTitle: '客户登录', signText: '请输入在 ADspace 登记的电子邮箱。', sendLink: '继续',
      sentTitle: '请查收邮件', sentText: function (e) { return '如 ' + e + ' 已登记，登录验证码和链接已发送至该邮箱。'; },
      code: '登录验证码', signIn: '登录', otherEmail: '使用其他邮箱',
      codeNeeded: '请输入邮件中的验证码。', codeWrong: '验证码错误或已过期，请重新发送。',
      codeWait: '尝试次数过多，请稍候几分钟后重新发送验证码。', codeFail: '登录失败，请重试。',
      emailNeeded: '请输入电子邮箱。',
      emailBad: '请输入有效的电子邮箱。',
      signFail: '邮件发送失败，请稍后重试，或联系您的 ADspace 客户经理。',
      overview: '公司概览', requestChange: '申请修改', services: '服务', requests: '申请', letters: '函件',
      engagements: '合作项目', payment: '付款', account: '门户访问权限',
      addCal: '加入日历', monthOf: function (a, b) { return '第' + a + '个月，共' + b + '个月'; }, endsOn: function (d) { return d + '结束'; },
      legalName: '公司注册名称', regNo: '商业注册号码', address: '账单地址', market: '市场',
      manager: '客户经理', status: '状态', notSet: '未填写',
      my: '马来西亚', sg: '新加坡',
      contact: '联系人', reach: '联系方式', contacts: '联系人',
      mainContact: '主要联系人', portal: '平台', noContacts: '暂无联系人。',
      service: '服务', qtyRate: '数量 × 单价', amount: '金额', state: '状态', noServices: '暂无服务。',
      months: function (n) { return n + '个月'; }, from: function (d) { return d + '起'; }, fromAlone: function (d) { return d + '起'; }, mo: '个月',
      quotedTotal: '待报价', confirmedTotal: '已确认',
      upgrade: '升级', downgrade: '降级', cancel: '取消服务', details: '资料变更',
      request: '申请', fee: '费用', noRequests: '暂无申请。', withdraw: '撤回', undo: '撤销',
      withdrawn: '已撤回', withdrawnSay: '申请已撤回。',
      reply: '回复', more: '更多操作',
      document: '文件', total: '总额', issued: '已签发', download: '下载', noLetters: '暂无函件。', offer: '服务确认函',
      reports: '报告', report: '报告', published: '已发布', version: '版本',
      meetings: '会议', meeting: '会议', when: '日期与时间', upcoming: '即将举行', held: '已完成',
      join: '加入会议', discussion: '内容讨论', to: '至',
      channel: { onsite: '现场', google_meet: 'Google Meet', zoom: 'Zoom', other: '线上' },
      review: '内容审阅', open: '打开', campaign: '创作者项目',
      bank: '银行', reference: '付款备注', person: '姓名', email: '电子邮箱',
      signInEmail: '登录邮箱', noAccessRows: '暂无记录。',
      reqTitle: function (k) { return T.zh[k]; }, reqKind: '申请类型', line: '服务', note: '备注', noteFor: { upgrade: '所需更改', downgrade: '所需更改', cancel: '原因（可选）', details: '需要修改的内容' },
      send: '提交申请', close: '取消', closeMark: '关闭', sent: '已提交。', noteNeeded: '请描述所需的更改。', company: '公司',
      tabsLabel: '门户分页', sideLabel: '客户经理与公司',
      tabs: { overview: '概览', content: '内容', review: '内容审阅', scripts: '视频脚本', campaigns: '创作者项目',
        services: '服务', letters: '函件', reports: '报告', meetings: '会议', feedback: '反馈', account: '账户' },
      rateTitle: '请评价您的体验', fbRequested: '请求日期：{d}', fbSubmit: '提交',
      loadFail: '{x}无法加载。', tryAgain: '重试',
      fbBy: '{n}于{d}提交', fbOn: '{d}提交', fbScore: '{v}/{m}',
      posts: function (n) { return n + '篇帖子'; },
      toReview: function (n) { return n + '篇待审阅'; }, changesAsked: '已要求修改', allApproved: '已批准', toReviewWord: '待审阅',
      noPosts: '暂无帖子', shoot: function (d) { return d + '拍摄'; }, noMonth: '未定月份',
      scriptKind: { scenes: '详细分镜', products: '产品与分镜', story: '故事与旁白' },
      viewAll: '查看全部', nextMeeting: '下次会议', latestReport: '最新报告', yourManager: '您的客户经理', contactUs: '联系 ADspace',
      lines: function (n) { return n + '项服务'; }, openRequests: '处理中的申请', whatsapp: 'WhatsApp',
      invoices: '发票', invoice: '发票', dueOn: function (d) { return '到期日：' + d; }, balanceOf: function (v) { return '余额：' + v; },
      invState: { paid: '已付款', outstanding: '未付款', overdue: '已逾期' }, downloadPdf: '下载PDF'
    }
  });
  var lang = 'en';
  function t() { return T[lang]; }
  var LANG_KEY = 'adspace.portal.lang';
  /* A choice made on this browser (the 中文 switch) wins; until one is made
     the page opens in the signed-in contact's own language (get_portal
     `me.lang`, 2026-11-17), never stored as if it were chosen. */
  var langChosen = false;
  try { var saved = localStorage.getItem(LANG_KEY); if (saved && T[saved]) { lang = saved; langChosen = true; } } catch (e) {}

  function setLang(next, keep) {
    lang = next;
    if (keep) { langChosen = true; try { localStorage.setItem(LANG_KEY, lang); } catch (e) {} }
    document.documentElement.lang = lang === 'zh' ? 'zh' : 'en';
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    if ($('kicker')) $('kicker').textContent = t().kicker;
    $('portalOutWord').textContent = t().signOut;
    $('portalOut').setAttribute('aria-label', t().signOut);  // the word gives way on a phone, as the creator page's does
    $('signGo').textContent = t().sendLink;
    $('signEmailLabel').textContent = t().email;
    $('signCodeLabel').textContent = t().code;
    $('codeGo').textContent = t().signIn;
    $('codeBack').textContent = t().otherEmail;
    if ($('cpTabs')) $('cpTabs').setAttribute('aria-label', t().tabsLabel);
    if ($('cpSide')) $('cpSide').setAttribute('aria-label', t().sideLabel);
    if (feed) build(); else if (shownState) showState.apply(null, shownState);
  }
  if ($('langToggle')) $('langToggle').addEventListener('click', function () { setLang(lang === 'en' ? 'zh' : 'en', true); });

  // ---- Helpers -------------------------------------------------------------
  function msg(id, text, kind) {
    var el = $(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (kind ? ' ' + kind : '');
  }
  /* `named`: a day the reader waits on carries its weekday (js/clock.js). */
  function niceDate(d, named) {
    if (!d) return '';
    /* Days are Malaysia's (js/clock.js), whatever the device's clock. */
    var k = String(d).length > 10 ? ADspaceClock.day(d) : String(d).slice(0, 10);
    return ADspaceClock.date(k, { zh: lang === 'zh', named: named }) || String(d);
  }
  /* The billed rate, term adjustment included, from the same one definition
     the console and the letter read. A client must never be shown a different
     figure from the one on the letter they signed. */
  function rateOf(l) { return MON.rateFor(l.rate, l.tenure, l.term_adjust, l.term_pct); }
  function amountOf(l) { return Number(l.qty || 0) * rateOf(l) * Math.max(1, Number(l.tenure || 1)); }
  function startDay(s) { s = String(s || ''); return s.length === 7 ? s + '-01' : s; }
  /* The term and its start, each held whole. Where the unit already names
     the term ("Per month, 6 month minimum") the months are not said again
     (the client pages audit, PORTAL-9). Answers HTML. */
  function termWord(l) {
    var n = Math.max(1, Number(l.tenure || 1));
    if (n === 1 && !l.start_on) return '';
    var said = n > 1 && new RegExp('(^|\\D)' + n + '[ -]?(month|个月)', 'i').test(String(l.unit || ''));
    var count = n > 1 && !said ? '<span class="nb">' + esc(t().months(n)) + '</span>' : '';
    if (!l.start_on) return count;
    var day = '<span class="nb">' + esc(niceDate(startDay(l.start_on))) + '</span>';
    var from = count ? t().from : t().fromAlone;
    if (count && lang === 'zh') return count + '，自' + day + '起';
    return (count ? count + ' ' : '') + from(day);
  }
  /* A line's unit and its term note are the rate card's English. On the
     中文 page each part is said in Chinese where this map knows it, and a
     part it does not know is left as the team wrote it (2026-10-31, POR-6).
     The stored words never change. */
  var UNIT_ZH = {
    'per month': '每月', 'per campaign': '每个项目', 'per post': '每篇帖子', 'per video': '每个视频',
    'per gif': '每个 GIF', 'per set': '每组', 'per account': '每个账号', 'per asset': '每项素材',
    'per affected asset': '每项受影响的素材', 'per round': '每轮', 'per language': '每种语言',
    'per unit / asset': '每单位／每项素材', 'per shoot': '每次拍摄', 'per scene / shoot': '每个场景／每次拍摄',
    'per trip': '每趟', 'from': '起', 'plus meta subscription': '另加 Meta 订阅费'
  };
  function partZh(p) {
    var k = String(p).trim().toLowerCase(), m;
    if (UNIT_ZH[k]) return UNIT_ZH[k];
    if ((m = /^(\d+)[ -]month minimum$/.exec(k))) return '最少' + m[1] + '个月';
    if ((m = /^up to (\d+) seconds$/.exec(k))) return '最长' + m[1] + '秒';
    if ((m = /^(rmb?) ([\d,.]+) platform fee included$/.exec(k))) return '含 ' + m[1].toUpperCase() + ' ' + m[2] + ' 平台费';
    if ((m = /^(\d+)-month commitment$/.exec(k))) return m[1] + '个月承诺期';
    if ((m = /^([\d.]+)% surcharge$/.exec(k))) return '附加费' + m[1] + '%';
    if ((m = /^([\d.]+)% discount$/.exec(k))) return '折扣' + m[1] + '%';
    return null;
  }
  function unitWord(u) {
    if (lang !== 'zh' || !u) return u || '';
    var out = String(u).split(', ').map(function (p) { return partZh(p) || p; });
    return out.join('，');
  }
  function mkt() { return MON.curOf(feed && feed.client); }
  /* A number as every page writes it (js/namecard.js: +60 19-888 7777). */
  function phoneWord(raw) { return API.phoneWord(raw) || String(raw || ''); }
  function glyph(n) { return window.ADspaceIcons ? window.ADspaceIcons.svg(n) : ''; }
  function money2(n) { return MON.money2(n, mkt()); }
  function chip(word, tone) { return '<span class="chip-state' + (tone ? ' ' + tone : '') + '">' + esc(word) + '</span>'; }
  function table(head) {
    var el = document.createElement('div');
    el.className = 'crm-table';
    if (head) el.innerHTML = head;
    return el;
  }
  /* The one copy of how a list says it has nothing in it, which this page had
     been going around: `.empty` is a bounded card, so a client with no
     services, no letters and no requests read four white slabs down the page
     where the console draws one line inside the surface the list would have
     filled. */
  function empty(box, word) { UI.emptyLine(box, word, '', null); }
  /* A read that failed is said in its card with Try again, in the page's
     language, never an empty or hidden card (2026-11-25). */
  function failIn(box, what, again) {
    var w = t();
    box.innerHTML = '<div class="errline" role="alert"><b>' + esc(w.loadFail.replace('{x}', what)) + '</b>' +
      '<button class="btn btn-sm" type="button" data-a="retry">' + esc(w.tryAgain) + '</button></div>';
    box.querySelector('[data-a="retry"]').addEventListener('click', again);
  }
  /* A line of parts wraps between its parts, never inside one (DESIGN §5):
     each short part is held whole; a long one a person typed (a note, a
     unit) still breaks where it must. Answers HTML. */
  function parts(list) {
    var out = [];
    list.filter(Boolean).forEach(function (x) {
      String(x).split(' · ').forEach(function (p) {
        if (!p) return;
        out.push(p.length <= 32 ? '<span class="nb">' + esc(p) + '</span>' : esc(p));
      });
    });
    return out.join(' · ');
  }
  /* The same parts as plain words, for a place that escapes its own. */
  function parts0(list) { return list.filter(Boolean).join(' · '); }
  /* A row's name led by its section's glyph tile (2026-11-25): the name
     over its facts beside it. `inner` is the name cell's own markup. */
  function led(name, inner) {
    return '<span class="svc-name cp-led"><span class="cx-tile is-sm">' + glyph(name) + '</span><span class="cp-led-words">' + inner + '</span></span>';
  }
  /* A press whose file is being drawn is answered on its button (Doherty;
     the console's js/acts.js): disabled at once, so a second press draws no
     second file, and after 150ms its words give way to the turning ring in
     its own ink, at its own width. Answers the release. */
  function pending(b) {
    if (!b) return function () {};
    b.disabled = true;
    var tm = setTimeout(function () {
      if (!b.disabled || !b.isConnected || b.classList.contains('is-busy')) return;
      b.style.width = b.getBoundingClientRect().width + 'px';
      b.classList.add('is-busy');
      b.setAttribute('aria-busy', 'true');
      b.insertAdjacentHTML('beforeend', '<span class="btn-spin" aria-hidden="true"></span>');
    }, 150);
    return function () {
      clearTimeout(tm);
      b.disabled = false;
      b.classList.remove('is-busy');
      b.removeAttribute('aria-busy');
      b.style.width = '';
      var sp = b.querySelector('.btn-spin');
      if (sp) sp.remove();
    };
  }
  /* A row whose one act is Download carries it in the row, never in a ⋯ of
     one item (DESIGN §5: the commonest act on a row belongs on the row). */
  function dlCell(w) {
    return '<span class="doc-dl"><button class="btn btn-sm" type="button" data-a="download">' + FILE + '<span>' + esc(w.download) + '</span></button></span>';
  }

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
        window.ADspaceMenu.place(btn, menu);
      }
    });
  }
  document.addEventListener('click', function (e) {
    if (e.target.closest('.kmenu, .team-act')) return;
    Array.prototype.forEach.call(document.querySelectorAll('.kmenu'), function (m) { m.hidden = true; });
  });
  window.ADspaceMenu.onScroll(function () {
    Array.prototype.forEach.call(document.querySelectorAll('.team-act .kmenu'), function (m) { m.hidden = true; });
  });
  function menuCell(items) {
    if (!items.length) return '<span class="team-act"></span>';
    return '<span class="team-act">' +
      '<button class="kmenu-btn" data-a="menu" type="button" aria-label="' + esc(t().more) + '" aria-expanded="false">' + DOTS + '</button>' +
      /* Each item carries its group (DESIGN.md §5 Menus and action
         groups); a request of a change is a Send, never red. */
      '<div class="kmenu" data-menu hidden role="menu">' + items.map(function (it) {
        return '<button class="kmenu-item" data-g="' + (it[2] || 3) + '" data-a="' + it[0] + '" type="button" role="menuitem">' + esc(it[1]) + '</button>';
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

  // ---- The tabs ---------------------------------------------------------------
  /* One pane at a time, the way the console's records open theirs (the user,
     2026-09-28, choosing tabs over one long page). The pane rides in the
     address (`?tab=`, Overview left out) and pushes history, so Back steps
     through the tabs and a refresh lands on the one that was open.
     Six tabs at most (2026-11-26, the user: "Ok"; the strip had run to
     ten): each tab holds its parts one under the other, each part a card
     keeping its own address, so `tab=review` opens Content on Content
     Review and every link written before still lands. A part of the
     client's work joins the tab it belongs to, never a seventh. A part is
     drawn once it holds something, a tab once any of its parts is; an
     address naming one not drawn yet opens it as soon as it is. */
  var STRIP = ['overview', 'content', 'reports', 'services', 'meetings', 'account'];
  var TABS = { overview: ['overview'], content: ['review', 'scripts', 'campaigns'], reports: ['reports'],
    services: ['services', 'letters'], meetings: ['meetings', 'feedback'], account: ['account'] };
  /* The card a part is; a part with none is always drawn. */
  var PART_EL = { review: 'crWrap', scripts: 'vsWrap', campaigns: 'cmWrap', reports: 'repWrap',
    letters: 'docWrap', meetings: 'meetWrap', feedback: 'fbWrap' };
  var TAB_OF = {};
  STRIP.forEach(function (g) { TAB_OF[g] = g; TABS[g].forEach(function (k) { TAB_OF[k] = g; }); });
  var pane = 'overview';
  var wantPane = null;
  function paneFromUrl() {
    var p = new URLSearchParams(location.search).get('tab');
    return TAB_OF[p] ? p : 'overview';
  }
  /* The tab a tab's or a part's name stands in. */
  function tabOf(name) { return document.querySelector('#cpTabs .tab[data-pane="' + TAB_OF[name] + '"]'); }
  function partEl(name) { return PART_EL[name] ? $(PART_EL[name]) : null; }
  function partShown(name) { var el = partEl(name); return !PART_EL[name] || !!(el && !el.hidden); }
  function showPane(name, push) {
    if (!TAB_OF[name]) name = 'overview';
    var tab = tabOf(name);
    if (!tab || tab.hidden) { wantPane = name; name = 'overview'; tab = tabOf(name); }
    else if (!partShown(name)) wantPane = name;
    else if (wantPane === name) wantPane = null;
    var g = TAB_OF[name];
    pane = g;
    Array.prototype.forEach.call(document.querySelectorAll('#cpTabs .tab'), function (b) {
      var on = b === tab;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    Array.prototype.forEach.call(document.querySelectorAll('.cp-pane'), function (p) {
      p.hidden = p.getAttribute('data-pane') !== g;
    });
    /* A part named by itself, below its tab's first card drawn, is brought into view. */
    var el = name !== g && partShown(name) ? partEl(name) : null;
    if (el) {
      var first = Array.prototype.filter.call(el.parentNode.children, function (x) { return x.classList.contains('cp-card') && !x.hidden; })[0];
      if (first !== el) requestAnimationFrame(function () { window.ADspaceChrome.underHead(el); });
    }
    var url = new URL(location.href);
    if (name === 'overview') url.searchParams.delete('tab'); else url.searchParams.set('tab', name);
    if (url.href === location.href) return;
    if (push) history.pushState({ tab: name }, '', url.href); else history.replaceState(history.state, '', url.href);
  }
  /* A part drawn late (Reports, Meetings, Content Review) opens if the address asked for it. */
  function tabShown(name, on) {
    var el = partEl(name), tab = tabOf(name), g = TAB_OF[name];
    if (el) el.hidden = !on;
    if (!tab) return;
    tab.hidden = !TABS[g].some(partShown);
    if (on && (wantPane === name || wantPane === g)) showPane(wantPane, false);
    if (tab.hidden && pane === g) showPane('overview', false);
    paintTiles();
  }
  /* A press on a tab is the person's own choice: a part still awaited is let go. */
  Array.prototype.forEach.call(document.querySelectorAll('#cpTabs .tab'), function (b) {
    b.addEventListener('click', function () { wantPane = null; showPane(b.getAttribute('data-pane'), true); });
  });
  /* The strip is a tab list: the arrows move along it, Home and End to its ends. */
  $('cpTabs').addEventListener('keydown', function (e) {
    var tabs = Array.prototype.filter.call(this.querySelectorAll('.tab'), function (b) { return !b.hidden; });
    var i = tabs.indexOf(document.activeElement);
    if (i < 0) return;
    var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
    if (to === null) return;
    e.preventDefault();
    to = (to + tabs.length) % tabs.length;
    tabs[to].focus();
    tabs[to].click();
  });
  /* An Overview card's View all or a tile opens its tab on its part, at the top of the strip. */
  document.addEventListener('click', function (e) {
    var go = e.target.closest && e.target.closest('[data-go]');
    if (!go) return;
    wantPane = null;
    showPane(go.getAttribute('data-go'), true);
    var strip = $('cpTabs');
    window.ADspaceChrome.underHead(strip, true);
  });
  window.addEventListener('popstate', function () { if (feed) showPane(paneFromUrl(), false); });

  // ---- Whole-page states ---------------------------------------------------
  var shownState = null;
  function showState(kind, extra) {
    shownState = [kind, extra];
    $('app').hidden = true;
    $('stateBox').hidden = false;
    $('signForm').hidden = kind !== 'sign';
    $('codeForm').hidden = kind !== 'sent';
    $('codeBack').hidden = kind !== 'sent';
    $('codeGo').disabled = false;
    $('portalOut').hidden = kind === 'sign' || kind === 'sent';
    document.body.classList.add('is-plain');
    var w = t();
    var title = { sign: w.signTitle, sent: w.sentTitle, none: w.noAccess, fail: w.failTitle }[kind];
    var text = { sign: w.signText, sent: w.sentText(extra || ''), none: w.noAccessText, fail: w.failText }[kind];
    $('stateTitle').textContent = title;
    $('stateText').textContent = text;
    $('stateCover').setAttribute('data-glyph', { sign: 'user', sent: 'mail', none: 'block', fail: 'alert' }[kind] || '');
    /* The database's own words never reach a client (audit, 2026-10-03). */
    msg('stateMsg', '');
    if (kind === 'sign') $('signEmail').focus();
    /* A new address clears the code; a repaint (the language) keeps it. */
    if (kind === 'sent') { if (sentTo !== (extra || '')) $('signCode').value = ''; sentTo = extra || ''; $('signCode').focus(); }
  }

  // ---- Sign in ---------------------------------------------------------------
  /* The page never says whether an address has an account (the brief of
     2026-09-26): an address with no access and one with access read the same,
     "if it is registered, a link has been sent", so the page cannot be used
     to learn who the clients are. Only a fault that is worth trying again (a
     rate limit, the network) says so. */
  function noUser(err) {
    var m = String((err && err.message) || err || '');
    return /signup|sign up|not allowed|not found|no user|invalid/i.test(m);
  }

  function otp(email) {
    /* Sign-ups are closed on the project and this page never makes an account
       of its own, so the link is only ever sent to a login that exists. The
       one before it is what puts it there. */
    var opts = { shouldCreateUser: false, emailRedirectTo: location.origin + '/client/' };
    var go = window.ADspaceCaptcha ? window.ADspaceCaptcha.options($('signGo'), opts) : Promise.resolve(opts);
    go.then(function (o) { return db.auth.signInWithOtp({ email: email, options: o }); })
      .then(function (r) {
        $('signGo').disabled = false;
        if (r.error && !noUser(r.error)) { msg('stateMsg', t().signFail, 'err'); return; }
        showState('sent', email);
      }, function () { $('signGo').disabled = false; msg('stateMsg', t().signFail, 'err'); });
  }

  function sendLink() {
    var email = ($('signEmail').value || '').trim().toLowerCase();
    if (!email) { msg('stateMsg', t().emailNeeded, 'err'); $('signEmail').focus(); return; }
    if (!ADspaceWords.emailOk(email)) { msg('stateMsg', t().emailBad, 'err'); $('signEmail').focus(); return; }
    $('signGo').disabled = true;
    /* Granting access is all the team should have to do, so the login is made
       here, on the way in, rather than depending on a call the console made
       days ago and may have lost. portal-login refuses every address that is
       not a live contact with portal access, which is what keeps a page
       anyone can open from minting accounts; it emails nothing, so the client
       gets the ordinary sign-in link and no invitation they did not expect.

       A flat refusal is the one answer we act on. Anything else, including
       the function not being deployed at all, falls through to Supabase:
       better to let the sign-in speak for itself than to lock everybody out
       over a call that was only ever a convenience. */
    API.invokeFn('portal-login', { email: email }).then(function (res) {
      /* An older portal-login still answers `ok: false` for an address it
         refuses; that address is sent nothing and reads like every other. */
      if (res && res.data && res.data.ok === false) {
        $('signGo').disabled = false;
        showState('sent', email);
        return;
      }
      otp(email);
    }, function () { otp(email); });
  }
  $('signGo').addEventListener('click', sendLink);
  $('signForm').addEventListener('submit', sendLink);

  /* The code from the same email signs in here (the user, 2026-09-28: "the
     link is not working very well"). A wrong code for an address with no
     access reads exactly like a wrong code for one that has it. */
  var sentTo = '';
  function signWithCode() {
    var code = String($('signCode').value || '').replace(/\D/g, '');
    if ($('codeGo').disabled) return;
    if (code.length < ADspaceOtp.digits()) { msg('stateMsg', t().codeNeeded, 'err'); $('signCode').focus(); return; }
    var b = $('codeGo');
    b.disabled = true;
    db.auth.verifyOtp({ email: sentTo, token: code, type: 'email' }).then(function (r) {
      var m = String((r && r.error && r.error.message) || '');
      if (r && r.error) b.disabled = false;
      if (r && r.error && /rate limit|too many/i.test(m)) { msg('stateMsg', t().codeWait, 'err'); return; }
      if (r && r.error) { msg('stateMsg', t().codeWrong, 'err'); $('signCode').focus(); return; }
      /* Signed in: the cover steps away while the portal is read, so the
         page's own ring stands in its place and nothing invites a second
         press of a code already spent. Whatever answers next (the portal, or
         a cover) draws over it; a cover lets the button go again. */
      msg('stateMsg', '');
      if (!feed) { $('stateBox').hidden = true; shownState = null; }
    }).catch(function () { b.disabled = false; msg('stateMsg', t().codeFail, 'err'); });
  }
  $('codeGo').addEventListener('click', signWithCode);
  $('signCode').addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); signWithCode(); }
  });
  $('codeBack').addEventListener('click', function () { msg('stateMsg', ''); showState('sign'); });
  $('portalOut').addEventListener('click', function () {
    // The media pass goes with the session (second audit, item 7).
    if (window.ADspaceMedia && window.ADspaceMedia.forget) window.ADspaceMedia.forget();
    /* The files an earlier visit drew go too, so js/documents.js is fetched
       to let them go when this visit has not. */
    need(['documents']).then(function () {
      var D = window.ADspaceDocs;
      return D && D.forgetFiles ? D.forgetFiles() : null;
    }).catch(function () {}).then(function () { return db.auth.signOut(); })
      .then(function () { location.reload(); });
  });

  // ---- Load ------------------------------------------------------------------
  var feed = null;
  var wanted = null;   // the client chosen from the select, when there are several
  var loads = 0;       // each load numbered: an answer for an earlier one is dropped
  /* A section's answer for a company no longer on screen (a switch while it
     was on its way) is dropped, never drawn under another company (audit
     2026-11-15). */
  function stale(c) { return !feed || !feed.client || !c || feed.client.id !== c.id; }
  function load() {
    var mine = ++loads;
    /* SST and the term percentages are settings (js/money.js): read beside the portal. */
    var rates = MON && MON.load ? MON.load() : Promise.resolve();
    /* The media pass (js/media.js, 2026-10-08): a logo or a report file kept
       under content/ opens only with it once CloudFront asks for it. It
       always resolves, a refused or slow pass never holding the page. */
    var media = window.ADspaceMedia && window.ADspaceMedia.pass ? window.ADspaceMedia.pass({}) : Promise.resolve();
    db.rpc('get_portal', { p_client: wanted })
      .then(function (r) { return Promise.all([rates, media]).then(function () { return r; }, function () { return r; }); }).then(function (r) {
      if (mine !== loads) return;
      if (r.error) { showState('fail', r.error.message); return; }
      var d = r.data || {};
      if (d.error === 'no-access' || d.error === 'not-signed-in') { showState('none'); return; }
      if (d.error) { showState('fail', d.error); return; }
      feed = d;
      shownState = null;
      var own = d.me && (d.me.lang === 'zh' ? 'zh' : d.me.lang === 'en' ? 'en' : '');
      if (!langChosen && own && own !== lang) { setLang(own); return; }
      build();
    }).catch(function (e) { showState('fail', (e && e.message) || String(e)); });
  }

  var session = null;
  function gate(s) {
    session = s;
    if (!s) { feed = null; showState('sign'); return; }
    load();
  }
  if (!db) {
    showState('fail');
  } else {
    db.auth.getSession().then(function (r) { gate(r.data.session); });
    db.auth.onAuthStateChange(function (_e, s) {
      // A token refresh is not a change of person; a reload would wipe what is on screen.
      if (s && session && s.user && session.user && s.user.id === session.user.id) { session = s; return; }
      gate(s);
    });
  }

  // ---- Social media reports -------------------------------------------------
  /* The versions the team has confirmed and published, newest month first;
     the section is not drawn until there is one. Download draws the file in
     the browser from the published snapshot, so it is the same file the team
     issued. A database without the reports migration answers with an error,
     which is read as "none". */
  var SMR = window.ADspaceSmReport;   /* set once fetched (paintReports) */
  function monthOf(a, b) {
    var x = String(a).slice(0, 10), y = String(b).slice(0, 10);
    var whole = /-01$/.test(x) && ADspaceClock.addDays(ADspaceClock.addMonths(x, 1) + '-01', -1) === y;
    if (lang === 'zh' && whole) return ADspaceClock.month(x, { zh: true });
    return SMR ? SMR.periodWord(a, b) : String(a) + ' – ' + String(b);
  }
  function paintReports(w, c) {
    var wrap = $('repWrap'), box = $('repBox');
    if (!wrap || !box || !c.id) return;
    db.rpc('portal_reports', { p_client: c.id }).then(function (r) {
      if (stale(c)) return;
      if (refused(r)) { tabShown('reports', false); failCard('ovRep', 'ovRepBox', 'ovRepGo'); return; }
      var list = (!r.error && r.data && r.data.reports) || [];
      /* A report to list fetches js/smreport.js (and js/documents.js) first:
         its words and its Download; a fetch refused draws it as before,
         with no Download. */
      return (list.length ? need(['smreport']).catch(function () {}) : Promise.resolve()).then(function () {
        if (stale(c)) return;
        SMR = window.ADspaceSmReport;
        tabShown('reports', list.length > 0);
        paintLatestReport(w, list[0]);
        if (!list.length) { box.innerHTML = ''; return; }
        setTile('reports', { head: monthOf(list[0].period_start, list[0].period_end), sub: w.published });
        var fc = SMR ? ' is-file' : '';
        var tb = table('<div class="crm-head svc-row doc-row' + fc + '"><span>' + esc(w.report) + '</span><span class="svc-rate">' + esc(w.version) +
          '</span><span>' + esc(w.state) + '</span><span></span></div>');
        list.forEach(function (v) {
          var row = document.createElement('div');
          row.className = 'svc-row doc-row' + fc;
          row.innerHTML =
            /* The report's own name, as its cover and file print it: the first
               kind was stored as Social Media Report (2026-09-27). */
            led('reports', '<b>' + esc(monthOf(v.period_start, v.period_end)) + '</b><small>' +
              parts([SMR && SMR.titleOf ? SMR.titleOf(v) : v.title, niceDate(v.published_at)]) + '</small>') +
            '<span class="svc-rate svc-amt">' + esc('v' + v.version_no) + '</span>' +
            '<span class="svc-state">' + chip(w.published, 'is-ok') + '</span>' +
            (SMR ? dlCell(w) : '<span class="team-act"></span>');
          var dlb = row.querySelector('[data-a="download"]');
          if (dlb) dlb.addEventListener('click', function () { downloadReport(v, null, dlb); });
          tb.appendChild(row);
        });
        box.innerHTML = ''; box.appendChild(tb);
      });
    });
  }
  // ---- The Overview's tiles ------------------------------------------------
  /* Each section at a glance (2026-11-25, the approved boards): a tile a
     tab drawn, its glyph, its name, where it stands and one fact under it,
     the whole tile opening its tab. Each source fills its own tile as its
     read answers; a tab not drawn has no tile. */
  /* Each tile draws its section by the meaning the console's rail draws it
     by (js/icons.js MEANS): one thing, one glyph on every page. */
  var TILES = [['review', 'review'], ['scripts', 'scripts'], ['campaigns', 'campaigns'], ['reports', 'reports'], ['services', 'services'], ['meetings', 'meetings']];
  var tiles = {};
  function setTile(key, v) { tiles[key] = v; paintTiles(); }
  function paintTiles() {
    var box = $('ovTiles');
    if (!box) return;
    var w = t();
    var shown = TILES.filter(function (x) { var b = tabOf(x[0]); return tiles[x[0]] && b && !b.hidden && partShown(x[0]); });
    box.hidden = !shown.length;
    /* Three across, two where four would leave one alone (a phone is two
       across, the last alone taking the row). */
    box.setAttribute('data-n', String(shown.length));
    box.innerHTML = shown.map(function (x) {
      var v = tiles[x[0]];
      return '<button class="cp-tile" type="button" data-go="' + x[0] + '">' +
        '<span class="cp-tile-top"><span class="cx-tile">' + glyph(x[1]) + '</span>' + GO + '</span>' +
        '<span class="cp-tile-label">' + esc(w.tabs[x[0]]) + '</span>' +
        '<b class="cp-tile-head">' + (v.dot ? '<i class="cx-dot is-' + v.dot + '"></i>' : '') + esc(v.head) + '</b>' +
        (v.sub ? '<span class="cp-tile-sub">' + esc(v.sub) + '</span>' : '') + '</button>';
    }).join('');
  }

  /* One piece of work as it stands (2026-11-25): its tile, its name over
     its facts, its state at the right, a track of its parts toned by their
     states with the words under it, a note, and Open at the right edge. */
  var DOT = { 'is-ok': 'ok', 'is-live': 'ok', 'is-warn': 'wait', 'is-danger': 'late', 'is-off': 'off' };
  function progRow(o) {
    var I = window.ADspaceIcons;
    var row = document.createElement('div');
    var bare = !(I && o.tones && o.tones.length) && !o.note;
    var open = '<a class="btn btn-sm cp-open" href="' + esc(o.url) + '">' + esc(t().open) + ' ' + GO + '</a>';
    row.className = 'svc-row cp-work-row cp-prog' + (o.glyph ? '' : ' is-bare');
    row.innerHTML = (o.glyph ? '<span class="cx-tile">' + glyph(o.glyph) + '</span>' : '') +
      '<div class="cp-prog-body"><div class="cp-prog-top"><span class="svc-name"><b>' + esc(o.name) + '</b>' +
        (o.sub ? '<small>' + o.sub + '</small>' : '') + '</span>' +
        (o.state ? '<span class="svc-state">' + o.state + '</span>' : '') + (bare ? open : '') + '</div>' +
      (I && o.tones && o.tones.length ? I.track(o.tones) + (o.note ? I.legend(o.legend) : '') : '') +
      /* The words under the track share Open's line, unless a note takes it;
         a row with neither keeps Open on its title line (2026-11-26). */
      (bare ? '' : '<div class="cp-prog-foot">' + (o.note ? '<span class="cp-prog-note">' + o.note + '</span>' :
        I && o.tones && o.tones.length ? I.legend(o.legend) : '') + open + '</div>') + '</div>';
    return row;
  }
  /* A content set: its approved posts green, those with changes asked and
     those waiting on the client amber, the rest still to come. */
  function setRow(w, x, token, withGlyph) {
    var ap = x.approved || 0, ch = x.changes || 0, wt = x.waiting || 0, n = x.posts || 0;
    var tones = [];
    for (var i = 0; i < n; i++) tones.push(i < ap ? 'ok' : i < ap + ch + wt ? 'wait' : '');
    var st = wt ? chip(w.toReview(wt), 'is-warn') : ch ? chip(w.changesAsked, 'is-warn') :
      n ? chip(w.allApproved, 'is-ok') : chip(w.noPosts, 'is-off');
    return progRow({ glyph: withGlyph ? 'image' : '', name: x.title || '', sub: parts([monthWord(x.period), w.posts(n)]), state: st,
      tones: tones, legend: [{ dot: 'ok', word: w.allApproved, n: ap }, { dot: 'wait', word: w.changesAsked, n: ch }, { dot: 'wait', word: w.toReviewWord, n: wt }],
      url: '/review/?k=' + encodeURIComponent(token) + '#s-' + String(x.id).slice(0, 8) });
  }
  /* A campaign: one part a booked creator, furthest along first, as the
     selection page draws its standing (js/creators.js). */
  var BOOK_ORDER = ['confirmed', 'pending_visit', 'pending_draft', 'changes', 'reviewing', 'scheduled', 'posted', 'completed'];
  function campName(w, m) {
    var nm = (lang === 'zh' && m.title_zh) ? m.title_zh : m.title;
    nm = String(nm == null ? '' : nm).trim();
    return (!nm || nm === '0' || nm === 'null' || nm === 'undefined') ? w.untitled : nm;
  }
  function campStanding(w, m) {
    var booked = (m.booked || []).slice().sort(function (a, b) { return BOOK_ORDER.indexOf(b) - BOOK_ORDER.indexOf(a); });
    var live = booked.filter(function (s) { return s === 'posted' || s === 'completed'; }).length;
    var seeding = m.push_format === 'seeding';
    var counts = [];
    booked.forEach(function (s) {
      var word = w.step[s === 'pending_visit' && seeding ? 'pending_delivery' : s] || s;
      var hit = counts.filter(function (c) { return c.word === word; })[0];
      if (hit) hit.n++; else counts.push({ word: word, n: 1, dot: DOT[window.ADspaceWords.tone(s)] || 'wait' });
    });
    return { booked: booked, live: live, counts: counts,
      tones: booked.map(function (s) { return DOT[window.ADspaceWords.tone(s)] || 'wait'; }),
      shoot: m.next_shoot && !seeding ? m.next_shoot : null };
  }
  function campRow(w, m, withGlyph) {
    var sd = campStanding(w, m);
    return progRow({ glyph: withGlyph ? 'campaigns' : '', name: campName(w, m),
      sub: parts([w.campaign, sd.booked.length ? w.ofPosted(sd.live, sd.booked.length) : '']),
      state: chip(w.campState[m.state] || '', m.state === 'completed' ? 'is-ok' : (m.state === 'open' ? 'is-warn' : 'is-live')),
      tones: sd.tones, legend: sd.counts,
      note: sd.shoot ? glyph('shoot') + esc(w.nextShoot(niceDate(sd.shoot, 'ahead'))) : '',
      url: '/creators/?k=' + encodeURIComponent(m.token) });
  }

  /* The Overview's engagements: Content Review with its latest month's
     sets under it, then each campaign still running, each as it stands. */
  function paintEng(w, sets) {
    var wrap = $('engWrap'), ebox = $('engBox');
    if (!wrap || !ebox) return;
    var camps = (feed.campaigns || []).filter(function (m) { return m.state !== 'completed'; });
    if (!camps.length) camps = (feed.campaigns || []).slice(0, 1);
    var token = feed.review && feed.review.token;
    wrap.hidden = !token && !camps.length;
    var etb = table('');
    if (token) {
      var head = document.createElement('div');
      head.className = 'svc-row cp-eng-row';
      head.innerHTML = '<span class="cx-tile">' + glyph('image') + '</span><span class="svc-name"><b>' + esc(w.review) + '</b></span>' +
        '<a class="btn btn-sm cp-open" href="/review/?k=' + esc(encodeURIComponent(token)) + '">' + esc(w.open) + ' ' + GO + '</a>';
      etb.appendChild(head);
      var last = (sets || []).map(function (x) { return x.period || ''; }).sort().pop();
      (sets || []).filter(function (x) { return (x.period || '') === last; }).forEach(function (x) { etb.appendChild(setRow(w, x, token, false)); });
    }
    camps.forEach(function (m) { etb.appendChild(campRow(w, m, true)); });
    ebox.innerHTML = ''; ebox.appendChild(etb);
  }

  // ---- One sign-in: Content Review, Video Scripts, Creator campaigns -------
  /* What the team shares with the client, a tab each, every row opening its
     own page in this tab, signed in: no access code and no name to type
     (the user, 2026-11-08, approving the portal's release 1). Each tab is
     drawn once it holds something; a refused read leaves the tab out. */
  function monthWord(p) {
    if (!p) return t().noMonth;
    var m = /^(\d{4})-(\d{2})/.exec(p);
    if (!m) return p;
    return lang === 'zh' ? m[1] + '年' + Number(m[2]) + '月' : MON_EN[Number(m[2]) - 1] + ' ' + m[1];
  }
  function paintWork(w, c, feed) {
    var camps = (feed && feed.campaigns) || [];
    var cmBox = $('cmBox');
    tabShown('campaigns', camps.length > 0);
    if (cmBox) {
      cmBox.innerHTML = '';
      if (camps.length) {
        var ctb = table('');
        camps.forEach(function (m) { ctb.appendChild(campRow(w, m, true)); });
        cmBox.appendChild(ctb);
      }
    }
    var cmTile = camps.filter(function (m) { return m.state !== 'completed'; })[0] || camps[0];
    if (cmTile) {
      var cs = campStanding(w, cmTile);
      setTile('campaigns', { head: cs.booked.length ? w.ofPosted(cs.live, cs.booked.length) : campName(w, cmTile),
        sub: w.campState[cmTile.state] || '' });
    }
    paintEng(w, null);
    if (!c.id) return;
    /* A failed read keeps both parts drawn with Try again, never hidden as
       nothing to review (review J8). */
    var workFail = function () {
      if (stale(c)) return;
      tabShown('review', true); tabShown('scripts', true);
      var again = function () { paintWork(w, c, feed); };
      if ($('crBox')) failIn($('crBox'), w.tabs.review, again);
      if ($('vsBox')) failIn($('vsBox'), w.tabs.scripts, again);
    };
    db.rpc('portal_work', { p_client: c.id }).then(function (r) {
      if (stale(c)) return;
      if (refused(r)) { workFail(); return; }
      var d = (!r.error && r.data && !r.data.error) ? r.data : {};
      var rv = d.review, sets = (rv && rv.sets) || [];
      var waiting = sets.reduce(function (n, x) { return n + (x.waiting || 0); }, 0);
      tabShown('review', sets.length > 0);
      var rt = tabOf('content');
      if (rt) rt.innerHTML = esc(w.tabs.content) + (waiting ? ' <span class="tab-n is-err">' + waiting + '</span>' : '');
      var crBox = $('crBox');
      if (crBox) {
        crBox.innerHTML = '';
        if (sets.length) {
          /* A content month a group, its sets under it, newest first. */
          var months = [];
          sets.forEach(function (x) { var k = x.period || ''; if (months.indexOf(k) < 0) months.push(k); });
          months.forEach(function (k) {
            var of = sets.filter(function (x) { return (x.period || '') === k; });
            var mh = document.createElement('div');
            mh.className = 'cp-group-head';
            mh.innerHTML = '<h4>' + esc(monthWord(k)) + '</h4><span class="tab-n">' + of.length + '</span>';
            crBox.appendChild(mh);
            var rtb = table('');
            of.forEach(function (x) { rtb.appendChild(setRow(w, x, rv.token, true)); });
            crBox.appendChild(rtb);
          });
        }
      }
      if (sets.length) {
        var lt = sets[0];
        setTile('review', waiting ? { head: w.toReview(waiting), dot: 'wait', sub: parts0([monthWord(lt.period), w.posts(lt.posts || 0)]) }
          : { head: lt.changes ? w.changesAsked : lt.posts ? w.allApproved : w.noPosts, sub: parts0([monthWord(lt.period), w.posts(lt.posts || 0)]) });
      }
      paintEng(w, sets);
      var sc = d.scripts, list = (sc && sc.list) || [];
      tabShown('scripts', list.length > 0);
      var vsBox = $('vsBox');
      if (vsBox) {
        vsBox.innerHTML = '';
        if (list.length) {
          var stb = table('');
          list.forEach(function (x) {
            stb.appendChild(progRow({ glyph: 'scripts', name: [x.code, x.title].filter(Boolean).join(' · '),
              sub: parts([(w.scriptKind || {})[x.kind] || '', monthWord(x.period)]),
              note: x.shoot_on ? glyph('shoot') + esc(w.shoot(niceDate(x.shoot_on, 'ahead'))) : '',
              url: '/script/?k=' + encodeURIComponent(sc.key) + '#' + encodeURIComponent(x.id) }));
          });
          vsBox.appendChild(stb);
        }
      }
      if (list.length) {
        var today = ADspaceClock.today();
        var next = list.filter(function (x) { return x.shoot_on && String(x.shoot_on).slice(0, 10) >= today; })
          .sort(function (a, b) { return String(a.shoot_on).localeCompare(String(b.shoot_on)); })[0];
        var sx = next || list[0];
        setTile('scripts', { head: next ? w.shoot(niceDate(next.shoot_on, 'ahead')) : [sx.code, sx.title].filter(Boolean).join(' · '),
          sub: (w.scriptKind || {})[sx.kind] || '' });
      }
    }).catch(workFail);
  }

  /* A failed read is never drawn as nothing (js/state.js): a refusal keeps
     the Overview's card with the cover's words, while a database without the
     function (PGRST202) reads as none, as before (the client pages audit,
     PORTAL-7). The client never reads the database's own words. */
  function refused(r) {
    var e = r && r.error;
    if (!e) return !!(r && r.data && r.data.error);   /* the function's own refusal (no-access) */
    return e.code !== 'PGRST202' && !/could not find the function/i.test(e.message || '');
  }
  function failCard(card, box, go) {
    var w = t();
    $(card).hidden = false;
    $(go).hidden = true;   /* its tab is not drawn: nothing to view */
    $(box).innerHTML = '<p class="cp-line"><b>' + esc(w.failTitle) + '</b></p><p class="cp-sub">' + esc(w.failText) + '</p>';
  }
  /* The Overview's latest report: the month, the report's name and date, and
     Download. The card leaves while there is none. */
  function paintLatestReport(w, v) {
    var card = $('ovRep'), box = $('ovRepBox');
    if (!card || !box) return;
    card.hidden = !v;
    $('ovRepGo').hidden = false;
    if (!v) { box.innerHTML = ''; return; }
    box.innerHTML = '<p class="cp-line"><b>' + esc(monthOf(v.period_start, v.period_end)) + '</b></p>' +
      '<p class="cp-sub">' + parts([SMR && SMR.titleOf ? SMR.titleOf(v) : v.title, (lang === 'zh' ? niceDate(v.published_at) + '发布' : w.published + ' ' + niceDate(v.published_at))]) + '</p>' +
      (SMR ? '<div class="cp-card-acts"><button class="btn btn-sm" type="button" data-a="dl">' + FILE + esc(w.download) + '</button></div>' : '');
    var dl = box.querySelector('[data-a="dl"]');
    if (dl) dl.addEventListener('click', function () { downloadReport(v, 'ovRepMsg', dl); });
  }

  // ---- Invoices -------------------------------------------------------------
  /* The client's own invoices (2026-11-25), read from Bukku through
     `bukku-sync` as the signed-in contact: the database answers which
     Bukku contacts are this client's, and nothing else is read. Overdue
     first, then outstanding by its due date, then paid, newest first; the
     card is drawn once one is held, and a failed read says so in the card,
     never an empty list. Download PDF opens Bukku's own copy. */
  var INV_ORDER = { overdue: 0, outstanding: 1, paid: 2 };
  function paintInvoices(w, c) {
    var wrap = $('invWrap'), box = $('invBox');
    if (!wrap || !box || !c.id) return;
    API.invokeFn('bukku-sync', { action: 'portal', client: c.id }).then(function (r) {
      if (stale(c)) return;
      var d = r.data || {};
      /* Bukku not set up, or the contact not linked: nothing to show.
         Any other refusal is a read that failed, said in the card. */
      if (d.error && /not-set-up|needs-update|bad-request|no-access|not-signed-in/.test(String(d.error))) { wrap.hidden = true; return; }
      if (r.error || d.error) { wrap.hidden = false; failIn(box, w.invoices, function () { paintInvoices(w, c); }); return; }
      var list = (d.invoices || []).slice();
      wrap.hidden = !list.length;
      if (!list.length) { box.innerHTML = ''; return; }
      list.sort(function (a, b) {
        var o = INV_ORDER[a.state] - INV_ORDER[b.state];
        if (o) return o;
        return a.state === 'paid' ? String(b.date).localeCompare(String(a.date)) : String(a.due).localeCompare(String(b.due));
      });
      var tb = table('<div class="crm-head svc-row doc-row is-file"><span>' + esc(w.invoice) + '</span><span class="svc-rate">' + esc(w.amount) +
        '</span><span>' + esc(w.state) + '</span><span></span></div>');
      list.forEach(function (v) {
        var cur = v.currency === 'SGD' ? 'SG' : 'MY';
        var part = v.state !== 'paid' && Number(v.balance) < Number(v.amount) ? w.balanceOf(MON.money2(v.balance, cur)) : '';
        var row = document.createElement('div');
        row.className = 'svc-row doc-row is-file';
        row.innerHTML = led('file', '<b>' + esc(v.number) + '</b><small>' +
            parts([niceDate(v.date), v.state === 'paid' ? '' : w.dueOn(niceDate(v.due, v.state === 'overdue' ? '' : 'ahead')), part]) + '</small>') +
          '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(v.amount, cur)) + '</b></span>' +
          '<span class="svc-state">' + chip(w.invState[v.state] || v.state, v.state === 'paid' ? 'is-ok' : v.state === 'overdue' ? 'is-danger' : 'is-warn') + '</span>' +
          '<span class="doc-dl">' + (v.link && window.ADspaceWords.absUrl(v.link) ? '<a class="btn btn-sm" href="' + esc(window.ADspaceWords.absUrl(v.link)) +
            '" target="_blank" rel="noopener"><span>' + esc(w.downloadPdf) + '</span> ' + EXT + '</a>' : '') + '</span>';
        tb.appendChild(row);
      });
      box.innerHTML = ''; box.appendChild(tb);
      msg('invMsg', '');
    }).catch(function () {
      if (stale(c)) return;
      wrap.hidden = false;
      failIn(box, w.invoices, function () { paintInvoices(w, c); });
    });
  }

  // ---- Content meetings -----------------------------------------------------
  /* When we meet about each month's content: the date, the time, how it is
     held, and the link while the meeting is still ahead. Read from
     `portal_meetings`, which sends nothing else about the month; the section
     is not drawn until there is a meeting. */
  /* Every meeting is read in Malaysia's clock (MYT, UTC+8, no summer
     time), whatever the device says, because it is booked in it: a client
     abroad read their own hour and no zone (the client pages refresh,
     2026-10-07). A Date shifted eight hours and read in UTC is that clock. */
  function myt(d) { return new Date(new Date(d).getTime() + 8 * 3600000); }
  /* Chinese reads 下午2:00, never pm (2026-10-20, POR-3). */
  function clock(d) {
    var h = d.getUTCHours(), m = d.getUTCMinutes(), hm = ((h % 12) || 12) + ':' + String(m).padStart(2, '0');
    if (lang === 'zh') return (h < 12 ? '上午' : '下午') + hm;
    return hm + (h < 12 ? 'am' : 'pm');
  }
  var MON_EN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var DAY_EN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  var DAY_ZH = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  function meetSpan(v) {
    var a = myt(v.at), b = new Date(a.getTime() + (Number(v.minutes) || 30) * 60000);
    return lang === 'zh' ? clock(a) + t().to + clock(b) : clock(a) + ' ' + t().to + ' ' + clock(b);
  }
  function meetWhen(v) {
    var a = myt(v.at);
    var day = lang === 'zh'
      ? a.getUTCFullYear() + '年' + (a.getUTCMonth() + 1) + '月' + a.getUTCDate() + '日'
      : DAY_EN[a.getUTCDay()] + ' ' + a.getUTCDate() + ' ' + MON_EN[a.getUTCMonth()] + ' ' + a.getUTCFullYear();
    return day + (lang === 'zh' ? '，' : ', ') + meetSpan(v);
  }
  /* Add to calendar: one event as an .ics file, the time in UTC, the link
     where it has one. Made in the page; nothing is sent anywhere. */
  function icsOf(v, title) {
    var z = function (d) { return new Date(d).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, ''); };
    var a = new Date(v.at), b = new Date(a.getTime() + (Number(v.minutes) || 30) * 60000);
    var clean = function (x) { return String(x || '').replace(/[\\;,]/g, function (m) { return '\\' + m; }).replace(/\n/g, ' '); };
    var lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//ADspace//Client Portal//EN', 'BEGIN:VEVENT',
      'UID:' + (v.id || z(a)) + '@digital.adspace.me', 'DTSTAMP:' + z(Date.now()), 'DTSTART:' + z(a), 'DTEND:' + z(b),
      'SUMMARY:' + clean(title)];
    if (v.link) { lines.push('URL:' + v.link); lines.push('LOCATION:' + clean(v.link)); }
    lines.push('END:VEVENT', 'END:VCALENDAR');
    return 'data:text/calendar;charset=utf-8,' + encodeURIComponent(lines.join('\r\n'));
  }
  function meetAgenda(w, per, kind) {
    /* A meeting booked outside a month is simply a meeting. */
    if (kind === 'meeting') return w.meeting;
    var m = /^(\d{4})-(\d{2})$/.exec(per || '');
    if (!m) return w.discussionAlone || w.discussion;
    if (lang === 'zh') return m[1] + '年' + Number(m[2]) + '月' + w.discussion;
    return ADspaceClock.month(m[1] + '-' + m[2]) + ' ' + w.discussion;
  }
  function paintMeetings(w, c) {
    var wrap = $('meetWrap'), box = $('meetBox');
    if (!wrap || !box || !c.id) return;
    db.rpc('portal_meetings', { p_client: c.id }).then(function (r) {
      if (stale(c)) return;
      if (refused(r)) { tabShown('meetings', false); failCard('ovMeet', 'ovMeetBox', 'ovMeetGo'); return; }
      var list = (!r.error && r.data && r.data.meetings) || [];
      tabShown('meetings', list.length > 0);
      paintNextMeeting(w, list);
      if (!list.length) { box.innerHTML = ''; return; }
      var soon = list.filter(function (v) { return new Date(v.at).getTime() + (Number(v.minutes) || 30) * 60000 > Date.now(); })
        .sort(function (a, b) { return new Date(a.at) - new Date(b.at); })[0];
      var past = list.slice().sort(function (a, b) { return new Date(b.at) - new Date(a.at); })[0];
      setTile('meetings', soon ? { head: niceDate(soon.at, 'ahead'), sub: w.upcoming } : { head: niceDate(past.at), sub: w.held });
      var tb = table('<div class="crm-head svc-row doc-row meet-row"><span>' + esc(w.meeting) + '</span><span class="svc-rate">' + esc(w.when) +
        '</span><span>' + esc(w.state) + '</span><span></span></div>');
      var now = Date.now();
      var endOf = function (v) { return new Date(v.at).getTime() + (Number(v.minutes) || 30) * 60000; };
      /* By when it takes place, never by when it was recorded (2026-11-03):
         what is ahead first, the soonest at the top, then what was held,
         the latest first. */
      list = list.slice().sort(function (a, b) {
        var ea = endOf(a), eb = endOf(b), fa = ea > now, fb = eb > now;
        if (fa !== fb) return fa ? -1 : 1;
        return fa ? ea - eb : eb - ea;
      });
      list.forEach(function (v) {
        var ahead = endOf(v) > now;
        var row = document.createElement('div');
        row.className = 'svc-row doc-row meet-row';
        /* Join is the row's own act while the meeting is ahead, as the
           Overview draws it (2026-10-20, POR-2). */
        var join = ahead && v.link;
        row.innerHTML =
          led('meetings', '<b>' + esc(meetAgenda(w, v.period, v.kind)) + '</b><small>' + esc((w.channel[v.channel] || w.channel.other)) + '</small>') +
          '<span class="svc-rate svc-amt">' + esc(meetWhen(v)) + '</span>' +
          '<span class="svc-state">' + (ahead ? chip(w.upcoming, 'is-warn') : chip(w.held, 'is-ok')) + '</span>' +
          '<span class="team-act">' + (join ? '<a class="btn btn-sm" href="' + esc(v.link) + '" target="_blank" rel="noopener">' + esc(w.join) + ' ' + EXT + '</a>' : '') + '</span>';
        tb.appendChild(row);
      });
      box.innerHTML = ''; box.appendChild(tb);
    });
  }

  /* Client feedback (CLIENT FEEDBACK, 2026-11-24): a request the agency sent
     is the Overview's first card until it is answered, the lead question on
     it and the rest of the form under it once a score is chosen; the
     Feedback tab holds past answers, read only, once there is one. The
     answer goes as the signed-in contact (`feedback_submit`). */
  var fbState = { key: null, answers: {}, sending: false };
  function fbFill(s, v) { return String(s).replace(/\{(\w+)\}/g, function (m, k) { return v[k] == null ? m : v[k]; }); }
  function paintFeedback(w, c) {
    var card = $('ovFb'), box = $('ovFbBox'), hbox = $('fbBox'), F = window.ADspaceFeedback;
    if (!card || !box || !hbox || !c.id || !F) return;
    db.rpc('portal_feedback', { p_client: c.id }).then(function (r) {
      if (stale(c)) return;
      if (r.error || !r.data || r.data.error) { fbFailed(w, c); return; }
      var d = r.data, open = d.open, hist = d.history || [];
      $('ovFbHead').textContent = w.rateTitle;
      tabShown('feedback', hist.length > 0);
      card.hidden = !open;
      if (open) {
        if (fbState.key !== open.key) fbState = { key: open.key, answers: {}, sending: false };
        var lead = open.questions.filter(function (q) { return q.lead; })[0];
        var picked = lead && fbState.answers[lead.key] != null;
        box.innerHTML = '<p class="cp-sub fb-ask-meta">' + parts([F.title(open.kind, lang), fbFill(w.fbRequested, { d: niceDate(open.requested_at) })]) + '</p>' +
          '<form class="fb-form" id="ovFbForm" novalidate data-lang="' + lang + '">' +
          F.form(picked ? open.questions : [lead], lang, fbState.answers) + '</form>' +
          '<p class="msg" id="ovFbMsg" role="status"></p>' +
          (picked ? '<div class="cp-card-acts fb-ask-acts"><button class="btn btn-primary" type="button" id="ovFbSubmit">' + esc(w.fbSubmit) + '</button></div>' : '');
        /* The first score chosen brings the rest of the form under it. */
        F.wire($('ovFbForm'), picked ? open.questions : [lead], fbState.answers, function (k) {
          if (!picked && lead && k === lead.key) paintFeedback(w, c);
        }, lang);
        var sb = $('ovFbSubmit');
        if (sb) sb.addEventListener('click', function () { submitFeedback(w, c, open, sb); });
      } else box.innerHTML = '';
      hbox.innerHTML = hist.length ? '<div class="fbh-list">' + hist.map(function (h) {
        var when = niceDate(h.submitted_at);
        return '<details class="fbh"><summary class="fbh-row"><span class="cx-tile is-sm">' + glyph('feedback') + '</span><span class="fbh-name"><b>' + esc(F.title(h.kind, lang)) + '</b><small>' +
          esc(h.by ? fbFill(w.fbBy, { d: when, n: h.by }) : fbFill(w.fbOn, { d: when })) + '</small></span>' +
          '<span class="fbh-score">' + esc(fbFill(w.fbScore, { v: h.score, m: h.max })) + '</span>' +
          window.ADspaceIcons.glyph('chevron', 'fbh-chev') + '</summary>' +
          '<div class="fbread">' + (h.answers || []).map(function (a) {
            var q = '<p class="fbread-q">' + esc(lang === 'zh' ? a.zh : a.en) + '</p>';
            if (a.type === 'scale') {
              var end = Number(a.value) === a.max ? (lang === 'zh' ? a.high_zh : a.high_en) : '';
              return '<div>' + q + '<p class="fbread-a"><b>' + esc(a.value) + '</b><span>' + esc(lang === 'zh' ? '/' + a.max : 'of ' + a.max) +
                (end ? ' · ' + esc(end) : '') + '</span></p></div>';
            }
            return '<div>' + q + '<p class="fbread-t">' + esc(a.value) + '</p></div>';
          }).join('') + '</div></details>';
      }).join('') + '</div>' : '';
    }).catch(function () { if (!stale(c)) fbFailed(w, c); });
  }
  /* A failed read may hide a request waiting on the client, so the card
     stands under the tab's name with Try again (2026-11-25). */
  function fbFailed(w, c) {
    var card = $('ovFb'), box = $('ovFbBox');
    if (!card || !box) return;
    $('ovFbHead').textContent = w.tabs.feedback;
    card.hidden = false;
    failIn(box, w.tabs.feedback, function () { paintFeedback(w, c); });
  }
  function submitFeedback(w, c, open, btn) {
    var F = window.ADspaceFeedback, form = $('ovFbForm');
    if (fbState.sending || !form) return;
    if (F.check(form, open.questions, fbState.answers, lang)) return;
    fbState.sending = true; btn.disabled = true; msg('ovFbMsg', '');
    db.rpc('feedback_submit', { p_key: open.key, p_answers: F.payload(open.questions, fbState.answers) }).then(function (r) {
      var d = r.data || {};
      if (r.error) throw r.error;
      if (d.error && d.error !== 'answered' && d.error !== 'closed') throw new Error(d.error);
      fbState = { key: null, answers: {}, sending: false };
      paintFeedback(w, c);
    }).catch(function () {
      fbState.sending = false; btn.disabled = false; msg('ovFbMsg', w.notSent, 'err');
    });
  }

  /* The Overview's next meeting: the soonest one still ahead, with Join where
     it has a link. The card leaves while none is ahead. */
  function paintNextMeeting(w, list) {
    var card = $('ovMeet'), box = $('ovMeetBox');
    if (!card || !box) return;
    var now = Date.now();
    var ahead = (list || []).filter(function (v) { return new Date(v.at).getTime() + (Number(v.minutes) || 30) * 60000 > now; })
      .sort(function (a, b) { return new Date(a.at) - new Date(b.at); });
    var v = ahead[0];
    card.hidden = !v;
    $('ovMeetGo').hidden = false;
    if (!v) { box.innerHTML = ''; return; }
    /* A date as a calendar leaf, the hour in MYT beside it, Join and Add to
       calendar under them. */
    var a = myt(v.at), agenda = meetAgenda(w, v.period, v.kind);
    var I = window.ADspaceIcons, ic = function (n) { return I ? I.svg(n) : ''; };
    box.innerHTML = '<div class="cx-meet">' +
        '<div class="cx-leaf" aria-hidden="true"><span>' + esc(lang === 'zh' ? (a.getUTCMonth() + 1) + '月' : MON_EN[a.getUTCMonth()]) + '</span>' +
          '<b>' + a.getUTCDate() + '</b><span>' + esc((lang === 'zh' ? DAY_ZH : DAY_EN)[a.getUTCDay()]) + '</span></div>' +
        '<div class="cx-meet-who"><p class="cp-line"><b>' + esc(meetSpan(v)) + ' MYT</b></p>' +
          '<p class="cp-sub cx-sr">' + esc(meetWhen(v)) + '</p>' +
          '<p class="cp-sub">' + esc(agenda) + '</p>' +
          '<p class="cp-sub cx-chan">' + ic('video') + esc(w.channel[v.channel] || w.channel.other) + '</p></div>' +
      '</div>' +
      '<div class="cp-card-acts cx-pair">' +
        (v.link ? '<a class="btn btn-sm" href="' + esc(v.link) + '" target="_blank" rel="noopener">' + esc(w.join) + ' ' + EXT + '</a>' : '') +
        '<a class="btn btn-sm" href="' + icsOf(v, agenda) + '" download="meeting.ics">' + ic('calplus') + esc(w.addCal) + '</a>' +
      '</div>';
  }

  /* The failure is said under whichever control asked: the Reports tab's
     table, or the Overview's latest report. */
  function downloadReport(v, where, btn) {
    where = where || 'repMsg';
    if (btn && btn.disabled) return;
    var done = pending(btn);
    var tab = window.ADspaceDocs.tabFor();
    msg(where, '', '');
    db.rpc('portal_report', { p_version: v.id }).then(function (r) {
      var snap = r.data && r.data.snapshot;
      if (r.error || !snap) throw new Error((r.error && r.error.message) || 'not-found');
      var drawn = function () {
        return SMR.render(snap).then(function (out) { return new Blob([out.bytes], { type: 'application/pdf' }); });
      };
      /* The file kept as it went out (2026-10-07), through sign-download as
         this contact; drawn from the version's own snapshot where none is
         kept or it does not open. */
      var get = r.data.kept
        ? db.functions.invoke('sign-download', { body: { reportVersion: v.id } }).then(function (x) {
            var b = x && x.data;
            if (x.error || !b || typeof b.size !== 'number' || !b.size) throw new Error('kept-unread');
            return b.type === 'application/pdf' ? b : new Blob([b], { type: 'application/pdf' });
          }).catch(drawn)
        : drawn();
      return get.then(function (blob) {
        return window.ADspaceDocs.save(blob, SMR.fileName(snap), tab, lang === 'zh');
      });
    }).then(done).catch(function () {
      done();
      window.ADspaceDocs.shut(tab);
      msg(where, lang === 'zh' ? '无法下载报告，请刷新页面后重试。' : 'The report could not be downloaded. Please refresh the page and try again.', 'err');
    });
  }

  /* Where each confirmed line is in its term: the month it is in, of how
     many, and when it ends, from its start and its months, both held. A line
     not started, or of one month, says nothing. */
  function termsHtml(list, w) {
    var now = myt(Date.now());
    var rows = list.map(function (l) {
      var n = Math.max(1, Number(l.tenure || 1));
      if (n < 2 || !l.start_on) return '';
      var st = new Date(startDay(l.start_on) + 'T00:00:00Z');
      var at = (now.getUTCFullYear() - st.getUTCFullYear()) * 12 + (now.getUTCMonth() - st.getUTCMonth()) + 1;
      if (now.getUTCDate() < st.getUTCDate()) at -= 1;
      if (at < 1 || at > n) return '';
      var end = new Date(Date.UTC(st.getUTCFullYear(), st.getUTCMonth() + n, st.getUTCDate() - 1));
      var endWord = lang === 'zh' ? end.getUTCFullYear() + '年' + (end.getUTCMonth() + 1) + '月'
        : MON_EN[end.getUTCMonth()] + ' ' + end.getUTCFullYear();
      /* The line, where it is in its term under it, then the bar: a line
         reads over its own sub-line, as every card's name does (2026-10-31,
         POR-10: the bar between them stood the two 20px apart). */
      /* A month a part, those begun green (2026-11-25, the approved boards). */
      var tones = [];
      for (var i = 0; i < n; i++) tones.push(i < at ? 'ok' : '');
      return '<div class="cx-term"><span class="cx-tile is-sm">' + glyph('services') + '</span><div class="cx-term-words"><p class="cp-line"><b>' + esc(l.label) + '</b></p>' +
        '<p class="cp-sub">' + parts([w.monthOf(at, n), w.endsOn(endWord)]) + '</p>' +
        (window.ADspaceIcons ? window.ADspaceIcons.track(tones, w.monthOf(at, n)) : '') + '</div></div>';
    }).join('');
    return rows ? '<div class="cx-terms">' + rows + '</div>' : '';
  }

  // ---- Build ---------------------------------------------------------------
  function build() {
    var w = t();
    var c = feed.client || {};
    tiles = {};
    document.body.classList.remove('is-plain');
    $('stateBox').hidden = true;
    $('app').hidden = false;
    $('portalOut').hidden = false;
    if (window.ADspaceGuide) window.ADspaceGuide.offer('client', GUIDE);
    if ($('kicker')) $('kicker').textContent = w.kicker;
    if ($('langToggle')) $('langToggle').textContent = w.lang;
    if (window.ADspaceChrome) window.ADspaceChrome.preparedFor('', '');

    ['ovHead:company', 'ctHead:contacts', 'invHead:invoices', 'svcHead:services', 'ovSvcHead:services', 'rqHead:requests',
     'docHead:letters', 'meetHead:meetings', 'repHead:reports', 'engHead:engagements',
     'payHead:payment', 'accHead:account', 'ovMeetHead:nextMeeting', 'ovRepHead:latestReport',
     'ovFbHead:rateTitle'].forEach(function (p) {
      var a = p.split(':'); $(a[0]).textContent = w[a[1]];
    });
    /* An Overview card's way to its tab: the console Overview's own control. */
    Array.prototype.forEach.call(document.querySelectorAll('.cp-card .ovgo-word'), function (x) { x.textContent = w.viewAll; });
    STRIP.forEach(function (k) { var b = tabOf(k); if (b) b.textContent = w.tabs[k]; });
    ['crHead:review', 'vsHead:scripts', 'cmHead:campaigns', 'fbHead:feedback'].forEach(function (p) {
      var a = p.split(':'); if ($(a[0])) $(a[0]).textContent = w.tabs[a[1]];
    });
    if (!feed.__shown) { feed.__shown = true; showPane(paneFromUrl(), false); }
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
    var stTone = window.ADspaceWords.tone(c.stage) || 'is-off';
    var mute = function (s) { return '<span class="muted">' + esc(s) + '</span>'; };

    /* Who this page is for. A client signed in and read a table of their own
       line items with their company name nowhere on it; the mark is their own
       logo where we hold one and their initials where we do not, exactly as
       both console records draw it. */
    var mark = $('cpMark');
    if (mark) {
      if (c.logo_url) {
        mark.className = 'rec-mark has-logo';
        mark.innerHTML = '<img src="' + esc(c.logo_url) + '" alt="">';
      } else {
        mark.className = 'rec-mark';
        mark.textContent = UI.initials(c.name || c.legal_name);
      }
    }
    if ($('cpName')) $('cpName').textContent = c.name || c.legal_name || '';
    if ($('cpState')) {
      $('cpState').textContent = st;
      $('cpState').className = 'tone ' + stTone;
      $('cpState').hidden = !st;
    }
    if ($('cpMeta')) {
      /* The facts that identify rather than describe, each left out when we do
         not hold it. The rest of them are in the rail, under the heading that
         names them, so nothing is printed twice. */
      var bits = [];
      if (c.legal_name && c.legal_name !== c.name) bits.push(esc(c.legal_name));
      $('cpMeta').innerHTML = bits.join(' &middot; ');
      $('cpMeta').hidden = !bits.length;
    }
    /* Who looks after them, and the two ways to reach the team: the account
       managers' shared address and the company's WhatsApp. */
    var mgr = $('ovMgr');
    if (mgr) {
      /* The Person in charge alone, never a stand-in (CLIENT REPRESENTATIVE,
         2026-11-27): with nobody assigned, the company and its two ways to
         reach the team, under Contact {agency}. */
      mgr.hidden = false;
      $('ovMgrHead').textContent = c.owner ? w.yourManager : w.contactUs;
      $('ovMgrBox').innerHTML = (c.owner ? '<div class="cp-who"><span class="cx-tile is-round">' + glyph('user') + '</span><span class="cp-led-words"><b class="cp-person">' + esc(c.owner) + '</b><small>' + esc(w.manager) + '</small></span></div>' : '') + '<div class="cp-reach">' +
        (ORG.phone ? '<a class="plink" href="https://wa.me/' + esc(String(ORG.phone).replace(/[^0-9]/g, '')) + '" target="_blank" rel="noopener">' + glyph('whatsapp') + esc(w.whatsapp) + '</a>' : '') +
        (CFG.accountEmail ? '<a class="plink" href="mailto:' + esc(CFG.accountEmail) + '">' + glyph('mail') + esc(w.email) + '</a>' : '') + '</div>';
    }
    /* The registered name, the account manager and the status are on the
       identity line above, so the rail carries what is left rather than
       repeating three facts a reader has just read. */
    $('ovFacts').innerHTML = [
      [w.regNo, c.company_no ? esc(c.company_no) : mute(w.notSet)],
      [w.address, c.billing_address ? esc(c.billing_address) : mute(w.notSet)],
      [w.market, esc((c.market === 'SG' ? w.sg : w.my) + ' · ' + MON.sign(MON.curOf(c)))]
    ].map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + f[1] + '</dd></div>'; }).join('');

    // Contacts, read only: who, how to reach them.
    var cbox = $('ovContacts');
    var contacts = feed.contacts || [];
    if (!contacts.length) empty(cbox, w.noContacts);
    else {
      var ct = table('<div class="crm-head svc-row ct-row"><span>' + esc(w.contact) + '</span><span>' + esc(w.reach) + '</span><span></span></div>');
      contacts.forEach(function (k) {
        var row = document.createElement('div');
        row.className = 'svc-row ct-row is-read';
        var wa = window.ADspaceAPI.waNumber(k.phone);
        row.innerHTML =
          /* The name with Main contact at the right of its line, as every card
             puts its chip; the role under it. Who signs in is the Portal
             access card's to say, so it is not said again here (2026-09-28). */
          '<span class="svc-name"><span class="ct-top"><b>' + esc(k.name) + '</b>' +
            (k.is_primary ? '<span class="tone">' + esc(w.mainContact) + '</span>' : '') + '</span>' +
            (k.role ? '<small>' + esc(k.role) + '</small>' : '') + '</span>' +
          '<span class="crm-reach">' +
            /* Each chip with its glyph, as the account manager's are. */
            (k.phone ? '<a class="plink" href="tel:' + esc(k.phone) + '">' + glyph('phone') + esc(phoneWord(k.phone)) + '</a>' : '') +
            (wa ? '<a class="plink" href="https://wa.me/' + esc(wa) + '" target="_blank" rel="noopener">' + glyph('whatsapp') + esc(w.whatsapp) + '</a>' : '') +
            (k.email ? '<a class="plink" href="mailto:' + esc(k.email) + '">' + glyph('mail') + esc(k.email) + '</a>' : '') +
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
      lines.filter(function (l) { return l.state === 'confirmed'; }).concat(lines.filter(function (l) { return l.state !== 'confirmed'; })).forEach(function (l) {
        var row = document.createElement('div');
        row.className = 'svc-row csv-row';
        var sub = [parts([unitWord(l.unit), unitWord(MON.termNote(l.tenure, l.term_adjust, l.term_pct))]), termWord(l), l.note ? esc(l.note) : '']
          .filter(Boolean).join(' · ');
        var items = l.state === 'confirmed' ? [['upgrade', w.upgrade], ['downgrade', w.downgrade], ['cancel', w.cancel]] : [];
        row.innerHTML =
          led('services', '<b>' + parts([l.label]) + '</b>' + (sub ? '<small>' + sub + '</small>' : '')) +
          /* One phrase that never breaks, "1 × RM 2,830.00 × 6 months", in a
             track wide enough for it at a desk (2026-10-31, POR-4: the
             months on a line of their own made a phone's row five lines). */
          '<span class="svc-rate svc-calc">' + esc(Number(l.qty) + ' × ' + money2(rateOf(l)) +
            (Number(l.tenure || 1) > 1 ? ' × ' + w.months(Number(l.tenure)) : '')) + '</span>' +
          '<span class="svc-rate svc-amt"><b>' + esc(money2(amountOf(l))) + '</b></span>' +
          '<span class="svc-state">' + chip(w.svState[l.state] || l.state, l.state === 'confirmed' ? 'is-ok' : 'is-warn') + '</span>' +
          menuCell(items);
        wireMenu(row);
        items.forEach(function (it) {
          row.querySelector('[data-a="' + it[0] + '"]').addEventListener('click', function () { openRequest(it[0], l); });
        });
        stb.appendChild(row);
      });
      var of = function (s) { return lines.filter(function (l) { return l.state === s; }); };
      var sum = function (s) { return of(s).reduce(function (a, l) { return a + amountOf(l); }, 0); };
      /* A state's total is drawn only over two lines or more: over one it
         repeats that line's amount (2026-10-31, POR-3). Confirmed first, as
         the Overview reads them. */
      var cells = [['confirmed', w.confirmedTotal], ['quoted', w.quotedTotal]].filter(function (x) { return of(x[0]).length > 1; })
        .map(function (x) { return '<span>' + esc(x[1]) + '<b>' + esc(money2(sum(x[0]))) + '</b></span>'; });
      if (cells.length) {
        var tot = document.createElement('div');
        tot.className = 'csv-total';
        tot.innerHTML = cells.join('');
        stb.appendChild(tot);
      }
      sbox.innerHTML = ''; sbox.appendChild(stb);
    }
    /* The Overview's services: what is confirmed, what is still to quote, and
       any request the team has not closed. */
    var obox = $('ovSvcBox');
    if (!lines.length) empty(obox, w.noServices);
    else {
      var tally = function (s) { return lines.filter(function (l) { return l.state === s; }); };
      var q = tally('quoted'), cf = tally('confirmed');
      var money = function (list) { return money2(list.reduce(function (a, l) { return a + amountOf(l); }, 0)); };
      var open = (feed.requests || []).filter(function (r) { return !r.withdrawn_at && (r.state === 'requested' || r.state === 'reviewing'); }).length;
      obox.innerHTML = '<dl class="cp-lines">' +
        '<div class="is-total"><dt>' + parts([w.confirmedTotal, w.lines(cf.length)]) + '</dt><dd>' + esc(money(cf)) + '</dd></div>' +
        (q.length ? '<div><dt>' + parts([w.quotedTotal, w.lines(q.length)]) + '</dt><dd>' + esc(money(q)) + '</dd></div>' : '') +
        (open ? '<div><dt>' + esc(w.openRequests) + '</dt><dd>' + open + '</dd></div>' : '') + '</dl>' + termsHtml(cf, w);
      setTile('services', cf.length ? { head: w.lines(cf.length), sub: w.confirmedTotal } : { head: w.lines(q.length), sub: w.quotedTotal });
    }

    // Requests, once there is one.
    var reqs = feed.requests || [];
    $('rqWrap').hidden = !reqs.length;
    var rbox = $('rqBox');
    if (reqs.length) {
      var rtb = table('<div class="crm-head svc-row doc-row rq-row"><span>' + esc(w.request) + '</span><span class="svc-rate">' + esc(w.fee) +
        '</span><span>' + esc(w.state) + '</span><span></span></div>');
      reqs.forEach(function (r) {
        var row = document.createElement('div');
        var gone = Boolean(r.withdrawn_at);
        row.className = 'svc-row doc-row rq-row' + (gone ? ' is-off' : '');
        var tone = gone ? '' : (r.state === 'approved' || r.state === 'applied') ? 'is-ok' : (r.state === 'declined') ? '' : 'is-warn';
        /* Its reference first (ONE REQUEST REFERENCE, 2026-11-26), kept after Withdraw. */
        var sub = [r.request_ref ? '<span class="nb">' + esc(r.request_ref) + '</span>' : '', r.created_at ? '<span class="nb">' + esc(niceDate(r.created_at)) + '</span>' : '', r.note ? esc(r.note) : '']
          .filter(Boolean).join(' · ');
        /* A request still Requested is withdrawn from its row, a tonal
           button, Undo as before (MENU-19, 2026-10-22). */
        var canWithdraw = !gone && r.state === 'requested';
        row.innerHTML =
          led('requests', '<b>' + parts([w[r.kind] || r.kind, r.service_label]) + '</b>' +
            (sub ? '<small>' + sub + '</small>' : '') +
            (r.reply ? '<small>' + esc(w.reply + (lang === 'zh' ? '：' : ': ') + r.reply) + '</small>' : '')) +
          /* No fee is a mute dash at a desk under its head, nothing on a
             phone, where the head is hidden (2026-10-20, POR-1). */
          '<span class="svc-rate svc-amt' + (r.fee != null && r.fee !== '' ? '' : ' is-none') + '">' + (r.fee != null && r.fee !== '' ? '<b>' + esc(money2(r.fee)) + '</b>' : '<span class="muted">\u2014</span>') + '</span>' +
          '<span class="svc-state">' + chip(gone ? w.withdrawn : (w.rqState[r.state] || r.state), tone) + '</span>' +
          '<span class="team-act">' + (canWithdraw ? '<button class="btn btn-sm" data-a="withdraw" type="button">' + esc(w.withdraw) + '</button>' : '') + '</span>';
        if (canWithdraw) row.querySelector('[data-a="withdraw"]').addEventListener('click', function () { withdraw(r); });
        rtb.appendChild(row);
      });
      rbox.innerHTML = ''; rbox.appendChild(rtb);
    } else rbox.innerHTML = '';

    // Letters
    var dbox = $('docBox');
    var docs = feed.documents || [];
    if (!docs.length) empty(dbox, w.noLetters);
    else {
      /* js/documents.js is fetched now, so it is here by the press (a tab
         an iPhone opens at the press stays the press's). */
      need(['documents']).catch(function () {});
      var dc = ' is-file';
      var dtb = table('<div class="crm-head svc-row doc-row' + dc + '"><span>' + esc(w.document) + '</span><span class="svc-rate">' + esc(w.total) +
        '</span><span>' + esc(w.state) + '</span><span></span></div>');
      docs.forEach(function (d) {
        var row = document.createElement('div');
        row.className = 'svc-row doc-row' + dc;
        row.innerHTML =
          led('mail', '<b>' + esc(d.number) + '</b><small>' + parts([w.offer, niceDate(d.issued_at)]) + '</small>') +
          '<span class="svc-rate svc-amt"><b>' + esc(MON.money2(d.total, d.market)) + '</b></span>' +
          '<span class="svc-state">' + chip(w.issued, 'is-ok') + '</span>' +
          dlCell(w);
        var dlb = row.querySelector('[data-a="download"]');
        if (dlb) dlb.addEventListener('click', function () {
          if (dlb.disabled) return;
          var done = pending(dlb);
          window.ADspaceChrome.needThen(['documents'], false, function () {
            window.ADspaceDocs.download(d, function (warn) { done(); msg('docMsg', warn || '', warn ? 'err' : ''); });
          }).catch(function () { done(); msg('docMsg', window.ADspaceWords.line.pdfLib, 'err'); });
        });
        dtb.appendChild(row);
      });
      dbox.innerHTML = ''; dbox.appendChild(dtb);
    }

    paintMeetings(w, c);
    paintInvoices(w, c);
    paintFeedback(w, c);
    paintReports(w, c);
    paintWork(w, c, feed);

    // Payment guidance, only once the bank line is set.
    $('payWrap').hidden = !ORG.bank;
    if (ORG.bank) {
      $('payFacts').innerHTML = [[w.bank, ORG.bank], [w.reference, c.legal_name || c.name || '']]
        .map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('');
    }

    /* Who can sign in, named for that. Headed "Account" it read as the
       viewer's own settings and left them wondering why it was on the page;
       the heading and the column are what say the section is about their
       colleagues' access, so no line underneath has to explain it. */
    var abox = $('accBox');
    var acc = feed.access || [];
    if (!acc.length) empty(abox, w.noAccessRows);
    else {
      var atb = table('<div class="crm-head svc-row ct-row"><span>' + esc(w.person) + '</span><span>' + esc(w.signInEmail) + '</span><span></span></div>');
      acc.forEach(function (a) {
        var row = document.createElement('div');
        row.className = 'svc-row ct-row';
        /* The address is what somebody signs in with, so it is read and not
           written to: a mailto drawn as this portal's outlined link chip
           offered to open a mail client, which is not what this section is
           for, and put a bordered pill in a table cell beside plain text. */
        row.innerHTML = '<span class="svc-name"><b>' + esc(a.name) + '</b></span>' +
          '<span class="crm-reach"><span class="acc-email">' + esc(a.email) + '</span></span>' +
          '<span class="team-act"></span>';
        atb.appendChild(row);
      });
      abox.innerHTML = ''; abox.appendChild(atb);
    }
  }

  $('clientPick').addEventListener('change', function () { wanted = this.value; load(); });

  // ---- Requests ------------------------------------------------------------
  var req = null;   // { kind, line }
  /* From a line's ⋯ the request is that line's; from the head's Request
     change the client says what kind, and which confirmed line for an
     upgrade, a downgrade or a cancel, as its guide says it does (the client
     pages audit, PO-1, 2026-10-08). */
  function openRequest(kind, line, pick) {
    var w = t();
    var cf = pick ? (feed.services || []).filter(function (l) { return l.state === 'confirmed'; }) : [];
    req = { kind: kind, line: line || null, pick: cf.length > 0 };
    $('reqPick').hidden = !req.pick;
    if (req.pick) {
      $('reqKindLabel').textContent = w.reqKind;
      $('reqLineLabel').textContent = w.line;
      $('reqKind').innerHTML = ['details', 'upgrade', 'downgrade', 'cancel'].map(function (k) {
        return '<option value="' + k + '">' + esc(w[k]) + '</option>';
      }).join('');
      $('reqKind').value = kind;
      $('reqLine').innerHTML = cf.map(function (l) {
        return '<option value="' + esc(String(l.id)) + '">' + esc(l.label) + '</option>';
      }).join('');
    }
    paintRequest();
    /* An unsent note is kept when the dialog is left and comes back when it
       opens again; sending it is what clears it (audit F8, 2026-10-10). */
    $('reqNote').value = reqDraft[feed.client.id] || '';
    $('reqGo').textContent = w.send;
    $('reqCancel').textContent = w.close;
    $('reqClose').setAttribute('aria-label', w.closeMark);
    msg('reqMsg', '');
    /* The shared sheet: focus held inside, Escape, focus back to the button
       that opened it, and a press outside never closes it over typed text. */
    var opener = document.activeElement;
    if (window.ADspaceSheet) {
      window.ADspaceSheet.show($('reqSheet'), { opener: opener, onClose: function () { if (feed && feed.client) reqDraft[feed.client.id] = $('reqNote').value; req = null; } });
    } else { $('reqSheet').hidden = false; }
  }
  var reqDraft = {};   // an unsent note a company, never carried to another (audit 2026-11-15)
  var reqKey = null, reqFor = null;
  function keyOf() {
    var a = new Uint8Array(16);
    (window.crypto || window.msCrypto).getRandomValues(a);
    return Array.prototype.map.call(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  function paintRequest() {
    var w = t();
    if (req.pick) {
      req.kind = $('reqKind').value;
      var id = $('reqLine').value;
      req.line = req.kind === 'details' ? null
        : (feed.services || []).filter(function (l) { return String(l.id) === id; })[0] || null;
      $('reqLineWrap').hidden = req.kind === 'details';
    }
    $('reqHeading').textContent = req.pick ? w.requestChange : w[req.kind];
    $('reqFacts').innerHTML = [
      [w.company, feed.client.name],
      !req.pick && req.line ? [w.line, req.line.label] : null
    ].filter(Boolean).map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('');
    $('reqNoteLabel').textContent = w.noteFor[req.kind] || w.note;
  }
  $('reqNote').addEventListener('input', function () { if ($('reqMsg').textContent) msg('reqMsg', ''); });
  ['reqKind', 'reqLine'].forEach(function (id) {
    $(id).addEventListener('change', function () { if (req) paintRequest(); });
  });
  function shutRequest() {
    if (window.ADspaceSheet && window.ADspaceSheet.isOpen($('reqSheet'))) { window.ADspaceSheet.close(); return; }
    $('reqSheet').hidden = true; req = null;
  }
  $('ovRequest').addEventListener('click', function () { openRequest('details', null, true); });
  $('reqCancel').addEventListener('click', shutRequest);
  $('reqClose').addEventListener('click', shutRequest);
  $('reqGo').addEventListener('click', function () {
    if (!req) return;
    var note = ($('reqNote').value || '').trim();
    if (req.kind !== 'cancel' && !note) { msg('reqMsg', t().noteNeeded, 'err'); $('reqNote').focus(); return; }
    $('reqGo').disabled = true;
    /* One request, however many presses (audit C1, 2026-10-10): a key kept
       until it is sent, so a reply lost on the way and a second press file
       it once. A database without `portal_request_once` is asked the older
       way. */
    var args = { p_client: feed.client.id, p_kind: req.kind, p_service: req.line ? req.line.id : null, p_note: note || null };
    /* The key is the request's: another kind, line or note is another
       request, never the answer to the one before (CP-3, 2026-10-22). */
    var fp = [args.p_kind, args.p_service || '', args.p_note || ''].join('|');
    if (!reqKey || reqFor !== fp) { reqKey = keyOf(); reqFor = fp; }
    db.rpc('portal_request_once', { p_client: args.p_client, p_kind: args.p_kind, p_service: args.p_service, p_note: args.p_note, p_idem: reqKey })
      .then(function (r) {
        var missing = r.error && (r.error.code === 'PGRST202' || /portal_request_once/.test(r.error.message || ''));
        return missing ? db.rpc('portal_request', args) : r;
      })
      .then(function (r) {
        $('reqGo').disabled = false;
        var d = r.data || {};
        if (r.error || d.error) { msg('reqMsg', d.error === 'note-required' ? t().noteNeeded : d.error === 'too-long' ? t().tooLong : t().notSent, 'err'); return; }
        reqKey = null; reqFor = null;
        $('reqNote').value = ''; delete reqDraft[feed.client.id];
        shutRequest();
        showPane('services', true);
        msg('rqMsg', t().sent, 'ok');
        load();
      }).catch(function () { $('reqGo').disabled = false; msg('reqMsg', t().notSent, 'err'); });
  });

  function withdraw(r) {
    db.rpc('portal_withdraw', { p_id: r.id, p_undo: false }).then(function (res) {
      var d = res.data || {};
      if (res.error || d.error) { msg('rqMsg', t().notSent, 'err'); return; }
      msg('rqMsg', '');
      load();
      undoBar(t().withdrawnSay, function () {
        db.rpc('portal_withdraw', { p_id: r.id, p_undo: true }).then(function () { load(); });
      });
    });
  }

  setLang(lang);
})();
