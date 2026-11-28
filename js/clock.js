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
 *   ADspaceClock.periodEnd(day, n) the last day of n months from day: the
 *                               day before the same day n months on, else
 *                               that month's last day (a start on the 31st)
 *   ADspaceClock.between(a, b)  whole days from day a to day b
 *   ADspaceClock.date(v, o)     12 Sept 2026; o.long (12 September 2026),
 *                               o.year false (12 Sept), o.weekday (Sat, 12
 *                               Sept 2026), o.zh (2026年9月12日)
 *                               o.named (20 Nov 2026 (Friday); with o.zh
 *                               2026年11月20日（星期五）): a day the reader
 *                               waits on carries its weekday; o.named
 *                               'ahead' only while the day has not passed;
 *                               o.short the weekday cut (22 Sept (Tue))
 *   ADspaceClock.due(v, o)      a moment the reader waits on: 20 Nov 2026
 *                               (Friday), 12:30pm; o.zh 2026年11月20日（星期五）
 *                               下午12:30; o.space (12:30 pm)
 *   ADspaceClock.clock(v, o)    11:30am; o.space (11:30 am), o.h24 (11:30),
 *                               o.zh (上午11:30)
 *   ADspaceClock.month(v, o)    Sept 2026 (a month key or a moment);
 *                               o.long (September 2026), o.zh (2026年9月)
 *
 * A moment is a Date, a number of milliseconds, or a string. A string of a
 * day alone (2026-10-12) is that Malaysian day, and a date and time written
 * with no zone (2026-10-12T15:30, as a date and a time field give it) is
 * Malaysian time; a string with its zone (Z, +00:00) is that moment. Days
 * are counted on the calendar, never by a device's midnight.
 */
(function () {
  'use strict';
  /* The agency's own clock: the profile's time zone (js/config.js
     `ADspaceAgency.time_zone`, restructure release 18), held as its offset
     from UTC. A zone that moves for summer is not read yet: its offset is
     the one it holds when the page loads. */
  var ZONE = (window.ADspaceAgency || {}).time_zone;
  if (!ZONE) throw new Error('ADspaceClock: the agency profile names no time zone (js/config.js).');
  function offsetOf(zone) {
    var t = Math.floor(Date.now() / 60000) * 60000, p = {};
    new Intl.DateTimeFormat('en-US', { timeZone: zone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit' }).formatToParts(new Date(t)).forEach(function (x) { p[x.type] = Number(x.value); });
    return Date.UTC(p.year, p.month - 1, p.day, p.hour % 24, p.minute) - t;
  }
  var OFF = offsetOf(ZONE);
  /* The offset as a moment's string writes it: +08:00. */
  var SUFFIX = (function (m) {
    var a = Math.abs(m);
    return (m < 0 ? '-' : '+') + (a < 600 ? '0' : '') + Math.floor(a / 60) + ':' + (a % 60 < 10 ? '0' : '') + a % 60;
  })(OFF / 60000);
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
      if (DAY_ONLY.test(s)) s += 'T00:00:00' + SUFFIX;
      else if (NO_ZONE.test(s)) s += SUFFIX;
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
             h: w.getUTCHours(), mi: w.getUTCMinutes(), s: w.getUTCSeconds(), wd: w.getUTCDay() };
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
  /* The day before the same day n months on; where that month is too short
     for the day, its last day, never a day rolled into the month after (the
     audit of 2026-10-26, finding 8). One copy for a letter's, a quotation's
     and a renewal's period (2026-11-12). */
  function periodEnd(d, n) {
    var k = split(d);
    if (!k || !String(d).match(/^\d{4}-\d{2}-\d{2}/)) return '';
    n = Number(n) || 0;
    var last = new Date(Date.UTC(k.y, k.mo + n + 1, 0)).getUTCDate();
    return k.d > last ? dayOf(k.y, k.mo + n, last) : dayOf(k.y, k.mo + n, k.d - 1);
  }
  function between(a, b) {
    var x = split(a), y = split(b);
    if (!x || !y) return null;
    return Math.round((Date.UTC(y.y, y.mo, y.d) - Date.UTC(x.y, x.mo, x.d)) / DAY);
  }
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var LONG = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  var WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  var WDAY = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  var WD_ZH = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  /* A month key (2026-09) is that month's first day. */
  function partsOf(v) { return parts(/^\d{4}-\d{2}$/.test(String(v || '')) ? v + '-01' : v); }
  function date(v, o) {
    o = o || {};
    var p = partsOf(v);
    if (!p) return '';
    /* 'ahead': the weekday only while the day is today or later, so a
       shoot or a deadline gone by reads as history. */
    if (o.named === 'ahead') o = Object.assign({}, o, { named: dayOf(p.y, p.mo, p.d) >= today() });
    /* o.short: the weekday cut, where a fact has a narrow box (22 Sept (Tue),
       9月22日（周二）; the selection page's head, 2026-11-25). */
    if (o.zh) return (o.year === false ? '' : p.y + '年') + (p.mo + 1) + '月' + p.d + '日' +
      (o.named ? '（' + (o.short ? '周' + WD_ZH[p.wd].slice(2) : WD_ZH[p.wd]) + '）' : '');
    return (o.weekday ? WD[p.wd] + ', ' : '') + p.d + ' ' + (o.long ? LONG : MON)[p.mo] + (o.year === false ? '' : ' ' + p.y) +
      (o.named ? ' (' + (o.short ? WD : WDAY)[p.wd] + ')' : '');
  }
  /* A date and time the reader waits on (a deadline, an appointment, a page
     back by): the weekday in brackets after the date, then the time
     (2026-11-20, the user: "remember to show the day when necessary"). A
     history date never carries it. */
  function due(v, o) {
    o = o || {};
    if (moment(v) === null) return '';
    if (o.zh) return date(v, { zh: true, named: true }) + clock(v, { zh: true });
    return date(v, { named: true, long: o.long }) + ', ' + clock(v, { space: o.space });
  }
  function clock(v, o) {
    o = o || {};
    var p = parts(v);
    if (!p) return '';
    if (o.h24) return pad(p.h) + ':' + pad(p.mi);
    if (o.zh) return (p.h < 12 ? '上午' : '下午') + ((p.h % 12) || 12) + ':' + pad(p.mi) + (o.sec ? ':' + pad(p.s) : '');
    /* `sec` adds the seconds, for a signed document's record (10:42:15am). */
    return ((p.h % 12) || 12) + ':' + pad(p.mi) + (o.sec ? ':' + pad(p.s) : '') + (o.space ? ' ' : '') + (p.h < 12 ? 'am' : 'pm');
  }
  function month(v, o) {
    o = o || {};
    var p = partsOf(v);
    if (!p) return '';
    if (o.zh) return p.y + '年' + (p.mo + 1) + '月';
    return (o.long ? LONG : MON)[p.mo] + ' ' + p.y;
  }
  function weekday(d) { var k = split(d); return k ? new Date(Date.UTC(k.y, k.mo, k.d)).getUTCDay() : null; }

  window.ADspaceClock = {
    ZONE: ZONE, OFFSET: OFF, SUFFIX: SUFFIX, moment: moment, parts: parts, day: day, today: today, start: start,
    at: at, time: time, addDays: addDays, addMonths: addMonths, periodEnd: periodEnd, between: between, weekday: weekday,
    date: date, due: due, clock: clock, month: month, MON: MON, LONG: LONG, WDAY: WDAY
  };
})();
