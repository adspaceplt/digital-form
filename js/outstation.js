/*
 * Outstation — a driver's trip out of the office, in My Work (OUTSTATION
 * RECORD, 2026-11-23; the user approved the mockup's screens 1, 2 and 5).
 * It replaces the Lark form "Outstation Record Form".
 *
 *   * My trips: the trip in progress (its route, office to each stop and
 *     back, the road distance so far, Next stop, Add photo, Check out, and
 *     Add claim drawn disabled until claims are built, release 2), then the
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
    'no-place': 'Choose the client, or enter the venue.',
    'bad-client': 'You do not have access to this client. Please ask an admin.',
    'bad-companion': 'One of the colleagues chosen cannot join this trip. Untick them and try again.',
    'bad-location': 'The location could not be read. Press Read again.',
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
  function placeName(s) { return s.client || s.venue || 'Client deleted'; }

  /* ---- State and the address ------------------------------------------- */
  var st = { mode: 'mine', month: C.today().slice(0, 7), d: null, err: null, host: null, seq: 0, msg: null };
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
      else st.d = r.data;
      paint();
    }).catch(function (e) {
      if (mine !== st.seq) return;
      st.err = (e && e.message) || 'The trips could not be loaded.'; paint();
    });
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
        (may('ops', 'work') ? '<button class="btn btn-primary" type="button" id="ostCheckIn">Check in</button>' : '');
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
          var hours = trip.ended_at ? span(trip.started_at, trip.ended_at) : '';
          var dist = trip.km_total != null ? km(trip.km_total) : '';
          row.setAttribute('aria-label', (trip.ref ? trip.ref + ', ' : '') + C.date(trip.started_at) + ', ' + route.join(', ') + ', open trip');
          row.innerHTML = '<span class="pr-main ost-what"><b>' + esc(C.date(trip.started_at)) + '</b><small>' +
              (trip.ref ? '<span class="inv-part ost-ref">' + esc(trip.ref) + '</span> · ' : '') +
              route.map(function (r) { return '<span class="inv-part">' + esc(r) + '</span>'; }).join(' · ') +
              '<span class="inv-part"> · ' + esc(PURPOSE[trip.purpose] || '') + '</span>' +
              '<span class="ost-m"> · ' + esc(who) + '</span></small></span>' +
            '<span class="ost-who">' + esc(who) + '</span>' +
            '<span class="ost-n">' + (hours ? esc(hours) : '<span class="muted">—</span>') + '</span>' +
            '<span class="ost-n pr-end">' + (dist ? esc(dist) : '<span class="muted">—</span>') + '</span>' +
            '<span class="pr-state">' + stateChip(trip) + '</span>';
          row.addEventListener('click', function () { openDetail(trip, row); });
          return row;
        });
        return t;
      }
    });
  }
  function stateChip(trip) {
    return trip.state === 'open' ? '<span class="chip chip-state is-warn">On the road</span>'
      : '<span class="chip chip-state is-ok">Checked out</span>';
  }

  /* The route, office to each stop and back, as screen 2 draws it. */
  /* The client sites alone (the user, 2026-11-24: "Check in out only
     needs to be on client site no need from Office"): each stop from its
     check-in to its check-out. The office stands only behind the road
     distance (Settings' pin), never as a stop. */
  function routeHtml(trip) {
    var rows = '';
    (trip.stops || []).forEach(function (s) {
      var here = !s.left_at && trip.state === 'open';
      var facts = ['Within ' + Math.round(Number(s.accuracy_m)) + ' m', plural((s.photos || []).length, 'photo', 'photos'),
        C.clock(s.arrived_at) + (s.left_at ? ' to ' + C.clock(s.left_at) : '')];
      rows += '<li class="ost-stop' + (here ? ' is-here' : '') + '" data-stop="' + esc(s.id) + '"><span class="ost-dot" aria-hidden="true"></span>' +
        '<span class="ost-place"><span class="ost-name"><b>' + esc(placeName(s)) + '</b>' + (s.km_from_prev != null ? '<span class="ost-km"> · ' + esc(km(s.km_from_prev)) + '</span>' : '') + '</span>' +
        '<small>' + facts.map(function (f) { return '<span class="inv-part">' + esc(f) + '</span>'; }).join(' · ') + '</small>' +
        (s.address ? '<small>' + esc(s.address) + (s.zone ? ' · ' + esc(ZONE[s.zone]) : '') + '</small>' : '') + '</span>' +
        '<span class="ost-time">' + esc(here ? 'On site' : span(s.arrived_at, s.left_at)) + '</span></li>';
    });
    var credited = (trip.stops || []).some(function (s) { return s.address || s.km_from_prev != null; });
    return '<ol class="ost-route">' + rows + '</ol>' +
      (credited ? '<p class="ost-credit">© openrouteservice.org by HeiGIT · Map data © OpenStreetMap contributors</p>' : '');
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
    var so = legsSoFar(trip);
    var w = withWord(trip);
    box.innerHTML =
      '<section class="rec-part ost-part"><div class="viewhead"><div class="headmark"><h2>Trip · ' + esc(C.date(trip.started_at)) + '</h2></div>' + stateChip(trip) + menuHtml(trip) + '</div>' +
        '<p class="ost-line">' + refHtml(trip) + esc([PURPOSE[trip.purpose], 'You drive'].concat(w ? ['With ' + w] : []).join(' · ')) + '</p>' +
        (long ? '<p class="msg warn ost-break" role="status">On the road for more than 4 hours. Take a break before you drive on.</p>' : '') +
      '</section>' +
      '<section class="rec-part ost-part"><div class="viewhead"><div class="headmark"><h2>Route</h2></div></div>' + routeHtml(trip) +
        '<div class="ost-acts">' +
          '<button class="btn btn-sm" type="button" data-a="next">' + PLUS + '<span class="btn-word">Next stop</span></button>' +
          '<label class="btn btn-sm ost-shot">' + CAMERA + '<span class="btn-word">Add photo</span>' +
            '<input type="file" accept="image/*" capture="environment" data-a="photo" class="ost-file"></label>' +
        '</div><p class="msg" id="ostTripMsg" role="status"></p></section>' +
      '<section class="rec-part ost-part"><div class="viewhead"><div class="headmark"><h2>Distance</h2></div></div>' +
        '<dl class="ovfacts"><div><dt>Road distance</dt><dd>' + (so != null ? esc(km(so)) + ' so far' : '<span class="muted">Not available</span>') + '</dd></div>' +
        '<div><dt>Return</dt><dd>Added at check-out</dd></div></dl></section>' +
      '<div class="ost-foot">' +
        '<button class="btn btn-primary" type="button" data-a="out">Check out</button>' +
        '<button class="btn ost-soon" type="button" aria-disabled="true" data-a="claim">Add claim (Coming soon)</button>' +
      '</div>';
    box.querySelector('[data-a="next"]').addEventListener('click', function (e) { openStopSheet(trip, e.currentTarget); });
    box.querySelector('[data-a="out"]').addEventListener('click', function (e) { openOutSheet(trip, e.currentTarget); });
    box.querySelector('[data-a="claim"]').addEventListener('click', function (e) { e.preventDefault(); });
    wire(box, trip);
    var file = box.querySelector('[data-a="photo"]');
    file.addEventListener('change', function () {
      var f = file.files && file.files[0];
      file.value = '';
      if (!f) return;
      var stop = (trip.stops || [])[trip.stops.length - 1];
      var msg = $('ostTripMsg');
      msg.className = 'msg'; msg.textContent = 'Saving the photo…';
      quickSpot().then(function (spot) {
        return addPhoto(trip.id, stop.id, { file: f, at: new Date().toISOString(), spot: spot });
      }).then(function (t) {
        keep(t); st.msg = { text: 'Photo added.', tone: 'ok' }; paint(); st.msg = null;
      }).catch(function (e) { msg.className = 'msg err'; msg.textContent = (e && e.message) || 'The photo could not be saved. Take it again.'; });
    });
    return box;
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
          acc: Math.round(c.accuracy * 10) / 10, at: new Date(p.timestamp || Date.now()).toISOString() };
        if (!best || r.acc < best.acc) { best = r; if (tick) tick(best); }
        if (best.acc <= 5 || (limit && best.acc <= limit && Date.now() - began >= 6000)) finish();
      }, function (e) {
        if (e && e.code === 1) { done = true; if (id !== null) geo.clearWatch(id); clearTimeout(timer); no({ code: 'denied' }); }
      }, { enableHighAccuracy: true, maximumAge: 0, timeout: WATCH_MS });
      timer = setTimeout(finish, WATCH_MS);
      /* A phone that reports once and then stays quiet settles at six
         seconds too, where that one reading is inside the limit. */
      setTimeout(function () { if (!done && best && limit && best.acc <= limit) finish(); }, 6100);
      /* A read abandoned (Read again, the sheet shut) stops watching and
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
  /* The location block of a sheet: read, refuse, read again. */
  function spotBlock(host) {
    var limit = setting('outstation_accuracy_m', 50);
    var o = { spot: null };
    host.className = 'ost-loc';
    host.innerHTML = '<div class="ost-loc-mark" aria-hidden="true"></div><div class="ost-loc-words" role="status">' +
      '<span class="ost-loc-state"></span><small class="ost-loc-note"></small></div>' +
      '<button class="btn btn-sm" type="button" data-a="again" hidden>Read again</button>';
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
      return readSpot(function (b) { if (o.ctl === ctl) say('warn', 'Reading your location… within ' + Math.round(b.acc) + ' m', at(b)); }, limit, ctl).then(function (b) {
        if (o.ctl !== ctl) return;
        again.hidden = false;
        if (b.acc > limit) {
          say('danger', 'Location within ' + Math.round(b.acc) + ' m', 'It must be within ' + limit + ' m. ' + PRECISE);
          return;
        }
        o.spot = b;
        say('ok', 'Location within ' + Math.round(b.acc) + ' m', at(b));
        geo({ near: { lat: b.lat, lng: b.lng } }).then(function (d) {
          if (o.ctl !== ctl || o.spot !== b || !d || !d.address) return;
          note.textContent = d.address + ' · ' + at(b);
        });
      }).catch(function (e) {
        if (o.ctl !== ctl) return;
        again.hidden = false;
        say('danger', 'Location not read', e && e.code === 'denied'
          ? 'Location access is off for this site. Allow it in the browser\'s settings, then press Read again.'
          : 'The location could not be read. Move to an open spot, then press Read again. ' + PRECISE);
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
      db.from('clients').select('id, name, stage, client_code').order('name')
    ]).then(function (r) {
      var m = me();
      people = ((r[0] && r[0].data) || []).filter(function (p) { return (!m || p.id !== m.id) && !(bridge.isSystem && bridge.isSystem(p)); }).sort(F.byStaff);
      clients = ((r[1] && r[1].data) || []).filter(function (c) { return c.stage !== 'past'; }).sort(F.byClient);
    });
  }
  function buildStopSheet() {
    if (stopSheet) return stopSheet;
    stopSheet = document.createElement('div');
    stopSheet.className = 'sheet'; stopSheet.id = 'ostStopSheet'; stopSheet.hidden = true;
    var keepMonths = setting('outstation_keep_months', 24);
    stopSheet.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ostStopH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="ostStopH">Check in</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        '<div class="row"><div><label class="field-label" for="ostClient">Client</label>' +
          '<select class="select" id="ostClient" aria-required="true"></select></div></div>' +
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
        '<div class="row ost-in"><div><span class="field-label" id="ostWithL">Going together</span>' +
          '<div class="meta-accs ost-people" id="ostPeople" role="group" aria-labelledby="ostWithL"></div>' +
          '<p class="asknote">You are the driver. Only the driver records the trip.</p></div></div>' +
        '<p class="asknote ost-in">Personal data notice: your location and photos are recorded with this trip and kept for ' + esc(plural(keepMonths, 'month', 'months')) + '.</p>' +
        '<p class="msg" id="ostStopMsg" role="status"></p>' +
      '</div>' +
      '<div class="sheet-foot">' +
        '<button class="btn btn-primary" type="button" id="ostStopGo" data-nocheck>Check in</button>' +
        '<button class="btn btn-quiet" type="button" id="ostStopCancel">Cancel</button>' +
      '</div></div>';
    document.body.appendChild(stopSheet);
    if (F && F.segment) F.segment($('ostPurpose'));
    stopSheet.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('ostStopCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('ostClient').addEventListener('change', function () { $('ostVenueRow').hidden = $('ostClient').value !== 'other'; });
    stopKit = { loc: spotBlock($('ostLoc')), shots: shotsBlock($('ostShots')) };
    $('ostStopGo').addEventListener('click', sendStop);
    return stopSheet;
  }
  function stopMsg(text, tone) { var m = $('ostStopMsg'); m.textContent = text || ''; m.className = 'msg' + (tone ? ' ' + tone : ''); }
  function openStopSheet(trip, opener) {
    buildStopSheet();
    stopSheet.trip = trip;
    $('ostStopH').textContent = trip ? 'Next stop' : 'Check in';
    $('ostStopGo').textContent = trip ? 'Add stop' : 'Check in';
    Array.prototype.forEach.call(stopSheet.querySelectorAll('.ost-in'), function (el) { el.hidden = !!trip; });
    $('ostVenue').value = ''; $('ostNote').value = ''; $('ostVenueRow').hidden = true;
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
      }).join('') + '<option value="other">Other place</option>';
      $('ostPeople').innerHTML = people.map(function (p) {
        return '<label class="tickline"><input type="checkbox" data-id="' + esc(p.id) + '"> <span>' + esc(F.named(p.staff_code, p.name)) + '</span></label>';
      }).join('');
    }).catch(function () { stopMsg('The clients could not be loaded. Close this form and open it again.', 'err'); });
  }
  function sendStop() {
    var trip = stopSheet.trip, go = $('ostStopGo');
    var cv = $('ostClient').value, venue = $('ostVenue').value.trim(), spot = stopKit.loc.spot;
    if (!cv) { stopMsg('Choose the client, or Other place.', 'err'); $('ostClient').focus(); return; }
    if (cv === 'other' && !venue) { stopMsg('Enter the venue.', 'err'); $('ostVenue').focus(); return; }
    if (!spot) { stopMsg('Read the location within ' + setting('outstation_accuracy_m', 50) + ' m first.', 'err'); return; }
    if (!stopKit.shots.list.length) { stopMsg('Take a photo on site.', 'err'); return; }
    var args = { p_client: cv === 'other' ? null : cv, p_venue: cv === 'other' ? venue : null,
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
  function openOutSheet(trip, opener) {
    buildOutSheet();
    outSheet.trip = trip;
    outSheet.rating = null;
    paintStars();
    $('ostOutNote').value = '';
    outMsg('');
    window.ADspaceSheet.show(outSheet, { opener: opener });
  }
  function sendOut() {
    var trip = outSheet.trip, go = $('ostOutGo');
    go.disabled = true;
    outMsg('');
    db.rpc('outstation_check_out', { p_trip: trip.id, p_lat: null, p_lng: null, p_accuracy: null, p_read_at: null,
      p_note: $('ostOutNote').value.trim() || null, p_rating: outSheet.rating || null }).then(function (r) {
      go.disabled = false;
      if (r.error || !r.data || r.data.error) { outMsg(r.data && r.data.error ? said(r.data) : (r.error && r.error.message) || W.notSaved, 'err'); return; }
      keep(r.data.trip);
      if (window.ADspaceSheet.clean) window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      st.msg = { text: 'Checked out.', tone: 'ok' };
      paint(); st.msg = null;
      geo({ trip: trip.id }).then(reread);
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
  function menuHtml(trip) {
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
    /* At Edit the ⋯ shows once the request is known to be open to it. */
    if (wrap.hidden && window.ADspaceDelReq) {
      window.ADspaceDelReq.load().then(function () {
        if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(menu);
        if (window.ADspaceDelReq.liveItem(del) || del.getAttribute('data-req')) wrap.hidden = false;
      });
    }
    mb.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      if (bridge.shutMenus) bridge.shutMenus();
      menu.hidden = !open; mb.setAttribute('aria-expanded', String(open));
      if (open) { if (window.ADspaceMenu.tidy) window.ADspaceMenu.tidy(menu); window.ADspaceMenu.place(mb, menu); }
    });
    del.addEventListener('click', function () {
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
      body: ref + ' · The trip on ' + C.date(trip.started_at) + ' will be deleted, with its ' + plural(stops, 'stop', 'stops') + ' and ' +
        plural(photos, 'photo', 'photos') + '.' + (filed ? ' The visits it recorded on the clients\' Calls and visits stay.' : '') + ' This cannot be undone.',
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
    var w = withWord(trip), m = me();
    var facts = [['Purpose', PURPOSE[trip.purpose]], ['Driver', m && trip.driver_id === m.id ? 'You' : F.named(trip.driver_code, trip.driver)]]
      .concat(w ? [['Going together', w]] : [])
      .concat([['Hours', trip.ended_at ? span(trip.started_at, trip.ended_at) : 'On the road'],
        ['Road distance', trip.km_total != null ? km(trip.km_total) : 'Not available']])
      .concat(trip.rating ? [['Rating', plural(trip.rating, 'star', 'stars')]] : [])
      .concat(trip.note ? [['Note', trip.note]] : [])
      .concat(trip.end_note ? [['Check-out note', trip.end_note]] : []);
    var photos = [];
    (trip.stops || []).forEach(function (s) { (s.photos || []).forEach(function (p) { photos.push({ p: p, s: s }); }); });
    detail.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ostTripH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="ostTripH">Trip · ' + esc(C.date(trip.started_at)) + '</h3>' + menuHtml(trip) +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        '<section class="fsec"><dl class="ovfacts">' + (trip.ref ? '<div><dt>Trip number</dt><dd>' + refHtml(trip, true) + '</dd></div>' : '') +
          facts.map(function (f) { return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>'; }).join('') + '</dl></section>' +
        '<section class="fsec"><h4 class="fsec-h">Route</h4>' + routeHtml(trip) + '</section>' +
        (photos.length ? '<section class="fsec"><h4 class="fsec-h">Photos</h4><div class="ost-gallery">' + photos.map(function (x) {
          return '<figure class="ost-photo" data-photo="' + esc(x.p.id) + '"><span class="ost-photo-img" aria-hidden="true"></span>' +
            '<figcaption>' + esc(placeName(x.s)) + ' · ' + esc(C.clock(x.p.taken_at)) + '</figcaption></figure>';
        }).join('') + '</div></section>' : '') +
      '</div></div>';
    detail.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    wire(detail, trip);
    window.ADspaceSheet.show(detail, { opener: opener });
    Array.prototype.forEach.call(detail.querySelectorAll('[data-photo]'), function (fig) {
      db.functions.invoke('sign-download', { body: { outstation: { photo: fig.getAttribute('data-photo') } } }).then(function (r) {
        if (r.error) { gone(fig); return; }
        return window.ADspaceAPI.fileOf(r.data).then(function (b) {
          if (!b || !/^image\//.test(b.type)) { gone(fig); return; }
          var img = document.createElement('img');
          img.alt = fig.querySelector('figcaption').textContent;
          img.src = URL.createObjectURL(b);
          fig.querySelector('.ost-photo-img').replaceWith(img);
        });
      }).catch(function () { gone(fig); });
    });
  }

  /* A photo that could not be read says so in its own tile. */
  function gone(fig) {
    fig.classList.add('is-gone');
    var t = fig.querySelector('.ost-photo-img');
    if (t) t.textContent = 'Not available';
  }

  /* ---- Download (All trips) --------------------------------------------- */
  function exportCsv(trips) {
    var head = ['Trip number', 'Date', 'Driver', 'Driver code', 'Going together', 'Purpose', 'Stop', 'Client code', 'Client or venue', 'Address', 'Zone',
      'Arrived', 'Left', 'Hours on site', 'Accuracy (m)', 'Latitude', 'Longitude', 'Photos', 'Km from previous', 'Km back to office', 'Km total',
      'Checked out', 'Rating', 'Note', 'Check-out note'];
    var rows = [head];
    trips.forEach(function (t) {
      (t.stops || []).forEach(function (s, i) {
        var last = i === t.stops.length - 1;
        rows.push([t.ref || '', C.day(t.started_at), t.driver || '', t.driver_code || '', withWord(t), PURPOSE[t.purpose] || '', s.seq, s.client_code || '',
          placeName(s), s.address || '', ZONE[s.zone] || '', C.clock(s.arrived_at), s.left_at ? C.clock(s.left_at) : '',
          s.left_at ? (Math.round((Date.parse(s.left_at) - Date.parse(s.arrived_at)) / 36e4) / 10).toFixed(1) : '',
          s.accuracy_m, s.lat, s.lng, (s.photos || []).length, s.km_from_prev == null ? '' : s.km_from_prev,
          last && t.km_back != null ? t.km_back : '', last && t.km_total != null ? t.km_total : '',
          last && t.ended_at ? C.clock(t.ended_at) : '', last && t.rating ? t.rating : '', i === 0 ? t.note || '' : '', last ? t.end_note || '' : '']);
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
