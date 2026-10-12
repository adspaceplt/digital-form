/*
 * ADspace portal chrome.
 *
 * The top bar and the footer were written out by hand in every page, so the
 * ADspace mark, the divider, the kicker and the fallback behaviour when the
 * logo fails to load existed in three copies that had already drifted apart.
 * This is the single copy. A new page includes this script and says what
 * section it is; everything else comes from here.
 *
 * Include it as the FIRST thing inside <body>:
 *
 *   <script src="/js/chrome.js" data-kicker="Creator Selection" data-for data-actions="lang"></script>
 *
 * It writes the header where the tag sits, so nothing paints before the
 * header exists and there is no placeholder to forget. The footer is appended
 * once the page has loaded.
 *
 * Attributes on the tag:
 *   data-kicker   the section name shown beside the mark. Required.
 *   data-for      present when the page is prepared for one client: renders
 *                 "Prepared for <b id="clientName">…</b>" under the kicker.
 *   data-actions  a space separated list of built-in controls to put on the
 *                 right: "lang" for the language toggle, "qr" for view on
 *                 phone, "push" for the notifications bell (js/push.js).
 *                 A page needing something of its own puts it in
 *                 #chromeActions afterwards.
 *   data-footer   "off" to leave the footer out (the console draws its own).
 *
 * Ids kept deliberately stable, because page scripts reach for them:
 *   agencyLogo, agencyWordmark, kicker, clientFor, clientName,
 *   langToggle, qrBtn, chromeActions, topbar
 */
