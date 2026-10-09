/* The client's Video Scripts page (/script/?k=, 2026-10-09).
 *
 * Every video the team has shared, by shoot, newest first: its facts, its
 * script as it will be shot (never the crew's clip numbers or ticks), and
 * the decision on it: Approve, or Request changes with a note, under the
 * name the reader types once (js/decide.js). A video changed after a
 * decision comes back to be decided again, heading the request it answers.
 * It reads only through `get_scripts` and writes only through
 * `script_decide`; a client page never shows a database message.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var W = window.ADspaceWords.en;
  var $ = function (id) { return document.getElementById(id); };
  var token = new URLSearchParams(location.search).get('k') || '';
  var feed = null, stage = null;

  var KIND_WORD = { scenes: 'Detailed scenes', products: 'Products and scenes', story: 'Story and voice-over' };
  var CONTEXT_WORD = { products: 'Products and context', story: 'Hook and story' };
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var STAGES = [['pending', 'To review'], ['changes', 'Changes requested'], ['approved', 'Approved'], ['all', 'All']];
  var GUIDE = { name: 'Video Scripts', steps: [
    { at: '#vsStages', text: 'Videos waiting for your decision are under To review.' },
    { at: '.vs-card .approve-row', text: 'Approve a script, or request changes with a note for the team.' }] };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function day(iso) {
    if (!iso) return '';
    var d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(iso + 'T00:00:00') : new Date(iso);
    return isNaN(d) ? '' : d.getDate() + ' ' + MON[d.getMonth()] + ' ' + d.getFullYear();
  }
  function time(t) {
    var m = /^(\d{1,2}):(\d{2})/.exec(t || '');
    if (!m) return '';
    var h = Number(m[1]);
    return ((h % 12) || 12) + ':' + m[2] + ' ' + (h >= 12 ? 'pm' : 'am');
  }
  function dur(n) {
    n = Number(n) || 0;
    if (!n) return '';
    var h = Math.floor(n / 60), m = n % 60;
    return (h ? h + (h === 1 ? ' hour' : ' hours') : '') + (h && m ? ' ' : '') + (m ? m + ' min' : '');
  }
  function label(s) { return 'V' + s.video_no + (s.title ? ' · ' + s.title : ''); }
  function stageOf(s) { return s.decision ? s.decision.decision : 'pending'; }

  function cover(title, body) {
    $('vsHead').hidden = true;
    $('vsStages').hidden = true;
    $('vsContent').innerHTML = '';
    $('vsEmpty').hidden = true;
    $('cover').hidden = false;
    document.body.classList.add('is-plain');
    $('coverTitle').textContent = title;
    $('coverBody').textContent = body;
    var f = document.querySelector('.brand-for');
    if (f) f.hidden = true;
  }

  function paintHead() {
    var c = feed.client || {};
    var mark = $('vsMark');
    if (c.logo_url) {
      mark.className = 'rec-mark has-logo';
      mark.innerHTML = '<img src="' + esc(c.logo_url) + '" alt="">';
      mark.querySelector('img').addEventListener('error', function () {
        mark.className = 'rec-mark'; mark.textContent = window.ADspaceState ? window.ADspaceState.initials(c.name) : '';
      });
    } else {
      mark.className = 'rec-mark';
      mark.textContent = window.ADspaceState ? window.ADspaceState.initials(c.name) : '';
    }
    $('vsName').textContent = c.name || '';
    var n = feed.scripts.length;
    var pending = feed.scripts.filter(function (s) { return stageOf(s) === 'pending'; }).length;
    $('vsMeta').textContent = n + (n === 1 ? ' video' : ' videos');
    $('vsState').hidden = !pending;
    $('vsState').textContent = pending + ' to review';
    $('vsHead').hidden = false;
    if (!$('vsHead').querySelector('.decide-as') && window.ADspaceDecide.whoLine) {
      window.ADspaceDecide.whoLine($('vsHead'), { as: W.decideAs, change: W.decideChange, forget: W.decideForget,
        save: W.decideSave, cancel: W.decideCancel, name: W.decideName }, $('vsHead').querySelector('.rec-id'));
    }
  }

  /* The strip counts each stage as the page loaded, as the review page does:
     a decision repaints its card and moves it on the next load. */
  var TONE = { pending: 'is-warn', changes: 'is-err', approved: 'is-ok' };
  function paintStages() {
    var strip = $('vsStages');
    var count = { pending: 0, changes: 0, approved: 0 };
    feed.scripts.forEach(function (s) { count[stageOf(s)]++; });
    count.all = feed.scripts.length;
    if (!stage) stage = count.pending ? 'pending' : 'all';
    /* The review page's strip: on a phone the longest stage reads Changes,
       so all four share the column's width. */
    strip.innerHTML = STAGES.map(function (t) {
      var on = t[0] === stage;
      var word = t[0] === 'changes' ? '<span class="tab-long">' + t[1] + '</span><span class="tab-short">Changes</span>' : t[1];
      return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" data-stage="' + t[0] + '" aria-selected="' + on +
        '" tabindex="' + (on ? 0 : -1) + '">' + word + ' <span class="tab-n' + (count[t[0]] && TONE[t[0]] ? ' ' + TONE[t[0]] : '') + '">' +
        count[t[0]] + '</span></button>';
    }).join('');
    strip.hidden = false;
  }
  function pickStage(to) {
    stage = to;
    Array.prototype.forEach.call(document.querySelectorAll('#vsStages .tab'), function (b) {
      var on = b.getAttribute('data-stage') === to;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    paintList();
  }
  $('vsStages').addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('.tab');
    if (b) pickStage(b.getAttribute('data-stage'));
  });
  /* A tab list: the arrows move along it, Home and End to its ends. */
  $('vsStages').addEventListener('keydown', function (e) {
    var tabs = Array.prototype.slice.call(this.querySelectorAll('.tab'));
    var i = tabs.indexOf(document.activeElement);
    if (i < 0) return;
    var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
    if (to === null) return;
    e.preventDefault();
    to = (to + tabs.length) % tabs.length;
    tabs[to].focus();
    pickStage(tabs[to].getAttribute('data-stage'));
  });

  function paintList() {
    var box = $('vsContent');
    box.innerHTML = '';
    var list = feed.scripts.filter(function (s) { return stage === 'all' || stageOf(s) === stage; });
    $('vsEmpty').hidden = list.length > 0;
    var shoots = [], by = {};
    list.forEach(function (s) {
      if (!by[s.series_id]) { by[s.series_id] = []; shoots.push(s.series_id); }
      by[s.series_id].push(s);
    });
    shoots.forEach(function (sid) {
      var vids = by[sid], first = vids[0];
      var sec = document.createElement('section');
      sec.className = 'vs-shoot';
      var when = [day(first.shoot_on), time(first.shoot_time)].filter(Boolean).join(', ');
      sec.innerHTML = '<h3 class="vs-shoot-head">' + esc(['Shoot', when, first.venue].filter(Boolean).join(' · ')) + '</h3>';
      vids.forEach(function (s) { sec.appendChild(card(s)); });
      box.appendChild(sec);
    });
    if (window.ADspaceGuide && list.length) window.ADspaceGuide.offer('script', GUIDE);
  }

  function factsOf(s) {
    var f = [['Platform', s.platform], ['Language', s.language],
             ['Shooting date', [day(s.shoot_on), time(s.shoot_time)].filter(Boolean).join(', ')],
             ['Venue', s.venue], ['Estimated duration', dur(s.duration_minutes)], ['Cast', s.cast_names]]
      .filter(function (x) { return x[1]; });
    if (!f.length) return '';
    return '<dl class="facts vs-facts">' + f.map(function (x) {
      return '<div><dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd></div>';
    }).join('') + '</dl>';
  }
  function scenesOf(s) {
    var two = s.kind === 'scenes';
    if (!s.scenes.length) return '';
    return '<section class="vs-block"><h4 class="fsec-h">Scenes</h4>' +
      '<div class="crm-table vs-scenes is-client' + (two ? ' is-two' : '') + '">' +
      '<div class="crm-head vs-scene"><span>#</span><span>' + (two ? 'Visual' : 'Scene') + '</span>' + (two ? '<span>Script</span>' : '') + '</div>' +
      s.scenes.map(function (sc, i) {
        return '<div class="vs-scene"><span class="vs-n">' + (i + 1) + '</span><span class="vs-text vs-vis">' + esc(sc.visual || '') + '</span>' +
          (two ? '<span class="vs-text vs-line">' + esc(sc.line || '') + '</span>' : '') + '</div>';
      }).join('') + '</div></section>';
  }
  function chipOf(k) {
    var w = { pending: ['To review', 'is-warn'], changes: ['Changes requested', 'is-warn'], approved: ['Approved', 'is-ok'] }[k];
    return '<span class="chip-state ' + w[1] + '">' + esc(w[0]) + '</span>';
  }

  function card(s) {
    var el = document.createElement('article');
    el.className = 'panel vs-card';
    el.setAttribute('data-id', s.id);
    var html =
      '<header class="vs-card-head"><div><h3>' + esc(label(s)) + '</h3><p class="vs-card-kind">' + esc(KIND_WORD[s.kind] || '') + '</p></div>' +
        '<span class="vs-card-state">' + chipOf(stageOf(s)) + '</span></header>';
    if (s.asked && !s.decision) {
      html += '<div class="vs-said"><p class="reask-head">Changes requested by ' + esc(s.asked.reviewer) + ' · ' + esc(day(s.asked.at)) + '</p>' +
        '<p class="vs-note">' + esc(s.asked.note || '') + '</p></div>';
    }
    html += factsOf(s);
    if (s.reference_url) {
      html += '<p class="vs-ref"><span class="field-label">Reference</span> <a class="plink" href="' + esc(s.reference_url) +
        '" target="_blank" rel="noopener">' + esc(s.reference_url.replace(/^https:\/\//, '')) + '</a></p>';
    }
    if (CONTEXT_WORD[s.kind] && s.context) {
      html += '<section class="vs-block"><h4 class="fsec-h">' + esc(CONTEXT_WORD[s.kind]) + '</h4><p class="vs-prose">' + esc(s.context) + '</p></section>';
    }
    html += scenesOf(s);
    if (s.kind === 'story' && s.vo) {
      html += '<section class="vs-block"><h4 class="fsec-h">Script (read here)</h4><p class="vs-prose">' + esc(s.vo) + '</p></section>';
    }
    if (s.remarks) html += '<section class="vs-block"><h4 class="fsec-h">Notes</h4><p class="vs-prose">' + esc(s.remarks) + '</p></section>';
    el.innerHTML = html;
    el.appendChild(decision(s, el));
    return el;
  }

  /* The decision: Approve, or Request changes with a note; the name asked in
     place, once (js/decide.js). Approved reads its line; Changes requested
     reads the note and may still be approved as it is. */
  function decision(s, cardEl) {
    var wrap = document.createElement('div');
    wrap.className = 'approve vs-decide';
    var d = s.decision;
    var line = '';
    if (d) {
      line = '<p class="vs-decided">' + (d.decision === 'approved' ? 'Approved' : 'Changes requested') + ' by ' +
        esc(d.reviewer) + ' · ' + esc(day(d.at)) + '</p>' + (d.note ? '<p class="vs-note">' + esc(d.note) + '</p>' : '');
    }
    var approved = d && d.decision === 'approved';
    wrap.innerHTML = line + (approved ? '' :
      '<div class="approve-row">' +
        '<button class="btn btn-approve" type="button">' + (d ? 'Approve as it is' : 'Approve') + '</button>' +
        (d ? '' : '<button class="btn btn-changes" type="button">Request changes</button>') +
      '</div>' +
      '<div class="changebox">' +
        '<textarea class="textarea" data-f="note" aria-label="Changes required" placeholder="Describe the changes required."></textarea>' +
        '<input class="input changebox-who" type="text" autocomplete="name" aria-label="Your name" placeholder="John Doe">' +
        '<div class="changebox-actions">' +
          '<button class="btn btn-primary" type="button" data-act="send">Send request</button>' +
          '<button class="btn" type="button" data-act="cancel">Cancel</button>' +
        '</div>' +
      '</div>') +
      '<p class="msg vs-decide-msg"></p>';
    if (approved) return wrap;
    var msg = wrap.querySelector('.vs-decide-msg');
    var say = function (t, bad) { msg.textContent = t || ''; msg.className = 'msg vs-decide-msg' + (t ? (bad ? ' err' : ' ok') : ''); };
    var approveBtn = wrap.querySelector('.btn-approve');
    var asker = window.ADspaceDecide.nameBox(approveBtn, {
      label: 'Your name', placeholder: 'John Doe', needed: 'A name is required to record this decision.'
    }, function (t) { say(t, true); });
    var send = function (decision, name, note, btns) {
      btns.forEach(function (b) { b.disabled = true; });
      API.client.rpc('script_decide', { p_token: token, p_script: s.id, p_decision: decision, p_name: name, p_note: note || null })
        .then(function (r) {
          if (r.error || (r.data && r.data.error)) throw new Error('refused');
          s.decision = { decision: decision, note: note || null, reviewer: name, at: new Date().toISOString() };
          var fresh = card(s);
          cardEl.parentNode.replaceChild(fresh, cardEl);
          var m = fresh.querySelector('.vs-decide-msg');
          if (m) { m.textContent = decision === 'approved' ? 'Approved.' : 'Request sent.'; m.className = 'msg vs-decide-msg ok'; }
          paintHead();
        })
        .catch(function () {
          btns.forEach(function (b) { b.disabled = false; });
          say(W.notSent, true);
        });
    };
    approveBtn.addEventListener('click', function () {
      asker.need(function (name) { send('approved', name, null, [approveBtn]); });
    });
    var reqBtn = wrap.querySelector('.btn-changes');
    var box = wrap.querySelector('.changebox');
    var note = box.querySelector('textarea'), who = box.querySelector('.changebox-who');
    if (reqBtn) reqBtn.addEventListener('click', function () {
      asker.close();
      box.classList.add('is-open');
      wrap.classList.add('is-requesting');
      who.hidden = Boolean(window.ADspaceDecide.known());
      note.focus();
    });
    box.querySelector('[data-act="cancel"]').addEventListener('click', function () {
      box.classList.remove('is-open');
      wrap.classList.remove('is-requesting');
      say('');
    });
    box.querySelector('[data-act="send"]').addEventListener('click', function () {
      var text = note.value.trim();
      var name = window.ADspaceDecide.known() || who.value.trim();
      if (!text) { say('Describe the changes required.', true); note.focus(); return; }
      if (!name) { say('A name is required to record this decision.', true); who.hidden = false; who.focus(); return; }
      if (!window.ADspaceDecide.known()) window.ADspaceDecide.keep(name);
      send('changes', name, text, [box.querySelector('[data-act="send"]')]);
    });
    return wrap;
  }

  function load() {
    if (!token || !API || !API.configured) { cover(W.notFound, W.notFoundText); return; }
    API.client.rpc('get_scripts', { p_token: token }).then(function (r) {
      if (r.error) throw r.error;
      var data = r.data || {};
      if (data.error) { cover(W.notFound, W.notFoundText); return; }
      feed = data;
      feed.scripts = feed.scripts || [];
      document.title = (feed.client && feed.client.name ? feed.client.name + ' ' : '') + 'Video Scripts by ADspace';
      if ($('clientName') && feed.client) $('clientName').textContent = feed.client.name;
      if (!feed.scripts.length) { cover('No scripts to review', 'The next video script will appear here when it is ready for review.'); return; }
      $('cover').hidden = true;
      paintHead();
      paintStages();
      paintList();
    }).catch(function () { cover(W.failTitle, W.failText); });
  }

  load();
})();
