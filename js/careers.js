/* A candidate's own page (2026-11-16, release H2 step A; HR-SPEC.md
 * decision 1): `/careers/?k={key}`, the one private link a candidate holds.
 * No account and no sign-in. It reads their name, the position and where the
 * application stands (`careers_read`), never a colleague, a note or a score.
 * English alone. The link ends after `hiring_link_days` without a step.
 *
 * Step D (HR-SPEC.md decisions 4, 10, 14): an Employment Offer or Contract
 * sent to the candidate is listed by its reference and where it stands; its
 * terms and salary open only behind a six-digit code emailed to the
 * candidate (`hiring-mail` kind `code`, `careers_doc_open`) and a caution
 * step, for 30 minutes on this device (the view kept in this tab's
 * session). An offer is accepted (the name typed, the confirmation ticked)
 * or declined; a contract is signed (name, NRIC or passport number, a
 * signature drawn in a 300 by 100 box). */
(function () {
  var API = window.ADspaceAPI, db = API && API.client;
  var $ = function (id) { return document.getElementById(id); };
  var esc = window.ADspaceWords.esc;
  var W = window.ADspaceWords.of({ en: {} }).en;
  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();
  var root = function () { return $('crRoot'); };
  function day(iso) { return window.ADspaceClock.date(iso, { long: true }); }
  /* The careers mailbox, the database's (`careers_read` answers it on every
     answer; 2026-11-20): every line asking the candidate to contact ADspace
     names it. */
  var CONTACT = '';
  function reach(line) {
    return CONTACT ? String(line || '').replace(/contact ADspace\.$/, 'contact ADspace at ' + CONTACT + '.') : line;
  }
  function cover(title, text) {
    text = reach(text);
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p></div></div></section>';
  }
  /* Where the application stands, in the candidate's words. The steps
     after Received arrive with the later releases. */
  var NEXT = {
    received: 'ADspace will contact you by email when there is a next step. The next step will also be shown on this page.'
  };
  var STATUS = { received: 'Application received', invited: 'Invited to an interview', interview: 'Interview confirmed', held: 'Interview held',
    cancelled: 'Interview cancelled', pending: 'Interview time pending confirmation',
    offer: 'Application in progress', pool: 'Talent pool', closed: 'Application closed', hired: 'Offer accepted' };
  var MARK = '<span class="qs-mark" aria-hidden="true"><svg viewBox="0 0 16 16" width="12" height="12"><path d="M3.5 8.4l2.9 2.9 6.1-6.6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>';
  /* A time the candidate waits on, in the portal's form (2026-11-20,
     `ADspaceClock.due`): 21 Nov 2026 (Saturday), 10:00am, the date held
     whole so a line breaks after its comma, never inside it. A time gone by
     (the interview held) reads without its weekday. */
  function when(iso, past) {
    if (!iso) return '';
    var C = window.ADspaceClock;
    return C.date(iso, { named: !past }).replace(/ /g, '\u00a0') + ', ' + C.clock(iso);
  }
  var ORG = window.ADSPACE_ORG || {};
  /* The interview (step B, HR-SPEC.md decision 2): the times offered to
     choose from, or other times asked for; once confirmed, when and where. */
  /* Where the interview is held, the same rows in every state (2026-11-19,
     the user: the office's details were missing): the office with its
     address and Get directions, or Google Meet with its link once the time
     is confirmed. The time, where known, leads; Length closes. */
  /* The address a line a part, each line's last two words held together, so
     a phone never leaves 2A alone on a line. */
  function addrLines() {
    return String(ORG.address || '').split('\n').map(function (l) { return esc(l).replace(/ (\S+)$/, '&nbsp;$1'); }).join('\n');
  }
  /* The meeting's address as words, its code held whole after the last
     slash (meet.google.com/ then abc-defg-hij), never broken at a hyphen. */
  function meetWord(u) {
    var t = String(u || '').replace(/^https?:\/\//, ''), k = t.lastIndexOf('/');
    return k < 0 ? '<span class="cr-meet-code">' + esc(t) + '</span>'
      : esc(t.slice(0, k + 1)) + '<wbr><span class="cr-meet-code">' + esc(t.slice(k + 1)) + '</span>';
  }
  function place(i, confirmed) {
    var I = window.ADspaceIcons;
    var where = i.mode === 'online'
      ? 'Google Meet' + (confirmed && i.link
        ? '<span class="cr-meet">' + meetWord(i.link) + '</span>'
        : confirmed ? '' : '<span class="cr-where-note">The meeting link will be shared once the time is confirmed.</span>')
      : 'ADspace office<span class="cr-addr">' + addrLines() + '</span>' +
        (ORG.map ? '<a class="btn btn-sm cr-map" href="' + esc(ORG.map) + '" target="_blank" rel="noopener">' +
          (I ? I.svg('pin') : '') + 'Get directions' + (I ? I.svg('out') : '') + '</a>' : '');
    return '<div><dt>Location</dt><dd class="cr-where">' + where + '</dd></div>' +
      '<div><dt>Duration</dt><dd>' + esc(i.minutes) + ' minutes</dd></div>';
  }
  /* The way to change an interview's time, before its confirmation and after
     it until it is held (2026-11-22, the user): ADspace's WhatsApp chat, never
     its number. */
  function change() {
    var I = window.ADspaceIcons, chat = (window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.quoteWhatsApp) || 'https://wa.me/adspace';
    return '<div class="cr-change"><p class="cr-next">To change the time, please contact ADspace on WhatsApp.</p>' +
      '<a class="btn btn-sm cr-chat" id="crChat" href="' + esc(chat) + '" target="_blank" rel="noopener">' + (I ? I.svg('chat') : '') +
      esc(W.chatWhatsApp || 'Chat on WhatsApp') + '</a></div>';
  }
  function interview(i) {
    if (!i) return '';
    var head = '<h2 class="qs-sec-h">Interview</h2>';
    if (i.state === 'invited') {
      return '<section class="qs-sec cr-iv" id="crIv"><h2 class="qs-sec-h">Choose an interview time</h2>' +
        '<dl class="ovfacts cr-facts">' + place(i, false) + '</dl>' +
        '<p class="cr-next">' + (i.reply_by ? 'Please reply by ' + esc(when(i.reply_by)) + '. ' : '') + 'All times are Malaysia time.</p>' +
        (i.note ? '<p class="cr-note">' + esc(i.note) + '</p>' : '') +
        '<fieldset class="cr-picks" aria-label="Interview time">' + (i.slots || []).map(function (t, n) {
          return '<label class="qs-pick"><input type="radio" name="crTime" value="' + (n + 1) + '"><span class="qs-text"><b>' + esc(when(t)) + '</b></span>' + MARK + '</label>';
        }).join('') +
        '<label class="qs-pick"><input type="radio" name="crTime" value="none"><span class="qs-text"><b>None of these times</b></span>' + MARK + '</label></fieldset>' +
        '<div class="field" id="crNoneBox" hidden><label for="crNone">Preferred times</label>' +
          '<textarea class="textarea" id="crNone" rows="2" maxlength="300" placeholder="Optional"></textarea></div>' +
        '<p class="msg" id="crMsg"></p>' +
        '<div class="qs-foot"><button class="btn btn-primary" type="button" id="crSend">Confirm time</button></div></section>';
    }
    /* A time chosen, not yet confirmed (2026-11-22, the user: "Before
       confirmation … a candidate won't actually see any like Google Meet
       details or office details"): the time and its length alone, never where
       (`careers_read` withholds it), the time said to wait on ADspace, and
       the way to change it, ADspace's WhatsApp chat, never its number. */
    if (i.state === 'picked') {
      return '<section class="qs-sec cr-iv" id="crIv">' + head + '<dl class="ovfacts cr-facts"><div><dt>Time chosen</dt><dd>' + esc(when(i.at)) + '</dd></div>' +
        '<div><dt>Duration</dt><dd>' + esc(i.minutes) + ' minutes</dd></div></dl>' +
        '<p class="cr-next" id="crPending">ADspace will confirm this interview time. ' + (i.mode === 'online'
          ? 'You will receive an email with the Google Meet link once it is confirmed.'
          : 'You will receive an email once it is confirmed. Please do not visit the office until then.') + '</p>' + change() + '</section>';
    }
    /* An invitation not answered by its reply-by date (2026-11-19, the user:
       "Expire, tell the team"): choosing closes, the team is told. */
    if (i.state === 'expired') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">The period for choosing an interview time has ended. ' +
      'ADspace will contact you by email if another time can be arranged.</p></section>';
    /* Cancelled (2026-11-20): no time and no way to join, only what follows. */
    if (i.state === 'cancelled') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will contact you to arrange another time.</p></section>';
    if (i.state === 'none') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will send you other times by email.</p></section>';
    /* Interview held (2026-11-20): when it was, and by when ADspace will
       inform the candidate of the outcome, in place of the way to join. */
    if (i.state === 'confirmed' && i.held) {
      return '<section class="qs-sec cr-iv">' + head + '<dl class="ovfacts cr-facts"><div><dt>Date and time</dt><dd>' + esc(when(i.at, true)) + '</dd></div></dl>' +
        (i.decide_by ? '<p class="cr-next">ADspace will inform you of the outcome by ' + esc(when(i.decide_by)) + ' (Malaysia time).</p>' : '') +
        /* Past the date with no decision, the careers mailbox to write to (the
           user, 2026-11-20); the address is the database's, never typed. */
        (i.contact ? '<p class="cr-next">If you have not heard from ADspace by then, please email ' + esc(i.contact) + '.</p>' : '') + '</section>';
    }
    if (i.state === 'confirmed') {
      var join = i.mode === 'online' && i.link && window.ADspaceWords.absUrl(i.link)
        ? '<a class="btn btn-primary" href="' + esc(window.ADspaceWords.absUrl(i.link)) + '" target="_blank" rel="noopener">Join Google Meet</a>' : '';
      /* Moved by the team (2026-11-22, the user: a candidate "would have
         thought the date is the same"): the new time leads, the time it
         replaced named under it. */
      return '<section class="qs-sec cr-iv">' + head + '<dl class="ovfacts cr-facts"><div><dt>Date and time</dt><dd>' + esc(when(i.at)) +
        (i.was ? '<span class="cr-moved" id="crMoved">Rescheduled from ' + esc(when(i.was, true)) + '</span>' : '') + '</dd></div>' +
        place(i, true) + '</dl>' + (join ? '<div class="qs-foot">' + join + '</div>' : '') + change() + '</section>';
    }
    return '';
  }
  /* The decision (step C): Keep in talent pool asks the candidate to agree;
     Not proceed, or a pool declined, reads closed; Proceed waits on the offer. */
  function decision(d) {
    var head = '';
    /* Proceed promises no offer (2026-11-20): the next step alone. */
    if (d.stage === 'offer') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will contact you about the next step.</p></section>';
    /* The talent pool declined: the details are not kept, the application never
       said to be refused (2026-11-20). */
    if (d.stage === 'closed' && d.pool_declined) return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will not keep your details on file.</p></section>';
    if (d.stage === 'closed') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">' +
      'ADspace will not be proceeding with your application at this time. ADspace wishes you every success in your search.</p></section>';
    var p = d.pool;
    if (d.stage !== 'pool' || !p) return '';
    if (p.consent === 'yes') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will keep your application until ' +
      esc(window.ADspaceClock.date(p.until, { long: true })) + ' and may contact you about future positions. Your details will then be deleted.</p></section>';
    return '<section class="qs-sec cr-iv" id="crPool"><h2 class="qs-sec-h">Keep your application on file?</h2>' +
      '<p class="cr-next">There is no suitable opening for you at this time. ADspace would like to keep your application for ' + esc(p.months) +
      ' months and may contact you about future positions. If you do not agree, your details will be deleted.</p>' +
      '<p class="msg" id="crMsg"></p>' +
      '<div class="qs-foot"><button class="btn" type="button" data-pool="no">Do not keep</button>' +
      '<button class="btn btn-primary" type="button" data-pool="yes">Keep my application</button></div></section>';
  }
  function wirePool() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-pool]'), function (b) {
      b.addEventListener('click', function () {
        Array.prototype.forEach.call(document.querySelectorAll('[data-pool]'), function (x) { x.disabled = true; });
        db.rpc('careers_pool', { p_key: key, p_yes: b.getAttribute('data-pool') === 'yes' }).then(function (r) {
          if (r.error) throw r.error;
          load();
        }).catch(function () {
          Array.prototype.forEach.call(document.querySelectorAll('[data-pool]'), function (x) { x.disabled = false; });
          say(W.notSentAdspace || 'Not sent. Please try again.');
        });
      });
    });
  }

  /* Offers and contracts (step D). */
  var DOCWORD = { offer: 'Employment Offer', contract: 'Employment Contract' };
  var DOCSTATE = {
    sent: function (k) { return k === 'contract' ? ['Awaiting your signature', 'is-warn'] : ['Awaiting your reply', 'is-warn']; },
    expired: function () { return ['Expired', 'is-off']; },
    signed: function (k) { return [k === 'contract' ? 'Signed, awaiting ADspace confirmation' : 'Accepted, awaiting ADspace confirmation', 'is-warn']; },
    confirmed: function () { return ['Confirmed', 'is-ok']; },
    declined: function () { return ['Declined', 'is-off']; }
  };
  var DOCSAID = {
    wrong: 'The code is incorrect. Please try again.',
    locked: 'This code can no longer be used. Please select Send a new code.',
    'no-code': 'This code can no longer be used. Please select Send a new code.',
    'code-expired': 'This code has expired. Please select Send a new code.',
    'too-many': 'Too many codes have been requested. Please try again in an hour.',
    'code-needed': 'Please open the document again with a new code.',
    'bad-name': 'Enter your full name.', 'bad-agree': 'Please tick the confirmation.',
    'bad-id': 'Enter your NRIC or Passport Number (for example 900101-01-1234).',
    'bad-signature': 'Please sign in the box.', expired: 'The time to reply has passed. Please contact ADspace.',
    answered: 'You have already replied to this document. Refresh the page to see it.', 'too-long': 'Shorten the reason to 500 characters.',
    'mail-not-set-up': 'The code could not be sent. Please contact ADspace.', 'not-sent': 'The code could not be sent. Please try again.'
  };
  var VIEW = 'adspace-careers-view:';
  function viewOf(id) { try { return sessionStorage.getItem(VIEW + id) || ''; } catch (e) { return ''; } }
  function keepView(id, v) { try { if (v) sessionStorage.setItem(VIEW + id, v); else sessionStorage.removeItem(VIEW + id); } catch (e) {} }
  var openDoc = { id: null, step: '', data: null, codeSent: false };
  function docsSection(list) {
    if (!list || !list.length) return '';
    return '<section class="qs-sec cr-docs" id="crDocs"><h2 class="qs-sec-h">Documents</h2>' + list.map(function (d) {
      var st = (DOCSTATE[d.state] || DOCSTATE.sent)(d.kind), on = openDoc.id === d.id;
      return '<div class="panel cr-doc" data-doc="' + esc(d.id) + '"><div class="cr-doc-head"><div class="cr-doc-who"><b>' + esc(DOCWORD[d.kind] || '') + '</b>' +
        '<span class="cr-doc-meta">' + esc(d.serial || '') + (d.state === 'sent' && d.reply_by ? ' · Reply by ' + esc(when(d.reply_by)) : '') + '</span></div>' +
        '<span class="chip chip-state ' + st[1] + '">' + esc(st[0]) + '</span></div>' +
        (on ? '<div class="cr-doc-body" id="crDocBody"></div>' : '<div class="qs-foot cr-doc-foot"><button class="btn" type="button" data-docopen="' + esc(d.id) + '">' +
          (d.kind === 'contract' ? 'Read contract' : 'Read offer') + '</button></div>') + '</div>';
    }).join('') + '</section>';
  }
  function docSay(t, ok) { t = reach(t); var m = $('crDocMsg'); if (m) { m.textContent = t || ''; m.className = 'msg' + (t ? (ok ? ' ok' : ' err') : ''); } }
  function deviceOf() { return window.ADspaceSeal && window.ADspaceSeal.device ? window.ADspaceSeal.device() : ''; }
  function docBody() {
    var box = $('crDocBody');
    if (!box) return;
    var d = openDoc.data;
    if (openDoc.step === 'caution') {
      box.innerHTML = '<div class="cr-caution"><h3 class="cr-doc-h">Sensitive information follows</h3>' +
        '<p class="cr-next">Proceed with caution. Please make sure no one else can see your screen.</p>' +
        '<div class="qs-foot"><button class="btn" type="button" data-docx="close">Cancel</button><button class="btn btn-primary" type="button" data-docx="continue">Continue</button></div></div>';
    } else if (openDoc.step === 'view' && d) {
      box.innerHTML = docView(d);
      padWire();
    } else {
      box.innerHTML = '<p class="cr-next">' + (openDoc.codeSent ? 'A code has been sent to your email address. It expires in 15 minutes.'
          : 'For your privacy, ADspace will email a six-digit code to your email address before showing the document.') + '</p>' +
        (openDoc.codeSent ? '<form class="cr-codeform" id="crCodeForm" novalidate><div class="qs-form"><div class="field"><label class="field-label" for="crCode">Code</label><input class="input cr-code" id="crCode" inputmode="numeric" autocomplete="one-time-code" maxlength="6" pattern="[0-9]*"></div></div>' +
          '<p class="msg" id="crDocMsg"></p>' +
          '<div class="qs-foot"><button class="btn" type="button" data-docx="code">Send a new code</button><button class="btn btn-primary" type="submit" data-docx="open">Open</button></div></form>'
          : '<p class="msg" id="crDocMsg"></p>' +
            '<div class="qs-foot"><button class="btn" type="button" data-docx="close">Cancel</button><button class="btn btn-primary" type="button" data-docx="code">Email me a code</button></div>');
      /* The code and Open are one form: Open is its commit, and Enter in the
         field submits it once (2026-11-19). */
      if ($('crCodeForm')) $('crCodeForm').addEventListener('submit', function (e) { e.preventDefault(); });
    }
    Array.prototype.forEach.call(box.querySelectorAll('[data-docx]'), function (b) { b.addEventListener('click', function () { docAct(b.getAttribute('data-docx'), b); }); });
  }
  var TYPEWORD = { permanent: 'Permanent, full-time', contract: 'Contract, full-time', intern: 'Internship', part_time: 'Part-time' };
  function money(n) { return window.ADspaceMoney && window.ADspaceMoney.money2 ? window.ADspaceMoney.money2(n, 'MY') : 'RM ' + Number(n || 0).toFixed(2); }
  function docView(d) {
    var t = d.terms || {}, p = d.pay || {}, months = Number(t.probation_months) || 0;
    var facts = '<dl class="ovfacts cr-facts">' +
      '<div><dt>Employment</dt><dd>' + esc(TYPEWORD[t.type] || '') + '</dd></div>' +
      '<div><dt>Position</dt><dd>' + esc(t.position || '') + '</dd></div>' +
      (t.scope ? '<div><dt>Job scope</dt><dd>' + esc(t.scope) + '</dd></div>' : '') +
      '<div><dt>Commencement</dt><dd>' + esc(day(t.start)) + '</dd></div>' +
      (t.end ? '<div><dt>End of contract</dt><dd>' + esc(day(t.end)) + '</dd></div>' : '') +
      (months ? '<div><dt>Probation</dt><dd>' + months + ' month' + (months === 1 ? '' : 's') + '</dd></div>' : '') +
      '<div><dt>Basic salary</dt><dd>' + esc(money(p.basic)) + ' per month' + (months && p.probation ? '<br>' + esc(money(p.probation)) + ' per month during probation' : '') + '</dd></div>' +
      '</dl>';
    var dl = '<div class="qs-foot cr-doc-dl"><button class="btn" type="button" data-docx="pdf">' + (window.ADspaceIcons ? window.ADspaceIcons.svg('file') : '') + 'Download</button></div>';
    if (d.returned_note) facts = '<p class="msg warn">ADspace returned this document: ' + esc(d.returned_note) + '</p>' + facts;
    if (d.state !== 'sent') return facts + dl + (d.state === 'signed' ? '<p class="cr-next">ADspace will confirm the document and tell you by email.</p>' : '');
    var tick = function (id, text) {
      return '<label class="qs-consent cr-agree"><input type="checkbox" id="' + id + '">' + MARK + '<span class="qs-text">' + esc(text) + '</span></label>';
    };
    if (d.kind === 'offer') {
      return facts + dl + '<div class="cr-answer qs-form"><h3 class="cr-doc-h">Reply to the offer</h3>' +
        '<div class="field"><label class="field-label" for="crName">Full name</label><input class="input" id="crName" autocomplete="name" maxlength="120" value="' + esc(d.name || '') + '"></div>' +
        tick('crAgree', 'I accept this Employment Offer.') +
        '<div class="field" id="crDeclineBox" hidden><label class="field-label" for="crDecline">Reason</label><textarea class="textarea" id="crDecline" rows="2" maxlength="500" placeholder="Optional"></textarea></div>' +
        '<p class="msg" id="crDocMsg"></p>' +
        '<div class="qs-foot"><button class="btn" type="button" data-docx="decline">Decline</button><button class="btn btn-primary" type="button" data-docx="accept">Accept offer</button></div></div>';
    }
    return facts + dl + '<div class="cr-answer qs-form"><h3 class="cr-doc-h">Sign the contract</h3>' +
      '<div class="field"><label class="field-label" for="crName">Full Name as per NRIC</label><input class="input" id="crName" autocomplete="name" maxlength="120" value="' + esc(d.name || '') + '"></div>' +
      '<div class="field"><label class="field-label" for="crIdNo">NRIC or Passport Number</label><input class="input" id="crIdNo" maxlength="20" placeholder="900101-01-1234"></div>' +
      '<div class="field"><div class="qs-sig-head"><span class="field-label">Signature</span><span class="qs-sig-acts"><button class="btn btn-quiet btn-sm" type="button" data-docx="clear" hidden>Clear</button></span></div>' +
        '<div class="qs-pad" id="crPad" role="img" aria-label="Signature box"><span class="qs-pad-line" aria-hidden="true"></span><span class="qs-pad-hint">Sign here</span>' +
        '<svg viewBox="0 0 300 100" preserveAspectRatio="none" aria-hidden="true"><path d=""/></svg></div></div>' +
      tick('crAgree', window.ADspaceHrDocs.declare) +
      '<p class="msg" id="crDocMsg"></p>' +
      '<div class="qs-foot"><button class="btn btn-primary" type="button" data-docx="sign">Sign contract</button></div></div>';
  }
  var SIG = { path: '' };
  function padWire() {
    var pad = $('crPad');
    if (!pad) return;
    SIG.path = '';
    var path = pad.querySelector('path'), on = false, lx = 0, ly = 0;
    var pt = function (e) {
      var r = pad.getBoundingClientRect();
      return [Math.max(0, Math.min(300, (e.clientX - r.left) / r.width * 300)), Math.max(0, Math.min(100, (e.clientY - r.top) / r.height * 100))];
    };
    var fx = function (n) { return (Math.round(n * 10) / 10).toString(); };
    pad.addEventListener('pointerdown', function (e) {
      if (SIG.path.length > 28000) return;
      e.preventDefault(); on = true;
      try { pad.setPointerCapture(e.pointerId); } catch (x) {}
      var p = pt(e); lx = p[0]; ly = p[1];
      SIG.path += (SIG.path ? ' ' : '') + 'M' + fx(lx) + ' ' + fx(ly);
      path.setAttribute('d', SIG.path);
      var hint = pad.querySelector('.qs-pad-hint'); if (hint) hint.hidden = true;
      pad.removeAttribute('aria-invalid');
    });
    pad.addEventListener('pointermove', function (e) {
      if (!on || SIG.path.length > 28000) return;
      var p = pt(e);
      if (Math.abs(p[0] - lx) + Math.abs(p[1] - ly) < 1.2) return;
      lx = p[0]; ly = p[1];
      SIG.path += ' L' + fx(lx) + ' ' + fx(ly);
      path.setAttribute('d', SIG.path);
    });
    var end = function () {
      if (!on) return; on = false;
      if (/M[\d.]+ [\d.]+$/.test(SIG.path)) { SIG.path += ' L' + fx(lx + 0.5) + ' ' + fx(ly + 0.5); path.setAttribute('d', SIG.path); }
      var c = document.querySelector('[data-docx="clear"]'); if (c) c.hidden = !SIG.path;
    };
    pad.addEventListener('pointerup', end); pad.addEventListener('pointercancel', end); pad.addEventListener('lostpointercapture', end);
  }
  function docAct(a, btn) {
    var id = openDoc.id;
    if (a === 'close') { openDoc = { id: null, step: '', data: null, codeSent: false }; load(); return; }
    if (a === 'continue') { openDoc.step = 'view'; docBody(); return; }
    if (a === 'clear') { SIG.path = ''; var pad = $('crPad'); if (pad) { pad.querySelector('path').setAttribute('d', ''); pad.querySelector('.qs-pad-hint').hidden = false; } btn.hidden = true; return; }
    if (a === 'code') {
      btn.disabled = true;
      db.functions.invoke('hiring-mail', { body: { kind: 'code', key: key, docId: id, device: deviceOf() } }).then(function (r) {
        var x = r.data || {};
        btn.disabled = false;
        if (r.error || x.error) { docSay(DOCSAID[x.error] || DOCSAID['not-sent']); return; }
        openDoc.codeSent = true; docBody();
        if ($('crCode')) $('crCode').focus();
      }).catch(function () { btn.disabled = false; docSay(DOCSAID['not-sent']); });
      return;
    }
    if (a === 'open') {
      var code = ($('crCode').value || '').replace(/\s+/g, '');
      if (!/^[0-9]{6}$/.test(code)) { docSay('Enter the six-digit code.'); return; }
      btn.disabled = true;
      db.rpc('careers_doc_open', { p_key: key, p_doc: id, p_code: code, p_device: deviceOf() }).then(function (r) {
        var x = r.data || {};
        btn.disabled = false;
        if (r.error) throw r.error;
        if (x.error) { docSay(DOCSAID[x.error] || W.notSentAdspace); return; }
        keepView(id, x.view); openDoc.data = x; openDoc.step = 'caution'; docBody();
      }).catch(function () { btn.disabled = false; docSay('The document could not be opened. Please try again, or contact ADspace.'); });
      return;
    }
    if (a === 'pdf') {
      if (!window.ADspaceHrDocs) return;
      btn.disabled = true;
      var d = openDoc.data;
      window.ADspaceHrDocs.bytes({ id: openDoc.id, kind: d.kind, serial: d.serial, sent_at: d.sent_at, terms: d.terms, name: d.name, signatory: d.signatory },
        d.pay, { key: key }).then(function (b) {
        btn.disabled = false;
        return window.ADspaceDocs.save(new Blob([b], { type: 'application/pdf' }), window.ADspaceHrDocs.fileName(d), window.ADspaceDocs.tabFor && window.ADspaceDocs.tabFor());
      }).catch(function () { btn.disabled = false; docSay('The document could not be generated. Please try again.'); });
      return;
    }
    if (a === 'decline' && $('crDeclineBox').hidden) { $('crDeclineBox').hidden = false; btn.textContent = 'Decline offer'; return; }
    var pl = { name: ($('crName').value || '').trim(), agree: $('crAgree') && $('crAgree').checked, device: deviceOf() };
    if (a === 'decline') pl = { note: ($('crDecline').value || '').trim() };
    else if (a === 'sign') { pl.id_no = ($('crIdNo').value || '').trim().toUpperCase(); pl.signature = SIG.path; }
    if (a !== 'decline') {
      if (pl.name.length < 2) { docSay(DOCSAID['bad-name']); $('crName').focus(); return; }
      if (a === 'sign' && !/^([0-9]{6}-[0-9]{2}-[0-9]{4}|[A-Z0-9]{6,20})$/.test(pl.id_no)) { docSay(DOCSAID['bad-id']); $('crIdNo').focus(); return; }
      if (a === 'sign' && !SIG.path) { docSay(DOCSAID['bad-signature']); $('crPad').setAttribute('aria-invalid', 'true'); return; }
      if (!pl.agree) { docSay(DOCSAID['bad-agree']); return; }
    }
    btn.disabled = true;
    db.rpc('careers_doc_answer', { p_key: key, p_doc: id, p_view: viewOf(id), p_answer: a, p_payload: pl }).then(function (r) {
      var x = r.data || {};
      if (r.error) throw r.error;
      if (x.error) {
        btn.disabled = false;
        if (x.error === 'code-needed') { keepView(id, ''); openDoc.step = ''; openDoc.codeSent = false; docBody(); }
        docSay(DOCSAID[x.error] || W.notSentAdspace);
        return;
      }
      openDoc = { id: null, step: '', data: null, codeSent: false }; keepView(id, '');
      load();
    }).catch(function () { btn.disabled = false; docSay(W.notSentAdspace || 'Not sent. Please try again.'); });
  }
  function wireDocs() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-docopen]'), function (b) {
      b.addEventListener('click', function () {
        var id = b.getAttribute('data-docopen');
        openDoc = { id: id, step: '', data: null, codeSent: false };
        var v = viewOf(id);
        if (!v) { load(); return; }
        db.rpc('careers_doc_read', { p_key: key, p_doc: id, p_view: v }).then(function (r) {
          var x = r.data || {};
          if (!r.error && x.ok) { openDoc.data = Object.assign(x, { view: v }); openDoc.step = 'caution'; } else keepView(id, '');
          load();
        }).catch(function () { load(); });
      });
    });
    if (openDoc.id) docBody();
  }
  /* With documents sent, where the application stands is theirs. */
  function docStatus(d) {
    var l = d.docs || [];
    if (!l.length) return '';
    if (l.some(function (x) { return x.state === 'sent'; })) return 'Awaiting your reply';
    if (l.some(function (x) { return x.state === 'signed'; })) return 'Awaiting ADspace confirmation';
    var of = function (k) { return l.filter(function (x) { return x.kind === k; }).pop(); }, c = of('contract'), o = of('offer'), last = c || o;
    if (c && c.state === 'confirmed') return 'Contract confirmed';
    if (last.state === 'confirmed') return 'Offer accepted';
    if (last.state === 'declined') return 'Offer declined';
    return last.kind === 'contract' ? 'Contract expired' : 'Offer expired';
  }
  function paint(d) {
    var i = d.interview, dec = decision(d);
    root().innerHTML = '<div class="qs-step cr-page" data-shown>' +
      '<div class="qs-top"><h1 class="qs-title">Your application</h1>' +
      '<p class="qs-lead">Dear ' + esc(d.name) + ', thank you for your interest in joining ADspace.</p></div>' +
      '<dl class="ovfacts cr-facts"><div><dt>Position</dt><dd>' + esc(d.position) + '</dd></div>' +
      '<div><dt>Received on</dt><dd>' + esc(day(d.received_at)) + '</dd></div>' +
      '<div><dt>Status</dt><dd>' + esc(docStatus(d) || (i && i.state === 'cancelled' ? STATUS.cancelled : '') || (i && i.state === 'picked' ? STATUS.pending : '') || (d.stage === 'interview' && i && i.held ? STATUS.held : '') || STATUS[d.stage] || STATUS.received) + '</dd></div></dl>' +
      (d.docs && d.docs.length ? docsSection(d.docs) : (dec || (i ? interview(i) : '<p class="cr-next">' + esc(NEXT.received) + '</p>'))) + '</div>';
    if (!(d.docs && d.docs.length) && !dec && i && i.state === 'invited') wire();
    if ($('crPool')) wirePool();
    if ($('crDocs')) wireDocs();
  }
  function wire() {
    var send = $('crSend');
    Array.prototype.forEach.call(document.querySelectorAll('input[name=crTime]'), function (r) {
      r.addEventListener('change', function () {
        Array.prototype.forEach.call(document.querySelectorAll('#crIv .qs-pick'), function (l) { l.classList.toggle('is-on', l.querySelector('input').checked); });
        var none = r.value === 'none' && r.checked;
        $('crNoneBox').hidden = !none;
        send.textContent = none ? 'Send' : 'Confirm time';
        say('');
      });
    });
    send.addEventListener('click', function () {
      var on = document.querySelector('input[name=crTime]:checked');
      if (!on) { say('Please choose a time.'); return; }
      send.disabled = true;
      var ask = on.value === 'none' ? db.rpc('careers_none', { p_key: key, p_note: ($('crNone').value || '').trim() || null })
        : db.rpc('careers_pick', { p_key: key, p_slot: Number(on.value) });
      ask.then(function (r) {
        var x = r.data || {};
        if (r.error) throw r.error;
        if (x.error === 'slot-past') { send.disabled = false; say('This time has passed. Please choose another time.'); return; }
        if (x.error) { load(); return; }
        load();
      }).catch(function () { send.disabled = false; say(W.notSentAdspace || 'Not sent. Please try again.'); });
    });
  }
  function say(t) { t = reach(t); var m = $('crMsg'); if (m) { m.textContent = t; m.className = 'msg' + (t ? ' err' : ''); } }
  if (!db) { cover(W.failTitle, W.failTextAdspace); return; }
  function load() {
    db.rpc('careers_read', { p_key: key }).then(function (r) {
      var d = r.data || {};
      if (r.error) throw r.error;
      if (d.contact) CONTACT = d.contact;
      if (d.error === 'expired') { cover('Link expired', W.contactAdspace); return; }
      if (d.error || !d.ok) { cover(W.notFound, W.contactAdspace); return; }
      paint(d);
    }).catch(function () { cover(W.failTitle, W.failTextAdspace); });
  }
  load();
})();
