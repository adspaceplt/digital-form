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

  function footerHtml() {
    var year = new Date().getFullYear();
    return '<footer class="portalfoot"><div class="portalfoot-in">' +
      '<span class="portalfoot-mark">ADspace</span>' +
      '<span class="portalfoot-note">Digital Portal · ' + year + '</span>' +
      '<span class="topbar-spacer"></span>' +
      '<a class="portalfoot-link" href="https://adspace.me" target="_blank" rel="noopener">adspace.me</a>' +
    '</div></footer>';
  }

  /* The mark, with the wordmark behind it. One copy of the fallback rather
     than the same four lines in every page script. */
  function paintLogo() {
    var logo = document.getElementById('agencyLogo');
    if (!logo) return;
    logo.onerror = function () {
      logo.hidden = true;
      var w = document.getElementById('agencyWordmark');
      if (w) w.hidden = false;
    };
    logo.src = cfg.brandLogo || '';
  }

  head();
  tag.insertAdjacentHTML('afterend', headerHtml());
  paintLogo();

  if (wantFooter) {
    var addFoot = function () {
      if (document.querySelector('.portalfoot')) return;
      document.body.insertAdjacentHTML('beforeend', footerHtml());
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', addFoot, { once: true });
    } else {
      addFoot();
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
      if (!logo) return;
      logo.onerror = function () {
        logo.hidden = true;
        var w = document.getElementById(wordmarkId);
        if (w) w.hidden = false;
      };
      logo.src = cfg.brandLogo || '';
    },
    actions: function () { return document.getElementById('chromeActions'); }
  };
})();
