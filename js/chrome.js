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
 *                 phone. A page needing something of its own puts it in
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
    var icon = cfg.brandIcon || 'https://mycdn.adspace.me/adspace-favicon.png';
    [['icon', icon], ['apple-touch-icon', icon]].forEach(function (pair) {
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
        '<path d="M14 14h3v3h-3zM19 14h2M14 19h3M19 19h2"/></svg>View on phone</button>'
  };

  function headerHtml() {
    return '<header class="topbar" id="topbar"><div class="topbar-inner">' +
      '<div class="brand">' +
        '<img id="agencyLogo" class="brand-logo" src="" alt="ADspace">' +
        '<span class="brand-wordmark" id="agencyWordmark" hidden>ADspace</span>' +
        '<span class="brand-divider"></span>' +
        '<span class="brand-meta">' +
          '<span class="brand-kicker" id="kicker">' + esc(kicker) + '</span>' +
          (forClient ? '<span class="brand-for" id="clientFor">Prepared for ' +
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
    var year = new Date().getFullYear();
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
      if (name) el.innerHTML = esc(label) + ' <b id="clientName">' + esc(name) + '</b>';
    },
    // Any mark on the page, wired to the same fallback.
    mark: function (logoId, wordmarkId) {
      var logo = document.getElementById(logoId);
      if (logo) wireMark(logo, wordmarkId, null);
    },
    actions: function () { return document.getElementById('chromeActions'); }
  };
})();
