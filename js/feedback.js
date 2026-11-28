/* A client's feedback, on its link (2026-11-24, CLIENT FEEDBACK; the user:
 * "only requested feedback (via email) to main pic, only it opens a feedback
 * for that specific clients").
 *
 * `/feedback/?k={key}`: the link a colleague's Request feedback emails the
 * client's primary contact. The page reads that one request
 * (`feedback_read`: the form, the client, the account manager it names) and
 * sends the answers once (`feedback_submit`); the first answer counts and the
 * link then reads Already submitted for everyone. No sign-in and no identity
 * fields: the link is the client. English and 中文, opening in the primary
 * contact's own language until the 中文 switch is pressed. */
(function () {
  var AGENCY = window.ADspaceAgency || {};
  var API = window.ADspaceAPI, db = API && API.client;
  var $ = function (id) { return document.getElementById(id); };
  var W = window.ADspaceWords, esc = W.esc, F = window.ADspaceFeedback;
  var LANG_KEY = 'adspace.feedback.lang';
  var lang = 'en', chosen = false;
  try { var sl = localStorage.getItem(LANG_KEY); if (sl === 'zh' || sl === 'en') { lang = sl; chosen = true; } } catch (e) {}

  var WORDS = W.of({
    en: {
      lang: '中文', preparedFor: 'Prepared for', requested: 'Requested {d}', submit: 'Submit',
      doneTitle: 'Feedback received', doneText: AGENCY.trading_name + ' appreciates the time you have taken to share your feedback.',
      usedTitle: 'Already submitted', usedText: 'This feedback was submitted on {d}.',
      closedTitle: 'Request closed', closedText: 'Please contact your ' + AGENCY.trading_name + ' account manager.',
      website: 'Visit website', fbSent: 'Feedback submitted', yourFeedback: 'Your feedback', follow: 'Follow ' + AGENCY.trading_name
    },
    zh: {
      lang: 'EN', preparedFor: '客户', requested: '请求日期：{d}', submit: '提交',
      doneTitle: '已收到您的反馈', doneText: '感谢您抽出宝贵时间提供反馈。',
      usedTitle: '已提交', usedText: '此反馈已于{d}提交。',
      closedTitle: '请求已关闭', closedText: '请联系您的 ' + AGENCY.trading_name + ' 客户经理。',
      website: '访问网站', fbSent: '反馈已提交', yourFeedback: '您的反馈', follow: '关注 ' + AGENCY.trading_name
    }
  });
  var t = function () { return WORDS[lang]; };
  var f = function (s, v) { return String(s).replace(/\{(\w+)\}/g, function (m, k) { return v[k] == null ? m : v[k]; }); };
  var LEAVE = window.ADspaceIcons.glyph('out');

  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();
  var info = null, state = 'loading', answers = {}, sending = false, answeredAt = null, sentAt = null, reqRef = '';
  var root = function () { return $('fbRoot'); };
  var CFG = window.ADSPACE_CONFIG || {};
  var site = function () { return W.absUrl((window.ADSPACE_ORG || {}).website || ''); };

  function day(iso, named) {
    var C = window.ADspaceClock;
    if (C && C.date) return C.date(iso, { zh: lang === 'zh', long: true, named: named });
    return new Date(iso).toLocaleDateString(lang === 'zh' ? 'zh-CN' : 'en-GB', { timeZone: 'Asia/Kuala_Lumpur', day: 'numeric', month: 'long', year: 'numeric' });
  }
  /* A cover's glyph is drawn by js/maintenance.js, from `data-glyph` or its title. */
  function cover(glyph, title, text, extra) {
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel"' +
      (glyph ? ' data-glyph="' + glyph + '"' : '') + '><h2>' + esc(title) + '</h2>' + (text ? '<p>' + esc(text) + '</p>' : '') + (extra || '') +
      '</div></div></section>';
  }
  function refWord() { return ((lang === 'zh' ? W.zh : W.en) || {}).coverRef || 'Reference'; }
  function websiteAct() {
    var u = site();
    return u ? '<div class="cover-acts"><a class="btn" href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(t().website) + LEAVE + '</a></div>' : '';
  }
  function socials() {
    var list = (CFG.socialLinks || []).filter(function (s) { return s && s.name && W.absUrl(s.url); });
    if (!list.length) return '';
    return '<div class="fb-social">' + list.map(function (s) {
      return '<a class="plink" href="' + esc(W.absUrl(s.url)) + '" target="_blank" rel="noopener">' + esc(s.name) + '</a>';
    }).join('') + '</div>';
  }
  /* Received (the board ReceivedFeedback, 2026-11-25; js/icons.js received):
     where it stands, what was answered, and the agency to follow. */
  function paintDone() {
    var w = t(), I = window.ADspaceIcons, C = window.ADspaceClock, zh = lang === 'zh', u = site();
    var when = sentAt && C ? C.date(sentAt, { zh: zh }) + (zh ? '' : ', ') + C.clock(sentAt, { zh: zh }) : '';
    var follow = socials() + (u ? '<div class="rcv-acts"><a class="btn" href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(w.website) + LEAVE + '</a></div>' : '');
    root().innerHTML = I.received({
      title: w.doneTitle, line: w.doneText, ref: F.title(info.kind, lang) + (info.client ? ' · ' + info.client : ''),
      /* The answer's reference (ONE REQUEST REFERENCE, 2026-11-26). */
      reqRef: reqRef, reqLabel: refWord(),
      steps: [
        { state: 'done', title: w.fbSent, sub: esc(when) },
        { state: 'now', glyph: 'search', title: w.rcvByManager, now: w.rcvNow }
      ],
      cards: [I.summary(w.yourFeedback, [{ rows: F.read(info.questions, answers, lang) }]), follow ? I.card(w.follow, follow) : '']
    });
  }
  function paint() {
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    var w = t(), C = window.ADspaceChrome;
    if (C && C.preparedFor) C.preparedFor(w.preparedFor, info && info.client);
    if (state === 'loading') return;
    if (state === 'bad') { cover('', w.notFound, w.notFoundText); return; }
    if (state === 'fail') { cover('', w.failTitle, w.failText); return; }
    if (state === 'closed') { cover('archive', w.closedTitle, w.closedText, websiteAct()); return; }
    if (state === 'answered') {
      cover('done', w.usedTitle, answeredAt ? f(w.usedText, { d: day(answeredAt) }) : '',
        (reqRef ? '<p class="rcv-ref rcv-req">' + esc(refWord() + ' ' + reqRef) + '</p>' : '') + websiteAct());
      return;
    }
    if (state === 'done') { paintDone(); return; }
    root().innerHTML = '<div class="qs-step fb-step" data-shown><div class="qs-top"><h1 class="qs-title">' + esc(F.title(info.kind, lang)) + '</h1>' +
      '<p class="qs-lead">' + esc(f(w.requested, { d: day(info.requested_at) })) + '</p></div>' +
      '<form class="fb-form" id="fbForm" novalidate data-lang="' + lang + '">' + F.form(info.questions, lang, answers) + '</form>' +
      '<p class="msg" id="fbMsg" role="status"></p></div>' +
      '<div class="qs-foot"><button class="btn btn-primary" type="button" id="fbSubmit">' + esc(w.submit) + '</button></div>';
    F.wire($('fbForm'), info.questions, answers, null, lang);
    if (window.ADspaceGrow && window.ADspaceGrow.fit) Array.prototype.forEach.call(root().querySelectorAll('textarea'), window.ADspaceGrow.fit);
  }
  function say(text) { var m = $('fbMsg'); if (m) { m.textContent = text || ''; m.className = 'msg' + (text ? ' err' : ''); } }
  function submit(btn) {
    if (sending || state !== 'open') return;
    if (F.check($('fbForm'), info.questions, answers, lang)) return;
    sending = true; btn.disabled = true; say('');
    db.rpc('feedback_submit', { p_key: key, p_answers: F.payload(info.questions, answers) }).then(function (r) {
      var d = r.data || {};
      if (r.error) throw r.error;
      if (d.error === 'answered') { state = 'answered'; answeredAt = d.answered_at; reqRef = d.request_ref || ''; paint(); return; }
      if (d.error === 'closed') { state = 'closed'; paint(); return; }
      if (d.error === 'not_found') { state = 'bad'; paint(); return; }
      if ((d.error === 'required' || d.error === 'bad-score' || d.error === 'too-long') && d.key) {
        F.check($('fbForm'), info.questions, answers, lang);
        say(t().notSent); return;
      }
      if (d.error) throw new Error(d.error);
      reqRef = d.request_ref || ''; state = 'done'; sentAt = new Date().toISOString(); paint(); window.scrollTo(0, 0);
    }).catch(function () {
      say(t().notSent);
    }).then(function () { sending = false; if (btn && btn.isConnected) btn.disabled = false; });
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest('#fbSubmit');
    if (b) submit(b);
  });
  if ($('langToggle')) $('langToggle').addEventListener('click', function () {
    lang = lang === 'en' ? 'zh' : 'en'; chosen = true;
    try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
    paint();
  });

  if (!db) { state = 'fail'; paint(); return; }
  if (!/^[a-z0-9]{16}$/.test(key)) { state = 'bad'; paint(); return; }
  db.rpc('feedback_read', { p_key: key }).then(function (r) {
    var d = r.data || {};
    if (r.error) throw r.error;
    if (d.client) info = { client: d.client };
    if (d.error === 'answered') { state = 'answered'; answeredAt = d.answered_at; reqRef = d.request_ref || ''; }
    else if (d.error === 'closed') state = 'closed';
    else if (d.error === 'busy') state = 'fail';
    else if (d.error || !d.ok) state = 'bad';
    else {
      info = d; state = 'open';
      if (!chosen && d.lang === 'zh') lang = 'zh';
    }
    paint();
  }).catch(function () { state = 'fail'; paint(); });
})();
