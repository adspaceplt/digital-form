/* ADspace Digital Portal — a captcha on every emailed sign-in.

   Supabase Auth checks a Cloudflare Turnstile token on the calls that send a
   sign-in email once "Enable CAPTCHA protection" is switched on in the
   dashboard (Authentication, Attack Protection), with the Turnstile SECRET
   key kept there and never here. This page only needs the SITE key, which is
   public by design: `ADSPACE_CONFIG.turnstileSiteKey` in js/config.js.

   While that key is blank nothing loads, `token()` answers null and every
   sign-in works as it did. Set the key and switch the dashboard on together
   (docs/SIGN-IN-SECURITY.md): the dashboard on without the key refuses every
   sign-in, and the key without the dashboard is a widget nobody checks.

   The widget runs in "interaction-only" appearance, so it draws nothing unless
   Cloudflare wants somebody to press a box. A token is good for one call, so
   the widget is reset before each new one. */
(function () {
  'use strict';

  var cfg = window.ADSPACE_CONFIG || {};
  var KEY = String(cfg.turnstileSiteKey || '').trim();
  var loading = null;

  function load() {
    if (loading) return loading;
    loading = new Promise(function (ok, bad) {
      if (window.turnstile) { ok(); return; }
      var s = document.createElement('script');
      s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
      s.async = true; s.defer = true;
      s.onload = function () { ok(); };
      s.onerror = function () { loading = null; bad(new Error('captcha-unavailable')); };
      /* A script that neither loads nor fails (a network that swallows the
         request) must not hold the sign-in button: after eight seconds the
         email goes without a token, as it does when the script fails. */
      setTimeout(function () { if (!window.turnstile) { loading = null; bad(new Error('captcha-slow')); } }, 8000);
      document.head.appendChild(s);
    });
    return loading;
  }

  /* One widget per host element, kept for the life of the page. */
  function token(host) {
    if (!KEY || !host) return Promise.resolve(null);
    return load().then(function () {
      return new Promise(function (ok) {
        var done = false;
        var give = function (t) { if (!done) { done = true; ok(t || null); } };
        var ts = window.turnstile;
        if (host.__cfWidget == null) {
          host.__cfWidget = ts.render(host, {
            sitekey: KEY,
            execution: 'execute',
            appearance: 'interaction-only',
            size: 'flexible',
            callback: function (t) { if (host.__cfGive) host.__cfGive(t); },
            'error-callback': function () { if (host.__cfGive) host.__cfGive(null); },
            'expired-callback': function () { try { ts.reset(host.__cfWidget); } catch (e) {} }
          });
        } else {
          try { ts.reset(host.__cfWidget); } catch (e) {}
        }
        host.__cfGive = give;
        try { ts.execute(host.__cfWidget); } catch (e) { give(null); }
        /* A challenge nobody answers is not a reason to hang the button. */
        setTimeout(function () { give(null); }, 30000);
      });
    }, function () { return null; });
  }

  /* The widget's place: just after the button that asked for it, so a box
     Cloudflare wants pressed appears where the person is looking. */
  function hostFor(btn) {
    if (!KEY || !btn) return null;
    if (btn.__cfHost) return btn.__cfHost;
    var h = document.createElement('div');
    h.className = 'cfbox';
    btn.insertAdjacentElement('afterend', h);
    btn.__cfHost = h;
    return h;
  }

  /* The options Supabase's sign-in calls take, with the token where there is
     one. `btn` is the control that sends the email. */
  function withToken(btn, opts) {
    return token(hostFor(btn)).then(function (t) {
      var o = {};
      for (var k in opts) if (Object.prototype.hasOwnProperty.call(opts, k)) o[k] = opts[k];
      if (t) o.captchaToken = t;
      return o;
    });
  }

  window.ADspaceCaptcha = { on: Boolean(KEY), token: token, options: withToken };
})();
