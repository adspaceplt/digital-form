/*
 * Health — a colleague's own check-in every half month, and every
 * colleague's for the holders of Team: Health (2026-10-07).
 *
 * Health is sensitive personal data (PDPA 2010, s.40), so nothing is asked
 * before the colleague agrees, in My Records, Health, and withdrawing takes their
 * answers out of Team: Health. What each reader is sent is the database's
 * decision (`health_*` functions; no table is readable directly): the
 * colleague their own, Team: Health (`team.health`, a granted part, an
 * admin's by itself) everybody's by name while their agreement stands. The
 * answers never reach a performance review, the Activity record or the
 * words of a notification.
 *
 * Health's own colour (`--health`, a Pantone pink) marks its glyph and its
 * chosen answers, nothing else.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  var UI = window.ADspaceState;
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function msg(id, text, kind) {
    var el = $(id); if (!el) return;
    el.textContent = text || ''; el.className = 'msg' + (kind ? ' ' + kind : '');
  }

  /* Five scales, 5 is well on each, a word for every step. */
  var SCALES = [
    ['body', 'Body', ['Unwell', 'Not great', 'Okay', 'Well', 'Very well']],
    ['mind', 'Mind', ['Struggling', 'Stressed', 'Okay', 'Calm', 'Very calm']],
    ['sleep', 'Sleep', ['Very poor', 'Poor', 'Okay', 'Good', 'Very good']],
    ['energy', 'Energy', ['Drained', 'Low', 'Okay', 'Good', 'Full of energy']],
    ['workload', 'Workload', ['Overwhelming', 'Heavy', 'Busy but fine', 'Manageable', 'Comfortable']]
  ];
  var HEART = '<svg class="health-mark" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7a4.3 4.3 0 0 1 7.5 2.8C19.5 15.4 12 20 12 20Z"/>' +
    '<path d="M7 12.5h2.6l1.4-2.6 2.2 4.6 1.3-2h2.5"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>';
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';

  var SAID = {
    'no-consent': 'Agree to the check-ins first.',
    'not-agreed': 'There is no agreement to withdraw.',
    'incomplete': 'Answer all five.',
    'bad-score': 'Each answer is 1 to 5.',
    'too-long': 'Keep the note to 1,000 characters.',
    'bad-colleague': 'Choose a colleague.',
    'already-asked': 'You have already asked them. Withdraw that request first.',
    'bad-status': 'That cannot be changed from here.',
    'not-found': 'Not found.',
    'denied': 'Your group cannot open health check-ins.',
    'not-team': 'Only a team member can open this.'
  };
  function said(d) {
    if (!d || !d.error) return '';
    if (d.error === 'db') {
      return /Could not find the function|schema cache|PGRST202/i.test(d.message || '')
        ? 'This needs a database update. Ask an admin to run the latest migration.' : (d.message || 'Not saved.');
    }
    return SAID[d.error] || d.error;
  }
  function call(fn, args, then) {
    var done = false;
    var back = function (d) { if (done) return; done = true; then(d || {}); };
    try {
      db.rpc(fn, args || {}).then(function (r) {
        if (r.error) { back({ error: 'db', message: r.error.message }); return; }
        back(r.data || {});
      }).catch(function (e) { back({ error: 'db', message: String((e && e.message) || e) }); });
    } catch (e) { back({ error: 'db', message: String((e && e.message) || e) }); }
  }
  /* The colleague's own reads go through My Records' call, so a proof gone stale
     puts the lock back over the whole of My Records. */
  function mineCall(fn, args, then) {
    var P = window.ADspacePerf;
    if (P && P.mineCall) P.mineCall(fn, args, then); else call(fn, args, then);
  }

  function dateWord(s) {
    if (!s) return '';
    var d = new Date(String(s).length === 10 ? s + 'T00:00:00' : s);
    if (isNaN(d)) return String(s);
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
  }
  /* A half month: 1 to 15 Oct 2026, 16 to 31 Oct 2026. */
  function halfWord(half, end) {
    var a = new Date(half + 'T00:00:00'), b = new Date(end + 'T00:00:00');
    if (isNaN(a) || isNaN(b)) return '';
    return a.getDate() + ' to ' + b.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
  }
  function word(k, v) {
    var s = SCALES.filter(function (x) { return x[0] === k; })[0];
    return s && v ? s[2][v - 1] : '';
  }
  /* A low answer is a caution, never a colour alone: the figure carries its word. */
  function figure(k, v) {
    if (!v) return '<span class="health-dash">—</span>';
    return '<span class="health-fig' + (v <= 2 ? ' is-low' : '') + '" title="' + esc(word(k, v)) + '">' + v + '</span>';
  }

  var st = { mine: null, team: null, person: null };

  // ---- The colleague's own -------------------------------------------------------------
  function enterMine() {
    var box = $('mineHealthBox');
    if (!box) return;
    if (!st.mine) UI.skeleton(box, 2);
    mineCall('health_mine', {}, function (d) {
      if (d.error) { UI.failLine(box, 'Your health check-ins', said(d), enterMine); return; }
      st.mine = d;
      paintMine();
    });
  }
  function agreed(d) { return Boolean(d && d.consent && !d.consent.withdrawn_at); }
  /* A card: its title (with a mute line under it where given), its one
     control at the right, then what it holds. */
  function card(title, ctl, inner, cls, meta) {
    var h = '<h3 class="health-h">' + title + '</h3>';
    return '<div class="ovcard health-card' + (cls ? ' ' + cls : '') + '"><div class="ovsec">' +
      '<div class="ovsec-head refl-head">' +
        (meta ? '<span class="health-hd">' + h + '<small class="health-meta">' + esc(meta) + '</small></span>' : h) +
      (ctl ? '<span class="refl-ctl">' + ctl + '</span>' : '') + '</div>' + inner + '</div></div>';
  }
  /* Before a colleague agrees, the company's own words come first (the user,
     2026-10-07: say that ADspace cares about their health at work and at
     home, ask for honest answers, and invite them to seek help), then what
     agreeing means. The one place in the console that speaks as "we". */
  var CARE = [
    'Life at work and life at home both shape how you feel, in body and in mind, and we care about all of it. ' +
      'Every two weeks, take a quiet moment to tell us how you really are.',
    'Please answer honestly. There are no right or wrong answers, only a true picture that helps us look after you. ' +
      'If something feels heavy, ask for a talk: reaching out early is a strength, and we would always rather hear from you and help.'
  ];
  var TERMS = [
    'Every two weeks: five questions on your body, mind, sleep, energy and workload, each from 1 to 5, with a note if you wish.',
    'ADspace management reads your answers with your name, only to understand how you are and to support you.',
    'Your answers are never part of your performance review.',
    'You can withdraw at any time here, and your answers leave management\'s view.'
  ];
  function paintMine() {
    var d = st.mine, box = $('mineHealthBox');
    if (!d || !box) return;
    if (!agreed(d)) {
      var gone = d.consent && d.consent.withdrawn_at;
      box.innerHTML = card(HEART + 'Your health matters to us', '',
        '<div class="health-cols"><div class="health-words">' +
          (gone ? '<p class="health-gone">You withdrew on ' + esc(dateWord(d.consent.withdrawn_at)) + '.</p>' : '') +
          CARE.map(function (t) { return '<p class="health-lead">' + esc(t) + '</p>'; }).join('') + '</div>' +
          '<div class="health-termbox"><h4 class="health-sub">What you agree to</h4>' +
          '<ul class="health-terms">' + TERMS.map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('') + '</ul></div></div>' +
        '<div class="row acts refl-acts"><button class="btn btn-primary" data-a="agree" type="button">' + (gone ? 'Agree again' : 'I agree') + '</button></div>',
        'health-consent');
      wireMine();
      return;
    }
    var cur = (d.history || []).filter(function (c) { return c.half === d.half; })[0];
    /* The five answers across the card, the note under them. A low answer,
       with no talk already asked for, opens Talks with a word of care. */
    var low = cur && SCALES.some(function (s) { return Number(cur.scales[s[0]]) <= 2; });
    var asking = (d.asked || []).some(function (t) { return t.status === 'open'; });
    var html = card(HEART + 'Check-in, ' + esc(halfWord(d.half, d.half_end)),
      cur ? '<button class="btn btn-sm" data-a="checkin" type="button">' + PEN + 'Edit</button>' : '',
      cur ? '<dl class="facts health-facts">' + SCALES.map(function (s) {
              var v = cur.scales[s[0]];
              return '<div><dt>' + esc(s[1]) + '</dt><dd>' + figure(s[0], v) + '<span class="health-word">' + esc(word(s[0], v)) + '</span></dd></div>';
            }).join('') + (cur.note ? '<div class="health-notecell"><dt>Note</dt><dd class="health-note">' + esc(cur.note) + '</dd></div>' : '') + '</dl>'
          : '<p class="health-lead">How are you feeling today?</p>' +
            '<div class="row acts refl-acts"><button class="btn btn-primary" data-a="checkin" type="button">Check in</button></div>',
      '', cur ? 'Checked in on ' + dateWord(cur.at) : 'Open until ' + dateWord(d.half_end));
    var past = (d.history || []).filter(function (c) { return c.half !== d.half; });
    if (past.length) {
      html += card('Your check-ins', '',
        '<div class="health-table" role="table" aria-label="Your check-ins">' +
          '<div class="health-hrow" role="row"><span role="columnheader">Half month</span>' +
            SCALES.map(function (s) { return '<span role="columnheader">' + esc(s[1]) + '</span>'; }).join('') + '</div>' +
          past.map(function (c) {
            return '<div class="health-trow" role="row"><span class="health-when" role="cell">' + esc(halfWord(c.half, c.half_end)) + '</span>' +
              SCALES.map(function (s) {
                return '<span class="health-cell" role="cell"><span class="health-cell-k">' + esc(s[1]) + '</span>' + figure(s[0], c.scales[s[0]]) + '</span>';
              }).join('') + '</div>';
          }).join('') +
        '</div>');
    }
    html += card('Talks', '<button class="btn btn-sm" data-a="talk" type="button">' + PLUS + 'Ask for a talk</button>',
      (low && !asking ? '<p class="health-care">Thank you for being honest with us. If something is weighing on you, a talk can help.</p>' : '') +
      talksHtml(d));
    /* The agreement is a standing fact, so a quiet line at the foot, not a card. */
    html += '<div class="health-agree"><span>Agreed on ' + esc(dateWord(d.consent.agreed_at)) + '</span>' +
      '<button class="btn btn-sm btn-quiet" data-a="withdraw" type="button">Withdraw</button></div>';
    box.innerHTML = html;
    wireMine();
  }
  function talksHtml(d) {
    var rows = [];
    (d.asked_me || []).forEach(function (t) {
      rows.push('<div class="health-talk' + (t.status === 'open' ? '' : ' is-closed') + '">' +
        '<span class="health-talk-who"><b>' + esc(t.from) + (t.status === 'open' ? ' would like to talk' : '') + '</b>' +
          '<small>' + esc(t.status === 'done' ? 'Talked · ' + dateWord(t.closed_at) : 'Asked ' + dateWord(t.at)) + '</small>' +
          (t.note ? '<span class="health-note">' + esc(t.note) + '</span>' : '') + '</span>' +
        '<span class="health-talk-act"><button class="btn btn-sm" type="button" data-talk="' + esc(t.id) + '" data-to="' +
          (t.status === 'open' ? 'done">Mark as done' : 'open">Reopen') + '</button></span></div>');
    });
    (d.asked || []).forEach(function (t) {
      rows.push('<div class="health-talk' + (t.status === 'open' ? '' : ' is-closed') + '">' +
        '<span class="health-talk-who"><b>Asked ' + esc(t.with) + '</b>' +
          '<small>' + esc(t.status === 'open' ? 'Asked ' + dateWord(t.at) : t.status === 'done' ? 'Talked · ' + dateWord(t.closed_at) : 'Withdrawn · ' + dateWord(t.closed_at)) + '</small>' +
          (t.note ? '<span class="health-note">' + esc(t.note) + '</span>' : '') + '</span>' +
        '<span class="health-talk-act">' + (t.status === 'open'
          ? '<button class="btn btn-sm" type="button" data-talk="' + esc(t.id) + '" data-to="withdrawn">Withdraw</button>'
          : t.status === 'withdrawn' ? '<button class="btn btn-sm" type="button" data-talk="' + esc(t.id) + '" data-to="open">Ask again</button>' : '') +
        '</span></div>');
    });
    return rows.length ? '<div class="health-talks">' + rows.join('') + '</div>' : '<p class="perf-quiet">No talks.</p>';
  }
  function wireMine() {
    var box = $('mineHealthBox');
    var on = function (a, f) {
      Array.prototype.forEach.call(box.querySelectorAll('[data-a="' + a + '"]'), function (b) {
        b.addEventListener('click', function () { f(b); });
      });
    };
    on('agree', agree);
    on('checkin', function (b) { openCheckin(b); });
    on('talk', function (b) { openTalk(b); });
    on('withdraw', withdraw);
    Array.prototype.forEach.call(box.querySelectorAll('[data-talk]'), function (b) {
      b.addEventListener('click', function () { setTalk(b); });
    });
  }
  /* Agreeing never asks: the card above the button is the question. */
  function agree(b) {
    b.disabled = true;
    mineCall('health_consent', { p_on: true }, function (d) {
      b.disabled = false;
      if (d.error) { msg('mineHealthMsg', said(d), 'err'); return; }
      msg('mineHealthMsg', '');
      st.mine = d; paintMine();
    });
  }
  /* Withdrawing asks, and says what it does; agreeing again is the way back. */
  function withdraw(b) {
    window.ADspaceConfirm.ask({
      title: 'Withdraw your agreement',
      body: 'Check-ins stop, and your answers leave management\'s view. You can agree again at any time.',
      go: 'Withdraw', tone: 'warn'
    }, function () {
      b.disabled = true;
      mineCall('health_consent', { p_on: false }, function (d) {
        b.disabled = false;
        if (d.error) { msg('mineHealthMsg', said(d), 'err'); return; }
        msg('mineHealthMsg', '');
        st.mine = d; paintMine();
      });
    });
  }
  function setTalk(b) {
    var to = b.getAttribute('data-to');
    b.disabled = true;
    mineCall('health_talk_set', { p_id: b.getAttribute('data-talk'), p_status: to }, function (d) {
      b.disabled = false;
      if (d.error) { msg('mineHealthMsg', said(d), 'err'); return; }
      msg('mineHealthMsg', '');
      st.mine = d; paintMine();
    });
  }

  // The check-in sheet: five scales as segments, the word for the one chosen.
  function openCheckin(opener) {
    var d = st.mine || {};
    var cur = (d.history || []).filter(function (c) { return c.half === d.half; })[0];
    $('healthSheetTitle').textContent = 'Check-in, ' + halfWord(d.half, d.half_end);
    SCALES.forEach(function (s) {
      var sel = $('hcS_' + s[0]);
      sel.value = cur ? String(cur.scales[s[0]]) : '';
      if (window.ADspaceForm && window.ADspaceForm.paint) window.ADspaceForm.paint(sel);
      sayScale(s[0]);
    });
    $('hcNote').value = (cur && cur.note) || '';
    msg('hcMsg', '');
    window.ADspaceSheet.show($('healthSheet'), { opener: opener });
  }
  function sayScale(k) {
    var sel = $('hcS_' + k), out = $('hcW_' + k);
    if (out) out.textContent = sel.value ? word(k, Number(sel.value)) : '';
  }
  SCALES.forEach(function (s) {
    var sel = $('hcS_' + s[0]);
    if (sel) sel.addEventListener('change', function () { sayScale(s[0]); });
  });
  if ($('healthSheet')) {
    $('hcClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('hcCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('hcSave').addEventListener('click', function () {
      var b = this, scores = {}, miss = null;
      SCALES.forEach(function (s) {
        var v = Number($('hcS_' + s[0]).value);
        if (!v && !miss) miss = s;
        scores[s[0]] = v;
      });
      if (miss) {
        msg('hcMsg', 'Answer ' + miss[1] + '.', 'err');
        if (window.ADspaceForm && window.ADspaceForm.reveal) window.ADspaceForm.reveal($('hcS_' + miss[0]));
        return;
      }
      b.disabled = true;
      mineCall('health_checkin_save', { p_scores: scores, p_note: $('hcNote').value }, function (d) {
        b.disabled = false;
        if (d.error) { msg('hcMsg', said(d), 'err'); return; }
        window.ADspaceSheet.clean();
        window.ADspaceSheet.close();
        msg('mineHealthMsg', '');
        st.mine = d; paintMine();
      });
    });
  }

  // Ask for a talk: who with, and what about if the colleague wishes.
  function openTalk(opener) {
    var d = st.mine || {}, sel = $('talkWith');
    var F = window.ADspaceForm;
    var list = (d.colleagues || []).slice().sort(F && F.byStaff ? F.byStaff : function () { return 0; });
    sel.innerHTML = '<option value="">Choose a colleague</option>' + list.map(function (c) {
      return '<option value="' + esc(c.id) + '">' + esc(F && F.named ? F.named(c.staff_code, c.name) : c.name) + '</option>';
    }).join('');
    if (F && F.paint) F.paint(sel);
    $('talkNote').value = '';
    msg('talkMsg', '');
    window.ADspaceSheet.show($('talkSheet'), { opener: opener });
  }
  if ($('talkSheet')) {
    $('talkClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('talkCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('talkSave').addEventListener('click', function () {
      var b = this, who = $('talkWith').value;
      if (!who) { msg('talkMsg', 'Choose a colleague.', 'err'); $('talkWith').focus(); return; }
      b.disabled = true;
      mineCall('health_talk_ask', { p_with: who, p_note: $('talkNote').value }, function (d) {
        b.disabled = false;
        if (d.error) { msg('talkMsg', said(d), 'err'); return; }
        window.ADspaceSheet.clean();
        window.ADspaceSheet.close();
        msg('mineHealthMsg', '');
        st.mine = d; paintMine();
      });
    });
  }

  // ---- Team: Health ----------------------------------------------------------------------
  function enterTeam() {
    var box = $('teamHealthBox');
    if (!box) return;
    if (!st.team) UI.skeleton(box, 3);
    call('health_team', {}, function (d) {
      if (d.error) { UI.failLine(box, 'Health check-ins', said(d), enterTeam); return; }
      st.team = d;
      paintTeam();
    });
  }
  function thisHalf(p) { var h = st.team && st.team.half; return (p.checkins || []).filter(function (c) { return c.half === h; })[0]; }
  function paintTeam() {
    var d = st.team, box = $('teamHealthBox');
    if (!d || !box) return;
    var people = d.people || [];
    var standing = people.filter(function (p) { return p.consent && !p.consent.withdrawn_at; });
    var done = standing.filter(thisHalf);
    box.innerHTML = '';
    /* The half month at a glance: who has checked in, and the average of each
       scale among them, a low average in warn with its figure. */
    var head = document.createElement('div');
    head.className = 'ovcard health-card health-sum';
    head.innerHTML = '<div class="ovsec"><div class="ovsec-head refl-head"><h3 class="health-h">' + HEART +
      esc(halfWord(d.half, d.half_end)) + '</h3><span class="refl-ctl health-count">' +
      esc(done.length + ' of ' + standing.length + ' checked in') + '</span></div><div id="healthAvg"></div></div>';
    box.appendChild(head);
    if (done.length && window.ADspaceChart) {
      window.ADspaceChart.draw($('healthAvg'), {
        kind: 'bars', name: 'Average this half month', max: 5,
        fmt: function (v) { return (Math.round(v * 10) / 10).toFixed(1); },
        rows: SCALES.map(function (s) {
          var sum = done.reduce(function (a, p) { return a + Number(thisHalf(p).scales[s[0]] || 0); }, 0);
          var avg = sum / done.length;
          return { label: s[1], value: avg, tone: avg < 3 ? 'warn' : '' };
        })
      });
    } else {
      $('healthAvg').innerHTML = '<p class="perf-quiet">No check-ins this half month.</p>';
    }
    var G = window.ADspaceGroup;
    box.appendChild(G.section({
      route: 'team-health', key: 'people', name: 'Colleagues', count: people.length, shut: false,
      table: function () {
        var t = G.table('health-prow', ['Colleague'].concat(SCALES.map(function (s) { return s[1]; })).concat(['Checked in', '']));
        G.more(t, people, 30, '', personRow);
        return t;
      }
    }));
    var talks = d.talks || [];
    if (talks.length) {
      var tc = document.createElement('div');
      tc.className = 'ovcard health-card';
      tc.innerHTML = '<div class="ovsec"><div class="ovsec-head"><h3 class="health-h">Talks</h3></div><div class="health-talks">' +
        talks.map(function (t) {
          return '<div class="health-talk' + (t.status === 'open' ? '' : ' is-closed') + '"><span class="health-talk-who">' +
            '<b>' + esc(t.from) + ' asked ' + esc(t.with) + '</b><small>' +
            esc(t.status === 'done' ? 'Talked · ' + dateWord(t.closed_at) : 'Asked ' + dateWord(t.at)) + '</small>' +
            (t.note ? '<span class="health-note">' + esc(t.note) + '</span>' : '') + '</span></div>';
        }).join('') + '</div></div>';
      box.appendChild(tc);
    }
  }
  function stateOf(p) {
    if (!p.consent) return 'Not agreed';
    if (p.consent.withdrawn_at) return 'Withdrawn';
    return '';
  }
  function personRow(p) {
    var c = thisHalf(p), s = stateOf(p), last = (p.checkins || [])[0];
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'crm-row health-prow' + (s ? ' is-faded' : '');
    b.setAttribute('data-person', p.id);
    b.innerHTML = '<span class="health-who' + (c ? ' has-line' : '') + '"><b>' + esc(p.name) + '</b>' +
        '<small class="health-code">' + esc([p.staff_code, p.designation].filter(Boolean).join(' · ')) + '</small>' +
        (c ? '<small class="health-line">' + esc(SCALES.map(function (x) { return x[1] + ' ' + c.scales[x[0]]; }).join(' · ')) + '</small>' : '') +
      '</span>' +
      SCALES.map(function (x) { return '<span class="health-col">' + figure(x[0], c && c.scales[x[0]]) + '</span>'; }).join('') +
      '<span class="health-at">' + (s ? '<span class="chip">' + esc(s) + '</span>'
        : esc(c ? dateWord(c.at) : last ? 'Last ' + dateWord(last.at) : 'Not this half')) + '</span>' +
      '<span class="perf-chev" aria-hidden="true">' + CHEV + '</span>';
    b.addEventListener('click', function () { openPerson(p, b); });
    return b;
  }
  function openPerson(p, opener) {
    st.person = p;
    $('hpTitle').textContent = p.name;
    var s = stateOf(p), ck = p.checkins || [];
    var talks = ((st.team && st.team.talks) || []).filter(function (t) { return t.from_id === p.id || t.with_id === p.id; });
    $('hpBody').innerHTML =
      '<p class="perf-quiet">' + esc(s === 'Not agreed' ? 'Has not agreed to the check-ins.'
        : s === 'Withdrawn' ? 'Withdrew on ' + dateWord(p.consent.withdrawn_at) + '.'
        : 'Agreed on ' + dateWord(p.consent.agreed_at) + '.') + '</p>' +
      (ck.length ? ck.map(function (c) {
        return '<section class="fsec"><h4 class="fsec-h">' + esc(halfWord(c.half, c.half_end)) + '</h4>' +
          '<dl class="ovfacts health-facts">' + SCALES.map(function (x) {
            var v = c.scales[x[0]];
            return '<div><dt>' + esc(x[1]) + '</dt><dd>' + figure(x[0], v) + ' <span class="health-word">' + esc(word(x[0], v)) + '</span></dd></div>';
          }).join('') + (c.note ? '<div><dt>Note</dt><dd class="health-note">' + esc(c.note) + '</dd></div>' : '') + '</dl></section>';
      }).join('') : (s ? '' : '<p class="perf-quiet">No check-ins.</p>')) +
      (talks.length ? '<section class="fsec"><h4 class="fsec-h">Talks</h4><div class="health-talks">' + talks.map(function (t) {
        return '<div class="health-talk' + (t.status === 'open' ? '' : ' is-closed') + '"><span class="health-talk-who"><b>' +
          esc(t.from_id === p.id ? 'Asked ' + t.with : t.from + ' asked them') + '</b><small>' +
          esc(t.status === 'done' ? 'Talked · ' + dateWord(t.closed_at) : 'Asked ' + dateWord(t.at)) + '</small>' +
          (t.note ? '<span class="health-note">' + esc(t.note) + '</span>' : '') + '</span></div>';
      }).join('') + '</div></section>' : '');
    window.ADspaceSheet.show($('healthPersonSheet'), { opener: opener });
  }
  if ($('healthPersonSheet')) $('hpClose').addEventListener('click', function () { window.ADspaceSheet.close(); });

  window.ADspaceHealth = { enterMine: enterMine, enterTeam: enterTeam };
})();
