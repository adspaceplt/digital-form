/*
 * Malaysia's clock, one copy (2026-10-12; the user: "this entire portal
 * should follow the timezone of malaysia").
 *
 * The portal reads and writes every day and time in Malaysia time (GMT+8,
 * which Singapore shares and neither moves for summer). A browser's own
 * Date methods (getDate, getHours, setHours, new Date(y, m, d)) answer in
 * the device's zone, so a colleague in Tokyo or Los Angeles saw a due date,
 * "today" and an overdue mark a day or some hours off. A page asks this
 * script instead:
 *
 *   ADspaceClock.day(v)         'YYYY-MM-DD', the Malaysian day of a moment
 *   ADspaceClock.today()        today's Malaysian day
 *   ADspaceClock.parts(v)       { y, mo (0 to 11), d, h, mi, wd (0 Sunday) }
 *   ADspaceClock.start(day)     the moment the Malaysian day begins (a Date)
 *   ADspaceClock.at(day, hhmm)  the moment of a Malaysian day and time
 *   ADspaceClock.time(v)        'HH:MM', the Malaysian time of a moment
 *   ADspaceClock.addDays(day, n), addMonths(month or day, n) -> 'YYYY-MM'
 *   ADspaceClock.between(a, b)  whole days from day a to day b
 *
 * A moment is a Date, a number of milliseconds, or a string. A string of a
 * day alone (2026-10-12) is that Malaysian day, and a date and time written
 * with no zone (2026-10-12T15:30, as a date and a time field give it) is
 * Malaysian time; a string with its zone (Z, +00:00) is that moment. Days
 * are counted on the calendar, never by a device's midnight.
 */
(function () {
  'use strict';
  var OFF = 8 * 3600000;
  var DAY = 86400000;
  var DAY_ONLY = /^\d{4}-\d{2}-\d{2}$/;
  var NO_ZONE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/;

  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function moment(v) {
    if (v == null || v === '') return null;
    var t;
    if (v instanceof Date) t = v.getTime();
    else if (typeof v === 'number') t = v;
    else {
      var s = String(v).trim();
      if (DAY_ONLY.test(s)) s += 'T00:00:00+08:00';
      else if (NO_ZONE.test(s)) s += '+08:00';
      t = Date.parse(s.replace(/([+-]\d{2})(\d{2})$/, '$1:$2'));
    }
    return isNaN(t) ? null : t;
  }
  /* A Date whose UTC fields read Malaysia's wall clock. */
  function wall(v) { var t = moment(v); return t === null ? null : new Date(t + OFF); }

  function parts(v) {
    var w = wall(v);
    if (!w) return null;
    return { y: w.getUTCFullYear(), mo: w.getUTCMonth(), d: w.getUTCDate(),
             h: w.getUTCHours(), mi: w.getUTCMinutes(), wd: w.getUTCDay() };
  }
  function dayOf(y, mo, d) {
    var w = new Date(Date.UTC(y, mo, d));
    return w.getUTCFullYear() + '-' + pad(w.getUTCMonth() + 1) + '-' + pad(w.getUTCDate());
  }
  function day(v) { var p = parts(v); return p ? dayOf(p.y, p.mo, p.d) : ''; }
  function today() { return day(Date.now()); }
  function split(s) {
    var m = /^(\d{4})-(\d{2})(?:-(\d{2}))?/.exec(String(s || ''));
    return m ? { y: Number(m[1]), mo: Number(m[2]) - 1, d: m[3] ? Number(m[3]) : 1 } : null;
  }
  function start(v) {
    var k = DAY_ONLY.test(String(v || '')) ? String(v) : day(v);
    var t = k ? moment(k) : null;
    return t === null ? null : new Date(t);
  }
  function at(d, hhmm) {
    var k = split(d), m = /^(\d{1,2}):(\d{2})/.exec(String(hhmm || '00:00'));
    if (!k || !m) return null;
    return new Date(Date.UTC(k.y, k.mo, k.d, Number(m[1]), Number(m[2])) - OFF);
  }
  function time(v) { var p = parts(v); return p ? pad(p.h) + ':' + pad(p.mi) : ''; }
  function addDays(d, n) { var k = split(d); return k ? dayOf(k.y, k.mo, k.d + (Number(n) || 0)) : ''; }
  function addMonths(d, n) { var k = split(d); return k ? dayOf(k.y, k.mo + (Number(n) || 0), 1).slice(0, 7) : ''; }
  function between(a, b) {
    var x = split(a), y = split(b);
    if (!x || !y) return null;
    return Math.round((Date.UTC(y.y, y.mo, y.d) - Date.UTC(x.y, x.mo, x.d)) / DAY);
  }
  function weekday(d) { var k = split(d); return k ? new Date(Date.UTC(k.y, k.mo, k.d)).getUTCDay() : null; }

  window.ADspaceClock = {
    OFFSET: OFF, moment: moment, parts: parts, day: day, today: today, start: start,
    at: at, time: time, addDays: addDays, addMonths: addMonths, between: between, weekday: weekday
  };
})();
