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
      isBackup: 'Backup',
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
      isBackup: '备选',
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

    paintCards();
    paintProgress();
  }

  function fmtDate(d) {
    var dt = new Date(d + 'T00:00:00');
    return dt.toLocaleDateString(lang === 'zh' ? 'zh-CN' : 'en-GB',
      { day: 'numeric', month: 'short', year: 'numeric' });
  }

  function countSelected() {
    return Object.keys(chosen).filter(function (k) { return chosen[k] === 'selected'; }).length;
  }

  function paintCards() {
    var grid = $('optionGrid');
    var options = feed.options || [];
    var slots = (feed.campaign || {}).slots || 0;
    var before = seenBefore();
    var isNew = function (o) { return before.length > 0 && before.indexOf(o.id) < 0; };

    grid.innerHTML = '';
    if (!options.length) {
      grid.innerHTML = '<div class="empty">' + esc(t().noneYet) + '</div>';
      return;
    }

    options.forEach(function (o) {
      var pick = chosen[o.id];
      var full = countSelected() >= slots && pick !== 'selected';
      var card = document.createElement('div');
      card.className = 'ccard' + (pick === 'selected' ? ' is-on' : '') + (pick === 'backup' ? ' is-backup' : '');

      var links = (o.profiles || []).map(function (p) {
        return '<a class="pchip" href="' + esc(p.url) + '" target="_blank" rel="noopener">' +
          esc(platLabel(p.platform)) + ' ↗</a>';
      }).join('');

      card.innerHTML =
        '<div class="ccard-head">' +
          '<b>' + esc(o.name) + '</b>' +
          (isNew(o) ? '<span class="tag-new">NEW</span>' : '') +
          (o.is_replacement ? '<span class="tag-rep">' + esc(t().replacement) + '</span>' : '') +
        '</div>' +
        '<div class="ccard-meta">' +
          esc(o.platforms || '') +
          (o.followers ? ' · ' + Number(o.followers).toLocaleString() : '') +
        '</div>' +
        '<div class="ccard-links">' + links + '</div>' +
        '<div class="ccard-foot">' +
          '<span class="ccard-rate">' + money(o.rate) + '</span>' +
          '<button class="btn btn-sm ' + (pick === 'selected' ? 'btn-primary' : '') + ' ccard-pick"' +
            (full ? ' disabled' : '') + ' type="button">' +
            esc(pick === 'selected' ? t().selected : (full ? t().full : t().select)) +
          '</button>' +
        '</div>' +
        '<button class="linkbtn ccard-backup" type="button">' +
          esc(pick === 'backup' ? t().isBackup : t().backup) + '</button>';

      card.querySelector('.ccard-pick').addEventListener('click', function () {
        if (chosen[o.id] === 'selected') delete chosen[o.id];
        else if (countSelected() < slots) chosen[o.id] = 'selected';
        redraw();
      });
      card.querySelector('.ccard-backup').addEventListener('click', function () {
        if (chosen[o.id] === 'backup') delete chosen[o.id];
        else chosen[o.id] = 'backup';
        redraw();
      });
      grid.appendChild(card);
    });

    remember(options.map(function (o) { return o.id; }));
  }

  function platLabel(p) {
    return { xhs: 'RedNote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' }[p] || p;
  }

  function redraw() { paintCards(); paintProgress(); save(); }

  function paintProgress() {
    var slots = (feed.campaign || {}).slots || 0;
    var n = countSelected();
    var pct = slots ? Math.min(100, Math.round((n / slots) * 100)) : 0;

    $('progLabel').textContent = t().yourSelection;
    $('progCount').textContent = t().count(n, slots);
    $('progFill').style.width = pct + '%';
    $('progSay').textContent = n >= slots ? t().complete : t().chooseMore(slots - n);
    $('progressCard').classList.toggle('is-done', n >= slots);

    var value = (feed.options || []).filter(function (o) { return chosen[o.id] === 'selected'; })
      .reduce(function (s, o) { return s + Number(o.rate || 0); }, 0);
    $('confirmSummary').textContent = t().summary(n, money(value));
    $('confirmBtn').textContent = t().confirm;
    $('confirmBtn').disabled = n === 0;
    $('confirmBar').hidden = n === 0;
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
