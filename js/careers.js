/* A candidate's own page (2026-11-16, release H2 step A; HR-SPEC.md
 * decision 1): `/careers/?k={key}`, the one private link a candidate holds.
 * No account and no sign-in. It reads their name, the position and where the
 * application stands (`careers_read`), never a colleague, a note or a score.
 * English alone. The link ends after `hiring_link_days` without a step. */
(function () {
  var API = window.ADspaceAPI, db = API && API.client;
  var $ = function (id) { return document.getElementById(id); };
  var esc = window.ADspaceWords.esc;
  var W = window.ADspaceWords.of({ en: {} }).en;
  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();
  var root = function () { return $('crRoot'); };
  function day(iso) { return window.ADspaceClock.date(iso, { long: true }); }
  function cover(title, text) {
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p></div></div></section>';
  }
  /* Where the application stands, in the candidate's words. The steps
     after Received arrive with the later releases. */
  var NEXT = {
    received: 'ADspace will contact you by email when there is a next step. The next step will also be shown on this page.'
  };
  var STATUS = { received: 'Application received', invited: 'Invited to an interview', interview: 'Interview confirmed',
    offer: 'Offer to follow', pool: 'Talent pool', closed: 'Application closed' };
  var MARK = '<span class="qs-mark" aria-hidden="true"><svg viewBox="0 0 16 16" width="12" height="12"><path d="M3.5 8.4l2.9 2.9 6.1-6.6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>';
  function when(iso) { return window.ADspaceClock.date(iso, { long: true }) + ', ' + window.ADspaceClock.clock(iso); }
  var ORG = window.ADSPACE_ORG || {};
  /* The interview (step B, HR-SPEC.md decision 2): the times offered to
     choose from, or other times asked for; once confirmed, when and where. */
  function interview(i) {
    if (!i) return '';
    var head = '<h2 class="qs-sec-h">Interview</h2>';
    if (i.state === 'invited') {
      return '<section class="qs-sec cr-iv" id="crIv">' + head +
        '<p class="cr-next">The interview will last ' + esc(i.minutes) + ' minutes and will be held ' + (i.mode === 'online' ? 'by Google Meet' : 'at our office') + '. Please choose a time. All times are Malaysia time.</p>' +
        (i.note ? '<p class="cr-note">' + esc(i.note) + '</p>' : '') +
        '<fieldset class="cr-picks" aria-label="Interview time">' + (i.slots || []).map(function (t, n) {
          return '<label class="qs-pick"><input type="radio" name="crTime" value="' + (n + 1) + '"><span class="qs-text"><b>' + esc(when(t)) + '</b></span>' + MARK + '</label>';
        }).join('') +
        '<label class="qs-pick"><input type="radio" name="crTime" value="none"><span class="qs-text"><b>None of these times</b></span>' + MARK + '</label></fieldset>' +
        '<div class="field" id="crNoneBox" hidden><label for="crNone">Times that suit you</label>' +
          '<textarea class="textarea" id="crNone" rows="2" maxlength="300" placeholder="Optional"></textarea></div>' +
        '<p class="msg" id="crMsg"></p>' +
        '<div class="qs-foot"><button class="btn btn-primary" type="button" id="crSend">Confirm time</button></div></section>';
    }
    if (i.state === 'picked') return '<section class="qs-sec cr-iv">' + head + '<dl class="ovfacts cr-facts"><div><dt>Time chosen</dt><dd>' + esc(when(i.at)) +
      '</dd></div><div><dt>Length</dt><dd>' + esc(i.minutes) + ' minutes</dd></div><div><dt>Where</dt><dd>' + (i.mode === 'online' ? 'Google Meet' : 'At our office') + '</dd></div></dl><p class="cr-next">ADspace will confirm the interview by email.</p></section>';
    if (i.state === 'none') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will send you other times by email.</p></section>';
    if (i.state === 'confirmed') {
      var where = i.mode === 'online'
        ? (i.link ? '<a class="btn btn-primary" href="' + esc(i.link) + '" target="_blank" rel="noopener">Join Google Meet</a>' : '')
        : '<a class="btn" href="' + esc(ORG.map || '#') + '" target="_blank" rel="noopener">Get directions</a>';
      return '<section class="qs-sec cr-iv">' + head + '<dl class="ovfacts cr-facts"><div><dt>Date and time</dt><dd>' + esc(when(i.at)) + '</dd></div>' +
        '<div><dt>Length</dt><dd>' + esc(i.minutes) + ' minutes</dd></div>' +
        '<div><dt>Where</dt><dd class="is-pre">' + (i.mode === 'online' ? 'Google Meet' : esc((ORG.name || 'ADSPACE PLT') + '\n' + (ORG.address || ''))) + '</dd></div></dl>' +
        (where ? '<div class="qs-foot">' + where + '</div>' : '') + '</section>';
    }
    return '';
  }
  /* The decision (step C): Keep in talent pool asks the candidate to agree;
     Not proceed, or a pool declined, reads closed; Proceed waits on the offer. */
  function decision(d) {
    var head = '';
    if (d.stage === 'offer') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will contact you by email about an offer.</p></section>';
    if (d.stage === 'closed') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">' +
      'ADspace will not be proceeding with your application at this time. We wish you every success in your search.</p></section>';
    var p = d.pool;
    if (d.stage !== 'pool' || !p) return '';
    if (p.consent === 'yes') return '<section class="qs-sec cr-iv">' + head + '<p class="cr-next">ADspace will keep your application until ' +
      esc(window.ADspaceClock.date(p.until, { long: true })) + ' and may contact you about future positions. Your details will then be deleted.</p></section>';
    return '<section class="qs-sec cr-iv" id="crPool"><h2 class="qs-sec-h">Talent pool</h2>' +
      '<p class="cr-next">There is no suitable opening for you at this time. ADspace would like to keep your application for ' + esc(p.months) +
      ' months, so that we may contact you about future positions. If you do not agree, your details will be deleted.</p>' +
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
  function paint(d) {
    var i = d.interview, dec = decision(d);
    root().innerHTML = '<div class="qs-step cr-page" data-shown>' +
      '<div class="qs-top"><h1 class="qs-title">Your application</h1>' +
      '<p class="qs-lead">Dear ' + esc(d.name) + ', thank you for your interest in joining ADspace.</p></div>' +
      '<dl class="ovfacts cr-facts"><div><dt>Position</dt><dd>' + esc(d.position) + '</dd></div>' +
      '<div><dt>Received on</dt><dd>' + esc(day(d.received_at)) + '</dd></div>' +
      '<div><dt>Status</dt><dd>' + esc(STATUS[d.stage] || STATUS.received) + '</dd></div></dl>' +
      (dec || (i ? interview(i) : '<p class="cr-next">' + esc(NEXT.received) + '</p>')) + '</div>';
    if (!dec && i && i.state === 'invited') wire();
    if ($('crPool')) wirePool();
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
  function say(t) { var m = $('crMsg'); if (m) { m.textContent = t; m.className = 'msg' + (t ? ' err' : ''); } }
  if (!db) { cover(W.failTitle, W.failTextAdspace); return; }
  if (!/^[a-z0-9]{8}$/.test(key)) { cover(W.notFound, W.contactAdspace); return; }
  function load() {
    db.rpc('careers_read', { p_key: key }).then(function (r) {
      var d = r.data || {};
      if (r.error) throw r.error;
      if (d.error === 'expired') { cover('Link expired', W.contactAdspace); return; }
      if (d.error || !d.ok) { cover(W.notFound, W.contactAdspace); return; }
      paint(d);
    }).catch(function () { cover(W.failTitle, W.failTextAdspace); });
  }
  load();
})();