(function () {
  var tag = document.currentScript;
  if (!tag) return;

  var cfg = window.ADSPACE_CONFIG || {};
  var kicker = tag.getAttribute('data-kicker') || 'Digital Portal';
  var forClient = tag.hasAttribute('data-for');
  var actions = (tag.getAttribute('data-actions') || '').split(/\s+/).filter(Boolean);
  var wantFooter = tag.getAttribute('data-footer') !== 'off';

  /* A field under 16px makes iPhone Safari zoom the page when it takes
     focus, and it never zooms back. Since iOS 10 Safari ignores
     maximum-scale for a pinch, so on iOS alone the value stops the automatic
     zoom and leaves the reader's own zoom working: fields keep the portal's
     own sizes instead of a 16px floor. Android does not zoom on focus and its
     browsers honour maximum-scale for a pinch too, so it never gets it. */
  (function () {
    var ua = navigator.userAgent || '';
    var ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
    var vp = document.querySelector('meta[name="viewport"]');
    if (ios && vp && !/maximum-scale/.test(vp.content)) vp.content += ', maximum-scale=1';
  })();

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /* The head bits that cannot change the first paint, so it is safe to add
     them from here rather than repeat them in every page. The stylesheet is
     deliberately NOT one of them: it has to be in the markup or the page
     flashes unstyled. */
  function head() {
    /* The ADspace wordmark on white, from the site itself (2026-09-28: the
       wordmark, never the monogram, and no page's icon hangs on the CDN). */
    [['icon', cfg.brandIcon || '/img/favicon-192.png'], ['apple-touch-icon', cfg.brandIcon || '/img/apple-touch-icon.png']].forEach(function (pair) {
      if (document.querySelector('link[rel="' + pair[0] + '"]')) return;
      var l = document.createElement('link');
      l.rel = pair[0];
      l.href = pair[1];
      if (pair[0] === 'icon') l.type = 'image/png';
      document.head.appendChild(l);
    });
    if (!document.querySelector('meta[property="og:site_name"]')) {
      var m = document.createElement('meta');
      m.setAttribute('property', 'og:site_name');
      m.content = 'ADspace';
      document.head.appendChild(m);
    }
  }

  var BUILTIN = {
    lang: '<button class="langtoggle" id="langToggle" type="button">中文</button>',
    qr: '<button class="pill" id="qrBtn" type="button" hidden>' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">' +
        '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/>' +
        '<rect x="3" y="14" width="7" height="7" rx="1"/>' +
        '<path d="M14 14h3v3h-3zM19 14h2M14 19h3M19 19h2"/></svg>View on phone</button>',
    /* Notifications on this device. Hidden until js/push.js knows the page
       follows something and the browser can deliver; it names itself then. */
    push: '<button class="iconbtn pushbtn" id="pushBtn" type="button" hidden></button>'
  };

  function headerHtml() {
    return '<header class="topbar" id="topbar"><div class="topbar-inner">' +
      '<div class="brand">' +
        '<img id="agencyLogo" class="brand-logo" src="" alt="ADspace">' +
        '<span class="brand-wordmark" id="agencyWordmark" hidden>ADspace</span>' +
        '<span class="brand-divider"></span>' +
        '<span class="brand-meta">' +
          '<span class="brand-kicker" id="kicker">' + esc(kicker) + '</span>' +
          (forClient ? '<span class="brand-for" id="clientFor"><span class="brand-for-label">Prepared for</span> ' +
            '<b id="clientName">…</b></span>' : '') +
        '</span>' +
      '</div>' +
      '<span class="topbar-spacer"></span>' +
      '<span class="chrome-actions" id="chromeActions">' +
        actions.map(function (a) { return BUILTIN[a] || ''; }).join('') +
      '</span>' +
    '</div></header>';
  }

  /* Two things, one at each end. The year comes from the clock so nobody has
     to remember to change it in January. */
  function footerHtml() {
    var year = window.ADspaceClock ? ADspaceClock.today().slice(0, 4) : new Date().getFullYear();
    return '<footer class="portalfoot"><div class="portalfoot-in">' +
      '<span class="portalfoot-copy">\u00a9 ' + year +
        ' ADSPACE PLT. All Rights Reserved.</span>' +
      '<a class="portalfoot-link" href="https://adspacestudios.com/legal/policies" ' +
        'target="_blank" rel="noopener">Terms of Service</a>' +
    '</div></footer>';
  }

  /* The mark, with the wordmark behind it. One copy of the fallback rather
     than the same four lines in every page script.
     The mark comes from the CDN and lands after the first paint, and an image
     with no file yet has no width: the page label beside it stood at the
     mark's left edge and jumped 208px right when the file arrived. So the
     mark's proportions are kept from the last visit and the box is drawn at
     that size from the first paint (`aspect-ratio: auto R`, which the file's
     own ratio replaces once it loads). On a first visit, with nothing kept,
     `holder` is held back until the mark has loaded or failed, so the brand
     arrives once, in place, instead of moving. */
  var RATIO_KEY = 'adspace-logo-ratio';
  function wireMark(logo, wordmarkId, holder) {
    var ratio = 0;
    try { ratio = parseFloat(localStorage.getItem(RATIO_KEY)) || 0; } catch (e) {}
    if (ratio > 0) logo.style.aspectRatio = 'auto ' + ratio;
    else if (holder) holder.classList.add('is-waiting');
    var settle = function () { if (holder) holder.classList.remove('is-waiting'); };
    var timer = setTimeout(settle, 2500);
    logo.onload = function () {
      clearTimeout(timer);
      if (logo.naturalWidth && logo.naturalHeight) {
        var r = Math.round(logo.naturalWidth / logo.naturalHeight * 1000) / 1000;
        logo.style.aspectRatio = 'auto ' + r;
        try { localStorage.setItem(RATIO_KEY, String(r)); } catch (e) {}
      }
      settle();
    };
    logo.onerror = function () {
      clearTimeout(timer);
      logo.hidden = true;
      var w = document.getElementById(wordmarkId);
      if (w) w.hidden = false;
      settle();
    };
    logo.src = cfg.brandLogo || '';
  }

  function paintLogo() {
    var logo = document.getElementById('agencyLogo');
    if (logo) wireMark(logo, 'agencyWordmark', logo.parentNode);
  }

  head();
  tag.insertAdjacentHTML('afterend', headerHtml());
  paintLogo();

  /* The footer is drawn with the header, not when the page has finished
     parsing. Added at the end, it arrived after the page had already shown
     what was under the bar, and on the sign-in page the card, centred in the
     space between the bar and the floor, moved 26px up when the floor
     rose. The body is a flex column, so `.portalfoot` (order 1) sits last on
     the screen wherever it is in the markup; once the page is parsed it is
     moved to the end of the body as well, so a keyboard and a screen reader
     reach it last too. */
  if (wantFooter && !document.querySelector('.portalfoot')) {
    document.getElementById('topbar').insertAdjacentHTML('afterend', footerHtml());
    var sinkFoot = function () {
      var f = document.querySelector('.portalfoot');
      if (f && f !== document.body.lastElementChild) document.body.appendChild(f);
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', sinkFoot, { once: true });
    } else {
      sinkFoot();
    }
  }

  /* Malaysia's clock (2026-10-12; the user: "this entire portal should
     follow the timezone of malaysia … push a fixed top bar … timezone
     difference detected"). A device whose clock is not GMT+8 (Malaysia and
     Singapore share it) is told so on every page, under its bar: the
     console's in its column, a client page's edge to edge under the top
     bar. In English or Chinese as the page reads, following the 中文
     switch; its close hides it for this visit alone. */
  var TZ_HIDE = 'adspace-tz-hide';
  function tzWords(zh, gmt, zone) {
    return zh
      ? '检测到时区差异：此设备使用 ' + gmt + (zone ? '（' + zone + '）' : '') + '。本门户以马来西亚时间（GMT+8）为准。'
      : 'Time zone difference detected: this device is on ' + gmt + (zone ? ' (' + zone + ')' : '') + '. The portal follows Malaysia time (GMT+8).';
  }
  function tzBar() {
    var off = -new Date().getTimezoneOffset();
    if (off === 480 || document.getElementById('tzBar')) return;
    /* An automated browser (the test suites, which run on UTC) is not a
       person to tell; tests/tzbar.js asks for the bar with window.__tzBar. */
    if (navigator.webdriver && !window.__tzBar) return;
    try { if (sessionStorage.getItem(TZ_HIDE) === '1') return; } catch (e) { /* shown */ }
    var zone = '';
    try { zone = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (e) { zone = ''; }
    var a = Math.abs(off), hh = Math.floor(a / 60), mm = a % 60;
    var gmt = 'GMT' + (off < 0 ? '\u2212' : '+') + hh + (mm ? ':' + (mm < 10 ? '0' : '') + mm : '');
    var bar = document.createElement('div');
    bar.className = 'tzbar'; bar.id = 'tzBar'; bar.setAttribute('role', 'status');
    var zh = function () { return /^zh/i.test(document.documentElement.lang || ''); };
    var paint = function () {
      bar.innerHTML = '<p class="tzbar-text">' + esc(tzWords(zh(), gmt, zone)) + '</p>' +
        '<button class="iconbtn tzbar-x" type="button" aria-label="' + (zh() ? '关闭' : 'Dismiss') + '">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>';
      bar.querySelector('.tzbar-x').addEventListener('click', function () {
        try { sessionStorage.setItem(TZ_HIDE, '1'); } catch (e) { /* closes for now only */ }
        if (bar.parentNode) bar.parentNode.removeChild(bar);
      });
    };
    paint();
    if (window.MutationObserver) new MutationObserver(paint).observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] });
    var up = document.getElementById('upgradeBar'), top = document.getElementById('topbar');
    if (up && up.parentNode) up.parentNode.insertBefore(bar, up);
    else if (top && top.parentNode) top.parentNode.insertBefore(bar, top.nextSibling);
    else if (document.body) document.body.insertBefore(bar, document.body.firstChild);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', tzBar, { once: true });
  else tzBar();

  /* Pages that build their own chrome (the signed-in console) still want the
     mark handled the same way, so the helper is shared rather than copied. */
  window.ADspaceChrome = {
    kicker: function (text) {
      var el = document.getElementById('kicker');
      if (el) el.textContent = text;
    },
    preparedFor: function (label, name) {
      var el = document.getElementById('clientFor');
      if (!el) return;
      el.hidden = !name;
      if (name) el.innerHTML = '<span class="brand-for-label">' + esc(label) + '</span> <b id="clientName">' + esc(name) + '</b>';
    },
    // Any mark on the page, wired to the same fallback.
    mark: function (logoId, wordmarkId) {
      var logo = document.getElementById(logoId);
      if (logo) wireMark(logo, wordmarkId, null);
    },
    actions: function () { return document.getElementById('chromeActions'); }
  };
})();
