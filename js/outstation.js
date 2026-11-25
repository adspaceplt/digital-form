/*
 * Outstation — a driver's trip out of the office, in My Work (OUTSTATION
 * RECORD, 2026-11-23; the user approved the mockup's screens 1, 2 and 5).
 * It replaces the Lark form "Outstation Record Form".
 *
 *   * My trips: the trip in progress (its route, office to each stop and
 *     back, the road distance so far, Next stop, Add photo, Check out, and
 *     Add claim not drawn until claims are built, release 2), then the
 *     trips the colleague drove or joined these three months.
 *   * All trips (`ops.outstation`, an admin's): every trip of a month, read
 *     only, and Download (a CSV of every stop).
 *   * Check in, Next stop and Check out read the phone's own location
 *     (`enableHighAccuracy`, never cached, watched up to 20 seconds, the
 *     best reading kept) and refuse one worse than the limit in Settings
 *     (50 m) with the way to turn precise location on. Never an address
 *     typed, never an IP lookup.
 *   * Photos come from the camera alone (`capture=environment`), drawn down
 *     to a 1600px JPEG (which also leaves the picture's own metadata
 *     behind), each kept with its time and the location at capture,
 *     private under the trip's folder (sign-upload `outstation`).
 *   * The address, the zone and the road km are the `outstation-geo`
 *     function's (OpenStreetMap, credited under the route; openrouteservice).
 *
 * Every read and write is a database function (`outstation_*`); no table is
 * readable directly.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;

  var $ = function (id) { return document.getElementById(id); };
  var bridge = window.ADspaceAdmin || {};
  var C = window.ADspaceClock;
  function may(key, level) { return Boolean(bridge.may && bridge.may(key, level)); }
  function me() { return bridge.me ? bridge.me() : null; }
  function esc(s) { return window.ADspaceWords.esc(s); }
  var UI = window.ADspaceState;
  var W = window.ADspaceWords.en;
  var F = window.ADspaceForm;
  var X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var CAMERA = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/></svg>';
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  /* The trip card's glyphs (2026-11-25): each purpose its own, the route's
     pin, the office, and the small facts under a stop. */
  var G_ = function (d) { return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>'; };
  var GLYPH = {
    meeting: G_('<circle cx="9" cy="8.5" r="3"/><path d="M3.5 19c.6-3 2.8-4.8 5.5-4.8s4.9 1.8 5.5 4.8"/><circle cx="16.5" cy="9.5" r="2.4"/><path d="M15.8 14.3c2.2.2 3.9 1.8 4.5 4.7"/>'),
    shooting: G_('<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>'),
    event: G_('<rect x="4" y="5.5" width="16" height="14" rx="2"/><path d="M8 3.5v4M16 3.5v4M4 10h16"/>'),
    other: G_('<circle cx="12" cy="12" r="8.5"/><path d="M8.5 12h.01M12 12h.01M15.5 12h.01"/>'),
    pin: G_('<path d="M12 21s-6.5-5.6-6.5-10.5a6.5 6.5 0 0 1 13 0C18.5 15.4 12 21 12 21z"/><circle cx="12" cy="10.5" r="2.3"/>'),
    road: G_('<circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M8 18h6.5a3.5 3.5 0 0 0 0-7h-5a3.5 3.5 0 0 1 0-7H16"/>'),
    office: G_('<path d="M5 20V6.5L12 4l7 2.5V20"/><path d="M3.5 20h17M9.5 9.5h.5M14 9.5h.5M9.5 13h.5M14 13h.5M11 20v-3h2v3"/>'),
    clock: G_('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
    target: G_('<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.5"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3"/>'),
    camera: G_('<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>'),
    pen: G_('<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/>')
  };
  /* Recording acts wait for a phone (2026-11-25, the user: a desk computer
     never travels): drawn disabled with the reason at a desk, through the
     one painter (`data-gate="phone"`, js/admin.js). */
  var GATE = ' data-gate="phone"';
  var STAR = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>';

  var PURPOSE = { meeting: 'Meeting', shooting: 'Shooting', event: 'Event', other: 'Other' };
  var ZONE = { johor: 'Johor', singapore: 'Singapore', beyond: 'Beyond Johor' };
  var WATCH_MS = 20000;
  var BREAK_MS = 4 * 3600000;
  var PRECISE = 'On an iPhone, turn on Precise Location (Settings, Privacy & Security, Location Services, Safari Websites). ' +
    'On Android, turn on Google Location Accuracy (Settings, Location).';
  var SAID = {
    denied: 'You do not have permission to record a trip. Please ask an admin.',
    'open-trip': 'A trip is already in progress. Check out of it first.',
    'no-trip': 'This trip no longer exists.',
    closed: 'This trip has been checked out. Refresh the page.',
    'bad-purpose': 'Choose the purpose.',
    'no-place': 'Choose the client, or choose No client and enter the venue.',
    'bad-client': 'You do not have access to this client. Please ask an admin.',
    'bad-companion': 'One of the colleagues chosen cannot join this trip. Untick them and try again.',
    'bad-location': 'The location could not be read. Press Locate again.',
    'no-photo': 'Take a photo at this stop first.',
    'too-many': 'This trip has reached the maximum number of stops or photos. Check out and start a new trip.',
    'bad-key': 'The photo could not be saved. Take it again.',
    'too-long': 'Enter a note of up to 2,000 characters.',
    'bad-rating': 'Choose a rating from 1 to 5.',
    'bad-period': 'Choose another month.'
  };
  function said(d) {
    if (!d) return W.notSaved;
    if (d.error === 'vague') return 'Your location is accurate to ' + d.accuracy + ' m; it must be within ' + d.limit + ' m. ' + PRECISE;
    return SAID[d.error] || W.notSaved;
  }
  function setting(key, dflt) {
    var M = window.ADspaceMoney;
    var v = M && M.setting ? Number(M.setting(key)) : NaN;
    return isFinite(v) && v > 0 ? v : dflt;
  }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
  function km(v) { return (Math.round(Number(v) * 10) / 10).toFixed(1) + ' km'; }
  function span(a, b) {
    var ms = (b ? Date.parse(b) : Date.now()) - Date.parse(a);
    if (!(ms >= 0)) return '';
    var m = Math.round(ms / 60000), h = Math.floor(m / 60);
    return h ? h + 'h ' + (m % 60) + 'm' : m + 'm';
  }
  /* A stop's client and, where the work was away from its site, the venue
     (2026-11-24). */
  function placeName(s) { return s.client ? s.client + (s.venue ? ' · ' + s.venue : '') : (s.venue || 'Deleted client'); }

  /* ---- State and the address ------------------------------------------- */
  var st = { mode: 'mine', month: C.today().slice(0, 7), d: null, err: null, host: null, seq: 0, msg: null, pending: [], office: null };
  (function fromUrl() {
    var q = new URLSearchParams(location.search);
    if (q.get('ov') === 'all') st.mode = 'all';
    if (/^\d{4}-\d{2}$/.test(q.get('om') || '')) st.month = q.get('om');
  })();
  function urlPart() {
    var q = {};
    if (st.mode === 'all') {
      q.ov = 'all';
      if (st.month !== C.today().slice(0, 7)) q.om = st.month;
    }
    return q;
  }
  function setUrl() { if (bridge.setUrl) bridge.setUrl(); }

  /* ---- Reading ---------------------------------------------------------- */
  function period() {
    if (st.mode === 'all') {
      var next = C.addMonths(st.month + '-01', 1);
      return { from: st.month + '-01', to: C.addDays(next + '-01', -1) };
    }
    return { from: C.addMonths(C.today(), -2) + '-01', to: C.today() };
  }
  function load() {
    var mine = ++st.seq, p = period();
    st.d = null; st.err = null;
    paint();
    return db.rpc('outstation_trips', { p_from: p.from, p_to: p.to, p_all: st.mode === 'all' }).then(function (r) {
      if (mine !== st.seq) return;
      if (r.error || !r.data || r.data.error) { st.err = (r.data && SAID[r.data.error]) || (r.error && r.error.message) || 'The trips could not be loaded.'; }
      else { st.d = r.data; heal(st.d.trips || []); }
      paint();
    }).catch(function (e) {
      if (mine !== st.seq) return;
      st.err = (e && e.message) || 'The trips could not be loaded.'; paint();
    });
  }
  /* A trip whose place or distance was never filled (the lookup failed, or
     the trip came before it worked: OS/20261101, 2026-11-24) is asked again
     when its driver opens the list, once a visit: each stop missing its
     address, then the trip's legs. Only the driver may ask
     (`outstation_geo_may`), so a colleague who joined asks nothing. */
  var healed = {};
  function heal(trips) {
    var m = me();
    if (!m) return;
    var asks = [];
    trips.forEach(function (t) {
      if (t.driver_id !== m.id || healed[t.id]) return;
      var stops = t.stops || [];
      var noPlace = stops.filter(function (s) { return !s.address; });
      var noKm = stops.some(function (s) { return s.km_from_prev == null; }) || (t.state === 'closed' && t.km_back == null);
      if (!noPlace.length && !noKm) return;
      healed[t.id] = true;
      noPlace.forEach(function (s) { asks.push({ stop: s.id }); });
      if (noKm) asks.push({ trip: t.id });
    });
    if (!asks.length) return;
    asks.reduce(function (p, b) { return p.then(function () { return geo(b); }); }, Promise.resolve()).then(reread);
  }
  function openTrip() {
    var m = me();
    return st.mode === 'mine' && st.d && m ? (st.d.trips || []).filter(function (t) { return t.state === 'open' && t.driver_id === m.id; })[0] : null;
  }
  /* A write answers the trip as it now stands: put in the list in place. */
  function keep(trip) {
    if (!st.d || !trip) return;
    var list = st.d.trips || (st.d.trips = []);
    var at = list.map(function (t) { return t.id; }).indexOf(trip.id);
    if (at < 0) list.unshift(trip); else list[at] = trip;
  }

  /* ---- Drawing ---------------------------------------------------------- */
  function draw(host) {
    st.host = host;
    if (!host.querySelector('#ostBody')) {
      host.innerHTML = '';
      if (may('ops.outstation', 'view')) {
        var strip = document.createElement('div');
        strip.className = 'ost-strip';
        strip.innerHTML = '<select id="ostMode" data-seg data-strip aria-label="Trips">' +
          '<option value="mine">My trips</option><option value="all">All trips</option></select>';
        host.appendChild(strip);
        var sel = strip.querySelector('select');
        sel.value = st.mode;
        if (F && F.segment) F.segment(sel);
        sel.addEventListener('change', function () {
          if (sel.value === st.mode) return;
          st.mode = sel.value; setUrl(); load();
        });
        host.setAttribute('data-swipe', 'ostModeStrip');
      } else st.mode = 'mine';
      var body = document.createElement('div');
      body.id = 'ostBody';
      host.appendChild(body);
    }
    load();
  }
  function paint() {
    var body = $('ostBody');
    if (!body) return;
    if (st.err) { UI.failLine(body, 'Trips', st.err, load); return; }
    if (!st.d) { UI.skeleton(body, 4); return; }
    body.innerHTML = '';
    if (st.mode === 'all') { paintAll(body); return; }
    var open = openTrip();
    if (open) body.appendChild(tripCard(open));
    else {
      var head = document.createElement('div');
      head.className = 'viewhead ost-head';
      head.innerHTML = '<div class="headmark"><h2>Trips</h2></div>' +
        (may('ops', 'work') ? '<button class="btn btn-primary" type="button" id="ostCheckIn"' + GATE + '>Check in</button>' : '');
      body.appendChild(head);
      var ci = head.querySelector('#ostCheckIn');
      if (ci) ci.addEventListener('click', function () { openStopSheet(null, ci); });
    }
    answered(body);
    var past = (st.d.trips || []).filter(function (t) { return t !== open; });
    if (!past.length) {
      if (!open) { var none = document.createElement('div'); body.appendChild(none); UI.emptyLine(none, 'No trips.'); }
      return;
    }
    body.appendChild(tripList(past, 'mine', open ? 'Recent trips' : 'Last three months'));
  }
  /* What a write answered, under the bar it was made from (both views). */
  function answered(body) {
    if (!st.msg) return;
    var m = document.createElement('p');
    m.className = 'msg ' + (st.msg.tone || ''); m.id = 'ostMsg'; m.setAttribute('role', 'status'); m.textContent = st.msg.text;
    body.appendChild(m);
  }
  function paintAll(body) {
    var bar = document.createElement('div');
    bar.className = 'cmdbar ost-allbar';
    var opts = '';
    for (var i = 0; i < 12; i++) {
      var k = C.addMonths(C.today(), -i);
      opts += '<option value="' + k + '">' + esc(C.month(k)) + '</option>';
    }
    bar.innerHTML = '<select class="select select-sm" id="ostMonth" aria-label="Month" data-nofilter>' + opts + '</select>' +
      '<span class="cmdbar-end"><span class="cmdbar-quiet"><span class="cmdbar-count" id="ostCount"></span></span>' +
      '<span class="cmdbar-acts"><button class="btn btn-sm" type="button" id="ostExport">Download</button></span></span>';
    body.appendChild(bar);
    answered(body);
    var ms = bar.querySelector('#ostMonth');
    if (!ms.querySelector('option[value="' + st.month + '"]')) ms.insertAdjacentHTML('beforeend', '<option value="' + esc(st.month) + '">' + esc(C.month(st.month)) + '</option>');
    ms.value = st.month;
    ms.addEventListener('change', function () { if (ms.value !== st.month) { st.month = ms.value; setUrl(); load(); } });
    var trips = st.d.trips || [];
    bar.querySelector('#ostCount').textContent = trips.length ? plural(trips.length, 'trip', 'trips') : '';
    var ex = bar.querySelector('#ostExport');
    ex.hidden = !trips.length;
    ex.addEventListener('click', function () { exportCsv(trips); });
    if (window.ADspaceActs && window.ADspaceActs.mark) window.ADspaceActs.mark(ex);
    if (!trips.length) { var none = document.createElement('div'); body.appendChild(none); UI.emptyLine(none, 'No trips.'); return; }
    body.appendChild(tripList(trips, 'all', C.month(st.month)));
  }

  /* One row a trip: the day over its stops; the driver, the hours, the road
     distance, where it stands. */
  function tripList(trips, key, name) {
    var G = window.ADspaceGroup, m = me();
    return G.section({
      route: 'outstation', key: key, name: name, count: trips.length, shut: false,
      table: function () {
        var t = document.createElement('div');
        t.className = 'crm-table softpanel ost-table';
        t.setAttribute('data-narrow', '640');
        t.innerHTML = '<div class="ost-row crm-head prow"><span>Trip</span><span>Driver</span><span class="ost-n">Hours</span>' +
          '<span class="ost-n">Distance</span><span>Status</span></div>';
        G.more(t, trips, 30, '', function (trip) {
          var row = document.createElement('button');
          row.type = 'button';
          row.className = 'crm-row ost-row prow';
          var route = (trip.stops || []).map(placeName);
          var who = m && trip.driver_id === m.id ? 'You' : trip.driver || '—';
          var hours = trip.ended_at ? span(trip.started_at, lastEnd(trip)) : '';
          var dist = trip.km_total != null ? km(trip.km_total) : '';
          row.setAttribute('aria-label', (trip.ref ? trip.ref + ', ' : '') + C.date(trip.started_at) + ', ' + route.join(', ') + ', open trip');
          /* On a phone (2026-11-25): who and when over the number, the
             stops' count and where they were; the distance under the state. */
          row.innerHTML = '<span class="pr-main ost-what"><b>' + esc(C.date(trip.started_at)) + '<span class="ost-m"> · ' + esc(who) + '</span></b><small>' +
              (trip.ref ? '<span class="inv-part ost-ref">' + esc(trip.ref) + '</span> · ' : '') +
              '<span class="inv-part">' + esc(plural(route.length, 'stop', 'stops')) + '</span> · ' +
              route.map(function (r) { return '<span class="inv-part">' + esc(r) + '</span>'; }).join(' · ') + '</small></span>' +
            '<span class="ost-who">' + esc(who) + '</span>' +
            '<span class="ost-n">' + (hours ? esc(hours) : '<span class="muted">—</span>') + '</span>' +
            '<span class="ost-n pr-end">' + (dist ? esc(dist) : '<span class="muted">—</span>') + '</span>' +
            '<span class="pr-state">' + stateChip(trip, true) + '</span>';
          row.addEventListener('click', function () { openDetail(trip, row); });
          return row;
        });
        return t;
      }
    });
  }
  /* A list row reads its state alone; the trip itself says it closed
     automatically. */
  function stateChip(trip, row) {
    return trip.state === 'open' ? '<span class="chip chip-state is-warn">In progress</span>'
      : '<span class="chip chip-state is-ok">Checked out</span>' + (!row && closedAuto(trip) ? '<span class="chip ost-auto">Closed automatically</span>' : '');
  }

  /* The route as a timeline (the user, 2026-11-25: the card read as lines
     of words): the office's start, each stop a dot on the hairline (filled
     once left, ringed while on site) with the leg's road distance on the
     line before it, then the return once checked out. The office is no
     stop, only where the road distance starts and ends (2026-11-24). */
  /* The zone only where the address does not already name it as one of
     its parts (2026-11-25: "…, Johor, Malaysia" read Johor twice, the
     country after it). */
  function zoneSaid(s) {
    if (!s.zone || !ZONE[s.zone]) return true;
    var z = ZONE[s.zone].toLowerCase();
    return String(s.address || '').split(',').some(function (part) { return part.trim().toLowerCase() === z; });
  }
  function zoneTag(s) {
    return zoneSaid(s) ? '' : '<span class="chip">' + esc(ZONE[s.zone]) + '</span>';
  }
  function legRow(v) {
    return '<li class="stl-row ost-leg"><span aria-hidden="true"></span><span class="ost-leg-km">' + esc(km(v)) + '</span></li>';
  }
  function officeRow(word) {
    return '<li class="stl-row ost-office"><span class="ost-office-mark" aria-hidden="true">' + GLYPH.office + '</span>' +
      '<span class="stl-name">Office<small> · ' + esc(word) + '</small></span><span></span></li>';
  }
  function routeHtml(trip) {
    var stops = trip.stops || [];
    var rows = officeRow('Start');
    var clientOf = function (s) { return { name: s.client, logo_url: s.client_logo }; };
    stops.forEach(function (s) {
      var here = !s.left_at && trip.state === 'open';
      if (s.km_from_prev != null) rows += legRow(s.km_from_prev);
      var small = [GLYPH.clock + '<span>' + esc(C.clock(s.arrived_at) + (s.left_at ? ' to ' + C.clock(s.left_at) : '')) + '</span>' +
        (s.left_how === 'office' ? '<span class="ost-how">worked out from the drive back</span>' : ''),
        GLYPH.target + '<span>' + esc(Math.round(Number(s.accuracy_m)) + ' m') + '</span>',
        GLYPH.camera + '<span>' + esc(plural(live(s).length, 'photo', 'photos')) + '</span>'];
      rows += '<li class="stl-row ost-stop' + (here ? ' is-here' : '') + '" data-stop="' + esc(s.id) + '">' +
        '<span class="stl-dot' + (here ? ' ost-dot-here' : '') + '" aria-hidden="true"></span>' +
        '<span class="stl-name ost-name">' + (s.client && bridge.clientMark ? bridge.clientMark(clientOf(s), s.client_id) : '') +
          '<span class="ost-name-w">' + esc(placeName(s)) + '</span></span>' +
        '<span class="ost-time">' + (here ? '<span class="chip chip-state is-warn">On site</span>' : esc(span(s.arrived_at, s.left_at))) + '</span>' +
        '<span class="stl-line ost-under">' +
          (s.address ? '<button class="ost-addr" type="button" aria-expanded="false" title="' + esc(s.address) + '">' + esc(s.address) + '</button>' : '') +
          '<span class="ost-small">' + small.map(function (x) { return '<span class="ost-sfact">' + x + '</span>'; }).join('') + zoneTag(s) + '</span>' +
          thumbsHtml(s) + noteHtml(trip, s, here) +
          (here && mayRecord(trip) ? '<span class="ost-acts" data-acts="' + esc(s.id) + '">' +
            '<button class="btn btn-sm" type="button" data-a="note"' + GATE + '>' + GLYPH.pen + '<span class="btn-word">' + (s.note ? 'Edit note' : 'Add note') + '</span></button>' +
            '<label class="btn btn-sm ost-shot"' + GATE + '>' + CAMERA + '<span class="btn-word">Add photo</span>' +
              '<input type="file" accept="image/*" capture="environment" data-a="photo" class="ost-file"></label></span>' : '') +
          '</span></li>';
    });
    if (trip.state === 'closed' && trip.km_back != null) rows += legRow(trip.km_back) + officeRow('End');
    return '<ol class="stl ost-route">' + rows + '</ol>';
  }
  /* A stop's note (2026-11-25): what was done or what to remember, under
     the stop; its pen edits it while the trip is open (the stop on site's
     own Edit note does so there). */
  function mayRecord(trip) {
    var m = me();
    return Boolean(m && trip.driver_id === m.id && trip.state === 'open' && may('ops', 'work'));
  }
  function noteHtml(trip, s, here) {
    if (!s.note) return '';
    var pen = !here && mayRecord(trip) ? '<button class="iconbtn ost-note-pen" type="button" data-a="note"' + GATE + ' aria-label="Edit note">' + GLYPH.pen + '</button>' : '';
    return '<span class="ost-note" data-note="' + esc(s.id) + '"><span>' + esc(s.note) + '</span>' + pen + '</span>';
  }
  function wireNotes(host, trip) {
    Array.prototype.forEach.call(host.querySelectorAll('[data-a="note"]'), function (b) {
      b.addEventListener('click', function () {
        var li = b.closest('[data-stop]'), id = li.getAttribute('data-stop');
        var stop = (trip.stops || []).filter(function (x) { return x.id === id; })[0];
        if (!stop) return;
        var after = b.closest('.ost-acts') || b.closest('.ost-note');
        if (after._ask && after._ask.open_()) { after._ask.close(); return; }
        after._ask = window.ADspaceAsk.note(after, {
          label: 'Note', send: 'Save', once: true,
          save: function (v) {
            db.rpc('outstation_stop_note', { p_stop: id, p_note: v }).then(function (r) {
              if (r.error || !r.data || r.data.error || !r.data.trip) throw new Error((r.data && SAID[r.data.error]) || W.notSaved);
              keep(r.data.trip);
              if (window.ADspaceSheet.isOpen(detail)) openDetail(r.data.trip, null);
              else { st.msg = { text: 'Saved.', tone: 'ok' }; paint(); st.msg = null; }
            }).catch(function (e) {
              st.msg = { text: (e && e.message) || W.notSaved, tone: 'err' };
              if (!window.ADspaceSheet.isOpen(detail)) paint();
              st.msg = null;
            });
          }
        });
        after._ask.box.querySelector('textarea').value = stop.note || '';
        after._ask.open();
      });
    });
  }
  function credit(trip) {
    var credited = (trip.stops || []).some(function (s) { return s.address || s.km_from_prev != null; });
    /* A block of its own holds the line inside the card's content box
       (2026-11-25: the button, a part's child with its inset, ran to the
       card's edge before its ellipsis). */
    return credited ? '<div class="ost-credit-line"><button class="ost-credit" type="button" aria-expanded="false">© openrouteservice.org by HeiGIT · Map data © OpenStreetMap contributors</button></div>' : '';
  }
  /* An address and the credit read as one line on a phone; a press shows
     them whole. */
  function wireLines(host) {
    Array.prototype.forEach.call(host.querySelectorAll('.ost-addr, .ost-credit'), function (b) {
      b.addEventListener('click', function () {
        var on = !b.classList.contains('is-whole');
        b.classList.toggle('is-whole', on); b.setAttribute('aria-expanded', String(on));
      });
    });
  }
  /* What the trip is, as facts: the number, the purpose with its glyph, who
     drove, who went along. */
  function headFacts(trip, more) {
    var m = me(), mine = Boolean(m && trip.driver_id === m.id);
    var person = function (name, word) { return '<span class="ost-person">' + (bridge.avatar ? bridge.avatar(name) : '') + '<span>' + esc(word || name) + '</span></span>'; };
    var cells = [];
    if (trip.ref) cells.push(['Trip number', refHtml(trip, true)]);
    cells.push(['Purpose', '<span class="ost-purpose">' + (GLYPH[trip.purpose] || '') + '<span>' + esc(PURPOSE[trip.purpose] || '') + '</span></span>']);
    cells.push(['Driver', mine ? person(trip.driver || 'You', 'You') : person(F.named(trip.driver_code, trip.driver))]);
    if ((trip.companions || []).length) cells.push(['Colleagues', '<span class="ost-people">' + trip.companions.map(function (c) { return person(c.name); }).join('') + '</span>']);
    (more || []).forEach(function (f) { cells.push([f[0], esc(f[1])]); });
    return '<dl class="facts ost-facts">' + cells.map(function (c) { return '<div><dt>' + esc(c[0]) + '</dt><dd>' + c[1] + '</dd></div>'; }).join('') + '</dl>';
  }
  /* The road distance as a figure, so far or in total, its legs as rows
     under it and the return once checked out. */
  function distanceHtml(trip) {
    var so = legsSoFar(trip), stops = trip.stops || [];
    var total = trip.state === 'closed' ? trip.km_total : so;
    var rows = stops.filter(function (s) { return s.km_from_prev != null; }).map(function (s) {
      return '<div><dt>To ' + esc(placeName(s)) + '</dt><dd>' + esc(km(s.km_from_prev)) + '</dd></div>';
    }).join('') + '<div><dt>Back to office</dt><dd>' + (trip.state === 'closed' ? (trip.km_back != null ? esc(km(trip.km_back)) : 'Not available') : 'Added at check-out') + '</dd></div>';
    return '<div class="tally ost-tally"><div class="tally-cell"><b>' + (total != null ? esc(km(total)) : 'Not available') + '</b>' +
      '<span>' + (trip.state === 'closed' ? 'Total' : 'So far') + '</span></div></div>' +
      '<dl class="ovfacts ost-legs">' + rows + '</dl>';
  }
  function partHead(glyph, title) {
    return '<div class="viewhead"><div class="headmark"><span class="ost-hglyph" aria-hidden="true">' + glyph + '</span><h2>' + esc(title) + '</h2></div></div>';
  }

  /* ---- The photos under each stop (2026-11-25) ------------------------- */
  /* The user, 2026-11-25: a stop read only "1 photo"; the photos are drawn
     instead, a tile each. A removed photo leaves the colleague's own view
     and the count; under All trips it stays, faded and marked. */
  function live(s) { return (s.photos || []).filter(function (p) { return !p.removed_at; }); }
  function shown(s) { return (s.photos || []).filter(function (p) { return !p.removed_at || st.mode === 'all'; }); }
  function thumbsHtml(s) {
    var ph = shown(s), pend = st.pending.filter(function (x) { return x.stop === s.id; });
    if (!ph.length && !pend.length) return '';
    return '<span class="ost-thumbs" data-thumbs="' + esc(s.id) + '">' + ph.map(function (p, i) {
      return '<button class="ost-thumb' + (p.removed_at ? ' is-removed' : '') + '" type="button" data-photo="' + esc(p.id) + '" aria-label="' +
        esc('Photo ' + (i + 1) + ', ' + placeName(s) + ', ' + C.clock(p.taken_at) + (p.removed_at ? ', removed' : '')) + '">' +
        (p.removed_at ? '<span class="ost-thumb-tag">Removed</span>' : '') + '</button>';
    }).join('') + pend.map(function (x) {
      return '<span class="ost-thumb is-busy" role="status" aria-label="Saving the photo"><img alt="" src="' + esc(x.url) + '"></span>';
    }).join('') + '</span>';
  }
  /* Every photo of a trip is signed in one request (sign-download
     `outstation.trip`), never one a photo; a repaint reads nothing again
     until the links near their hour or a photo is new. */
  var signed = {};
  function photoUrls(trip) {
    var ids = [];
    (trip.stops || []).forEach(function (s) { shown(s).forEach(function (p) { ids.push(p.id); }); });
    var had = signed[trip.id];
    var fresh = had && Date.now() - had.at < 50 * 60000 && ids.every(function (id) { return Object.prototype.hasOwnProperty.call(had.urls, id); });
    if (fresh) return Promise.resolve(had.urls);
    if (had && had.p) return had.p;
    var entry = { at: 0, urls: {}, p: null };
    entry.p = db.functions.invoke('sign-download', { body: { outstation: { trip: trip.id } } }).then(function (r) {
      if (r.error || !r.data || !r.data.urls) throw new Error('unsigned');
      entry.urls = r.data.urls; entry.at = Date.now(); entry.p = null;
      ids.forEach(function (id) { if (!Object.prototype.hasOwnProperty.call(entry.urls, id)) entry.urls[id] = null; });
      return entry.urls;
    }).catch(function () { delete signed[trip.id]; return {}; });
    signed[trip.id] = entry;
    return entry.p;
  }
  /* A tile shaded until its picture arrives; one that cannot load stays
     the shaded tile. */
  function fillThumbs(host, trip, from) {
    var btns = host.querySelectorAll('[data-photo]');
    Array.prototype.forEach.call(btns, function (b) {
      b.addEventListener('click', function () { openPhoto(trip, b.getAttribute('data-photo'), b, from); });
    });
    if (!btns.length) return;
    photoUrls(trip).then(function (urls) {
      Array.prototype.forEach.call(btns, function (b) {
        var u = urls[b.getAttribute('data-photo')];
        if (!u) { b.classList.add('is-gone'); return; }
        var img = document.createElement('img');
        img.alt = ''; img.decoding = 'async'; img.draggable = false;
        img.onerror = function () { img.remove(); b.classList.add('is-gone'); };
        img.src = u;
        b.insertBefore(img, b.firstChild);
      });
    });
  }
  function findPhoto(trip, id) {
    var hit = null;
    (trip.stops || []).forEach(function (s) { (s.photos || []).forEach(function (p) { if (p.id === id) hit = { p: p, s: s }; }); });
    return hit;
  }
  function tripNow(trip) {
    return ((st.d && st.d.trips) || []).filter(function (t) { return t.id === trip.id; })[0] || trip;
  }
  /* Remove: the driver's own photo, while the trip is in progress, and only
     while another stays at its stop (the database holds the same). */
  function mayRemove(trip, x) {
    var m = me();
    return Boolean(m && trip.driver_id === m.id && trip.state === 'open' && !x.p.removed_at && may('ops', 'work') && live(x.s).length > 1);
  }
  var REMOVE_SAID = {
    'no-photo': 'A stop must keep at least one photo. Take another photo before you remove this one.',
    closed: SAID.closed, denied: 'Only the colleague who took this photo can remove it.', 'not-found': 'This photo no longer exists.'
  };

  /* The photo full size: the stop's place, the time and the accuracy it was
     taken at; its ⋯ holds Remove where it may. No download or share of its
     own. Sheets never stack, so from a trip read whole it closes back to
     that trip. */
  var viewer = null;
  function openPhoto(trip, id, opener, from) {
    trip = tripNow(trip);
    var x = findPhoto(trip, id);
    if (!x) return;
    if (!viewer) {
      viewer = document.createElement('div');
      viewer.className = 'sheet'; viewer.id = 'ostPhotoSheet'; viewer.hidden = true;
      document.body.appendChild(viewer);
    }
    var p = x.p, s = x.s, n = shown(s).indexOf(p) + 1;
    var can = mayRemove(trip, x);
    var facts = [['Taken', C.date(p.taken_at) + ', ' + C.clock(p.taken_at)],
      ['Accuracy', p.accuracy_m != null ? Math.round(Number(p.accuracy_m)) + ' m' : 'Not available']]
      .concat(s.address ? [['Address', s.address + (zoneSaid(s) ? '' : ' · ' + ZONE[s.zone])]] : [])
      .concat(p.removed_at ? [['Removed', (p.removed_by || 'Former colleague') + ' · ' + C.date(p.removed_at) + ', ' + C.clock(p.removed_at)]] : []);
    viewer.innerHTML = '<div class="sheet-card formsheet ost-viewer" role="dialog" aria-modal="true" aria-labelledby="ostPhotoH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="ostPhotoH">' + esc(placeName(s)) + '</h3>' +
        (can ? '<span class="team-act"><button class="kmenu-btn" type="button" data-a="pmenu" aria-expanded="false" aria-label="More actions for photo ' + n + '">' + DOTS + '</button>' +
          '<div class="kmenu" hidden>' + window.ADspaceMenu.items([[], [], [], [], [], [{ a: 'remove', label: 'Remove', need: 'ops:work' }]], 'data-o') + '</div></span>' : '') +
        '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        '<div class="ost-view' + (p.removed_at ? ' is-removed' : '') + '" id="ostPhotoBox"><span class="pageload-spin ost-view-spin" role="status" aria-label="Loading"></span></div>' +
        '<dl class="ovfacts ost-view-facts">' + facts.map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('') + '</dl>' +
        '<p class="msg" id="ostPhotoMsg" role="status"></p>' +
      '</div></div>';
    var v = { trip: trip, from: from, after: null };
    viewer.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    window.ADspaceSheet.show(viewer, { opener: from === 'detail' ? null : opener, onClose: function () { closedPhoto(v); } });
    photoUrls(trip).then(function (urls) {
      var box = $('ostPhotoBox');
      if (!box || !viewer.contains(box)) return;
      var u = urls[p.id];
      var none = function () { box.classList.add('is-gone'); box.innerHTML = '<span class="ost-view-note">The photo could not be loaded. Close it and open it again.</span>'; };
      if (!u) { none(); return; }
      var img = document.createElement('img');
      img.alt = 'Photo ' + n + ', ' + placeName(s) + ', ' + C.clock(p.taken_at); img.draggable = false;
      img.onload = function () { var w = box.querySelector('.ost-view-spin'); if (w) w.remove(); };
      img.onerror = none;
      img.src = u;
      box.appendChild(img);
    });
    if (!can) return;
    var mb = viewer.querySelector('[data-a="pmenu"]'), menu = mb.nextElementSibling;
    mb.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      if (bridge.shutMenus) bridge.shutMenus();
      menu.hidden = !open; mb.setAttribute('aria-expanded', String(open));
      if (open) { if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(menu); window.ADspaceMenu.place(mb, menu); }
    });
    var rm = menu.querySelector('[data-o="remove"]');
    rm.addEventListener('click', function () {
      menu.hidden = true; mb.setAttribute('aria-expanded', 'false');
      var msg = $('ostPhotoMsg');
      msg.className = 'msg'; msg.textContent = '';
      db.rpc('outstation_photo_remove', { p_photo: p.id }).then(function (r) {
        if (r.error || !r.data || r.data.error || !r.data.trip) {
          msg.className = 'msg err'; msg.textContent = (r.data && REMOVE_SAID[r.data.error]) || 'Not removed. Please try again.';
          return;
        }
        keep(r.data.trip);
        v.trip = r.data.trip; v.after = { stop: s.id, photo: p.id };
        window.ADspaceSheet.close();
      }).catch(function () { msg.className = 'msg err'; msg.textContent = 'Not removed. Please try again.'; });
    });
  }
  /* Closing the photo goes back to where it was opened, and a removal
     offers its Undo there, under the stop's photos. */
  function closedPhoto(v) {
    var t = tripNow(v.trip);
    if (v.from === 'detail') openDetail(t, null); else paint();
    if (!v.after) return;
    var a = v.after;
    var host = document.querySelector((v.from === 'detail' ? '#ostTripSheet ' : '#ostBody ') + '[data-thumbs="' + a.stop + '"]');
    if (!host || !bridge.undoHere) return;
    bridge.undoHere('Photo removed.', function () {
      db.rpc('outstation_photo_restore', { p_photo: a.photo }).then(function (r) {
        if (r.error || !r.data || r.data.error || !r.data.trip) throw new Error((r.data && REMOVE_SAID[r.data.error]) || 'Not undone. Please try again.');
        keep(r.data.trip);
        if (v.from === 'detail') { if (window.ADspaceSheet.isOpen(detail)) openDetail(r.data.trip, null); }
        else { st.msg = { text: 'Undone.', tone: 'ok' }; paint(); st.msg = null; }
      }).catch(function (e) {
        st.msg = { text: (e && e.message) || 'Not undone. Please try again.', tone: 'err' };
        if (v.from !== 'detail') paint();
        st.msg = null;
      });
    }, host);
  }

  /* A trip's hours run from its check-in to the last stop's end (a trip
     checked out at the office ends its last visit a drive earlier). */
  function lastEnd(trip) {
    var st0 = (trip.stops || [])[(trip.stops || []).length - 1];
    return (st0 && st0.left_at) || trip.ended_at;
  }
  function closedAuto(trip) {
    return trip.state === 'closed' && (trip.stops || []).some(function (x) { return x.left_how === 'auto'; });
  }
  function legsSoFar(trip) {
    var legs = (trip.stops || []).map(function (s) { return s.km_from_prev; });
    if (!legs.length || legs.some(function (v) { return v == null; })) return null;
    return legs.reduce(function (a, b) { return a + Number(b); }, 0);
  }
  function withWord(trip) {
    return (trip.companions || []).map(function (c) { return c.name; }).join(', ');
  }

  /* Screen 2: the trip in progress. */
  function tripCard(trip) {
    var box = document.createElement('div');
    box.className = 'ost-trip';
    var long = Date.now() - Date.parse(trip.started_at) >= BREAK_MS;
    box.innerHTML =
      '<section class="rec-part ost-part"><div class="viewhead ost-vh"><div class="headmark"><h2>Trip · ' + esc(C.date(trip.started_at)) + '</h2></div>' +
          '<span class="ost-vh-end">' + stateChip(trip) + menuHtml(trip) + '</span></div>' +
        headFacts(trip) +
        (long ? '<p class="msg warn ost-break" role="status">On the road for more than 4 hours. Take a break before you drive on.</p>' : '') +
      '</section>' +
      '<section class="rec-part ost-part">' + partHead(GLYPH.pin, 'Route') + routeHtml(trip) +
        '<p class="msg" id="ostTripMsg" role="status"></p>' + credit(trip) + '</section>' +
      '<section class="rec-part ost-part">' + partHead(GLYPH.road, 'Distance') + distanceHtml(trip) + '</section>' +
      /* Go on to another site or finish (2026-11-25): Add stop then
         Check out, equal, Check out nearest the thumb. */
      (st.office && st.office.trip === trip.id && st.office.at ? '<p class="msg ost-office-line" role="status">You are at the office.</p>' : '') +
      '<div class="ost-foot">' +
        '<button class="btn btn-primary" type="button" data-a="out"' + GATE + '>Check out</button>' +
        '<button class="btn" type="button" data-a="next"' + GATE + '>' + PLUS + '<span class="btn-word">Add stop</span></button>' +
      '</div>';
    box.querySelector('[data-a="next"]').addEventListener('click', function (e) { openStopSheet(trip, e.currentTarget); });
    box.querySelector('[data-a="out"]').addEventListener('click', function (e) { openOutSheet(trip, e.currentTarget); });
    wire(box, trip);
    wireLines(box);
    wireNotes(box, trip);
    fillThumbs(box, trip, 'card');
    readOffice(trip);
    var file = box.querySelector('[data-a="photo"]');
    if (file) file.addEventListener('change', function () {
      var f = file.files && file.files[0];
      file.value = '';
      if (!f) return;
      var stop = (trip.stops || [])[trip.stops.length - 1];
      /* The photo shows at once from the phone, its ring turning until it
         is saved. */
      var wait = { stop: stop.id, url: URL.createObjectURL(f) };
      var done = function () { st.pending = st.pending.filter(function (x) { return x !== wait; }); URL.revokeObjectURL(wait.url); };
      st.pending.push(wait);
      paint();
      quickSpot().then(function (spot) {
        return addPhoto(trip.id, stop.id, { file: f, at: new Date().toISOString(), spot: spot });
      }).then(function (t) {
        done(); keep(t); st.msg = { text: 'Photo added.', tone: 'ok' }; paint(); st.msg = null;
      }).catch(function (e) {
        done(); st.msg = { text: (e && e.message) || 'The photo could not be saved. Take it again.', tone: 'err' }; paint(); st.msg = null;
      });
    });
    return box;
  }

  /* ---- At the office (2026-11-25) --------------------------------------- */
  /* An iPhone web app cannot read the location in the background, so the
     trip in progress takes one reading when it is opened, on a phone alone
     (`ADspaceAdmin.onTravelDevice`), through the one watcher. Within the
     office radius of Settings' pin, Check out is a check-out at the office. */
  function metres(a, b) {
    var r = function (d) { return d * Math.PI / 180; };
    return 2 * 6371000 * Math.asin(Math.sqrt(Math.pow(Math.sin(r(b.lat - a.lat) / 2), 2) +
      Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.pow(Math.sin(r(b.lng - a.lng) / 2), 2)));
  }
  function readOffice(trip) {
    if (!bridge.onTravelDevice || !bridge.onTravelDevice()) return;
    if (st.office && st.office.trip === trip.id) return;
    st.office = { trip: trip.id, at: null };
    var mine = st.office;
    quickSpot().then(function (spot) {
      if (st.office !== mine || !spot) return;
      var pin = { lat: Number(setting('outstation_office_lat', NaN)), lng: Number(setting('outstation_office_lng', NaN)) };
      var limit = Number(setting('outstation_accuracy_m', 50)), radius = Number(setting('outstation_office_radius_m', 100));
      if (!isFinite(pin.lat) || !isFinite(pin.lng) || spot.acc > limit || metres(spot, pin) > radius) return;
      mine.at = { lat: spot.lat, lng: spot.lng, acc: spot.acc, read: new Date().toISOString() };
      if (!window.ADspaceSheet.isOpen()) paint();
    });
  }

  /* ---- The phone's location -------------------------------------------- */
  /* The best reading in up to 20 seconds, never a cached one; `tick` hears
     each better one. Settles early on 5 m, or once one inside the limit
     has stood six seconds. */
  function readSpot(tick, limit, ctl) {
    return new Promise(function (ok, no) {
      var geo = navigator.geolocation;
      if (!geo) { no({ code: 'none' }); return; }
      var best = null, began = Date.now(), done = false, id = null, timer = null;
      var finish = function () {
        if (done) return; done = true;
        if (id !== null) geo.clearWatch(id);
        clearTimeout(timer);
        if (best) ok(best); else no({ code: 'unavailable' });
      };
      id = geo.watchPosition(function (p) {
        var c = p.coords;
        var r = { lat: Math.round(c.latitude * 1e6) / 1e6, lng: Math.round(c.longitude * 1e6) / 1e6,
          acc: Math.round(c.accuracy * 10) / 10, at: new Date().toISOString() };
        if (!best || r.acc < best.acc) { best = r; if (tick) tick(best); }
        if (best.acc <= 5 || (limit && best.acc <= limit && Date.now() - began >= 6000)) finish();
      }, function (e) {
        if (e && e.code === 1) { done = true; if (id !== null) geo.clearWatch(id); clearTimeout(timer); no({ code: 'denied' }); }
      }, { enableHighAccuracy: true, maximumAge: 0, timeout: WATCH_MS });
      timer = setTimeout(finish, WATCH_MS);
      /* A phone that reports once and then stays quiet settles at six
         seconds too, where that one reading is inside the limit. */
      setTimeout(function () { if (!done && best && limit && best.acc <= limit) finish(); }, 6100);
      /* A read abandoned (Locate again, the sheet shut) stops watching and
         never answers. */
      if (ctl) ctl.cancel = function () { if (done) return; done = true; if (id !== null) geo.clearWatch(id); clearTimeout(timer); };
    });
  }
  /* A photo's place: the best in eight seconds, or none. */
  function quickSpot() {
    return new Promise(function (ok) {
      var geo = navigator.geolocation;
      if (!geo) { ok(null); return; }
      var best = null, done = false, timer = null, id = null;
      var end = function () { if (done) return; done = true; clearTimeout(timer); if (id !== null) geo.clearWatch(id); ok(best); };
      id = geo.watchPosition(function (p) {
        var c = p.coords;
        if (!best || c.accuracy < best.acc) best = { lat: Math.round(c.latitude * 1e6) / 1e6, lng: Math.round(c.longitude * 1e6) / 1e6, acc: Math.round(c.accuracy * 10) / 10 };
        if (best.acc <= 10) end();
      }, end, { enableHighAccuracy: true, maximumAge: 0, timeout: 8000 });
      if (done) geo.clearWatch(id);
      timer = setTimeout(end, 8000);
    });
  }
  var STALE_MS = 9 * 60 * 1000;
  /* The location block of a sheet: read, refuse, read again. */
  function spotBlock(host) {
    var limit = setting('outstation_accuracy_m', 50);
    var o = { spot: null };
    host.className = 'ost-loc';
    host.innerHTML = '<div class="ost-loc-mark" aria-hidden="true"></div><div class="ost-loc-words" role="status">' +
      '<span class="ost-loc-state"></span><small class="ost-loc-note"></small></div>' +
      '<button class="btn btn-sm" type="button" data-a="again" hidden>Locate again</button>';
    var state = host.querySelector('.ost-loc-state'), note = host.querySelector('.ost-loc-note'), again = host.querySelector('[data-a="again"]');
    var say = function (tone, word, line) {
      host.setAttribute('data-tone', tone);
      state.innerHTML = '<span class="chip chip-state is-' + tone + '">' + esc(word) + '</span>';
      note.textContent = line || '';
    };
    /* Where the phone says it is, as it says it (the user, 2026-11-24: "is
       it possible to show the location name? Or coordinate instead of just
       Reading your location"): the coordinates from the first reading, and
       the place OpenStreetMap names for them once the reading is accepted.
       The stop's own address is still looked up again when it is saved. */
    var at = function (b) { return b.lat.toFixed(6) + ', ' + b.lng.toFixed(6); };
    o.stop = function () { if (o.ctl && o.ctl.cancel) o.ctl.cancel(); o.ctl = null; };
    o.read = function () {
      o.stop();
      var ctl = o.ctl = {};
      o.spot = null;
      again.hidden = true;
      say('warn', 'Reading your location…', '');
      return readSpot(function (b) { if (o.ctl === ctl) say('warn', 'Reading your location… accurate to ' + Math.round(b.acc) + ' m', at(b)); }, limit, ctl).then(function (b) {
        if (o.ctl !== ctl) return;
        again.hidden = false;
        if (b.acc > limit) {
          say('danger', 'Location accurate to ' + Math.round(b.acc) + ' m', 'It must be within ' + limit + ' m. ' + PRECISE);
          return;
        }
        o.spot = b;
        say('ok', 'Location accurate to ' + Math.round(b.acc) + ' m', at(b));
        geo({ near: { lat: b.lat, lng: b.lng } }).then(function (d) {
          if (o.ctl !== ctl || o.spot !== b || !d || !d.address) return;
          note.innerHTML = esc(d.address) + '<br>' + esc(at(b));
        });
      }).catch(function (e) {
        if (o.ctl !== ctl) return;
        again.hidden = false;
        say('danger', 'Location unavailable', e && e.code === 'denied'
          ? 'Location access is off for this site. Allow it in the browser\'s settings, then press Locate again.'
          : 'The location could not be read. Move to an open spot, then press Locate again. ' + PRECISE);
      });
    };
    again.addEventListener('click', o.read);
    return o;
  }

  /* ---- Photos ----------------------------------------------------------- */
  function shrink(file) {
    return new Promise(function (ok, no) {
      var img = new Image(), url = URL.createObjectURL(file);
      img.onload = function () {
        var s = Math.min(1, 1600 / Math.max(img.width, img.height)), c = document.createElement('canvas');
        c.width = Math.round(img.width * s); c.height = Math.round(img.height * s);
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(url);
        c.toBlob(function (b) { if (b) ok(b); else no(new Error('The photo could not be read. Take it again.')); }, 'image/jpeg', 0.82);
      };
      img.onerror = function () { URL.revokeObjectURL(url); no(new Error('The photo could not be read. Take it again.')); };
      img.src = url;
    });
  }
  function addPhoto(tripId, stopId, p) {
    var cfg = window.ADSPACE_CONFIG || {};
    return shrink(p.file).then(function (blob) {
      return db.functions.invoke((cfg.s3 && cfg.s3.functionName) || 'sign-upload', {
        body: { purpose: 'outstation', tripId: tripId, ext: 'jpg', size: blob.size }
      }).then(function (r) {
        if (!r.error && r.data && r.data.uploadUrl) return { r: r, blob: blob };
        return API.fnRefusal(r).then(function (code) {
          throw new Error(code === 'not_allowed' ? SAID.denied : 'The photo could not be saved. Take it again.');
        });
      });
    }).then(function (o) {
      return fetch(o.r.data.uploadUrl, { method: 'PUT', headers: { 'Content-Type': o.r.data.contentType }, body: o.blob })
        .then(function (res) { if (!res.ok) throw new Error('The photo could not be saved. Take it again.'); return o.r.data.key; });
    }).then(function (key) {
      var s = p.spot || {};
      return db.rpc('outstation_photo_add', { p_stop: stopId, p_path: key, p_taken_at: p.at,
        p_lat: s.lat == null ? null : s.lat, p_lng: s.lng == null ? null : s.lng, p_accuracy: s.acc == null ? null : s.acc }).then(function (r) {
        if (r.error || !r.data || r.data.error) throw new Error(said(r.data));
        return r.data.trip;
      });
    });
  }
  /* The photos taken in a sheet before it is sent: a tile each, then the
     camera's own tile. */
  function shotsBlock(host) {
    var o = { list: [] };
    host.className = 'ost-shots';
    var paintShots = function () {
      host.innerHTML = o.list.map(function (p, i) {
        return '<span class="ost-shot-tile"><img alt="Photo ' + (i + 1) + '" src="' + esc(p.url) + '">' +
          '<button class="iconbtn" type="button" data-i="' + i + '" aria-label="Remove photo ' + (i + 1) + '">' + X + '</button></span>';
      }).join('') +
        '<label class="ost-shot-add" aria-label="Take a photo">' + CAMERA +
        '<input type="file" accept="image/*" capture="environment" class="ost-file" data-a="take"></label>';
      host.querySelector('[data-a="take"]').addEventListener('change', function (e) {
        var f = e.target.files && e.target.files[0];
        if (!f) return;
        var shot = { file: f, at: new Date().toISOString(), url: URL.createObjectURL(f), spot: null };
        o.list.push(shot);
        paintShots();
        quickSpot().then(function (s) { shot.spot = s; });
        if (o.changed) o.changed();
      });
      Array.prototype.forEach.call(host.querySelectorAll('[data-i]'), function (b) {
        b.addEventListener('click', function () {
          var i = Number(b.getAttribute('data-i'));
          URL.revokeObjectURL(o.list[i].url);
          o.list.splice(i, 1);
          paintShots();
          if (o.changed) o.changed();
        });
      });
    };
    o.reset = function () { o.list.forEach(function (p) { URL.revokeObjectURL(p.url); }); o.list = []; paintShots(); };
    /* While the stop is sent, each photo's ring turns over it. */
    o.busy = function (on) { host.classList.toggle('is-busy', !!on); };
    paintShots();
    return o;
  }

  /* ---- Check in and Next stop (screen 1) -------------------------------- */
  var stopSheet = null, stopKit = null;
  var people = null, clients = null;
  function readPick() {
    if (people && clients) return Promise.resolve();
    return Promise.all([
      db.from('team_members').select('id, name, staff_code, active').eq('active', true).order('name'),
      db.from('clients').select('id, name, stage, client_code').order('name'),
      /* Only a colleague who may work My Work joins a trip, as only one may
         drive it: never one kept for the namecard alone (2026-11-24). */
      bridge.pickable ? bridge.pickable('ops') : null
    ]).then(function (r) {
      var m = me();
      people = ((r[0] && r[0].data) || []).filter(function (p) { return (!m || p.id !== m.id) && !(bridge.isSystem && bridge.isSystem(p)); }).sort(F.byStaff);
      if (bridge.pickFrom) people = bridge.pickFrom(people, r[2]);
      clients = ((r[1] && r[1].data) || []).filter(function (c) { return c.stage !== 'past'; }).sort(F.byClient);
    });
  }
  function buildStopSheet() {
    if (stopSheet) return stopSheet;
    stopSheet = document.createElement('div');
    stopSheet.className = 'sheet'; stopSheet.id = 'ostStopSheet'; stopSheet.hidden = true;
    stopSheet.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ostStopH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="ostStopH">Check in</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        '<div class="row"><div><label class="field-label" for="ostClient">Client</label>' +
          '<select class="select" id="ostClient" aria-required="true"></select></div></div>' +
        /* The client and the place apart (2026-11-24): work for a client
           away from its own site still reaches its Calls and visits. */
        '<div class="row" id="ostWhereRow" hidden><div><label class="field-label" for="ostWhere">Place</label>' +
          '<select class="select" id="ostWhere" data-seg data-seg-value><option value="site">Client\'s site</option>' +
          '<option value="venue">Another venue</option></select></div></div>' +
        '<div class="row" id="ostVenueRow" hidden><div><label class="field-label" for="ostVenue">Venue</label>' +
          '<textarea class="input" id="ostVenue" data-oneline rows="1" maxlength="200" placeholder="ADspace Advertising"></textarea></div></div>' +
        /* What Check in waits for comes first, under the place: a long list
           of colleagues once pushed both below a phone's screen (2026-11-24). */
        '<div class="row"><div><span class="field-label">Location</span><div id="ostLoc"></div></div></div>' +
        '<div class="row"><div><span class="field-label" id="ostShotsL">Take a photo on site</span><div id="ostShots" role="group" aria-labelledby="ostShotsL"></div></div></div>' +
        '<div class="row ost-in"><div><label class="field-label" for="ostPurpose">Purpose</label>' +
          '<select class="select" id="ostPurpose" data-seg data-seg-value><option value="meeting">Meeting</option><option value="shooting">Shooting</option>' +
          '<option value="event">Event</option><option value="other">Other</option></select></div></div>' +
        '<div class="row ost-in"><div><label class="field-label" for="ostNote">Note</label>' +
          '<textarea class="input" id="ostNote" rows="2" maxlength="2000" placeholder="Optional" data-nodraft></textarea></div></div>' +
        '<div class="row ost-in"><div><span class="field-label" id="ostWithL">Colleagues</span>' +
          '<div class="meta-accs ost-people" id="ostPeople" role="group" aria-labelledby="ostWithL"></div></div></div>' +
        '<p class="msg" id="ostStopMsg" role="status"></p>' +
      '</div>' +
      '<div class="sheet-foot">' +
        '<button class="btn btn-primary" type="button" id="ostStopGo" data-nocheck>Check in</button>' +
        '<button class="btn btn-quiet" type="button" id="ostStopCancel">Cancel</button>' +
      '</div></div>';
    document.body.appendChild(stopSheet);
    if (F && F.segment) { F.segment($('ostPurpose')); F.segment($('ostWhere')); }
    stopSheet.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('ostStopCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    var placeRows = function () {
      var cv = $('ostClient').value;
      $('ostWhereRow').hidden = !cv || cv === 'other';
      $('ostVenueRow').hidden = !(cv === 'other' || (cv && $('ostWhere').value === 'venue'));
    };
    $('ostClient').addEventListener('change', placeRows);
    $('ostWhere').addEventListener('change', placeRows);
    stopKit = { loc: spotBlock($('ostLoc')), shots: shotsBlock($('ostShots')) };
    $('ostStopGo').addEventListener('click', sendStop);
    return stopSheet;
  }
  function stopMsg(text, tone) { var m = $('ostStopMsg'); m.textContent = text || ''; m.className = 'msg' + (tone ? ' ' + tone : ''); }
  function openStopSheet(trip, opener) {
    buildStopSheet();
    stopSheet.trip = trip;
    $('ostStopH').textContent = trip ? 'Add stop' : 'Check in';
    $('ostStopGo').textContent = trip ? 'Add stop' : 'Check in';
    Array.prototype.forEach.call(stopSheet.querySelectorAll('.ost-in'), function (el) { el.hidden = !!trip; });
    $('ostVenue').value = ''; $('ostNote').value = ''; $('ostVenueRow').hidden = true; $('ostWhereRow').hidden = true;
    $('ostWhere').value = 'site';
    if (F && F.paint) F.paint($('ostWhere'));
    $('ostPurpose').value = 'meeting';
    if (F && F.paint) F.paint($('ostPurpose'));
    stopMsg('');
    stopKit.shots.reset();
    $('ostClient').innerHTML = '<option value="">Loading…</option>';
    window.ADspaceSheet.show(stopSheet, { opener: opener, onClose: function () { stopKit.loc.stop(); } });
    stopKit.loc.read();
    readPick().then(function () {
      $('ostClient').innerHTML = '<option value="">Choose a client</option>' + clients.map(function (c) {
        return '<option value="' + esc(c.id) + '">' + esc(F.named(c.client_code, c.name)) + '</option>';
      }).join('') + '<option value="other">No client</option>';
      $('ostPeople').innerHTML = people.map(function (p) {
        return '<label class="tickline"><input type="checkbox" data-id="' + esc(p.id) + '"> <span>' + esc(F.named(p.staff_code, p.name)) + '</span></label>';
      }).join('');
    }).catch(function () { stopMsg('The clients could not be loaded. Close this form and open it again.', 'err'); });
  }
  function sendStop() {
    var trip = stopSheet.trip, go = $('ostStopGo');
    var cv = $('ostClient').value, venue = $('ostVenue').value.trim(), spot = stopKit.loc.spot;
    if (!cv) { stopMsg(SAID['no-place'], 'err'); $('ostClient').focus(); return; }
    var atVenue = cv === 'other' || $('ostWhere').value === 'venue';
    if (atVenue && !venue) { stopMsg('Enter the venue.', 'err'); $('ostVenue').focus(); return; }
    if (!spot) { stopMsg('The location must be accurate to within ' + setting('outstation_accuracy_m', 50) + ' m. Press Locate again.', 'err'); return; }
    /* A reading is good for ten minutes in the database: one older than
       nine is read again here, never sent to be refused (2026-11-24: a
       reading left open while the driver did something else read "could not
       be read"). */
    if (Date.now() - Date.parse(spot.at) > STALE_MS) {
      stopKit.loc.read();
      stopMsg('The location is more than 10 minutes old and will be updated. Press ' + go.textContent + ' once the new location appears.', 'warn');
      return;
    }
    if (!stopKit.shots.list.length) { stopMsg('Take a photo on site.', 'err'); return; }
    var args = { p_client: cv === 'other' ? null : cv, p_venue: atVenue ? venue : null,
      p_lat: spot.lat, p_lng: spot.lng, p_accuracy: spot.acc, p_read_at: spot.at };
    var call;
    if (trip) {
      args.p_trip = trip.id;
      call = db.rpc('outstation_stop_add', args);
    } else {
      args.p_purpose = $('ostPurpose').value;
      args.p_note = $('ostNote').value.trim() || null;
      args.p_companions = Array.prototype.filter.call($('ostPeople').querySelectorAll('input[data-id]'), function (c) { return c.checked; })
        .map(function (c) { return c.getAttribute('data-id'); });
      call = db.rpc('outstation_check_in', args);
    }
    go.disabled = true;
    stopMsg('');
    stopKit.shots.busy(true);
    var shots = stopKit.shots.list.slice();
    call.then(function (r) {
      if (r.error || !r.data || r.data.error) throw new Error(r.data && r.data.error ? said(r.data) : (r.error && r.error.message) || W.notSaved);
      var t = r.data.trip, stop = t.stops[t.stops.length - 1];
      keep(t);
      /* The photos follow the stop they belong to, one after another. */
      var chain = Promise.resolve(t), failed = 0;
      shots.forEach(function (p) {
        chain = chain.then(function (cur) {
          return addPhoto(t.id, stop.id, p).catch(function () { failed++; return cur; });
        });
      });
      return chain.then(function (cur) {
        keep(cur);
        go.disabled = false;
        stopKit.shots.busy(false);
        if (window.ADspaceSheet.clean) window.ADspaceSheet.clean();
        window.ADspaceSheet.close();
        stopKit.shots.reset();
        st.msg = failed ? { text: plural(failed, 'photo', 'photos') + ' could not be saved. Press Add photo to take ' + (failed === 1 ? 'it' : 'them') + ' again.', tone: 'err' }
          : { text: trip ? 'Stop added.' : 'Checked in.', tone: 'ok' };
        paint(); st.msg = null;
        geo({ stop: stop.id }).then(function () { return geo({ trip: t.id }); }).then(reread);
      });
    }).catch(function (e) {
      go.disabled = false;
      stopKit.shots.busy(false);
      stopMsg((e && e.message) || W.notSaved, 'err');
    });
  }

  /* ---- Check out -------------------------------------------------------- */
  var outSheet = null;
  function buildOutSheet() {
    if (outSheet) return outSheet;
    outSheet = document.createElement('div');
    outSheet.className = 'sheet'; outSheet.id = 'ostOutSheet'; outSheet.hidden = true;
    var stars = '';
    for (var i = 1; i <= 5; i++) stars += '<button class="ost-star" type="button" role="radio" aria-checked="false" data-n="' + i + '" aria-label="' + plural(i, 'star', 'stars') + '">' + STAR + '</button>';
    outSheet.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ostOutH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="ostOutH">Check out</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        /* No reading at check-out (the user, 2026-11-24: "checkout doesnt
           need to read location again. Only on-site needs to check once"):
           the way back is measured to the office pin. */
        '<dl class="ovfacts ost-out-facts" id="ostOutFacts" hidden><div><dt>Location</dt><dd>At the office</dd></div></dl>' +
        '<div class="row"><div><label class="field-label" for="ostOutNote">Note</label>' +
          '<textarea class="input" id="ostOutNote" rows="2" maxlength="2000" placeholder="Optional" data-nodraft></textarea></div></div>' +
        '<div class="row"><div><span class="field-label" id="ostRateL">Rate your trip</span>' +
          '<div class="ost-stars" role="radiogroup" aria-labelledby="ostRateL">' + stars + '</div></div></div>' +
        '<p class="msg" id="ostOutMsg" role="status"></p>' +
      '</div>' +
      '<div class="sheet-foot">' +
        '<button class="btn btn-primary" type="button" id="ostOutGo" data-nocheck>Check out</button>' +
        '<button class="btn btn-quiet" type="button" id="ostOutCancel">Cancel</button>' +
      '</div></div>';
    document.body.appendChild(outSheet);
    outSheet.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('ostOutCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    Array.prototype.forEach.call(outSheet.querySelectorAll('.ost-star'), function (b) {
      b.addEventListener('click', function () {
        var n = Number(b.getAttribute('data-n'));
        outSheet.rating = outSheet.rating === n ? null : n;
        paintStars();
      });
    });
    $('ostOutGo').addEventListener('click', sendOut);
    return outSheet;
  }
  function paintStars() {
    Array.prototype.forEach.call(outSheet.querySelectorAll('.ost-star'), function (b) {
      var n = Number(b.getAttribute('data-n'));
      b.classList.toggle('is-on', !!outSheet.rating && n <= outSheet.rating);
      b.setAttribute('aria-checked', String(outSheet.rating === n));
    });
  }
  function outMsg(text, tone) { var m = $('ostOutMsg'); m.textContent = text || ''; m.className = 'msg' + (tone ? ' ' + tone : ''); }
  function openOutSheet(trip, opener, edit) {
    buildOutSheet();
    outSheet.trip = trip;
    outSheet.edit = !!edit;
    outSheet.office = !edit && st.office && st.office.trip === trip.id ? st.office.at : null;
    outSheet.rating = edit ? trip.rating || null : null;
    paintStars();
    $('ostOutNote').value = edit ? trip.end_note || '' : '';
    $('ostOutH').textContent = edit ? 'Edit check-out' : 'Check out';
    $('ostOutGo').textContent = edit ? 'Save' : 'Check out';
    $('ostOutFacts').hidden = !outSheet.office;
    outMsg('');
    window.ADspaceSheet.show(outSheet, { opener: opener });
  }
  function sendOut() {
    var trip = outSheet.trip, go = $('ostOutGo');
    go.disabled = true;
    outMsg('');
    var note = $('ostOutNote').value.trim() || null, rating = outSheet.rating || null, at = outSheet.office, edit = outSheet.edit;
    /* A reading is good for ten minutes in the database: one older than
       nine is not sent, and Check out is the ordinary one. */
    if (at && Date.now() - Date.parse(at.read) > STALE_MS) at = null;
    var call = edit ? db.rpc('outstation_checkout_edit', { p_trip: trip.id, p_note: note, p_rating: rating })
      : at ? db.rpc('outstation_check_out_office', { p_trip: trip.id, p_lat: at.lat, p_lng: at.lng, p_accuracy: at.acc, p_read_at: at.read, p_note: note, p_rating: rating })
      : db.rpc('outstation_check_out', { p_trip: trip.id, p_lat: null, p_lng: null, p_accuracy: null, p_read_at: null, p_note: note, p_rating: rating });
    call.then(function (r) {
      go.disabled = false;
      if (r.data && (r.data.error === 'not-office' || r.data.error === 'bad-location')) {
        /* Moved away from the office meanwhile: the sheet says so and the
           next press is the ordinary check-out. */
        st.office = { trip: trip.id, at: null }; outSheet.office = null; $('ostOutFacts').hidden = true;
        outMsg('This device is no longer at the office. Press Check out again.', 'warn');
        return;
      }
      if (r.error || !r.data || r.data.error) { outMsg(r.data && r.data.error ? said(r.data) : (r.error && r.error.message) || W.notSaved, 'err'); return; }
      keep(r.data.trip);
      if (window.ADspaceSheet.clean) window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      st.msg = { text: edit ? 'Saved.' : 'Checked out.', tone: 'ok' };
      paint(); st.msg = null;
      if (!edit) geo({ trip: trip.id }).then(reread);
    }).catch(function (e) { go.disabled = false; outMsg((e && e.message) || W.notSaved, 'err'); });
  }

  /* The place and the road distance arrive after the write; the list is
     read again once they have. A refusal leaves the trip as it stands. */
  function geo(body) {
    return db.functions.invoke('outstation-geo', { body: body }).then(function (r) { return r.data || {}; }).catch(function () { return {}; });
  }
  function reread() {
    if (!st.d || !st.host || !document.body.contains(st.host)) return;
    var p = period(), mine = ++st.seq;
    db.rpc('outstation_trips', { p_from: p.from, p_to: p.to, p_all: st.mode === 'all' }).then(function (r) {
      if (mine !== st.seq || r.error || !r.data || r.data.error) return;
      st.d = r.data;
      if (!window.ADspaceSheet.isOpen()) paint();
    });
  }

  /* ---- The trip number and Delete (2026-11-24) --------------------------- */
  /* The number copies on a press, as a serial does on the Register; on a
     list row, itself a button, it is words. */
  function refHtml(trip, alone) {
    if (!trip.ref) return '';
    return '<button class="serial-copy" type="button" data-a="ref" aria-label="Copy ' + esc(trip.ref) + '">' + esc(trip.ref) + '</button>' + (alone ? '' : ' · ');
  }
  /* The driver deletes their own trip, an admin any; at Edit the Delete is
     a request an admin decides (js/delreq.js turns it into Request delete). */
  function mayDelete(trip) {
    var m = me();
    var own = Boolean(m && trip.driver_id === m.id);
    return (own || Boolean(bridge.isAdmin && bridge.isAdmin())) && may('ops', 'work');
  }
  function mayEditOut(trip) {
    var m = me();
    return Boolean(m && trip.driver_id === m.id && closedAuto(trip) && may('ops', 'work'));
  }
  function menuHtml(trip) {
    if (mayEditOut(trip)) {
      return '<span class="team-act ost-menu"><button class="kmenu-btn" type="button" data-a="menu" aria-expanded="false" ' +
        'aria-label="More actions for ' + esc(trip.ref || 'this trip') + '">' + DOTS + '</button>' +
        '<div class="kmenu" hidden>' + window.ADspaceMenu.items([[], [{ a: 'editout', label: 'Edit check-out', need: 'ops:work' }], [], [], [],
          mayDelete(trip) ? [{ a: 'delete', label: 'Delete', need: 'ops:manage' }] : []], 'data-o') + '</div></span>';
    }
    if (!mayDelete(trip)) return '';
    return '<span class="team-act ost-menu"' + (may('ops', 'manage') ? '' : ' hidden') + '><button class="kmenu-btn" type="button" data-a="menu" aria-expanded="false" ' +
      'aria-label="More actions for ' + esc(trip.ref || 'this trip') + '">' + DOTS + '</button>' +
      '<div class="kmenu" hidden>' + window.ADspaceMenu.items([[], [], [], [], [], [{ a: 'delete', label: 'Delete', need: 'ops:manage' }]], 'data-o') + '</div></span>';
  }
  function wire(host, trip) {
    var cp = host.querySelector('[data-a="ref"]');
    if (cp) cp.addEventListener('click', function (e) { e.stopPropagation(); if (window.ADspaceCopy) window.ADspaceCopy.to(cp, trip.ref); });
    var wrap = host.querySelector('.ost-menu');
    if (!wrap) return;
    var mb = wrap.querySelector('.kmenu-btn'), menu = wrap.querySelector('.kmenu'), del = menu.querySelector('[data-o="delete"]');
    var editOut = menu.querySelector('[data-o="editout"]');
    /* At Edit the Delete is a request, shown once it is known to be open
       to the reader (beside Edit check-out, which stands either way). */
    if (del && !may('ops', 'manage') && window.ADspaceDelReq) {
      window.ADspaceDelReq.load().then(function () {
        if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(menu);
        var open = window.ADspaceDelReq.liveItem(del) || del.getAttribute('data-req');
        if (open) wrap.hidden = false; else if (editOut) del.hidden = true;
      });
    }
    if (editOut) editOut.addEventListener('click', function () {
      menu.hidden = true; mb.setAttribute('aria-expanded', 'false');
      openOutSheet(trip, mb, true);
    });
    mb.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      if (bridge.shutMenus) bridge.shutMenus();
      menu.hidden = !open; mb.setAttribute('aria-expanded', String(open));
      if (open) { if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(menu); window.ADspaceMenu.place(mb, menu); }
    });
    if (del) del.addEventListener('click', function () {
      menu.hidden = true; mb.setAttribute('aria-expanded', 'false');
      askDelete(trip);
    });
  }
  var GONE = {
    denied: 'You do not have permission to delete this trip. Please ask an admin.',
    'not-found': 'This trip no longer exists.',
    'confirm-required': 'The trip number does not match. Type it exactly as shown.'
  };
  function askDelete(trip) {
    var stops = (trip.stops || []).length, photos = 0;
    (trip.stops || []).forEach(function (s) { photos += (s.photos || []).length; });
    var filed = (trip.stops || []).some(function (s) { return s.filed; });
    var ref = trip.ref || '';
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: (ref ? 'Trip ' + ref : 'The trip') + ' on ' + C.date(trip.started_at) + ' will be deleted, with its ' + plural(stops, 'stop', 'stops') + ' and ' +
        plural(photos, 'photo', 'photos') + '.' + (filed ? ' The visits this trip added to each client\'s Calls and visits will also be deleted.' : '') + ' This cannot be undone.',
      go: 'Delete', tone: 'danger', wait: true,
      fields: [{ name: 'ref', label: 'Type the trip number to confirm', placeholder: ref, match: ref,
        need: 'Type the trip number to confirm.', mismatch: GONE['confirm-required'] }]
    }, function (v) {
      return db.rpc('outstation_trip_delete', { p_trip: trip.id, p_confirm: String(v.ref || '').trim().toUpperCase() }).then(function (r) {
        var d = r && r.data;
        if (r && r.error) {
          return /PGRST202|42883|Could not find the function/i.test((r.error.code || '') + ' ' + (r.error.message || ''))
            ? window.ADspaceWords.line.notYet : 'Not deleted. Please try again.';
        }
        if (!d || d.error || !d.deleted) return GONE[d && d.error] || 'Not deleted. The database refused the request.';
        if (window.ADspaceSheet.isOpen()) window.ADspaceSheet.close();
        st.msg = { text: 'Deleted.', tone: 'ok' };
        Promise.resolve(load()).then(function () { st.msg = null; });
        return '';
      }, function () { return 'Not deleted. Please try again.'; });
    });
  }

  /* ---- A trip read whole ------------------------------------------------ */
  var detail = null;
  function openDetail(trip, opener) {
    if (!detail) {
      detail = document.createElement('div');
      detail.className = 'sheet'; detail.id = 'ostTripSheet'; detail.hidden = true;
      document.body.appendChild(detail);
    }
    var more = [['Hours', trip.ended_at ? span(trip.started_at, lastEnd(trip)) : 'In progress']]
      .concat(trip.rating ? [['Rating', plural(trip.rating, 'star', 'stars')]] : [])
      .concat(trip.note ? [['Note', trip.note]] : [])
      .concat(trip.end_note ? [['Check-out note', trip.end_note]] : []);
    detail.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ostTripH" data-narrow="560">' +
      '<div class="sheet-head ost-sheet-head"><h3 id="ostTripH"><span class="ost-tw">Trip · </span>' + esc(C.date(trip.started_at)) + '</h3>' + '<span class="ost-vh-end">' + stateChip(trip) + menuHtml(trip) + '</span>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        '<section class="fsec">' + headFacts(trip, more) + '</section>' +
        '<section class="fsec"><h4 class="fsec-h">Route</h4>' + routeHtml(trip) + credit(trip) + '</section>' +
        '<section class="fsec"><h4 class="fsec-h">Distance</h4>' + distanceHtml(trip) + '</section>' +
      '</div></div>';
    detail.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    wire(detail, trip);
    wireLines(detail);
    wireNotes(detail, trip);
    window.ADspaceSheet.show(detail, { opener: opener });
    fillThumbs(detail, trip, 'detail');
  }

  /* ---- Download (All trips) --------------------------------------------- */
  function exportCsv(trips) {
    var head = ['Trip number', 'Date', 'Driver', 'Driver code', 'Colleagues', 'Purpose', 'Stop', 'Client code', 'Client or venue', 'Address', 'Zone',
      'Arrived', 'Left', 'Hours on site', 'Accuracy (m)', 'Latitude', 'Longitude', 'Photos', 'Km from previous stop', 'Km back to office', 'Km total',
      'Checked out', 'Rating', 'Note', 'Check-out note', 'Stop note'];
    var rows = [head];
    trips.forEach(function (t) {
      (t.stops || []).forEach(function (s, i) {
        var last = i === t.stops.length - 1;
        rows.push([t.ref || '', C.day(t.started_at), t.driver || '', t.driver_code || '', withWord(t), PURPOSE[t.purpose] || '', s.seq, s.client_code || '',
          placeName(s), s.address || '', ZONE[s.zone] || '', C.clock(s.arrived_at), s.left_at ? C.clock(s.left_at) : '',
          s.left_at ? (Math.round((Date.parse(s.left_at) - Date.parse(s.arrived_at)) / 36e4) / 10).toFixed(1) : '',
          s.accuracy_m, s.lat, s.lng, live(s).length, s.km_from_prev == null ? '' : s.km_from_prev,
          last && t.km_back != null ? t.km_back : '', last && t.km_total != null ? t.km_total : '',
          last && t.ended_at ? C.clock(t.ended_at) : '', last && t.rating ? t.rating : '', i === 0 ? t.note || '' : '', last ? t.end_note || '' : '', s.note || '']);
      });
    });
    var csv = rows.map(function (r) {
      return r.map(function (v) {
        var s = String(v == null ? '' : v);
        if (/^[=+\-@]/.test(s)) s = '\'' + s;
        return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
      }).join(',');
    }).join('\r\n');
    var blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'outstation-' + st.month + '.csv';
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  window.ADspaceOutstation = { draw: draw, urlPart: urlPart };
})();
