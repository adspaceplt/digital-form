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
  function money(n) {
    return 'RM ' + Number(n || 0).toLocaleString('en-MY', { minimumFractionDigits: 0 });
  }

  /* Page furniture in both languages. Creator names are already Chinese and
     are never translated; only the words around them are. */
  var T = {
    en: {
      kicker: 'Creator Selection',
      lang: '中文',
      chooseMore: function (n) { return 'Choose ' + n + ' more to complete your list.'; },
      complete: 'Your list is complete.',
      over: 'You have chosen more than your campaign allows.',
      yourSelection: 'Your selection',
      count: function (a, b) { return a + ' of ' + b + ' chosen'; },
      newAdded: function (n) { return n + ' creators were added recently'; },
      seeNew: 'See what is new',
      select: 'Select',
      selected: 'Selected',
      backup: 'Backup',
      isBackup: 'Backup ✓',
      backupHint: 'Tick the ones you want. Marking a creator as backup costs nothing. We only use them if someone you picked becomes unavailable.',
      replacement: 'Replacement',
      viewProfile: 'View profile',
      full: 'All slots taken',
      confirm: 'Confirm selection',
      confirmHeading: 'Confirm your selection',
      confirmBlurb: 'We will start booking these creators. Your name is recorded against the confirmation.',
      nameLabel: 'Your name',
      namePlaceholder: 'Who is confirming',
      send: 'Confirm',
      cancel: 'Cancel',
      nameNeeded: 'Please enter your name.',
      confirmed: 'Thank you. Your selection is confirmed and we will be in touch with the shoot dates.',
      summary: function (n, v) { return n + ' chosen · ' + v; },
      due: function (d) { return 'Please respond by ' + d; },
      yourCampaign: 'Your campaign',
      stillChoosing: 'Still to choose',
      chip: {
        confirmed: 'Confirmed', pending_visit: 'Shoot booked', pending_delivery: 'Sending product',
        pending_draft: 'Filming done', reviewing: 'Your review needed',
        changes: 'Changes in progress', scheduled: 'Going live', posted: 'Live', completed: 'Complete',
        withdrawn: 'Unavailable'
      },
      shootOn: 'Shoot',
      pic: 'Ask for',
      goLive: 'Going live',
      viewPost: 'View post',
      reviewDraft: 'Review the draft',
      draftHeading: 'Review the draft',
      draftBlurb: 'Open it in Drive, then tell us whether it is good to go.',
      openDraft: 'Open the draft ↗',
      noteLabel: 'Anything to change (optional)',
      byLabel: 'Your name',
      approve: 'Approve',
      askChanges: 'Request changes',
      roundOf: function (n) { return 'Revision round ' + n + ' of 2'; },
      lastRound: 'This is the last included revision round.',
      reviewThanks: 'Thank you, that has gone through to the team.',
      needNote: 'Please say what needs changing.',
      unavailable: 'This creator became unavailable. Please choose a replacement below.',
      results: 'Results',
      impressions: 'Impressions', engagements: 'Engagements', views: 'Views',
      closed: 'Selection closed',
      closedText: 'This campaign is no longer open for selection. Speak to your ADspace contact if something needs changing.',
      notFound: 'Link not recognised',
      notFoundText: 'Check the link, or ask your ADspace contact for a new one.',
      passTitle: 'Access code',
      passText: 'Enter the code we sent you.',
      passWrong: 'That code did not work.',
      loading: 'Loading…',
      noneYet: 'We are still sourcing. Creators will appear here as they confirm availability.'
    },
    zh: {
      kicker: '博主选择',
      lang: 'EN',
      chooseMore: function (n) { return '再选 ' + n + ' 位即可完成。'; },
      complete: '您的名单已完成。',
      over: '所选人数已超出本次合作的名额。',
      yourSelection: '您的选择',
      count: function (a, b) { return '已选 ' + a + ' / ' + b; },
      newAdded: function (n) { return '新增了 ' + n + ' 位博主'; },
      seeNew: '查看新增',
      select: '选择',
      selected: '已选',
      backup: '设为备选',
      isBackup: '备选 ✓',
      backupHint: '勾选您想合作的博主。设为备选不产生费用，只有当您所选的博主档期不合时才会启用。',
      replacement: '替补',
      viewProfile: '查看主页',
      full: '名额已满',
      confirm: '确认选择',
      confirmHeading: '确认您的选择',
      confirmBlurb: '我们将开始安排这些博主。确认人姓名会一并记录。',
      nameLabel: '您的姓名',
      namePlaceholder: '确认人',
      send: '确认',
      cancel: '取消',
      nameNeeded: '请填写姓名。',
      confirmed: '已收到，感谢确认。我们会尽快与您跟进拍摄日期。',
      summary: function (n, v) { return '已选 ' + n + ' 位 · ' + v; },
      due: function (d) { return '请于 ' + d + ' 前回复'; },
      yourCampaign: '合作进度',
      stillChoosing: '待选择',
      chip: {
        confirmed: '已确认', pending_visit: '已排期', pending_delivery: '寄送中',
        pending_draft: '已拍摄', reviewing: '待您确认',
        changes: '修改中', scheduled: '待发布', posted: '已发布', completed: '已完成',
        withdrawn: '暂不可用'
      },
      shootOn: '拍摄',
      pic: '对接人',
      goLive: '发布日期',
      viewPost: '查看帖子',
      reviewDraft: '查看初稿',
      draftHeading: '查看初稿',
      draftBlurb: '请在 Drive 中打开查看，然后告诉我们是否可以发布。',
      openDraft: '打开初稿 ↗',
      noteLabel: '需要修改的地方（选填）',
      byLabel: '您的姓名',
      approve: '通过',
      askChanges: '需要修改',
      roundOf: function (n) { return '第 ' + n + ' 次修改（共 2 次）'; },
      lastRound: '这是最后一次包含在内的修改。',
      reviewThanks: '已收到，我们会尽快处理。',
      needNote: '请说明需要修改的内容。',
      unavailable: '该博主暂不可用，请在下方另选一位。',
      results: '数据',
      impressions: '曝光', engagements: '互动', views: '播放',
      closed: '选择已结束',
      closedText: '本次合作已不开放选择。如需调整，请联系您的 ADspace 对接人。',
      notFound: '链接无效',
      notFoundText: '请检查链接，或向您的 ADspace 对接人索取新链接。',
      passTitle: '访问码',
      passText: '请输入我们发送给您的访问码。',
      passWrong: '访问码不正确。',
      loading: '加载中…',
      noneYet: '我们仍在寻找合适的博主，确认档期后会陆续显示在这里。'
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

    document.title = (client.name ? client.name + ' · ' : '') + t().kicker;
    $('clientName').textContent = client.name || '';
    if (client.logo_url) {
      $('clientLogo').src = client.logo_url;
      $('clientLogo').hidden = false;
    }
    $('kicker').textContent = t().kicker;
    $('langToggle').textContent = t().lang;

    var title = (lang === 'zh' && c.title_zh) ? c.title_zh : c.title;
    $('campTitle').textContent = title || '';
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
    var rows = booked.concat(lost);

    $('bookingWrap').hidden = !rows.length;
    $('chooseHead').hidden = !rows.length;
    $('chooseHead').textContent = t().stillChoosing;
    $('bookingHead').textContent = t().yourCampaign;
    if (!rows.length) return;

    var box = $('bookingList');
    box.innerHTML = '';
    rows.forEach(function (o) { box.appendChild(bookingRow(o)); });
  }

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

    var bits = [];
    if (!seeding && o.visit_date) {
      bits.push(t().shootOn + ' ' + fmtDate(o.visit_date) + (o.visit_time ? ', ' + o.visit_time : ''));
    }
    if (o.visit_location) bits.push(o.visit_location);
    if (o.visit_pic) bits.push(t().pic + ' ' + o.visit_pic + (o.visit_pic_phone ? ' (' + o.visit_pic_phone + ')' : ''));
    if (o.planned_publish && o.state === 'scheduled') bits.push(t().goLive + ' ' + fmtDate(o.planned_publish));
    if (o.state === 'changes' && o.revision_round > 1) bits.push(t().roundOf(o.revision_round));

    var posts = (o.posts || []).filter(function (p) { return p.post_url; });

    row.innerHTML =
      '<div class="booking-head">' +
        '<b>' + esc(o.name) + '</b>' +
        '<span class="chip-state' + (mine ? ' is-mine' : '') + '">' + esc(chipFor(o)) + '</span>' +
        (o.is_replacement ? '<span class="tag-rep">' + esc(t().replacement) + '</span>' : '') +
      '</div>' +
      (bits.length ? '<div class="booking-meta">' + esc(bits.join('  ·  ')) + '</div>' : '') +
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

  function countSelected() {
    return Object.keys(chosen).filter(function (k) { return chosen[k] === 'selected'; }).length;
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
    $('chooseHint').textContent = t().backupHint;

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
      var links = (o.profiles || []).map(function (p) {
        return '<a class="plink" href="' + esc(p.url) + '" target="_blank" rel="noopener">' +
          esc(platLabel(p.platform)) +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
          'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
          '<path d="M14 4h6v6"/><path d="M20 4 11 13"/>' +
          '<path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg></a>';
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

    /* The bar is about what is waiting to be confirmed, not about the campaign.
       Counting booked creators in it said "3 chosen · RM 0" and offered to
       confirm a selection nobody had made. */
    var pending = (feed.options || []).filter(function (o) { return chosen[o.id] === 'selected'; });
    var value = pending.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    $('confirmSummary').textContent = t().summary(pending.length, money(value));
    $('confirmBtn').textContent = t().confirm;
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
