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
  var GUIDE = { name: { en: 'Select your creators', zh: '挑选创作者' }, steps: [
    { at: '.cs-tick', text: { en: 'Select the creators for this campaign. Your selection is saved automatically.', zh: '勾选您希望合作的创作者，每次勾选都会自动保存。' } },
    { at: '#confirmBtn', text: { en: 'Press Submit selection once your selection is final.', zh: '选定后，请点「提交选择」。' } }] };
  var db  = API && API.client;
  var $   = function (id) { return document.getElementById(id); };

  function esc(s) { return window.ADspaceWords.esc(s); }

  /* "Prepared for <client>" under the section name, in whichever language the
     page is showing. */
  /* The bar names the client only once the link has said whose campaign it
     is; while it loads it said "Prepared for …" (SELECTION-11). */
  (function () { var f = document.getElementById('clientFor'); if (f) f.hidden = true; })();
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
  function mkt() { return MON.curOf(feed && feed.client); }
  function taxOn() {
    var v = feed && feed.client && feed.client.sst_applies;
    return v === undefined || v === null ? true : v;
  }
  function money(n)  { return MON.money(n, mkt()); }
  function money2(n) { return MON.money2(n, mkt()); }
  /* The mark that says this opens somewhere else: the one leaving mark
     (js/icons.js, loaded first; CR-7). */
  var EXT_ICON = window.ADspaceIcons ? window.ADspaceIcons.svg('out') : '';
  function icon(n) { return window.ADspaceIcons ? window.ADspaceIcons.svg(n) : ''; }
  /* What is booked carries SST at the rate in force when the client last
     confirmed, so a confirmed campaign's total never moves with a later rate
     (the third audit, item 10); a selection still to confirm, today's. */
  function confAt() { return (lastConfirm || (feed && feed.campaign && feed.campaign.confirmed) || {}).at; }
  function sstOf(subtotal, at) { return MON.taxOf(subtotal, mkt(), taxOn(), at); }
  function sstWord(at) { return MON.taxLabel(mkt(), at); }
  /* A client who is not charged tax gets two lines, not three with a zero in
     the middle. */
  function totalsHtml(subtotal, at) {
    var sst = sstOf(subtotal, at);
    return '<div><span>' + esc(t().subtotal) + '</span><span>' + money2(subtotal) + '</span></div>' +
           (sst ? '<div><span>' + esc(sstWord(at)) + '</span><span>' + money2(sst) + '</span></div>' : '') +
           '<div class="is-total"><span>' + esc(t().total) + '</span><span>' + money2(subtotal + sst) + '</span></div>';
  }

  /* Page furniture in both languages. Creator names are already Chinese and
     are never translated; only the words around them are. */
  var T = window.ADspaceWords.of({
    en: {
      kicker: 'Creator Selection',
      openFile: 'Open file', newTag: 'New', accessCode: 'Access code', openCode: 'Open',
      preparedFor: 'Prepared for',
      lang: '中文',
      chooseMore: function (n) { return 'Select ' + n + ' more.'; },
      complete: 'All selected.',
      yourSelection: 'Your selection',
      count: function (a, b) { return a + ' of ' + b + ' selected'; },
      select: 'Select',
      selected: 'Selected',
      backup: 'Backup',
      backupsNeeded: function () { return 'Backup creators are optional.'; },
      backupsDone: 'Backup creators selected.',
      backupCount: function (a, b) { return a + ' of ' + b + ' backups selected'; },
      priorityNotice: 'A creator is unavailable. Please select a replacement; your backups are listed first.',
      priority: 'Priority',
      oneMoreBackup: 'Please select one more backup.',
      replacement: 'Replacement',
      viewProfile: 'View profile',
      viewOn: function (platform) { return 'View ' + platform + ' profile'; },
      platform: { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
      full: 'All creators selected',
      fullLine: 'To select another creator, please remove one from your selection.',
      confirm: 'Submit selection',
      confirmHeading: 'Submit selection',
      /* The selection page's cards and cart (the mockup of 2026-11-25). */
      chooseBy: 'Choose by',
      ofN: function (a, b) { return a + ' of ' + b; },
      viewsLabel: 'Creators shown',
      viewAll: 'All', viewSelected: 'Selected', viewBackup: 'Backups',
      markBackup: 'Mark as backup', markedBackup: 'Marked as backup',
      perUnit: { video: 'per video', graphic: 'per graphic' },
      backupLine: function (names, fee) { return 'Backup: ' + names + ' (' + fee + ', charged only if used)'; },
      backupsN: function (n) { return n + (n === 1 ? ' backup' : ' backups'); },
      inclTax: function (tax) { return 'incl. ' + tax; },
      viewSelection: 'View selection',
      close: 'Close',
      confirmBlurb: '',
      nameLabel: 'Your name',
      /* Just Name. Asking a client for their full name every time they
         approve something reads as an identity check rather than a signature.
         Chinese already said 姓名, which is the same register. */
      namePlaceholder: 'John Doe',
      send: 'Submit',
      cancel: 'Cancel',
      nameNeeded: 'Please enter your name.',
      confirmedBy: function (who, d) { return 'Confirmed by ' + who + ' on ' + d + '. Shoot dates will follow.'; },
      changedSince: function (d) { return 'Changed since the confirmation on ' + d + '.'; },
      subtotal: 'Subtotal',
      total: 'Total',
      totalShort: function (v, tax) { return 'Total ' + v + (tax ? ' incl. ' + tax : ''); },
      invoice: 'Invoice',
      due: function (d) { return 'Campaign due ' + d; },
      yourCampaign: 'Your campaign',
      stillChoosing: 'Choose your creators',
      backupsHead: 'Choose backup creators',
      shootOn: 'Shoot visit',
      deliveryOn: 'Delivery',
      postedOn: 'Posted',
      platformsLabel: 'Posting on',
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
        changes: 'Revision in progress', scheduled: 'Post date',
        posted: 'Results in 7 days'
      },
      tbc: 'To be confirmed',
      amountLabel: 'Amount',
      creatorsLabel: 'Creators',
      dueLabel: 'Campaign due',
      pdf: 'PDF',
      pdfFail: 'Unable to open the invoice. Please refresh the page and try again.',
      pic: 'Contact',
      /* Post date, as the step track names it (2026-10-27, SEL-5). */
      goLive: 'Post date',
      viewPost: 'View post',
      /* The post itself, named for where it lives (the user, 2026-09-27: the
         platform's name alone was "too not obvious"). */
      viewPostOn: function (platform) { return 'View post on ' + platform; },
      captionLabel: 'Caption',
      openDraft: 'Open draft',
      noteLabel: 'Changes required',
      approve: 'Approve',
      askChanges: 'Request changes',
      sendRequest: 'Send request',
      theClient: 'you',
      approvedBy: function (who, when) { return 'Approved by ' + who + (when ? ' on ' + when : '') + '.'; },
      proceededBy: function (who, when) { return 'Confirmed by ' + who + (when ? ' on ' + when : '') + '.'; },
      changesBy: function (who, when) { return 'Changes requested by ' + who + (when ? ' on ' + when : '') + '.'; },
      reviewThanks: 'Thank you. Your response has been received. ADspace will follow up shortly.',
      draftMoved: 'This draft has been updated since the page was opened. The page has been refreshed.',
      needNote: 'Please describe the changes required.',
      selectionClosed: 'Selection is closed. Please contact your ADspace account manager.',
      ratesChanged: 'The rates have been updated. Please review them and submit your selection again.',
      selectionChanged: 'A creator is no longer available. Please review your selection and submit it again.',
      overSlots: function (n) {
        return n > 0 ? 'Only ' + n + ' more ' + (n === 1 ? 'creator' : 'creators') + ' can be selected. Please remove the extra creators and submit your selection again.'
          : 'Every creator for this campaign has been booked. Please contact your ADspace account manager.';
      },
      unavailable: 'Unavailable. Please select a replacement below.',
      results: 'Results',
      resultsHead: 'Campaign results',
      placements: 'Posts', cpe: 'Cost per engagement',
      impressions: 'Impressions', engagements: 'Engagements', views: 'Views',
      noneYet: 'No creators.',
      /* The campaign room (2026-10-07, the client pages refresh). */
      waitingYou: 'Waiting for your approval',
      engRate: 'Engagement rate', perEng: 'Per engagement', viewsWord: 'views',
      topPost: 'Top post', measuredWord: function (d) { return 'Measured ' + d; }
    },
    zh: {
      kicker: '创作者选择',
      openFile: '打开文件', newTag: '新增', accessCode: '访问码', openCode: '打开',
      preparedFor: '致',
      lang: 'EN',
      chooseMore: function (n) { return '再选' + n + '位。'; },
      complete: '已选齐。',
      yourSelection: '您的选择',
      count: function (a, b) { return '已选 ' + a + ' / ' + b; },
      select: '选择',
      selected: '已选',
      backup: '设为备选',
      backupsNeeded: function () { return '备选为可选项。'; },
      backupsDone: '已设定备选创作者。',
      backupCount: function (a, b) { return '已选备选 ' + a + ' / ' + b; },
      priorityNotice: '有一位创作者暂不可用，请选择替补。备选已优先显示。',
      priority: '优先',
      oneMoreBackup: '请再选一位备选。',
      replacement: '替补',
      viewProfile: '查看主页',
      viewOn: function (platform) { return '查看' + platform + '主页'; },
      platform: { xhs: '小红书', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
      full: '名额已满',
      fullLine: '如需选择其他创作者，请先取消一位已选的创作者。',
      confirm: '提交选择',
      confirmHeading: '提交选择',
      chooseBy: '选择截止',
      ofN: function (a, b) { return a + ' / ' + b; },
      viewsLabel: '显示的创作者',
      viewAll: '全部', viewSelected: '已选', viewBackup: '备选',
      markBackup: '设为备选', markedBackup: '已设为备选',
      perUnit: { video: '每条视频', graphic: '每张图文' },
      backupLine: function (names, fee) { return '备选：' + names + '（' + fee + '，仅在启用时收费）'; },
      backupsN: function (n) { return n + '位备选'; },
      inclTax: function (tax) { return '含' + tax; },
      viewSelection: '查看已选',
      close: '关闭',
      confirmBlurb: '',
      nameLabel: '您的姓名',
      namePlaceholder: '陈小明',
      send: '提交',
      cancel: '取消',
      nameNeeded: '请填写姓名。',
      confirmedBy: function (who, d) { return who + ' 已于 ' + d + ' 确认。拍摄日期将随后通知。'; },
      changedSince: function (d) { return '自 ' + d + ' 确认后已有更改。'; },
      subtotal: '小计',
      total: '总计',
      totalShort: function (v, tax) { return '总计 ' + v + (tax ? '（含 ' + tax + '）' : ''); },
      invoice: '发票',
      due: function (d) { return '合作截止 ' + d; },
      yourCampaign: '合作进度',
      stillChoosing: '选择创作者',
      backupsHead: '选择备选创作者',
      shootOn: '拍摄',
      deliveryOn: '寄送',
      postedOn: '发布于',
      platformsLabel: '发布平台',
      stageLabel: '当前进度',
      nextLabel: '下一步',
      nextUp: {
        confirmed: '安排拍摄日期', pending_visit: '拍摄',
        pending_draft: '初稿制作中', reviewing: '待您确认',
        changes: '修改中', scheduled: '发布日期',
        posted: '7天后提供数据'
      },
      tbc: '待确认',
      amountLabel: '金额',
      creatorsLabel: '创作者人数',
      dueLabel: '合作截止',
      pdf: 'PDF',
      pdfFail: '暂时无法打开发票，请刷新页面后再试。',
      pic: '联系人',
      goLive: '发布日期',
      viewPost: '查看帖子',
      viewPostOn: function (platform, key) { return key === 'xhs' ? '查看小红书笔记' : '查看' + platform + '帖子'; },
      captionLabel: '文案',
      openDraft: '打开初稿',
      noteLabel: '需要修改的内容',
      approve: '通过',
      askChanges: '要求修改',
      sendRequest: '提交修改要求',
      theClient: '您',
      approvedBy: function (who, when) { return who + '已通过' + (when ? '（' + when + '）' : '') + '。'; },
      proceededBy: function (who, when) { return '已由' + who + '确认' + (when ? '（' + when + '）' : '') + '。'; },
      changesBy: function (who, when) { return who + '提出修改' + (when ? '（' + when + '）' : '') + '。'; },
      reviewThanks: '谢谢，您的回复已收到，ADspace 团队将尽快跟进。',
      draftMoved: '页面打开后此初稿已更新，页面已刷新。',
      needNote: '请说明需要修改的内容。',
      selectionClosed: '选择已截止，请联系您的 ADspace 客户经理。',
      ratesChanged: '报价已更新，请查看后重新提交。',
      selectionChanged: '部分创作者已无法选择，请重新查看后再次提交。',
      overSlots: function (n) {
        return n > 0 ? '目前只能再选' + n + '位创作者，请取消多选的创作者后重新提交。'
          : '本次合作的创作者名额已全部预订，请联系您的 ADspace 客户经理。';
      },
      unavailable: '暂不可用，请在下方选择替补。',
      results: '数据',
      resultsHead: '合作成效',
      placements: '发布数', cpe: '单次互动成本',
      impressions: '曝光', engagements: '互动', views: '播放',
      noneYet: '暂无创作者。',
      waitingYou: '待您确认',
      engRate: '互动率', perEng: '单次互动成本', viewsWord: '播放',
      topPost: '表现最佳内容', measuredWord: function (d) { return '统计于 ' + d; }
    }
  });

  var lang = 'en';
  function t() { return T[lang]; }

  var LANG_KEY = 'adspace.creators.lang';
  /* A choice made here (the 中文 switch) wins; until one is made the page
     opens in the client's primary contact's language (get_campaign `lang`,
     2026-11-17), never stored as if it were chosen. */
  var langChosen = false;
  try { var saved = localStorage.getItem(LANG_KEY); if (saved && T[saved]) { lang = saved; langChosen = true; } } catch (e) {}

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

  /* Who this device decides as, with Change and Forget, under the name
     card (2026-10-08); its words follow the 中文 switch. */
  var keepPicks = false;
  var whoAs = null;
  function whoWords() { var x = t(); return { as: x.decideAs, change: x.decideChange, forget: x.decideForget, save: x.decideSave, cancel: x.decideCancel, name: x.decideName }; }
  function mountWho() {
    if (whoAs || !window.ADspaceDecide || !window.ADspaceDecide.whoLine) return;
    var host = $('campHead');
    if (host) whoAs = window.ADspaceDecide.whoLine(host, whoWords(), host.querySelector('.rec-id'));
  }
  function setLang(next, keep) {
    lang = next;
    if (whoAs) whoAs.words(whoWords());
    if (keep) { langChosen = true; try { localStorage.setItem(LANG_KEY, lang); } catch (e) {} }
    $('langToggle').textContent = t().lang;
    $('kicker').textContent = t().kicker;
    $('passInput').placeholder = t().accessCode;
    $('passGo').textContent = t().openCode;
    paintPreparedFor();
    document.documentElement.lang = lang === 'zh' ? 'zh' : 'en';
    if (feed) { keepPicks = true; build(); keepPicks = false; }
    if (following && window.ADspacePush) window.ADspacePush.relabel();
  }

  $('langToggle').addEventListener('click', function () { setLang(lang === 'en' ? 'zh' : 'en', true); });

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
  var portalAsked = false;
  /* Back to the client portal, where a signed-in contact came from. */
  function portalBack() {
    var main = document.querySelector('main');
    if (document.getElementById('cpPortalBack') || !main) return;
    var a = document.createElement('a');
    a.id = 'cpPortalBack'; a.className = 'backlink'; a.href = '/client/?tab=campaigns';
    a.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 18l-6-6 6-6"/></svg>' +
      window.ADspaceWords.esc(t().back || 'Back');
    main.insertBefore(a, main.firstChild);
  }
  function load() {
    if (!db) { showState(t().failTitle, t().failText, false); return; }
    if (!TOKEN) { showState(t().notFound, t().notFoundText, false); return; }

    /* Opened by a contact signed in to the client portal (2026-11-08): no
       code is typed and the selection and decisions go under the
       contact's own name. */
    if (!portalAsked && API && API.portalPass) {
      portalAsked = true;
      return API.portalPass('campaign', TOKEN).then(function (pp) {
        if (pp) {
          if (pp.passcode) passcode = pp.passcode;
          if (window.ADspaceDecide && window.ADspaceDecide.sign) window.ADspaceDecide.sign(pp.name);
          portalBack();
        }
        return load();
      });
    }
    /* SST is a setting (js/money.js): read beside the campaign, never after it. */
    var rates = MON.load ? MON.load() : Promise.resolve();
    return db.rpc('get_campaign', { p_token: TOKEN, p_passcode: passcode })
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
      if (d.error === 'locked') {
        showState(t().lockedTitle, window.ADspaceWords.lockedLine(t(), d.minutes), false);
        return;
      }
      if (d.error === 'passcode') {
        // The gate knows whose campaign it is guarding, so say so.
        if (d.client) paintPreparedFor(d.client);
        showState(t().passTitle, t().passText, true);
        if (passcode) $('stateMsg').textContent = t().passWrong;
        return;
      }
      if (!langChosen && (d.lang === 'zh' || d.lang === 'en') && d.lang !== lang) setLang(d.lang);
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
    mountWho();
    var forBar = document.querySelector('.brand-for');
    if (forBar) forBar.hidden = true;
    var purpose = (lang === 'zh' && c.purpose_zh) ? c.purpose_zh : c.purpose;
    $('campPurpose').textContent = purpose || '';
    $('campPurpose').hidden = !purpose;
    var brief = (lang === 'zh' && c.brief_zh) ? c.brief_zh : c.brief;
    $('campBrief').textContent = brief || '';
    $('campBrief').hidden = !brief;
    /* The brief is one shaded line under the head, never folded (the
       mockup of 2026-11-25): the client reads it before choosing. */
    $('campBriefBox').hidden = !brief && !purpose;
    $('campBriefIc').innerHTML = icon('doc');
    paintFacts();

    if (c.state === 'draft') { showState(t().closed, t().closedText, false); return; }

    $('app').hidden = false;
    if (window.ADspaceGuide) window.ADspaceGuide.offer('creators', GUIDE);

    // Seed from whatever the server already holds, so returning to the link
    // shows what was left rather than an empty sheet.
    /* A language switch repaints what is on screen: the picks made since
       the campaign was read stay (they were reseeded from the read and an
       unsaved pick was lost, 2026-10-15). */
    if (!keepPicks) {
      chosen = {};
      options.forEach(function (o) {
        if (o.state === 'shortlisted') chosen[o.id] = 'selected';
        else if (o.state === 'backup') chosen[o.id] = 'backup';
      });
    }

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
    // A booking whose post is out (Posted, Completed) follows the running
    // ones (2026-11-03): its old shoot date no longer leads the list.
    var done = function (o) { return o.state === 'posted' || o.state === 'completed'; };
    booked = booked.map(function (o, i) { return [o, i]; }).sort(function (a, b) {
      var xa = done(a[0]) ? 1 : 0, xb = done(b[0]) ? 1 : 0;
      if (xa !== xb) return xa - xb;
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
    $('bookedTotals').innerHTML = booked.length ? totalsHtml(sub, confAt()) : '';
    $('amountFold').hidden = !booked.length;
    $('amountLabel').textContent = t().amountLabel;
    $('amountPdf').hidden = !c.invoice_url;
    /* A private invoice has no address of its own: the press asks
       sign-download for a five-minute link with this page's own key. */
    $('amountPdf').href = c.invoice_url && /^https:\/\//i.test(c.invoice_url) ? c.invoice_url : '#';
    $('amountPdf').setAttribute('data-private', /^private\//.test(c.invoice_url || '') ? '1' : '');
    $('amountPdf').innerHTML = esc(t().pdf) + EXT_ICON;
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
    var today = ADspaceClock.today();
    var shoots = booked.filter(function (o) { return o.visit_date && o.visit_date >= today &&
      ['confirmed', 'pending_visit'].indexOf(o.state) > -1; })
      .map(function (o) { return o.visit_date; }).sort();
    var seeding = (feed.campaign || {}).push_format === 'seeding';
    box.innerHTML =
      '<p class="cx-standing-line"><b>' + esc(t().ofPosted(live, booked.length)) + '</b>' +
        (shoots.length && !seeding ? '<span>' + esc(t().nextShoot(fmtDate(shoots[0], true))) + '</span>' : '') + '</p>' +
      window.ADspaceIcons.track(bars.map(function (o) { return dotOf(o.state); })) +
      window.ADspaceIcons.legend(counts.map(function (c) { return { dot: c.dot, word: c.w, n: c.n }; }));
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
    if (vid && window.ADspaceMedia) return '<span class="cx-cover">' + ADspaceMedia.still(vid.url) + '</span>';
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
    /* A completed booking has every step behind it: the track says nothing
       its Completed chip does not (the user, 2026-10-10: "once completed
       the progress bar got not much usage"). */
    if (o.state === 'completed') return '';
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
      // that, the shoot is the date everyone is planning around. A post
      // with its link says its own day on its row, so the card does not
      // say it again.
      var wentOut = live && (o.posts || []).map(function (p) { return p.published_at; })
        .filter(Boolean).sort()[0];
      if (wentOut && posts.some(function (p) { return p.published_at; })) {
        /* said by the post's row */
      } else if (wentOut) {
        facts.push([t().postedOn, fmtDate(wentOut)]);
      } else if (!live) {
        facts.push([seeding ? t().deliveryOn : t().shootOn,
          o.visit_date ? fmtDate(o.visit_date, 'ahead') + (o.visit_time ? (lang === 'zh' ? ' ' : ', ') + ampm(o.visit_time) : '') : t().tbc]);
      }
      /* Once its post is out, each post's row names its platform. */
      var plats = posts.length ? [] : platsOf(o);
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
      postRows(o, posts, opts.sole) +
      /* Once the post is out, who approved it is history the console keeps;
         the card leads with the post (the user, 2026-09-27: "Is it necessary
         to keep the approved there"). */
      (live ? '' : decidedLine(o)) +
      /* At a desk the draft stands beside its caption and the decision, so
         Approve is in the first screen with the video (SELECTION-7). */
      (mine ? '<div class="draft-decide' + ((o.files || []).some(function (f) { return f.kind === 'video' || f.kind === 'image'; }) ? ' has-media' : '') + '">' +
        draftPreview(o) + decisionBlock(o) + '</div>' : '');

    if (mine) wireDecision(row, o);
    return row;
  }

  /* Each post as the campaign's Top post reads (the user, 2026-10-10: "I
     like this view … for all creators … way better for clients to view the
     results"): the booking's picture, the platform and the day it went
     out, its figures as glyphs (views, else impressions, then engagements),
     when they were measured, and the button to the post, named for where it
     opens. The measured day is what makes a figure read a year later still
     make sense. A lone live post's figures are the campaign's, said once in
     the results card above, so its row keeps only the post (`bare`). */
  function figuresIn(posts) {
    return posts.some(function (p) {
      return p.impressions != null || p.engagements != null || p.views != null;
    });
  }
  function measuredOf(p) {
    if (p.measured_at) return fmtDate(String(p.measured_at).slice(0, 10));
    if (p.published_at && p.window_days) {
      return fmtDate(ADspaceClock.addDays(String(p.published_at).slice(0, 10), Number(p.window_days)));
    }
    return '';
  }
  function postRows(o, posts, bare) {
    if (!posts.length) return '';
    var I = window.ADspaceIcons;
    var ic = function (n) { return I ? I.svg(n) : ''; };
    var cover = coverOf(o);
    var fig = function (glyph, n, word) {
      var v = Number(n).toLocaleString();
      return '<span aria-label="' + esc(v + ' ' + word) + '">' + ic(glyph) + '<span aria-hidden="true">' + esc(v) + '</span></span>';
    };
    return '<div class="cx-posts">' + posts.map(function (p) {
      var figs = !bare && figuresIn([p]);
      var mini = !figs ? '' : '<span class="cx-mini">' +
        (p.views != null ? fig('eye', p.views, t().viewsWord) : p.impressions != null ? fig('layers', p.impressions, t().impressions.toLowerCase()) : '') +
        (p.engagements != null ? fig('heart', p.engagements, t().engagements.toLowerCase()) : '') + '</span>';
      var when = figs ? measuredOf(p) : '';
      return '<div class="cx-post-item">' +
        '<div class="cx-post-row' + (cover ? '' : ' is-bare') + '">' + cover +
          '<div class="cx-post-who">' +
            '<span class="cx-plat">' + (I ? I.platform(platKey(p.platform)) : '') + esc(platWord(p.platform)) +
              (p.published_at ? ' · ' + esc(fmtDate(p.published_at)) : '') + '</span>' +
            mini +
            (when ? '<span class="cx-measured">' + esc(t().measuredWord(when)) + '</span>' : '') +
          '</div></div>' +
        '<a class="btn btn-sm postlink cx-postbtn" href="' + esc(absUrl(p.post_url)) + '" target="_blank" rel="noopener">' +
          esc(t().viewPostOn(platWord(p.platform), platKey(p.platform))) + EXT_ICON + '</a>' +
      '</div>';
    }).join('') + '</div>';
  }

  /* A stored address drawn as a link: http or https alone (js/words.js). */
  function absUrl(u) { return window.ADspaceWords.absUrl(u); }

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
      return '<a class="btn btn-sm" href="' + esc(absUrl(f.url)) + '" target="_blank" rel="noopener">' +
        esc(f.name || t().openFile) + '</a>';
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
    /* The console's own stamp, the year included (2026-10-20, SEL-5). */
    var stamp = r.at && ADspaceClock.parts(r.at)
      ? (lang === 'zh' ? ADspaceClock.date(r.at, { zh: true }) + ' ' + ADspaceClock.clock(r.at, { zh: true })
                       : ADspaceClock.date(r.at) + ', ' + ADspaceClock.clock(r.at))
      : '';
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
        '<textarea class="textarea" rows="3" maxlength="2000" aria-label="' + esc(t().noteLabel) +
          '" placeholder="' + esc(t().needNote) + '"></textarea>' +
        /* Drawn only where we do not already hold the name, so a client who
           has decided on something before is not asked twice. */
        /* Shown only while no name is held (the Request changes press), so
           Forget on the page brings it back. */
        '<input class="input changebox-who" type="text" autocomplete="name" maxlength="80" aria-label="' +
          esc(t().nameLabel) + '" placeholder="' + esc(t().namePlaceholder) + '"' +
          (window.ADspaceDecide.known() ? ' hidden' : '') + '>' +
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
      if (who) who.hidden = Boolean(window.ADspaceDecide.known());
      box.classList.add('is-open');
      /* While a request is open, Approve steps away: one decision at a
         time, as Content Review asks it (SELECTION-3). */
      wrap.classList.add('is-requesting');
      note.focus();
    });
    box.querySelector('[data-act="cancel"]').addEventListener('click', function () {
      box.classList.remove('is-open');
      wrap.classList.remove('is-requesting');
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
        /* The draft is no longer with the client (sent back to the creator
           meanwhile): the page is read again, never asked the same answer
           (review 2026-10-29, 18). */
        if (d.error === 'not-reviewing') { say(t().draftMoved, true); load(); return; }
        if ((r && r.error) || d.error) {
          lock(false);
          say(d.error === 'closed' ? t().closedText
            : d.error === 'locked' ? window.ADspaceWords.lockedLine(t(), d.minutes)
            : d.error === 'too-long' ? t().tooLong : t().notSent, true);
          return;
        }
        say(t().reviewThanks);
        load();                     // states have moved, so read them back
      }).catch(function () {
        lock(false);
        say(t().notSaved, true);
      });
    }
  }

  /* A time of day on the twelve-hour clock the client pages read (10:47am,
     as the scripts page writes it), never 24-hour beside a shoot's 2pm
     (SELECTION-10). */
  function ampm(hm) {
    var s = String(hm || '').trim();
    var m = /^(\d{1,2}):(\d{2})/.exec(s) || /^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)$/i.exec(s);
    if (!m) return s;
    var h = Number(m[1]);
    if (m[3]) h = (h % 12) + (/pm/i.test(m[3]) ? 12 : 0);
    if (h > 23) return s;
    var x = h >= 12 ? 'pm' : 'am', zh = h < 12 ? '上午' : '下午';
    h = h % 12 || 12;
    return lang === 'zh' ? zh + h + ':' + (m[2] || '00') : h + ':' + (m[2] || '00') + x;
  }
  /* `named`: a day the reader waits on carries its weekday (js/clock.js). */
  function fmtDate(d, named) {
    /* Days are Malaysia's (js/clock.js), whatever the device's clock. */
    return ADspaceClock.date(d, { zh: lang === 'zh', named: named });
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

  /* The view the strip shows: every creator, the selected or the backups. */
  var view = 'all';

  /* The head's facts (the mockup of 2026-11-25): Choose by, the day the
     client waits on with its weekday, and Creators, n of N. Once nothing
     is left to choose, the day is the campaign's own. */
  function paintFacts() {
    var c = feed.campaign || {};
    var slots = c.slots || 0, n = countSelected() + countBooked();
    var open = choosable().length > 0;
    var facts = [];
    if (c.deadline) facts.push(['calendar', open ? t().chooseBy : t().dueLabel, dueShort(c.deadline)]);
    if (slots) facts.push(['people', t().creatorsLabel, t().ofN(n, slots)]);
    if (c.invoice_no) facts.push(['doc', t().invoice, c.invoice_no]);
    $('csFacts').innerHTML = facts.map(function (f) {
      return '<div><span class="cs-fact-ic" aria-hidden="true">' + icon(f[0]) + '</span>' +
        '<dt>' + esc(f[1]) + '</dt><dd>' + esc(f[2]) + '</dd></div>';
    }).join('');
    $('csFacts').hidden = !facts.length;
  }
  /* 22 Sept (Tue): the year only where it is not this one (js/clock.js). */
  function dueShort(d) {
    var thisYear = String(d).slice(0, 4) === String(ADspaceClock.today()).slice(0, 4);
    return ADspaceClock.date(d, { zh: lang === 'zh', named: 'ahead', short: true, year: thisYear ? false : undefined });
  }

  function viewOf(o) {
    if (view === 'selected') return chosen[o.id] === 'selected';
    if (view === 'backup') return chosen[o.id] === 'backup';
    return true;
  }
  /* The strip: All, Selected and Backup, each with its count (`.tab-n`). */
  function paintStrip(options) {
    var n = { all: options.length, selected: 0, backup: 0 };
    options.forEach(function (o) { if (chosen[o.id] === 'selected') n.selected++; else if (chosen[o.id] === 'backup') n.backup++; });
    var views = [['all', t().viewAll], ['selected', t().viewSelected]];
    if (backupsOpen() || n.backup) views.push(['backup', t().viewBackup]);
    if (!views.some(function (v) { return v[0] === view; })) view = 'all';
    var strip = $('csStrip');
    strip.setAttribute('aria-label', t().viewsLabel);
    strip.innerHTML = views.map(function (v) {
      var on = v[0] === view;
      return '<button type="button" class="acttab btn-sm' + (on ? ' is-on' : '') + '" aria-pressed="' + on + '" data-v="' + v[0] + '">' +
        esc(v[1]) + '<span class="tab-n">' + n[v[0]] + '</span></button>';
    }).join('');
  }
  $('csStrip').addEventListener('click', function (e) {
    var b = e.target.closest('.acttab');
    if (!b || b.getAttribute('data-v') === view) return;
    view = b.getAttribute('data-v');
    paintCards();
  });

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
    paintFacts();
    if (!options.length) {
      // Nothing left to choose is not the same as nothing sourced yet.
      $('csBody').hidden = !!countBooked();
      $('csStrip').parentNode.hidden = true;
      grid.innerHTML = countBooked() ? '' : '<p class="cs-empty">' + esc(t().noneYet) + '</p>';
      $('csCart').hidden = true;
      $('chooseHead').hidden = true;
      $('chooseHint').hidden = true;
      return;
    }
    $('csBody').hidden = false;
    $('csCart').hidden = false;
    $('csStrip').parentNode.hidden = false;
    // Only a reopened slot needs a line here.
    $('chooseHint').hidden = !priority;
    $('chooseHint').textContent = priority ? t().priorityNotice : '';
    $('chooseHint').classList.toggle('is-priority', priority);

    paintStrip(options);
    var unit = (t().perUnit || {})[(feed.campaign || {}).deliverable] || t().perUnit.video;

    /* A card a creator (the mockup of 2026-11-25): the name and its tags,
       the profiles as contact chips, a hairline, then the fee over what it
       buys and Mark as backup; the round tick at the top right. Numbers
       carry on from the bookings above (SEL-4). */
    options.forEach(function (o, idx) {
      if (!viewOf(o)) return;
      var pick = chosen[o.id];
      var full = countSelected() >= slots && pick !== 'selected';
      var card = document.createElement('div');
      card.className = 'cs-card' + (pick === 'selected' ? ' is-on' : '') + (pick === 'backup' ? ' is-backup' : '');

      var links = (o.profiles || []).map(function (p) {
        var name = t().platform[p.platform] || platLabel(p.platform);
        var href = absUrl(p.url);
        if (!href) return '';
        return '<a class="plink" href="' + esc(href) + '" target="_blank" rel="noopener" aria-label="' + esc(t().viewOn(name)) + '">' +
          (window.ADspaceIcons ? (window.ADspaceIcons.mark(p.platform) || window.ADspaceIcons.platform(p.platform)) : '') + esc(name) + EXT_ICON + '</a>';
      }).join('');
      /* The fee is for a stated set of placements, read under it with the
         deliverable it buys. */
      var plats = platsOf(o);
      var per = unit + (plats.length ? ' · ' + plats.join(', ') : '');

      card.innerHTML =
        '<div class="cs-top">' +
          '<div class="cs-name">' +
            '<span class="rowno">' + (listedAbove + idx + 1) + '</span>' +
            '<b>' + esc(o.name) + '</b>' +
            (isNew(o) ? '<span class="chip tag-new">' + esc(t().newTag) + '</span>' : '') +
            (priority && pick === 'backup' ? '<span class="chip tag-pri">' + esc(t().priority) + '</span>' : '') +
            (o.is_replacement ? '<span class="chip tag-rep">' + esc(t().replacement) + '</span>' : '') +
          '</div>' +
          '<button class="cs-tick' + (full ? ' is-full' : '') + '" type="button" aria-pressed="' + (pick === 'selected') + '"' +
            (full ? ' aria-disabled="true"' : '') + ' aria-label="' + esc(t().select + ' ' + o.name) + '">' + icon('check') + '</button>' +
        '</div>' +
        (links ? '<div class="cs-links">' + links + '</div>' : '') +
        '<div class="msg err cs-msg" role="status" hidden></div>' +
        '<div class="cs-foot">' +
          '<div class="cs-fee"><b>' + money(o.rate) + '</b><small>' + esc(per) + '</small></div>' +
          (backupsOpen() || pick === 'backup'
            ? '<button class="btn btn-sm cs-backup' + (pick === 'backup' ? ' is-on' : '') + '" type="button" aria-pressed="' + (pick === 'backup') + '">' +
              icon('bookmark') + esc(pick === 'backup' ? t().markedBackup : t().markBackup) + '</button>'
            : '') +
        '</div>';

      card.querySelector('.cs-tick').addEventListener('click', function () {
        if (chosen[o.id] === 'selected') delete chosen[o.id];
        else if (countSelected() < slots) chosen[o.id] = 'selected';
        else {
          /* The slots are full: refused in place, on the card pressed. */
          var m = card.querySelector('.cs-msg');
          m.textContent = t().fullLine; m.hidden = false;
          return;
        }
        redraw();
      });
      var bk = card.querySelector('.cs-backup');
      if (bk) bk.addEventListener('click', function () {
        if (chosen[o.id] === 'backup') delete chosen[o.id];
        else if (backupsOpen()) chosen[o.id] = 'backup';
        redraw();
      });
      grid.appendChild(card);
    });
    if (!grid.children.length) grid.innerHTML = '<p class="cs-empty">' + esc(t().noneYet) + '</p>';

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

  /* The cart (the mockup of 2026-11-25, as Build quote's Summary): at a
     desk a shaded card beside the creators, on a phone the bar at the foot
     with its sheet. It counts against the slots, lists what is selected
     with its fee, the backups on one mute line, then the totals and
     Submit selection. */
  function paintProgress() {
    var slots = (feed.campaign || {}).slots || 0;
    var booked = countBooked();
    var n = countSelected() + booked;      // locked creators already hold a slot
    var open = choosable().length > 0;
    var over = slots > 0 && n > slots;
    paintFacts();

    $('cartHeading').textContent = t().yourSelection;
    $('cartIc').innerHTML = icon('doccheck');
    $('cartClose').setAttribute('aria-label', t().close);
    $('progCount').textContent = t().ofN(n, slots);
    $('progSay').textContent = over ? t().overSlots(slotsLeft()) : n >= slots ? t().complete : t().chooseMore(slots - n);
    $('progSay').classList.toggle('is-over', over);
    $('progSay').classList.toggle('is-done', !over && n >= slots);
    /* A selection the client has confirmed says so when the link is opened
       again, and Submit returns only once the picks differ from what was
       confirmed (UX audit SELECTION-1, 2026-10-14). */
    var conf = lastConfirm || (feed.campaign || {}).confirmed;
    var mine = (feed.options || []).filter(function (o) { return chosen[o.id] === 'selected'; }).map(function (o) { return o.id; }).sort();
    var asConfirmed = !!(conf && conf.selected && conf.selected.length && mine.length &&
      conf.selected.slice().sort().join(',') === mine.join(','));
    var confDay = conf && conf.at ? fmtDate(conf.at) : '';
    if (asConfirmed) $('progSay').textContent = t().confirmedBy(conf.person, confDay);

    var pending = (feed.options || []).filter(function (o) { return chosen[o.id] === 'selected'; });
    var backs = (feed.options || []).filter(function (o) { return chosen[o.id] === 'backup'; });
    var value = pending.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    var sst = sstOf(value);
    $('cartLines').innerHTML = pending.map(function (o) {
      return '<li><span>' + esc(o.name) + '</span><span>' + money(o.rate) + '</span></li>';
    }).join('');
    $('cartLines').hidden = !pending.length;
    var bval = backs.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    $('cartBackup').hidden = !backs.length;
    $('cartBackup').textContent = backs.length
      ? t().backupLine(backs.map(function (o) { return o.name; }).join(lang === 'zh' ? '、' : ', '), money(bval)) : '';
    $('cartTotals').innerHTML = pending.length ? totalsHtml(value) : '';
    $('cartTotals').hidden = !pending.length;

    var want = backupsWanted();
    var have = countBackups();
    var backupsOk = have >= want;
    $('progBackup').hidden = !want;
    /* Chinese runs on after its full stop; English takes a space (SEL-9). */
    var gap = lang === 'zh' ? '' : ' ';
    $('progBackup').textContent = !want ? '' :
      (backupsOk ? t().backupsDone + gap + t().backupCount(have, want)
                 : t().backupsNeeded(want - have) + gap + t().backupCount(have, want));
    $('progBackup').classList.toggle('is-ok', backupsOk);
    $('cartChanged').hidden = !(conf && !asConfirmed && confDay && pending.length);
    $('cartChanged').textContent = confDay ? t().changedSince(confDay) : '';

    $('confirmBtn').textContent = t().confirm;
    $('barSubmit').textContent = t().confirm;
    /* Backups are advice, never a block; more chosen than the slots left
       rests Submit until one is taken off (2026-10-20, SEL-1). */
    var rest = !pending.length || over;
    $('confirmBtn').disabled = rest;
    $('barSubmit').disabled = rest;
    $('confirmBtn').hidden = asConfirmed;
    $('barSubmit').hidden = asConfirmed;

    /* The bar: n of N selected and the total, over the backups and the tax
       (a client charged none reads no tax word). */
    var taxWord = sst ? t().inclTax(MON.taxLabel(mkt())) : '';
    var under = [backs.length ? t().backupsN(backs.length) : '', taxWord].filter(Boolean).join(' · ');
    $('confirmSummary').innerHTML = asConfirmed
      ? '<b>' + esc(t().confirmedBy(conf.person, confDay)) + '</b>'
      : '<b>' + esc(t().count(n, slots)) + ' · ' + money2(value + sst) + '</b>' +
        (over ? '<span class="is-over">' + esc(t().overSlots(slotsLeft())) + '</span>' : under ? '<span>' + esc(under) + '</span>' : '');
    $('cartOpen').innerHTML = esc(t().viewSelection) + '<span class="tab-n">' + pending.length + '</span>';
    $('confirmBar').hidden = !open || (!pending.length && !asConfirmed && !backs.length);
    document.documentElement.classList.toggle('has-csbar', !$('confirmBar').hidden);
  }

  /* View selection carries the cart into its sheet, and back when it shuts. */
  function cartHome() {
    var cart = $('csCart');
    if (cart.parentNode !== $('csBody')) $('csBody').appendChild(cart);
    cart.classList.remove('is-sheet');
  }
  $('cartOpen').addEventListener('click', function () {
    var cart = $('csCart');
    $('cartSheetBody').appendChild(cart);
    cart.classList.add('is-sheet');
    if (window.ADspaceSheet) window.ADspaceSheet.show($('cartSheet'), { opener: $('cartOpen'), onClose: cartHome });
    else $('cartSheet').hidden = false;
  });
  $('cartClose').addEventListener('click', function () {
    if (window.ADspaceSheet && window.ADspaceSheet.isOpen($('cartSheet'))) window.ADspaceSheet.close();
    else { $('cartSheet').hidden = true; cartHome(); }
  });
  $('barSubmit').addEventListener('click', function () { $('confirmBtn').click(); });

  // ---- Save (fire and forget, the client never waits on it) ---------------
  /* One save at a time, the latest picks sent last: two saves on their
     way at once could land in either order and keep the older picks. A
     refusal is read: a selection closed or full meanwhile is read again,
     so the page never shows picks that were not kept (audit 2026-11-15). */
  var saveTimer = null, saving = false, saveAgain = false;
  function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(sendSave, 500);
  }
  function sendSave() {
    if (saving) { saveAgain = true; return; }
    saving = true;
    var sel = [], bak = [];
    Object.keys(chosen).forEach(function (id) {
      (chosen[id] === 'selected' ? sel : bak).push(id);
    });
    db.rpc('save_selection', {
      p_token: TOKEN, p_selected: sel, p_backup: bak, p_passcode: passcode
    }).then(function (r) {
      var e = r && r.data && r.data.error;
      if (e === 'closed' || e === 'locked' || e === 'over-slots') load();
    }).catch(function () {}).then(function () {
      saving = false;
      if (saveAgain) { saveAgain = false; sendSave(); }
    });
  }

  // ---- Confirm ------------------------------------------------------------
  $('confirmBtn').addEventListener('click', function () {
    $('confirmHeading').textContent = t().confirmHeading;
    $('confirmBlurb').textContent = t().confirmBlurb;
    $('confirmBlurb').hidden = !t().confirmBlurb;
    $('confirmNameLabel').textContent = t().nameLabel;
    $('confirmName').placeholder = t().namePlaceholder;
    $('confirmGo').textContent = t().send;
    $('confirmCancel').textContent = t().cancel;
    paintConfirmList();
    msg('confirmMsg', '');
    /* The name already held on this device fills the field, still the
       client's to change (2026-10-27, SEL-4). */
    if (!$('confirmName').value && window.ADspaceDecide && window.ADspaceDecide.known()) $('confirmName').value = window.ADspaceDecide.known();
    /* The one sheet mechanism (js/sheet.js): focus held inside and handed
       back, Escape, the card focused rather than a field (SELECTION-4). */
    if (window.ADspaceSheet) window.ADspaceSheet.show($('confirmSheet'), { opener: $('confirmBtn') });
    else $('confirmSheet').hidden = false;
  });

  /* The creators chosen and their rates, as the sheet confirms them; drawn
     again when the campaign is read again under an open sheet. */
  function paintConfirmList() {
    var picked = (feed.options || []).filter(function (o) { return chosen[o.id] === 'selected'; });
    $('confirmList').innerHTML = picked.map(function (o) {
      return '<div class="act"><span class="act-subject">' + esc(o.name) + '</span>' +
        '<span class="muted act-when">' + money(o.rate) + '</span></div>';
    }).join('');
    var sub = picked.reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    $('confirmTotals').innerHTML = totalsHtml(sub);
  }

  function msg(id, text, kind) {
    var n = $(id); n.textContent = text || ''; n.className = 'msg' + (kind ? ' ' + kind : '');
  }

  function shutConfirm() {
    if (window.ADspaceSheet && window.ADspaceSheet.isOpen($('confirmSheet'))) window.ADspaceSheet.close();
    else $('confirmSheet').hidden = true;
  }
  $('confirmClose').addEventListener('click', shutConfirm);
  $('confirmCancel').addEventListener('click', shutConfirm);
  if (!window.ADspaceSheet) {
    $('confirmSheet').addEventListener('click', function (e) { if (e.target === $('confirmSheet')) shutConfirm(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutConfirm(); });
  }

  /* One press is one confirmation (audit F1, 2026-10-10): the creators on
     the client's screen, the rate shown for each and a key made when the
     sheet opens go together to `confirm_selection_with`, which saves the
     selection and files the confirmation in one transaction, refuses a rate
     or a creator that changed under the page, and answers the same key
     again without filing twice. A database without it is asked the older
     way, which now refuses a selection that never saved. */
  var confirmKey = null;
  /* What this page confirmed, for a database that does not yet send the
     confirmation back. */
  var lastConfirm = null;
  function newKey() {
    var a = new Uint8Array(16);
    (window.crypto || window.msCrypto).getRandomValues(a);
    return Array.prototype.map.call(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  $('confirmBtn').addEventListener('click', function () { confirmKey = newKey(); }, true);

  $('confirmGo').addEventListener('click', function () {
    var name = ($('confirmName').value || '').trim();
    if (!name) { msg('confirmMsg', t().nameNeeded, 'err'); $('confirmName').focus(); return; }
    var btn = this;
    if (btn.disabled) return;
    clearTimeout(saveTimer);
    var sel = [], bak = [], seen = {};
    Object.keys(chosen).forEach(function (id) { (chosen[id] === 'selected' ? sel : bak).push(id); });
    (feed.options || []).forEach(function (o) {
      if (chosen[o.id]) seen[o.id] = o.rate == null ? null : Number(o.rate);
    });
    if (!confirmKey) confirmKey = newKey();
    btn.disabled = true;
    var reread = function () {
      var lp = load();
      if (lp && lp.then) lp.then(function () { if (!$('confirmSheet').hidden) paintConfirmList(); });
    };
    var said = function (d) {
      var e = d && d.error;
      if (e === 'closed') { msg('confirmMsg', t().selectionClosed, 'err'); load(); }
      else if (e === 'locked') msg('confirmMsg', window.ADspaceWords.lockedLine(t(), d.minutes), 'err');
      else if (e === 'prices') { msg('confirmMsg', t().ratesChanged, 'err'); reread(); }
      else if (e === 'over-slots') {
        /* Too many for the slots left: said in the client's words with how
           many may still be chosen, the sheet shut so the list is fixed
           where the picks are made (2026-10-20, SEL-1). */
        shutConfirm();
        load();
      }
      else if (e === 'stale' || e === 'empty') { msg('confirmMsg', t().selectionChanged, 'err'); reread(); }
      else if (e === 'too-long') msg('confirmMsg', t().tooLong, 'err');
      else msg('confirmMsg', t().notSaved, 'err');
    };
    db.rpc('confirm_selection_with', {
      p_token: TOKEN, p_person: name, p_passcode: passcode,
      p_selected: sel, p_backup: bak, p_seen: seen, p_idem: confirmKey
    }).then(function (r) {
      btn.disabled = false;
      var d = (r && r.data) || {};
      /* In the client's words, never the database's; where the campaign
         moved under the page it is read again. */
      if ((r && r.error) || d.error) { said(r && r.error ? {} : d); return; }
      confirmKey = null;
      lastConfirm = { person: name, at: new Date().toISOString(), selected: sel.slice() };
      shutConfirm();
      /* The page stays, read again: the selection card then says who
         confirmed it and when (SELECTION-5), rather than a cover titled with
         the page's own name. */
      load();
    }).catch(function () { btn.disabled = false; msg('confirmMsg', t().notSaved, 'err'); });
  });

  setLang(lang);
  load();
})();
