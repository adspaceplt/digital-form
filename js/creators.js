/*
 * Creator Selection — what the client sees.
 *
 * One link for the campaign, protected the same way the review portal is. The
 * option list grows while sourcing continues, so the page is built to be come
 * back to rather than filled in once.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  var $   = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }

  /* "Prepared for <client>" under the section name, in whichever language the
     page is showing. */
  function paintPreparedFor(name) {
    var who = name || ($('clientName') ? $('clientName').textContent : '');
    if (window.ADspaceChrome) window.ADspaceChrome.preparedFor(t().preparedFor, who);
  }

  /* The mark and the standard bar come from the shared chrome. This page's
     one extra control is moved into the slot the chrome leaves for it. */
  (function () {
    var slot = window.ADspaceChrome && window.ADspaceChrome.actions();
    var extra = $('chromeExtra');
    if (!slot || !extra) return;
    slot.insertBefore(extra.content.cloneNode(true), slot.firstChild);
    if ($('invoiceLink')) $('invoiceLink').hidden = true;
  })();
  /* Currency comes with the campaign, so a Singapore client sees S$ and never
     a ringgit sign on their own page. */
  var MON = window.ADspaceMoney;
  function mkt() { return (feed && feed.client && feed.client.market) || 'MY'; }
  function taxOn() {
    var v = feed && feed.client && feed.client.sst_applies;
    return v === undefined || v === null ? true : v;
  }
  function money(n)  { return MON.money(n, mkt()); }
  function money2(n) { return MON.money2(n, mkt()); }
  // The mark that says this opens somewhere else.
  var EXT_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M14 4h6v6"/><path d="M20 4 11 13"/>' +
    '<path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';

  function sstOf(subtotal) { return MON.taxOf(subtotal, mkt(), taxOn()); }
  /* A client who is not charged tax gets two lines, not three with a zero in
     the middle. */
  function totalsHtml(subtotal) {
    var sst = sstOf(subtotal);
    return '<div><span>' + esc(t().subtotal) + '</span><span>' + money2(subtotal) + '</span></div>' +
           (sst ? '<div><span>' + esc(MON.taxLabel(mkt())) + '</span><span>' + money2(sst) + '</span></div>' : '') +
           '<div class="is-total"><span>' + esc(t().total) + '</span><span>' + money2(subtotal + sst) + '</span></div>';
  }

  /* Page furniture in both languages. Creator names are already Chinese and
     are never translated; only the words around them are. */
  var T = {
    en: {
      kicker: 'Creator Selection',
      preparedFor: 'Prepared for',
      lang: '中文',
      chooseMore: function (n) { return 'Choose ' + n + ' more.'; },
      complete: 'All chosen.',
      over: 'You have chosen more than your campaign allows.',
      yourSelection: 'Your selection',
      count: function (a, b) { return a + ' of ' + b + ' chosen'; },
      newAdded: function (n) { return n + ' creators were added recently'; },
      seeNew: 'See what is new',
      select: 'Select',
      selected: 'Selected',
      backup: 'Backup',
      isBackup: 'Backup ✓',
      backupHint: 'Tick your picks. Best to also mark one or two backups, in case someone becomes unavailable. Backups cost nothing.',
      backupsNeeded: function (n) { return 'Best to mark ' + n + ' more backup' + (n === 1 ? '' : 's') + ', optional.'; },
      backupsDone: 'Backups marked.',
      backupCount: function (a, b) { return a + ' of ' + b + ' backups'; },
      priorityNotice: 'A creator is unavailable. Your backups are first in line. Tick one.',
      priority: 'Priority',
      oneMoreBackup: 'Choose another backup so two stay in reserve.',
      replacement: 'Replacement',
      viewProfile: 'View profile',
      viewOn: function (platform) { return 'View ' + platform + ' profile'; },
      platform: { xhs: 'RedNote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
      full: 'All slots taken',
      confirm: 'Confirm selection',
      confirmHeading: 'Confirm your selection',
      confirmBlurb: 'We will book these creators. Your name goes on the confirmation.',
      nameLabel: 'Your name',
      namePlaceholder: 'Who is confirming',
      send: 'Confirm',
      cancel: 'Cancel',
      nameNeeded: 'Please enter your name.',
      confirmed: 'Confirmed. We will send the shoot dates soon.',
      summary: function (n, v) { return n + ' chosen · ' + v; },
      subtotal: 'Subtotal',
      sst: 'SST 8%',
      total: 'Total',
      totalShort: function (v, tax) { return 'Total ' + v + (tax ? ' incl. ' + tax : ''); },
      invoice: 'Invoice',
      due: function (d) { return 'Campaign due ' + d; },
      yourCampaign: 'Your campaign',
      stillChoosing: 'Still to choose',
      chip: {
        confirmed: 'Confirmed', pending_visit: 'Shoot booked', pending_delivery: 'Sending product',
        pending_draft: 'Filming done', reviewing: 'Your review needed',
        changes: 'Changes in progress', scheduled: 'Going live', posted: 'Live', completed: 'Complete',
        withdrawn: 'Unavailable'
      },
      shootOn: 'Shoot',
      deliveryOn: 'Delivery',
      postedOn: 'Posted',
      platformsLabel: 'Posting on',
      stageLabel: 'Stage',
      revisionLabel: 'Revision',
      nextLabel: 'Next',
      nextUp: {
        confirmed: 'We fix a shoot date', pending_visit: 'Filming',
        pending_draft: 'Draft comes to you', reviewing: 'Your approval',
        changes: 'Creator reworks it', scheduled: 'Goes live',
        posted: 'Results after 7 days'
      },
      tbc: 'To be confirmed',
      amountLabel: 'Campaign amount',
      pic: 'Ask for',
      goLive: 'Going live',
      viewPost: 'View post',
      reviewDraft: 'Review the draft',
      draftHeading: 'Review the draft',
      draftBlurb: 'Open the draft in Drive. Then approve it, or ask for changes.',
      openDraft: 'Open the draft ↗',
      noteLabel: 'Anything to change (optional)',
      byLabel: 'Your name',
      approve: 'Approve',
      askChanges: 'Request changes',
      roundOf: function (n) { return 'Revision round ' + n + ' of 2'; },
      lastRound: 'Last included revision round.',
      reviewThanks: 'Thank you, that has gone through to the team.',
      needNote: 'Please say what needs changing.',
      unavailable: 'Unavailable. Choose a replacement below.',
      results: 'Results',
      impressions: 'Impressions', engagements: 'Engagements', views: 'Views',
      closed: 'Selection closed',
      closedText: 'Selection is closed. Contact your ADspace person to change anything.',
      notFound: 'Link not recognised',
      notFoundText: 'Check the link, or ask your ADspace person for a new one.',
      passTitle: 'Access code',
      passText: 'Enter the code we sent you.',
      passWrong: 'That code did not work.',
      loading: 'Loading…',
      noneYet: 'Still sourcing. Creators appear here as they confirm.'
    },
    zh: {
      kicker: '博主选择',
      preparedFor: '呈交',
      lang: 'EN',
      chooseMore: function (n) { return '再选 ' + n + ' 位。'; },
      complete: '已选齐。',
      over: '所选人数已超出本次合作的名额。',
      yourSelection: '您的选择',
      count: function (a, b) { return '已选 ' + a + ' / ' + b; },
      newAdded: function (n) { return '新增了 ' + n + ' 位博主'; },
      seeNew: '查看新增',
      select: '选择',
      selected: '已选',
      backup: '设为备选',
      isBackup: '备选 ✓',
      backupHint: '勾选您想要的博主。建议再设一两位备选，以防有人档期不合。备选不产生费用。',
      backupsNeeded: function (n) { return '建议再设 ' + n + ' 位备选（可选）。'; },
      backupsDone: '备选已设。',
      backupCount: function (a, b) { return '备选 ' + a + ' / ' + b; },
      priorityNotice: '有一位博主暂不可用。备选已优先显示，请勾选一位。',
      priority: '优先',
      oneMoreBackup: '请再选一位备选，以保持两位在候补。',
      replacement: '替补',
      viewProfile: '查看主页',
      viewOn: function (platform) { return '查看' + platform + '主页'; },
      platform: { xhs: '小红书', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
      full: '名额已满',
      confirm: '确认选择',
      confirmHeading: '确认您的选择',
      confirmBlurb: '我们将安排这些博主。确认人姓名会一并记录。',
      nameLabel: '您的姓名',
      namePlaceholder: '确认人',
      send: '确认',
      cancel: '取消',
      nameNeeded: '请填写姓名。',
      confirmed: '已确认。我们会尽快发送拍摄日期。',
      summary: function (n, v) { return '已选 ' + n + ' 位 · ' + v; },
      subtotal: '小计',
      sst: 'SST 8%',
      total: '总计',
      totalShort: function (v, tax) { return '总计 ' + v + (tax ? '（含 ' + tax + '）' : ''); },
      invoice: '发票',
      due: function (d) { return '合作截止 ' + d; },
      yourCampaign: '合作进度',
      stillChoosing: '待选择',
      chip: {
        confirmed: '已确认', pending_visit: '已排期', pending_delivery: '寄送中',
        pending_draft: '已拍摄', reviewing: '待您确认',
        changes: '修改中', scheduled: '待发布', posted: '已发布', completed: '已完成',
        withdrawn: '暂不可用'
      },
      shootOn: '拍摄',
      deliveryOn: '寄送',
      postedOn: '发布于',
      platformsLabel: '发布平台',
      stageLabel: '当前进度',
      revisionLabel: '修改',
      nextLabel: '下一步',
      nextUp: {
        confirmed: '确定拍摄日期', pending_visit: '拍摄',
        pending_draft: '初稿交给您', reviewing: '等您确认',
        changes: '博主修改中', scheduled: '即将发布',
        posted: '7 天后出数据'
      },
      tbc: '待定',
      amountLabel: '合作金额',
      pic: '对接人',
      goLive: '发布日期',
      viewPost: '查看帖子',
      reviewDraft: '查看初稿',
      draftHeading: '查看初稿',
      draftBlurb: '请在 Drive 中打开初稿，然后通过或提出修改。',
      openDraft: '打开初稿 ↗',
      noteLabel: '需要修改的地方（选填）',
      byLabel: '您的姓名',
      approve: '通过',
      askChanges: '需要修改',
      roundOf: function (n) { return '第 ' + n + ' 次修改（共 2 次）'; },
      lastRound: '这是最后一次包含在内的修改。',
      reviewThanks: '已收到，我们会尽快处理。',
      needNote: '请说明需要修改的内容。',
      unavailable: '暂不可用。请在下方另选一位。',
      results: '数据',
      impressions: '曝光', engagements: '互动', views: '播放',
      closed: '选择已结束',
      closedText: '选择已结束。如需调整，请联系您的 ADspace 对接人。',
      notFound: '链接无效',
      notFoundText: '请检查链接，或向您的 ADspace 对接人索取新链接。',
      passTitle: '访问码',
      passText: '请输入我们发送给您的访问码。',
      passWrong: '访问码不正确。',
      loading: '加载中…',
      noneYet: '仍在寻找博主，确认档期后会显示在这里。'
    }
  };

  var lang = 'en';
  function t() { return T[lang]; }

  var LANG_KEY = 'adspace.creators.lang';
  try { var saved = localStorage.getItem(LANG_KEY); if (saved && T[saved]) lang = saved; } catch (e) {}

  var params = new URLSearchParams(location.search);
  var TOKEN = params.get('k') || '';
  var passcode = null;
  var feed = null;
  var chosen = {};   // option id -> 'selected' | 'backup'
  var SEEN_KEY = 'adspace.creators.seen.' + (TOKEN || 'demo');

  function seenBefore() {
    try { return JSON.parse(localStorage.getItem(SEEN_KEY) || '[]'); } catch (e) { return []; }
  }
  function remember(ids) {
    try { localStorage.setItem(SEEN_KEY, JSON.stringify(ids)); } catch (e) {}
  }

  function showState(title, text, withPass) {
    $('app').hidden = true;
    $('stateBox').hidden = false;
    $('stateTitle').textContent = title;
    $('stateText').textContent = text;
    $('passRow').hidden = !withPass;
    document.body.classList.add('is-plain');
    if (withPass) $('passInput').focus();
  }

  function setLang(next) {
    lang = next;
    try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
    $('langToggle').textContent = t().lang;
    $('kicker').textContent = t().kicker;
    paintPreparedFor();
    document.documentElement.lang = lang === 'zh' ? 'zh' : 'en';
    if (feed) build();
  }

  $('langToggle').addEventListener('click', function () { setLang(lang === 'en' ? 'zh' : 'en'); });

  // ---- Load ---------------------------------------------------------------
  function load() {
    if (!db) { showState('Not connected', 'This portal has not been configured yet.', false); return; }
    if (!TOKEN) { showState(t().notFound, t().notFoundText, false); return; }

    db.rpc('get_campaign', { p_token: TOKEN, p_passcode: passcode }).then(function (r) {
      if (r.error) { showState(t().notFound, r.error.message, false); return; }
      var d = r.data || {};
      if (d.error === 'not-found') { showState(t().notFound, t().notFoundText, false); return; }
      if (d.error === 'passcode') {
        // The gate knows whose campaign it is guarding, so say so.
        if (d.client) $('clientName').textContent = d.client;
        showState(t().passTitle, t().passText, true);
        if (passcode) $('stateMsg').textContent = t().passWrong;
        return;
      }
      feed = d;
      $('stateBox').hidden = true;
      document.body.classList.remove('is-plain');
      build();
    });
  }

  $('passGo').addEventListener('click', function () {
    passcode = ($('passInput').value || '').trim();
    if (passcode) load();
  });
  $('passInput').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') $('passGo').click();
  });

  // ---- Build --------------------------------------------------------------
  function build() {
    var c = feed.campaign || {};
    var client = feed.client || {};
    var options = feed.options || [];

    document.title = (client.name ? client.name + ' · ' : '') + 'ADspace ' + t().kicker;
    $('clientName').textContent = client.name || '';
    paintPreparedFor(client.name);

    $('kicker').textContent = t().kicker;
    $('langToggle').textContent = t().lang;
    $('invoiceLink').hidden = !c.invoice_url;
    if (c.invoice_url) {
      $('invoiceLink').href = c.invoice_url;
      $('invoiceLinkText').textContent = t().invoice + (c.invoice_no ? ' ' + c.invoice_no : '');
    }

    var title = (lang === 'zh' && c.title_zh) ? c.title_zh : c.title;
    $('campTitle').textContent = title || '';
    var purpose = (lang === 'zh' && c.purpose_zh) ? c.purpose_zh : c.purpose;
    $('campPurpose').textContent = purpose || '';
    $('campPurpose').hidden = !purpose;
    var brief = (lang === 'zh' && c.brief_zh) ? c.brief_zh : c.brief;
    $('campBrief').textContent = brief || '';
    $('campBrief').hidden = !brief;
    $('campDue').textContent = c.deadline ? t().due(fmtDate(c.deadline)) : '';
    $('campDue').hidden = !c.deadline;

    if (c.state === 'draft') { showState(t().closed, t().closedText, false); return; }

    $('app').hidden = false;

    // Seed from whatever the server already holds, so returning to the link
    // shows what was left rather than an empty sheet.
    chosen = {};
    options.forEach(function (o) {
      if (o.state === 'shortlisted') chosen[o.id] = 'selected';
      else if (o.state === 'backup') chosen[o.id] = 'backup';
    });

    paintBookings();
    paintCards();
    paintProgress();
  }

  /* Which states count as "booked and running" rather than "still on offer".
     Selection and production live on one page, because a campaign is normally
     both at once: six locked and filming while four slots are still open. */
  var BOOKED = ['confirmed', 'pending_visit', 'pending_draft', 'reviewing',
                'changes', 'scheduled', 'posted', 'completed'];

  function isBooked(o) { return BOOKED.indexOf(o.state) > -1; }

  function paintBookings() {
    var options = feed.options || [];
    var booked = options.filter(isBooked);
    var lost = options.filter(function (o) { return o.state === 'withdrawn'; });
    // The next shoot is what the client is watching for, so dated bookings
    // come first, soonest first. Undated ones follow in the order offered.
    booked = booked.map(function (o, i) { return [o, i]; }).sort(function (a, b) {
      var da = a[0].visit_date || '', dbb = b[0].visit_date || '';
      if (da && dbb) return da < dbb ? -1 : da > dbb ? 1 : a[1] - b[1];
      if (da) return -1;
      if (dbb) return 1;
      return a[1] - b[1];
    }).map(function (x) { return x[0]; });
    var rows = booked.concat(lost);

    $('bookingWrap').hidden = !rows.length;
    $('chooseHead').hidden = !rows.length;
    $('chooseHead').textContent = t().stillChoosing;
    $('bookingHead').textContent = t().yourCampaign;
    if (!rows.length) return;

    var box = $('bookingList');
    box.innerHTML = '';
    rows.forEach(function (o) { box.appendChild(bookingRow(o)); });

    var sub = booked.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    $('bookedTotals').innerHTML = booked.length ? totalsHtml(sub) : '';
    $('amountFold').hidden = !booked.length;
    $('amountLabel').textContent = t().amountLabel;
  }

  /* Folded shut every time the page loads, so the figure is shown on purpose
     rather than by default. */
  $('amountToggle').addEventListener('click', function () {
    var open = $('bookedTotals').hidden;
    $('bookedTotals').hidden = !open;
    this.setAttribute('aria-expanded', String(open));
    this.classList.toggle('is-open', open);
  });

  function chipFor(o) {
    var c = feed.campaign || {};
    var key = o.state;
    if (key === 'pending_visit' && c.push_format === 'seeding') key = 'pending_delivery';
    return t().chip[key] || key;
  }

  function bookingRow(o) {
    var c = feed.campaign || {};
    var seeding = c.push_format === 'seeding';
    var row = document.createElement('div');
    var mine = o.state === 'reviewing';          // the only one that is theirs to act on
    row.className = 'booking' + (mine ? ' is-mine' : '') +
      (o.state === 'withdrawn' ? ' is-off' : '');

    /* One line of small grey text left most of the card empty and made the
       client hunt for the date. The same facts as a labelled grid fill the
       card and read at a glance. */
    var live = o.state === 'posted' || o.state === 'completed';
    var facts = [];
    if (o.state !== 'withdrawn') {
      // Once it is out, when it went out is the date that matters. Before
      // that, the shoot is the date everyone is planning around.
      var wentOut = live && (o.posts || []).map(function (p) { return p.published_at; })
        .filter(Boolean).sort()[0];
      if (wentOut) {
        facts.push([t().postedOn, fmtDate(wentOut)]);
      } else if (!live) {
        facts.push([seeding ? t().deliveryOn : t().shootOn,
          o.visit_date ? fmtDate(o.visit_date) + (o.visit_time ? ', ' + o.visit_time : '') : t().tbc]);
      }
      var plats = String(o.platforms || '').split(',').map(function (s) { return s.trim(); })
        .filter(Boolean).map(platLabel);
      if (plats.length) facts.push([t().platformsLabel, plats.join(' · ')]);
      if (o.planned_publish && !live) facts.push([t().goLive, fmtDate(o.planned_publish)]);
      if ((o.state === 'changes' || o.state === 'reviewing') && o.revision_round > 1) {
        facts.push([t().revisionLabel, o.revision_round + ' / 2']);
      }
      // The one thing a chip cannot say: what happens after this.
      var next = t().nextUp[o.state];
      if (next) facts.push([t().nextLabel, next]);
    }
    var factsHtml = facts.length ? '<dl class="booking-facts">' + facts.map(function (f) {
      return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
    }).join('') + '</dl>' : '';

    var posts = (o.posts || []).filter(function (p) { return p.post_url; });

    row.innerHTML =
      '<div class="booking-head">' +
        '<b>' + esc(o.name) + '</b>' +
        '<span class="chip-state' + (mine ? ' is-mine' : '') + '">' + esc(chipFor(o)) + '</span>' +
        (o.is_replacement ? '<span class="tag-rep">' + esc(t().replacement) + '</span>' : '') +
      '</div>' +
      factsHtml +
      (o.state === 'withdrawn' ? '<div class="booking-meta">' + esc(t().unavailable) + '</div>' : '') +
      (posts.length ? '<div class="booking-posts">' + posts.map(function (p) {
          return '<a class="pchip" href="' + esc(p.post_url) + '" target="_blank" rel="noopener">' +
            esc(platLabel(p.platform)) + ' · ' + esc(t().viewPost) + ' ↗</a>';
        }).join('') + '</div>' : '') +
      (resultsOf(posts) || '') +
      (mine && o.draft_url ? '<button class="btn btn-sm btn-primary booking-cta" type="button">' +
        esc(t().reviewDraft) + '</button>' : '');

    if (mine && o.draft_url) {
      row.querySelector('.booking-cta').addEventListener('click', function () { openDraft(o); });
    }
    return row;
  }

  function resultsOf(posts) {
    var withNums = posts.filter(function (p) {
      return p.impressions != null || p.engagements != null || p.views != null;
    });
    if (!withNums.length) return '';
    return '<div class="booking-results">' + withNums.map(function (p) {
      var n = [];
      if (p.impressions != null) n.push(t().impressions + ' ' + Number(p.impressions).toLocaleString());
      if (p.engagements != null) n.push(t().engagements + ' ' + Number(p.engagements).toLocaleString());
      if (p.views != null) n.push(t().views + ' ' + Number(p.views).toLocaleString());
      return '<span><b>' + esc(platLabel(p.platform)) + '</b> ' + esc(n.join(' · ')) + '</span>';
    }).join('') + '</div>';
  }

  // ---- Draft review -------------------------------------------------------
  var reviewing = null;

  function openDraft(o) {
    reviewing = o;
    $('draftHeading').textContent = t().draftHeading + ' · ' + o.name;
    $('draftBlurb').textContent = t().draftBlurb +
      (o.revision_round >= 2 ? '  ' + t().lastRound : '');
    $('draftOpen').href = o.draft_url;
    $('draftOpen').textContent = t().openDraft;
    $('draftNoteLabel').textContent = t().noteLabel;
    $('draftByLabel').textContent = t().byLabel;
    $('draftApprove').textContent = t().approve;
    $('draftChanges').textContent = t().askChanges;
    $('draftCancel').textContent = t().cancel;
    $('draftNote').value = '';
    msg('draftMsg', '');
    $('draftSheet').hidden = false;
  }
  function shutDraft() { $('draftSheet').hidden = true; reviewing = null; }
  $('draftClose').addEventListener('click', shutDraft);
  $('draftCancel').addEventListener('click', shutDraft);
  $('draftSheet').addEventListener('click', function (e) {
    if (e.target === $('draftSheet')) shutDraft();
  });

  function sendReview(decision) {
    if (!reviewing) return;
    var note = ($('draftNote').value || '').trim();
    if (decision === 'changes' && !note) { msg('draftMsg', t().needNote, 'err'); return; }
    db.rpc('review_draft', {
      p_token: TOKEN, p_option: reviewing.id, p_decision: decision,
      p_note: note || null, p_reviewer: ($('draftBy').value || '').trim() || null,
      p_passcode: passcode
    }).then(function (r) {
      var d = (r && r.data) || {};
      if ((r && r.error) || d.error) {
        msg('draftMsg', (r.error && r.error.message) || d.error, 'err');
        return;
      }
      shutDraft();
      load();                       // states have moved, so read them back
    });
  }
  $('draftApprove').addEventListener('click', function () { sendReview('approved'); });
  $('draftChanges').addEventListener('click', function () { sendReview('changes'); });

  function fmtDate(d) {
    var dt = new Date(d + 'T00:00:00');
    return dt.toLocaleDateString(lang === 'zh' ? 'zh-CN' : 'en-GB',
      { day: 'numeric', month: 'short', year: 'numeric' });
  }

  var BACKUPS_WANTED = 2;

  function countSelected() {
    return Object.keys(chosen).filter(function (k) { return chosen[k] === 'selected'; }).length;
  }
  function countBackups() {
    return Object.keys(chosen).filter(function (k) { return chosen[k] === 'backup'; }).length;
  }
  /* Two backups, unless there are not two spare creators to choose from. A
     client with exactly ten options for ten slots cannot be asked for more. */
  function backupsWanted() {
    var spare = choosable().length - countSelected();
    return Math.max(0, Math.min(BACKUPS_WANTED, spare));
  }
  /* A slot has come free through a withdrawal and has not been refilled. The
     client's own backups are the first thing they should see. */
  function slotReopened() {
    var lost = (feed.options || []).some(function (o) { return o.state === 'withdrawn'; });
    return lost && countSelected() < slotsLeft();
  }
  // Already locked, so they hold a slot and are no longer on offer.
  function countBooked() {
    return (feed.options || []).filter(isBooked).length;
  }
  function slotsLeft() {
    return Math.max(0, ((feed.campaign || {}).slots || 0) - countBooked());
  }
  // What is still choosable. A booked creator has left the shelf; a withdrawn
  // one has too, and its slot has already been handed back.
  function choosable() {
    return (feed.options || []).filter(function (o) {
      return ['option', 'shortlisted', 'backup'].indexOf(o.state) > -1;
    });
  }

  function paintCards() {
    var grid = $('optionGrid');
    var options = choosable();
    var slots = slotsLeft();
    var before = seenBefore();
    var priority = slotReopened();
    if (priority) {
      // Backups first, everything else in its original order.
      options = options.slice().sort(function (a, b) {
        var ab = chosen[a.id] === 'backup' ? 0 : 1;
        var bb = chosen[b.id] === 'backup' ? 0 : 1;
        return ab - bb;
      });
    }
    var isNew = function (o) { return before.length > 0 && before.indexOf(o.id) < 0; };

    grid.innerHTML = '';
    if (!options.length) {
      // Nothing left to choose is not the same as nothing sourced yet.
      grid.innerHTML = countBooked()
        ? '' : '<div class="empty">' + esc(t().noneYet) + '</div>';
      $('chooseHead').hidden = true;
      $('chooseHint').hidden = true;
      return;
    }
    $('chooseHint').hidden = false;
    $('chooseHint').textContent = priority ? t().priorityNotice : t().backupHint;
    $('chooseHint').classList.toggle('is-priority', priority);

    /* A list, not cards. Ten is a page of cards and forty is an afternoon of
       scrolling; the decision is made by opening profiles and comparing rates,
       and a row puts both within reach without moving the eye. */
    options.forEach(function (o) {
      var pick = chosen[o.id];
      var full = countSelected() >= slots && pick !== 'selected';
      var row = document.createElement('div');
      row.className = 'crow' + (pick === 'selected' ? ' is-on' : '') +
        (pick === 'backup' ? ' is-backup' : '');

      // The profile link is the thing they came to click, so it is a button
      // with the platform named on it, not a chip that reads as decoration.
      /* The profile is the thing they came to open, so it is named in full and
         carries the icon that says it leaves the page. Several sit side by
         side and wrap when the width runs out. */
      var links = (o.profiles || []).map(function (p) {
        var name = t().platform[p.platform] || platLabel(p.platform);
        return '<a class="plink" href="' + esc(p.url) + '" target="_blank" rel="noopener">' +
          esc(t().viewOn(name)) + EXT_ICON + '</a>';
      }).join('');

      row.innerHTML =
        '<button class="crow-tick' + (full ? ' is-full' : '') + '" type="button"' +
          (full ? ' disabled' : '') + ' aria-pressed="' + (pick === 'selected') + '"' +
          ' title="' + esc(full ? t().full : t().select) + '">' +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" ' +
          'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
          '<path d="m5 12.5 4.5 4.5L19 7.5"/></svg></button>' +
        '<div class="crow-name">' +
          '<b>' + esc(o.name) + '</b>' +
          (isNew(o) ? '<span class="tag-new">NEW</span>' : '') +
          (priority && pick === 'backup' ? '<span class="tag-pri">' + esc(t().priority) + '</span>' : '') +
          (o.is_replacement ? '<span class="tag-rep">' + esc(t().replacement) + '</span>' : '') +
        '</div>' +
        '<div class="crow-links">' + links + '</div>' +
        '<div class="crow-rate">' + money(o.rate) + '</div>' +
        '<button class="crow-backup' + (pick === 'backup' ? ' is-on' : '') + '" type="button">' +
          esc(pick === 'backup' ? t().isBackup : t().backup) + '</button>';

      row.querySelector('.crow-tick').addEventListener('click', function () {
        if (chosen[o.id] === 'selected') delete chosen[o.id];
        else if (countSelected() < slots) chosen[o.id] = 'selected';
        redraw();
      });
      row.querySelector('.crow-backup').addEventListener('click', function () {
        if (chosen[o.id] === 'backup') delete chosen[o.id];
        else chosen[o.id] = 'backup';
        redraw();
      });
      grid.appendChild(row);
    });

    remember(options.map(function (o) { return o.id; }));
  }

  function platLabel(p) {
    return { xhs: 'RedNote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' }[p] || p;
  }

  function redraw() { paintCards(); paintProgress(); save(); }

  function paintProgress() {
    var slots = (feed.campaign || {}).slots || 0;
    var booked = countBooked();
    var n = countSelected() + booked;      // locked creators already hold a slot
    var pct = slots ? Math.min(100, Math.round((n / slots) * 100)) : 0;

    // Once everything is booked there is nothing left to choose, so the card
    // would be telling the client about a job that is finished.
    $('progressCard').hidden = !choosable().length;

    $('progLabel').textContent = t().yourSelection;
    $('progCount').textContent = t().count(n, slots);
    $('progFill').style.width = pct + '%';
    $('progSay').textContent = n >= slots ? t().complete : t().chooseMore(slots - n);
    $('progressCard').classList.toggle('is-done', n >= slots);

    var want = backupsWanted();
    var have = countBackups();
    var backupsOk = have >= want;
    $('progBackup').hidden = !want;
    $('progBackup').textContent = !want ? '' :
      (backupsOk ? t().backupsDone + ' ' + t().backupCount(have, want)
                 : t().backupsNeeded(want - have) + ' ' + t().backupCount(have, want));
    $('progBackup').classList.toggle('is-ok', backupsOk);

    /* The bar is about what is waiting to be confirmed, not about the campaign.
       Counting booked creators in it said "3 chosen · RM 0" and offered to
       confirm a selection nobody had made. */
    var pending = (feed.options || []).filter(function (o) { return chosen[o.id] === 'selected'; });
    var value = pending.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    // Confirming needs the backups too, and the bar says so rather than just
    // refusing. A backup promoted into a slot leaves one fewer in reserve.
    var short = want - have;
    $('confirmSummary').innerHTML =
      '<b>' + esc(t().totalShort(money2(value + sstOf(value)),
                 sstOf(value) ? MON.taxLabel(mkt()) : '')) + '</b>' +
      // A client who is not charged tax should not read a tax line of zero.
      '<span class="muted">' + esc(t().summary(pending.length, money2(value))) +
        (sstOf(value) ? ' + ' + esc(MON.taxLabel(mkt())) + ' ' + money2(sstOf(value)) : '') +
      '</span>' +
      (short > 0 ? '<span class="muted">' + esc(t().backupsNeeded(short)) + '</span>' : '');
    $('confirmBtn').textContent = t().confirm;
    // Backups are advice. Blocking the button on them left people who had
    // made their choice staring at a grey Confirm with no idea why.
    $('confirmBtn').disabled = !pending.length;
    $('confirmBar').hidden = !pending.length;
  }

  // ---- Save (fire and forget, the client never waits on it) ---------------
  var saveTimer = null;
  function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      var sel = [], bak = [];
      Object.keys(chosen).forEach(function (id) {
        (chosen[id] === 'selected' ? sel : bak).push(id);
      });
      db.rpc('save_selection', {
        p_token: TOKEN, p_selected: sel, p_backup: bak, p_passcode: passcode
      }).then(function () {}, function () {});
    }, 500);
  }

  // ---- Confirm ------------------------------------------------------------
  $('confirmBtn').addEventListener('click', function () {
    var picked = (feed.options || []).filter(function (o) { return chosen[o.id] === 'selected'; });
    $('confirmHeading').textContent = t().confirmHeading;
    $('confirmBlurb').textContent = t().confirmBlurb;
    $('confirmNameLabel').textContent = t().nameLabel;
    $('confirmName').placeholder = t().namePlaceholder;
    $('confirmGo').textContent = t().send;
    $('confirmCancel').textContent = t().cancel;
    $('confirmList').innerHTML = picked.map(function (o) {
      return '<div class="act"><span class="act-subject">' + esc(o.name) + '</span>' +
        '<span class="muted act-when">' + money(o.rate) + '</span></div>';
    }).join('');
    var sub = picked.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    $('confirmTotals').innerHTML = totalsHtml(sub);
    msg('confirmMsg', '');
    $('confirmSheet').hidden = false;
    $('confirmName').focus();
  });

  function msg(id, text, kind) {
    var n = $(id); n.textContent = text || ''; n.className = 'msg' + (kind ? ' ' + kind : '');
  }

  function shutConfirm() { $('confirmSheet').hidden = true; }
  $('confirmClose').addEventListener('click', shutConfirm);
  $('confirmCancel').addEventListener('click', shutConfirm);
  $('confirmSheet').addEventListener('click', function (e) {
    if (e.target === $('confirmSheet')) shutConfirm();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutConfirm(); });

  $('confirmGo').addEventListener('click', function () {
    var name = ($('confirmName').value || '').trim();
    if (!name) { msg('confirmMsg', t().nameNeeded, 'err'); return; }
    db.rpc('confirm_selection', { p_token: TOKEN, p_person: name, p_passcode: passcode })
      .then(function (r) {
        var d = (r && r.data) || {};
        if ((r && r.error) || d.error) {
          msg('confirmMsg', (r.error && r.error.message) || d.error, 'err');
          return;
        }
        shutConfirm();
        showState(t().kicker, t().confirmed, false);
      });
  });

  setLang(lang);
  load();
})();
