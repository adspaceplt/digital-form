/*
 * Health — a colleague's own check-in, and every colleague's for the
 * holders of Team: Health (2026-10-07). Since 2026-11-22 a mood check-in
 * after Apple Health's State of Mind, asked each week while the colleague's
 * planned work this week is near their weekly capacity, else each month;
 * the half-month check-ins before it stay readable as Earlier check-ins.
 *
 * Health is sensitive personal data (PDPA 2010, s.40), so nothing is asked
 * before the colleague agrees, in My records, Health, and withdrawing takes their
 * answers out of Team: Health. What each reader is sent is the database's
 * decision (`health_*` functions; no table is readable directly): the
 * colleague their own, Team: Health (an admin's alone, behind the
 * Performance master code) everybody's by name while their agreement stands. The
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
  var DOTS = window.ADspaceIcons.glyph('more');
  var UI = window.ADspaceState;
  function esc(s) { return window.ADspaceWords.esc(s); }
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
  /* The check-in since 2026-11-22: a mood of seven steps, a workload of
     five, and the feelings and influences chosen from the database's own
     lists (`health_mood_save`). */
  var MOOD = ['Very unpleasant', 'Unpleasant', 'Slightly unpleasant', 'Neutral', 'Slightly pleasant', 'Pleasant', 'Very pleasant'];
  var WORK = ['Overwhelming', 'Heavy', 'Busy', 'Manageable', 'Comfortable'];
  var FEEL = ['Calm', 'Content', 'Motivated', 'Confident', 'Grateful', 'Hopeful', 'Tired', 'Stressed', 'Anxious', 'Frustrated', 'Overwhelmed', 'Sad'];
  var INFL = ['Workload', 'Clients', 'Colleagues', 'Family', 'Friends', 'Health', 'Sleep', 'Finances'];
  var HEART = window.ADspaceIcons.glyph('pulse', 'health-mark');
  var PLUS = window.ADspaceIcons.glyph('plus');
  var PEN = window.ADspaceIcons.glyph('pen');
  var CHEV = window.ADspaceIcons.glyph('chevron');

  var SAID = {
    'no-consent': 'Agree to the check-ins first.',
    'not-agreed': 'There is no agreement to withdraw.',
    'stale-wording': 'These terms have changed. Read them again before agreeing.',
    'incomplete': 'Answer all five.',
    'stale-half': 'That half month has ended, so nothing was saved. Your answers are kept: save them for the half month now open.',
    'bad-score': 'Choose an answer from 1 to 5 for each.',
    'too-long': 'Enter a note of up to 1,000 characters.',
    'no-mood': 'Choose your mood.',
    'no-workload': 'Choose your workload.',
    'bad-tag': 'Choose each answer from its list.',
    'stale-period': 'Not saved. This check-in period has ended. Your answers are kept; save them for the current period.',
    'bad-colleague': 'Choose a colleague.',
    'already-asked': 'You have already asked them. Withdraw that request first.',
    'bad-status': 'This talk has changed. Refresh the page.',
    'not-found': 'This talk no longer exists.',
    'denied': 'You do not have permission to open Health check-ins. Please ask an admin.',
    'not-team': 'You do not have permission to open this page. Please ask an admin.'
  };
  function said(d) {
    if (!d || !d.error) return '';
    if (d.error === 'db') {
      return /Could not find the function|schema cache|PGRST202/i.test(d.message || '')
        ? 'This feature is not available yet. Please contact an admin.' : (d.message || 'Not saved.');
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
  /* The colleague's own reads go through My records' call, so a proof gone stale
     puts the lock back over the whole of My records. */
  function mineCall(fn, args, then) {
    var P = window.ADspacePerf;
    if (P && P.mineCall) P.mineCall(fn, args, then); else call(fn, args, then);
  }

  function dateWord(s) {
    if (!s) return '';
    return window.ADspaceClock.date(s) || String(s);
  }
  /* A half month: 1 to 15 Oct 2026, 16 to 31 Oct 2026. */
  function halfWord(half, end) {
    var CK = window.ADspaceClock, a = CK.parts(half), b = CK.date(end);
    return a && b ? a.d + ' to ' + b : '';
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
  function agreed(d) {
    return Boolean(d && d.consent && !d.consent.withdrawn_at &&
      (!d.wording || Number(d.consent.wording || 0) >= Number(d.wording.version)));
  }
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
     2026-10-07: say that the agency cares about their health at work and at
     home, ask for honest answers, and invite them to seek help), then what
     agreeing means. The one place in the console that speaks as "we". The
     words are the database's, each version kept whole (`health_wordings`,
     2026-10-18): `health_mine()` sends the latest, and a new version asks
     everyone to agree again. */
  function paintMine() {
    var d = st.mine, box = $('mineHealthBox');
    if (!d || !box) return;
    if (!agreed(d)) {
      var gone = d.consent && d.consent.withdrawn_at;
      var stale = d.consent && !gone;
      var w = d.wording;
      if (!w) { UI.failLine(box, 'Your health check-ins', said({ error: 'db', message: 'PGRST202' }), enterMine); return; }
      box.innerHTML = card(HEART + 'Your health matters to us', '',
        '<div class="health-cols"><div class="health-words">' +
          (gone ? '<p class="health-gone">You withdrew on ' + esc(dateWord(d.consent.withdrawn_at)) + '.</p>'
            : stale ? '<p class="health-gone">These terms changed on ' + esc(dateWord(w.made_at)) + '. Your check-ins resume once you agree to them.</p>' : '') +
          (w.care || []).map(function (t) { return '<p class="health-lead">' + esc(t) + '</p>'; }).join('') + '</div>' +
          '<div class="health-termbox"><h4 class="health-sub">What you agree to</h4>' +
          '<ul class="health-terms">' + (w.terms || []).map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('') + '</ul></div></div>' +
        '<div class="row acts refl-acts"><button class="btn btn-primary" data-a="agree" type="button">' + (gone || stale ? 'Agree again' : 'I agree') + '</button></div>',
        'health-consent');
      wireMine();
      return;
    }
    var per = d.period;
    if (!per) { UI.failLine(box, 'Your health check-ins', said({ error: 'db', message: 'PGRST202' }), enterMine); return; }
    var cur = per.current;
    /* The answers across the card, the note under them. A low mood or a
       heavy workload, with no talk already asked for, opens Talks with a
       word of care. */
    var low = cur && (Number(cur.mood) <= 2 || Number(cur.workload) <= 2);
    var asking = (d.asked || []).some(function (t) { return t.status === 'open'; });
    var metaLine = cur ? 'Checked in on ' + dateWord(cur.at)
      : 'Open until ' + window.ADspaceClock.date(per.end, { named: true });
    var html = card(HEART + esc(periodTitle(per)),
      cur ? '<button class="btn btn-sm" data-a="checkin" type="button">' + PEN + 'Edit</button>' : '',
      (per.kind === 'week' ? '<p class="health-why">This check-in is weekly while your planned work is near your weekly capacity.</p>' : '') +
      (cur ? moodFacts(cur, 'facts')
          : '<p class="health-lead">How are you feeling today?</p>' +
            '<div class="row acts refl-acts"><button class="btn btn-primary" data-a="checkin" type="button">Check in</button></div>'),
      'health-now', metaLine);
    var past = (d.moods || []).filter(function (c) { return !cur || c.id !== cur.id; });
    if (past.length) html += card('Your check-ins', '', moodTable(past));
    var old = d.history || [];
    if (old.length) {
      html += card('Earlier check-ins',
        '<button class="btn btn-sm btn-quiet" data-a="earlier" type="button" aria-expanded="false" aria-controls="healthEarlier">Show</button>',
        '<div id="healthEarlier" hidden>' + halfTable(old) + '</div>', 'health-earlier',
        old.length + (old.length === 1 ? ' half month' : ' half months') + ' · Body, Mind, Sleep, Energy and Workload');
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
  function periodTitle(per) { return per && per.kind === 'week' ? 'This week’s check-in' : 'This month’s check-in'; }
  function moodWord(v) { return v ? MOOD[v - 1] || '' : ''; }
  function workWord(v) { return v ? WORK[v - 1] || '' : ''; }
  function listWord(a) { return (a || []).length ? a.join(', ') : '—'; }
  /* A check-in's answers as facts: a low answer is a caution in words, never a colour alone. */
  function moodFacts(c, cls) {
    var lowM = Number(c.mood) <= 2, lowW = Number(c.workload) <= 2;
    return '<dl class="' + cls + ' health-facts hm-facts">' +
      '<div><dt>Mood</dt><dd><span class="health-word' + (lowM ? ' is-low' : '') + '">' + esc(moodWord(c.mood)) + '</span></dd></div>' +
      '<div><dt>Workload</dt><dd><span class="health-word' + (lowW ? ' is-low' : '') + '">' + esc(workWord(c.workload)) + '</span></dd></div>' +
      '<div><dt>Feelings</dt><dd class="hm-list">' + esc(listWord(c.feelings)) + '</dd></div>' +
      '<div><dt>Influences</dt><dd class="hm-list">' + esc(listWord(c.influences)) + '</dd></div>' +
      (c.note ? '<div class="health-notecell"><dt>Note</dt><dd class="health-note">' + esc(c.note) + '</dd></div>' : '') + '</dl>';
  }
  function moodTable(rows) {
    return '<div class="health-table hm-table" role="table" aria-label="Your check-ins">' +
      '<div class="health-hrow" role="row"><span role="columnheader">Checked in</span><span role="columnheader">Mood</span>' +
        '<span role="columnheader">Workload</span><span role="columnheader">Period</span></div>' +
      rows.map(function (c) {
        var tags = (c.feelings || []).concat(c.influences || []);
        return '<div class="health-trow" role="row"><span class="health-when" role="cell"><b>' + esc(dateWord(c.at)) + '</b>' +
            (tags.length ? '<small>' + esc(tags.join(' · ')) + '</small>' : '') + '</span>' +
          '<span class="health-cell" role="cell">' + esc(moodWord(c.mood)) + '</span>' +
          '<span class="health-cell hm-work" role="cell">' + esc(workWord(c.workload)) + '</span>' +
          '<span class="health-cell hm-per" role="cell">' + (c.period === 'week' ? 'Weekly' : 'Monthly') + '</span></div>';
      }).join('') + '</div>';
  }
  /* The half-month check-ins before 2026-11-22, as they were asked. */
  function halfTable(rows) {
    return '<div class="health-table" role="table" aria-label="Earlier check-ins">' +
      '<div class="health-hrow" role="row"><span role="columnheader">Half month</span>' +
        SCALES.map(function (s) { return '<span role="columnheader">' + esc(s[1]) + '</span>'; }).join('') + '</div>' +
      rows.map(function (c) {
        return '<div class="health-trow" role="row"><span class="health-when" role="cell">' + esc(halfWord(c.half, c.half_end)) + '</span>' +
          SCALES.map(function (s) {
            return '<span class="health-cell" role="cell"><span class="health-cell-k">' + esc(s[1]) + '</span>' + figure(s[0], c.scales[s[0]]) + '</span>';
          }).join('') + '</div>';
      }).join('') + '</div>';
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
          : t.status === 'withdrawn' ? '<button class="btn btn-sm" type="button" data-talk="' + esc(t.id) + '" data-to="open">Ask again</button>' +
            /* A withdrawn talk is the asker's alone, so its ⋯ holds Delete
               (2026-10-24). */
            '<span class="team-act"><button class="kmenu-btn" type="button" data-talkmenu aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
              '<div class="kmenu" hidden role="menu"><button class="kmenu-item is-danger" data-g="6" type="button" role="menuitem" data-talkdel="' +
                esc(t.id) + '" data-with="' + esc(t.with) + '">Delete</button></div></span>' : '') +
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
    on('earlier', function (b) {
      var open = b.getAttribute('aria-expanded') !== 'true';
      b.setAttribute('aria-expanded', String(open));
      b.textContent = open ? 'Hide' : 'Show';
      $('healthEarlier').hidden = !open;
    });
    Array.prototype.forEach.call(box.querySelectorAll('[data-talk]'), function (b) {
      b.addEventListener('click', function () { setTalk(b); });
    });
    Array.prototype.forEach.call(box.querySelectorAll('[data-talkmenu]'), function (mb) {
      var mn = mb.nextElementSibling;
      mb.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = mn.hidden;
        shutTalkMenus();
        mn.hidden = !open;
        mb.setAttribute('aria-expanded', String(open));
        if (open) window.ADspaceMenu.place(mb, mn);
      });
    });
    Array.prototype.forEach.call(box.querySelectorAll('[data-talkdel]'), function (b) {
      b.addEventListener('click', function () {
        shutTalkMenus();
        window.ADspaceConfirm.ask({ title: 'Delete this talk?',
          body: 'Your withdrawn request to talk with ' + b.getAttribute('data-with') + ' will be deleted. This cannot be undone.',
          go: 'Delete', tone: 'danger' }, function () { dropTalk(b.getAttribute('data-talkdel')); });
      });
    });
  }
  function shutTalkMenus() {
    var box = $('mineHealthBox');
    Array.prototype.forEach.call(box.querySelectorAll('[data-talkmenu]'), function (mb) {
      mb.setAttribute('aria-expanded', 'false');
      mb.nextElementSibling.hidden = true;
    });
  }
  function dropTalk(id) {
    mineCall('health_talk_delete', { p_id: id }, function (d) {
      if (d.error) { msg('mineHealthMsg', said(d), 'err'); return; }
      st.mine = d; paintMine();
      msg('mineHealthMsg', 'Deleted.', 'ok');
    });
  }
  /* Agreeing never asks: the card above the button is the question. */
  function agree(b) {
    b.disabled = true;
    var shown = st.mine && st.mine.wording && st.mine.wording.version;
    mineCall('health_consent', { p_on: true, p_wording: shown }, function (d) {
      b.disabled = false;
      if (d.error === 'stale-wording') {
        /* The words changed while the card was open: draw the new ones and say so. */
        mineCall('health_mine', {}, function (m) {
          if (!m.error) { st.mine = m; paintMine(); }
          msg('mineHealthMsg', said(d), 'err');
        });
        return;
      }
      if (d.error) { msg('mineHealthMsg', said(d), 'err'); return; }
      msg('mineHealthMsg', '');
      st.mine = d; paintMine();
    });
  }
  /* Withdrawing asks, and says what it does; agreeing again is the way back. */
  function withdraw(b) {
    window.ADspaceConfirm.ask({
      title: 'Withdraw your agreement?',
      body: 'Check-ins stop, and management will no longer see your answers. You can agree again at any time.',
      go: 'Withdraw', tone: 'warn'
    }, function () {
      b.disabled = true;
      mineCall('health_consent', { p_on: false, p_wording: (st.mine && st.mine.wording && st.mine.wording.version) || null }, function (d) {
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

  // The check-in sheet: the mood, the feelings and influences, the workload and a note.
  /* At a desk the whole check-in is one sheet; on a phone it is three short
     steps, each fitting above the tab bar, a choice never lost by moving
     back, and Save open on every step once a mood and a workload are
     chosen (the user, 2026-11-22). */
  var hc = { step: 1, phone: false };
  function tagsInto(host, list) {
    if (!host || host.children.length) return;
    host.innerHTML = list.map(function (w) {
      return '<button class="btn btn-sm hc-tag" type="button" aria-pressed="false" data-tag="' + esc(w) + '">' + esc(w) + '</button>';
    }).join('');
    host.addEventListener('click', function (e) {
      var b = e.target.closest('.hc-tag');
      if (!b) return;
      b.setAttribute('aria-pressed', String(b.getAttribute('aria-pressed') !== 'true'));
    });
  }
  function tagsSet(host, on) {
    Array.prototype.forEach.call(host.querySelectorAll('.hc-tag'), function (b) {
      b.setAttribute('aria-pressed', String((on || []).indexOf(b.getAttribute('data-tag')) >= 0));
    });
  }
  function tagsOf(host) {
    return Array.prototype.filter.call(host.querySelectorAll('.hc-tag'), function (b) {
      return b.getAttribute('aria-pressed') === 'true';
    }).map(function (b) { return b.getAttribute('data-tag'); });
  }
  function moodOf() {
    var r = document.querySelector('#hcMood input:checked');
    return r ? Number(r.value) : null;
  }
  function sayMood() { $('hcMoodWord').textContent = moodWord(moodOf()); }
  function showStep(n) {
    hc.step = n;
    var steps = document.querySelectorAll('#healthSheet .hc-step');
    Array.prototype.forEach.call(steps, function (x) { x.hidden = hc.phone && Number(x.getAttribute('data-step')) !== n; });
    $('hcSteps').hidden = $('hcTrack').hidden = !hc.phone;
    $('hcSteps').textContent = 'Step ' + n + ' of 3';
    $('hcTrack').firstElementChild.style.width = Math.round(n / 3 * 100) + '%';
    var last = !hc.phone || n === 3;
    $('hcNext').hidden = last;
    $('hcSave').className = 'btn ' + (last ? 'btn-primary' : 'btn-quiet');
    $('hcCancel').textContent = hc.phone && n > 1 ? 'Back' : 'Cancel';
  }
  function openCheckin(opener) {
    var d = st.mine || {}, per = d.period || {}, cur = per.current;
    /* The period the sheet shows is the one it saves into (2026-10-18). */
    st.sheetStart = per.start;
    $('healthSheetTitle').textContent = periodTitle(per);
    tagsInto($('hcFeel'), FEEL);
    tagsInto($('hcInfl'), INFL);
    Array.prototype.forEach.call(document.querySelectorAll('#hcMood input'), function (r) {
      r.checked = Boolean(cur) && Number(r.value) === Number(cur.mood);
    });
    sayMood();
    tagsSet($('hcFeel'), cur && cur.feelings);
    tagsSet($('hcInfl'), cur && cur.influences);
    var sel = $('hcWork');
    sel.value = cur ? String(cur.workload) : '';
    if (window.ADspaceForm && window.ADspaceForm.paint) window.ADspaceForm.paint(sel);
    $('hcNote').value = (cur && cur.note) || '';
    msg('hcMsg', '');
    hc.phone = window.matchMedia('(max-width: 640px)').matches;
    showStep(1);
    window.ADspaceSheet.show($('healthSheet'), { opener: opener });
  }
  /* What is missing names itself and opens its step. */
  function missing() {
    if (!moodOf()) return [1, 'no-mood', document.querySelector('#hcMood input')];
    if (!$('hcWork').value) return [3, 'no-workload', $('hcWork')];
    return null;
  }
  if ($('healthSheet')) {
    Array.prototype.forEach.call(document.querySelectorAll('#hcMood input'), function (r, i) {
      r.setAttribute('aria-label', MOOD[i]);
      r.addEventListener('change', sayMood);
    });
    $('hcClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('hcCancel').addEventListener('click', function () {
      if (hc.phone && hc.step > 1) { showStep(hc.step - 1); msg('hcMsg', ''); return; }
      window.ADspaceSheet.close();
    });
    $('hcNext').addEventListener('click', function () {
      if (hc.step === 1 && !moodOf()) { msg('hcMsg', said({ error: 'no-mood' }), 'err'); return; }
      msg('hcMsg', '');
      showStep(Math.min(3, hc.step + 1));
    });
    $('hcSave').addEventListener('click', function () {
      var b = this, miss = missing();
      if (miss) {
        if (hc.phone) showStep(miss[0]);
        msg('hcMsg', said({ error: miss[1] }), 'err');
        if (miss[2] && miss[2].focus) miss[2].focus();
        return;
      }
      b.disabled = true;
      mineCall('health_mood_save', { p_start: st.sheetStart, p_mood: moodOf(), p_workload: Number($('hcWork').value),
        p_feelings: tagsOf($('hcFeel')), p_influences: tagsOf($('hcInfl')), p_note: $('hcNote').value }, function (d) {
        b.disabled = false;
        if (d.error === 'stale-period') {
          /* The period ended while the sheet was open: nothing was kept,
             the answers stay, and the sheet now names the period open. */
          st.sheetStart = d.period && d.period.start;
          $('healthSheetTitle').textContent = periodTitle(d.period);
          msg('hcMsg', said(d), 'err');
          if ($('hcMsg').scrollIntoView) $('hcMsg').scrollIntoView({ block: 'nearest' });
          mineCall('health_mine', {}, function (m) { if (!m.error) { st.mine = m; paintMine(); } });
          return;
        }
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
  /* Team: Health is an admin's, behind the Performance master code
     (2026-10-18, Team audit 11): the same unlock, the same 15 minutes. */
  var P = function () { return window.ADspacePerf || {}; };
  var LOCKED = { 'code-needed': 1, 'no-code': 1, 'locked': 1 };
  function teamRead(host, then, again) {
    var tok = P().token ? P().token() : null;
    if (!tok) { lockCard(host, null, again); return; }
    call('health_team', { p_token: tok }, function (d) {
      if (d.error && LOCKED[d.error]) { if (P().keepToken) P().keepToken(null); lockCard(host, d, again); return; }
      then(d);
    });
  }
  function lockCard(host, why, again) {
    st.team = null;
    var said2 = P().said || said, blocked = why && why.error === 'no-code';
    host.innerHTML = '<div class="lockcard" data-glyph="lock">' +
      '<h3 class="lockcard-title">Health check-ins are locked</h3>' +
      (blocked ? '' : '<p class="lockcard-line">Unlocks for 15 minutes.</p>' +
        '<form class="lockcard-form" autocomplete="off">' +
        '<label class="field-label" for="healthCode">Master code</label>' +
        '<input class="input" id="healthCode" type="password" autocomplete="off" spellcheck="false" autocapitalize="off">' +
        '<button class="btn btn-primary" id="healthUnlock" type="submit">Unlock</button></form>') +
      '<div class="msg' + (why && why.error !== 'code-needed' ? ' err' : '') + '" id="healthLockMsg">' + esc(why ? said2(why) : '') + '</div></div>';
    var f = host.querySelector('form');
    if (!f) return;
    f.addEventListener('submit', function (e) {
      e.preventDefault();
      var code = $('healthCode').value, m = $('healthLockMsg');
      if (!code) { m.className = 'msg err'; m.textContent = 'Enter the master code.'; return; }
      $('healthUnlock').disabled = true;
      call('perf_unlock', { p_code: code }, function (d) {
        $('healthUnlock').disabled = false;
        $('healthCode').value = '';
        if (d.error) { m.className = 'msg err'; m.textContent = said2(d); return; }
        if (P().keepToken) P().keepToken(d.token);
        again();
      });
    });
  }
  function enterTeam() {
    var box = $('teamHealthBox');
    if (!box) return;
    if (!st.team) UI.skeleton(box, 3);
    teamRead(box, function (d) {
      if (d.error) { UI.failLine(box, 'Health check-ins', said(d), enterTeam); return; }
      st.team = d;
      paintTeam();
    }, enterTeam);
  }
  function paintTeam() {
    var d = st.team, box = $('teamHealthBox');
    if (!d || !box) return;
    /* A system account (2026-10-08) is no colleague to check on. */
    var S = window.ADspaceAdmin;
    var people = (d.people || []).filter(function (p) { return !(S && S.isSystem && S.isSystem(p.team_member_id || p.id)); });
    var standing = people.filter(function (p) { return p.consent && !p.consent.withdrawn_at && p.consent.current !== false; });
    var done = standing.filter(function (p) { return p.period && p.period.current; });
    var weekly = people.filter(function (p) { return p.period && p.period.kind === 'week'; });
    var open = (d.talks || []).filter(function (t) { return t.status === 'open'; });
    box.innerHTML = '';
    if (!d.trend) { UI.failLine(box, 'Health check-ins', said({ error: 'db', message: 'PGRST202' }), enterTeam); return; }
    /* The period at a glance (the redesign, 2026-11-22): the average mood of
       the last four weeks, who has checked in, who is asked weekly, the
       talks open. An average is drawn only from 3 check-ins a week. */
    var last4 = (d.trend || []).slice(-4).filter(function (w) { return w.avg != null; });
    var n4 = last4.reduce(function (a, w) { return a + w.n; }, 0);
    var avg4 = n4 ? last4.reduce(function (a, w) { return a + Number(w.avg) * w.n; }, 0) / n4 : null;
    var kp = document.createElement('div');
    kp.className = 'ovw-kpis health-kpis';
    kp.id = 'healthKpis';
    kp.innerHTML = [
      ['Average mood over 4 weeks', avg4 == null ? '—' : avg4.toFixed(1), avg4 == null ? 'Fewer than 3 check-ins per week' : moodWord(Math.round(avg4))],
      ['Check-ins this period', standing.length ? done.length + ' of ' + standing.length : '—',
        standing.length ? (standing.length - done.length ? (standing.length - done.length) + ' due' : 'All checked in') : 'No colleague has agreed'],
      ['Weekly check-ins', String(weekly.length), 'Colleagues near their weekly capacity'],
      ['Open talks', String(open.length), open.length ? 'Asked ' + dateWord(open[open.length - 1].at) : 'None']
    ].map(function (k) {
      return '<article class="chartcard ovw-kpi"><span class="ovw-kpi-label">' + esc(k[0]) + '</span><b class="ovw-kpi-fig">' + esc(k[1]) +
        '</b><span class="ovw-kpi-line"><span class="ovw-kpi-sub">' + esc(k[2]) + '</span></span></article>';
    }).join('');
    box.appendChild(kp);
    var pair = document.createElement('div');
    pair.className = 'health-pair';
    pair.innerHTML = '<div class="ovcard health-card"><div class="ovsec"><div class="ovsec-head refl-head"><span class="health-hd">' +
        '<h3 class="health-h">' + HEART + 'Mood over time</h3><small class="health-meta">Weekly average over 12 weeks, from 1 Very unpleasant to 7 Very pleasant</small></span></div>' +
        '<div id="healthTrend"></div><p class="health-why">A week with fewer than 3 check-ins is not shown.</p></div></div>' +
      '<div class="ovcard health-card"><div class="ovsec"><div class="ovsec-head refl-head"><span class="health-hd">' +
        '<h3 class="health-h">Workload against mood</h3><small class="health-meta">Average mood by planned work against weekly capacity, over 12 weeks</small></span></div>' +
        '<div id="healthBands"></div></div></div>';
    box.appendChild(pair);
    var CH = window.ADspaceChart, shown = (d.trend || []).filter(function (w) { return w.avg != null; });
    var fmt1 = function (v) { return (Math.round(Number(v) * 10) / 10).toFixed(1); };
    if (CH && shown.length) {
      CH.draw($('healthTrend'), { kind: 'line', name: 'Average mood by week', max: 7, none: 'Not shown',
        cats: (d.trend || []).map(function (w) { return { label: shortDay(w.week), long: 'Week of ' + dateWord(w.week), values: [w.avg == null ? null : Number(w.avg)] }; }),
        series: [{ label: 'Average mood' }], fmt: fmt1,
        table: { heads: ['Week', 'Average mood', 'Check-ins'], rows: (d.trend || []).map(function (w) {
          return ['Week of ' + dateWord(w.week), w.avg == null ? '—' : fmt1(w.avg), String(w.n)];
        }) } });
    } else $('healthTrend').innerHTML = '<p class="perf-quiet">No check-ins in 12 weeks.</p>';
    var BANDS = ['Under 50%', '50% to ' + (nearPct(d) - 1) + '%', nearPct(d) + '% or more'];
    if (CH && (d.bands || []).some(function (b) { return b.avg != null; })) {
      CH.draw($('healthBands'), { kind: 'bars', name: 'Average mood by planned work', max: 7, fmt: fmt1,
        rows: (d.bands || []).filter(function (b) { return b.avg != null; }).map(function (b) {
          return { label: BANDS[b.band - 1] + ' · ' + b.n + ' check-ins', value: Number(b.avg),
            tone: b.band === 3 ? 'warn' : '' };
        }) });
    } else $('healthBands').innerHTML = '<p class="perf-quiet">No check-ins in 12 weeks.</p>';
    var G = window.ADspaceGroup;
    box.appendChild(G.section({
      route: 'team-health', key: 'people', name: 'Colleagues', count: people.length, shut: false,
      table: function () {
        var t = G.table('health-prow', ['Colleague', 'Mood', 'This week', 'Checked in', '']);
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
            esc(t.status === 'done' ? 'Talked · ' + dateWord(t.closed_at) : 'Asked ' + dateWord(t.at)) + '</small></span></div>';
        }).join('') + '</div></div>';
      box.appendChild(tc);
    }
  }
  function nearPct(d) {
    var p = (d.people || []).filter(function (x) { return x.period && x.period.load; })[0];
    return p ? Number(p.period.load.near) || 90 : 90;
  }
  function shortDay(v) { return window.ADspaceClock.date(v, { year: false }) || ''; }
  function stateOf(p) {
    if (!p.consent) return 'Not agreed';
    if (p.consent.withdrawn_at) return 'Withdrawn';
    if (p.consent.current === false) return 'Terms changed';
    return '';
  }
  function hoursWord(min) { var h = Math.round(Number(min) / 6) / 10; return (h % 1 ? h.toFixed(1) : String(h)); }
  /* This week's planned work in words: the share of capacity, or why it is not measured. */
  function loadWord(p) {
    var l = p.period && p.period.load;
    if (!l) return '—';
    return l.measured ? l.pct + '%' : 'Not measured';
  }
  function loadLine(l) {
    if (!l) return '';
    if (!l.measured) return 'This week: not measured';
    return 'This week: ' + hoursWord(l.load) + ' of ' + hoursWord(l.cap) + ' hours (' + l.pct + '%)' +
      (l.late_tasks ? ' · ' + l.late_tasks + (l.late_tasks === 1 ? ' task late' : ' tasks late') : '');
  }
  function personRow(p) {
    var s = stateOf(p), per = p.period || {}, c = per.current, last = (p.moods || [])[0];
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'crm-row health-prow' + (s ? ' is-faded' : '');
    b.setAttribute('data-person', p.id);
    var wk = loadWord(p) + (c ? ' · ' + workWord(c.workload) : '');
    b.innerHTML = '<span class="health-who"><b>' + esc(p.name) + '</b>' +
        '<small class="health-code">' + esc([p.staff_code, per.kind === 'week' ? 'Weekly' : 'Monthly'].filter(Boolean).join(' · ')) + '</small>' +
        '<small class="health-line">' + esc([s || (c ? moodWord(c.mood) : 'Due'), wk].join(' · ')) + '</small>' +
      '</span>' +
      '<span class="health-col hp-mood">' + (s ? '<span class="chip">' + esc(s) + '</span>'
        : c ? '<span class="health-word' + (Number(c.mood) <= 2 ? ' is-low' : '') + '">' + esc(moodWord(c.mood)) + '</span>'
        : '<span class="chip-state is-warn">Due</span>') + '</span>' +
      '<span class="health-col hp-week">' + esc(wk) + '</span>' +
      '<span class="health-at">' + esc(s ? '—' : c ? shortDay(c.at) : last ? shortDay(last.at) : '—') + '</span>' +
      '<span class="perf-chev" aria-hidden="true">' + CHEV + '</span>';
    b.addEventListener('click', function () { openPerson(p, b); });
    return b;
  }
  function openPerson(p, opener) {
    st.person = p;
    $('hpTitle').textContent = p.name;
    $('hpBody').innerHTML = personBody(p);
    window.ADspaceSheet.show($('healthPersonSheet'), { opener: opener });
  }
  function personBody(p) {
    var s = stateOf(p), mk = p.moods || [], ck = p.checkins || [];
    var talks = ((st.team && st.team.talks) || []).filter(function (t) { return t.from_id === p.id || t.with_id === p.id; });
    var l = p.period && p.period.load;
    return '<p class="perf-quiet">' + esc(s === 'Not agreed' ? 'Has not agreed to the check-ins.'
        : s === 'Withdrawn' ? 'Withdrew on ' + dateWord(p.consent.withdrawn_at) + '.'
        : s === 'Terms changed' ? 'Has not agreed to the current terms.'
        : 'Agreed on ' + dateWord(p.consent.agreed_at) + '.') + '</p>' +
      (l ? '<p class="perf-quiet">' + esc(loadLine(l)) + '</p>' : '') +
      (mk.length ? mk.map(function (c) {
        return '<section class="fsec"><h4 class="fsec-h">' + esc(dateWord(c.at)) + ' · ' + (c.period === 'week' ? 'Weekly' : 'Monthly') + '</h4>' +
          moodFacts(c, 'ovfacts') + '</section>';
      }).join('') : '') +
      (ck.length ? ck.map(function (c) {
        return '<section class="fsec"><h4 class="fsec-h">' + esc(halfWord(c.half, c.half_end)) + '</h4>' +
          '<dl class="ovfacts health-facts">' + SCALES.map(function (x) {
            var v = c.scales[x[0]];
            return '<div><dt>' + esc(x[1]) + '</dt><dd>' + figure(x[0], v) + ' <span class="health-word">' + esc(word(x[0], v)) + '</span></dd></div>';
          }).join('') + (c.note ? '<div><dt>Note</dt><dd class="health-note">' + esc(c.note) + '</dd></div>' : '') + '</dl></section>';
      }).join('') : '') +
      (!mk.length && !ck.length && !s ? '<p class="perf-quiet">No check-ins.</p>' : '') +
      (talks.length ? '<section class="fsec"><h4 class="fsec-h">Talks</h4><div class="health-talks">' + talks.map(function (t) {
        return '<div class="health-talk' + (t.status === 'open' ? '' : ' is-closed') + '"><span class="health-talk-who"><b>' +
          esc(t.from_id === p.id ? 'Asked ' + t.with : t.from + ' asked them') + '</b><small>' +
          esc(t.status === 'done' ? 'Talked · ' + dateWord(t.closed_at) : 'Asked ' + dateWord(t.at)) + '</small></span></div>';
      }).join('') + '</div></section>' : '');
  }
  /* One colleague's check-ins and talks on their record (js/team.js,
     2026-10-18), from the same read Team: Health makes. */
  function paintPerson(id, host, live) {
    if (!host) return;
    UI.skeleton(host, 2);
    teamRead(host, function (d) {
      if (live && !live()) return;
      if (d.error) { UI.failLine(host, 'Health check-ins', said(d), function () { paintPerson(id, host, live); }); return; }
      st.team = d;
      var p = (d.people || []).filter(function (x) { return (x.team_member_id || x.id) === id; })[0];
      host.innerHTML = p ? '<div class="mrec-health">' + personBody(p) + '</div>' : '<p class="perf-quiet">Has not agreed to the check-ins.</p>';
    }, function () { paintPerson(id, host, live); });
  }
  if ($('healthPersonSheet')) $('hpClose').addEventListener('click', function () { window.ADspaceSheet.close(); });

  window.ADspaceHealth = { enterMine: enterMine, enterTeam: enterTeam, paintPerson: paintPerson };
})();
