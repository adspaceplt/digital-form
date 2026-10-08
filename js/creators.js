/*
 * Creator Selection — what the client sees.
 *
 * One link for the campaign, protected the same way the review portal is. The
 * option list grows while sourcing continues, so the page is built to be come
 * back to rather than filled in once.
 */
(function () {
  var API = window.ADspaceAPI;
  /* FIRST-VISIT GUIDE (js/guide.js, the user, 2026-10-07): offered once in
     this browser, the moment the page shows what it is for. */
  var GUIDE = { name: { en: 'Choose your creators', zh: '挑选创作者' }, steps: [
    { at: '.crow-tick', text: { en: 'Tick the creators you want for this campaign. Each pick is kept as you go.', zh: '勾选您希望合作的创作者，每次勾选都会自动保存。' } },
    { at: '#confirmBtn', text: { en: 'Confirm selection once your picks are final.', zh: '选定后，请点「确认选择」。' } }] };
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
  var T = window.ADspaceWords.of({
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
      backupHint: 'Select your creators. Backups are optional and not charged.',
      backupsNeeded: function () { return 'Backups optional.'; },
      backupsDone: 'Backups marked.',
      backupCount: function (a, b) { return a + ' of ' + b + ' marked'; },
      priorityNotice: 'A creator is unavailable. Please select a replacement; your backups are listed first.',
      priority: 'Priority',
      oneMoreBackup: 'Please select one more backup.',
      replacement: 'Replacement',
      viewProfile: 'View profile',
      viewOn: function (platform) { return 'View ' + platform + ' profile'; },
      platform: { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
      full: 'All creators chosen',
      confirm: 'Confirm selection',
      confirmHeading: 'Confirm your selection',
      confirmBlurb: 'Your selection will be confirmed under the name entered below.',
      nameLabel: 'Your name',
      /* Just Name. Asking a client for their full name every time they
         approve something reads as an identity check rather than a signature.
         Chinese already said 姓名, which is the same register. */
      namePlaceholder: 'John Doe',
      send: 'Confirm',
      cancel: 'Cancel',
      nameNeeded: 'Please enter your name.',
      confirmed: 'Selection confirmed. Shoot dates will follow.',
      summary: function (n, v) { return n + ' chosen · ' + v; },
      subtotal: 'Subtotal',
      total: 'Total',
      totalShort: function (v, tax) { return 'Total ' + v + (tax ? ' incl. ' + tax : ''); },
      invoice: 'Invoice',
      due: function (d) { return 'Campaign due ' + d; },
      yourCampaign: 'Your campaign',
      stillChoosing: 'Available creators',
      backupsHead: 'Backup creators',
      shootOn: 'Shoot',
      deliveryOn: 'Delivery',
      postedOn: 'Posted',
      measuredOn: 'Measured',
      platformCol: 'Platform',
      platformsLabel: 'Posting on',
      /* The columns a fee is compared across. Named only where there is room
         to compare: below the phone line the header leaves with them. */
      colCreator: 'Creator', colProfiles: 'Profiles', colFee: 'Fee',
      stageLabel: 'Stage',
      nextLabel: 'Next',
      /* Next names the client only where the client is the one who acts. At
         pending_draft nothing has arrived yet, so a line reading "for your
         review" sends them looking for a link that is not there; the draft
         reaches them when the team uploads it and the step becomes reviewing.
         Only that step, and changes requested, are theirs. */
      nextUp: {
        confirmed: 'Shoot date to be scheduled', pending_visit: 'Filming',
        pending_draft: 'Draft in progress', reviewing: 'Your approval',
        changes: 'Revision in progress', scheduled: 'Goes live',
        posted: 'Results in 7 days'
      },
      tbc: 'To be confirmed',
      amountLabel: 'Amount',
      detailsLabel: 'Campaign details',
      creatorsLabel: 'Creators',
      dueLabel: 'Campaign due',
      pdf: 'PDF ↗',
      pdfFail: 'Unable to open the invoice. Please refresh and try again.',
      pic: 'Contact',
      goLive: 'Going live',
      viewPost: 'View post',
      /* The post itself, named for where it lives (the user, 2026-09-27: the
         platform's name alone was "too not obvious"). */
      viewPostOn: function (platform) { return 'View post on ' + platform; },
      captionLabel: 'Caption',
      openDraft: 'Open the draft',
      noteLabel: 'Changes required',
      approve: 'Approve',
      askChanges: 'Request changes',
      sendRequest: 'Send request',
      theClient: 'the client',
      approvedBy: function (who, when) { return 'Approved by ' + who + (when ? ' on ' + when : '') + '.'; },
      proceededBy: function (who, when) { return 'Proceeded by ' + who + (when ? ' on ' + when : '') + '.'; },
      changesBy: function (who, when) { return 'Changes requested by ' + who + (when ? ' on ' + when : '') + '.'; },
      reviewThanks: 'Received. The team will follow up.',
      needNote: 'Please describe the changes required.',
      saveFailed: 'Unable to save. Please try again.',
      selectionClosed: 'Selection is closed. Please contact your ADspace account manager.',
      unavailable: 'Unavailable. Please select a replacement below.',
      results: 'Results',
      resultsHead: 'Campaign results',
      placements: 'Placements', cpe: 'Cost per engagement',
      impressions: 'Impressions', engagements: 'Engagements', views: 'Views',
      noneYet: 'No creators.',
      /* The campaign room (2026-10-07, the client pages refresh). */
      ofPosted: function (a, b) { return a + ' of ' + b + ' posted'; },
      nextShoot: function (d) { return 'Next shoot ' + d; },
      waitingYou: 'Waiting for your approval',
      engRate: 'Engagement rate', perEng: 'Per engagement', viewsWord: 'views',
      topPost: 'Top post', measuredWord: function (d) { return 'Measured ' + d; }
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
      backupHint: '请选择博主。备选为可选项，不产生费用。',
      backupsNeeded: function () { return '备选为可选项。'; },
      backupsDone: '备选已设。',
      backupCount: function (a, b) { return '已设备选 ' + a + ' / ' + b; },
      priorityNotice: '有一位博主暂不可用，请选择替补。备选已优先显示。',
      priority: '优先',
      oneMoreBackup: '请再选一位备选。',
      replacement: '替补',
      viewProfile: '查看主页',
      viewOn: function (platform) { return '查看' + platform + '主页'; },
      platform: { xhs: '小红书', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
      full: '名额已满',
      confirm: '确认选择',
      confirmHeading: '确认您的选择',
      confirmBlurb: '您的选择将以下方填写的姓名确认。',
      nameLabel: '您的姓名',
      namePlaceholder: '陈小明',
      send: '确认',
      cancel: '取消',
      nameNeeded: '请填写姓名。',
      confirmed: '已确认。拍摄日期将随后通知。',
      summary: function (n, v) { return '已选 ' + n + ' 位 · ' + v; },
      subtotal: '小计',
      total: '总计',
      totalShort: function (v, tax) { return '总计 ' + v + (tax ? '（含 ' + tax + '）' : ''); },
      invoice: '发票',
      due: function (d) { return '合作截止 ' + d; },
      yourCampaign: '合作进度',
      stillChoosing: '可选博主',
      backupsHead: '备选博主',
      shootOn: '拍摄',
      deliveryOn: '寄送',
      postedOn: '发布于',
      measuredOn: '统计日期',
      platformCol: '平台',
      platformsLabel: '发布平台',
      colCreator: '博主', colProfiles: '主页', colFee: '费用',
      stageLabel: '当前进度',
      nextLabel: '下一步',
      nextUp: {
        confirmed: '安排拍摄日期', pending_visit: '拍摄',
        pending_draft: '初稿制作中', reviewing: '等您确认',
        changes: '修改中', scheduled: '即将发布',
        posted: '7 天后提供数据'
      },
      tbc: '待定',
      amountLabel: '金额',
      detailsLabel: '合作详情',
      creatorsLabel: '博主人数',
      dueLabel: '合作截止',
      pdf: 'PDF ↗',
      pdfFail: '暂时无法打开发票，请刷新页面后再试。',
      pic: '联系人',
      goLive: '发布日期',
      viewPost: '查看帖子',
      viewPostOn: function (platform, key) { return key === 'xhs' ? '查看小红书笔记' : '查看' + platform + '帖子'; },
      captionLabel: '文案',
      openDraft: '打开初稿',
      noteLabel: '需要修改的内容',
      approve: '通过',
      askChanges: '需要修改',
      sendRequest: '提交修改',
      theClient: '客户',
      approvedBy: function (who, when) { return who + '已通过' + (when ? '（' + when + '）' : '') + '。'; },
      proceededBy: function (who, when) { return '已由' + who + '确认推进' + (when ? '（' + when + '）' : '') + '。'; },
      changesBy: function (who, when) { return who + '提出修改' + (when ? '（' + when + '）' : '') + '。'; },
      reviewThanks: '已收到，团队将跟进处理。',
      needNote: '请说明需要修改的内容。',
      saveFailed: '保存失败，请重试。',
      selectionClosed: '选择已截止，请联系您的 ADspace 客户经理。',
      unavailable: '暂不可用，请在下方选择替补。',
      results: '数据',
      resultsHead: '合作成效',
      placements: '发布数', cpe: '单次互动成本',
      impressions: '曝光', engagements: '互动', views: '播放',
      noneYet: '暂无博主。',
      ofPosted: function (a, b) { return '已发布 ' + a + '/' + b; },
      nextShoot: function (d) { return '下次拍摄 ' + d; },
      waitingYou: '待您确认',
      engRate: '互动率', perEng: '单次互动成本', viewsWord: '播放',
      topPost: '表现最佳内容', measuredWord: function (d) { return '统计于 ' + d; }
    }
  });

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
    // No client to name until the link resolves.
    var who = document.querySelector('.brand-for');
    if (who && !(feed && feed.client && feed.client.name)) who.hidden = true;
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
    if (following && window.ADspacePush) window.ADspacePush.relabel();
  }

  $('langToggle').addEventListener('click', function () { setLang(lang === 'en' ? 'zh' : 'en'); });

  $('amountPdf').addEventListener('click', function (e) {
    if (!this.getAttribute('data-private')) return;
    e.preventDefault();
    var tab = window.open('', '_blank'), note = $('amountMsg');
    note.hidden = true;
    db.functions.invoke('sign-download', { body: { token: TOKEN, passcode: passcode || null } }).then(function (r) {
      var u = r && r.data && r.data.url;
      if (r.error || !u) throw new Error('no-url');
      if (tab) tab.location.href = u; else location.href = u;
    }).catch(function () {
      if (tab) tab.close();
      // A client page never shows a database message: one line, in its language.
      note.textContent = t().pdfFail; note.hidden = false;
    });
  });

  // ---- Load ---------------------------------------------------------------
  function load() {
    if (!db) { showState('Not connected', 'This portal is not set up.', false); return; }
    if (!TOKEN) { showState(t().notFound, t().notFoundText, false); return; }

    /* SST is a setting (js/money.js): read beside the campaign, never after it. */
    var rates = MON.load ? MON.load() : Promise.resolve();
    db.rpc('get_campaign', { p_token: TOKEN, p_passcode: passcode })
      .then(function (r) { return rates.then(function () { return r; }); }).then(function (r) {
      /* A client page never shows a database message (audit, 2026-10-03). */
      if (r.error) { showState(t().failTitle, t().failText, false); return; }
      var d = r.data || {};
      if (d.error === 'not-found') {
        /* A long link from before the short keys: the new key replaces it in
           the address and the page loads on that. */
        var moved = window.ADspaceAPI && window.ADspaceAPI.movedKey;
        (moved ? moved('selection', TOKEN) : Promise.resolve(null)).then(function (next) {
          if (!next || next === TOKEN) { showState(t().notFound, t().notFoundText, false); return; }
          TOKEN = next;
          var q = new URLSearchParams(location.search); q.set('k', next);
          history.replaceState(null, '', location.pathname + '?' + q.toString() + location.hash);
          load();
        });
        return;
      }
      if (d.error === 'passcode') {
        // The gate knows whose campaign it is guarding, so say so.
        if (d.client) $('clientName').textContent = d.client;
        showState(t().passTitle, t().passText, true);
        if (passcode) $('stateMsg').textContent = t().passWrong;
        return;
      }
      feed = d;
      // The link has proved itself: the media pass first, then the files.
      var M = window.ADspaceMedia;
      (M && M.pass ? M.pass({ campaign: TOKEN, passcode: passcode || null }) : Promise.resolve()).then(function () {
        $('stateBox').hidden = true;
        document.body.classList.remove('is-plain');
        build();
        follow();
      });
    });
  }

  /* Notifications on this device for this campaign (js/push.js): offered
     once the link has proved which campaign it is. */
  var following = false;
  function follow() {
    var P = window.ADspacePush;
    if (!P || following) return;
    following = true;
    P.setup({ audience: 'client', ref: function () { return TOKEN; }, lang: function () { return lang; },
              sw: '/creators/sw.js', scope: '/creators/' });
    P.control(function () { return t().push; });
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

    /* The page's own heading. A campaign whose name renders as nothing left
       the client looking at a blank line where the job should be. */
    var title = String(((lang === 'zh' && c.title_zh) ? c.title_zh : c.title) || '').trim();
    if (!title || title === '0' || title === 'null' || title === 'undefined') title = t().untitled;
    $('campTitle').textContent = title;
    /* The client portal's name card (2026-10-03): the client's mark, the
       job's name, and whose it is under it; the bar no longer names them. */
    var mark = $('campMark');
    if (mark) {
      var ini = window.ADspaceState ? window.ADspaceState.initials(client.name || '') : '';
      if (client.logo_url) {
        mark.className = 'rec-mark has-logo';
        mark.innerHTML = '<img src="' + esc(client.logo_url) + '" alt="">';
        mark.querySelector('img').addEventListener('error', function () { mark.className = 'rec-mark'; mark.textContent = ini; });
      } else { mark.className = 'rec-mark'; mark.textContent = ini; }
    }
    if ($('campMeta')) $('campMeta').textContent = client.name || '';
    var forBar = document.querySelector('.brand-for');
    if (forBar) forBar.hidden = true;
    var purpose = (lang === 'zh' && c.purpose_zh) ? c.purpose_zh : c.purpose;
    $('campPurpose').textContent = purpose || '';
    $('campPurpose').hidden = !purpose;
    var brief = (lang === 'zh' && c.brief_zh) ? c.brief_zh : c.brief;
    $('campBrief').textContent = brief || '';
    $('campBrief').hidden = !brief;
    // The engagement in one line: how many creators, when, which invoice.
    var facts = [[t().creatorsLabel, String(c.slots || 0)]];
    if (c.deadline) facts.push([t().dueLabel, fmtDate(c.deadline)]);
    if (c.invoice_no) facts.push([t().invoice, c.invoice_no]);
    $('engageFacts').innerHTML = facts.map(function (f) {
      return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
    }).join('');

    /* The fold's own head. The label names what is behind it, and the summary
       carries the one fact with a consequence — the date — so it is readable
       while the card is shut and the client is not made to open a card to
       find out when this is due. A date needs no label, because a date reads as
       one; where the campaign has none the count takes its place with its own
       word, since a shut fold whose summary is blank is a fold with dead space
       where the reason to open it should be. */
    $('engageLabel').textContent = t().detailsLabel;
    $('engageSum').textContent = c.deadline ? fmtDate(c.deadline)
      : (c.slots ? t().creatorsLabel + ' ' + c.slots : '');

    if (c.state === 'draft') { showState(t().closed, t().closedText, false); return; }

    $('app').hidden = false;
    if (window.ADspaceGuide) window.ADspaceGuide.offer('creators', GUIDE);

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
  /* How many creators are numbered above the list still to choose from, so
     its numbers carry on rather than start again at 1 (audit SEL-4). */
  var listedAbove = 0;

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
    $('chooseHead').textContent = backupStage() ? t().backupsHead : t().stillChoosing;
    $('bookingHead').textContent = t().yourCampaign;
    paintStanding(booked);
    listedAbove = rows.length;
    /* What the client owes leads the page (the client pages refresh,
       2026-10-07): a draft waiting on them is its own card above the
       results, and its creator leaves the list below while it waits, so
       one booking is drawn once (audit SEL-1, 2026-10-08); the list keeps
       its numbers, the card carrying the one it left. */
    var owed = booked.filter(owesClient);
    var need = $('needBox');
    if (need) {
      need.innerHTML = '';
      need.hidden = !owed.length;
      owed.forEach(function (o) { need.appendChild(bookingRow(o, { need: true, no: rows.indexOf(o) + 1 })); });
    }
    if (!rows.length) return;

    /* With one post live, the campaign's results are that post's figures:
       its own table under the booking said them a second time (SEL-3). */
    var sole = booked.filter(function (o) {
      return figuresIn((o.posts || []).filter(function (p) { return p.post_url; }));
    });
    var soleId = sole.length === 1 && (sole[0].posts || []).filter(function (p) { return p.post_url; }).length === 1
      ? sole[0].id : null;

    var box = $('bookingList');
    box.innerHTML = '';
    rows.forEach(function (o, i) {
      if (need && owed.indexOf(o) > -1) return;
      box.appendChild(bookingRow(o, { no: i + 1, sole: o.id === soleId }));
    });

    var sub = booked.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    var c = feed.campaign || {};
    $('bookedTotals').innerHTML = booked.length ? totalsHtml(sub) : '';
    $('amountFold').hidden = !booked.length;
    $('amountLabel').textContent = t().amountLabel;
    $('amountPdf').hidden = !c.invoice_url;
    /* A private invoice has no address of its own: the press asks
       sign-download for a five-minute link with this page's own key. */
    $('amountPdf').href = c.invoice_url && !/^private\//.test(c.invoice_url) ? c.invoice_url : '#';
    $('amountPdf').setAttribute('data-private', /^private\//.test(c.invoice_url || '') ? '1' : '');
    $('amountPdf').textContent = t().pdf;
    paintRollup(booked);
  }

  /* Folded shut every time the page loads, so the figure is shown on purpose
     rather than by default. */
  $('amountToggle').addEventListener('click', function () {
    var open = $('bookedTotals').hidden;
    $('bookedTotals').hidden = !open;
    this.setAttribute('aria-expanded', String(open));
    this.classList.toggle('is-open', open);
  });

  /* The detail card. Shut when the page opens, because the creators the client
     came to choose are below it; opening and shutting is the same move every
     other fold in this portal makes, so the card grows and collapses in place
     rather than blinking away. */
  $('engageToggle').addEventListener('click', function () {
    var shut = $('engageCard').classList.toggle('is-shut');
    this.setAttribute('aria-expanded', String(!shut));
  });

  /* Where the campaign stands, on its own head card: how many of the booked
     creators are live, one part of the bar a creator in their state's dot
     colour, the words under it, and the next shoot. Worked out from the
     bookings on every paint; nothing is stored. */
  var ORDER = ['confirmed', 'pending_visit', 'pending_draft', 'changes', 'reviewing', 'scheduled', 'posted', 'completed'];
  var DOT = { 'is-ok': 'ok', 'is-live': 'ok', 'is-warn': 'wait', 'is-danger': 'late', 'is-off': 'off' };
  function dotOf(state) { return DOT[toneOf(state)] || 'wait'; }
  function paintStanding(booked) {
    var box = $('campStanding');
    if (!box) return;
    box.hidden = !booked.length;
    if (!booked.length) { box.innerHTML = ''; return; }
    var rank = function (o) { var i = ORDER.indexOf(o.state); return i < 0 ? 0 : i; };
    var bars = booked.slice().sort(function (a, b) { return rank(b) - rank(a); });
    var live = booked.filter(function (o) { return o.state === 'posted' || o.state === 'completed'; }).length;
    var counts = [];
    bars.forEach(function (o) {
      var w = chipFor(o), hit = counts.filter(function (c) { return c.w === w; })[0];
      if (hit) hit.n++; else counts.push({ w: w, n: 1, dot: dotOf(o.state) });
    });
    var today = new Date().toISOString().slice(0, 10);
    var shoots = booked.filter(function (o) { return o.visit_date && o.visit_date >= today &&
      ['confirmed', 'pending_visit'].indexOf(o.state) > -1; })
      .map(function (o) { return o.visit_date; }).sort();
    var seeding = (feed.campaign || {}).push_format === 'seeding';
    box.innerHTML =
      '<p class="cx-standing-line"><b>' + esc(t().ofPosted(live, booked.length)) + '</b>' +
        (shoots.length && !seeding ? '<span>' + esc(t().nextShoot(fmtDate(shoots[0]))) + '</span>' : '') + '</p>' +
      '<div class="cx-track" aria-hidden="true">' + bars.map(function (o) {
        return '<i class="is-' + dotOf(o.state) + '"></i>'; }).join('') + '</div>' +
      '<p class="cx-legend">' + counts.map(function (c) {
        return '<span><i class="cx-dot is-' + c.dot + '"></i>' + esc(c.w) + ' ' + c.n + '</span>'; }).join('') + '</p>';
  }

  /* A draft the client is asked to decide on: theirs, and only once it has
     something to open. */
  function owesClient(o) { return o.state === 'reviewing' && hasDraft(o); }

  /* The campaign's numbers, added up the way the console adds them: every
     post that is live, against what the live creators cost. One figure
     leads (views, else impressions); the rest sit under it with their
     glyphs, and the engagement rate is engagements over impressions. Once
     two posts or more are live, the best of them leads under the figures
     with its cover; with one, its own card below already shows it. */
  function paintRollup(booked) {
    var live = booked.filter(function (o) { return o.state === 'posted' || o.state === 'completed'; });
    var rows = [];
    live.forEach(function (o) { (o.posts || []).forEach(function (p) { if (p.post_url) rows.push({ p: p, o: o }); }); });
    var hasNums = rows.some(function (r) { var p = r.p; return p.impressions != null || p.engagements != null || p.views != null; });
    $('clientRollup').hidden = !rows.length || !hasNums;
    if (!rows.length || !hasNums) return;
    var sum = function (k) { return rows.reduce(function (s, r) { return s + Number(r.p[k] || 0); }, 0); };
    var imp = sum('impressions'), eng = sum('engagements'), vie = sum('views');
    var spend = live.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    var I = window.ADspaceIcons;
    var ic = function (n) { return I ? I.svg(n) : ''; };
    var fig = function (glyph, label, value) {
      return '<div><dt>' + ic(glyph) + esc(label) + '</dt><dd>' + esc(String(value)) + '</dd></div>';
    };
    var lead = vie ? ['eye', t().viewsWord, vie] : ['layers', t().impressions, imp];
    var measured = rows.map(function (r) { return r.p.measured_at; }).filter(Boolean).sort().pop();
    $('rollupHead').innerHTML = '<span>' + esc(t().resultsHead) + '</span>' +
      (measured ? '<span class="cx-quiet">' + esc(t().measuredWord(fmtDate(String(measured).slice(0, 10)))) + '</span>' : '');
    var figs = [];
    if (vie) figs.push(fig('layers', t().impressions, imp.toLocaleString()));
    figs.push(fig('heart', t().engagements, eng.toLocaleString()));
    if (imp && eng) figs.push(fig('percent', t().engRate, (Math.round(eng / imp * 1000) / 10).toFixed(1) + '%'));
    if (eng) figs.push(fig('tag', t().perEng, money2(spend / eng)));
    var top = '';
    if (rows.length > 1) {
      var best = rows.slice().sort(function (a, b) {
        return Number(b.p.views || b.p.engagements || 0) - Number(a.p.views || a.p.engagements || 0); })[0];
      var bp = best.p, cover = coverOf(best.o);
      top = '<div class="cx-post">' +
        '<p class="cx-eyebrow">' + esc(t().topPost) + '</p>' +
        '<div class="cx-post-row' + (cover ? '' : ' is-bare') + '">' + cover +
          '<div class="cx-post-who"><b>' + esc(best.o.name) + '</b>' +
            '<span class="cx-plat">' + (I ? I.platform(platKey(bp.platform)) : '') + esc(platWord(bp.platform)) +
              (bp.published_at ? ' · ' + esc(fmtDate(bp.published_at)) : '') + '</span>' +
            '<span class="cx-mini">' +
              (bp.views != null ? '<span>' + ic('eye') + Number(bp.views).toLocaleString() + '</span>' : '') +
              (bp.engagements != null ? '<span>' + ic('heart') + Number(bp.engagements).toLocaleString() + '</span>' : '') +
            '</span></div></div>' +
        '<a class="btn btn-sm cx-postbtn" href="' + esc(absUrl(bp.post_url)) + '" target="_blank" rel="noopener">' +
          esc(t().viewPostOn(platWord(bp.platform), platKey(bp.platform))) + EXT_ICON + '</a>' +
      '</div>';
    }
    $('clientTally').innerHTML =
      '<p class="cx-hero"><b>' + esc(Number(lead[2]).toLocaleString()) + '</b><span>' + ic(lead[0]) + esc(lead[1]) + '</span></p>' +
      '<dl class="cx-figs">' + figs.join('') + '</dl>' + top;
  }

  /* A booking's picture: the first image the creator handed in, else the
     first video at its opening frame. Nothing where neither is held. */
  function coverOf(o) {
    var files = o.files || [];
    var img = files.filter(function (f) { return f.kind === 'image'; })[0];
    if (img) return '<span class="cx-cover"><img src="' + esc(img.url) + '" alt="" loading="lazy"></span>';
    var vid = files.filter(function (f) { return f.kind === 'video'; })[0];
    if (vid && window.ADspaceMedia) return '<span class="cx-cover">' + ADspaceMedia.tag(vid.url, 'muted playsinline preload="metadata"') + '</span>';
    return '';
  }

  function chipFor(o) {
    var c = feed.campaign || {};
    var key = o.state;
    if (key === 'pending_visit' && c.push_format === 'seeding') key = 'pending_delivery';
    return t().step[key] || key;
  }

  // The same colour the console gives the same state.
  function toneOf(s) {
    return window.ADspaceWords.tone(s) || 'is-warn';
  }

  /* The booking's six steps under its creator's name, each named, as the
     creator's own page draws them (ADspaceIcons.journey), placed by the one
     map the console shares (ADspaceIcons.stepOf). */
  function stepsOf(o) {
    var at = window.ADspaceIcons ? window.ADspaceIcons.stepOf(o.state) : null;
    if (at == null) return '';
    var words = t().journey.slice();
    if ((feed.campaign || {}).push_format === 'seeding') words[1] = t().journeyDelivery;
    return window.ADspaceIcons.journey(words, at);
  }
  var FACT_ICON = {};

  function bookingRow(o, opts) {
    opts = opts || {};
    var c = feed.campaign || {};
    var seeding = c.push_format === 'seeding';
    var row = document.createElement('div');
    /* Theirs to act on: drawn whole in the card at the top of the page,
       and left out of the list below while it waits. */
    var mine = opts.need === true;
    row.className = 'booking' + (mine ? ' cx-need' : '') + (o.state === 'withdrawn' ? ' is-off' : '');
    var icon = function (n) { return window.ADspaceIcons ? window.ADspaceIcons.svg(n) : ''; };
    FACT_ICON[t().shootOn] = 'camera'; FACT_ICON[t().deliveryOn] = 'box'; FACT_ICON[t().postedOn] = 'check';
    FACT_ICON[t().platformsLabel] = 'megaphone'; FACT_ICON[t().goLive] = 'calendar'; FACT_ICON[t().nextLabel] = 'hourglass';

    /* One line of small grey text left most of the card empty and made the
       client hunt for the date. The same facts as a labelled grid fill the
       card and read at a glance. */
    var live = o.state === 'posted' || o.state === 'completed';
    var posts = (o.posts || []).filter(function (p) { return p.post_url; });
    var facts = [];
    if (o.state !== 'withdrawn') {
      // Once it is out, when it went out is the date that matters. Before
      // that, the shoot is the date everyone is planning around. Where the
      // platforms went out on different days and the figures are in, the
      // results table dates each post, so the card does not say one again.
      var wentOut = live && (o.posts || []).map(function (p) { return p.published_at; })
        .filter(Boolean).sort()[0];
      if (wentOut && figuresIn(posts) && byDay(posts)) {
        /* said by the table */
      } else if (wentOut) {
        facts.push([t().postedOn, fmtDate(wentOut)]);
      } else if (!live) {
        facts.push([seeding ? t().deliveryOn : t().shootOn,
          o.visit_date ? fmtDate(o.visit_date) + (o.visit_time ? ', ' + o.visit_time : '') : t().tbc]);
      }
      var plats = platsOf(o);
      if (plats.length) facts.push([t().platformsLabel, plats.join(' · ')]);
      if (o.planned_publish && !live) facts.push([t().goLive, fmtDate(o.planned_publish)]);
      // The one thing a chip cannot say: what happens after this. The card
      // at the top of the page says it in its own heading.
      var next = t().nextUp[o.state];
      if (next && !mine) facts.push([t().nextLabel, next]);
    }
    var factsHtml = facts.length ? '<dl class="booking-facts cx-facts">' + facts.map(function (f) {
      return '<div><dt>' + icon(FACT_ICON[f[0]]) + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
    }).join('') + '</dl>' : '';

    row.innerHTML =
      (mine ? '<p class="cx-eyebrow"><i class="cx-dot is-wait"></i>' + esc(t().waitingYou) + '</p>' : '') +
      '<div class="booking-head">' +
        /* A creator is known by their number on the call (the user,
           2026-10-07: "The creator needs numbering not profile photos"). */
        (opts.no ? '<span class="rowno">' + opts.no + '</span>' : '') +
        '<b>' + esc(o.name) + '</b>' +
        '<span class="chip-state ' + toneOf(o.state) + '">' + esc(chipFor(o)) + '</span>' +
        (o.is_replacement ? '<span class="tag-rep">' + esc(t().replacement) + '</span>' : '') +
      '</div>' +
      (o.state === 'withdrawn' ? '' : stepsOf(o)) +
      factsHtml +
      (o.state === 'withdrawn' ? '<div class="booking-meta">' + esc(t().unavailable) + '</div>' : '') +
      postLinks(posts) +
      (opts.sole ? '' : resultsOf(posts) || '') +
      /* Once the post is out, who approved it is history the console keeps;
         the card leads with the post (the user, 2026-09-27: "Is it necessary
         to keep the approved there"). */
      (live ? '' : decidedLine(o)) +
      (mine ? draftPreview(o) + decisionBlock(o) : '');

    if (mine) wireDecision(row, o);
    return row;
  }

  /* The post itself, one button a platform, named for where it opens: the
     thing a client comes back to the card for once it is live. */
  function postLinks(posts) {
    if (!posts.length) return '';
    return '<div class="postlinks">' + posts.map(function (p) {
      return '<a class="btn btn-sm postlink" href="' + esc(absUrl(p.post_url)) + '" target="_blank" rel="noopener">' +
        esc(t().viewPostOn(platWord(p.platform), platKey(p.platform))) + EXT_ICON + '</a>';
    }).join('') + '</div>';
  }

  /* One row per platform once there are figures: when the numbers were taken,
     and the numbers. The measured date is what makes a figure read a year
     later still make sense. Before the figures there is no table: the post
     is the button above it and the date is the card's own Posted, and a table
     of the two said both again. The date a post went out is a column only
     where the platforms went out on different days. */
  function figuresIn(posts) {
    return posts.some(function (p) {
      return p.impressions != null || p.engagements != null || p.views != null;
    });
  }
  function byDay(posts) {
    var days = {};
    posts.forEach(function (p) { days[p.published_at || ''] = true; });
    return Object.keys(days).length > 1;
  }
  function resultsOf(posts) {
    if (!posts.length || !figuresIn(posts)) return '';
    var dated = byDay(posts);
    var num = function (v) { return v == null ? '<span class="muted">–</span>' : Number(v).toLocaleString(); };
    var measured = function (p) {
      if (p.measured_at) return fmtDate(p.measured_at);
      if (p.published_at && p.window_days) {
        var d = new Date(p.published_at + 'T00:00:00');
        d.setDate(d.getDate() + Number(p.window_days));
        return fmtDate(d.toISOString().slice(0, 10));
      }
      return '';
    };
    return '<div class="results-wrap"><table class="results">' +
      '<thead><tr>' +
        '<th>' + esc(t().platformCol) + '</th>' +
        (dated ? '<th>' + esc(t().postedOn) + '</th>' : '') +
        '<th>' + esc(t().measuredOn) + '</th>' +
        '<th class="num">' + esc(t().impressions) + '</th>' +
        '<th class="num">' + esc(t().engagements) + '</th>' +
        '<th class="num">' + esc(t().views) + '</th>' +
      '</tr></thead><tbody>' +
      posts.map(function (p) {
        return '<tr>' +
          '<td data-l="' + esc(t().platformCol) + '"><b class="results-plat">' + esc(platWord(p.platform)) + '</b></td>' +
          (dated ? '<td data-l="' + esc(t().postedOn) + '">' + (p.published_at ? esc(fmtDate(p.published_at)) : '<span class="muted">–</span>') + '</td>' : '') +
          '<td data-l="' + esc(t().measuredOn) + '">' + esc(measured(p)) + '</td>' +
          '<td class="num" data-l="' + esc(t().impressions) + '">' + num(p.impressions) + '</td>' +
          '<td class="num" data-l="' + esc(t().engagements) + '">' + num(p.engagements) + '</td>' +
          '<td class="num" data-l="' + esc(t().views) + '">' + num(p.views) + '</td>' +
        '</tr>';
      }).join('') +
      '</tbody></table></div>';
  }

  function absUrl(u) {
    u = String(u || '').trim();
    if (!u) return '';
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(u) ? u : 'https://' + u.replace(/^\/+/, '');
  }

  // ---- Draft review -------------------------------------------------------

  /* A draft the team released is the creator's own files, a pasted link, or
     both. get_campaign sends neither until the release, so a card with
     nothing to open is a card the client is not being asked to decide on. */
  function hasDraft(o) { return !!(o.draft_url || (o.files || []).length); }

  /* The work itself, on the card. A 9:16 video is the main object being
     reviewed, not a thumbnail that asks for another tab. */
  function draftPreview(o) {
    var files = o.files || [];
    var media = files.map(function (f) {
      if (f.kind === 'video') {
        return ADspaceMedia.tag(f.url, 'controls playsinline preload="metadata"');
      }
      if (f.kind === 'image') return '<img src="' + esc(f.url) + '" alt="" loading="lazy">';
      return '<a class="btn btn-sm" href="' + esc(f.url) + '" target="_blank" rel="noopener">' +
        esc(f.name || 'Open file') + '</a>';
    }).join('');
    return '<div class="client-draft-preview">' +
      (media ? '<div class="client-draft-media">' + media + '</div>' : '') +
      (o.caption ? '<div class="draft-caption"><span class="field-label">' + esc(t().captionLabel) +
        '</span><p>' + esc(o.caption).replace(/\n/g, '<br>') + '</p></div>' : '') +
      (o.draft_url ? '<a class="btn btn-sm" href="' + esc(absUrl(o.draft_url)) +
        '" target="_blank" rel="noopener">' + esc(t().openDraft) + EXT_ICON + '</a>' : '') +
      '</div>';
  }

  /* What the client last said, kept on the card after the step has moved on.
     Approving used to leave no trace at all: the chip went from Reviewing to
     Scheduled and nothing on the page said who had approved it or when, so
     the one decision the client makes was the one nothing recorded. The note
     they wrote rides with a change request, because it is what the next
     round is answering. */
  function decidedLine(o) {
    var r = o.review;
    if (!r || !r.decision) return '';
    var when = r.at ? new Date(r.at) : null;
    var stamp = when ? when.toLocaleString(lang === 'zh' ? 'zh-CN' : 'en-GB',
      { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).replace(/\bSep\b/, 'Sept') : '';
    /* An approval the team gave on the client's behalf names the colleague
       who proceeded, never as if the client had approved it. */
    var word = r.decision !== 'approved' ? t().changesBy : r.by_team ? t().proceededBy : t().approvedBy;
    return '<p class="approve-state booking-decided">' +
      esc(word(r.reviewer || t().theClient, stamp)) + '</p>' +
      (r.decision !== 'approved' && r.note
        ? '<div class="approve-note">' + esc(r.note) + '</div>' : '');
  }

  /* The name a decision is recorded under lives in js/decide.js now, with the
     control that asks for it. It was a private pair of helpers here and
     another pair in js/review.js over the same localStorage key, which is the
     shape a rule drifts in. */

  /* Content Review decides in place, and this is the same decision, so it is
     the same component: Approve, Request changes, and a note that opens under
     them. It used to be a button that opened the draft in a window over the
     card — a frame to open and a frame to dismiss before the client could say
     anything, on a card that is already showing them what they are deciding
     on. */
  function decisionBlock(o) {
    return '<div class="approve">' +
      '<div class="approve-row">' +
        '<button class="btn btn-approve" type="button" data-act="approve">' + esc(t().approve) + '</button>' +
        '<button class="btn btn-changes" type="button" data-act="changes">' + esc(t().askChanges) + '</button>' +
      '</div>' +
      '<div class="changebox">' +
        '<textarea class="textarea" rows="3" aria-label="' + esc(t().noteLabel) +
          '" placeholder="' + esc(t().needNote) + '"></textarea>' +
        /* Drawn only where we do not already hold the name, so a client who
           has decided on something before is not asked twice. */
        (window.ADspaceDecide.known() ? '' :
          '<input class="input changebox-who" type="text" autocomplete="name" aria-label="' +
            esc(t().nameLabel) + '" placeholder="' + esc(t().namePlaceholder) + '">') +
        '<div class="changebox-actions">' +
          '<button class="btn btn-sm btn-primary" type="button" data-act="send">' + esc(t().sendRequest) + '</button>' +
          '<button class="btn btn-sm" type="button" data-act="cancel">' + esc(t().cancel) + '</button>' +
        '</div>' +
      '</div>' +
      '<div class="approve-state" role="status"></div>' +
    '</div>';
  }

  function wireDecision(row, o) {
    var wrap  = row.querySelector('.approve');
    var box   = wrap.querySelector('.changebox');
    var note  = wrap.querySelector('.textarea');
    var who   = wrap.querySelector('.changebox-who');
    var state = wrap.querySelector('.approve-state');
    var busy  = false;

    function say(text, err) {
      state.textContent = text || '';
      state.classList.toggle('is-err', !!err);
    }
    function lock(on) {
      busy = on;
      Array.prototype.forEach.call(wrap.querySelectorAll('.btn'), function (b) { b.disabled = on; });
    }

    /* The name is asked inside Approve, so the client never leaves the card
       they are deciding on. A name already given opens nothing. */
    var approveBtn = wrap.querySelector('[data-act="approve"]');
    var asker = window.ADspaceDecide.nameBox(approveBtn, {
      label: t().nameLabel, placeholder: t().namePlaceholder, needed: t().nameNeeded
    }, say);

    approveBtn.addEventListener('click', function () {
      if (busy) return;
      box.classList.remove('is-open');
      asker.need(function (name) { send('approved', '', name); });
    });
    wrap.querySelector('[data-act="changes"]').addEventListener('click', function () {
      asker.close();
      box.classList.add('is-open');
      note.focus();
    });
    box.querySelector('[data-act="cancel"]').addEventListener('click', function () {
      box.classList.remove('is-open');
      say('');
    });
    box.querySelector('[data-act="send"]').addEventListener('click', function () {
      if (busy) return;
      var text = (note.value || '').trim();
      if (!text) { say(t().needNote, true); note.focus(); return; }
      /* The note box is already open, so the name it may still need is a
         field inside it rather than one growing out of a button on the row
         behind it. Same question, asked where the client is looking. */
      var name = window.ADspaceDecide.known();
      if (!name) {
        name = (who.value || '').trim();
        if (!name) { say(t().nameNeeded, true); who.focus(); return; }
        window.ADspaceDecide.keep(name);
      }
      send('changes', text, name);
    });

    /* A decision with nobody's name on it is worth nothing to either side, so
       the name is asked once and kept, exactly as Content Review asks it. It
       is asked at the moment somebody decides rather than as a field on every
       card, because a reader who is not deciding anything was being asked to
       fill one in — but it is asked on this page now, not in a browser
       dialog: see js/decide.js. By here it is settled and passed in. */
    function send(decision, text, name) {
      lock(true);
      say('');
      db.rpc('review_draft', {
        p_token: TOKEN, p_option: o.id, p_decision: decision,
        p_note: text || null, p_reviewer: name, p_passcode: passcode
      }).then(function (r) {
        var d = (r && r.data) || {};
        if ((r && r.error) || d.error) {
          lock(false);
          say(d.error === 'closed' ? t().closedText : t().notSent, true);
          return;
        }
        say(t().reviewThanks);
        load();                     // states have moved, so read them back
      }).catch(function () {
        lock(false);
        say(t().saveFailed, true);
      });
    }
  }

  function fmtDate(d) {
    var dt = new Date(d + 'T00:00:00');
    return dt.toLocaleDateString(lang === 'zh' ? 'zh-CN' : 'en-GB',
      { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
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
    if (!backupsOpen()) return 0;
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
  // Whether the team has asked this client for names in reserve.
  function backupsOpen() { return Boolean((feed.campaign || {}).backups_open); }

  /* What is still choosable. A booked creator has left the shelf; a withdrawn
     one has too, and its slot has already been handed back.

     Once every slot is taken the offer is over, so the creators nobody picked
     are not an offer any more: they are a long list of disabled ticks under
     the campaign, which is what the client's page looked like the moment the
     team confirmed. They come back by themselves if a slot reopens, because
     the count is what decides. Backups are the one reason to keep the list
     alive past that, and only where the team opened them. */
  function choosable() {
    var live = (feed.options || []).filter(function (o) {
      return ['option', 'shortlisted', 'backup'].indexOf(o.state) > -1;
    });
    /* Closed by the database the moment the slots filled, and open again
       only when the team reopens it (the user, 2026-09-27): a slot freed by a
       withdrawal waits for the team. Backups stay namable where the team
       opened them and every slot is taken. */
    if ((feed.campaign || {}).selection_closed) return slotsLeft() <= 0 && backupsOpen() ? live : [];
    if (slotsLeft() > 0) return live;
    return backupsOpen() ? live : [];
  }
  // True once the slots are full and the list is only still there for backups.
  function backupStage() { return slotsLeft() <= 0 && backupsOpen() && choosable().length > 0; }

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
    // The progress card already says how to choose; only a reopened slot
    // needs a line here.
    $('chooseHint').hidden = !priority;
    $('chooseHint').textContent = priority ? t().priorityNotice : '';
    $('chooseHint').classList.toggle('is-priority', priority);

    /* A list, not cards. Ten is a page of cards and forty is an afternoon of
       scrolling; the decision is made by opening profiles and comparing rates,
       and a row puts both within reach without moving the eye.

       On a screen wide enough to compare on, the columns are named: a fee and
       a set of placements with nothing over them is a number the client has to
       work out what to read against. Below the phone line the header leaves
       and the row stacks, because four labels over a 358px row is furniture. */
    var head = document.createElement('div');
    head.className = 'crow crow-head';
    head.innerHTML =
      '<span class="crow-no"></span><span class="crow-tick-cell"></span>' +
      '<div class="crow-name">' + esc(t().colCreator) + '</div>' +
      '<div class="crow-plat">' + esc(t().platformsLabel) + '</div>' +
      '<div class="crow-links">' + esc(t().colProfiles) + '</div>' +
      '<div class="crow-rate">' + esc(t().colFee) + '</div>' +
      (backupsOpen() ? '<span class="crow-backup-cell">' + esc(t().backup) + '</span>' : '');
    grid.appendChild(head);

    options.forEach(function (o, idx) {
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

      /* The fee is for a stated set of platforms, so the rate beside it cannot
         be read without them. It sits under the name as the row's meta line,
         where every other list in the portal puts what qualifies the money. */
      var plats = platsOf(o);

      row.innerHTML =
        '<span class="rowno crow-no">' + (listedAbove + idx + 1) + '</span>' +
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
        /* Its own column on a screen wide enough to compare on, and back
           under the name on a phone. A fee is quoted for a stated set of
           placements, so the two are read against each other. */
        '<div class="crow-plat">' +
          (plats.length
            ? '<span>' + esc(t().platformsLabel) + '</span>' + esc(plats.join(' · '))
            : '') +
        '</div>' +
        '<div class="crow-links">' + links + '</div>' +
        '<div class="crow-rate">' + money(o.rate) + '</div>' +
        (backupsOpen()
          ? '<button class="crow-backup' + (pick === 'backup' ? ' is-on' : '') + '" type="button">' +
            esc(pick === 'backup' ? t().isBackup : t().backup) + '</button>'
          : '');

      row.querySelector('.crow-tick').addEventListener('click', function () {
        if (chosen[o.id] === 'selected') delete chosen[o.id];
        else if (countSelected() < slots) chosen[o.id] = 'selected';
        redraw();
      });
      var bk = row.querySelector('.crow-backup');
      if (bk) bk.addEventListener('click', function () {
        if (chosen[o.id] === 'backup') delete chosen[o.id];
        else chosen[o.id] = 'backup';
        redraw();
      });
      grid.appendChild(row);
    });

    remember(options.map(function (o) { return o.id; }));
  }

  function platLabel(p) {
    return { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' }[p] || p;
  }
  /* A placement is stored by its printed name ("rednote", "Instagram") and
     older rows by the key; both read as the key, so both find their word. */
  function platKey(p) {
    var k = { rednote: 'xhs', xiaohongshu: 'xhs', instagram: 'instagram', tiktok: 'tiktok', facebook: 'facebook', xhs: 'xhs' };
    return k[String(p || '').trim().toLowerCase()] || p;
  }
  function platWord(p) { var k = platKey(p); return t().platform[k] || platLabel(k); }

  /* What the creator is booked to post on, which is not the same list as the
     profiles they can be looked up on: one fee covers the platforms agreed for
     it, and another creator charges for a second. Read in the reader's own
     language, the way the profile buttons on the same row already are. */
  function platsOf(o) {
    // The console stores the placement by its printed name ("rednote, Instagram"),
    // and older rows carry the key, so both resolve to the same word.
    // Matched without case, because older rows hold what was typed ("RedNote").
    var key = { rednote: 'xhs', xhs: 'xhs', xiaohongshu: 'xhs', instagram: 'instagram', tiktok: 'tiktok', facebook: 'facebook' };
    return String(o.platforms || '').split(',').map(function (s) { return s.trim(); })
      .filter(Boolean).map(function (p) { var k = key[p.toLowerCase()] || p; return t().platform[k] || p; });
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
          /* In the client's words, never the database's. Selection closed
             under them: the page is read again, so the list goes too. */
          msg('confirmMsg', d.error === 'closed' ? t().selectionClosed : t().saveFailed, 'err');
          if (d.error === 'closed') load();
          return;
        }
        shutConfirm();
        showState(t().kicker, t().confirmed, false);
      });
  });

  setLang(lang);
  load();
})();
