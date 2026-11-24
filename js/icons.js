/* ADspace Digital Portal · one icon set, and the booking's step track (the user, 2026-10-07: the client
   pages read plain; the proposal's set, outline glyphs at the portal's own
   15px and 1.8 stroke, in ink). One glyph, one meaning, on every page:
   ADspaceIcons.svg(name, cls) answers the markup, and a name it does not
   hold answers nothing. Never filled, never coloured; the play mark on a
   video is the one solid shape, drawn by the page that plays it. */
(function () {
  'use strict';
  var P = {
    eye: '<path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0"/><circle cx="12" cy="12" r="3"/>',
    layers: '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    heart: '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
    percent: '<path d="M19 5 5 19"/><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>',
    tag: '<path d="M12.59 2.59A2 2 0 0 0 11.17 2H4a2 2 0 0 0-2 2v7.17a2 2 0 0 0 .59 1.42l8.7 8.7a2.43 2.43 0 0 0 3.42 0l6.58-6.58a2.43 2.43 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".6"/>',
    users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    camera: '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/>',
    box: '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5M12 22V12"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    calplus: '<path d="M8 2v4M16 2v4M21 13V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h8M3 10h18M16 19h6M19 16v6"/>',
    clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    pin: '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
    phone: '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>',
    megaphone: '<path d="m3 11 18-5v12L3 14v-3z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/>',
    upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m17 8-5-5-5 5"/><path d="M12 3v12"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.09-3.09a2 2 0 0 0-2.82 0L6 21"/>',
    video: '<path d="m16 13 5.22 3.48a.5.5 0 0 0 .78-.42V7.87a.5.5 0 0 0-.75-.43L16 10.5"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    hourglass: '<path d="M5 22h14M5 2h14M17 22v-4.17a2 2 0 0 0-.59-1.42L12 12l-4.41 4.41A2 2 0 0 0 7 17.83V22M7 2v4.17a2 2 0 0 0 .59 1.42L12 12l4.41-4.41A2 2 0 0 0 17 6.17V2"/>',
    chat: '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
    mail: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
    note: '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4M10 9H8M16 13H8M16 17H8"/>',
    rednote: '<path d="M12 7v14"/><path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/>',
    instagram: '<rect x="2" y="2" width="20" height="20" rx="5"/><circle cx="12" cy="12" r="4"/><path d="M17.5 6.5h.01"/>',
    tiktok: '<path d="M9 12a4 4 0 1 0 4 4V2a5 5 0 0 0 5 5"/>',
    facebook: '<path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/>',
    /* The leaving mark, after the words of anything that opens in a new tab,
       drawn as the console's act table draws it (js/acts.js `out`); and the
       chevron, after a way to another page. One drawing each (CR-7). */
    out: '<path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
    chevron: '<path d="m9 18 6-6-6-6"/>',
    /* Download: the file with its arrow, as the console's act table draws
       it (js/acts.js `file`; 2026-11-19, the careers page's Download). */
    file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M12 12v6M9 15l3 3 3-3"/>',
    /* A full-page notice's mark, one a state (the cover family, 2026-11-22):
       drawn in the locks' disc (.lockcard-mark) above the title. */
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
    linkoff: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/><path d="m4 4 16 16"/>',
    tool: '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L4 17v3h3l5.3-5.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4z"/>',
    pause: '<circle cx="12" cy="12" r="9"/><path d="M10 9v6M14 9v6"/>',
    block: '<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>',
    alert: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5"/><path d="M12 16.5h.01"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18"/>',
    wifioff: '<path d="M2 8.8A15 15 0 0 1 6.3 6"/><path d="M10.7 5.1A15 15 0 0 1 22 8.8"/><path d="M5 12.5a10 10 0 0 1 4-2.2"/><path d="M15.5 10.8A10 10 0 0 1 19 12.5"/><path d="M8.5 16a5 5 0 0 1 7 0"/><path d="M12 19.5h.01"/><path d="m3 3 18 18"/>',
    building: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M9 7h1M14 7h1M9 11h1M14 11h1M9 15h1M14 15h1"/><path d="M10 21v-3h4v3"/>',
    done: '<circle cx="12" cy="12" r="9"/><path d="m8 12.5 2.7 2.7L16 9.5"/>',
    archive: '<rect x="3" y="4" width="18" height="5" rx="1.5"/><path d="M5 9v9a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9"/><path d="M10 13h4"/>',
    inbox: '<path d="M3 13h5l1.5 3h5l1.5-3h5"/><path d="M5.5 5h13L21 13v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-5z"/>',
    film: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
    userx: '<circle cx="10" cy="8" r="4"/><path d="M3 21a7 7 0 0 1 11-5.7"/><path d="m17 15 4 4M21 15l-4 4"/>',
    shield: '<path d="M12 3 5 6v5c0 4.5 3 8.3 7 10 4-1.7 7-5.5 7-10V6z"/><path d="m9 12 2 2 4-4"/>',
    docq: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M10.2 12.2a1.9 1.9 0 1 1 2.6 1.8c-.5.2-.8.6-.8 1.1v.4"/><path d="M12 18h.01"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="M10.8 12.2 20 3"/><path d="m16 7 3 3"/><path d="m14 9 2 2"/>',
    /* A quotation plan's mark and the facts under its name (/quote/, the
       boards QuotePhone and QuoteDesk, 2026-11-25): a content plan, a plan
       with advertising (a rising chart in a square), content pieces, a
       platform, an advertising budget. */
    plancontent: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><path d="M15.5 15l4 2.5-4 2.5z"/>',
    planads: '<rect x="3" y="3" width="18" height="18" rx="3"/><path d="M7 15.5l3.5-3.5 2.5 2.5L17 10"/><path d="M14 10h3v3"/>',
    pieces: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    device: '<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M10.5 18.5h3"/>',
    bars: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>'
  };
  /* A platform's glyph by the words the pages hold for it. */
  var PLAT = { rednote: 'rednote', xhs: 'rednote', xiaohongshu: 'rednote', instagram: 'instagram', ig: 'instagram',
    tiktok: 'tiktok', facebook: 'facebook', fb: 'facebook' };
  function svg(name, cls) {
    var p = P[name];
    if (!p) return '';
    return '<svg class="ic' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + p + '</svg>';
  }
  function platform(key) {
    var k = String(key || '').toLowerCase().replace(/[^a-z]/g, '');
    return svg(PLAT[k] || '');
  }
  /* A booking's steps as one track, drawn alike on the client's page and
     the creator's own: a hairline a step with its name under it, the done
     ones in ink, the one in hand amber (css .cx-journey). Bars with no
     names were refused (the user, 2026-10-08: "how would people
     understand the stage name"), and so were large ringed marks ("Do you
     think Apple would put such huge stage status"). `at` is the step in
     hand; past the last, all are done. */
  function journey(words, at) {
    var esc = window.ADspaceWords.esc;
    return '<ol class="cx-journey">' + words.map(function (w, i) {
      var cls = i < at ? 'is-done' : i === at ? 'is-now' : '';
      return '<li' + (cls ? ' class="' + cls + '"' : '') + (i === at ? ' aria-current="step"' : '') + '><span>' + esc(w) + '</span></li>';
    }).join('') + '</ol>';
  }
  /* Where a booking stands on the client's six steps, one map for the
     client's page and the console's Creators tab (2026-10-08): the client's
     review begins at Reviewing, so a draft still with the team (Submitted)
     is the Draft step. Null for a creator not yet booked. The creator's own
     page keeps its own map: to a creator, a draft handed in is in review. */
  var CLIENT_AT = { confirmed: 1, pending_visit: 1, pending_draft: 2, changes: 2, submitted: 2, reviewing: 3,
                    scheduled: 4, posted: 5, completed: 6 };
  function stepOf(state) { var at = CLIENT_AT[state]; return at == null ? null : at; }
  /* A platform's own mark, single colour in ink (the user, 2026-11-24: no
     brand colour fills), where a prospect chooses platforms (/quote/): the
     mark in currentColor, what is cut out of it in the card's ground
     (`.ic-cut`). Meta is Facebook and Instagram together, one platform on
     the Rate Card. */
  var MARK = {
    facebook: '<circle cx="12" cy="12" r="11" fill="currentColor"/><path class="ic-cut" d="M13.4 23v-8.3h2.8l.4-3.3h-3.2V9.3c0-.9.3-1.6 1.6-1.6h1.7V4.8c-.3 0-1.3-.1-2.5-.1-2.5 0-4.2 1.5-4.2 4.3v2.4H7.2v3.3H10V23z"/>',
    instagram: '<rect x="2.5" y="2.5" width="19" height="19" rx="5.5" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="12" r="4.3" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="17.6" cy="6.4" r="1.2" fill="currentColor"/>',
    tiktok: '<path fill="currentColor" d="M16.6 2h-3.4v13.4a2.9 2.9 0 1 1-2.9-2.9c.3 0 .6 0 .9.1V9.1a6.3 6.3 0 1 0 5.4 6.3V8.6a8 8 0 0 0 4.6 1.5V6.7a4.7 4.7 0 0 1-4.6-4.7z"/>',
    rednote: '<rect x="1" y="1" width="22" height="22" rx="6" fill="currentColor"/><text class="ic-cut" x="12" y="14.6" font-family="PingFang SC, Microsoft YaHei, sans-serif" font-size="6.4" font-weight="700" text-anchor="middle">小红书</text>',
    linkedin: '<rect x="1" y="1" width="22" height="22" rx="4" fill="currentColor"/><path class="ic-cut" d="M5.5 9.5h2.8V18H5.5zM6.9 5.3a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2zM10 9.5h2.7v1.2c.4-.7 1.3-1.4 2.7-1.4 2.9 0 3.4 1.9 3.4 4.3V18H16v-3.9c0-.9 0-2.2-1.3-2.2s-1.6 1-1.6 2.1v4H10z"/>'
  };
  var MARKS_OF = { meta: ['facebook', 'instagram'], facebook: ['facebook'], instagram: ['instagram'], tiktok: ['tiktok'],
    rednote: ['rednote'], xhs: ['rednote'], linkedin: ['linkedin'] };
  function mark(key) {
    var k = String(key || '').toLowerCase().replace(/[^a-z]/g, '');
    return (MARKS_OF[k] || []).map(function (m) {
      return '<svg class="ic-mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">' + MARK[m] + '</svg>';
    }).join('');
  }
  window.ADspaceIcons = { svg: svg, platform: platform, mark: mark, journey: journey, stepOf: stepOf, has: function (n) { return !!P[n]; } };
})();
