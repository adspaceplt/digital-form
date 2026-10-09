/* The client link for Video Scripts (/script/?k=, 2026-10-09).
 *
 * Every script the team has published, a content month at a time (the newest
 * first). A month is a list, a row a script (the user, 2026-10-09: "if i
 * have 30 videos = one whole long page"); a script opens on its own, with
 * Previous and Next and the way back to the list, its facts in one card and
 * its script in the next, as it will be shot. The address keeps the script
 * open (#id), so Back returns to the list and a refresh lands on it. Nobody decides on it here (the
 * user, 2026-10-09: "no need show the approve or changes at client side, the
 * public link … is for us and or client to view how the video script is
 * like digitally; and on the spot digital use for entering VC#"): on the day
 * each scene's clip number (VC#) and Shot tick are recorded here, saved as
 * they change through `script_shot_link` and put back on a refusal. It reads
 * only through `get_scripts`; a client page never shows a database message.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var W = window.ADspaceWords.en;
  var $ = function (id) { return document.getElementById(id); };
  var token = new URLSearchParams(location.search).get('k') || '';
  var feed = null, month = null, open = null, pushed = false;

  var KIND_WORD = { scenes: 'Detailed scenes', products: 'Products and scenes', story: 'Story and voice-over' };
  var CONTEXT_WORD = { products: 'Products and context', story: 'Hook and story' };
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var GUIDE = { name: 'Video Scripts', steps: [
    { at: '#vsStages', text: 'Each content month has its own tab.' },
    { at: '.vs-pick', text: 'Open a script to read it.' },
    { at: '.vs-scene .vs-vc input', text: 'On the day, type each scene\'s clip number (VC#) and tick Shot once it is filmed.' }] };
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
  var BACK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5"/><path d="m11 6-6 6 6 6"/></svg>';

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
  function monthWord(p) {
    var m = /^(\d{4})-(\d{2})$/.exec(p || '');
    return m ? MON[Number(m[2]) - 1] + ' ' + m[1] : '';
  }
  function label(s) { return (s.code || '') + (s.title ? ' · ' + s.title : ''); }

  function cover(title, body) {
    $('vsHead').hidden = true;
    $('vsStages').hidden = true;
    $('vsContent').innerHTML = '';
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
    $('vsMeta').textContent = n + (n === 1 ? ' video script' : ' video scripts');
    $('vsHead').hidden = false;
  }

  /* The months the scripts belong to, newest first; a tab each, drawn only
     where there are two. */
  function months() {
    var out = [];
    feed.scripts.forEach(function (s) { if (out.indexOf(s.period) < 0) out.push(s.period); });
    return out.sort().reverse();
  }
  function paintMonths() {
    var list = months(), strip = $('vsStages');
    if (!month || list.indexOf(month) < 0) month = list[0];
    strip.hidden = list.length < 2;
    strip.innerHTML = list.map(function (p) {
      var on = p === month;
      var n = feed.scripts.filter(function (s) { return s.period === p; }).length;
      return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" data-month="' + esc(p) + '" aria-selected="' + on +
        '" tabindex="' + (on ? 0 : -1) + '">' + esc(monthWord(p)) + ' <span class="tab-n">' + n + '</span></button>';
    }).join('');
  }
  function pickMonth(to) {
    month = to;
    if (open) { open = null; pushed = false; history.replaceState(null, '', location.pathname + location.search); }
    Array.prototype.forEach.call(document.querySelectorAll('#vsStages .tab'), function (b) {
      var on = b.getAttribute('data-month') === to;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    paintList();
  }
  $('vsStages').addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('.tab');
    if (b) pickMonth(b.getAttribute('data-month'));
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
    pickMonth(tabs[to].getAttribute('data-month'));
  });

  function inMonth() { return feed.scripts.filter(function (s) { return s.period === month; }); }
  /* Where the crew stands on a script: scenes shot of the scenes, the
     voice-over counted as one. */
  function shotWord(s) {
    var n = s.scenes.length + (s.kind === 'story' ? 1 : 0);
    var done = s.scenes.filter(function (x) { return x.shot; }).length + (s.kind === 'story' && s.vo_shot ? 1 : 0);
    return n ? done + ' of ' + n + ' shot' : '';
  }
  /* The month: its scripts as a list; one opens on its own. A month of one
     script opens it straight away. */
  function paintList() {
    var box = $('vsContent');
    var list = inMonth();
    box.innerHTML = '';
    var cur = open && list.filter(function (s) { return s.id === open; })[0];
    if (list.length === 1) cur = list[0];
    if (cur) box.appendChild(openView(cur, list));
    else box.appendChild(index(list));
    if (window.ADspaceState && window.ADspaceState.fit) window.ADspaceState.fit();
    if (window.ADspaceGuide) window.ADspaceGuide.offer('script', GUIDE);
  }
  function index(list) {
    var el = document.createElement('section');
    el.className = 'panel vs-index';
    el.innerHTML = list.map(function (s) {
      var sub = [KIND_WORD[s.kind], [day(s.shoot_on), time(s.shoot_time)].filter(Boolean).join(', ')].filter(Boolean).join(' · ');
      var shot = shotWord(s);
      return '<button class="vs-pick" type="button" data-id="' + esc(s.id) + '">' +
        '<span class="vs-pick-name"><b>' + esc(label(s)) + '</b><small>' + esc(sub) + '</small></span>' +
        '<span class="vs-pick-state">' + esc(shot) + '</span>' + CHEV + '</button>';
    }).join('');
    Array.prototype.forEach.call(el.querySelectorAll('.vs-pick'), function (b) {
      b.addEventListener('click', function () { show(b.getAttribute('data-id'), true); });
    });
    return el;
  }
  /* One script on its own: the way back to the list, where it stands in the
     month, Previous and Next (a sideways swipe on a phone), then the script. */
  function openView(s, list) {
    var wrap = document.createElement('div');
    wrap.className = 'vs-open';
    var i = list.indexOf(s);
    if (list.length > 1) {
      wrap.setAttribute('data-swipe-prev', 'vsPrev');
      wrap.setAttribute('data-swipe-next', 'vsNext');
      var bar = document.createElement('div');
      bar.className = 'vs-openbar';
      bar.innerHTML = '<button class="backlink vs-back" type="button" id="vsAll">' + BACK + 'All scripts</button>' +
        '<span class="vs-steps"><span class="vs-pos">' + (i + 1) + ' of ' + list.length + '</span>' +
        '<button class="btn btn-sm" type="button" id="vsPrev"' + (i > 0 ? '' : ' disabled') + '>Previous</button>' +
        '<button class="btn btn-sm" type="button" id="vsNext"' + (i < list.length - 1 ? '' : ' disabled') + '>Next</button></span>';
      wrap.appendChild(bar);
      bar.querySelector('#vsAll').addEventListener('click', function () {
        if (pushed) { history.back(); return; }
        open = null;
        history.replaceState(null, '', location.pathname + location.search);
        paintList();
      });
      bar.querySelector('#vsPrev').addEventListener('click', function () { if (i > 0) show(list[i - 1].id, false); });
      bar.querySelector('#vsNext').addEventListener('click', function () { if (i < list.length - 1) show(list[i + 1].id, false); });
    }
    wrap.appendChild(video(s));
    return wrap;
  }
  /* Open a script: from the list it is a step Back can undo; Previous and
     Next replace it. Each opens at its top. */
  function show(id, fromList) {
    open = id;
    if (fromList) { history.pushState({ vs: id }, '', '#' + id); pushed = true; }
    else history.replaceState({ vs: id }, '', '#' + id);
    paintList();
    var top = $('vsContent').getBoundingClientRect().top + window.pageYOffset - 80;
    if (window.pageYOffset > top) window.scrollTo(0, Math.max(0, top));
  }
  window.addEventListener('popstate', function () {
    if (!feed) return;
    var id = location.hash.replace(/^#/, '');
    var s = id && feed.scripts.filter(function (x) { return x.id === id; })[0];
    open = s ? s.id : null;
    if (!s) pushed = false;
    if (s && s.period !== month) { month = s.period; paintMonths(); }
    paintList();
  });

  function factsOf(s) {
    var f = [['Platform', s.platform], ['Language', s.language],
             ['Shooting date', [day(s.shoot_on), time(s.shoot_time)].filter(Boolean).join(', ')],
             ['Venue', s.venue], ['Estimated duration', dur(s.duration_minutes)], ['Cast', s.cast_names]];
    var ref = s.reference_url
      ? '<div class="vs-ref"><dt>Reference video</dt><dd><a class="plink" href="' + esc(s.reference_url) +
        '" target="_blank" rel="noopener">' + esc(s.reference_url.replace(/^https:\/\//, '')) + '</a></dd></div>'
      : '';
    return '<dl class="facts vs-facts">' + f.map(function (x) {
      return '<div><dt>' + esc(x[0]) + '</dt><dd>' + (x[1] ? esc(x[1]) : '<span class="mute">Not set</span>') + '</dd></div>';
    }).join('') + ref + '</dl>';
  }
  function vcCell(id, vc, n) {
    return '<span class="vs-vc"><input class="input input-sm" type="text" maxlength="40" value="' + esc(vc || '') +
      '" aria-label="Clip number for ' + esc(n) + '" placeholder="VC#" data-vc="' + esc(id) + '"></span>';
  }
  function shotCell(id, on, n) {
    return '<span class="vs-shot"><input type="checkbox"' + (on ? ' checked' : '') + ' aria-label="' + esc(n) + ' shot" data-shot="' + esc(id) + '"></span>';
  }
  function scenesOf(s) {
    var two = s.kind === 'scenes';
    var head = '<div class="crm-head vs-scene"><span>#</span><span>' + (two ? 'Visual' : 'Scene') + '</span>' +
      (two ? '<span>Script</span>' : '') + '<span>VC#</span><span>Shot</span></div>';
    return '<section class="vs-block"><h4 class="fsec-h">Scenes</h4>' +
      '<div class="crm-table vs-scenes' + (two ? ' is-two' : '') + '">' + head +
      (s.scenes.length ? s.scenes.map(function (sc, i) {
        var n = 'scene ' + (i + 1);
        return '<div class="vs-scene"><span class="vs-n">' + (i + 1) + '</span><span class="vs-text vs-vis">' + esc(sc.visual || '') + '</span>' +
          (two ? '<span class="vs-text vs-line">' + esc(sc.line || '') + '</span>' : '') +
          vcCell(sc.id, sc.vc, n) + shotCell(sc.id, sc.shot, 'Scene ' + (i + 1)) + '</div>';
      }).join('') : '<p class="vs-empty">No scenes.</p>') + '</div></section>';
  }

  /* One video: its head, its facts card, its script card. */
  function video(s) {
    var el = document.createElement('section');
    el.className = 'vs-video';
    el.setAttribute('data-id', s.id);
    var html = '<header class="vs-video-head"><h3>' + esc(label(s)) + '</h3><p>' + esc(KIND_WORD[s.kind] || '') + '</p></header>' +
      '<div class="panel vs-card">' + factsOf(s) + '</div>';
    var body = '';
    if (CONTEXT_WORD[s.kind]) {
      body += '<section class="vs-block"><h4 class="fsec-h">' + esc(CONTEXT_WORD[s.kind]) + '</h4><p class="vs-prose">' +
        (s.context ? esc(s.context) : '<span class="mute">Not written</span>') + '</p></section>';
    }
    body += scenesOf(s);
    if (s.kind === 'story') {
      body += '<section class="vs-block"><h4 class="fsec-h">Script (read here)</h4><p class="vs-prose">' +
        (s.vo ? esc(s.vo) : '<span class="mute">Not written</span>') + '</p>' +
        '<div class="vs-vo"><span class="field-label">VC#</span>' + vcCell('vo', s.vo_vc, 'the voice-over') +
        '<label class="tickline"><input type="checkbox"' + (s.vo_shot ? ' checked' : '') + ' data-shot="vo"> <span>Shot</span></label></div></section>';
    }
    if (s.remarks) body += '<section class="vs-block"><h4 class="fsec-h">Notes</h4><p class="vs-prose">' + esc(s.remarks) + '</p></section>';
    html += '<div class="panel vs-card">' + body + '<p class="msg vs-shot-msg" role="status"></p></div>';
    el.innerHTML = html;
    wire(s, el);
    return el;
  }

  /* On the day: a clip number or a tick, saved as it changes, put back on a
     refusal with one line in the reader's words. */
  function wire(s, el) {
    var msg = el.querySelector('.vs-shot-msg');
    var say = function (t, bad) { msg.textContent = t || ''; msg.className = 'msg vs-shot-msg' + (t ? (bad ? ' err' : ' ok') : ''); };
    var scene = function (key) { return key === 'vo' ? null : s.scenes.filter(function (x) { return x.id === key; })[0]; };
    var save = function (key, on, vc, input) {
      say('');
      API.client.rpc('script_shot_link', { p_token: token, p_script: s.id, p_scene: key === 'vo' ? null : key, p_on: on, p_vc: vc })
        .then(function (r) {
          if (r.error || (r.data && r.data.error)) throw new Error('refused');
          var sc = scene(key);
          if (sc) { if (on != null) sc.shot = on; if (vc != null) sc.vc = vc.trim() || null; }
          else { if (on != null) s.vo_shot = on; if (vc != null) s.vo_vc = vc.trim() || null; }
          say('Saved.');
        })
        .catch(function () {
          var sc = scene(key);
          if (input.type === 'checkbox') input.checked = !input.checked;
          else input.value = (sc ? sc.vc : s.vo_vc) || '';
          say(W.notSent, true);
        });
    };
    Array.prototype.forEach.call(el.querySelectorAll('[data-vc]'), function (i) {
      i.addEventListener('change', function () { save(i.getAttribute('data-vc'), null, i.value, i); });
    });
    Array.prototype.forEach.call(el.querySelectorAll('[data-shot]'), function (i) {
      i.addEventListener('change', function () { save(i.getAttribute('data-shot'), i.checked, null, i); });
    });
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
      if (!feed.scripts.length) { cover('No video scripts', 'Video scripts appear here once they are published.'); return; }
      $('cover').hidden = true;
      var id = location.hash.replace(/^#/, '');
      var at = id && feed.scripts.filter(function (x) { return x.id === id; })[0];
      if (at) { month = at.period; open = at.id; }
      paintHead();
      paintMonths();
      paintList();
    }).catch(function () { cover(W.failTitle, W.failText); });
  }

  load();
})();
