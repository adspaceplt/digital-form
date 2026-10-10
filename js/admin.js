/*
 * Team admin. Built for people who are not technical:
 * drop files, we work out the placement, you write the caption, you send the link.
 */
(function () {
  var cfg = window.ADSPACE_CONFIG;
  var API = window.ADspaceAPI;
  var MK  = window.ADspaceMockups;
  var db  = API.client;
  var $   = function (id) { return document.getElementById(id); };

  /* The signed out bar is the shared chrome's, which handles its own mark.
     The console rail is this page's, so it asks the chrome to wire that one
     the same way rather than repeating the fallback here. */
  if (window.ADspaceChrome) window.ADspaceChrome.mark('sideLogo', 'sideWordmark');
  /* Installable, and a lost connection answered with a page that says so.
     The worker caches nothing else (see /admin/sw.js), so a release still
     reaches everybody on their next load. */
  try {
    if ('serviceWorker' in navigator && location.protocol !== 'file:') {
      window.addEventListener('load', function () {
        navigator.serviceWorker.register('/admin/sw.js', { scope: '/admin/' }).catch(function () {});
      });
    }
  } catch (e) {}
  if (!API.configured || !db) { $('notConfigured').hidden = false; return; }

  /* One dropdown in plain language beats two dropdowns of jargon. */
  var PLACEMENTS = [
    ['instagram:feed',     'Instagram feed post'],
    ['instagram:carousel', 'Instagram carousel'],
    ['instagram:reel',     'Instagram Reels'],
    ['instagram:story',    'Instagram Story'],
    ['facebook:feed',      'Facebook post'],
    ['facebook:multi',     'Facebook multi-photo post'],
    ['facebook:carousel',  'Facebook carousel ad'],
    ['facebook:reel',      'Facebook Reels'],
    ['facebook:story',     'Facebook Story'],
    ['tiktok:reel',        'TikTok video'],
    ['xhs:note',           'rednote post'],
    ['cover:image',        'Cover image']
  ];

  var state = { client: null, batch: null, drafts: [], lastDropCount: 0, uploading: false,
               storageCheck: null, pendingBy: {}, xhrs: [], cancelled: false };

  /* A picked file stays in the browser until Add to set, so closing the tab
     with one waiting, or mid upload, is warned about; switching tabs is not. */
  window.addEventListener('beforeunload', function (e) {
    if (!state.uploading && !hasLocal()) return;
    e.preventDefault();
    e.returnValue = '';
  });

  function msg(id, text, kind) {
    var n = $(id); n.textContent = text || ''; n.className = 'msg' + (kind ? ' ' + kind : '');
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
  function reviewUrl(c) { return location.origin + '/review/?k=' + c.access_token; }

  /* Records the handful of actions that destroy data or change what a client
     can see. Deliberately fire and forget: a failure to log must never stop
     the action itself, and this is not a click tracker. */
  var actor = '';
  function logAction(action, subject, detail) {
    db.from('activity_log').insert({
      actor: actor || 'unknown',
      action: action,
      subject: subject || null,
      detail: detail || null
    }).then(function () {}, function () {});
  }

  /* The activity record stores who by the address they signed in with, which
     is the stable identity: two colleagues can share a display name, nobody
     shares a login, and the nine security definer functions that write the log
     have `auth.jwt() ->> 'email'` and nothing else to hand.

     A person reading the record wants the person, so the address is resolved
     to a name here rather than stored as one. That way every entry ever
     written reads as a name from the moment this ships, with no migration and
     no audit row rewritten, and somebody who changes their name is recognised
     in their old entries too.

     Stood down colleagues are included deliberately: they still wrote what
     they wrote. An address with no team row at all — a legacy entry, a
     colleague whose row was deleted, `unknown` — keeps the address, because
     the point is to say who and not to hide that we cannot. */
  var whoBy = null;
  function loadWho(then) {
    db.from('team_members').select('email, name').then(function (r) {
      var by = {};
      (r.data || []).forEach(function (t) {
        var e = String(t.email || '').trim().toLowerCase();
        if (e && t.name) by[e] = t.name;
      });
      whoBy = by;
      if (then) then();
    }, function () { whoBy = whoBy || {}; if (then) then(); });
  }
  /* Never throws and never blanks a row: a failed read leaves every entry
     reading exactly as it does today. */
  function whoName(email) {
    var e = String(email == null ? '' : email).trim();
    if (!e || !whoBy) return e;
    return whoBy[e.toLowerCase()] || e;
  }

  function thisMonth() {
    return new Date().toLocaleDateString('en-GB', { month: 'long', year: 'numeric' }) + ' Content';
  }

  // ---- Auth ---------------------------------------------------------------
  /* The email carries a link and a code. The link signs in where it is
     opened; the code signs in here, which is what the installed app needs,
     since it cannot take a link from the mail app into its own window. */
  var authEmailSent = '';
  function authStep(code) {
    $('authEmailStep').hidden = code;
    $('authCodeStep').hidden = !code;
    if (code) { $('authCode').value = ''; $('authCode').focus(); }
    else $('authEmail').focus();
  }
  $('authSend').addEventListener('click', function () {
    var email = $('authEmail').value.trim();
    if (!email) return;
    var b = $('authSend');
    b.disabled = true;
    // A fixed URL, not location.href, so it matches the Supabase allow list exactly.
    // Supabase silently falls back to its Site URL for anything not on that list.
    /* The console never makes an account (a colleague is added on the Team
       page), and it never says whether an address has one (the brief of
       2026-09-26): an unknown address moves to the code step like any other,
       so the page cannot be used to learn who is on the team. Only a fault
       worth trying again says so, in our words. */
    var opts = { shouldCreateUser: false, emailRedirectTo: location.origin + '/admin/' };
    var go = window.ADspaceCaptcha ? window.ADspaceCaptcha.options(b, opts) : Promise.resolve(opts);
    go.then(function (o) { return db.auth.signInWithOtp({ email: email, options: o }); }).then(function (r) {
      b.disabled = false;
      var m = String((r.error && r.error.message) || '');
      if (r.error && /seconds|rate limit|too many/i.test(m)) { msg('authMsg', 'Please wait a minute before asking for another code.', 'err'); return; }
      if (r.error && !/signup|sign up|not allowed|not found|no user|invalid/i.test(m)) { msg('authMsg', 'Not sent. Please try again.', 'err'); return; }
      authEmailSent = email;
      $('authSent').textContent = 'If ' + email + ' is registered, a code and a sign-in link have been sent to it. Enter the code, or open the link.';
      msg('authMsg', '');
      authStep(true);
    }, function () { b.disabled = false; msg('authMsg', 'Not sent. Please try again.', 'err'); });
  });
  $('authEmail').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') $('authSend').click();
  });
  function authVerify() {
    var code = String($('authCode').value || '').replace(/\D/g, '');
    if (code.length < 6) { msg('authMsg', 'Enter the code from the email.', 'err'); $('authCode').focus(); return; }
    var b = $('authVerify');
    b.disabled = true;
    db.auth.verifyOtp({ email: authEmailSent, token: code, type: 'email' }).then(function (r) {
      b.disabled = false;
      var m = String((r && r.error && r.error.message) || '');
      if (r && r.error && /rate limit|too many/i.test(m)) { msg('authMsg', 'Too many tries. Please wait a few minutes, then send a new code.', 'err'); return; }
      if (r && r.error) { msg('authMsg', 'That code is wrong or has expired. Send a new one.', 'err'); return; }
      msg('authMsg', '');
    }, function () { b.disabled = false; msg('authMsg', 'Not signed in. Please try again.', 'err'); });
  }
  $('authVerify').addEventListener('click', authVerify);
  $('authCode').addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); authVerify(); }
  });
  $('authBack').addEventListener('click', function () { msg('authMsg', ''); authStep(false); });

  /* Dark is the console's and this browser's. It starts from the device,
     because a tool the team sits in all day should arrive in the register
     their machine is already in, and a choice made here wins over it for
     ever. The client pages are untouched: they carry no dark at all, which is
     the half of that rule that was ever about a client deciding something in
     a register nobody chose. The head script has already applied the answer
     before first paint; this flips it and writes the choice down. */
  var sysDark = window.matchMedia
    ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function stored() {
    try { return localStorage.getItem('adspace-theme'); } catch (e) { return null; }
  }
  /* The theme is the account menu's Theme (2026-10-10, the user: "enhance
     the light or dark mode"): Auto follows the device, Light and Dark are
     kept in this browser. It was a two-way switch in the bar, where Auto was
     reached only by pressing back to what the device already showed. */
  function themeChoice() {
    var t = stored();
    return t === 'dark' || t === 'light' ? t : 'auto';
  }
  function paintTheme() {
    var pick = $('themePick');
    if (pick && pick.value !== themeChoice()) pick.value = themeChoice();
  }
  function wearTheme(dark) {
    if (dark) document.documentElement.setAttribute('data-theme', 'dark');
    else document.documentElement.removeAttribute('data-theme');
    /* The status bar follows the console's register, not the device's. */
    Array.prototype.forEach.call(document.querySelectorAll('meta[name="theme-color"]'), function (m) {
      m.removeAttribute('media');
      m.setAttribute('content', dark ? '#171717' : '#ffffff');
    });
    paintTheme();
  }
  if ($('themePick')) $('themePick').addEventListener('change', function () {
    var v = this.value;
    try {
      if (v === 'auto') localStorage.removeItem('adspace-theme');
      else localStorage.setItem('adspace-theme', v);
    } catch (e) {}
    wearTheme(v === 'dark' || (v === 'auto' && Boolean(sysDark && sysDark.matches)));
  });
  /* The device changing carries the console with it, but only while nobody
     has chosen: a stored answer is a decision and is not overruled by dusk. */
  if (sysDark) {
    var follow = function (e) { if (!stored()) wearTheme(e.matches); };
    if (sysDark.addEventListener) sysDark.addEventListener('change', follow);
    else if (sysDark.addListener) sysDark.addListener(follow);
  }
  paintTheme();

  /* The account control. Who you are, the register you read in and the way
     out are three things touched a few times a year, so they sit behind one
     control at the end of the bar rather than in a block at the foot of the
     sidebar that every screen had to carry. */
  /* The name where we hold one, the address until we do, and the initial for
     the phone, which has the section's name to protect and no room for both. */
  function paintAcct(who) {
    var name = (me && me.name) || '';
    var word = name || String(who || '').split('@')[0] || '';
    var nm = $('acctName'), mk = $('acctMark');
    if (nm) nm.textContent = word;
    if (mk) mk.textContent = (word || '?').charAt(0).toUpperCase();
    var btn = $('acctBtn');
    if (btn) btn.setAttribute('aria-label', word ? 'Account, ' + word : 'Account');
    // The menu's head names you over the address you sign in with.
    var hn = $('acctWhoName');
    if (hn) { hn.textContent = name; hn.hidden = !name; }
  }

  /* At a desk the menu hangs from the control; on a phone it docks at the
     foot of the screen, where the thumb is, as every card a bar control opens
     does (ADspaceMenu.pop). Docked, it is laid from the page itself, so it is
     put back under its control when it shuts. */
  var acctPhone = window.matchMedia ? window.matchMedia('(max-width: 640px)') : null;
  function shutAcct() {
    var menu = $('acctMenu');
    menu.hidden = true;
    $('acctBtn').setAttribute('aria-expanded', 'false');
    if (menu.parentNode !== $('acctWrap')) {
      menu.classList.remove('popcard', 'is-dock', 'is-up');
      $('acctWrap').appendChild(menu);
    }
  }
  $('acctBtn').addEventListener('click', function (e) {
    e.stopPropagation();
    var menu = $('acctMenu'), open = menu.hidden;
    if (!open) { shutAcct(); return; }
    menu.hidden = false;
    this.setAttribute('aria-expanded', 'true');
    if (acctPhone && acctPhone.matches && window.ADspaceMenu) window.ADspaceMenu.pop(this, menu, 'right');
    /* The theme's segment was laid while the menu was hidden. */
    var seg = $('themePick') && $('themePick').__seg;
    if (seg && window.ADspaceForm && window.ADspaceForm.thumb) window.ADspaceForm.thumb(seg);
    menu.querySelector('button.kmenu-item:not([hidden])').focus();
  });
  /* Settings, Arrange sections and the Activity record open from the menu,
     which shuts behind them. */
  ['settingsOpen', 'railEdit'].forEach(function (id) {
    if ($(id)) $(id).addEventListener('click', function () { shutAcct(); });
  });
  if ($('acctClose')) $('acctClose').addEventListener('click', function () { shutAcct(); $('acctBtn').focus(); });
  // Crossing the phone line with the menu open shuts it rather than leave it laid for the other.
  if (acctPhone && acctPhone.addEventListener) acctPhone.addEventListener('change', function () {
    if (!$('acctMenu').hidden) shutAcct();
  });
  document.addEventListener('click', function (e) {
    if (!$('acctMenu').hidden && !e.target.closest('#acctWrap') && !e.target.closest('#acctMenu')) shutAcct();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('acctMenu').hidden) { shutAcct(); $('acctBtn').focus(); }
  });

  /* My records is the person's own record, so it opens from who they are rather
     than from the rail everybody shares. */
  $('myPerf').addEventListener('click', function () {
    shutAcct();
    showSection('mine');
  });
  /* The person's digital namecard (js/namecard.js). */
  $('myCard').addEventListener('click', function () {
    shutAcct();
    if (window.ADspaceCard) window.ADspaceCard.openMine($('acctBtn'));
  });
  /* Passkeys are the person's own way in, drawn only where this browser can
     use one (js/passkey.js decides). */
  if (window.ADspacePasskey && window.ADspacePasskey.on && $('acctPasskeys')) {
    $('acctPasskeys').hidden = false;
    $('acctPasskeys').addEventListener('click', function () {
      shutAcct();
      window.ADspacePasskey.open($('acctBtn'));
    });
  }
  /* Notifications on this device, for the signed-in colleague's bell. The
     item is a switch with its state at the right edge, and the menu stays
     open while it works, so the new state is the answer. Where the device
     cannot, it says why. */
  var PUSH_WHY = {
    install: 'On iPhone, add the console to the Home Screen, then turn notifications on from there.',
    blocked: 'Notifications are blocked for this site in the browser settings.',
    failed: 'Notifications could not be turned on. Try again.'
  };
  var pushOn = false;
  function paintPush(s) {
    var P = window.ADspacePush;
    if (!P || !$('acctPush')) return;
    pushOn = !!(s && s.on);
    $('acctPush').hidden = !s || s.why === 'none' || s.why === 'nokey';
    $('acctPushWord').textContent = pushOn ? 'On' : 'Off';
    $('acctPush').setAttribute('aria-checked', String(pushOn));
  }
  function pushSay(text) {
    $('acctPushMsg').textContent = text || '';
    $('acctPushMsg').className = 'msg acct-msg' + (text ? ' warn' : '');
    $('acctPushMsg').hidden = !text;
  }
  function followBell() {
    var P = window.ADspacePush;
    if (!P || !me) return;
    P.setup({ audience: 'team', sw: '/admin/sw.js', scope: '/admin/' }).then(function () {
      return P.state();
    }).then(paintPush).catch(function () {});
  }
  if ($('acctPush')) $('acctPush').addEventListener('click', function (e) {
    e.stopPropagation();
    var P = window.ADspacePush;
    if (!P) return;
    var why = P.why();
    if (why === 'install' || why === 'blocked') { pushSay(PUSH_WHY[why]); return; }
    var btn = $('acctPush');
    btn.disabled = true;
    pushSay('');
    (pushOn ? P.off(false) : P.on(false)).then(function (r) {
      btn.disabled = false;
      if (r && r.ok) { paintPush({ on: !pushOn, why: '' }); btn.focus(); return; }
      var err = r && r.error;
      if (err === 'dismissed') return;
      pushSay(PUSH_WHY[err] || PUSH_WHY.failed);
    });
  });
  $('refreshApp').addEventListener('click', function () {
    shutAcct();
    if (window.ADspaceRefresh) window.ADspaceRefresh.hard(); else location.reload();
  });

  /* ===== Upgrade mode (js/maintenance.js, 2026-10-03). An admin switches
     every portal page to one cover, Upgrading in progress, now or from a set
     moment in Malaysia time, until switched off or an end set with it
     passes. The admin keeps working under a banner; anybody else signed in
     here meets the cover, with a way to sign out. Turning it off never
     asks: it is the way back. */
  var upgrade = { on: false, set: false };
  var upgradeTimer = null;
  function isAdminMe() { return Boolean(me && (me.is_admin || me.role === 'admin')); }
  /* A refusal is said where it can be read: under the switch while the
     account menu is open, else on the banner's line. */
  function upgradeSay(text) {
    /* Said on the Settings page, where the switch is (2026-10-10), and on
       the upgrade bar anywhere else. */
    if (window.ADspaceSettings) window.ADspaceSettings.say(text || '', text ? 'err' : '');
    var bar = $('upgradeBar');
    if (!text) { bar.classList.remove('is-err'); return; }
    if (section === 'settings') return;
    bar.hidden = false;
    bar.classList.add('is-err');
    $('upgradeWord').textContent = text;
    $('upgradeOff').hidden = true;
  }
  function paintUpgrade(d) {
    var M = window.ADspaceMaintenance;
    upgrade = d || { on: false, set: false };
    var admin = may('team.upgrade', 'work');
    /* Upgrade mode, Announcements, Notices and WhatsApp's templates are on
       the Settings page (2026-10-10), which repaints its switch from here. */
    if (section === 'settings' && window.ADspaceSettings) window.ADspaceSettings.paint();
    var bar = $('upgradeBar');
    if (bar) {
      bar.classList.remove('is-err');
      $('upgradeOff').hidden = false;
      bar.hidden = !(admin && upgrade.set);
      var w = !M ? '' : upgrade.on
        ? 'Upgrade mode is on' + (upgrade.ends_at ? ' until ' + M.when(upgrade.ends_at) : '') + '. Everyone but admins sees the upgrade screen.'
        : 'Upgrade mode starts ' + M.when(upgrade.starts_at) + (upgrade.ends_at ? ' and ends ' + M.when(upgrade.ends_at) : '') + '.';
      $('upgradeWord').textContent = w;
    }
    if (M && upgrade.on && !admin && me) {
      M.cover({ note: upgrade.note, ends_at: upgrade.ends_at, out: function () { $('signOut').click(); } });
    } else if (document.getElementById('maintCover') && !upgrade.on) {
      location.reload();
      return;
    }
    if (upgradeTimer) { clearTimeout(upgradeTimer); upgradeTimer = null; }
    if (M) upgradeTimer = M.watch(upgrade, readUpgrade);
  }
  /* Asked again every minute while on screen and on every return
     (2026-10-04); a read that fails changes nothing. */
  function readUpgrade() {
    var M = window.ADspaceMaintenance;
    if (!M || !me) return;
    M.ask(true).then(function (d) { if (d) paintUpgrade(d); });
  }
  if (window.ADspaceMaintenance && window.ADspaceMaintenance.often) {
    window.ADspaceMaintenance.often('maintenance',
      function (d) { if (meLoaded && me && d) paintUpgrade(d); },
      function () { if (meLoaded) readUpgrade(); });
  }
  function setUpgrade(args, done) {
    db.rpc('maintenance_set', args).then(function (r) {
      var d = r.data || {};
      if (r.error || d.error) {
        done(r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message)
                     : d.error === 'bad-window' ? 'Choose an end after the start, and later than now.'
                     : d.error === 'denied' ? 'This needs Team: Upgrade mode.' : d.error);
        return;
      }
      done('');
      paintUpgrade(d);
    }).catch(function () { done('Not saved. Check the connection and try again.'); });
  }
  function upgradeOff(btn) {
    if (btn) btn.disabled = true;
    setUpgrade({ p_on: false, p_note: null, p_starts: null, p_ends: null }, function (err) {
      if (btn) btn.disabled = false;
      upgradeSay(err);
    });
  }
  function myDay(d) { return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }); }
  function myMoment(day, time, fallback) { return day ? day + 'T' + (time || fallback) + ':00+08:00' : null; }
  /* The window as typed: a time with no date is today's (it was dropped, so
     "10:00 pm" alone put the cover up at once), an empty start is now, and
     an empty end waits to be turned off. */
  function upgradeWindow(v) {
    var today = myDay(new Date());
    var starts = myMoment(v.sday || (v.stime ? today : ''), v.stime, '00:00');
    var ends = myMoment(v.eday || (v.etime ? today : ''), v.etime, '23:59');
    var bad = ends && (new Date(ends) <= new Date(starts || Date.now()) || new Date(ends) <= new Date());
    return { starts: starts, ends: ends, bad: bad ? 'Choose an end after the start, and later than now.' : '' };
  }
  /* The switch on the Settings page (2026-10-10): off at the press, on
     through its question. */
  function upgradeToggle(btn) {
    upgradeSay('');
    if (upgrade.set) { upgradeOff(btn); return; }
    var today = myDay(new Date());
    window.ADspaceConfirm.ask({
      title: 'Turn on upgrade mode',
      body: 'Every portal page shows Upgrading in progress to everyone but admins. The front door and short links stay up. An empty start begins now; an empty end waits to be turned off.',
      go: 'Turn on',
      tone: 'warn',
      fields: [{ name: 'sday', label: 'Starts', type: 'date', min: today, required: false, half: true },
               { name: 'stime', label: 'Start time', type: 'time', required: false, half: true, hint: 'Optional' },
               { name: 'eday', label: 'Ends', type: 'date', min: today, required: false, half: true },
               { name: 'etime', label: 'End time', type: 'time', required: false, half: true, hint: 'Optional' },
               { name: 'note', label: 'Note on the cover', placeholder: 'Optional', required: false }],
      check: function (v) { return upgradeWindow(v).bad; }
    }, function (v) {
      var w = upgradeWindow(v);
      setUpgrade({ p_on: true, p_note: v.note || null, p_starts: w.starts, p_ends: w.ends }, upgradeSay);
    });
  }
  if ($('upgradeOff')) $('upgradeOff').addEventListener('click', function () { upgradeOff(this); });
  /* Signing out ends a performance unlock at once rather than leaving it to
     run out on a machine somebody else may sit at next. */
  $('signOut').addEventListener('click', function () {
    /* This device stops hearing about this colleague's work before the
       session goes: whoever signs in next is not told about it. Waited on
       for at most a second and a half, so a slow network never holds the
       way out. */
    var quiet = function (then) {
      var P = window.ADspacePush;
      if (!P || !pushOn) { then(); return; }
      var done = false, once = function () { if (!done) { done = true; then(); } };
      P.off(true).then(once, once);
      setTimeout(once, 1500);
    };
    var forget = function () { var D = window.ADspaceDocs; return D && D.forgetFiles ? D.forgetFiles() : Promise.resolve(); };
    var out = function () { quiet(function () { forget().then(function () { return db.auth.signOut(); }).then(function () { location.reload(); }); }); };
    if (window.ADspacePerf && window.ADspacePerf.lock) window.ADspacePerf.lock(out); else out();
  });
  $('noTeamRetry').addEventListener('click', function () { location.reload(); });
  $('noTeamOut').addEventListener('click', function () {
    db.auth.signOut().then(function () { location.reload(); });
  });
  db.auth.getSession().then(function (r) { gate(r.data.session); });
  /* A proof of who you are (a passkey on My records) runs a sign-in, and
     the library announces the session it makes before the page can check
     whose it is. While one runs the console holds its auth events, and it
     reads the session again once the proof has finished (`hold`). */
  var held = false;
  db.auth.onAuthStateChange(function (_e, session) { if (!held) gate(session); });
  function hold(on) {
    held = Boolean(on);
    if (!held) db.auth.getSession().then(function (r) { gate(r.data.session); });
  }

  /* Supabase refreshes the token when you come back to the tab, which fires an
     auth event. Only the first one should decide what is on screen, otherwise
     switching tabs throws away whatever you were in the middle of. */
  var entered = false;

  function whoOf(session) {
    var u = session && session.user;
    return u ? String(u.id || u.email || '').toLowerCase() : '';
  }
  /* ONE PERSON PER CONSOLE. The access map, the lists and every section's
     cache were read for the person who entered; a session that turns into
     somebody else's (a sign-in in another tab, or any sign-in over this one)
     must never keep them. The console starts again from the top as that
     person, after a moment in which a proof that is putting the right
     session back can finish (2026-09-27: a passkey unlock left the menus of
     one account over the data of another). */
  var enteredAs = '';
  function gate(session) {
    var inApp = Boolean(session);
    if (inApp && enteredAs && whoOf(session) !== enteredAs) {
      setTimeout(function () {
        db.auth.getSession().then(function (r) {
          if (whoOf(r.data.session) !== enteredAs) location.reload();
        });
      }, 1500);
      return;
    }
    // Signed out is a plain page, white to the edges. Signed in is the console,
    // which brings its own chrome and does not want the page header as well.
    /* SIGNED IN IS NOT THE SAME AS ALLOWED IN, and the in-between is still
       the console's own shell. Nothing about what this person may open is
       drawn before the database has said it — the nav's names and the bar's
       controls are blank and the body is a skeleton — but the shell, the rail
       and the bar are the console's, because what used to stand here was the
       shared page bar over an empty page, which is the composition the
       client-facing pages use, and a refresh read for a second or two as
       somebody else's portal. */
    document.body.classList.toggle('is-plain', !inApp);
    document.documentElement.removeAttribute('data-boot');
    $('topbar').hidden = inApp;
    $('publicShell').hidden = inApp;
    $('console').classList.toggle('is-booting', inApp && !meLoaded);
    $('console').hidden = !inApp;
    $('authPanel').hidden = inApp;
    $('acctWrap').hidden = !inApp;
    if (!inApp) shutAcct();
    $('whoami').textContent = inApp ? session.user.email : '';
    /* Who you are, in words. There is no profile picture by decision, so the
       control names the person: a screenshot of any screen then says whose
       account it was taken from, which a monogram of an email address did
       not. The team row arrives after this, so the address stands in until
       it does (see nameAcct below) and the name replaces it. */
    paintAcct(inApp ? (session.user.email || '') : '');
    actor = inApp ? session.user.email : '';

    if (!inApp) {
      entered = false;
      enteredAs = '';
      meLoaded = false;
      $('noTeamShell').hidden = true;
      $('clientsView').hidden = true;
      $('workspace').hidden = true;
      return;
    }
    // Already decided: a token refresh must not blank the console.
    if (meLoaded) { $('console').hidden = Boolean(!me); return; }
    if (entered) return;
    entered = true;
    enteredAs = whoOf(session);
    /* Who this person is on the team decides what the console draws. The
       database enforces the same row on every query; this only keeps the
       screen honest about it. Fetched once, before anything is shown. */
    loadMe(function () {
      applyAccess();
      readUpgrade();
      /* The team's announcement, once the person is known (js/announce.js). */
      if (me && window.ADspaceAnnounce) window.ADspaceAnnounce.refresh();
      /* The media pass for a colleague (js/media.js). Not waited on: a file
         drawn before it lands asks again and loads. */
      if (me && window.ADspaceMedia && window.ADspaceMedia.pass) window.ADspaceMedia.pass({});
      /* The bell in the bar is My Work's, drawn on every route for anybody who
         can read the section, so it is told the moment the person is known. */
      if (window.ADspaceOps && window.ADspaceOps.signedIn) window.ADspaceOps.signedIn();
      gateActivity();
      // Who wrote what, by address. Fire and forget: the record reads as
      // addresses until it lands, which is what it read as before.
      if (me) loadWho(function () { if (!$('activitySheet').hidden) paintActivity(); });
      if (!me) {
        // A plain page like sign-in: the page header, white to the edges.
        $('console').classList.remove('is-booting');
        $('console').hidden = true;
        $('topbar').hidden = false;
        document.body.classList.add('is-plain');
        $('noTeamShell').hidden = false;
        $('noTeamWho').textContent = actor;
        if (meFailed) {
          var fail = $('noTeamShell').querySelector('.cover-panel');
          fail.querySelector('h2').textContent = 'Unable to load';
          fail.querySelector('p').textContent = 'Please refresh the page.';
          $('noTeamRetry').hidden = false;
          return;
        }
        /* Access that ended on its date says so (TEAM ACCESS EXPIRY). */
        db.rpc('my_access_expired').then(function (r) {
          if (r.error || r.data !== true) return;
          var panel = $('noTeamShell').querySelector('.cover-panel');
          panel.querySelector('h2').textContent = 'Access expired';
          panel.querySelector('p').innerHTML = 'Access for <b>' + String(actor).replace(/[&<>"]/g, '') + '</b> has ended. Please contact an administrator to extend it.';
        }).catch(function () {});
        return;
      }
      $('console').classList.remove('is-booting');
      $('console').hidden = false;
      $('topbar').hidden = true;
      document.body.classList.remove('is-plain');
      // A session kept in local storage answers before the scripts below this
      // one have run. Restoring then would write the address with nothing
      // open and lose the tab or campaign it named, so wait for the page.
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', restoreView, { once: true });
      } else {
        restoreView();
      }
      followBell();
      /* Once per browser, on a device that can hold one, a colleague with no
         passkey is asked whether to add one. */
      if (window.ADspacePasskey) setTimeout(window.ADspacePasskey.offer, 1200);
    });
  }

  /* The signed-in person's team row, or null if they have a login but no row.
     A sign-in that lapsed while the tab slept answers 401: it is refreshed
     and asked once more. A read that still fails is said as Unable to load
     (`meFailed`), never drawn as the whole console nor as Access denied
     (2026-10-07: the older answer, "everyone may do everything", was for a
     database without me()). */
  var me = null;
  var SYSTEM = { ids: {}, names: {} };
  /* A colleague is a system account by its row's own mark, else by its id
     or name in the console's one read. */
  function isSystem(m) {
    if (!m) return false;
    if (typeof m === 'string') return Boolean(SYSTEM.ids[m] || SYSTEM.names[m]);
    return Boolean(m.system || SYSTEM.ids[m.id || m.team_member_id] || (m.name && SYSTEM.names[m.name] && !m.id));
  }
  var meLoaded = false;
  var meFailed = false;
  function loadMe(then) {
    /* The business figures the team may change (SST, terms, follow-up
       limits; js/money.js) are read beside me(), so no screen draws first. */
    var MON = window.ADspaceMoney, rates = MON && MON.load ? MON.load() : Promise.resolve();
    /* System accounts (2026-10-08): kept for IT, never offered for work, so
       every picker asks `isSystem` from this one read. A read that fails
       leaves the set empty, never the console. */
    var sys = db.from('team_members').select('id, name').eq('system', true).then(function (r) {
      SYSTEM = { ids: {}, names: {} };
      (r && !r.error && r.data || []).forEach(function (m) { SYSTEM.ids[m.id] = true; if (m.name) SYSTEM.names[m.name] = true; });
    }, function () {});
    var go = function () { Promise.all([rates.then(null, function () {}), sys]).then(then, then); };
    var ask = function () { return db.rpc('me'); };
    ask().then(function (r) {
      if (!r.error) return r;
      return db.auth.refreshSession().then(ask, ask);
    }).then(function (r) {
      meFailed = Boolean(r.error);
      me = !r.error && r.data && r.data.id ? r.data : null;
      /* First-visit guides (js/guide.js): which this colleague has met,
         on any device. */
      if (me && window.ADspaceGuide) window.ADspaceGuide.useServer(function () {
        return db.rpc('guides_seen').then(function (g) { if (g.error) throw g.error; return g.data || []; });
      }, function (key) { db.rpc('guide_seen_mark', { p_guide: key }).then(function () {}, function () {}); });
      /* The rail and the tab bar as this colleague arranged them. */
      if (me) loadRail();
      meLoaded = true;
      go();
    }).catch(function () { me = null; meFailed = true; meLoaded = true; go(); });
  }

  /* Access is a level per section, the same four the database ranks.
     `view` reads, `work` adds, edits and publishes, `manage` also destroys.
     The line is reversibility: Unpublish exists, so publishing is `work`;
     a permanent deletion has no way back, so it is `manage`. */
  /* The rail's order, which is also the Activity record's and the Team
     panel's: one sequence across the console rather than three. */
  var SECTIONS = ['ops', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp', 'register', 'links', 'services', 'team', 'activity'];
  /* A part is a pane or a list inside a section, keyed `section.part`. It
     takes its own level where the group set one and its section's where it
     did not, in the page exactly as in `allowed()`, so a group that never
     opened the Parts fold is where it always was. HR letters were a section
     and are `register.hr` now. */
  var PARTS = {
    /* `leads` and `past` are the lead stages and Past (2026-10-03): they
       narrow what the Clients level opens on those records, in the database
       (`client_row_seen`) as here. */
    clients:   ['contacts', 'billing', 'services', 'documents', 'requests', 'calls', 'leads', 'past'],
    /* WhatsApp (2026-10-10): a send for a report, a feedback request or a
       creator's booking follows the section unless a group shuts it. */
    whatsapp:  ['report', 'feedback', 'booking', 'approval'],
    review:    ['sets', 'settings'],
    campaigns: ['campaigns', 'creators', 'finance', 'files_delete'],
    /* Document types (2026-10-07) is granted: an admin's by itself, any
       other group's once set. */
    register:  ['documents', 'hr', 'types'],
    /* The record is read a tab at a time, so its access is a part per tab.
       `activity_section()` in the database maps a tag to the section the
       console files it under and the read policy asks the part, so the tabs
       here draw exactly what the database will send. */
    activity:  ['ops', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp', 'register', 'links', 'services', 'team', 'handbook'],
    /* Operations is the one section whose parts *widen* it rather than
       narrowing it: the team's whole queue, the reports, the templates and
       another person's hours are all more than "work my own tasks". So they
       are granted and never inherited, which `level()` below honours by not
       falling back for them, exactly as `ops_granted()` does in the
       database. A group given `{"ops":"work"}` reads its own work and
       nothing else, today and after somebody adds a group next year. */
    ops:       ['all', 'reports', 'workflows', 'time', 'numbering', 'override'],
    /* Everybody's monthly performance review. Granted and never inherited
       like the four above, and for the same reason: administering the team
       is not reading everybody's scores. The database asks for the master
       code on top of this, every time. */
    team:      ['performance', 'perfadmin', 'settings', 'upgrade', 'invite', 'handbook', 'announce', 'notice'],
    /* White label (2026-10-07): granted like the ones above, so an admin
       holds it and any other group only once it is set. So is every act an
       admin alone could take before (2026-10-07, ADMIN PARTS): task
       numbering, moving anybody's task, Performance's company figures,
       settings and removals, business settings, upgrade mode, invitations,
       Handbook files, Transfer client and AI usage. */
    reports:   ['whitelabel', 'transfer', 'ai', 'meta']
  };
  var OPS_GRANTED = { 'ops.all': 1, 'ops.reports': 1, 'ops.workflows': 1, 'ops.time': 1, 'team.performance': 1,
    'reports.whitelabel': 1, 'ops.numbering': 1, 'ops.override': 1, 'team.perfadmin': 1, 'team.settings': 1,
    'team.upgrade': 1, 'team.invite': 1, 'team.handbook': 1, 'reports.transfer': 1, 'reports.ai': 1,
    'team.announce': 1, 'register.types': 1, 'team.health': 1, 'team.notice': 1, 'reports.meta': 1,
    'campaigns.files_delete': 1 };
  var RANK = { none: 0, view: 1, work: 2, manage: 3 };
  function level(key) {
    /* No key is no access, never an exception. A permission check that throws
       takes the whole console down with it, which is what an unnamed key did
       here once; and where it cannot answer it refuses, which is the posture
       the rest of the ladder already states. The admin answer deliberately
       stays *below* this, or a bug reaches only the people without the
       permission to survive it — which is exactly how this one hid. */
    if (!key) return 0;
    if (!me) return 0;
    if (me.is_admin || me.role === 'admin') return 3;
    var acc = me.access || {};
    var lv = acc[key];
    if (lv == null && key.indexOf('.') > 0 && !OPS_GRANTED[key]) lv = acc[key.split('.')[0]];
    return RANK[lv] || 0;
  }
  /* `may('clients')` still reads as it always did and still means the
     everyday level, so nothing that asked the old question has changed its
     meaning; a second argument asks for one of the other three. */
  function may(section, want) {
    return level(section) >= (RANK[want || 'work'] || 2);
  }
  /* Two routes whose name on the screen is not the key in the ladder. The
     Register is one page over two parts of the ladder, the documents and the
     HR letters, which are gated apart: either opens it, and the database's own
     policy decides which rows arrive. My Work is the section the database
     calls `ops`: the route is named for what a person does on it and the
     permission for what it governs, and the mapping lives here rather than
     being spelled out in both vocabularies everywhere. */
  function sectionAllowed(name) {
    if (name === 'register') return may('register.documents', 'view') || may('register.hr', 'view');
    if (name === 'activity') {
      return may('activity', 'view') || PARTS.activity.some(function (k) {
        return may('activity.' + k, 'view');
      });
    }
    if (name === 'work') return may('ops', 'view');
    /* Team is two jobs gated apart: members and groups, and the monthly
       reviews. Either opens the route; the tab strip shows what is held. */
    if (name === 'team') return may('team', 'view') || may('team.performance', 'view') || may('team.health', 'work');
    /* Everybody on the team has a record of their own to read. */
    if (name === 'mine') return Boolean(me && me.id);
    /* Settings (2026-10-10): any colleague holding one of its granted parts. */
    if (name === 'settings') return Boolean(window.ADspaceSettings && window.ADspaceSettings.allowed());
    /* The Handbook is every colleague's to read (only an admin changes it),
       so it has no level of its own on the ladder. */
    if (name === 'handbook') return Boolean(me && (me.id || me.is_admin));
    /* The Overview is the start page of a group that oversees something: an
       admin, or a group one of whose cards is allowed (2026-09-28). It has no
       key of its own; each card asks its own, and the Overview asks them all
       (`ADspaceOverview.any`), so Full Access on a section with no card
       (Short Links, Services, Team) never lands on an empty page (audit,
       2026-10-03). */
    if (name === 'overview') {
      var ov = window.ADspaceOverview;
      return ov && ov.any ? ov.any() : managesAny();
    }
    return may(name, 'view');
  }
  function managesAny() {
    if (!me) return false;
    if (me.is_admin || me.role === 'admin') return true;
    var keys = SECTIONS.slice();
    Object.keys(PARTS).forEach(function (s) { PARTS[s].forEach(function (p) { keys.push(s + '.' + p); }); });
    return keys.some(function (k) { return level(k) >= RANK.manage; });
  }

  /* Hide what the person may not use. Nothing here is the control; the
     policies are. This keeps the screen from offering what will be refused.
     One class per section and per part rather than one global `no-remove`,
     because the authority to destroy is per section now: a group can manage
     Content Review without being able to delete a client. A part's class
     hyphenates the key (`no-work-clients-billing`), since a dot is not a
     class token. */
  function applyAccess() {
    /* The team row has arrived by now, so the account control can stop
       standing in with an address and name the person. */
    paintAcct(actor);
    navItems().forEach(function (b) {
      b.hidden = !sectionAllowed(b.getAttribute('data-section'));
    });
    /* A group whose every route is withheld takes its heading with it: a
       label over nothing is the same fault as a table header over no rows. */
    Array.prototype.forEach.call(document.querySelectorAll('.navgroup'), function (g) {
      g.hidden = !g.querySelector('.navitem:not([hidden])');
    });
    var keys = SECTIONS.slice();
    Object.keys(PARTS).forEach(function (s) {
      PARTS[s].forEach(function (p) { keys.push(s + '.' + p); });
    });
    keys.forEach(function (k) {
      var cls = k.replace('.', '-');
      document.body.classList.toggle('no-manage-' + cls, !may(k, 'manage'));
      document.body.classList.toggle('no-work-' + cls, !may(k, 'work'));
      document.body.classList.toggle('no-view-' + cls, !may(k, 'view'));
    });
    /* ===== Console search (js/search.js): drawn once the ladder is known. */
    if (window.ADspaceSearch) window.ADspaceSearch.access();
  }

  /* On a narrow desk window the rail is a drawer; under the tab bar it is
     the panel More opens, holding the sections the bar does not. Either
     closes on a pick, on the scrim, and on escape, so it can never be left
     covering the work. */
  var rail = (function () {
    var bar = $('sidebar');
    var scrim = null;

    function shut() {
      bar.classList.remove('is-open');
      if (scrim) { scrim.remove(); scrim = null; }
      var more = $('tabMore');
      if (more) more.setAttribute('aria-expanded', 'false');
      paintTabOn();
    }
    function open() {
      bar.classList.add('is-open');
      scrim = document.createElement('button');
      scrim.className = 'scrim';
      scrim.type = 'button';
      scrim.setAttribute('aria-label', 'Close sections');
      scrim.addEventListener('click', shut);
      document.body.appendChild(scrim);
      var more = $('tabMore');
      if (more && document.documentElement.classList.contains('has-tabbar')) more.setAttribute('aria-expanded', 'true');
      paintTabOn();
    }

    $('navToggle').addEventListener('click', function () {
      bar.classList.contains('is-open') ? shut() : open();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && bar.classList.contains('is-open')) shut();
    });
    bar.addEventListener('click', function (e) {
      if (e.target.closest('.navitem, .railrow')) shut();
    });
    return { open: open, shut: shut, isOpen: function () { return bar.classList.contains('is-open'); } };
  })();

  /* ===== The phone tab bar (the user, 2026-10-09: "a tab bar below on
     mobile / pwa"). On a touch screen narrower than a desk, the foldable
     open as much as shut, and on any window at 640 and under, the rail
     gives way to a bar at the foot: the first four sections this person may
     open, in the rail's order, each one press from the thumb, and More,
     which opens the rest above the bar. Five or fewer with no Activity
     record take the bar whole, with no More. Each section is offered once:
     More lists only what the bar does not. A card that pops up (a ⋯ menu,
     the bell, the account menu, a guide) rises above the bar; a sheet
     covers it, as an iPhone app's sheet does, so no form is left with the
     bar under a thumb. The bar steps away while a field takes the keyboard,
     so it never sits on what is typed. */
  var TAB_WORD = {
    overview: 'Overview', work: 'My Work', clients: 'Clients', whatsapp: 'WhatsApp', review: 'Review',
    scripts: 'Scripts', campaigns: 'Campaigns', register: 'Documents', reports: 'Reports', links: 'Links',
    services: 'Services', team: 'Team', handbook: 'Handbook'
  };
  var TAB_MORE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="5.5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18.5" cy="12" r="1.3"/></svg>';
  var tabMedia = window.matchMedia && window.ADSPACE_TABBAR ? window.matchMedia(window.ADSPACE_TABBAR) : null;
  var tabbed = [];
  /* The person's own order (the user, 2026-10-10: "Add in the phone tab
     bar rearrange"; "mobile tab and web … both sync edits"): one list a
     colleague, kept by `rail_order_set` with a copy in this browser so the
     first paint is theirs. It orders each of the rail's groups (Work,
     Internal; the Overview stays first), a section it does not name after
     in the standard order, and the tab bar takes the rail as it then reads,
     so the web and the phone follow the one arrangement. */
  var railPick = [];
  var railStd = null;
  var tabRoom = 4;
  function railKey() { return me && me.id ? 'adspace-rail:' + me.id : ''; }
  function railGroups() {
    return Array.prototype.filter.call(document.querySelectorAll('#sidebar .navgroup'), function (g) {
      return g.querySelector('.sidebar-label');
    });
  }
  function applyRail(list) {
    var groups = railGroups();
    if (!railStd) railStd = groups.map(function (g) {
      return Array.prototype.map.call(g.querySelectorAll('.navitem[data-section]'), function (b) { return b.getAttribute('data-section'); });
    });
    groups.forEach(function (g, n) {
      var std = railStd[n] || [];
      var want = (list || []).filter(function (k) { return std.indexOf(k) > -1; });
      std.forEach(function (k) { if (want.indexOf(k) < 0) want.push(k); });
      want.forEach(function (k) {
        var b = g.querySelector('.navitem[data-section="' + k + '"]');
        if (b) g.appendChild(b);
      });
    });
  }
  function keepRail(list) {
    railPick = (list || []).filter(function (k) { return typeof k === 'string'; });
    applyRail(railPick);
    var k = railKey();
    if (!k) return;
    try {
      if (railPick.length) localStorage.setItem(k, JSON.stringify(railPick));
      else localStorage.removeItem(k);
    } catch (e) {}
  }
  function loadRail() {
    var k = railKey();
    var kept = [];
    if (k) { try { var v = JSON.parse(localStorage.getItem(k) || '[]'); if (Array.isArray(v)) kept = v; } catch (e) {} }
    keepRail(kept);
    db.rpc('rail_order_mine').then(function (r) {
      if (r.error || !r.data || r.data.error || !Array.isArray(r.data.sections)) return;
      if (r.data.sections.join(',') === railPick.join(',')) return;
      keepRail(r.data.sections);
      if (meLoaded) paintTabbar();
    }).catch(function () {});
  }
  function tabbarOn() { return Boolean(tabMedia && tabMedia.matches); }
  function paintTabbar() {
    var bar = $('tabBar');
    if (!bar) return;
    document.documentElement.classList.toggle('has-tabbar', tabbarOn());
    var open = navItems().filter(function (b) { return !b.hidden; });
    /* Settings and the Activity record are in the account menu, so More
       holds sections alone. */
    var room = open.length <= 5 ? 5 : 4;
    tabRoom = room;
    var tabs = open.slice(0, room);
    var more = open.length > room;
    var edit = $('railEdit');
    if (edit) edit.hidden = !(open.length > 2);
    tabbed = tabs.map(function (b) { return b.getAttribute('data-section'); });
    navItems().forEach(function (b) {
      b.classList.toggle('is-tabbed', tabbed.indexOf(b.getAttribute('data-section')) > -1);
    });
    Array.prototype.forEach.call(document.querySelectorAll('.navgroup'), function (g) {
      g.classList.toggle('is-tabbed', !g.querySelector('.navitem:not([hidden]):not(.is-tabbed)'));
    });
    var sign = tabbed.join(',') + (more ? ',more' : '');
    if (sign === bar.getAttribute('data-sign')) { paintTabOn(); return; }
    bar.setAttribute('data-sign', sign);
    bar.innerHTML = tabs.map(function (b) {
      var name = b.getAttribute('data-section');
      var glyph = b.querySelector('svg');
      return '<button class="tabbar-tab" type="button" data-tab="' + esc(name) + '">' +
        (glyph ? glyph.outerHTML : '') + '<span class="tabbar-word">' + esc(TAB_WORD[name] || name) + '</span></button>';
    }).join('') + (more
      ? '<button class="tabbar-tab" id="tabMore" type="button" data-tab="more" aria-haspopup="true" aria-expanded="false" aria-controls="sidebar">' +
        TAB_MORE + '<span class="tabbar-word">More</span></button>'
      : '');
    bar.style.setProperty('--tabs', String(tabs.length + (more ? 1 : 0)));
    bar.hidden = !tabs.length;
    paintTabOn();
  }
  /* The chosen tab is the section on screen; one the bar does not hold
     chooses More, as an iPhone app does. My records (the account menu)
     chooses none. */
  function paintTabOn() {
    var bar = $('tabBar');
    if (!bar) return;
    var moreOpen = rail && rail.isOpen() && document.documentElement.classList.contains('has-tabbar');
    var inBar = tabbed.indexOf(section) > -1;
    Array.prototype.forEach.call(bar.querySelectorAll('.tabbar-tab'), function (t) {
      var name = t.getAttribute('data-tab');
      var on = moreOpen ? name === 'more'
        : name === 'more' ? (!inBar && section !== 'mine' && (section === 'settings' || navItems().some(function (b) { return !b.hidden && b.getAttribute('data-section') === section; })))
        : name === section;
      t.classList.toggle('is-on', on);
      if (on && name !== 'more') t.setAttribute('aria-current', 'page'); else t.removeAttribute('aria-current');
    });
  }
  (function () {
    var bar = $('tabBar');
    if (!bar) return;
    bar.addEventListener('click', function (e) {
      var t = e.target.closest('.tabbar-tab');
      if (!t) return;
      var name = t.getAttribute('data-tab');
      if (name === 'more') { rail.isOpen() ? rail.shut() : rail.open(); return; }
      if (rail.isOpen()) rail.shut();
      visitSection(name);
    });
    /* Arrange sections (the rail's foot; under the tab bar, More's): the
       rail's two groups as lists, each section dragged by its grip (or
       moved with the arrow keys on it) within its group. Under the tab bar
       the sections it will hold read Tab bar as they move. Save keeps the
       order for the rail and the bar alike; Reset order puts the standard
       back in the sheet. */
    var RO_X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
    var RO_GRIP = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" aria-hidden="true"><path d="M5 9h14M5 15h14"/></svg>';
    var roBox = null;
    function roSheet() {
      if (roBox) return roBox;
      roBox = document.createElement('div');
      roBox.className = 'sheet'; roBox.id = 'railSheet'; roBox.hidden = true;
      roBox.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="railSheetH" data-narrow="560">' +
        '<div class="sheet-head"><h3 id="railSheetH">Arrange sections</h3>' +
        '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + RO_X + '</button></div>' +
        '<div class="sheet-body"><div id="railLists"></div><div class="msg ro-msg" id="railMsg" role="status"></div></div>' +
        '<div class="sheet-foot">' +
          '<button class="btn btn-primary" type="button" id="railSave">Save</button>' +
          '<button class="btn" type="button" id="railReset">Reset order</button>' +
          '<button class="btn btn-quiet" type="button" id="railCancel">Cancel</button>' +
        '</div></div>';
      document.body.appendChild(roBox);
      roBox.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
      $('railCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
      $('railReset').addEventListener('click', function () { roFill(railStd ? [].concat.apply([], railStd) : []); });
      $('railSave').addEventListener('click', roSave);
      var lists = $('railLists');
      /* The drag: a press on a grip carries its row; the row moves before
         the first row whose middle is below the hand, within its own list. */
      var drag = null;
      lists.addEventListener('pointerdown', function (e) {
        var g = e.target.closest('.ro-grip');
        if (!g || (e.pointerType === 'mouse' && e.button !== 0)) return;
        e.preventDefault();
        var row = g.closest('.ro-row');
        drag = { row: row, list: row.parentNode, id: e.pointerId };
        row.classList.add('is-drag');
        try { g.setPointerCapture(e.pointerId); } catch (x) {}
      });
      lists.addEventListener('pointermove', function (e) {
        if (!drag || e.pointerId !== drag.id) return;
        var rows = Array.prototype.filter.call(drag.list.children, function (r) { return r !== drag.row; });
        var before = null;
        for (var i = 0; i < rows.length; i++) {
          var q = rows[i].getBoundingClientRect();
          if (e.clientY < q.top + q.height / 2) { before = rows[i]; break; }
        }
        if (before !== drag.row.nextElementSibling || (!before && drag.list.lastElementChild !== drag.row)) {
          drag.list.insertBefore(drag.row, before);
          roMarks();
        }
      });
      function drop() {
        if (!drag) return;
        drag.row.classList.remove('is-drag');
        drag = null;
        roMarks();
      }
      lists.addEventListener('pointerup', drop);
      lists.addEventListener('pointercancel', drop);
      lists.addEventListener('keydown', function (e) {
        var g = e.target.closest('.ro-grip');
        if (!g || (e.key !== 'ArrowUp' && e.key !== 'ArrowDown')) return;
        e.preventDefault();
        var row = g.closest('.ro-row');
        if (e.key === 'ArrowUp' && row.previousElementSibling) row.parentNode.insertBefore(row, row.previousElementSibling);
        else if (e.key === 'ArrowDown' && row.nextElementSibling) row.parentNode.insertBefore(row.nextElementSibling, row);
        else return;
        g.focus();
        roMarks();
      });
      return roBox;
    }
    function roFill(order) {
      var lists = $('railLists');
      lists.innerHTML = railGroups().map(function (g, n) {
        var label = g.querySelector('.sidebar-label');
        var items = Array.prototype.filter.call(g.querySelectorAll('.navitem[data-section]'), function (b) { return !b.hidden; });
        if (order) items.sort(function (x, y) {
          var ix = order.indexOf(x.getAttribute('data-section')), iy = order.indexOf(y.getAttribute('data-section'));
          return (ix < 0 ? 99 : ix) - (iy < 0 ? 99 : iy);
        });
        if (!items.length) return '';
        return '<section class="fsec ro-sec"><h4 class="fsec-h" id="roH' + n + '">' + esc(label ? label.textContent.trim() : '') + '</h4>' +
          '<div class="ro-list" role="list" aria-labelledby="roH' + n + '">' + items.map(function (b) {
            var k = b.getAttribute('data-section'), w = b.querySelector('span'), glyph = b.querySelector('svg');
            var name = (w && w.textContent.trim()) || k;
            return '<div class="ro-row" role="listitem" data-k="' + esc(k) + '">' +
              '<span class="ro-glyph">' + (glyph ? glyph.outerHTML : '') + '</span>' +
              '<span class="ro-name">' + esc(name) + '</span>' +
              '<span class="chip ro-tab" hidden>Tab bar</span>' +
              '<button class="iconbtn ro-grip" type="button" aria-label="Move ' + esc(name) + '" aria-keyshortcuts="ArrowUp ArrowDown">' + RO_GRIP + '</button></div>';
          }).join('') + '</div></section>';
      }).join('');
      roMarks();
    }
    /* Under the tab bar, the rows it will hold: the Overview first where
       it is open, then the rail as the sheet reads it. */
    function roMarks() {
      var rows = Array.prototype.slice.call($('railLists').querySelectorAll('.ro-row'));
      var ov = navItems().some(function (b) { return !b.hidden && b.getAttribute('data-section') === 'overview'; });
      var room = tabRoom - (ov ? 1 : 0);
      rows.forEach(function (r, i) { r.querySelector('.ro-tab').hidden = !(tabbarOn() && i < room); });
    }
    function roOrder() {
      return Array.prototype.map.call($('railLists').querySelectorAll('.ro-row'), function (r) { return r.getAttribute('data-k'); });
    }
    function roSave() {
      var btn = $('railSave'), m = $('railMsg');
      var list = roOrder();
      var std = [].concat.apply([], railStd || []).filter(function (k) { return list.indexOf(k) > -1; });
      var send = list.join(',') === std.join(',') ? [] : list;
      m.textContent = ''; m.className = 'msg ro-msg';
      btn.disabled = true;
      db.rpc('rail_order_set', { p_sections: send }).then(function (r) {
        btn.disabled = false;
        var why = r.error ? (/PGRST202|Could not find the function/i.test((r.error.code || '') + ' ' + (r.error.message || ''))
          ? 'This needs a database update.' : 'Not saved. Try again.')
          : (r.data && r.data.error) ? 'Not saved. Try again.' : '';
        if (why) { m.textContent = why; m.className = 'msg ro-msg err'; return; }
        keepRail(send);
        paintTabbar();
        window.ADspaceSheet.clean();
        window.ADspaceSheet.close();
      }).catch(function () { btn.disabled = false; m.textContent = 'Not saved. Try again.'; m.className = 'msg ro-msg err'; });
    }
    var edit = $('railEdit');
    if (edit) edit.addEventListener('click', function () {
      if (rail.isOpen()) rail.shut();
      roSheet();
      $('railMsg').textContent = '';
      roFill(null);
      window.ADspaceSheet.show(roBox, { opener: $('acctBtn') });
    });
    function follow() {
      var was = document.documentElement.classList.contains('has-tabbar');
      if (was !== tabbarOn() && rail.isOpen()) rail.shut();
      paintTabbar();
    }
    if (tabMedia) {
      if (tabMedia.addEventListener) tabMedia.addEventListener('change', follow);
      else if (tabMedia.addListener) tabMedia.addListener(follow);
    }
    document.documentElement.classList.toggle('has-tabbar', tabbarOn());
    /* The keyboard: a field that takes typing hides the bar under a finger,
       and it returns once nothing is typed in. A select opens the system's
       own wheel and leaves the bar where it is. */
    var touch = window.matchMedia ? window.matchMedia('(pointer: coarse)') : null;
    var typingOff = 0;
    function typing(el) {
      if (!el || !el.matches) return false;
      if (el.isContentEditable || el.matches('textarea')) return true;
      return el.matches('input') && !/^(button|checkbox|radio|range|color|file|submit|reset|image|hidden)$/i.test(el.type || '');
    }
    document.addEventListener('focusin', function (e) {
      if (!touch || !touch.matches || !typing(e.target)) return;
      clearTimeout(typingOff);
      document.body.classList.add('is-typing');
    });
    document.addEventListener('focusout', function () {
      clearTimeout(typingOff);
      typingOff = setTimeout(function () {
        if (!typing(document.activeElement)) document.body.classList.remove('is-typing');
      }, 120);
    });
  })();

  /* Which section of the console is on screen. The rail decides; neither
     section knows the other exists, which is the point of the shell. */
  /* Clients is the root of the model: a content set and a campaign both hang
     off one, so the console opens on the list rather than on work whose owner
     has not been established yet. */
  var section = 'clients';
  var SECTION_TITLE = {
    overview: 'Overview',
    clients: 'Clients',
    whatsapp: 'WhatsApp',
    work: 'My Work',
    review: 'Content Review',
    scripts: 'Video Scripts',
    campaigns: 'Creator Campaigns',
    links: 'Short Links',
    register: 'Documents',
    reports: 'Reports',
    services: 'Services',
    team: 'Team',
    handbook: 'Handbook',
    mine: 'My records',
    settings: 'Settings'
  };
  /* WHAT EACH SECTION IS FOR, in one line, while the team is new to it.
     This portal carries no explanatory copy, and the user asked for exactly
     this on 2026-09-22: the portal is opening to the whole team and most of
     them do not yet know what the sections are. So it is the instruction
     pattern the creator page and the draft step already use: the line opens
     by itself the first three times a section is entered and then retires
     behind its `?` in the command bar, where anybody can open it again. Not
     a `title`, because a tooltip is unreachable on a phone. */
  /* ONE LINE A ROUTE, IN OFFICIAL REGISTER: what the section holds and what
     it is for, and nothing about how to use it. The first pass wrote two
     sentences a route, half of them naming the panes inside a record, which
     is an explanation of the product rather than of the section. The user
     sent them back on 2026-09-22 as too long; each is one sentence now. */
  var INTRO = {
    overview:  'What each section has waiting, for the groups that manage it.',
    clients:   'Every client and lead, from first enquiry to active engagement.',
    whatsapp:  'Every WhatsApp message the portal sent, with what Meta reports of its delivery.',
    work:      'Tasks owed to clients and to the team, ordered by when they are due.',
    review:    'Content sets prepared for client approval.',
    scripts:   'Video scripts by content month, published to the client and used by the crew on the shoot.',
    campaigns: 'Creator campaigns, from selection through to posting.',
    links:     'Short links for slides, print and QR codes, served from ' + ((window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.linkHost) || 'hi.adspace.me') + '.',
    register:  'Every document issued through the portal, and its reference.',
    reports:   'Client reports, from first draft to the version the client reads.',
    services:  'The rate card every quotation is priced from.',
    team:      'Team members, user groups and what each group may open.',
    handbook:  'The Employee Handbook, SOPs, policies and templates the team works by.',
    mine:      'Your own reviews, initiatives, reflections, HR letters and health check-ins.',
    settings:  'Portal switches, business figures, AI limits and document lists, kept by the colleagues who hold them.'
  };
  var INTRO_SHOWS = 3;
  /* FIRST-VISIT GUIDES (js/guide.js; the user, 2026-10-07: first time users
     do not know what each section is for). Two or three steps a section,
     each on a control the section draws; a step whose control this person
     cannot see is left out. Opened once by itself, and again from the ⓘ. */
  var GUIDES = {
    overview: { name: 'Overview', steps: [
      { at: '#ovwTabs', text: 'One tab a section. Its count is what waits there, in red where something is late.' },
      { at: '.ovw-grid .ovw-row', text: 'Press a row to open it where it is kept. View all opens the whole section.' }] },
    work: { name: 'My Work', steps: [
      { at: '#workViews', text: 'The same tasks as a list, a board, a calendar or by month.' },
      { at: '#workNew', text: 'Add a task here, or a client\'s posts for the month.' },
      { at: '#workList .task-stage .state-select', text: 'Move a task on from its stage. Whoever takes it next is told.' }] },
    clients: { name: 'Clients', steps: [
      { at: '#crmNew', text: 'Add a lead the day it comes in. Billing, brand and services follow as the deal firms.' },
      { at: '#crmList .crm-row:not(.crm-head)', text: 'Open a client for its contacts, services, documents and every call and visit.' },
      { at: '#crmViews', text: 'Sales shows the leads won, the clients lost and who needs a call.' }] },
    whatsapp: { name: 'WhatsApp', steps: [
      { at: '#waNew', text: 'New message sends a template Meta approved to a client contact or a creator.' },
      { at: '#waList .wam-row:not(.crm-head)', text: 'Every message the portal sent: Sent, Delivered, Read, or Failed with the reason.' },
      { at: '#waTabs', text: 'Templates sets which approved template each purpose sends, and turns it on or off.' }] },
    review: { name: 'Content Review', steps: [
      { at: '#clientCards .cr-client-row', text: 'Open a client to prepare a content set and send it for approval.' },
      { at: '#crFind', text: 'Find a client by name.' }] },
    scripts: { name: 'Video Scripts', steps: [
      { at: '#vsNew', text: 'New script adds a video to a client\'s content month, numbered by month (2610VS01).' },
      { at: '#vsList .vs-row:not(.crm-head)', text: 'Open a script to write it, publish it to the client\'s link and record each clip number on the day.' }] },
    campaigns: { name: 'Creator Campaigns', steps: [
      { at: '#showAddCamp', text: 'New campaign starts one for a client, with creators from the Creators List.' },
      { at: '#campSectionTabs', text: 'Campaigns, and the Creators List of every creator and their rates.' },
      { at: '#campCards .camp-row', text: 'Open a campaign to book creators, check drafts and release them to the client.' }] },
    register: { name: 'Documents', steps: [
      { at: '#regIssue', text: 'Issue a letter on the letterhead. Its reference is numbered for you.' },
      { at: '#regList .serial-copy', text: 'Press a reference to copy it. Anyone can check it at digital.adspace.me/verify.' }] },
    reports: { name: 'Reports', steps: [
      { at: '#rhNew', text: 'New report starts an Accounts or Advertising Report for an active client.' },
      { at: '#rhTabs', text: 'A report moves from Drafts to In review, Confirmed and Published, where the client reads it.' },
      { at: '#rhMoreBtn', text: 'Select reports to download several, or mark them as sent.' }] },
    links: { name: 'Short Links', steps: [
      { at: '#showAddLink', text: 'Add link makes a short address and its QR code.' },
      { at: '#linkList .crm-group-head', text: 'Live, Namecards and Paused. Every namecard address is listed, so none is taken twice.' }] },
    services: { name: 'Services', steps: [
      { at: '#svcAdd', text: 'Add a service or an add-on to the rate card.' },
      { at: '#svcList .svc-row:not(.crm-head)', text: 'Each line seeds a client\'s services, where it stays editable.' }] },
    team: { name: 'Team', steps: [
      { at: '#teamTabs', text: 'Members, the groups that set what each may open, Performance and Health.' },
      { at: '#teamAdd', text: 'Add member gives a colleague their sign-in and namecard.' }] },
    handbook: { name: 'Handbook', steps: [
      { at: '#hbAdd', text: 'Add a file or a link. A new version never replaces the old one.' },
      { at: '#hbList .hb-row:not(.crm-head)', text: 'Open a file. Earlier versions are in its ⋯.' }] },
    mine: { name: 'My records', steps: [
      { at: '#mineViews', text: 'Your reviews, initiatives, reflections, letters and health check-ins. Only you see them here.' }] }
  };
  function offerGuide(name) {
    var G = window.ADspaceGuide;
    if (!G) return;
    G.leave();
    if (meLoaded && me && GUIDES[name]) G.offer(name, GUIDES[name]);
  }
  function introSeen(name) {
    try { return Number(localStorage.getItem('adspace-hint-intro-' + name) || 0); } catch (e) { return INTRO_SHOWS; }
  }
  /* THE LINE IS A SURFACE THAT COMES FROM THE CONTROL THAT OPENS IT, not a
     block inserted under each route's command bar. A block there could only
     be reached from the directory: open a client, a campaign or a task and
     the bar is off the screen, so the one control that explains the section
     did nothing at all. It hangs off the section's name now, at every width
     and in every state of every route, and is placed by the one copy of where
     a panel opens. */
  function aboutOpen(on) {
    var pop = $('sectionAbout'), btn = $('sectionTitle');
    if (!pop || !btn) return;
    /* Show me around: the section's guide again, where a step of it is on
       the screen (a record hides the list's controls). */
    if (on && $('sectionGuide')) $('sectionGuide').hidden = !(window.ADspaceGuide && window.ADspaceGuide.can(GUIDES[section]));
    pop.hidden = !on;
    btn.setAttribute('aria-expanded', String(on));
    if (on) ADspaceMenu.pop(btn, pop, 'left');
  }
  function aboutIsOpen() { var p = $('sectionAbout'); return p && !p.hidden; }
  /* IT OPENS WHEN IT IS ASKED FOR, AND NEVER BY ITSELF. As a line in the flow
     it could open on arrival and cost one row; as a surface over the page it
     would land on the command bar underneath it, which is the row somebody
     came to use. While a route is new the title's glyph carries the action
     colour instead, so the invitation is on the control and the screen is
     still the person's; after three visits even that retires. */
  function paintIntro(name) {
    var pop = $('sectionAbout'), btn = $('sectionTitle');
    if (!pop || !btn) return;
    aboutOpen(false);
    offerGuide(name);
    if (!INTRO[name]) { btn.classList.remove('is-new'); return; }
    $('sectionAboutText').textContent = INTRO[name];
    var seen = introSeen(name);
    // Counted once per visit, not once per repaint.
    if (seen < INTRO_SHOWS) {
      try { localStorage.setItem('adspace-hint-intro-' + name, String(seen + 1)); } catch (e) {}
    }
    btn.classList.toggle('is-new', seen < INTRO_SHOWS);
  }
  /* The section's name opens and shuts it, wherever on the route you are. */
  $('sectionTitle').addEventListener('click', function (e) {
    e.stopPropagation();
    aboutOpen(!aboutIsOpen());
  });
  $('sectionAboutHide').addEventListener('click', function () {
    try { localStorage.setItem('adspace-hint-intro-' + section, String(INTRO_SHOWS)); } catch (e) {}
    $('sectionTitle').classList.remove('is-new');
    aboutOpen(false);
  });
  $('sectionAbout').addEventListener('click', function (e) { e.stopPropagation(); });
  if ($('sectionGuide')) $('sectionGuide').addEventListener('click', function () {
    aboutOpen(false);
    if (window.ADspaceGuide) window.ADspaceGuide.open(section, GUIDES[section]);
  });
  document.addEventListener('click', function () { if (aboutIsOpen()) aboutOpen(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && aboutIsOpen()) { aboutOpen(false); $('sectionTitle').focus(); }
  });
  ADspaceMenu.onScroll(function () { aboutOpen(false); });

  /* The first section this person is allowed, for when the one asked for is
     not: the Overview, then the rail's own order, My Work first (it was left
     out, so a colleague whose day is My Work landed on Clients, or on the
     Handbook with My Work alone; audit, 2026-10-03). Every colleague reads the
     Handbook, so it is the floor. */
  function firstAllowed() {
    var order = ['overview', 'work', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp', 'register', 'links', 'services', 'team', 'handbook'];
    for (var i = 0; i < order.length; i++) if (sectionAllowed(order[i])) return order[i];
    return 'handbook';
  }

  var enterLater = '';

  function showSection(name) {
    if (!SECTION_TITLE[name]) name = 'clients';
    if (meLoaded && !sectionAllowed(name)) name = firstAllowed();
    section = name;
    $('sectionOverview').hidden  = name !== 'overview';
    $('sectionClients').hidden   = name !== 'clients';
    $('sectionWhatsApp').hidden  = name !== 'whatsapp';
    $('sectionWork').hidden      = name !== 'work';
    $('sectionReview').hidden    = name !== 'review';
    $('sectionScripts').hidden   = name !== 'scripts';
    $('sectionCampaigns').hidden = name !== 'campaigns';
    $('sectionLinks').hidden     = name !== 'links';
    $('sectionRegister').hidden  = name !== 'register';
    $('sectionReports').hidden   = name !== 'reports';
    $('sectionServices').hidden  = name !== 'services';
    $('sectionTeam').hidden      = name !== 'team';
    $('sectionMine').hidden      = name !== 'mine';
    $('sectionHandbook').hidden  = name !== 'handbook';
    $('sectionSettings').hidden  = name !== 'settings';
    $('sectionTitle').querySelector('.console-title-word').textContent = SECTION_TITLE[name];
    if ($('sectionAboutName')) $('sectionAboutName').textContent = SECTION_TITLE[name];
    $('sectionTitle').setAttribute('aria-label', SECTION_TITLE[name] + ', about this section');
    paintIntro(name);
    /* Content Review's list was read once; a client's name, handles or logo
       changed on the record since then are read again on the way in. */
    if (name === 'review' && meLoaded && !state.client && state.reviewClients) loadClients();
    // The tab said Content Review Internal whichever section you were in.
    document.title = SECTION_TITLE[name] + ' · ADspace Digital Portal';
    navItems().forEach(function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-section') === name);
    });
    showActivityLink();
    // Campaigns reads the address before it writes it, because on a reload the
    // address is the only record of which campaign or tab was open. Writing
    // first, with nothing open yet, blanked exactly the part it needed.
    if (name === 'campaigns') {
      // Not loaded yet: leave the address alone and enter once it is.
      if (!window.ADspaceCampaigns) { enterLater = 'campaigns'; return; }
      window.ADspaceCampaigns.enter();
      return;
    }
    if (name === 'overview') {
      if (!window.ADspaceOverview) { enterLater = 'overview'; return; }
      window.ADspaceOverview.enter();
      return;
    }
    if (name === 'clients') {
      if (!window.ADspaceCRM) { enterLater = 'clients'; return; }
      window.ADspaceCRM.enter();
      return;
    }
    if (name === 'team') {
      if (!window.ADspaceTeam || !window.ADspacePerf) { enterLater = 'team'; return; }
      window.ADspacePerf.enterTeam();
      setUrl();
      return;
    }
    if (name === 'mine') {
      if (!window.ADspacePerf) { enterLater = 'mine'; return; }
      window.ADspacePerf.enterMine();
      setUrl();
      return;
    }
    if (name === 'reports') {
      if (!window.ADspaceReports) { enterLater = 'reports'; return; }
      window.ADspaceReports.enterHub();
      setUrl();
      return;
    }
    if (name === 'register') {
      if (!window.ADspaceRegister) { enterLater = 'register'; return; }
      window.ADspaceRegister.enter();
      setUrl();
      return;
    }
    /* My Work reads the address before it writes it, as Campaigns does: on a
       reload the address is the only record of which task was open, and
       writing first would blank the one thing it needs. */
    if (name === 'work') {
      if (!window.ADspaceOps) { enterLater = 'work'; return; }
      window.ADspaceOps.enter();
      return;
    }
    if (name === 'services') {
      if (!window.ADspaceCRM) { enterLater = 'services'; return; }
      window.ADspaceCRM.enterServices();
      setUrl();
      return;
    }
    if (name === 'handbook') {
      if (!window.ADspaceHandbook) { enterLater = 'handbook'; return; }
      window.ADspaceHandbook.enter();
      setUrl();
      return;
    }
    if (name === 'settings') {
      if (!window.ADspaceSettings) { enterLater = 'settings'; return; }
      window.ADspaceSettings.enter();
      setUrl();
      return;
    }
    /* Video Scripts reads the address before it writes it: a video open on a
       reload is named only there. */
    if (name === 'scripts') {
      if (!window.ADspaceScripts) { enterLater = 'scripts'; return; }
      window.ADspaceScripts.enter();
      return;
    }
    /* WhatsApp reads its tab from the address before it writes it. */
    if (name === 'whatsapp' && window.ADspaceWhatsApp) {
      window.ADspaceWhatsApp.enter();
      setUrl();
      return;
    }
    setUrl();
    if (name === 'links') { loadLinks(); restoreScroll(); }
  }

  /* Every `.navitem` that names a section, which is what this function is
     asked for: `applyAccess` puts each one's `data-section` to the ladder, so
     a `.navitem` without one is a question the ladder cannot answer. The rail
     carries a row that is not a section (the Activity record at its foot) and
     that row is a `.railrow`, not a `.navitem` — the selector states the
     requirement rather than trusting the markup to keep it. */
  function navItems() {
    return Array.prototype.slice.call(document.querySelectorAll('.navitem[data-section]'));
  }
  /* A section reached from the rail, or from a link inside the console, is a
     visit: it opens at its top (the user, 2026-10-09: Clients opened halfway
     down after Reports was scrolled), and the list's own restore leaves it
     there. Back from a record still returns to the list's place. */
  var visitAt = 0;
  function visitSection(name) {
    visitAt = Date.now();
    window.scrollTo(0, 0);
    showSection(name);
  }
  navItems().forEach(function (b) {
    b.addEventListener('click', function () { visitSection(b.getAttribute('data-section')); });
  });

  /* A tab that has been in the background long enough is thrown away by the
     browser and rebuilt from scratch when you return. The address bar already
     carries the client and the set; this carries how far down the page you
     were, so coming back lands where you left rather than at the top. */
  var PLACE = 'adspace.place';
  var pendingScroll = 0;

  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';

  var scrollTimer = null;
  window.addEventListener('scroll', function () {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(function () {
      if (!state.client || !personScrolled) return;
      try {
        sessionStorage.setItem(PLACE, JSON.stringify({
          client: clientKey(state.client),
          set: state.batch ? state.batch.id : null,
          y: Math.round(window.scrollY),
          drawer: false
        }));
      } catch (e) { /* private browsing */ }
    }, 180);
  }, { passive: true });

  function readPlace() {
    try { return JSON.parse(sessionStorage.getItem(PLACE) || 'null'); }
    catch (e) { return null; }
  }

  /* Called once the lists that make the page tall have rendered, so the
     position it scrolls to actually exists. */
  function settleScroll() {
    if (!pendingScroll) return;
    var y = pendingScroll;
    requestAnimationFrame(function () {
      window.scrollTo(0, y);
      // A second pass after images size themselves, which is what moves things.
      setTimeout(function () { if (pendingScroll) { window.scrollTo(0, y); pendingScroll = 0; } }, 260);
    });
  }

  // 2. The address bar remembers the client and set you are working on, so a
  //    reload or a reopened tab lands back in the same place.
  /* The address bar is where you are: the section, and whatever is open
     inside it. A refresh, a reopened tab or a pasted link all land there.
     What you were typing is not here; that is the form's own memory. */
  /* A client's address is its slug, the readable one the Clients section
     writes. Older links carrying a UUID still resolve, so nothing shared
     before this stops working. Both live in js/crm.js, which owns clients. */
  function clientKey(c) {
    var CRM = window.ADspaceCRM;
    return (CRM && CRM.keyOf ? CRM.keyOf(c) : '') || (c && c.id) || '';
  }
  function clientByKey(key, then) {
    var CRM = window.ADspaceCRM;
    if (CRM && CRM.byKey) { CRM.byKey(key, then); return; }
    db.from('clients').select(API.CLIENT_COLS).eq('id', key).single()
      .then(function (r) { then(r.error ? null : (r.data || null)); }, function () { then(null); });
  }

  function setUrl() { history.replaceState(null, '', urlOf(queryNow())); }

  function queryNow() {
    var q = [];
    /* A client's own address reads as Clients from `client=` alone; the bare
       list names itself, because `/admin/` is a manager's Overview
       (2026-09-28), and a refresh on the list must stay on the list. */
    if (section !== 'clients' || !(window.ADspaceCRM && window.ADspaceCRM.urlState().client)) {
      q.push('s=' + section);
    }
    if (section === 'review') {
      // The same readable address the Clients section uses.
      if (state.client) q.push('client=' + encodeURIComponent(clientKey(state.client)));
      if (state.batch)  q.push('set=' + state.batch.id);
    } else if (section === 'campaigns' && window.ADspaceCampaigns) {
      var sub = window.ADspaceCampaigns.urlState();
      Object.keys(sub).forEach(function (k) { if (sub[k]) q.push(k + '=' + encodeURIComponent(sub[k])); });
    } else if (section === 'clients' && window.ADspaceCRM) {
      var crm = window.ADspaceCRM.urlState();
      Object.keys(crm).forEach(function (k) { if (crm[k]) q.push(k + '=' + encodeURIComponent(crm[k])); });
    } else if (section === 'work' && window.ADspaceOps) {
      var w = window.ADspaceOps.urlState();
      Object.keys(w).forEach(function (k) { if (w[k]) q.push(k + '=' + encodeURIComponent(w[k])); });
    } else if (section === 'reports' && window.ADspaceReports) {
      var rp = window.ADspaceReports.urlState();
      Object.keys(rp).forEach(function (k) { if (rp[k]) q.push(k + '=' + encodeURIComponent(rp[k])); });
    } else if (section === 'overview' && window.ADspaceOverview && window.ADspaceOverview.urlState) {
      var ov = window.ADspaceOverview.urlState();
      Object.keys(ov).forEach(function (k) { if (ov[k]) q.push(k + '=' + encodeURIComponent(ov[k])); });
    } else if (section === 'team' && window.ADspacePerf) {
      var pf = window.ADspacePerf.urlState();
      Object.keys(pf).forEach(function (k) { if (pf[k]) q.push(k + '=' + encodeURIComponent(pf[k])); });
    } else if (section === 'scripts' && window.ADspaceScripts) {
      var vs = window.ADspaceScripts.urlState();
      Object.keys(vs).forEach(function (k) { if (vs[k]) q.push(k + '=' + encodeURIComponent(vs[k])); });
    } else if (section === 'whatsapp' && window.ADspaceWhatsApp) {
      var wa = window.ADspaceWhatsApp.urlState();
      Object.keys(wa).forEach(function (k) { if (wa[k]) q.push(k + '=' + encodeURIComponent(wa[k])); });
    } else if (section === 'mine' && window.ADspacePerf && window.ADspacePerf.mineState) {
      var mn = window.ADspacePerf.mineState();
      Object.keys(mn).forEach(function (k) { if (mn[k]) q.push(k + '=' + encodeURIComponent(mn[k])); });
    }
    return q;
  }

  /* Most of the address is a note of where you are: it is replaced, so the
     browser's Back button still leaves the console rather than walking every
     repaint. A local navigation inside a record is different — it is a move a
     person made, so it pushes an entry and Back and Forward walk the panes. */
  function pushUrl() {
    var before = location.pathname + location.search;
    var after = urlOf(queryNow());
    if (after !== before) history.pushState(null, '', after);
  }
  function urlOf(q) { return '/admin/' + (q.length ? '?' + q.join('&') : ''); }

  /* Scroll, per address. Review has its own richer memory tied to the client;
     this is the plain one the other sections use. */
  var SCROLL = 'adspace.admin.scroll:';
  var scrollSaveTimer = null;
  /* A list opens at its top on a new visit and on a refresh; only Back and
     Forward return to where it was (the user, 2026-10-08: "it starts at
     slightly lower every refreshes or new visit"). Bars drawn above the list
     while it loads (the announcement, upgrade mode) pushed the page down,
     and that pushed place was saved and restored again, a little lower each
     time; nothing is saved until the person scrolls. */
  var navType = (function () {
    try { var n = performance.getEntriesByType('navigation')[0]; return n ? n.type : ''; } catch (e) { return ''; }
  })();
  var bootScroll = navType !== 'back_forward';
  var personScrolled = false;
  ['wheel', 'touchmove', 'keydown', 'mousedown'].forEach(function (ev) {
    window.addEventListener(ev, function () { personScrolled = true; bootScroll = false; }, { passive: true, capture: true });
  });
  /* Back and Forward return to the place, even straight after a visit. */
  window.addEventListener('popstate', function () { bootScroll = false; visitAt = 0; });
  window.addEventListener('scroll', function () {
    if (section === 'review' || !personScrolled) return;
    clearTimeout(scrollSaveTimer);
    scrollSaveTimer = setTimeout(function () {
      try { sessionStorage.setItem(SCROLL + location.search, String(window.scrollY)); } catch (e) {}
    }, 200);
  });
  function restoreScroll(record) {
    if (record !== true && (bootScroll || Date.now() - visitAt < 4000)) return;
    var y = 0;
    try { y = Number(sessionStorage.getItem(SCROLL + location.search) || 0); } catch (e) {}
    if (!y) return;
    // The content arrives after the call, so try now and again once it has.
    window.scrollTo(0, y);
    setTimeout(function () { window.scrollTo(0, y); }, 260);
  }

  function restoreView() {
    var params = new URLSearchParams(location.search);
    // Read the address before anything writes to it: showSection rewrites the
    // address from state, and state does not know about these yet.
    var clientId = params.get('client');
    var setId = params.get('set');
    /* A client's address carries no `s=` (Clients writes none), so it is read
       as Clients before the landing page is asked: a refresh inside a record
       stays inside it (2026-09-28). */
    var where = params.get('s') || (params.get('client') ? 'clients' : firstAllowed());
    if (!SECTION_TITLE[where]) where = firstAllowed();

    if (where !== 'review') {
      // Content Review still needs its list painted for when they come back.
      $('clientsView').hidden = false;
      loadClients();
      showSection(where);
      return;
    }

    showSection('review');
    if (!clientId) { showClients(); return; }

    var place = readPlace();
    var samePlace = place && place.client === clientId;
    if (samePlace) pendingScroll = place.y || 0;

    clientByKey(clientId, function (c) {
      if (!c) { showClients(); return; }
      openClient(c);
      if (samePlace && place.drawer) openDrawer(true);
      if (!setId) return;
      db.from('batches').select('*').eq('id', setId).single().then(function (bt) {
        if (!bt.error && bt.data) openBatch(bt.data, true);
      });
    });
  }

  // ---- Clients ------------------------------------------------------------
  function showClients() {
    $('clientsView').hidden = false;
    $('workspace').hidden = true;
    state.client = null; state.batch = null;
    setUrl();
    loadClients();
  }

  /* Only active clients belong here. The CRM also holds leads and past
     clients, and none of those have content to review. A client removed from
     this section stays a client; they are simply not listed here. */
  /* Loading, empty and failed are said one way across the console. */
  var UI = window.ADspaceState;
  var skeleton = UI.skeleton, failLine = UI.failLine;

  var crFind = '';
  function loadClients() {
    var box = $('clientCards');
    if (!state.reviewClients) skeleton(box, 3);
    db.from('clients').select(API.CLIENT_COLS).eq('stage', 'active').eq('review_hidden', false)
      .order('name').then(function (r) {
      if (r.error) {
        state.reviewClients = null;
        failLine(box, 'Clients', r.error.message, loadClients);
        settleScroll();
        return;
      }
      state.reviewClients = r.data || [];
      state.reviewSets = null;
      paintReviewClients();
      settleScroll();
      readSets(state.reviewClients);
    });
  }

  /* Every client's sets in one read for the whole list, in pages of a
     thousand. A read a client, again on every paint and every key typed in
     the search, was a sixth of the portal's API traffic (2026-10-09). */
  function readSets(list) {
    var ids = list.map(function (c) { return c.id; });
    var got = [];
    function page(from) {
      db.from('batches').select('id, client_id, published').in('client_id', ids)
        .order('id').range(from, from + 999).then(function (b) {
        if (state.reviewClients !== list) return;
        if (b.error) { state.reviewSets = 'error'; paintSets(); return; }
        got = got.concat(b.data || []);
        if ((b.data || []).length === 1000 && from < 19000) { page(from + 1000); return; }
        var m = {};
        got.forEach(function (x) {
          var k = m[x.client_id] || (m[x.client_id] = { n: 0, live: 0 });
          k.n++; if (x.published) k.live++;
        });
        state.reviewSets = m;
        paintSets();
      }).catch(function () {
        if (state.reviewClients !== list) return;
        state.reviewSets = 'error'; paintSets();
      });
    }
    if (ids.length) page(0); else state.reviewSets = {};
  }

  /* A one line answer to "where does this client stand?" A read that failed
     is not a client with nothing on it: "No content sets" over a fault sends
     somebody to build a set that is already there. */
  function setsLine(id) {
    var s = state.reviewSets;
    if (!s) return '<span class="muted">Loading…</span>';
    if (s === 'error') return '<span class="is-warn">Sets unavailable</span>';
    var k = s[id];
    if (!k) return '<span class="muted">No sets</span>';
    return esc(k.n + ' set' + (k.n === 1 ? '' : 's') + ' · ' + k.live + ' published');
  }
  function paintSets() {
    var box = $('clientCards');
    Array.prototype.forEach.call(box.querySelectorAll('.cr-client-row[data-id]'), function (row) {
      var sub = row.querySelector('[data-role="sub"]');
      if (sub) sub.innerHTML = setsLine(row.getAttribute('data-id'));
    });
  }

  function paintReviewClients() {
    var box = $('clientCards');
    var all = state.reviewClients || [];
    var rows = !crFind ? all : all.filter(function (c) {
      return String(c.name || '').toLowerCase().indexOf(crFind) >= 0;
    });
    var count = $('crCount');
    if (count) {
      count.textContent = !all.length ? ''
        : rows.length === all.length ? all.length + (all.length === 1 ? ' client' : ' clients')
        : rows.length + ' of ' + all.length;
    }
    box.innerHTML = '';
    if (!all.length) { UI.emptyLine(box, 'No active clients.'); return; }
    if (!rows.length) {
      UI.emptyLine(box, 'No matches.', 'Clear the search', function () {
        crFind = ''; if ($('crFind')) $('crFind').value = ''; paintReviewClients();
      });
      return;
    }
    /* One register, not a grid of tiles, drawn as the one directory shape
       every console route takes: a heading with the count over a card with
       its own header row. A card per client answered "which clients are
       there" and nothing else; a tile cannot be read down a column. */
    var GRP = window.ADspaceGroup;
    var table = GRP.table('cr-client-row', ['Client', 'Content sets', 'Access', ''], 'crm-register');
    var sec = GRP.section({
      route: 'review', key: 'clients', name: 'Clients', count: rows.length,
      shut: false, table: function () { return table; }
    });

    rows.forEach(function (c) {
      var row = document.createElement('button');
      row.type = 'button';
      row.className = 'crm-row cr-client-row';
      row.setAttribute('data-id', c.id);
      row.innerHTML =
        '<span class="crm-c crm-c-name">' + esc(c.name) + '</span>' +
        '<span class="crm-c crm-c-sets" data-role="sub">' + setsLine(c.id) + '</span>' +
        /* An access code is the exception, so the row says nothing where there
           is none rather than printing "Open" on almost every line. */
        '<span class="crm-c crm-c-code">' + (c.passcode
          ? '<span class="tone">Access code</span>' : '<span class="muted">\u2014</span>') + '</span>' +
        '<span class="crm-c crm-c-go" aria-hidden="true">' + GO_CHEV + '</span>';
      row.addEventListener('click', function () { openClient(c); });
      table.appendChild(row);
    });
    box.appendChild(sec);
  }

  var GO_CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18l6-6-6-6"/></svg>';

  if ($('crFind')) $('crFind').addEventListener('input', function () {
    crFind = this.value.trim().toLowerCase();
    paintReviewClients();
  });

  /* Label, tone, and which section of the portal the action belongs to, so the
     record can be filtered the way the sidebar is. */
  var ACTION_LABEL = {
    /* A deleted task takes its own events with it, so the only record of the
       deletion is here. Filed under My Work, which is the section it is about. */
    'ops.deleted':           ['Task deleted', 'is-danger', 'ops'],
    'ops.month_deleted':     ['Month deleted', 'is-danger', 'ops'],
    /* An admin setting the next task number. */
    'ops.numbering':         ['Numbering changed', '', 'ops'],
    'client.added':          ['Client added', 'is-ok', 'clients'],
    'team.added':            ['Team member added', 'is-ok', 'team'],
    'team.changed':          ['Access changed', 'is-warn', 'team'],
    'team.edited':           ['Team member edited', '', 'team'],
    'team.invited':          ['Invitation sent', '', 'team'],
    'team.group_added':      ['User group added', 'is-ok', 'team'],
    'team.group_changed':    ['User group changed', 'is-warn', 'team'],
    'team.group_removed':    ['User group removed', 'is-danger', 'team'],
    'client.removed':        ['Client removed', 'is-danger', 'review'],
    'client.deleted':        ['Client deleted', 'is-danger', 'clients'],
    'review.removed':        ['Removed from review', 'is-warn', 'review'],
    'client.edited':         ['Client edited', '', 'clients'],
    'client.stage':          ['Stage changed', '', 'clients'],
    'client.billing':        ['Billing updated', '', 'clients'],
    'client.brand':          ['Brand updated', '', 'clients'],
    'client.service':        ['Service added', 'is-ok', 'clients'],
    'client.service_changed': ['Service changed', '', 'clients'],
    'client.service_removed': ['Service removed', 'is-danger', 'clients'],
    'client.service_restored': ['Service restored', 'is-ok', 'clients'],
    'report.created':        ['Report started', 'is-ok', 'reports'],
    'report.submitted':      ['Report submitted', '', 'reports'],
    'report.returned':       ['Report returned', 'is-warn', 'reports'],
    'report.reassigned':     ['Reviewer changed', '', 'reports'],
    'report.confirmed':      ['Report confirmed', 'is-ok', 'reports'],
    'report.published':      ['Report published', 'is-ok', 'reports'],
    'report.revised':        ['Report revised', '', 'reports'],
    'report.unpublished':    ['Report unpublished', 'is-warn', 'reports'],
    'report.deleted':        ['Report deleted', 'is-danger', 'reports'],
    /* Every save and every Draft with AI, filed by the page (2026-10-01). */
    'report.saved':          ['Report saved', '', 'reports'],
    /* The Handbook (2026-10-01): its files and their versions. */
    'handbook.added':        ['File added', 'is-ok', 'handbook'],
    'handbook.edited':       ['File edited', '', 'handbook'],
    'handbook.version':      ['New version', '', 'handbook'],
    'handbook.archived':     ['File archived', 'is-warn', 'handbook'],
    'handbook.restored':     ['File restored', '', 'handbook'],
    'handbook.deleted':      ['File deleted', 'is-danger', 'handbook'],
    /* Video Scripts (2026-10-09): written, shared, decided by the client,
       ticked on the day. */
    'script.created':        ['Script started', 'is-ok', 'scripts'],
    'script.saved':          ['Script saved', '', 'scripts'],
    'script.shared':         ['Script published', 'is-ok', 'scripts'],
    'script.unshared':       ['Script unpublished', 'is-warn', 'scripts'],
    'script.approved':       ['Script approved', 'is-ok', 'scripts'],
    'script.changes':        ['Changes requested', 'is-warn', 'scripts'],
    'script.shot':           ['Scene shot', '', 'scripts'],
    'script.link':           ['Script link reset', 'is-warn', 'scripts'],
    'script.deleted':        ['Script deleted', 'is-danger', 'scripts'],
    'report.ai_drafted':     ['AI used', '', 'reports'],
    'report.ai_failed':      ['AI failed', 'is-warn', 'reports'],
    /* The Report audit's reading of Meta (2026-10-09), filed by the database. */
    'report.audited':        ['Report audit', '', 'reports'],
    'document.issued':       ['Document issued', 'is-ok', 'register'],
    'document.voided':       ['Document voided', 'is-danger', 'register'],
    'document.restored':     ['Document restored', 'is-ok', 'register'],
    'document.deleted':      ['Document deleted', 'is-danger', 'register'],
    'document.reissued':     ['Document reissued', '', 'register'],
    'register.added':        ['Document added', 'is-ok', 'register'],
    'register.edited':       ['Document edited', '', 'register'],
    'service.added':         ['Rate line added', 'is-ok', 'services'],
    'service.changed':       ['Rate line changed', '', 'services'],
    'service.off':           ['Rate line inactive', 'is-warn', 'services'],
    'service.on':            ['Rate line active', 'is-ok', 'services'],
    'service.deleted':       ['Rate line deleted', 'is-danger', 'services'],
    'client.touch':          ['Call/visit logged', '', 'clients'],
    /* WhatsApp (2026-10-10): a message sent by hand, and a purpose's
       template chosen or switched. */
    'wa.sent':               ['Sent on WhatsApp', '', 'whatsapp'],
    'wa.template':           ['Template changed', '', 'whatsapp'],
    'client.review_on':      ['Added to review', 'is-ok', 'clients'],
    'contact.portal_on':     ['Portal enabled', 'is-ok', 'clients'],
    'contact.portal_off':    ['Portal revoked', 'is-warn', 'clients'],
    'contact.portal_invite': ['Invitation sent', '', 'clients'],
    'contact.deleted':       ['Contact deleted', 'is-danger', 'clients'],
    'request.raised':        ['Request raised', 'is-warn', 'clients'],
    'request.changed':       ['Request changed', '', 'clients'],
    'request.replied':       ['Request replied', '', 'clients'],
    'contact.added':         ['Contact added', 'is-ok', 'clients'],
    'contact.edited':        ['Contact edited', '', 'clients'],
    'contact.restored':      ['Contact restored', 'is-ok', 'clients'],
    'client.touch_edited':   ['Call/visit edited', '', 'clients'],
    'client.touch_removed':  ['Call/visit removed', 'is-warn', 'clients'],
    'client.touch_deleted':  ['Call/visit deleted', 'is-danger', 'clients'],
    'client.touch_restored': ['Call/visit restored', 'is-ok', 'clients'],
    'client.action_done':    ['Action done', 'is-ok', 'clients'],
    'client.action_reopened':['Action reopened', 'is-warn', 'clients'],
    'contact.primary':       ['Main contact set', '', 'clients'],
    'contact.removed':       ['Contact removed', 'is-danger', 'clients'],
    'set.deleted':           ['Content set deleted', 'is-danger', 'review'],
    'post.deleted':          ['Post deleted', 'is-danger', 'review'],
    'set.published':         ['Published', 'is-ok', 'review'],
    'set.withdrawn':         ['Unpublished', 'is-warn', 'review'],
    'link.reset':            ['Access link reset', 'is-warn', 'review'],
    'reapproval.requested':  ['Resent for approval', 'is-warn', 'review'],
    /* What a client and a creator did, not only what we did. The record is
       what answers a dispute, and it held one side of every conversation:
       a client approved a post and the portal kept the verdict in `reviews`
       alone, which no screen reads as a history. These carry the name the
       person typed as the actor, so the row says who, what and when. */
    'review.approved':       ['Approved', 'is-ok', 'review'],
    'review.unconfirmed':    ['Confirmation reverted', 'is-warn', 'review'],
    'review.changes':        ['Changes requested', 'is-warn', 'review'],
    'request.withdrawn':     ['Request withdrawn', 'is-warn', 'clients'],
    'request.reinstated':    ['Request reinstated', '', 'clients'],
    // Short links. Named apart from link.reset above, which is the client's
    // access link and a different thing entirely.
    'shortlink.created':     ['Link created', 'is-ok', 'links'],
    'shortlink.updated':     ['Link changed', 'is-warn', 'links'],
    'shortlink.deleted':     ['Link deleted', 'is-danger', 'links'],
    'shortlink.imported':    ['Links imported', 'is-ok', 'links'],
    // Creator campaigns and the creators list behind them.
    'campaign.created':      ['Campaign created', 'is-ok', 'campaigns'],
    'campaign.edited':       ['Campaign edited', '', 'campaigns'],
    'campaign.opened':       ['Published', 'is-ok', 'campaigns'],
    'campaign.closed':       ['Unpublished', 'is-warn', 'campaigns'],
    'campaign.deleted':      ['Campaign deleted', 'is-danger', 'campaigns'],
    'campaign.locked':       ['Selection accepted', 'is-ok', 'campaigns'],
    'campaign.keyed':        ['Picked for client', '', 'campaigns'],
    'campaign.unkeyed':      ['Selection undone', 'is-warn', 'campaigns'],
    'campaign.rate':         ['Rate changed', 'is-warn', 'campaigns'],
    'campaign.stage':        ['Stage changed', '', 'campaigns'],
    'campaign.task_linked':  ['Task linked', '', 'campaigns'],
    'campaign.task_unlinked': ['Task unlinked', '', 'campaigns'],
    'campaign.unbooked':     ['Back to options', 'is-warn', 'campaigns'],
    'campaign.withdrawn':    ['Creator withdrawn', 'is-danger', 'campaigns'],
    'campaign.whatsapp':     ['Sent on WhatsApp', '', 'campaigns'],
    'campaign.confirmed':    ['Selection confirmed', 'is-ok', 'campaigns'],
    'campaign.submitted':    ['Draft submitted', '', 'campaigns'],
    'campaign.rated':        ['Booking rated', '', 'campaigns'],
    'campaign.replaced':     ['Creator replaced', 'is-danger', 'campaigns'],
    'campaign.reinstated':   ['Creator reinstated', 'is-ok', 'campaigns'],
    'campaign.invoice':      ['Invoice no. set', '', 'campaigns'],
    'campaign.invoice_file': ['Invoice uploaded', 'is-ok', 'campaigns'],
    'campaign.invoice_removed': ['Invoice removed', 'is-warn', 'campaigns'],
    'campaign.bulk':         ['Dates applied', '', 'campaigns'],
    'campaign.dates':        ['Schedule updated', '', 'campaigns'],
    'creator.added':         ['Creator added', 'is-ok', 'campaigns'],
    'creator.updated':       ['Creator edited', '', 'campaigns'],
    'creator.removed':       ['Creator removed', 'is-danger', 'campaigns'],
    'creator.off':           ['Creator inactive', 'is-warn', 'campaigns'],
    'creator.on':            ['Creator active', 'is-ok', 'campaigns'],
    'creator.links':         ['Links updated', '', 'campaigns'],
    'creator.links_self':    ['Creator updated links', 'is-warn', 'campaigns'],
    'creator.links_restored': ['Links restored', 'is-ok', 'campaigns'],
    'creator.code':          ['Portal link reset', 'is-warn', 'campaigns'],
    /* Written for months and never named here, so each row landed in the
       record with no label and no section: a tag a function writes is
       always one this map names. */
    'qr.created':            ['QR code created', 'is-ok', 'links'],
    'qr.revoked':            ['QR code revoked', 'is-warn', 'links'],
    'qr.restored':           ['QR code restored', 'is-ok', 'links'],
    'document.signed':       ['Letter signed', 'is-ok', 'register'],
    'document.unsigned':     ['Signature cleared', 'is-warn', 'register'],
    'document.verified':     ['Letter verified', 'is-ok', 'register'],
    'document.superseded':   ['Letter superseded', 'is-warn', 'register'],
    'campaign.review':       ['Draft reviewed', '', 'campaigns'],
    'campaign.results':      ['Results entered', '', 'campaigns'],
    'service.override':      ['Price overridden', 'is-warn', 'clients'],
    /* Content Review wrote nothing for the everyday acts on a set. */
    'set.created':           ['Set created', 'is-ok', 'review'],
    'set.renamed':           ['Set renamed', '', 'review'],
    'set.month':             ['Content month changed', '', 'review'],
    'set.task_linked':       ['Task linked', '', 'review'],
    'set.task_unlinked':     ['Task unlinked', '', 'review'],
    'post.added':            ['Posts added', 'is-ok', 'review'],
    'post.edited':           ['Post edited', '', 'review'],
    'client.handles':        ['Handles updated', '', 'review'],
    'client.profile':        ['Settings updated', '', 'review'],
    'client.drive':          ['Drive folder set', '', 'review'],
    'drive.imported':        ['Drive imported', 'is-ok', 'review'],
    /* A file the team handed in for a creator, from the console. */
    'campaign.file_added':   ['Draft uploaded', '', 'campaigns'],
    'campaign.file_hidden':  ['File hidden from the client', '', 'campaigns'],
    'campaign.file_shown':   ['File restored for the client', '', 'campaigns'],
    'campaign.file_deleted': ['Approved file deleted', '', 'campaigns'],
    'campaign.qc':           ['Quality checked', '', 'campaigns']
  };
  /* The same order as the rail, because they are the same eight sections and
     a person who has learned one sequence should not have to learn a second.
     Everything leads, being the view somebody lands on. */
  var ACT_SECTION = { all: 'Everything',
                      ops: 'My Work', clients: 'Clients',
                      review: 'Content Review', scripts: 'Video Scripts', campaigns: 'Creator Campaigns',
                      reports: 'Reports', whatsapp: 'WhatsApp', register: 'Documents', links: 'Short Links',
                      services: 'Services', team: 'Team', performance: 'Performance', handbook: 'Handbook' };
  /* The steps of a review, read through perf_activity(): when, the step,
     whose month, who. Never a score, a grade or a dispute's words. */
  var PERF_STEP = { released: 'Review shared', disputed: 'Query raised', decided: 'Query answered',
                    acknowledged: 'Review acknowledged', finalised: 'Review finalised', reopened: 'Review reopened',
                    returned: 'Reverted to draft', printed: 'Record downloaded', deleted: 'Record deleted',
                    opened: 'Review opened', 'self.saved': 'Self-rating saved' };

  /* The section only appears for people on the viewer list. The database
     enforces this too, so hiding it here is convenience rather than the
     control itself. */
  var maySeeActivity = false;

  function gateActivity() {
    /* The record has parts now, so a group may hold none of the section and
       one of its tabs: the link is drawn where any tab is readable, and the
       tabs themselves draw where their own part is. */
    maySeeActivity = may('activity', 'view') || may('team.performance', 'view') || PARTS.activity.some(function (k) {
      return may('activity.' + k, 'view');
    });
    showActivityLink();
  }

  /* The record covers the whole portal, not one section of it, so it is
     offered wherever you are. Hiding it is convenience; the database is what
     actually refuses. */
  function showActivityLink() {
    $('activityOpen').hidden = !maySeeActivity;
    if ($('settingsOpen')) $('settingsOpen').hidden = !(meLoaded && sectionAllowed('settings'));
    if (meLoaded) paintTabbar();
  }

  /* The build this console is running, at the rail's foot: the
     deploy's day in Malaysia, short (v26.10.06; the user, 2026-10-06).
     /version.json is written by the Pages build itself; read raw (no build
     ran) or not at all, the line stays hidden. */
  function showVersion() {
    var box = $('appVersion');
    if (!box || !window.fetch) return;
    fetch('/version.json', { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (v) {
      if (!v || /[{}%]/.test(v.commit + v.built)) return;
      var at = new Date(v.built);
      if (isNaN(at)) return;
      var sha = String(v.commit || '').slice(0, 7);
      box.textContent = 'v' + new Date(at.getTime() + 8 * 3600000).toISOString().slice(2, 10).replace(/-/g, '.')
        + (/^[0-9a-f]{7}$/.test(sha) ? ' · ' + sha : '');
      box.hidden = false;
    }).catch(function () {});
  }
  showVersion();

  function shutActivity() { $('activitySheet').hidden = true; }

  if ($('settingsOpen')) $('settingsOpen').addEventListener('click', function () {
    if (rail && rail.isOpen && rail.isOpen()) rail.shut();
    visitSection('settings');
  });
  $('activityOpen').addEventListener('click', function () {
    $('activitySheet').hidden = false;
    loadActivity();
  });
  $('activityClose').addEventListener('click', shutActivity);
  $('activitySheet').addEventListener('click', function (e) {
    if (e.target === $('activitySheet')) shutActivity();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') shutActivity();
  });

  /* Filtered by section and grouped by day. Sixty rows in one unbroken column
     was a scroll with no landmarks in it; a date heading gives the eye
     somewhere to stop, and the tabs answer "what happened in campaigns" without
     reading past everything else. */
  var actFilter = 'all';
  var actRows = [];

  function sectionOf(action) { return (ACTION_LABEL[action] || [])[2] || 'other'; }
  function sectionOfRow(a) { return a._section || sectionOf(a.action); }
  function monthLong(p) {
    var d = new Date(String(p).slice(0, 7) + '-01T00:00:00');
    return isNaN(d) ? String(p) : d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  }

  function paintActivity() {
    var box = $('activityList');
    var rows = actRows.filter(function (a) {
      return actFilter === 'all' || sectionOfRow(a) === actFilter;
    });
    Array.prototype.forEach.call($('activityTabs').children, function (b) {
      var on = b.getAttribute('data-af') === actFilter;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-pressed', String(on));
    });
    if (!rows.length) {
      box.innerHTML = '<div class="empty">Nothing recorded' +
        (actFilter === 'all' ? '' : ' in ' + ACT_SECTION[actFilter]) + '.</div>';
      return;
    }
    /* One line an entry, a heading a day, runs folded (js/records.js). */
    window.ADspaceRecords.paint(box, rows.map(recordOf));
  }
  /* A tag that is read on its own is never folded into the entry beside it:
     Performance, an HR document, a void or a delete, billing, money and
     access. */
  var STICKY = /deleted|voided|removed|billing|\.rate$|invoice|team\.changed|group_|numbering|withdrawn|replaced/;
  /* A client's decision on a draft and a creator's hand-in are each read on
     their own: three change requests sent in one minute were one line with
     three notes joined (the user, 2026-09-27: "combined is hard to read"). */
  var OWN_LINE = /^campaign\.(review|submitted)$/;
  function stickyOf(a) {
    return a._section === 'performance' || a.subject === 'HR' || STICKY.test(a.action || '') ||
      OWN_LINE.test(a.action || '');
  }
  /* What a line is about, for the fold: its subject, and for a document its
     reference as well, because one client holds many documents and the
     subject alone folded three references into one line (2026-09-27). */
  function keyOf(a) {
    var act = a.action || '';
    if (BOOKING.test(act)) {
      /* A booking's line names its creator first ("恩比 · back to …"), and
         one campaign holds many creators: the fold keys on both. */
      var who = String(a.detail || '').split(' \u00b7 ')[0].trim();
      return (a.subject || '') + '|' + who;
    }
    if (!/^(register|document)\./.test(act)) return null;
    var ref = String(a.detail || '').split(/ \u00b7 |: /)[0].trim();
    return (a.subject || '') + '|' + ref;
  }
  var BOOKING = /^campaign\.(stage|file_added|qc|dates|unbooked|reinstated|keyed|unkeyed|review)$/;
  /* Words the first row already says are not said again on the second:
     "quality checked by Qiao Rou" under Qiao Rou's Quality checked, and
     "schedule updated" under Schedule updated. Read off rows written before
     the words were dropped as well. */
  function detailOf(a) {
    var d = String(a.detail || '');
    if (a.action === 'campaign.qc') d = d.replace(/ \u00b7 quality checked by [^\u00b7]*?(?= \u00b7 |$)/, '');
    if (a.action === 'campaign.dates') d = d.replace(/ \u00b7 schedule updated$/, '');
    return d;
  }
  function recordOf(a) {
    var meta = a._section === 'performance' ? [PERF_STEP[a.kind] || a.kind, ''] : (ACTION_LABEL[a.action] || [String(a.action || '').replace(/[._]/g, ' '), '']);
    var detail = detailOf(a), lead = '', rest = detail;
    /* A booking's entry names its creator first; where the page is the
       campaign's own, the creator is what the entry is about (`lead`), and
       the rest is what changed. */
    if (BOOKING.test(a.action || '')) {
      var parts = detail.split(' \u00b7 ');
      lead = parts[0]; rest = parts.slice(1).join(' \u00b7 ');
    }
    return { at: a.created_at, who: a._who || whoName(a.actor) || 'System', what: meta[0], on: a.subject || '',
             key: keyOf(a), detail: detail, lead: lead, rest: rest,
             tone: meta[1] === 'is-danger' ? 'is-danger' : '', sticky: stickyOf(a) };
  }

  Array.prototype.forEach.call($('activityTabs').children, function (b) {
    b.addEventListener('click', function () {
      actFilter = b.getAttribute('data-af');
      paintActivity();
    });
  });

  function loadActivity() {
    var box = $('activityList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    // Opening it from a section starts on that section, since that is almost
    // always what the question was about.
    actFilter = ACT_SECTION[section] ? section : 'all';
    /* Performance's steps come from their own function, read only where the
       part is held, and join the rest by time. A refused or missing read of
       them leaves the other sections as they are. */
    var perf = may('team.performance', 'view')
      ? db.rpc('perf_activity', { p_limit: 200 }).then(function (r) {
          var d = (r && r.data) || {};
          return (r && r.error) || d.error ? [] : (d.rows || []).map(function (x) {
            return { created_at: x.at, kind: x.kind, _section: 'performance',
                     _who: x.actor_name || x.actor || (x.auto ? 'Automatic' : ''),
                     subject: [x.member, x.period ? monthLong(x.period) : ''].filter(Boolean).join(' · '), detail: '' };
          });
        }, function () { return []; })
      : Promise.resolve([]);
    Promise.all([db.from('activity_log').select('*').order('created_at', { ascending: false }).limit(200), perf])
      .then(function (both) {
        var r = both[0], pr = both[1] || [];
        if (r.error && !pr.length) {
          box.innerHTML = '<div class="empty">Access denied.</div>';
          return;
        }
        actRows = ((r.error ? [] : r.data) || []).concat(pr).sort(function (x, y) {
          return String(y.created_at).localeCompare(String(x.created_at));
        });
        paintActivity();
      });
  }

  /* Creating a client used to happen here, and separately inside Creator
     Campaigns, so the same company could be entered twice with neither place
     owning the record. A client is a company and belongs to the CRM; this
     section publishes their deliverables. */
  $('goToCrm').addEventListener('click', function () { showSection('clients'); });

  function openClient(c) {
    state.client = c;
    state.batch = null;
    $('clientsView').hidden = true;
    $('workspace').hidden = false;
    $('workspace').classList.remove('is-set');
    $('setPanel').hidden = true;
    paintHead(c);
    msg('wsMsg', '');

    var url = reviewUrl(c);
    $('clientLink').value = url;
    $('openLink').href = url;
    openDrawer(false);
    fillProfile(c);
    /* The handles and the logo are the client record's too (Brand profile
       edits the same columns), and the row in this list was read when the
       list was, so a logo changed on the record since then would show here
       stale and a save would write the old one back (reported 2026-09-26:
       "why do i have to update both sides"). The row is read again on open,
       and a field somebody has already changed is left as they typed it. */
    var before = { ig: c.handle_ig, fb: c.handle_fb, tt: c.handle_tiktok, xhs: c.handle_xhs, logo: c.logo_url, pass: c.passcode };
    db.from('clients').select(API.CLIENT_COLS).eq('id', c.id).single().then(function (r) {
      if (!r || r.error || !r.data || state.client !== c) return;
      Object.assign(c, r.data);
      fillProfile(c, before);
      paintHead(c);
    }, function () {});
    msg('handleMsg', '');
    msg('profileMsg', '');
    setUrl();
    loadBatches();
    if (!pendingScroll) window.scrollTo(0, 0);
  }

  /* The profile fields from the row. With `was`, a field is only refilled
     while it still holds what it was filled with, so a fresh read never
     throws away what somebody has typed. */
  function fillProfile(c, was) {
    var map = [['eIg', 'handle_ig', 'ig'], ['eFb', 'handle_fb', 'fb'], ['eTt', 'handle_tiktok', 'tt'],
               ['eXhs', 'handle_xhs', 'xhs'], ['eLogo', 'logo_url', 'logo'], ['ePass', 'passcode', 'pass']];
    map.forEach(function (m) {
      var el = $(m[0]);
      if (!el) return;
      if (was && el.value !== (was[m[2]] || '')) return;
      el.value = c[m[1]] || '';
    });
    paintLogo();
    paintLock();
  }

  /* Back from a set is the client; back from the client is the list. */
  $('backToClients').addEventListener('click', function () {
    if (state.batch) closeBatch(); else showClients();
  });
  function closeBatch() {
    state.batch = null;
    $('setPanel').hidden = true;
    $('workspace').classList.remove('is-set');
    if (window.ADspaceSheet.isOpen($('assetSheet'))) window.ADspaceSheet.close();
    setUrl();
    loadBatches();
    window.scrollTo(0, 0);
  }

  /* The client's settings are a sheet from the head's ⋯ (2026-09-28), where
     they were a fold that opened forms in the middle of the page. */
  function openDrawer(open) {
    var sh = $('crSettingsSheet');
    if (open) { msg('handleMsg', ''); msg('profileMsg', ''); window.ADspaceSheet.show(sh, { opener: $('wsMenuBtn') }); }
    else if (window.ADspaceSheet.isOpen(sh)) window.ADspaceSheet.close();
  }

  $('advancedToggle').addEventListener('click', function () { shutWsMenu(); openDrawer(true); });
  $('crSettingsCancel').addEventListener('click', function () { openDrawer(false); });
  $('crSettingsClose').addEventListener('click', function () { openDrawer(false); });
  /* One Save for both groups; the sheet shuts once both have saved, and a
     refusal keeps it open with the refusal under its group. */
  $('crSettingsSave').addEventListener('click', function () {
    var btn = this, left = 2, ok = true;
    btn.disabled = true;
    var one = function (fine) {
      ok = ok && fine;
      if (--left) return;
      btn.disabled = false;
      if (!ok) return;
      openDrawer(false);
      msg('wsMsg', 'Saved.', 'ok');
    };
    saveHandles(one); saveProfile(one);
  });

  /* The head's ⋯: Client settings, Reset access link, Remove. */
  function shutWsMenu() {
    $('wsMenu').hidden = true;
    $('wsMenuBtn').setAttribute('aria-expanded', 'false');
  }
  $('wsMenuBtn').addEventListener('click', function (e) {
    e.stopPropagation();
    var open = $('wsMenu').hidden;
    shutWsMenu();
    if (!open) return;
    $('wsMenu').hidden = false;
    this.setAttribute('aria-expanded', 'true');
    window.ADspaceMenu.place(this, $('wsMenu'));
  });
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#wsMenu, #wsMenuBtn')) shutWsMenu();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('wsMenu').hidden) { shutWsMenu(); $('wsMenuBtn').focus(); }
  });
  window.ADspaceMenu.onScroll(shutWsMenu);

  /* The head: the client's logo or initials, the name, and their handles. */
  function paintHead(c) {
    var mark = $('wsMark');
    var initials = window.ADspaceState.initials(c.name);
    if (c.logo_url) {
      mark.className = 'rec-mark has-logo';
      mark.innerHTML = '<img src="' + esc(c.logo_url) + '" alt="">';
      mark.querySelector('img').addEventListener('error', function () {
        mark.className = 'rec-mark'; mark.textContent = initials;
      });
    } else { mark.className = 'rec-mark'; mark.textContent = initials; }
    $('wsClientName').textContent = c.name || '';
    $('wsMeta').textContent = [
      c.handle_ig ? 'Instagram @' + String(c.handle_ig).replace(/^@/, '') : '',
      c.handle_tiktok ? 'TikTok @' + String(c.handle_tiktok).replace(/^@/, '') : '',
      c.handle_fb ? 'Facebook ' + c.handle_fb : '',
      c.handle_xhs ? 'rednote ' + c.handle_xhs : ''
    ].filter(Boolean).join(' · ');
  }

  function saveHandles(done) {
    db.from('clients').update({
      handle_ig:     $('eIg').value.trim() || null,
      handle_fb:     $('eFb').value.trim() || null,
      handle_tiktok: $('eTt').value.trim() || null,
      handle_xhs:    $('eXhs').value.trim() || null
    }).eq('id', state.client.id).select('id').then(function (r) {
      if (r.error) { msg('handleMsg', r.error.message, 'err'); done(false); return; }
      if (!(r.data || []).length) { msg('handleMsg', 'Not saved. The database refused the request.', 'err'); done(false); return; }
      logAction('client.handles', state.client.name,
        ['ig', 'fb', 'tiktok', 'xhs'].map(function (k) {
          var v = $({ ig: 'eIg', fb: 'eFb', tiktok: 'eTt', xhs: 'eXhs' }[k]).value.trim();
          return v ? k + '=' + v : '';
        }).filter(Boolean).join(', '));
      state.client.handle_ig = $('eIg').value.trim() || null;
      state.client.handle_fb = $('eFb').value.trim() || null;
      state.client.handle_tiktok = $('eTt').value.trim() || null;
      state.client.handle_xhs = $('eXhs').value.trim() || null;
      paintHead(state.client);
      msg('handleMsg', 'Saved.', 'ok');
      done(true);
    });
  }

  /* Shows the address as a circle, the way every platform will, and says so
     when the file is not square. Nothing is ever skewed: a wide mark either
     loses its ends to a crop or sits small inside the circle, and neither is
     what the client's real profile looks like. The fix is a square file, so
     the tool asks for one here rather than letting a mockup deliver the news. */
  var logoTimer = null;
  function paintLogo() {
    var url = $('eLogo').value.trim();
    var box = $('logoPreview');
    var img = $('logoPreviewImg');
    box.classList.toggle('is-empty', !url);
    if (!url) { img.hidden = true; img.removeAttribute('src'); msg('logoNote', ''); return; }
    if (!/^https:\/\//i.test(url)) { img.hidden = true; msg('logoNote', ''); return; }

    var probe = new Image();
    probe.onload = function () {
      img.src = url;
      img.hidden = false;
      var w = probe.naturalWidth, h = probe.naturalHeight;
      var square = w && h && Math.abs(w - h) / Math.max(w, h) < 0.02;
      if (square) {
        msg('logoNote', w + ' x ' + h + '. Square, so it fills the circle exactly.', 'ok');
      } else {
        msg('logoNote', w + ' x ' + h + '. Not square; it will appear small inside the circle. Use a square version.', 'warn');
      }
    };
    probe.onerror = function () {
      img.hidden = true;
      msg('logoNote', 'No image could be loaded from that address.', 'err');
    };
    probe.src = url;
  }

  $('eLogo').addEventListener('input', function () {
    clearTimeout(logoTimer);
    logoTimer = setTimeout(paintLogo, 400);
  });

  /* Whether the link needs a code is worth seeing without opening the drawer. */
  function paintLock() {
    $('wsLock').hidden = !state.client.passcode;
  }

  /* Logo and access code were set once at creation and then stuck. Both are
     editable here, and clearing either field removes it. */
  function saveProfile(done) {
    var logo = $('eLogo').value.trim();
    var pass = $('ePass').value.trim();
    if (logo && !/^https:\/\//i.test(logo)) {
      msg('profileMsg', 'The logo address needs to start with https://', 'err');
      done(false);
      return;
    }
    var had = Boolean(state.client.passcode);
    db.from('clients').update({ logo_url: logo || null, passcode: pass || null })
      .eq('id', state.client.id).select('id').then(function (r) {
        if (r.error) { msg('profileMsg', r.error.message, 'err'); done(false); return; }
        if (!(r.data || []).length) { msg('profileMsg', 'Not saved. The database refused the request.', 'err'); done(false); return; }
        logAction('client.profile', state.client.name,
          [(logo || null) !== (state.client.logo_url || null) ? 'logo changed' : '',
           !had && pass ? 'access code added' : had && !pass ? 'access code removed'
             : pass && pass !== state.client.passcode ? 'access code updated' : ''].filter(Boolean).join(', ') || 'no change');
        state.client.logo_url = logo || null;
        state.client.passcode = pass || null;
        paintLock();
        var note = !had && pass ? 'Access code added.'
                 : had && !pass ? 'Access code removed.'
                 : had && pass  ? 'Access code updated.'
                 : 'Saved.';
        msg('profileMsg', note, 'ok');
        if (!had && !pass) msg('profileMsg', logo ? 'Logo saved.' : 'Saved.', 'ok');
        paintHead(state.client);
        done(true);
      });
  }

  $('resetLink').addEventListener('click', function () {
    shutWsMenu();
    window.ADspaceConfirm.ask({
      title: 'Reset the review link',
      body: 'The current link for ' + state.client.name + ' stops working immediately. '
          + 'The new one has to be sent to the client.',
      go: 'Reset link',
      tone: 'warn'
    }, function () {
      var next = window.ADspaceAPI.accessToken();
      db.from('clients').update({ access_token: next }).eq('id', state.client.id)
        .select('id').then(function (r) {
          if (r.error) { msg('wsMsg', r.error.message, 'err'); return; }
          if (!(r.data || []).length) { msg('wsMsg', 'Not saved. The database refused the request.', 'err'); return; }
          logAction('link.reset', state.client.name, 'Previous link invalidated');
          state.client.access_token = next;
          var fresh = reviewUrl(state.client);
          $('clientLink').value = fresh;
          $('openLink').href = fresh;
          msg('wsMsg', 'New link issued. The previous link is no longer valid.', 'ok');
        });
    });
  });

  /* Deleting a client takes every set, post and approval with it, and two
     confirm boxes are two reflexes. It takes something typed instead.

     The code itself is never in this file. Anything here is served to the
     browser and readable by anyone who opens the page, so a code kept here
     would not be a code at all. It lives in the database, behind a table the
     browser cannot read, and the deletion runs as a function on the server
     that compares it there. This side only asks the question and passes the
     answer along; it never learns whether the answer was right until the
     server says so, and a browser that skipped the question outright would be
     refused all the same. */
  /* Remove takes the client off this list and closes their review link, and
     nothing else: every set, post and approval is kept (audit, 2026-10-03; it
     deleted them all, with no way back). Undo puts the client back at once,
     and Enable Content Review on the client's record does the same later,
     with the same link. The company, its contacts and its log stay in
     Clients, where they belong. */
  $('deleteClient').addEventListener('click', function () {
    shutWsMenu();
    var c = state.client;
    window.ADspaceConfirm.ask({
      title: 'Remove from Content Review',
      body: c.name + ' leaves this list and its review link stops opening. Every content set is kept.',
      go: 'Remove',
      tone: 'warn'
    }, function () {
      setReviewHidden(c, true, 'wsMsg', function () {
        showClients();
        undoHere(c.name + ' removed from Content Review.', function () {
          setReviewHidden(c, false, 'clientMsg', loadClients);
        }, $('clientMsg'));
      });
    });
  });
  /* One write for both ways, taking the row back: a refused update is a 204
     with nothing in it, and is named, never filed. */
  function setReviewHidden(c, hide, msgId, then) {
    db.from('clients').update({ review_hidden: hide }).eq('id', c.id).select('id').then(function (u) {
      if (u.error) { msg(msgId, u.error.message, 'err'); return; }
      if (!u.data || !u.data.length) { msg(msgId, 'Not saved. The database refused the request.', 'err'); return; }
      c.review_hidden = hide;
      logAction(hide ? 'review.removed' : 'client.review_on', c.name, '');
      then();
    }).catch(function (e) { msg(msgId, (e && e.message) || String(e), 'err'); });
  }
  /* The way back, drawn where the act lands: one line and Undo, eight
     seconds, under `host`. */
  var undoTimer = null;
  function undoHere(text, undo, host) {
    if (!host || !host.parentNode) return;
    var bar = host.parentNode.querySelector(':scope > .undobar-here');
    if (!bar) {
      bar = document.createElement('div');
      bar.className = 'undobar undobar-here';
      host.parentNode.insertBefore(bar, host.nextSibling);
    }
    var shut = function () { if (bar.parentNode) bar.parentNode.removeChild(bar); };
    bar.innerHTML = '<span>' + esc(text) + '</span><button class="btn btn-sm" type="button">Undo</button>';
    bar.querySelector('button').addEventListener('click', function () { clearTimeout(undoTimer); shut(); undo(); });
    clearTimeout(undoTimer);
    undoTimer = setTimeout(shut, 8000);
  }

  $('copyLink').addEventListener('click', function () {
    window.ADspaceCopy.to(this, $('clientLink').value);
  });

  /* ---- Write caption (2026-10-08) ------------------------------------------
     Beside a post's caption fields (Add assets, and a saved post's Edit), at
     Content Review: Sets at Work. A short question first: the main language
     (the main contact's preferred one), 中文 (on where the set or the post
     holds Chinese), XHS Safe Mode on a rednote post (off until ticked: the
     user applies it only when confirmed) and notes (kept in this browser,
     else the brief of a task naming the set). The caption-draft function's
     words go into the fields; nothing is saved until the post's own Save,
     and Undo puts the earlier words back. */
  var CAP_SAID = {
    'needs-update': 'This needs a database update.',
    'ai-not-set-up': 'AI needs its key in Supabase.',
    'ai-key': 'The AI key was refused. Check it in Supabase.',
    'ai-busy': 'The AI service is busy. Try again in a minute.',
    'ai-credit': 'The AI account has no credit. Top up in the Claude Console.',
    'ai-model': 'The caption model name in Supabase is not recognised.',
    'ai-failed': 'No caption came back. Try again.',
    'ai-incomplete': 'No caption came back. Try again.',
    'denied': 'This needs Content Review: Sets at Manage.',
    'not-found': 'This set no longer exists.'
  };
  /* The caption's language, one choice (2026-10-10). */
  var CAP_LANGS = [['en', 'English'], ['ms', 'Bahasa Melayu'], ['zh', '中文'], ['en_zh', 'English and 中文']];
  var CAP_HANDLE = { instagram: 'handle_ig', facebook: 'handle_fb', tiktok: 'handle_tiktok', xhs: 'handle_xhs' };
  var capKnown = { lang: {}, brief: {} };
  var AI_GLYPH = (window.ADspaceConfirm && window.ADspaceConfirm.ai && window.ADspaceConfirm.ai.glyph) || '';
  function capIdle(b) { if (b) { b.disabled = false; b.innerHTML = AI_GLYPH + 'Write with AI'; } }
  function capButton() {
    return may('review.sets', 'work')
      ? '<div class="capwrite"><button class="btn btn-sm btn-icon" data-f="capwrite" type="button">' + AI_GLYPH + 'Write with AI</button></div>' +
        '<div class="msg capmsg" data-m="cap" role="status"></div>'
      : '';
  }
  function capClock(iso) {
    var at = new Date(iso);
    if (isNaN(at.getTime())) return '';
    return ((at.getHours() % 12) || 12) + ':' + String(at.getMinutes()).padStart(2, '0') + (at.getHours() < 12 ? 'am' : 'pm');
  }
  function capLimit(d) {
    d = d || {};
    if (d.scope === 'stopped' || d.limit === 0) return 'Captions with AI are turned off for you. An admin can turn them on.';
    return 'You have used your ' + (d.limit || 20) + ' captions for today.' + (d.next ? ' Resets at ' + capClock(d.next) + '.' : '');
  }
  function capNotes(key, v) {
    var k = 'adspace-caption-notes:' + key;
    try {
      if (v === undefined) return localStorage.getItem(k) || '';
      if (v) localStorage.setItem(k, v); else localStorage.removeItem(k);
    } catch (e) {}
    return '';
  }
  /* What the question opens with: the main contact's language, whether the
     set holds Chinese, and the brief of a task naming the set. Each read is
     its own; a refused one leaves its default. */
  function capPrefill(client, set) {
    var lang = capKnown.lang[client.id] != null ? Promise.resolve(capKnown.lang[client.id])
      : db.from('client_contacts').select('lang, is_primary').eq('client_id', client.id).is('archived_at', null).then(function (r) {
          var list = r.error ? [] : (r.data || []);
          var main = list.filter(function (x) { return x.is_primary; })[0] || list[0];
          return (capKnown.lang[client.id] = main && main.lang ? main.lang : 'en');
        }, function () { return 'en'; });
    var brief = capKnown.brief[set.id] != null ? Promise.resolve(capKnown.brief[set.id])
      : db.rpc('ops_record_tasks', { p_type: 'set', p_ref: set.id }).then(function (r) {
          var ids = (!r.error && Array.isArray(r.data) ? r.data : []).map(function (t) { return t.id; }).slice(0, 20);
          if (!ids.length) return (capKnown.brief[set.id] = '');
          return db.from('ops_tasks').select('id, description').in('id', ids).then(function (q) {
            var by = {};
            (q.error ? [] : (q.data || [])).forEach(function (t) { by[t.id] = String(t.description || '').trim(); });
            return (capKnown.brief[set.id] = ids.map(function (id) { return by[id] || ''; }).filter(Boolean)[0] || '');
          });
        }).then(null, function () { return ''; });
    return Promise.all([lang, brief]).then(function (a) { return { lang: a[0], brief: a[1] }; });
  }
  /* `o`: { btn, placement, title, notesKey, now: { caption },
     put(words) → the row's .capwrite after the words are in the field }.
     One caption a post (the user, 2026-10-10: "one post only allowed one
     caption … make it as a language option"): the language is asked once,
     English and 中文 being one caption in both. */
  function writeCaption(o) {
    var client = state.client, set = state.batch;
    if (!client || !set || !may('review.sets', 'work')) return;
    var say = function (anchor, text, kind) {
      var m = anchor && anchor.parentNode && anchor.parentNode.querySelector('[data-m="cap"]');
      if (m) { m.textContent = text || ''; m.className = 'msg capmsg' + (kind ? ' ' + kind : ''); }
    };
    var wrapOf = function (b) { return b && b.closest('.capwrite'); };
    var plat = String(o.placement || 'instagram:feed').split(':')[0];
    var btn = o.btn;
    btn.disabled = true;
    say(wrapOf(btn), '');
    Promise.all([db.rpc('ai_caption_left'), capPrefill(client, set)]).then(function (a) {
      btn.disabled = false;
      var r = a[0], pre = a[1], left = r.data || {};
      if (r.error || left.error) {
        say(wrapOf(btn), r.error ? (/function|schema cache/i.test(r.error.message) ? CAP_SAID['needs-update'] : r.error.message)
          : (CAP_SAID[left.error] || left.error), 'err');
        return;
      }
      if (!left.left) { say(wrapOf(btn), capLimit(left), 'err'); return; }
      var had = !!String(o.now.caption || '').trim();
      var fields = [
        { name: 'lang', label: 'Caption language', choices: CAP_LANGS,
          value: ['en', 'ms', 'zh'].indexOf(pre.lang) > -1 ? pre.lang : 'en' }
      ];
      if (plat === 'xhs') fields.push({ name: 'safe', label: 'XHS Safe Mode', tick: true, value: false });
      fields.push({ name: 'notes', label: 'Notes for the caption', rows: 3, required: false,
        placeholder: 'What the post is about, the offer, the call to action',
        value: capNotes(o.notesKey) || pre.brief });
      window.ADspaceConfirm.ask({
        title: 'Write with AI',
        body: (had ? 'Replaces the words in the caption. ' : '') + left.left + (left.left === 1 ? ' caption' : ' captions') + ' left today.',
        go: 'Write', fields: fields
      }, function (v) {
        capNotes(o.notesKey, String(v.notes || '').trim());
        btn.disabled = true;
        btn.innerHTML = AI_GLYPH + 'Writing';
        var before = { caption: o.now.caption || '' };
        db.functions.invoke('caption-draft', { body: {
          set_id: set.id, placement: o.placement, title: o.title || '', notes: String(v.notes || '').trim(),
          lang: CAP_LANGS.some(function (x) { return x[0] === v.lang; }) ? v.lang : 'en', safe: plat === 'xhs' && v.safe === 'on'
        } }).then(function (res) {
          var d = res && res.data;
          if (res.error || !d || d.error || !d.draft) { var x = new Error((d && d.error) || 'ai-failed'); x.d = d; throw x; }
          /* {brand} and {handle} come back as written and are filled here. */
          var handle = String(client[CAP_HANDLE[plat]] || '').trim().replace(/^@/, '');
          var fill = function (t) {
            return String(t || '').replace(/\{\s*brand\s*\}/gi, client.name || '')
              .replace(/\{\s*handle\s*\}/gi, handle ? '@' + handle : (client.name || ''));
          };
          var words = { caption: fill(d.draft.caption), ai: true };
          var at = o.put(words);
          var b2 = at && at.querySelector('[data-f="capwrite"]');
          capIdle(b2);
          if (btn !== b2) capIdle(btn);
          var line = at && at.parentNode && at.parentNode.querySelector('[data-m="cap"]');
          say(at, '');
          if (line) undoHere('Written by AI. Read before saving.', function () { o.put({ caption: before.caption, ai: false }); }, line);
        }).catch(function (e) {
          capIdle(btn);
          say(wrapOf(btn), e && e.message === 'ai-limit' ? capLimit(e.d) : (CAP_SAID[e && e.message] || (e && e.message) || CAP_SAID['ai-failed']), 'err');
        });
      });
    }).catch(function (e) {
      btn.disabled = false;
      say(wrapOf(btn), (e && e.message) || String(e), 'err');
    });
  }


  // ---- Content sets -------------------------------------------------------
  /* A set's content month (`batches.period`, YYYY-MM; empty is Ad hoc;
     2026-10-10). This month is Malaysia's. */
  var MON3 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  function ymNow() { return new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 7); }
  function ymAdd(ym, n) { var y = Number(ym.slice(0, 4)), m = Number(ym.slice(5, 7)) - 1 + n; y += Math.floor(m / 12); m = ((m % 12) + 12) % 12; return y + '-' + String(m + 1).padStart(2, '0'); }
  function ymWord(ym) { return /^\d{4}-\d{2}$/.test(ym || '') ? MON3[Number(ym.slice(5, 7)) - 1] + ' ' + ym.slice(0, 4) : 'Ad hoc'; }

  /* The client's sets by content month, newest first, the newest open and
     Ad hoc last (2026-10-10, the user: a client's sets grow without end);
     a row a set, its state at the right, its post count under it. The
     posts are counted in one read for every set (a read a row was a line
     Supabase logs and meters). */
  function loadBatches() {
    db.from('batches').select('*').eq('client_id', state.client.id)
      .order('created_at', { ascending: false }).then(function (r) {
        var box = $('batchCards');
        box.innerHTML = '';
        if (r.error) { failLine(box, 'Content sets', r.error.message, loadBatches); return; }
        if (!r.data.length) {
          box.innerHTML = '<div class="crm-table softpanel cr-sets"><div class="empty">No content sets.</div></div>';
          return;
        }
        var sets = r.data, byMonth = {}, months = [];
        sets.forEach(function (b) {
          var k = /^\d{4}-\d{2}$/.test(b.period || '') ? b.period : 'adhoc';
          if (!byMonth[k]) { byMonth[k] = []; months.push(k); }
          byMonth[k].push(b);
        });
        months.sort(function (a, z) { return a === 'adhoc' ? 1 : z === 'adhoc' ? -1 : z.localeCompare(a); });
        var subs = {};
        var GRP = window.ADspaceGroup;
        months.forEach(function (k, i) {
          box.appendChild(GRP.section({
            route: 'review-sets', key: k, name: k === 'adhoc' ? 'Ad hoc' : ymWord(k), count: byMonth[k].length,
            shut: GRP.shut('review-sets', k, i > 0, months.length === 1),
            table: function () {
              var t = document.createElement('div');
              t.className = 'crm-table softpanel cr-sets';
              byMonth[k].forEach(function (b) {
                var card = document.createElement('button');
                card.className = 'set-row' + (state.batch && state.batch.id === b.id ? ' is-on' : '');
                card.type = 'button';
                card.innerHTML =
                  '<span class="set-row-top"><b>' + esc(b.title) + '</b>' +
                    '<span class="tone ' + (b.published ? 'is-ok' : 'is-off') + '">' + (b.published ? 'Published' : 'Draft') + '</span></span>' +
                  '<span class="set-row-sub" data-role="sub">' + esc(subs[b.id] || 'Loading…') + '</span>';
                card.setAttribute('data-set', b.id);
                card.addEventListener('click', function () { openBatch(b); });
                t.appendChild(card);
              });
              return t;
            }
          }));
        });
        /* A count that could not be read is not a count of nothing: it
           said "0 posts" over a failed request and the set looked empty. */
        db.from('posts').select('batch_id').in('batch_id', sets.map(function (b) { return b.id; })).then(function (p) {
          var n = {};
          (p.data || []).forEach(function (x) { n[x.batch_id] = (n[x.batch_id] || 0) + 1; });
          sets.forEach(function (b) {
            subs[b.id] = p.error ? 'Posts unavailable' : (n[b.id] || 0) + ((n[b.id] || 0) === 1 ? ' post' : ' posts');
          });
          Array.prototype.forEach.call(box.querySelectorAll('[data-set]'), function (row) {
            var sub = row.querySelector('[data-role="sub"]');
            sub.textContent = subs[row.getAttribute('data-set')];
            sub.className = 'set-row-sub' + (p.error ? ' is-warn' : '');
          });
        });
      });
  }

  /* The name a new set needs is not on the screen yet, so the field grows out
     of the button that needs it and that button confirms it. Seeded with the
     month, which is what nearly every set is called. */
  var addSetAsk = window.ADspaceAsk.inline($('addBatch'), {
    label: 'Content set name', placeholder: 'Content set name',
    value: function () { return thisMonth(); },
    save: function (title) { makeBatch(title); }
  });
  $('addBatch').addEventListener('click', function () {
    addSetAsk.press();
  });
  function makeBatch(title) {
    db.from('batches').insert({
      client_id: state.client.id, title: title, published: false, period: ymNow()
    }).select().single().then(function (r) {
      if (r.error) { msg('setsMsg', r.error.message, 'err'); return; }
      logAction('set.created', state.client.name + ' — ' + title, '');
      loadBatches();
      openBatch(r.data);
    });
  }

  function openBatch(b, quiet) {
    state.batch = b;
    setUrl();
    state.drafts = state.pendingBy[b.id] || readStoredDrafts();
    $('setPanel').hidden = false;
    $('workspace').classList.add('is-set');
    $('driveUrl').value = state.client.drive_folder || '';
    $('mediaUrl').value = '';
    $('drivePicker').hidden = true;
    msg('driveMsg', '');
    paintSetHeader();
    loadSetTasks(b);
    renderDrafts();
    loadBatches();
    loadPosts();

    if (state.drafts.length) {
      msg('setMsg', state.drafts.length + ' pending asset' +
        (state.drafts.length === 1 ? '' : 's') +
        ' still waiting to be added to this set.', 'ok');
    }
    if (!quiet) window.scrollTo(0, 0);
  }

  /* The tasks in My Work that name this set (the user, 2026-09-27: "it
     works like a backlinks kind"). The panel is drawn only where one does;
     a failed read leaves it out rather than saying none. */
  function loadSetTasks(b) {
    var box = $('setTasks'), O = window.ADspaceOps;
    if (!box) return;
    box.hidden = true;
    if (!O || !O.recordTasks) return;
    O.recordTasks('set', b.id, function (rows) {
      if (!state.batch || state.batch.id !== b.id || !rows || !rows.length) return;
      $('setTaskList').innerHTML = O.recordTaskRows(rows);
      box.hidden = false;
    });
  }

  function paintSetHeader() {
    var live = state.batch.published;
    $('setTitle').textContent = state.batch.title;

    var chip = $('setState');
    chip.textContent = live ? 'Published' : 'Draft';
    chip.className = 'chip ' + (live ? 'is-ok' : 'is-off');

    // Publishing is the positive action, taking it back is a step in reverse,
    // so they should not look the same.
    $('publishLabel').textContent = live ? 'Unpublish' : 'Publish';
    // A paper plane to send it out, an eye struck through to take it back.
    $('publishIcon').innerHTML = live
      ? '<path d="m3 3 18 18"/><path d="M10.6 5.1A9.6 9.6 0 0 1 12 5c5 0 9 4.5 9 7a12 12 0 0 1-2.4 3.4"/>' +
        '<path d="M6.5 7.6C4.3 9.1 3 11.2 3 12c0 2.5 4 7 9 7a9.7 9.7 0 0 0 4.2-1"/>' +
        '<path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>'
      : '<path d="M21 3 10.5 13.5"/><path d="M21 3l-6.8 18-3.7-7.5L3 9.8z"/>';
    $('publishSet').className = 'btn btn-icon ' + (live ? 'btn-warn' : 'btn-go');

    // The standing state belongs beside the title. #setMsg is kept free for
    // things that just happened, so one does not overwrite the other.
    $('setNote').textContent = ymWord(state.batch.period) + ' · ' + (live
      ? 'Visible to the client on their review link.'
      : 'Not visible to the client.');
    msg('setMsg', '');
  }

  $('publishSet').addEventListener('click', function () {
    var next = !state.batch.published;
    if (!next) { setPublished(false); return; }

    // Sending is the commitment, so this is where a missing caption is worth flagging.
    db.from('posts').select('caption, caption_zh').eq('batch_id', state.batch.id).then(function (r) {
      var posts = r.data || [];
      if (!posts.length) { msg('setMsg', 'Add at least one post before publishing.', 'err'); return; }
      var blank = posts.filter(function (p) { return !p.caption && !p.caption_zh; }).length;
      var warn = blank
        ? ' ' + blank + ' of ' + posts.length + ' ' + (blank === 1 ? 'has' : 'have')
          + ' no caption.'
        : '';
      window.ADspaceConfirm.ask({
        title: 'Publish to the client',
        body: posts.length + ' post' + (posts.length === 1 ? '' : 's') + ' become'
            + (posts.length === 1 ? 's' : '') + ' visible to ' + state.client.name
            + ' immediately.' + warn,
        go: 'Publish'
      }, function () { setPublished(true); });
    });
  });

  function setPublished(next) {
    db.from('batches').update({ published: next }).eq('id', state.batch.id).select('id').then(function (r) {
      if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
      if (!(r.data || []).length) { msg('setMsg', 'Not saved. The database refused the request.', 'err'); return; }
      logAction(next ? 'set.published' : 'set.withdrawn',
        state.client.name + ' — ' + state.batch.title);
      state.batch.published = next;
      paintSetHeader();
      msg('setMsg', next
        ? 'Published. The client can now see this set on their review link.'
        : 'Withdrawn. This set is no longer visible to the client.', next ? 'ok' : '');
      loadBatches();
    });
  }

  function shutSetMenu() {
    $('setMenu').hidden = true;
    $('setMenuBtn').setAttribute('aria-expanded', 'false');
  }
  $('setMenuBtn').addEventListener('click', function (e) {
    e.stopPropagation();
    var open = $('setMenu').hidden;
    shutSetMenu();
    if (!open) return;
    $('setMenu').hidden = false;
    this.setAttribute('aria-expanded', 'true');
    window.ADspaceMenu.place(this, $('setMenu'));
  });
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#setMenu, #setMenuBtn')) shutSetMenu();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('setMenu').hidden) { shutSetMenu(); $('setMenuBtn').focus(); }
  });
  window.ADspaceMenu.onScroll(shutSetMenu);

  /* Adding assets is a sheet over the set: upload, Drive or a link, the
     pending files, then Add to set, which shuts it. */
  $('addAssets').addEventListener('click', function () {
    window.ADspaceSheet.show($('assetSheet'), { opener: this });
  });
  $('assetClose').addEventListener('click', function () { window.ADspaceSheet.close(); });


  /* ===== Pair covers (2026-10-03). A set made before covers were paired
     holds its covers and videos side by side and nothing ties them: the
     files were stored under random names, and a cover carries no caption.
     The set's order is the one clue (a cover is uploaded just before its
     video), so each unpaired cover is proposed the first free video after
     it, shown side by side, and changed by its select; Save writes only what
     the sheet holds. Each cover can be paired again later from its ⋯. */
  function paintPairSheet() {
    var v = state.postView;
    var posts = (v && v.posts || []).slice().sort(function (a, b) { return (a.position || 0) - (b.position || 0); });
    var videos = videosOf(posts);
    var isVideo = {};
    videos.forEach(function (x) { isVideo[x.id] = true; });
    /* A video a paired cover holds is neither proposed nor offered; a cover
       whose video was deleted waits again. */
    var held = {};
    posts.forEach(function (p) { if (p.platform === 'cover' && p.cover_for && isVideo[p.cover_for]) held[p.cover_for] = true; });
    var free = videos.filter(function (x) { return !held[x.id]; });
    var taken = {};
    var covers = posts.filter(function (p) { return p.platform === 'cover' && !(p.cover_for && isVideo[p.cover_for]); });
    var opts = function (sel) {
      return '<option value="">No video</option>' + free.map(function (x) {
        return '<option value="' + esc(x.id) + '"' + (x.id === sel ? ' selected' : '') + '>' + esc(x.label) + '</option>';
      }).join('');
    };
    /* The first free video after the cover (every pair the team has made
       has its video right after its cover), else the nearest one before it
       (a cover added after its video). */
    var propose = function (c) {
      var pos = c.position || 0, after = null, before = null;
      free.forEach(function (x) {
        if (taken[x.id]) return;
        if ((x.pos || 0) > pos) { if (!after) after = x; }
        else before = x;
      });
      return after || before;
    };
    /* The two side by side at 9:16, large enough to judge a match by eye;
       the video plays in place. */
    var coverTile = function (m) {
      return '<figure class="pairtile"><span class="pairtile-pic">' + (m ? thumbOf(m) : '') + '</span>' +
        '<figcaption>Cover</figcaption></figure>';
    };
    var videoTile = function (x) {
      return '<figure class="pairtile is-video"><span class="pairtile-pic">' +
        (x ? '<video controls muted playsinline preload="metadata">' +
          ADspaceMedia.sources(x.media.url).replace(/src="([^"#]+)"/g, 'src="$1#t=0.1"') + '</video>' : '') +
        '</span><figcaption>' + (x ? 'Video ' + x.n : 'No video') + '</figcaption></figure>';
    };
    $('pairList').innerHTML = covers.map(function (c, i) {
      var next = propose(c);
      if (next) taken[next.id] = true;
      var id = 'pairSel' + i;
      return '<div class="paircard" data-cover="' + esc(c.id) + '">' +
        '<div class="paircard-media">' + coverTile((c.media || [])[0]) +
          '<span class="pairlink" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/></svg></span>' +
          videoTile(next) + '</div>' +
        '<div class="paircard-ctl">' +
          '<label class="field-label" for="' + id + '">Video</label>' +
          '<select class="select" id="' + id + '" data-nodraft>' + opts(next ? next.id : '') + '</select>' +
          '<label class="tickline"><input type="checkbox" data-pair' + (next ? ' checked' : ' disabled') + '> Pair</label>' +
        '</div>' +
      '</div>';
    }).join('');
    Array.prototype.forEach.call($('pairList').querySelectorAll('.paircard'), function (card) {
      var sel = card.querySelector('select'), tick = card.querySelector('[data-pair]');
      sel.addEventListener('change', function () {
        var x = videos.filter(function (y) { return y.id === sel.value; })[0];
        var tmp = document.createElement('div');
        tmp.innerHTML = videoTile(x);
        var old = card.querySelector('.pairtile.is-video');
        old.parentNode.replaceChild(tmp.firstChild, old);
        tick.disabled = !x;
        tick.checked = !!x;
        pairCount();
      });
      tick.addEventListener('change', pairCount);
    });
    pairCount();
    msg('pairMsg', '', '');
    return covers.length;
  }
  /* What Pair will write: the ticked covers that name a video. */
  function pairPicks() {
    return Array.prototype.slice.call($('pairList').querySelectorAll('.paircard')).map(function (l) {
      var t = l.querySelector('[data-pair]');
      return { cover: l.getAttribute('data-cover'), video: t.checked ? l.querySelector('select').value : '' };
    }).filter(function (x) { return x.video; });
  }
  function pairCount() {
    var n = pairPicks().length;
    $('pairSave').textContent = n ? 'Pair ' + n : 'Pair';
    $('pairSave').disabled = !n;
  }
  $('pairCovers').addEventListener('click', function () {
    if (!paintPairSheet()) return;
    window.ADspaceSheet.show($('pairSheet'), { opener: this });
  });
  $('pairClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('pairCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  function setCovers(picks, then) {
    return Promise.all(picks.map(function (x) {
      return db.from('posts').update({ cover_for: x.video || null }).eq('id', x.cover).select('id')
        .then(function (r) { return !r.error && (r.data || []).length; })
        .catch(function () { return false; });
    })).then(then);
  }
  $('pairSave').addEventListener('click', function () {
    var btn = this;
    var picks = pairPicks();
    var seen = {}, twice = picks.some(function (x) { if (seen[x.video]) return true; seen[x.video] = true; return false; });
    if (twice) { msg('pairMsg', 'One video is chosen for two covers. Give each cover its own video.', 'err'); return; }
    if (!picks.length) { window.ADspaceSheet.close(); return; }
    btn.disabled = true;
    msg('pairMsg', 'Saving…', '');
    setCovers(picks, function (out) {
      btn.disabled = false;
      var done = picks.filter(function (x, i) { return out[i]; });
      var ok = done.length, bad = out.length - ok;
      var subject = state.client.name + ' — ' + (state.batch.title || '');
      if (ok) logAction('post.edited', subject, 'Covers paired: ' + ok);
      if (bad) { msg('pairMsg', bad + (bad === 1 ? ' cover was' : ' covers were') + ' not paired. The database refused the request.', 'err'); loadPosts(); return; }
      window.ADspaceSheet.close();
      msg('setMsg', ok + (ok === 1 ? ' cover paired.' : ' covers paired.'), 'ok');
      loadPosts();
      /* The way back, over the posts it changed. */
      undoHere(ok + (ok === 1 ? ' cover paired.' : ' covers paired.'), function () {
        setCovers(done.map(function (x) { return { cover: x.cover, video: null }; }), function (o2) {
          var back = o2.filter(Boolean).length;
          if (back) logAction('post.edited', subject, 'Covers unpaired: ' + back);
          msg('setMsg', back === done.length ? 'Pairing undone.' : 'Not undone. The database refused the request.', back === done.length ? 'ok' : 'err');
          loadPosts();
        });
      }, $('postStages'));
    });
  });
  $('deleteSet').addEventListener('click', function () {
    shutSetMenu();
    var b = state.batch;
    db.from('posts').select('id').eq('batch_id', b.id).then(function (r) {
      var n = (r.data || []).length;
      window.ADspaceConfirm.ask({
        title: 'Delete',
        body: n + ' post' + (n === 1 ? '' : 's') + ' in "' + b.title
            + '" and their approval records go.'
            + (b.published ? ' This set is published to the client.' : '')
            + ' There is no restore.',
        go: 'Delete',
        tone: 'danger',
        field: { label: 'Type the set name to confirm', placeholder: b.title, match: b.title, need: 'Type the set name to confirm.', mismatch: 'The set name does not match.' }
      }, function () {

      /* `.select()` so the answer says what was removed. A delete the database
         refuses returns no error at all — PostgREST answers 204 and the row
         simply stays — so without this the panel closed, nothing was said, and
         the set was still in the list underneath. A refusal is a sentence on
         the screen, never a success nobody can tell from one. */
      db.from('batches').delete().eq('id', b.id).select('id').then(function (res) {
        if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
        if (!(res.data || []).length) {
          msg('setMsg', 'Not deleted. The database refused the request.', 'err');
          return;
        }
        logAction('set.deleted', state.client.name + ' — ' + b.title,
          n + ' post' + (n === 1 ? '' : 's') + (b.published ? ', was published' : ', was draft'));
        state.batch = null;
        clearDrafts();
        $('setPanel').hidden = true;
        loadBatches();
      });
      });
    });
  });

  /* The title is already on the screen, so the pen edits it where it sits and
     becomes the tick that saves it. It used to open a browser prompt, which is
     a window over the page asking for a value the page was already showing. */
  $('renameSet').addEventListener('click', function () {
    var btn = this;
    window.ADspaceAsk.rename($('setTitle'), btn, {
      label: 'Content set name', max: 120,
      saveLabel: 'Save name',
      save: function (title) {
        db.from('batches').update({ title: title }).eq('id', state.batch.id).select('id').then(function (r) {
          if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
          if (!(r.data || []).length) { msg('setMsg', 'Not saved. The database refused the request.', 'err'); return; }
          logAction('set.renamed', state.client.name + ' — ' + title, 'was ' + (state.batch.title || ''));
          state.batch.title = title;
          paintSetHeader();
          loadBatches();
        });
      }
    });
  });

  // ---- Uploading ----------------------------------------------------------
  var drop = $('drop'), fileInput = $('fileInput');
  drop.addEventListener('click', function () { fileInput.click(); });
  drop.addEventListener('dragover', function (e) { e.preventDefault(); drop.classList.add('is-over'); });
  drop.addEventListener('dragleave', function () { drop.classList.remove('is-over'); });
  drop.addEventListener('drop', function (e) {
    e.preventDefault(); drop.classList.remove('is-over');
    handleFiles(e.dataTransfer.files);
  });
  fileInput.addEventListener('change', function () { handleFiles(fileInput.files); fileInput.value = ''; });

  /* Reads the real pixel size so we can guess the placement instead of asking. */
  function probe(file) {
    return probeBlob(file, file.type || '');
  }

  /* Reads the real pixel size, and for a video grabs a still as well. The still
     becomes the poster, so the client sees the frame straight away and the
     video itself is not fetched until they press play. */
  function probeBlob(blob, mime) {
    return new Promise(function (resolve) {
      var url = URL.createObjectURL(blob);
      var isVideo = String(mime).indexOf('video') === 0;
      var node = document.createElement(isVideo ? 'video' : 'img');
      var settled = false;
      var done = function (w, h, poster) {
        if (settled) return;
        settled = true;
        URL.revokeObjectURL(url);
        resolve({ width: w || 0, height: h || 0, isVideo: isVideo,
                  mime: mime || null, poster: poster || null });
      };
      // A file the browser cannot decode must not hold the batch up.
      setTimeout(function () { done(node.videoWidth || 0, node.videoHeight || 0); }, 15000);

      if (isVideo) {
        node.preload = 'metadata';
        node.muted = true;
        node.playsInline = true;
        node.onloadedmetadata = function () {
          var w = node.videoWidth, h = node.videoHeight;
          node.onseeked = function () {
            grabFrame(node, w, h).then(function (poster) { done(w, h, poster); },
                                       function () { done(w, h); });
          };
          // A little way in, so the still is not the black frame most edits open on.
          try { node.currentTime = Math.min(1, (node.duration || 2) / 3); }
          catch (e) { done(w, h); }
        };
      } else {
        node.onload = function () { done(node.naturalWidth, node.naturalHeight); };
      }
      node.onerror = function () { done(0, 0); };
      node.src = url;
    });
  }

  /* One frame as a small JPEG. Capped at 720 across, which is plenty for a
     poster and keeps it to a few tens of kilobytes. */
  function grabFrame(video, w, h) {
    return new Promise(function (resolve, reject) {
      if (!w || !h) { reject(); return; }
      var scale = Math.min(1, 720 / Math.max(w, h));
      var canvas = document.createElement('canvas');
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(h * scale);
      try {
        canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
      } catch (e) { reject(); return; }
      canvas.toBlob(function (b) { b ? resolve(b) : reject(); }, 'image/jpeg', 0.72);
    });
  }

  /* An MP4 only starts playing once the player has read its moov atom. Most
     exports leave it at the end of the file, which means the whole video has to
     arrive before the first frame does. Reading the box order tells us which
     kind we have, so the team can re-export rather than hand a client a video
     that takes a minute to start. */
  function hasFastStart(file) {
    if (!/mp4|quicktime|m4v/i.test(file.type || '')) return Promise.resolve(true);
    var offset = 0;
    var steps = 0;
    function readBox() {
      if (steps++ > 12 || offset + 8 > file.size) return Promise.resolve(true);
      return file.slice(offset, offset + 16).arrayBuffer().then(function (buf) {
        var view = new DataView(buf);
        if (buf.byteLength < 8) return true;
        var size = view.getUint32(0);
        var type = String.fromCharCode(view.getUint8(4), view.getUint8(5),
                                       view.getUint8(6), view.getUint8(7));
        if (type === 'moov') return true;
        if (type === 'mdat') return false;
        if (size === 1) {                       // 64-bit size follows the type
          if (buf.byteLength < 16) return true;
          size = Number(view.getBigUint64(8));
        }
        if (!size || size < 8) return true;
        offset += size;
        return readBox();
      }, function () { return true; });         // unreadable is not a verdict
    }
    return readBox();
  }

  function guessPlacement(info) {
    if (!info.width || !info.height) return 'instagram:feed';
    var ratio = info.width / info.height;
    if (ratio < 0.62) return info.isVideo ? 'instagram:reel' : 'instagram:story';  // 9:16
    if (info.isVideo) return 'instagram:reel';
    return 'instagram:feed';                                                       // 4:5, 1:1, landscape
  }

  /* A picked file stays in the browser: it is previewed from the device and
     goes up to storage only when Add to set is pressed, so a file removed or
     discarded before then costs nothing and leaves nothing behind in S3. */
  function handleFiles(files) {
    if (!files || !files.length) return;
    if (!state.batch) { msg('setMsg', 'Select a content set first.', 'err'); return; }
    if (state.uploading) return;

    // The size limit belongs to Supabase storage. S3 has no such ceiling.
    var cap = usingS3() ? Infinity : (cfg.maxUploadMB || 50) * 1024 * 1024;
    var all = Array.prototype.slice.call(files);
    var queue = all.filter(function (f) { return f.size <= cap; });
    var toobig = all.filter(function (f) { return f.size > cap; });

    if (toobig.length) {
      msg('setMsg',
        toobig.map(function (f) { return f.name + ' (' + mb(f.size) + ' MB)'; }).join(', ') +
        ' exceeds the ' + (cfg.maxUploadMB || 50) + ' MB limit. Export a smaller review copy or paste a link.', 'err');
      if (!queue.length) return;
    } else {
      msg('setMsg', '');
    }

    state.lastDropCount = queue.length;
    var slow = [];
    runPool(queue, function (file) {
      return probe(file).then(function (info) {
        return hasFastStart(file).then(function (fast) {
          if (!fast) slow.push(file.name);
          return { file: file, info: info };
        });
      });
    }, 3).then(function (list) {
      // Added in the order they were chosen, not the order they were read.
      list.forEach(function (x) {
        state.drafts.push(draftOf(localMedia(x.file, x.info, extFor(x.file.type, x.file.name)), x.info));
      });
      renderDrafts();
      if (slow.length) {
        msg('setMsg', slow.join(', ') + ': not web-optimised, so playback waits for the full download. ' +
          'Re-export with Fast Start.', 'err');
      }
    });
  }

  /* A file held in the browser until Add to set: previewed from an object URL
     on this device, carried with what it needs to go up later. */
  function localMedia(blob, info, ext, extra) {
    var m = {
      url: URL.createObjectURL(blob),
      type: info.isVideo ? 'video' : 'image',
      width: info.width || null,
      height: info.height || null,
      mime: info.mime || blob.type || null,
      poster: info.poster ? URL.createObjectURL(info.poster) : null,
      local: { file: blob, ext: ext, posterBlob: info.poster || null }
    };
    if (extra) Object.keys(extra).forEach(function (k) { m[k] = extra[k]; });
    return m;
  }

  function draftOf(media, info) {
    return {
      placement: guessPlacement(info),
      media: [media],
      caption: '', title: '', ai: false,
      /* Which reel a cover is for (2026-10-03): its own key, and the key of
         the reel draft it belongs to, matched by name on arrival. */
      key: 'd' + Math.random().toString(36).slice(2, 10),
      name: (media.local && media.local.file && media.local.file.name) || (info && info.name) || '',
      coverFor: null
    };
  }

  /* A cover and its reel go up together and show as one card. A cover finds
     its reel by name first (`launch.mp4` and `launch-cover.jpg`, or
     `launch_thumb.png`), else the first video after it that has no cover yet
     (the team uploads a cover just before its video: every pair made so far
     has its video right after its cover), else the nearest one before it. A
     pick by hand is kept. */
  function isCoverDraft(d) { return d.placement === 'cover:image'; }
  function isReelDraft(d) { return d.media.length === 1 && d.media[0].type === 'video'; }
  function stemOf(name) {
    return String(name || '').toLowerCase().replace(/\.[a-z0-9]+$/, '')
      .replace(/[\s._-]*(cover|thumb|thumbnail|poster)[\s._-]*\d*$/, '').replace(/[\s._-]+$/, '');
  }
  function autoPair() {
    var reels = state.drafts.filter(isReelDraft);
    var taken = {};
    state.drafts.forEach(function (d) {
      if (!isCoverDraft(d)) { d.coverFor = null; return; }
      if (d.coverFor && reels.some(function (r) { return r.key === d.coverFor; })) taken[d.coverFor] = true;
      else d.coverFor = null;
    });
    var open = function (d) { return isCoverDraft(d) && !d.coverFor && !d.pairedByHand; };
    /* Every name first, so a cover named for its reel is never beaten to it
       by a cover that only sits next to it. */
    state.drafts.forEach(function (d) {
      if (!open(d)) return;
      var stem = stemOf(d.name);
      var got = stem && reels.filter(function (r) { return !taken[r.key] && stemOf(r.name) === stem; })[0];
      if (got) { d.coverFor = got.key; taken[got.key] = true; }
    });
    /* Then the order: the first free video after the cover, else the nearest
       one before it. */
    state.drafts.forEach(function (d, i) {
      if (!open(d)) return;
      var near = null, j, r;
      for (j = i + 1; j < state.drafts.length && !near; j++) {
        r = state.drafts[j];
        if (isReelDraft(r) && !taken[r.key]) near = r;
      }
      for (j = i - 1; j >= 0 && !near; j--) {
        r = state.drafts[j];
        if (isReelDraft(r) && !taken[r.key]) near = r;
      }
      if (near) { d.coverFor = near.key; taken[near.key] = true; }
    });
  }

  function hasLocal() {
    return state.drafts.some(function (d) {
      return d.media.some(function (m) { return m.local; });
    });
  }

  function dropLocal(m) {
    if (!m || !m.local) return;
    try { URL.revokeObjectURL(m.url); } catch (e) {}
    if (m.poster && m.local.posterBlob) { try { URL.revokeObjectURL(m.poster); } catch (e) {} }
  }

  /* Add to set: every file still on this device goes up, a few at a time, with
     one bar for the lot and Cancel beside it. A file that finishes is kept (its
     draft now points at storage), so a retry sends only what is left. */
  function uploadPending() {
    var items = [];
    state.drafts.forEach(function (d) {
      d.media.forEach(function (m) { if (m.local) items.push(m); });
    });
    if (!items.length) return Promise.resolve();

    state.uploading = true;
    state.cancelled = false;
    paintSaving(true);
    var done = 0;
    var total = items.reduce(function (n, m) { return n + (m.local.file.size || 0); }, 0);
    var sent = items.map(function () { return 0; });
    var word = items.length === 1 ? 'file' : 'files';
    function tick() {
      var n = sent.reduce(function (a, b) { return a + b; }, 0);
      showProgress('Uploading ' + items.length + ' ' + word + ' · ' +
        done + ' of ' + items.length + ' complete', total ? n / total : 0, 'save');
    }
    tick();

    // Every file runs to its end, success or not, before the answer: a retry
    // must never send a file that is still on its way.
    var firstError = null;
    return runPool(items, function (m, i) {
      if (state.cancelled) return null;
      var file = m.local.file;
      return storeBlob(file, m.local.ext, m.mime || file.type, function (frac) {
        sent[i] = frac * (file.size || 0);
        tick();
      }).then(function (url) {
        return storePoster(m.local.posterBlob).then(function (posterUrl) {
          if (m.driveId) {
            // Remembered even if the post is later deleted, so a re-import is free.
            db.from('drive_assets').insert({
              client_id: state.client.id, drive_id: m.driveId, url: url,
              mime_type: m.mime || null, width: m.width || null, height: m.height || null,
              bytes: file.size || null, poster_url: posterUrl || null
            }).then(function () {}, function () {});
          }
          dropLocal(m);
          m.url = url;
          m.poster = posterUrl || null;
          delete m.local;
          sent[i] = file.size || 0;
          done++;
          tick();
          saveDrafts();
        });
      }).catch(function (e) {
        sent[i] = 0;
        if (!firstError) firstError = e;
      });
    }, 3).then(function () {
      state.uploading = false;
      paintSaving(false);
      showProgress(null, 0, 'save');
      var left = items.filter(function (m) { return m.local; }).length;
      if (!left) return;
      renderDrafts();
      if (state.cancelled) {
        throw new Error('Upload cancelled. ' + (items.length - left) + ' of ' + items.length +
          ' uploaded; nothing was added to the set.');
      }
      var text = (firstError && firstError.message) || 'Upload failed.';
      if (/payload|too large|exceeded/i.test(text)) {
        text = 'File exceeds the ' + (cfg.maxUploadMB || 50) +
          ' MB limit. Export a smaller review copy or paste a link.';
      }
      throw new Error(text + ' ' + left + ' of ' + items.length +
        ' not uploaded. Select Add to set to send the rest.');
    });
  }

  function paintSaving(on) {
    $('saveDrafts').disabled = on;
    $('saveDrafts').textContent = on ? 'Uploading…' : 'Add to set';
    $('clearDrafts').textContent = on ? 'Cancel' : 'Discard all';
    $('draftZone').classList.toggle('is-busy', on);
  }

  function cancelUpload() {
    state.cancelled = true;
    state.xhrs.slice().forEach(function (x) { try { x.abort(); } catch (e) {} });
  }

  function mb(bytes) {
    var v = bytes / 1024 / 1024;
    return v < 1 ? v.toFixed(1) : v.toFixed(0);   // 0.4 MB should not read as 0 MB
  }

  function usingS3() { return Boolean(cfg.s3 && cfg.s3.enabled); }

  function clientHandles() {
    var c = state.client || {};
    return {
      instagram: c.handle_ig, facebook: c.handle_fb,
      tiktok: c.handle_tiktok, xhs: c.handle_xhs
    };
  }

  /* "MP4 · 1080 x 1920", so it is obvious what was actually imported. */
  /* Carousel order decides which slide Instagram shows first and sizes the
     whole post, so it has to be changeable when the guess is wrong. */
  function slidesNode(media, onChange) {
    var wrap = el2('div', 'slides');
    media.forEach(function (m, i) {
      var chip = el2('div', 'slide-chip');
      chip.innerHTML =
        thumbOf(m) +
        '<i>' + (i + 1) + '</i>' +
        '<span class="slide-move">' +
          '<button type="button" data-d="-1"' + (i === 0 ? ' disabled' : '') + '>&#8249;</button>' +
          '<button type="button" data-d="1"' + (i === media.length - 1 ? ' disabled' : '') + '>&#8250;</button>' +
        '</span>';
      chip.querySelectorAll('button').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var to = i + Number(btn.dataset.d);
          if (to < 0 || to >= media.length) return;
          var moved = media.splice(i, 1)[0];
          media.splice(to, 0, moved);
          onChange();
        });
      });
      wrap.appendChild(chip);
    });
    return wrap;
  }

  /* Runs `work` over `items` a few at a time. One upload rarely fills the
     office line on its own, so several in flight finish the batch far sooner
     than one after another. Results come back in the original order. */
  function runPool(items, work, limit) {
    var out = new Array(items.length);
    var next = 0;
    function lane() {
      if (next >= items.length) return Promise.resolve();
      var i = next++;
      return Promise.resolve(work(items[i], i)).then(function (r) {
        out[i] = r;
        return lane();
      });
    }
    var lanes = [];
    for (var i = 0; i < Math.min(limit || 3, items.length); i++) lanes.push(lane());
    return Promise.all(lanes).then(function () { return out; });
  }

  function el2(tag, cls) {
    var n = document.createElement(tag);
    n.className = cls;
    return n;
  }

  function fileLabel(m) {
    if (!m) return '';
    var ext = extFor(m.mime, m.url || '').toUpperCase();
    var size = m.width && m.height ? m.width + ' x ' + m.height : '';
    return [ext, size].filter(Boolean).join(' · ');
  }

  /* A draft whose files are already in storage (a link, a Drive file copied
     before, or one sent by an Add to set that stopped part way) is kept in
     this browser, so a reload never costs an upload. A file still on the
     device cannot be kept across a reload: it lives in memory for this set. */
  function draftKey() { return 'adspace_drafts_' + (state.batch ? state.batch.id : 'none'); }

  function saveDrafts() {
    if (state.batch) {
      if (state.drafts.length) state.pendingBy[state.batch.id] = state.drafts;
      else delete state.pendingBy[state.batch.id];
    }
    var stored = state.drafts.filter(function (d) {
      return !d.media.some(function (m) { return m.local; });
    });
    try {
      if (stored.length) localStorage.setItem(draftKey(), JSON.stringify(stored));
      else localStorage.removeItem(draftKey());
    } catch (e) { /* private mode, carry on without it */ }
  }

  function readStoredDrafts() {
    try {
      var raw = localStorage.getItem(draftKey());
      var list = raw ? JSON.parse(raw) : [];
      return Array.isArray(list) ? list : [];
    } catch (e) { return []; }
  }

  /* One place that knows where files live. S3 behind CloudFront when it is set
     up, Supabase storage otherwise. Returns the URL to save on the post. */
  /* The content type is authoritative, the filename is not. A video named
     .jpg, or a Drive file with no extension at all, must not decide how the
     file is stored or how the client's browser is told to play it. */
  var MIME_EXT = {
    'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
    'video/x-m4v': 'm4v', 'video/mpeg': 'mpg', 'video/x-matroska': 'mkv',
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
    'image/gif': 'gif', 'image/heic': 'heic', 'image/avif': 'avif'
  };

  function extFor(mimeType, name) {
    var byMime = MIME_EXT[String(mimeType || '').toLowerCase().split(';')[0].trim()];
    if (byMime) return byMime;

    var fromName = String(name || '').split('.').pop().toLowerCase().replace(/[^a-z0-9]/g, '');
    if (fromName && fromName.length <= 5 && /\./.test(String(name || ''))) return fromName;

    // Last resort: at least keep video and image apart.
    return String(mimeType || '').indexOf('video') === 0 ? 'mp4' : 'jpg';
  }

  function storePoster(blob) {
    if (!blob) return Promise.resolve(null);
    return storeBlob(blob, 'jpg', 'image/jpeg').then(function (url) { return url; },
                                                     function () { return null; });
  }

  function storeFile(file, onProgress) {
    return storeBlob(file, extFor(file.type, file.name), file.type, onProgress);
  }

  /* fetch() cannot report how much of a body has gone out, so a 40 MB video
     looks frozen until it lands. XHR can, and it is the same request. */
  function putToS3(url, blob, contentType, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      state.xhrs.push(xhr);
      var forget = function () { state.xhrs = state.xhrs.filter(function (x) { return x !== xhr; }); };
      xhr.open('PUT', url, true);
      xhr.setRequestHeader('Content-Type', contentType || 'application/octet-stream');
      // filenames are random and never reused, so this is safe to cache hard
      xhr.setRequestHeader('Cache-Control', 'public, max-age=31536000, immutable');
      if (onProgress) {
        xhr.upload.onprogress = function (e) {
          if (e.lengthComputable) onProgress(e.loaded / e.total);
        };
      }
      xhr.onload = function () {
        forget();
        if (xhr.status >= 200 && xhr.status < 300) { if (onProgress) onProgress(1); resolve(); }
        else reject(new Error('S3 rejected the upload (HTTP ' + xhr.status + ').'));
      };
      xhr.onerror = function () {
        forget();
        reject(new Error('The connection to storage dropped part way through the upload.'));
      };
      xhr.onabort = function () { forget(); reject(new Error('cancelled')); };
      xhr.send(blob);
    });
  }

  /* `ref` names what the upload is for and its record (sign-upload signs
     nothing else, audit P1): a content set's file unless it says otherwise. */
  function storeBlob(blob, ext, contentType, onProgress, clientId, ref) {
    var cid = clientId || state.client.id;
    ref = ref || { purpose: 'review', batchId: state.batch && state.batch.id };
    if (!usingS3()) {
      var path = cid + '/' + crypto.randomUUID() + '.' + (ext || 'bin');
      return db.storage.from(cfg.storageBucket)
        .upload(path, blob, { cacheControl: '31536000', contentType: contentType || undefined })
        .then(function (r) {
          if (r.error) throw r.error;
          return db.storage.from(cfg.storageBucket).getPublicUrl(path).data.publicUrl;
        });
    }

    // Ask our own function to sign one upload, then send the file straight to
    // S3. The file never passes through Supabase, so there is no size ceiling.
    return db.functions.invoke(cfg.s3.functionName || 'sign-upload', {
      body: Object.assign({ ext: ext || 'bin', clientId: cid, size: blob.size }, ref)
    }).then(function (r) {
      if (r.error) {
        var hint = /failed to send|fetch/i.test(r.error.message || '')
          ? ' The browser could not reach it. In the Supabase dashboard, open Edge ' +
            'Functions, check a function named "' + (cfg.s3.functionName || 'sign-upload') +
            '" exists, and turn OFF its "Verify JWT" setting.'
          : '';
        throw new Error('Could not start the upload. ' + r.error.message + hint);
      }
      if (!r.data || !r.data.uploadUrl) throw new Error(
        'Upload was refused: ' + ((r.data && r.data.error) || 'unknown reason'));

      return putToS3(r.data.uploadUrl, blob, contentType, onProgress).then(function () {
        // The file is in the bucket, but that does not prove CloudFront serves it
        // at the URL we are about to save. What this catches is a misconfigured
        // distribution, which is the same for every file, so one check a session
        // is enough. Reading every upload back meant downloading it a second
        // time. Held as a promise rather than a flag so uploads running side by
        // side share the one check instead of each starting their own.
        if (!state.storageCheck) {
          state.storageCheck = probeUrl(r.data.publicUrl).then(function (info) {
            if (info.ok) return true;
            state.storageCheck = null;   // a later upload may be worth retrying
            throw new Error(
              'Uploaded to S3, but nothing is served at ' + r.data.publicUrl + ' — so the ' +
              'client would see a broken post. Usually the CloudFront distribution has an ' +
              'Origin path set, which shifts where files appear. Open that URL in a tab to ' +
              'confirm, then see docs/S3-UPLOAD-SETUP.md.');
          });
        }
        return state.storageCheck.then(function () { return r.data.publicUrl; });
      });
    });
  }

  /* A client's logo kept in our own storage (2026-10-03): a Facebook
     profile picture's address expires, so the mark broke on every mockup
     after a while. The picture is drawn down to 800px on its longer side in
     its own format (a PNG keeps its transparency) and stored under the
     client's folder like any upload; the address saved is ours and never
     expires. */
  function uploadLogo(file, clientId) {
    if (!file || !clientId) return Promise.reject(new Error('Choose an image.'));
    if (!/^image\/(png|jpeg|webp)$/.test(file.type)) return Promise.reject(new Error('Choose a PNG, JPEG or WebP image.'));
    if (file.size > 10 * 1024 * 1024) return Promise.reject(new Error('Choose an image under 10 MB.'));
    var png = file.type !== 'image/jpeg';
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () {
        var k = Math.min(1, 800 / Math.max(img.naturalWidth, img.naturalHeight));
        var cv = document.createElement('canvas');
        cv.width = Math.max(1, Math.round(img.naturalWidth * k));
        cv.height = Math.max(1, Math.round(img.naturalHeight * k));
        cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
        URL.revokeObjectURL(url);
        cv.toBlob(function (b) {
          if (!b) { reject(new Error('That image could not be read.')); return; }
          resolve(b);
        }, png ? 'image/png' : 'image/jpeg', 0.9);
      };
      img.onerror = function () { URL.revokeObjectURL(url); reject(new Error('That image could not be read.')); };
      img.src = url;
    }).then(function (b) {
      return storeBlob(b, png ? 'png' : 'jpg', png ? 'image/png' : 'image/jpeg', null, clientId, { purpose: 'logo' });
    });
  }
  /* One wiring for every logo field: the Upload button beside it opens its
     file picker, and the stored address is written into the field, which
     the sheet's own Save then keeps. */
  function wireLogoUpload(btnId, fileId, fieldId, msgId, clientOf) {
    var btn = $(btnId), file = $(fileId);
    if (!btn || !file) return;
    btn.addEventListener('click', function () { file.value = ''; file.click(); });
    file.addEventListener('change', function () {
      var f = file.files && file.files[0];
      var c = clientOf();
      if (!f || !c) return;
      btn.disabled = true;
      msg(msgId, 'Uploading…');
      uploadLogo(f, c.id).then(function (u) {
        btn.disabled = false;
        var field = $(fieldId);
        field.value = u;
        field.dispatchEvent(new Event('input', { bubbles: true }));
        msg(msgId, 'Uploaded. Save to keep it.', 'ok');
      }).catch(function (e) {
        btn.disabled = false;
        msg(msgId, (e && e.message) || 'Not uploaded.', 'err');
      });
    });
  }
  wireLogoUpload('eLogoUp', 'eLogoFile', 'eLogo', 'logoNote', function () { return state.client; });

  window.__hasFastStart = hasFastStart;   // used by the test harness

  /* A link already served from somewhere: nothing to upload. The real pixel
     size is kept so the client's preview frame matches the file before it
     has finished loading. */
  function pushDraft(url, info, quiet) {
    state.drafts.push(draftOf({
      url: url,
      type: info.isVideo ? 'video' : 'image',
      width: info.width || null,
      height: info.height || null,
      mime: info.mime || null,
      poster: info.posterUrl || null
    }, info));
    if (!quiet) renderDrafts();
  }

  /* Large videos can live anywhere that serves the file directly, such as
     mycdn.adspace.me. We read the dimensions off the URL the same way. */
  function probeUrl(url) {
    return new Promise(function (resolve) {
      var settled = false;
      var finish = function (r) { if (!settled) { settled = true; resolve(r); } };
      setTimeout(function () { finish({ ok: false }); }, 12000);

      var v = document.createElement('video');
      v.preload = 'metadata';
      v.onloadedmetadata = function () {
        finish({ width: v.videoWidth, height: v.videoHeight, isVideo: true,
                 mime: null, ok: v.videoWidth > 0 });
      };
      v.onerror = function () {
        var i = new Image();
        i.onload = function () {
          finish({ width: i.naturalWidth, height: i.naturalHeight, isVideo: false,
                   mime: null, ok: true });
        };
        i.onerror = function () { finish({ ok: false }); };
        i.src = url;
      };
      v.src = url;
    });
  }

  $('addMediaUrl').addEventListener('click', function () {
    var url = $('mediaUrl').value.trim();
    if (!url) return;
    if (!state.batch) { msg('setMsg', 'Select a content set first.', 'err'); return; }

    // A Drive link is a normal thing to paste here, so handle it rather than refuse it.
    if (isDriveLink(url)) { handleDriveLink(url); return; }

    if (!/^https:\/\//i.test(url)) {
      msg('setMsg', 'The link needs to start with https://', 'err');
      return;
    }
    msg('setMsg', 'Verifying the link…');
    probeUrl(url).then(function (info) {
      if (!info.ok) {
        msg('setMsg', 'Link could not be loaded. It must point directly to the file.', 'err');
        return;
      }
      pushDraft(url, info);
      $('mediaUrl').value = '';
      msg('setMsg', 'Asset added.', 'ok');
    });
  });

  function handleDriveLink(url) {
    if (!driveKey()) {
      msg('setMsg', 'Drive import requires a Google API key in js/config.js. See docs/DRIVE-IMPORT-CHECK.md.', 'err');
      return;
    }

    // A folder belongs in the Drive section, so send it there and load it.
    var folder = driveFolderId(url);
    if (folder) {
      $('mediaUrl').value = '';
      $('driveUrl').value = url;
      msg('setMsg', '');
      $('driveLoad').click();
      return;
    }

    var fileId = driveFileId(url);
    if (!fileId) {
      msg('setMsg', 'No file id found in that Drive link. Use Share in Drive and copy the link.', 'err');
      return;
    }

    msg('setMsg', 'Retrieving file details from Drive…');
    driveMeta(fileId).then(function (f) {
      if (!/^(image|video)\//.test(f.mimeType)) {
        msg('setMsg', f.name + ' is not an image or a video.', 'err');
        return;
      }
      var cap = usingS3() ? Infinity : (cfg.maxUploadMB || 50) * 1024 * 1024;
      if (f.size > cap) {
        msg('setMsg', f.name + ' is ' + mb(f.size) + ' MB, over the ' +
          (cfg.maxUploadMB || 50) + ' MB limit. Turning on S3 storage removes this limit.', 'err');
        return;
      }
      msg('setMsg', 'Reading ' + f.name + ' from Drive…');
      return copyDriveFile(f).then(function (res) {
        state.drafts.push(res.draft);
        renderDrafts();
        $('mediaUrl').value = '';
        msg('setMsg', f.name + ' ready. Add the caption below, then select Add to set.', 'ok');
      });
    }).catch(function (e) {
      if (e.name === 'AbortError') {
        msg('setMsg', 'Timed out reading that file from Drive.', 'err');
      } else if (/uploaded to s3|s3 rejected|could not start/i.test(e.message || '')) {
        // A storage problem, not a Drive one. Do not muddy it with sharing advice.
        msg('setMsg', e.message, 'err');
      } else {
        msg('setMsg', 'Could not read that file from Drive. ' + e.message +
          ' Check it is shared as Anyone with the link.', 'err');
      }
    });
  }

  // ---- Google Drive import -------------------------------------------------
  // Creative uploads to Drive, so the portal reads that folder directly rather
  // than making anyone download and re-upload. Files are copied into our own
  // storage once, so a client link never depends on a Drive folder staying put.
  var DRIVE_API = 'https://www.googleapis.com/drive/v3/files';
  var driveFiles = [];

  function driveKey() { return (cfg.googleApiKey || '').trim(); }

  function driveFileId(url) {
    var m = String(url).match(/\/file\/d\/([A-Za-z0-9_-]{10,})/) ||
            String(url).match(/[?&]id=([A-Za-z0-9_-]{10,})/);
    return m ? m[1] : null;
  }

  function isDriveLink(url) {
    return /^https?:\/\/(?:[a-z0-9-]+\.)*drive\.google\.com\//i.test(String(url).trim());
  }

  /* Reads bytes with progress, so a large video does not look like it has hung. */
  function fetchWithProgress(url, onProgress) {
    return driveFetch(url, 600000).then(function (r) {
      if (!r.ok) throw new Error('Drive refused the file (HTTP ' + r.status + ')');
      var total = Number(r.headers.get('content-length')) || 0;
      if (!r.body || !total) return r.blob();

      var reader = r.body.getReader();
      var chunks = [];
      var got = 0;
      return (function pump() {
        return reader.read().then(function (res) {
          if (res.done) return new Blob(chunks);
          chunks.push(res.value);
          got += res.value.length;
          if (onProgress) onProgress(got / total);
          return pump();
        });
      })();
    });
  }

  /* Reads a Drive file into this browser, to go up to our own storage with the
     rest at Add to set. If we have copied this Drive file before, reuse it:
     re-importing after a mistake should not upload again and pay for a second
     copy in S3. */
  function copyDriveFile(f, onProgress) {
    return db.from('drive_assets')
      .select('url, poster_url').eq('client_id', state.client.id).eq('drive_id', f.id).limit(1)
      .then(function (r) {
        var hit = (r.data || [])[0];
        if (hit && hit.url) {
          if (onProgress) onProgress(1);
          return { url: hit.url, reused: true, poster: hit.poster_url || null };
        }
        return fetchWithProgress(
          DRIVE_API + '/' + f.id + '?alt=media&key=' + encodeURIComponent(driveKey()), onProgress)
          .then(function (blob) {
            // The bytes are already here, so the poster costs nothing extra.
            return probeBlob(blob, f.mimeType).then(function (shot) {
              if (!f.width)  f.width = shot.width;
              if (!f.height) f.height = shot.height;
              return { blob: blob, shot: shot };
            });
          });
      })
      .then(function (res) {
        // The caller adds it, so a batch import can keep the chosen order even
        // though the reads finish out of order.
        var info = { width: f.width, height: f.height, isVideo: f.isVideo, mime: f.mimeType };
        res.draft = draftOf(res.blob
          ? localMedia(res.blob, { width: f.width, height: f.height, isVideo: f.isVideo,
              mime: f.mimeType, poster: res.shot.poster }, extFor(f.mimeType, f.name), { driveId: f.id })
          : {
              url: res.url,
              type: f.isVideo ? 'video' : 'image',
              width: f.width || null,
              height: f.height || null,
              mime: f.mimeType || null,
              poster: res.poster || null,
              driveId: f.id
            }, info);
        return res;
      });
  }

  function driveMeta(id) {
    var fields = 'id,name,mimeType,size,imageMediaMetadata(width,height),' +
                 'videoMediaMetadata(width,height)';
    return driveFetch(DRIVE_API + '/' + id + '?key=' + encodeURIComponent(driveKey()) +
                      '&fields=' + encodeURIComponent(fields) + '&supportsAllDrives=true')
      .then(function (r) {
        return r.json().then(function (body) {
          if (r.status !== 200) {
            throw new Error((body.error && body.error.message) || ('Google returned ' + r.status));
          }
          var m = body.imageMediaMetadata || body.videoMediaMetadata || {};
          return {
            id: body.id, name: body.name || 'file', mimeType: body.mimeType || '',
            size: Number(body.size) || 0,
            width: m.width || 0, height: m.height || 0,
            isVideo: String(body.mimeType || '').indexOf('video') === 0
          };
        });
      });
  }

  function driveFolderId(url) {
    var m = String(url).match(/\/folders\/([A-Za-z0-9_-]{10,})/) ||
            String(url).match(/[?&]id=([A-Za-z0-9_-]{10,})/);
    return m ? m[1] : null;
  }

  function driveFetch(url, ms) {
    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, ms || 30000);
    return fetch(url, { signal: ctrl.signal }).finally(function () { clearTimeout(timer); });
  }

  /* Drive ids already used by this client, so last month's files are not
     imported a second time by accident. */
  function alreadyImported() {
    return db.from('batches').select('id').eq('client_id', state.client.id)
      .then(function (r) {
        var ids = (r.data || []).map(function (b) { return b.id; });
        if (!ids.length) return {};
        return db.from('posts').select('media').in('batch_id', ids).then(function (p) {
          var seen = {};
          (p.data || []).forEach(function (post) {
            (post.media || []).forEach(function (m) { if (m.driveId) seen[m.driveId] = true; });
          });
          return seen;
        });
      }).catch(function () { return {}; });
  }

  $('driveLoad').addEventListener('click', function () {
    var url = $('driveUrl').value.trim();
    var id = driveFolderId(url);
    if (!id) {
      msg('driveMsg', 'That does not look like a Drive folder link. It should have ' +
        '/folders/ followed by a long id.', 'err');
      return;
    }
    msg('driveMsg', 'Reading folder contents…');
    $('drivePicker').hidden = true;

    var fields = 'files(id,name,mimeType,size,imageMediaMetadata(width,height),' +
                 'videoMediaMetadata(width,height))';
    var q = encodeURIComponent("'" + id + "' in parents and trashed=false");
    var listUrl = DRIVE_API + '?q=' + q + '&key=' + encodeURIComponent(driveKey()) +
      '&fields=' + encodeURIComponent(fields) +
      '&pageSize=200&supportsAllDrives=true&includeItemsFromAllDrives=true';

    driveFetch(listUrl).then(function (r) {
      return r.json().then(function (body) { return { status: r.status, body: body }; });
    }).then(function (res) {
      if (res.status !== 200) {
        msg('driveMsg', (res.body.error && res.body.error.message) ||
          ('Google returned ' + res.status) +
          '. Check the folder is shared as Anyone with the link.', 'err');
        return;
      }
      var files = (res.body.files || []).filter(function (f) {
        return /^(image|video)\//.test(f.mimeType);
      });
      if (!files.length) {
        msg('driveMsg', 'That folder contains no images or videos.', 'err');
        return;
      }

      // remember the folder so next month is one click
      db.from('clients').update({ drive_folder: url }).eq('id', state.client.id).select('id')
        .then(function (r) {
          if (r.error || !(r.data || []).length) return;
          if (state.client.drive_folder !== url) logAction('client.drive', state.client.name, url);
          state.client.drive_folder = url;
        });

      return alreadyImported().then(function (seen) {
        driveFiles = files.map(function (f) {
          var m = f.imageMediaMetadata || f.videoMediaMetadata || {};
          return {
            id: f.id, name: f.name, mimeType: f.mimeType,
            size: Number(f.size) || 0,
            width: m.width || 0, height: m.height || 0,
            isVideo: f.mimeType.indexOf('video') === 0,
            done: Boolean(seen[f.id]),
            pick: !seen[f.id]
          };
        });
        renderDriveFiles();
        var fresh = driveFiles.filter(function (f) { return !f.done; }).length;
        // Neutral: nothing has happened yet. Green is kept for the import
        // actually finishing, so it means the same thing everywhere.
        msg('driveMsg', files.length + ' file' + (files.length === 1 ? '' : 's') + ' found' +
          (fresh ? ', ' + fresh + ' to import.' : '. All of them are already in storage.'));
      });
    }).catch(function (e) {
      msg('driveMsg', e.name === 'AbortError'
        ? 'Timed out reading the folder.'
        : 'Could not reach Google. ' + e.message, 'err');
    });
  });

  function renderDriveFiles() {
    var box = $('driveFiles');
    box.innerHTML = '';
    $('drivePicker').hidden = false;

    driveFiles.forEach(function (f, i) {
      var card = document.createElement('label');
      card.className = 'dfile' + (f.done ? ' is-done' : '');
      // Drive knows the pixel size of an image but often not of a video, and
      // "size unknown" beside a figure in megabytes read as a contradiction.
      var spec = [f.width ? f.width + ' x ' + f.height : '', f.size ? mb(f.size) + ' MB' : '']
        .filter(Boolean).join(' \u00b7 ');
      card.innerHTML =
        '<input type="checkbox"' + (f.pick ? ' checked' : '') + (f.done ? ' disabled' : '') + '>' +
        '<span class="dfile-img"><img loading="lazy" alt="">' +
          '<i>' + esc(extFor(f.mimeType, f.name).toUpperCase()) + '</i></span>' +
        '<span class="dfile-meta"><b>' + esc(f.name) + '</b>' +
          '<span class="dfile-status status ' +
            (f.done ? 'status-approved' : 'status-pending') + '">' +
            (f.done ? 'Imported' : 'Not imported') + '</span>' +
          (spec ? '<span class="muted">' + spec + '</span>' : '') +
        '</span>';
      // Drive has no thumbnail for every file. Fall back to the file type
      // rather than leaving a browser's broken image icon on screen.
      var thumb = card.querySelector('img');
      thumb.addEventListener('error', function () {
        card.querySelector('.dfile-img').classList.add('is-blank');
      });
      thumb.src = 'https://drive.google.com/thumbnail?id=' + f.id + '&sz=w400';
      card.querySelector('input').addEventListener('change', function (e) {
        driveFiles[i].pick = e.target.checked;
      });
      box.appendChild(card);
    });
  }

  $('driveAll').addEventListener('click', function () {
    driveFiles.forEach(function (f) { if (!f.done) f.pick = true; });
    renderDriveFiles();
  });
  $('driveNone').addEventListener('click', function () {
    driveFiles.forEach(function (f) { f.pick = false; });
    renderDriveFiles();
  });

  /* Two bars: reading from Drive at the top of the sheet, and Add to set's
     upload beside the button that started it. */
  function showProgress(label, fraction, which) {
    var ids = which === 'save'
      ? ['saveProgress', 'saveLabel', 'savePct', 'saveFill']
      : ['driveProgress', 'progressLabel', 'progressPct', 'progressFill'];
    var box = $(ids[0]);
    if (label === null) { box.hidden = true; return; }
    box.hidden = false;
    $(ids[1]).textContent = label;
    var pct = Math.max(0, Math.min(100, Math.round(fraction * 100)));
    $(ids[2]).textContent = pct + '%';
    $(ids[3]).style.width = pct + '%';
  }

  $('driveImport').addEventListener('click', function () {
    if (!state.batch) { msg('driveMsg', 'Select a content set first.', 'err'); return; }
    var picked = driveFiles.filter(function (f) { return f.pick && !f.done; });
    if (!picked.length) { msg('driveMsg', 'No assets selected.', 'err'); return; }

    var cap = usingS3() ? Infinity : (cfg.maxUploadMB || 50) * 1024 * 1024;
    var toobig = picked.filter(function (f) { return f.size > cap; });
    var queue = picked.filter(function (f) { return f.size <= cap; });

    if (toobig.length) {
      msg('driveMsg', toobig.length + ' file' + (toobig.length === 1 ? ' is' : 's are') +
        ' over the ' + (cfg.maxUploadMB || 50) + ' MB limit and were skipped: ' +
        toobig.map(function (f) { return f.name; }).join(', ') +
        '. Turning on S3 storage removes this limit.', 'err');
      if (!queue.length) return;
    }

    var done = 0;
    var reused = 0;
    var total = queue.reduce(function (n, f) { return n + (f.size || 0); }, 0);
    var moved = queue.map(function () { return 0; });
    showProgress('Preparing…', 0);

    function tick() {
      var n = moved.reduce(function (a, b) { return a + b; }, 0);
      showProgress('Reading ' + queue.length + ' file' + (queue.length === 1 ? '' : 's') +
        ' from Drive · ' + done + ' of ' + queue.length + ' complete', total ? n / total : 0);
    }

    runPool(queue, function (f, i) {
      return copyDriveFile(f, function (frac) {
        moved[i] = frac * (f.size || 0);
        tick();
      }).then(function (res) {
        if (res.reused) reused++;
        f.done = true; f.pick = false;
        moved[i] = f.size || 0;
        done++;
        tick();
        return res;
      });
    }, 3)
      .then(function (results) {
        showProgress(null);
        results.forEach(function (r) { state.drafts.push(r.draft); });
        renderDrafts();
        renderDriveFiles();
        if (!toobig.length) {
          msg('driveMsg', done + ' file' + (done === 1 ? '' : 's') + ' ready' +
            (reused ? ', ' + reused + ' already in storage at no additional cost' : '') +
            '. Add the caption below, then select Add to set.', 'ok');
        }
      })
      .catch(function (e) {
        showProgress(null);
        msg('driveMsg', e.name === 'AbortError'
          ? 'Timed out reading a file from Drive. Large videos can take a while, try fewer at a time.'
          : e.message, 'err');
      });
  });

  function renderDrafts() {
    autoPair();
    saveDrafts();
    var box = $('drafts');
    box.innerHTML = '';
    $('draftActions').hidden = state.drafts.length === 0;
    $('draftZone').hidden = state.drafts.length === 0;

    var images = state.drafts.filter(function (d) { return d.media[0].type === 'image'; });
    var canCombine = state.drafts.length > 1 && images.length === state.drafts.length;
    $('combineBar').hidden = !canCombine;
    if (canCombine) {
      $('combineText').textContent =
        state.drafts.length + ' images added. Separate posts, or one carousel?';
    }

    state.drafts.forEach(function (d, i) {
      var isXhs = d.placement.indexOf('xhs') === 0;
      var row = document.createElement('div');
      row.className = 'draft';

      var opts = PLACEMENTS.map(function (p) {
        return '<option value="' + p[0] + '"' + (p[0] === d.placement ? ' selected' : '') + '>' +
          p[1] + '</option>';
      }).join('');

      row.innerHTML =
        '<div class="draft-media">' +
          d.media.map(function (m) {
            /* A file still on this device plays from it; where the browser
               cannot decode it (an iPhone's HEVC in Chrome) the still read
               from it stands in. */
            return m.type === 'video'
              ? ADspaceMedia.tag(m.url, 'muted' + (m.poster ? ' poster="' + esc(m.poster) + '"' : ''))
              : '<img src="' + m.url + '" alt="">';
          }).join('') +
          (d.media.length > 1 ? '<i>' + d.media.length + ' slides</i>' : '') +
        '</div>' +
        '<div class="draft-body">' +
          '<div class="draft-top">' +
            '<select class="select" data-f="placement" aria-label="Placement">' + opts + '</select>' +
            '<span class="filetag">' + esc(fileLabel(d.media[0])) + '</span>' +
            '<span class="muted">Change if wrong</span>' +
            '<button class="linkbtn" data-f="remove" type="button">Remove</button>' +
          '</div>' +
          (isCoverDraft(d) ? coverForField(d) : '') +
          (isXhs ? '<input class="input" data-f="title" placeholder="Note title 标题" value="' +
                   esc(d.title) + '">' : '') +
          '<textarea class="textarea" data-f="caption" placeholder="Caption" aria-label="Caption">' +
            esc(d.caption) + '</textarea>' +
          capButton() +
        '</div>';

      if (d.media.length > 1) {
        var body = row.querySelector('.draft-body');
        var strip = slidesNode(d.media, function () { saveDrafts(); renderDrafts(); });
        var hint = el2('div', 'slide-hint');
        hint.textContent = d.placement === 'facebook:multi'
          ? 'Photo 1 takes the largest tile.'
          : 'Slide 1 is the cover and sets the carousel shape.';
        body.insertBefore(strip, body.children[1] || null);
        body.insertBefore(hint, strip.nextSibling);
      }

      row.querySelector('[data-f="placement"]').addEventListener('change', function (e) {
        d.placement = e.target.value; renderDrafts();
      });
      row.querySelector('[data-f="remove"]').addEventListener('click', function () {
        if (state.uploading) return;
        d.media.forEach(dropLocal);
        state.drafts.splice(i, 1); renderDrafts();
      });
      var cap = row.querySelector('[data-f="caption"]');
      cap.addEventListener('input', function (e) { d.caption = e.target.value; queueSave(); });
      var capw = row.querySelector('[data-f="capwrite"]');
      if (capw) capw.addEventListener('click', function () {
        writeCaption({ btn: capw, placement: d.placement, title: d.title, notesKey: state.batch.id + ':' + d.key,
          now: { caption: d.caption },
          put: function (w) {
            d.caption = w.caption || '';
            d.ai = !!w.ai;
            var at = state.drafts.indexOf(d);
            renderDrafts();
            var nr = at > -1 ? $('drafts').children[at] : null;
            return nr && nr.querySelector('.capwrite');
          } });
      });
      var title = row.querySelector('[data-f="title"]');
      if (title) title.addEventListener('input', function (e) { d.title = e.target.value; queueSave(); });
      var cf = row.querySelector('[data-f="coverfor"]');
      if (cf) cf.addEventListener('change', function (e) {
        d.coverFor = e.target.value || null; d.pairedByHand = true; renderDrafts();
      });

      box.appendChild(row);
    });
  }

  /* A cover's reel, as a choice among the videos being added (each named by
     its place and file), or none. */
  function coverForField(d) {
    var n = 0;
    var opts = state.drafts.map(function (r) {
      if (!isReelDraft(r)) return '';
      n++;
      var taken = state.drafts.some(function (o) { return o !== d && isCoverDraft(o) && o.coverFor === r.key; });
      if (taken && d.coverFor !== r.key) return '';
      return '<option value="' + r.key + '"' + (d.coverFor === r.key ? ' selected' : '') + '>' +
        esc('Video ' + n + (r.name ? ' · ' + r.name : '')) + '</option>';
    }).join('');
    return '<label class="draft-pair"><span class="field-label">Cover for</span>' +
      '<select class="select" data-f="coverfor"><option value="">No video</option>' + opts + '</select></label>';
  }

  $('combineBtn').addEventListener('click', function () {
    if (state.uploading) return;
    var merged = {
      placement: 'instagram:carousel',
      media: state.drafts.reduce(function (all, d) { return all.concat(d.media); }, []),
      caption: state.drafts.map(function (d) { return d.caption; }).filter(Boolean)[0] || '',
      title: '', ai: state.drafts.some(function (d) { return d.ai && d.caption; })
    };
    state.drafts = [merged];
    renderDrafts();
  });

  $('clearDrafts').addEventListener('click', function () {
    // While Add to set is uploading, this is its Cancel.
    if (state.uploading) { cancelUpload(); return; }
    if (!state.drafts.length) { clearDrafts(); return; }
    window.ADspaceConfirm.ask({
      title: 'Discard these assets',
      body: state.drafts.length + ' pending asset' + (state.drafts.length === 1 ? '' : 's')
          + ' go. Nothing is added to the set.',
      go: 'Discard',
      tone: 'danger'
    }, clearDrafts);
  });

  var saveTimer = null;
  function queueSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveDrafts, 400);   // typing should not hit storage on every key
  }

  function clearDrafts() {
    state.drafts.forEach(function (d) { d.media.forEach(dropLocal); });
    state.drafts = [];
    try { localStorage.removeItem(draftKey()); } catch (e) {}
    renderDrafts();
    msg('setMsg', '');
    if (state.batch) paintSetHeader();
  }

  $('saveDrafts').addEventListener('click', function () {
    if (!state.drafts.length || state.uploading) return;
    msg('setMsg', '');
    /* A caption written with AI is declared read before it is kept
       (2026-10-10), once for every such caption in the set. */
    var ai = state.drafts.filter(function (d) { return d.ai && String(d.caption || '').trim(); }).length;
    var go = function () {
      uploadPending().then(function () { return addPosts(ai); }).catch(function (e) {
        msg('setMsg', (e && e.message) || 'Upload failed.', 'err');
      });
    };
    if (ai && window.ADspaceConfirm.ai) window.ADspaceConfirm.ai.declare(ai === 1 ? 'caption' : 'set of captions', 'Confirm and add', go);
    else go();
  });

  /* Every file is in storage by now, so the posts are written in one insert. */
  function addPosts(ai) {
    return db.from('posts').select('position').eq('batch_id', state.batch.id)
      .order('position', { ascending: false }).limit(1).then(function (r) {
        var next = (r.data && r.data.length ? r.data[0].position : -1) + 1;
        var rows = state.drafts.map(function (d, i) {
          var parts = d.placement.split(':');
          return {
            batch_id: state.batch.id,
            platform: parts[0], format: parts[1],
            handle: null,   // the client's per platform account name is used instead
            title: d.title || null,
            caption: d.caption || null,
            media: d.media,
            position: next + i
          };
        });
        db.from('posts').insert(rows).select('id, position').then(function (res) {
          if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
          /* Each cover names its reel once both rows exist. */
          var idAt = {};
          (res.data || []).forEach(function (x) { idAt[x.position] = x.id; });
          var keyAt = {};
          state.drafts.forEach(function (d, i) { keyAt[d.key] = next + i; });
          var pairs = [];
          state.drafts.forEach(function (d, i) {
            if (isCoverDraft(d) && d.coverFor && idAt[next + i] && idAt[keyAt[d.coverFor]]) {
              pairs.push(db.from('posts').update({ cover_for: idAt[keyAt[d.coverFor]] }).eq('id', idAt[next + i]).select('id'));
            }
          });
          if (pairs.length) Promise.all(pairs).then(function (out) {
            var bad = out.filter(function (o) { return o.error || !o.data || !o.data.length; }).length;
            if (bad) msg('setMsg', bad + (bad === 1 ? ' cover was added unpaired. Pair it' : ' covers were added unpaired. Pair them') + ' from the ⋯.', 'warn');
            loadPosts();
          }).catch(function () {
            msg('setMsg', 'Covers were added unpaired. Pair them from the ⋯.', 'warn');
            loadPosts();
          });
          logAction('post.added', state.client.name + ' — ' + (state.batch.title || ''),
            rows.length + (rows.length === 1 ? ' post' : ' posts') +
            (ai ? ' · ' + ai + (ai === 1 ? ' caption' : ' captions') + ' written with AI, read and confirmed' : ''));
          clearDrafts();
          if (window.ADspaceSheet.isOpen($('assetSheet'))) window.ADspaceSheet.close();
          msg('setMsg', rows.length + ' post' + (rows.length === 1 ? '' : 's') + ' added.', 'ok');
          loadPosts();
          loadBatches();
        });
      });
  }

  // ---- Saved posts --------------------------------------------------------
  /* Once a post is in the set it is shown as settled rather than as a form.
     Editing is deliberate, so a stray click cannot change what a client sees. */
  /* The strip, the covers line and the progress belong to the set they were
     counted for (the user, 2026-10-06: opening another client's set still
     showed the last one's counts, since a set with no posts never redrew
     them). They are cleared on a new set, and an answer for a set no longer
     open is thrown away. */
  function clearPostView() {
    state.postView = null;
    state.postPick = null;
    state.postShown = [];
    if ($('postBulk')) $('postBulk').hidden = true;
    $('postStages').hidden = true;
    $('postStages').innerHTML = '';
    $('pairNote').hidden = true;
    $('setProgressBlock').hidden = true;
  }
  function loadPosts() {
    if (!state.batch) return;
    var bid = state.batch.id;
    if (!state.postView || state.postView.batch !== bid) {
      clearPostView();
      $('postList').innerHTML = '';
      $('savedCount').textContent = '';
    }
    var here = function () { return state.batch && state.batch.id === bid; };
    db.from('posts').select('*').eq('batch_id', bid).order('position')
      .then(function (r) {
        if (!here()) return;
        var box = $('postList');
        box.innerHTML = '';
        /* A failed read used to print "Nothing added yet." over a set that
           was full, which is the one message that makes somebody add a post
           twice. */
        if (r.error) {
          $('savedCount').textContent = '';
          failLine(box, 'Posts', r.error.message, loadPosts);
          settleScroll();
          return;
        }
        var n = (r.data || []).length;
        $('savedCount').textContent = n
          ? n + ' post' + (n === 1 ? '' : 's')
          : 'No posts.';
        $('setProgressBlock').hidden = true;
        if (!n) { clearPostView(); settleScroll(); return; }

        var ids = r.data.map(function (p) { return p.id; });
        /* The decision on the round on show, what was asked of the round
           before it, and the rounds kept (POST REVISIONS, 2026-09-30). A
           database from before the rounds answers without them, and the page
           reads every decision as the first round's. */
        Promise.all([
          db.from('reviews').select('*').in('post_id', ids).order('created_at', { ascending: false }),
          db.from('post_versions').select('*').in('post_id', ids).order('round', { ascending: false })
        ]).then(function (both) {
            if (!here()) return;
            var rev = both[0], vers = both[1];
            var latest = {}, asked = {}, kept = {}, earlier = {};
            var byId = {};
            r.data.forEach(function (p) { byId[p.id] = p; });
            (rev.data || []).forEach(function (x) {
              var p = byId[x.post_id];
              /* A team approval taken back is kept but no longer stands. */
              if (!p || x.undone_at) return;
              var round = x.round || 1, now = p.round || 1;
              if (round === now && (!p.review_reset_at || x.created_at > p.review_reset_at)) {
                if (!latest[x.post_id]) latest[x.post_id] = x;
                /* A request on this round that an approval since replaced:
                   kept in sight, so the team knows what was asked. */
                else if (latest[x.post_id].decision === 'approved' && x.decision === 'changes' && !earlier[x.post_id]) earlier[x.post_id] = x;
              } else if (round === now - 1 && x.decision === 'changes' && !asked[x.post_id]) {
                asked[x.post_id] = x;
              }
            });
            (vers.error ? [] : vers.data || []).forEach(function (v) {
              (kept[v.post_id] = kept[v.post_id] || []).push(v);
            });
            state.postView = { batch: bid, posts: r.data, latest: latest, asked: asked, kept: kept, earlier: earlier };
            paintPostStages(true);
            paintProgress(r.data, latest, !rev.error);
            settleScroll();
          });
      });
  }

  /* The set's posts by stage, as the view strip with each stage's count in
     its tab: a set of thirty mixed outcomes is a work list, not one long
     scroll (the user, 2026-09-30). Opens on Changes requested while there is
     any, else All; the choice is kept per set while the page is open. */
  var POST_STAGES = [['pending', 'Pending'], ['changes', 'Changes requested'], ['approved', 'Approved'], ['all', 'All']];
  /* A stage's count wears its chip's tone where it counts any. */
  var STAGE_TONE = { pending: 'is-warn', changes: 'is-err', approved: 'is-ok' };
  var postStageBy = {};
  function stageWord(s) {
    /* On a phone the longest stage takes its short word, so all four fit the
       column's width without scrolling (the user, 2026-09-30). */
    return s[0] === 'changes'
      ? '<span class="tab-long">' + s[1] + '</span><span class="tab-short">Changes</span>'
      : s[1];
  }
  function postStageOf(review) {
    return !review ? 'pending' : review.decision === 'approved' ? 'approved' : 'changes';
  }
  /* The set's videos, named by their place in it, for a cover to belong to.
     Named by what tells one video from the next: its title, else the first
     words of its caption, else its file, else its placement (the user,
     2026-10-03: thirty reels all read Instagram Reels). */
  function videosOf(posts) {
    var vn = 0, videos = [];
    (posts || []).forEach(function (p) {
      var m0 = (p.media || [])[0];
      if (p.platform !== 'cover' && (p.media || []).length === 1 && m0 && m0.type === 'video') {
        var said = String(p.title || '').trim() ||
          String(p.caption || '').split(/\n/)[0].trim() || String(m0.name || '').trim();
        if (said.length > 48) said = said.slice(0, 47).replace(/\s+\S*$/, '') + '…';
        vn++; videos.push({ id: p.id, n: vn, pos: p.position, media: m0, label: 'Video ' + vn + ' · ' + (said || MK.label(p)) });
      }
    });
    return videos;
  }

  function paintPostStages(fresh) {
    var v = state.postView, box = $('postList'), strip = $('postStages');
    if (!v || !state.batch || v.batch !== state.batch.id) return;
    var counts = { pending: 0, changes: 0, approved: 0, all: v.posts.length };
    v.posts.forEach(function (p) { counts[postStageOf(v.latest[p.id])]++; });
    var id = state.batch.id;
    var decided = counts.changes + counts.approved > 0;
    var pick = postStageBy[id];
    if (!pick || (pick !== 'all' && !counts[pick])) pick = counts.changes ? 'changes' : 'all';
    if (!decided && !state.batch.published) pick = 'all';
    postStageBy[id] = pick;
    /* A set nobody has decided on yet has one stage, so the strip would
       only restate the count. */
    strip.hidden = !decided;
    strip.innerHTML = POST_STAGES.map(function (s) {
      var on = s[0] === pick;
      return '<button class="tab' + (on ? ' is-on' : '') + '" type="button" role="tab" data-stage="' + s[0] + '"' +
        ' aria-selected="' + on + '" tabindex="' + (on ? 0 : -1) + '">' + stageWord(s) +
        ' <span class="tab-n' + (counts[s[0]] && STAGE_TONE[s[0]] ? ' ' + STAGE_TONE[s[0]] : '') + '">' + counts[s[0]] + '</span></button>';
    }).join('');
    box.innerHTML = '';
    var videos = videosOf(v.posts);
    var isVideo = {}, coversOf = {}, holder = {};
    videos.forEach(function (x) { isVideo[x.id] = x; });
    /* A cover is paired while the video it names is still a video in this
       set; one whose video was deleted waits again, as it reads. */
    var paired = function (p) { return p.platform === 'cover' && p.cover_for && isVideo[p.cover_for]; };
    v.posts.forEach(function (p) { if (paired(p) && !holder[p.cover_for]) holder[p.cover_for] = p.id; });
    /* Covers waiting for a video say so on the page, with the way to pair
       them beside the count (the user, 2026-10-03: the ⋯ hid it). */
    var waiting = videos.length ? v.posts.filter(function (p) { return p.platform === 'cover' && !paired(p); }).length : 0;
    $('pairNote').hidden = !waiting;
    $('pairNoteText').textContent = waiting + (waiting === 1 ? ' cover has no video' : ' covers have no video');
    /* A video and the cover paired with it are one linked card: the video,
       then its cover attached under it in one frame, each still its own row
       with its own state, ⋯ and notes (the user, 2026-10-03: a line of text
       naming the video read as complicated). The pair shows while either
       half is in the chosen stage; the other half stays in sight, faded, so
       the two are never parted. */
    var shown = function (p) { return pick === 'all' || postStageOf(v.latest[p.id]) === pick; };
    var rowOf = function (p, inPair) {
      return savedRow(p, v.latest[p.id], { asked: v.asked[p.id], kept: v.kept[p.id] || [],
        earlier: (v.earlier || {})[p.id], videos: videos, inPair: inPair, holder: holder });
    };
    v.posts.forEach(function (p) { if (paired(p)) (coversOf[p.cover_for] = coversOf[p.cover_for] || []).push(p); });
    v.posts.forEach(function (p) {
      if (paired(p)) return;
      var covers = coversOf[p.id];
      if (!covers) { if (shown(p)) box.appendChild(rowOf(p, false)); return; }
      var halves = [p].concat(covers);
      if (!halves.some(shown)) return;
      var g = document.createElement('div');
      g.className = 'saved-pair';
      g.setAttribute('role', 'group');
      g.setAttribute('aria-label', isVideo[p.id].label + ' with its cover');
      halves.forEach(function (h) {
        var r = rowOf(h, true);
        if (!shown(h)) r.classList.add('is-aside');
        g.appendChild(r);
      });
      box.appendChild(g);
    });
    state.postShown = v.posts.filter(shown).map(function (p) { return p.id; });
    paintPostBulk();
    if (!box.children.length) UI.emptyLine(box, 'No posts.');
  }
  $('postStages').addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('.tab');
    if (!b || !state.batch) return;
    postStageBy[state.batch.id] = b.getAttribute('data-stage');
    paintPostStages();
  });
  $('postStages').addEventListener('keydown', function (e) {
    var tabs = Array.prototype.slice.call(this.querySelectorAll('.tab'));
    var i = tabs.indexOf(document.activeElement);
    if (i < 0) return;
    var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
    if (to === null) return;
    e.preventDefault();
    to = (to + tabs.length) % tabs.length;
    postStageBy[state.batch.id] = tabs[to].getAttribute('data-stage');
    paintPostStages();
    var again = this.querySelector('.tab[data-stage="' + postStageBy[state.batch.id] + '"]');
    if (again) again.focus();
  });

  /* Where the client's review of a published set stands, in the rail: how
     many are approved, and how many came back with changes. Drawn only once
     the set is published and the decisions could be read. */
  function paintProgress(posts, latest, read) {
    var block = $('setProgressBlock');
    if (!read || !state.batch || !state.batch.published) { block.hidden = true; return; }
    var n = posts.length, ok = 0, ch = 0;
    posts.forEach(function (p) {
      var d = latest[p.id];
      if (d && d.decision === 'approved') ok++;
      else if (d) ch++;
    });
    var pct = n ? Math.round(ok / n * 100) : 0;
    $('setProgress').innerHTML =
      '<p class="railpct"><b>' + ok + ' of ' + n + ' approved</b><span>' + pct + '%</span></p>' +
      '<span class="railbar"><span class="railbar-fill" style="width:' + pct + '%"></span></span>' +
      (ch ? '<p class="setprog-note"><span class="tone is-danger">' + ch + ' changes requested</span></p>' : '');
    block.hidden = false;
  }

  // The ⋯ this portal draws everywhere a row hides its rarer actions.
  var DOTS = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
    '<circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';

  var ICON = {
    pencil: '<path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17z"/><path d="M14.5 6.5l3 3"/>',
    trash:  '<path d="M4 7h16"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7"/>' +
            '<path d="M6.5 7 7.4 19a1.6 1.6 0 0 0 1.6 1.5h6a1.6 1.6 0 0 0 1.6-1.5L17.5 7"/>',
    redo:   '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 4v4h-4"/>',
    copy:   '<rect x="9" y="9" width="11" height="11" rx="2"/>' +
            '<path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/>',
    tick:   '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    qr:     '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/>' +
            '<rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3z"/>' +
            '<path d="M20 14v3M14 20h3M20 20h.01"/>',
    out:    '<path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>'
  };

  /* The rail's own drawing for a section, for a list that mixes sections
     (the bell, search, Waiting for you), so a line says where it will take
     you in the shape the rail already taught (2026-10-08). Read from the
     rail itself: one copy of every glyph. My records lives in the account
     menu, and the Creators List and My Work answer to their rail rows. */
  var GLYPH_OF = { ops: 'work', creators: 'campaigns' };
  function sectionGlyph(key) {
    var el = key === 'mine' ? document.querySelector('#myPerf svg')
      : document.querySelector('.navitem[data-section="' + (GLYPH_OF[key] || key) + '"] svg');
    if (!el) return '';
    var g = el.cloneNode(true);
    g.removeAttribute('width'); g.removeAttribute('height'); g.removeAttribute('class');
    g.setAttribute('aria-hidden', 'true');
    return g.outerHTML;
  }

  /* A round mark with the action named for anyone who cannot see the shape. */
  function iconBtn(name, action, label, tone) {
    return '<button class="iconbtn' + (tone ? ' ' + tone : '') + '" data-a="' + action +
      '" type="button" title="' + label + '" aria-label="' + label + '">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" ' +
      'stroke-linejoin="round" aria-hidden="true">' + ICON[name] + '</svg></button>';
  }

  /* THE BUSINESS FIGURES (2026-10-05): follow-up limits, SST, the term
     percentages and the report deadline are settings an admin changes from a
     day on (`app_settings_set`, today or later, so an issued letter keeps
     the figures of its day). One sheet for every group of them: From, then
     each figure as it stands today; only what changed is sent; the page
     reads the figures again and repaints. `spec`: { title, keys: [[key,
     label, kind]], msg (an element id), done }. Kinds: hours, days, pct
     (0 to 100), adj (-100 to 100). */
  var SET_BOUND = { hours: [1, 720, true], days: [1, 365, true], due: [1, 60, true], pct: [0, 100, false], adj: [-100, 100, false], usd: [0, 1000, false], allow: [0, 5, false] };
  function editSettings(spec, opener) {
    var MON = window.ADspaceMoney;
    if (!may('team.settings', 'work') || !MON) return;
    var day = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kuala_Lumpur' });
    var fields = [{ name: 'from', label: 'From', type: 'date', value: day, min: day, required: true }].concat(spec.keys.map(function (k, i) {
      return { name: k[0], label: k[1], type: 'number', value: String(MON.setting(k[0])), required: true,
        half: spec.keys.length > 1 && !(spec.keys.length % 2 && i === spec.keys.length - 1) };
    }));
    window.ADspaceConfirm.ask({
      title: spec.title, go: 'Save', fields: fields,
      check: function (v) {
        if (!v.from || v.from < day) return 'From is today or a later day.';
        for (var i = 0; i < spec.keys.length; i++) {
          var k = spec.keys[i], b = SET_BOUND[k[2]], x = String(v[k[0]] == null ? '' : v[k[0]]).trim(), n = Number(x);
          if (x === '' || isNaN(n) || n < b[0] || n > b[1] || (b[2] && n % 1) || Math.round(n * 100) !== n * 100) {
            return k[1] + ': ' + (b[2] ? 'a whole number from ' : 'a number from ') + b[0] + ' to ' + b[1] + '.';
          }
        }
        return '';
      }
    }, function (v) {
      var vals = {};
      spec.keys.forEach(function (k) { var n = Number(v[k[0]]); if (n !== MON.setting(k[0], v.from)) vals[k[0]] = n; });
      if (!Object.keys(vals).length) { if (spec.msg) msg(spec.msg, 'No change.', 'ok'); return; }
      db.rpc('app_settings_set', { p_from: v.from, p_values: vals }).then(function (r) {
        var d = r.data || {};
        if (r.error || d.error) {
          if (spec.msg) msg(spec.msg, r.error ? (/function|schema cache/i.test(r.error.message) ? 'This needs a database update.' : r.error.message)
            : d.error === 'past' ? 'From is today or a later day.' : d.error === 'denied' ? 'This needs Team: Business settings.'
            : d.error === 'bad-value' ? 'A figure is out of range.' : d.error, 'err');
          return;
        }
        return MON.load(true).then(function () {
          var word = new Date(v.from + 'T00:00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
          if (spec.msg) msg(spec.msg, 'Saved. From ' + word + '.', 'ok');
          if (spec.done) spec.done();
        });
      }).catch(function (e) { if (spec.msg) msg(spec.msg, String((e && e.message) || e), 'err'); });
    });
  }

  /* Creator Campaigns lives in its own file, because this one is long enough.
     It needs the same marks, the same activity record and the same idea of who
     is signed in, so those are lent rather than written twice. */
  window.ADspaceAdmin = {
    wireLogoUpload: wireLogoUpload,
    editSettings: editSettings,
    isAdmin: isAdminMe,
    ICON: ICON,
    glyph: sectionGlyph,
    isSystem: isSystem,
    hold: hold,
    iconBtn: iconBtn,
    /* The one list of what each logged action is called. The client record's
       Activity pane reads it rather than keeping a second copy that would
       drift from the activity record's own. */
    actionLabel: ACTION_LABEL,
    /* One activity row as one record line, the same words everywhere. */
    record: recordOf,
    log: logAction,
    actor: function () { return actor; },
    actorName: function () { return (me && me.name) || actor; },
    /* The client record and a campaign draw their own activity excerpt, so
       they resolve a logged address through the same map rather than keeping
       a second one that would answer differently. */
    whoName: whoName,
    // The signed PUT to S3, so an invoice PDF travels the same road as media.
    putToS3: putToS3,
    // Where you are, and how far down. The address bar is shared property.
    setUrl: setUrl,
    pushUrl: pushUrl,
    restoreScroll: restoreScroll,
    // Campaigns announces itself once its script has run; if the rail asked
    // for it before then, enter now.
    campaignsReady: function () {
      if (enterLater !== 'campaigns' || section !== 'campaigns') return;
      enterLater = '';
      window.ADspaceCampaigns.enter();
    },
    crmReady: function () {
      if (enterLater === 'services' && section === 'services') {
        enterLater = '';
        window.ADspaceCRM.enterServices();
        return;
      }
      if (enterLater !== 'clients' || section !== 'clients') return;
      enterLater = '';
      window.ADspaceCRM.enter();
    },
    teamReady: function () {
      if (enterLater !== 'team' || section !== 'team' || !window.ADspacePerf) return;
      enterLater = '';
      window.ADspacePerf.enterTeam();
    },
    perfReady: function () {
      if (enterLater === 'mine' && section === 'mine') { enterLater = ''; window.ADspacePerf.enterMine(); return; }
      if (enterLater !== 'team' || section !== 'team' || !window.ADspaceTeam) return;
      enterLater = '';
      window.ADspacePerf.enterTeam();
    },
    scriptsReady: function () {
      if (enterLater !== 'scripts' || section !== 'scripts') return;
      enterLater = '';
      window.ADspaceScripts.enter();
    },
    settingsReady: function () {
      if (enterLater !== 'settings' || section !== 'settings') return;
      enterLater = '';
      window.ADspaceSettings.enter();
      setUrl();
    },
    handbookReady: function () {
      if (enterLater !== 'handbook' || section !== 'handbook') return;
      enterLater = '';
      window.ADspaceHandbook.enter();
    },
    reportsReady: function () {
      if (enterLater !== 'reports' || section !== 'reports') return;
      enterLater = '';
      window.ADspaceReports.enterHub();
    },
    overviewReady: function () {
      if (enterLater !== 'overview' || section !== 'overview') return;
      enterLater = '';
      window.ADspaceOverview.enter();
    },
    opsReady: function () {
      if (enterLater !== 'work' || section !== 'work') return;
      enterLater = '';
      window.ADspaceOps.enter();
    },
    // The signed-in person's team row, for sections that gate on it.
    me: function () { return me; },
    /* Open a section from outside the rail: the bell opens the task a row
       names, after writing the address the section reads on entry. */
    show: function (name) { visitSection(name); },
    /* ===== Console search (js/search.js) =====
       Land where the address says, the way a reload does: a content set is
       reached through its client, which only this file opens. */
    restore: function () { restoreView(); },
    /* ===== end console search ===== */
    may: may,
    upgradeState: function () { return upgrade; },
    upgradeToggle: upgradeToggle,
    parts: PARTS
  };

  /* Pending, approved, changes requested. The dot is what you scan for; the
     word is what makes it mean something. */
  /* The client's decision as the portal's chip (`.status-*`): warn while
     it waits, rose for changes requested, green once approved. A word,
     never a coloured dot. */
  function statusMark(review) {
    var kind = !review ? 'pending'
             : review.decision === 'approved' ? 'approved' : 'changes';
    var word = kind === 'pending' ? 'Pending'
             /* "requested" gives way on a narrow pane, as the stage strip's
                tab does, so the placement's name keeps its one line. */
             : kind === 'approved' ? 'Approved' : 'Changes<span class="chip-more"> requested</span>';
    return '<span class="tone ' + (kind === 'approved' ? 'is-ok' : kind === 'changes' ? 'is-danger' : 'is-warn') + '">' + word + '</span>';
  }

  function shutPostMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#postList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#postList .kmenu-btn'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#postList .kmenu, #postList .kmenu-btn')) shutPostMenus();
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutPostMenus(); });
  window.ADspaceMenu.onScroll(shutPostMenus);

  /* The client's edit to the copy, kept on their request as a suggestion:
     what they would have it read, and Accept caption to make it the next
     round's copy without retyping (2026-09-30). */
  function suggestHtml(review) {
    if (!review || review.decision !== 'changes') return '';
    var cap = review.suggested_caption, zh = review.suggested_caption_zh;
    if (cap == null && zh == null) return '';
    return '<div class="saved-suggest">' +
      '<span class="saved-suggest-h">Suggested caption</span>' +
      (cap != null ? '<p class="saved-suggest-t">' + esc(cap) + '</p>' : '') +
      (zh != null ? '<p class="saved-suggest-t">' + esc(zh) + '</p>' : '') +
      '<button class="btn btn-sm" data-a="accept" data-need="review.sets:work" type="button">Accept caption</button>' +
      '</div>';
  }
  /* The rounds this post replaced, for the team alone: the client's page
     never carries them. Folded, newest first, each opening its file. */
  function keptHtml(kept) {
    if (!kept || !kept.length) return '';
    return '<details class="saved-kept"><summary>Earlier rounds (' + kept.length + ')</summary>' +
      kept.map(function (v) {
        var vm = (v.media || [])[0] || {};
        return '<div class="saved-kept-row">' +
          '<span class="saved-kept-n">Round ' + v.round + '</span>' +
          '<span class="saved-kept-t">' + esc((v.caption || v.caption_zh || '').slice(0, 90)) + '</span>' +
          (vm.url ? '<a class="plink" href="' + esc(vm.url) + '" target="_blank" rel="noopener">' + esc(fileLabel(vm) || 'File') + '</a>' : '') +
          '</div>';
      }).join('') + '</details>';
  }

  /* A video's thumbnail in the console: its cover frame where the upload
     kept one, else the first frame asked for by a media fragment. A bare
     <video> draws nothing on iPhone Safari until it plays, which left every
     reel an empty box (the user, 2026-10-01). */
  function thumbOf(m) {
    if (m.type !== 'video') return '<img src="' + esc(m.url || '') + '" alt="">';
    if (m.poster) return '<img src="' + esc(m.poster) + '" alt="">';
    return ADspaceMedia.still(m.url);
  }

  function coverWord(p, videos) {
    var v = (videos || []).filter(function (x) { return x.id === p.cover_for; })[0];
    return v ? 'Cover for ' + v.label : 'No video';
  }

  var CONFIRM_SAID = {
    denied: 'Not allowed for this group.',
    'no-post': 'That post is no longer there.',
    'not-published': 'Publish the set first. The client sees only a published set.',
    'already-approved': 'Already approved.',
    'not-confirmed': 'There is no internal confirmation to take back.'
  };
  function confirmSaid(e) {
    var k = String(e || '');
    if (/review_(revert_)?confirm/.test(k) && /(does not exist|Could not find)/i.test(k)) return 'This needs a database update.';
    return CONFIRM_SAID[k] || k || 'Not saved.';
  }

  /* SELECT POSTS (the user, 2026-10-06: Select where many items are acted
     on): the set's ⋯ turns each post shown into its tick, at the right edge
     where its ⋯ was; the bar under the stage strip counts them and offers
     what the ticked posts can take, each as one post takes it: Confirm
     internally (a published set; posts not approved), Request re-approval
     (posts the client approved), Delete (the count typed back). */
  function setPostPicking(on) {
    state.postPick = on ? {} : null;
    msg('postBulkMsg', '');
    if (state.postView) paintPostStages(); else paintPostBulk();
  }
  function pickedPosts() {
    var v = state.postView;
    return v ? v.posts.filter(function (p) { return state.postPick && state.postPick[p.id]; }) : [];
  }
  function postConfirmable(p) { var r = state.postView && state.postView.latest[p.id]; return !r || r.decision !== 'approved'; }
  function postReaskable(p) { var r = state.postView && state.postView.latest[p.id]; return Boolean(r && r.decision === 'approved' && r.source !== 'team'); }
  function paintPostBulk() {
    var bar = $('postBulk');
    if (!bar) return;
    bar.hidden = !state.postPick || !state.postView;
    if (bar.hidden) return;
    var ids = state.postShown || [];
    Object.keys(state.postPick).forEach(function (id) { if (ids.indexOf(id) < 0) delete state.postPick[id]; });
    var n = Object.keys(state.postPick).length;
    $('postBulkCount').textContent = n + ' selected';
    var all = $('postBulkAll');
    all.checked = n > 0 && n === ids.length;
    all.indeterminate = n > 0 && n < ids.length;
    all.setAttribute('aria-label', n && n === ids.length ? 'Clear the selection' : 'Select every post shown');
    /* An act is drawn once a ticked post can take it, never greyed. */
    var picked = pickedPosts();
    $('postBulkConfirm').hidden = !(state.batch && state.batch.published) || !picked.some(postConfirmable);
    $('postBulkReask').hidden = !picked.some(postReaskable);
    $('postBulkDelete').disabled = !n;
  }
  /* One post after another, so a refusal is named against its post. */
  function eachPost(list, act) {
    var out = { ok: [], bad: [] };
    return list.reduce(function (pr, p) {
      return pr.then(function () {
        return Promise.resolve(act(p)).then(function (err) { (err ? out.bad : out.ok).push({ p: p, err: err }); })
          .catch(function (e) { out.bad.push({ p: p, err: (e && e.message) || String(e) }); });
      });
    }, Promise.resolve()).then(function () { return out; });
  }
  function postsWord(n) { return n + (n === 1 ? ' post' : ' posts'); }
  function badPosts(out) {
    return out.bad.length ? out.bad.length + ' not: ' + out.bad.slice(0, 3).map(function (x) {
      return MK.label(x.p) + ' (' + x.err + ')';
    }).join(', ') + (out.bad.length > 3 ? '…' : '') + '.' : '';
  }
  function bulkPostConfirm() {
    var list = pickedPosts().filter(postConfirmable);
    if (!list.length) return;
    var who = (state.client && state.client.name) || 'the client';
    window.ADspaceConfirm.ask({
      title: 'Confirm ' + postsWord(list.length) + ' internally?',
      body: 'Each is approved on the client\u2019s behalf. Their review page reads Confirmed by ' + who + '.',
      go: 'Confirm'
    }, function () {
      eachPost(list, function (p) {
        return db.rpc('review_confirm', { p_post: p.id }).then(function (res) {
          var d = (res && res.data) || {};
          return res.error || d.error ? confirmSaid(res.error ? res.error.message : d.error) : null;
        });
      }).then(function (out) {
        state.postPick = null;
        loadPosts();
        msg('postBulkMsg', badPosts(out), out.bad.length ? 'warn' : '');
        if (!out.ok.length) return;
        undoHere(postsWord(out.ok.length) + ' confirmed internally.', function () {
          eachPost(out.ok.map(function (x) { return x.p; }), function (p) {
            return db.rpc('review_revert_confirm', { p_post: p.id }).then(function (res) {
              var d = (res && res.data) || {};
              return res.error || d.error ? confirmSaid(res.error ? res.error.message : d.error) : null;
            });
          }).then(function (back) {
            loadPosts();
            msg('postBulkMsg', back.bad.length ? badPosts(back) : 'Confirmation reverted.', back.bad.length ? 'warn' : 'ok');
          });
        }, $('postBulk'));
      });
    });
  }
  function bulkPostReask() {
    var list = pickedPosts().filter(postReaskable);
    if (!list.length) return;
    window.ADspaceConfirm.ask({
      title: 'Request re-approval for ' + postsWord(list.length) + '?', go: 'Request re-approval',
      field: { label: 'Reason for re-approval', rows: 3, need: 'Say why the client is asked again.',
        placeholder: 'Why the client is being asked again. They read this.' }
    }, function (why) {
      eachPost(list, function (p) {
        return db.from('posts').update({ review_reset_at: new Date().toISOString(), review_reset_note: why })
          .eq('id', p.id).select('id').then(function (r) {
            if (r.error) return r.error.message;
            if (!(r.data || []).length) return 'refused';
            logAction('reapproval.requested', state.client.name + ' \u2014 ' + MK.label(p), why);
            return null;
          });
      }).then(function (out) {
        state.postPick = null;
        loadPosts();
        msg('postBulkMsg', ((out.ok.length ? 'Re-approval requested for ' + postsWord(out.ok.length) + '. ' : '') + badPosts(out)).trim(),
          out.bad.length ? 'warn' : 'ok');
      });
    });
  }
  function bulkPostDelete() {
    var list = pickedPosts();
    var n = list.length;
    if (!n) return;
    window.ADspaceConfirm.ask({
      title: 'Delete ' + postsWord(n),
      body: (n === 1 ? 'It leaves the client view, with its approval record.' : 'They leave the client view, with their approval records.') + ' There is no restore.',
      go: 'Delete', tone: 'danger',
      fields: [{ name: 'n', label: 'Type ' + n + ' to confirm', match: String(n), mismatch: 'Type ' + n + ' to confirm.' }]
    }, function () {
      eachPost(list, function (p) {
        return db.from('posts').delete().eq('id', p.id).select('id').then(function (r) {
          if (r.error) return r.error.message;
          if (!(r.data || []).length) return 'Not deleted. The database refused the request.';
          logAction('post.deleted', state.client.name + ' \u2014 ' + state.batch.title, MK.label(p));
          return null;
        });
      }).then(function (out) {
        state.postPick = null;
        loadPosts(); loadBatches();
        msg('postBulkMsg', ((out.ok.length ? postsWord(out.ok.length) + ' deleted. ' : '') + badPosts(out)).trim(),
          out.bad.length ? 'warn' : 'ok');
      });
    });
  }
  $('selectPosts').addEventListener('click', function () { shutSetMenu(); setPostPicking(true); });
  /* The set's content month: last month, this month and the next six, the
     month it holds, or Ad hoc; filed from and to (2026-10-10). */
  $('setMonth').addEventListener('click', function () {
    shutSetMenu();
    var b = state.batch, now = ymNow(), opts = [];
    for (var i = -1; i <= 6; i++) opts.push(ymAdd(now, i));
    if (b.period && opts.indexOf(b.period) < 0) opts.unshift(b.period);
    window.ADspaceConfirm.ask({
      title: 'Content month', go: 'Save',
      field: { label: 'Month', required: false, choices: opts.map(function (m) { return [m, ymWord(m)]; }).concat([['', 'Ad hoc']]), value: b.period || '' }
    }, function (v) {
      var next = v || null;
      if ((b.period || null) === next) return;
      db.from('batches').update({ period: next }).eq('id', b.id).select('id, period').then(function (r) {
        if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('setMsg', 'Not saved. The database refused the request.', 'err'); return; }
        logAction('set.month', state.client.name + ' — ' + b.title, 'Content month: ' + ymWord(b.period) + ' → ' + ymWord(next));
        b.period = next;
        paintSetHeader();
        msg('setMsg', 'Saved.', 'ok');
        loadBatches();
      }).catch(function (e) { msg('setMsg', (e && e.message) || String(e), 'err'); });
    });
  });
  $('postBulkDone').addEventListener('click', function () { setPostPicking(false); });
  $('postBulkConfirm').addEventListener('click', bulkPostConfirm);
  $('postBulkReask').addEventListener('click', bulkPostReask);
  $('postBulkDelete').addEventListener('click', bulkPostDelete);
  $('postBulkAll').addEventListener('change', function () {
    var on = this.checked;
    state.postPick = {};
    if (on) (state.postShown || []).forEach(function (id) { state.postPick[id] = 1; });
    paintPostStages();
  });

  function savedRow(p, review, extra) {
    extra = extra || {};
    var row = document.createElement('div');
    row.className = 'saved';
    row.addEventListener('click', function (e) {
      if (!state.postPick || row.classList.contains('is-editing')) return;
      if (e.target.closest && e.target.closest('input, button, a, textarea, select, label, video')) return;
      var t = row.querySelector('.saved-pick input');
      if (!t) return;
      t.checked = !t.checked;
      t.dispatchEvent(new Event('change'));
    });
    var m = (p.media || [])[0] || {};
    var round = p.round || 1;
    /* A change after the client decided is the next round (the database
       keeps the one it replaces), so the edit form says so before it saves. */
    var decided = !!review;

    function paintRead() {
      row.classList.remove('is-editing');
      row.innerHTML =
        '<div class="saved-thumb">' +
          thumbOf(m) + '</div>' +
        /* The placement with the client's decision at the right of its line,
           then the file, then the copy: one row, and its acts in one ⋯
           (2026-09-28; the pencil and the bin had a line of their own). */
        '<div class="saved-body">' +
          '<span class="saved-top"><b>' + MK.label(p) + '</b>' + statusMark(review) + '</span>' +
          '<span class="saved-meta">' +
            (round > 1 ? '<span class="saved-round">Revision ' + round + '</span><span class="sep">·</span>' : '') +
            /* A video's number in the set, the one the cover's choice names. */
            ((extra.videos || []).filter(function (x) { return x.id === p.id; }).map(function (x) {
              return '<span>Video ' + x.n + '</span><span class="sep">·</span>';
            })[0] || '') +
            '<span class="spec">' + esc(fileLabel(m)) + '</span>' +
            /* Inside its video's card the cover needs no words for whose it is. */
            (p.platform === 'cover' && !extra.inPair ? '<span class="sep">·</span><span>' + esc(coverWord(p, extra.videos)) + '</span>' : '') +
            '</span>' +
          // A post with no copy yet says nothing rather than saying "No caption".
          ((p.caption || p.caption_zh)
            ? '<span class="muted">' + esc((p.caption || p.caption_zh).slice(0, 90)) + '</span>'
            : '') +
          (review && review.decision === 'changes' && review.note
            ? '<span class="saved-note">' + esc(review.note) + '</span>' : '') +
          (review && review.decision === 'approved' && review.source === 'team'
            ? '<span class="saved-asked">Confirmed internally by ' + esc(review.reviewer || 'the team') + '</span>' : '') +
          /* The request this approval replaced, kept in sight. */
          (review && review.decision === 'approved' && extra.earlier
            ? '<span class="saved-asked">Earlier request: ' +
                esc([extra.earlier.note, extra.earlier.suggested_caption != null || extra.earlier.suggested_caption_zh != null ? 'caption edit' : '']
                  .filter(Boolean).join(' · ') || 'no note') + '</span>' : '') +
          suggestHtml(review) +
          /* What this round answers, while the client has not decided on it. */
          (!review && extra.asked && extra.asked.note
            ? '<span class="saved-asked">Asked: ' + esc(extra.asked.note) + '</span>' : '') +
          keptHtml(extra.kept) +
          (p.review_reset_note
            ? '<span class="saved-note is-warn">Sent back: ' + esc(p.review_reset_note) + '</span>'
            : '') +
        '</div>' +
        (state.postPick
          ? '<label class="saved-actions saved-pick"><input class="trow-pick" type="checkbox"' + (state.postPick[p.id] ? ' checked' : '') +
              ' aria-label="Select ' + esc(MK.label(p)) + '"></label>'
          : '<div class="saved-actions">' +
          '<button class="kmenu-btn" data-a="menu" type="button" aria-haspopup="true" aria-expanded="false" aria-label="More for ' + esc(MK.label(p)) + '">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden role="menu">' +
            '<button class="kmenu-item" data-a="edit" data-need="review.sets:work" type="button" role="menuitem">Edit</button>' +
            (p.platform === 'cover' && (extra.videos || []).length
              ? '<button class="kmenu-item" data-a="pair" data-need="review.sets:work" type="button" role="menuitem">Pair with video</button>' : '') +
            /* The client said yes by word of mouth: the team approves the
               round on show for them (the user, 2026-10-01). Its way back is
               Revert confirmation; a client's own approval is asked again. */
            /* Only on a set the client can see: an unpublished one has
               nothing for them to have agreed to. */
            ((!review || review.decision !== 'approved') && state.batch && state.batch.published
              ? '<button class="kmenu-item" data-a="confirm" data-need="review.sets:work" type="button" role="menuitem">Confirm internally</button>' : '') +
            (review && review.decision === 'approved' && review.source === 'team'
              ? '<button class="kmenu-item" data-a="unconfirm" data-need="review.sets:work" type="button" role="menuitem">Revert confirmation</button>' : '') +
            (review && review.decision === 'approved' && review.source !== 'team'
              ? '<button class="kmenu-item" data-a="reask" data-need="review.sets:work" type="button" role="menuitem">Request re-approval</button>' : '') +
            '<button class="kmenu-item is-danger" data-a="del" data-need="review.sets:manage" type="button" role="menuitem">Delete</button>' +
          '</div>' +
        '</div>');

      /* Picking (Select posts, 2026-10-07): the row is ticked, not acted on. */
      row.classList.toggle('is-picking', Boolean(state.postPick));
      row.classList.toggle('is-picked', Boolean(state.postPick && state.postPick[p.id]));
      if (state.postPick) {
        var tick = row.querySelector('.saved-pick input');
        tick.addEventListener('change', function () {
          if (!state.postPick) return;
          if (tick.checked) state.postPick[p.id] = 1; else delete state.postPick[p.id];
          row.classList.toggle('is-picked', tick.checked);
          paintPostBulk();
        });
        return;
      }

      var mbtn = row.querySelector('[data-a="menu"]'), menu = row.querySelector('[data-menu]');
      mbtn.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = menu.hidden;
        shutPostMenus();
        if (!open) return;
        menu.hidden = false;
        mbtn.setAttribute('aria-expanded', 'true');
        window.ADspaceMenu.place(mbtn, menu);
      });
      row.querySelector('[data-a="edit"]').addEventListener('click', function () { shutPostMenus(); paintEdit(); });
      /* A cover's video, chosen again or cleared: the client's page shows the
         two as one card with a tab each. Not a revision: the file is the same. */
      var pairBtn = row.querySelector('[data-a="pair"]');
      if (pairBtn) pairBtn.addEventListener('click', function () {
        shutPostMenus();
        /* A video another cover already holds is not offered: the client's
           page shows one cover a reel, so a second would stand alone there. */
        var holder = extra.holder || {};
        var choices = [['', 'No video']].concat((extra.videos || []).filter(function (x) {
          return !holder[x.id] || holder[x.id] === p.id;
        }).map(function (x) { return [x.id, x.label]; }));
        window.ADspaceConfirm.ask({
          title: 'Pair with video',
          body: 'The client sees the cover and its video as one card, each decided on its own.',
          go: 'Save',
          field: { label: 'Video', choices: choices, value: p.cover_for || '', required: false }
        }, function (val) {
          var to = (val && typeof val === 'object' ? val[0] : val) || null;
          db.from('posts').update({ cover_for: to }).eq('id', p.id).select('id').then(function (res) {
            if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
            if (!(res.data || []).length) { msg('setMsg', 'Not saved. The database refused the request.', 'err'); return; }
            logAction('post.edited', state.client.name + ' — ' + (state.batch.title || ''),
              'Cover image: ' + (to ? 'paired with ' + coverWord({ cover_for: to }, extra.videos).replace(/^Cover for /, '') : 'unpaired'));
            msg('setMsg', 'Saved.', 'ok');
            loadPosts();
          }).catch(function (e) { msg('setMsg', (e && e.message) || 'Not saved.', 'err'); });
        });
      });

      /* Accepting the client's copy is an edit after their decision, so the
         database makes it the next round and keeps this one. */
      var accept = row.querySelector('[data-a="accept"]');
      if (accept) accept.addEventListener('click', function () {
        var patch = {};
        if (review.suggested_caption != null) patch.caption = review.suggested_caption;
        if (review.suggested_caption_zh != null) patch.caption_zh = review.suggested_caption_zh;
        accept.disabled = true;
        db.from('posts').update(patch).eq('id', p.id).select('id').then(function (res) {
          accept.disabled = false;
          if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
          if (!(res.data || []).length) { msg('setMsg', 'Not saved. The database refused the request.', 'err'); return; }
          logAction('post.edited', state.client.name + ' — ' + (state.batch.title || ''),
            MK.label(p) + ': caption accepted from ' + (review.reviewer || 'the client'));
          msg('setMsg', 'Caption accepted.', 'ok');
          loadPosts();
        }).catch(function (e) { accept.disabled = false; msg('setMsg', (e && e.message) || 'Not saved.', 'err'); });
      });

      /* Confirm internally asks first, because the client's page will name
         who; Revert confirmation is the way back and never asks. */
      var conf = row.querySelector('[data-a="confirm"]');
      if (conf) conf.addEventListener('click', function () {
        shutPostMenus();
        window.ADspaceConfirm.ask({
          title: 'Confirm internally',
          body: MK.label(p) + ' is approved on the client\u2019s behalf. Their review page reads Confirmed by ' +
            ((state.client && state.client.name) || 'the client') + '.',
          go: 'Confirm'
        }, function () {
          db.rpc('review_confirm', { p_post: p.id }).then(function (res) {
            var d = (res && res.data) || {};
            if (res.error || d.error) { msg('setMsg', confirmSaid(res.error ? res.error.message : d.error), 'err'); return; }
            msg('setMsg', 'Confirmed internally.', 'ok');
            loadPosts();
          }).catch(function (e) { msg('setMsg', confirmSaid((e && e.message) || String(e)), 'err'); });
        });
      });
      var unconf = row.querySelector('[data-a="unconfirm"]');
      if (unconf) unconf.addEventListener('click', function () {
        shutPostMenus();
        db.rpc('review_revert_confirm', { p_post: p.id }).then(function (res) {
          var d = (res && res.data) || {};
          if (res.error || d.error) { msg('setMsg', confirmSaid(res.error ? res.error.message : d.error), 'err'); return; }
          msg('setMsg', 'Confirmation reverted.', 'ok');
          loadPosts();
        }).catch(function (e) { msg('setMsg', confirmSaid((e && e.message) || String(e)), 'err'); });
      });

      /* The client reads this, so it is a note and not a value: it opens under
         the control that sends it rather than in a browser window over the
         post it is about. */
      var reask = row.querySelector('[data-a="reask"]');
      if (reask) reask.addEventListener('click', function () {
        shutPostMenus();
        if (reask._ask) { reask._ask.open(); return; }
        /* The note opens under the post it is about, not inside the menu. */
        reask._ask = window.ADspaceAsk.note(row.querySelector('.saved-body'), {
          label: 'Reason for re-approval', send: 'Request re-approval',
          placeholder: 'Why the client is being asked again. They read this.',
          save: function (why) {
            db.from('posts').update({
              review_reset_at: new Date().toISOString(),
              review_reset_note: why
            }).eq('id', p.id).select('id').then(function (r) {
              if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
              if (!(r.data || []).length) { msg('setMsg', 'Not saved. The database refused the request.', 'err'); return; }
              logAction('reapproval.requested',
                state.client.name + ' — ' + MK.label(p), why);
              msg('setMsg', 'Re-approval requested.', 'ok');
              loadPosts();
            });
          }
        });
        reask._ask.open();
      });
      row.querySelector('[data-a="del"]').addEventListener('click', function () {
        shutPostMenus();
        window.ADspaceConfirm.ask({
          title: 'Delete',
          body: MK.label(p) + ' leaves the client view, with its approval record. '
              + 'There is no restore.',
          go: 'Delete',
          tone: 'danger'
        }, function () {
          // Same as the set above: the answer was thrown away entirely here, so a
          // refused delete repainted the list with the post still in it.
          db.from('posts').delete().eq('id', p.id).select('id').then(function (r) {
            if (r.error) { msg('setMsg', r.error.message, 'err'); return; }
            if (!(r.data || []).length) {
              msg('setMsg', 'Not deleted. The database refused the request.', 'err');
              return;
            }
            logAction('post.deleted',
              state.client.name + ' — ' + state.batch.title, MK.label(p));
            loadPosts(); loadBatches();
          });
        });
      });
    }

    var editMedia = null;

    function paintEdit() {
      row.classList.add('is-editing');
      var current = (p.platform || 'instagram') + ':' + (p.format || 'feed');
      var opts = PLACEMENTS.map(function (o) {
        return '<option value="' + o[0] + '"' + (o[0] === current ? ' selected' : '') + '>' +
          o[1] + '</option>';
      }).join('');

      row.innerHTML =
        '<div class="saved-thumb">' +
          thumbOf(m) + '</div>' +
        '<div class="saved-body">' +
          '<div class="draft-top">' +
            '<select class="select" data-f="placement" aria-label="Placement">' + opts + '</select>' +
            '<span class="filetag">' + esc(fileLabel(m)) + '</span>' +
          '</div>' +
          (current.indexOf('xhs') === 0
            ? '<input class="input" data-f="title" placeholder="Note title 标题" value="' +
              esc(p.title || '') + '">' : '') +
          '<textarea class="textarea" data-f="caption" placeholder="Caption" aria-label="Caption">' +
            esc(p.caption || '') + '</textarea>' +
          /* One caption a post (2026-10-10); a Chinese caption kept from
             before stays editable where one is held. */
          (String(p.caption_zh || '').trim()
            ? '<textarea class="textarea" data-f="caption_zh" placeholder="中文文案" aria-label="中文 caption">' +
              esc(p.caption_zh || '') + '</textarea>' : '') +
          capButton() +
          /* The revised file goes in here; it stays on this device until
             Save, like every other file picked in this section. */
          '<label class="saved-file"><span>Replace file</span>' +
            '<input class="input" type="file" data-f="file" multiple accept="image/*,video/*"></label>' +
          (decided ? '<span class="saved-asked">Saves as revision ' + (round + 1) + '.</span>' : '') +
          '<div class="changebox-actions">' +
            '<button class="btn btn-primary btn-sm" data-a="save" type="button">Save</button>' +
            '<button class="btn btn-sm" data-a="cancel" type="button">Cancel</button>' +
          '</div>' +
        '</div>';

      var mediaCopy = editMedia || JSON.parse(JSON.stringify(p.media || []));
      editMedia = mediaCopy;
      if (mediaCopy.length > 1) {
        var sbody = row.querySelector('.saved-body');
        var sstrip = slidesNode(mediaCopy, function () { paintEdit(); });
        sbody.insertBefore(sstrip, sbody.children[1] || null);
      }

      row.querySelector('[data-a="cancel"]').addEventListener('click', function () {
        editMedia = null;
        paintRead();
      });
      var capw = row.querySelector('[data-f="capwrite"]');
      var aiCap = false;
      if (capw) capw.addEventListener('click', function () {
        var capEl = row.querySelector('[data-f="caption"]');
        var titleNow = row.querySelector('[data-f="title"]');
        writeCaption({ btn: capw, placement: row.querySelector('[data-f="placement"]').value,
          title: titleNow ? titleNow.value : (p.title || ''), notesKey: p.id,
          now: { caption: capEl.value },
          put: function (w) {
            capEl.value = w.caption || '';
            aiCap = !!w.ai;
            capEl.dispatchEvent(new Event('input', { bubbles: true }));
            return capw.closest('.capwrite');
          } });
      });
      row.querySelector('[data-a="save"]').addEventListener('click', function () {
        /* A caption written with AI is declared read first (2026-10-10). */
        if (aiCap && String(row.querySelector('[data-f="caption"]').value || '').trim() && window.ADspaceConfirm.ai) {
          window.ADspaceConfirm.ai.declare('caption', 'Confirm and save', function () { savePost(true); });
          return;
        }
        savePost(false);
      });
      function savePost(declared) {
        var parts = row.querySelector('[data-f="placement"]').value.split(':');
        var titleEl = row.querySelector('[data-f="title"]');
        var zhField = row.querySelector('[data-f="caption_zh"]');
        var patch = {
          platform: parts[0],
          format: parts[1],
          title: titleEl ? (titleEl.value.trim() || null) : p.title,
          caption: row.querySelector('[data-f="caption"]').value || null,
          media: mediaCopy
        };
        if (zhField) patch.caption_zh = zhField.value || null;
        var picked = Array.prototype.slice.call(row.querySelector('[data-f="file"]').files || []);
        var saveBtn = row.querySelector('[data-a="save"]');
        saveBtn.disabled = true;
        saveBtn.textContent = picked.length ? 'Uploading…' : 'Saving…';
        /* A replaced file is sent at Save, then the row points at storage. */
        var upload = !picked.length ? Promise.resolve(null) : Promise.all(picked.map(function (f) {
          return probe(f).then(function (info) {
            return storeFile(f).then(function (url) {
              return storePoster(info.poster).then(function (poster) {
                return { url: url, type: info.isVideo ? 'video' : 'image', width: info.width || null,
                         height: info.height || null, mime: info.mime || f.type || null, poster: poster };
              });
            });
          });
        }));
        var moved = [];
        upload.then(function (fresh) {
          if (fresh) patch.media = fresh;
          /* What this save changes, read before it is sent. */
          moved = Object.keys(patch).filter(function (k) {
            return JSON.stringify(patch[k] == null ? null : patch[k]) !== JSON.stringify(p[k] == null ? null : p[k]);
          });
          return db.from('posts').update(patch).eq('id', p.id).select('id');
        }).then(function (res) {
          saveBtn.disabled = false;
          saveBtn.textContent = 'Save';
          if (res.error) { msg('setMsg', res.error.message, 'err'); return; }
          if (!(res.data || []).length) { msg('setMsg', 'Not saved. The database refused the request.', 'err'); return; }
          /* Which fields changed, so the row says what was edited. */
          logAction('post.edited', state.client.name + ' — ' + (state.batch.title || ''),
            MK.label(p) + ': ' + (moved.length ? moved.map(function (k) { return k === 'media' ? 'file' : k; }).join(', ') : 'no change') +
            (decided && moved.some(function (k) { return ['media', 'caption', 'caption_zh', 'title'].indexOf(k) > -1; })
              ? ' · revision ' + (round + 1) : '') +
            (declared ? ' · caption written with AI, read and confirmed' : ''));
          editMedia = null;
          msg('setMsg', 'Post updated.', 'ok');
          loadPosts();
        }).catch(function (e) {
          saveBtn.disabled = false;
          saveBtn.textContent = 'Save';
          msg('setMsg', 'Not saved. ' + ((e && e.message) || 'The upload failed.'), 'err');
        });
      }
    }

    paintRead();
    return row;
  }

  /* ---- Short Links -------------------------------------------------------
     This list is live: hi.adspace.me is a Cloudflare Worker (workers/links/)
     that reads it one slug at a time through link_resolve, so a row saved here
     redirects as soon as it is saved and a row paused here stops redirecting.
     The page used to carry a "Not live yet." line under the table; the Worker
     is deployed, so that line would now be a standing fact that is false.

     The host is one value in js/config.js, read here and written into the
     field's prefix, because it was typed into this file and into the console's
     markup and the two could disagree. `go.adspace.me` is deliberately not
     retired and is not served by that Worker: a QR code encodes the whole
     address, so the ones already printed on slides keep working for as long as
     that host redirects. This value decides what the next link is built with. */
  var LINK_HOST = (window.ADSPACE_CONFIG && window.ADSPACE_CONFIG.linkHost) || 'go.adspace.me';
  if ($('slugPrefix')) $('slugPrefix').textContent = LINK_HOST + '/';
  /* The host a link redirects from is a standing fact about the route, so it
     is the quiet line under the register: the team asked where these links
     live, and the field's prefix is only on screen while one is being added.
     go.adspace.me is named because the QR codes printed before this portal
     encode it whole and keep working. */
  /* Both hosts open, because the fastest way to know a redirector is alive is
     to follow it, and the bare host answers rather than refusing: the Worker
     sends it to the website, since somebody who types it has half a URL. Drawn
     the way the Register's routenote draws /verify: the outlined chip inline
     in its sentence, in a new tab (no underlined words, 2026-09-28). */
  if ($('linkNote')) $('linkNote').innerHTML = 'Short links redirect from ' +
    hostLink(LINK_HOST) + '. Codes printed with ' + hostLink('go.adspace.me') + ' keep working.';
  function hostLink(h) {
    return '<a class="plink" href="https://' + esc(h) + '" target="_blank" rel="noopener">' + esc(h) + '</a>';
  }
  var links = [];
  /* Every colleague's namecard slug answers on the links host too, so the
     list shows them beside the links, taken (the user, 2026-10-07: which
     slugs are in use). Null where the read failed. */
  var cards = [];
  var editingSlug = null;

  // What a slug may be: the part after the slash, and safe in a URL as typed.
  function slugOk(s) { return /^[a-z0-9][a-z0-9._-]{0,79}$/.test(s); }

  // People paste the whole short link as often as they type the slug alone.
  function cleanSlug(s) {
    return String(s == null ? '' : s).trim()
      .replace(/^https?:\/\//i, '').replace(/^[^/]*\//, '')
      .replace(/^\/+|\/+$/g, '').toLowerCase();
  }
  /* Returns '' for anything that is not plausibly a destination. Without the
     hostname check, a stray line like "BROKEN LINE ONLY" in a pasted export
     parses as the slug "broken" pointing at "https://LINE", and a bad row
     imports silently instead of being reported. */
  function cleanTarget(u) {
    var v = String(u == null ? '' : u).trim();
    if (!v) return '';
    if (/^https?:\/\//i.test(v)) return v;
    return /^[a-z0-9-]+(\.[a-z0-9-]+)+([:/?#]|$)/i.test(v) ? 'https://' + v : '';
  }
  function shortUrl(slug) { return 'https://' + LINK_HOST + '/' + slug; }

  function loadLinks() {
    var box = $('linkList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    var left = 2, failed = null;
    var settle = function () {
      if (--left) return;
      if (failed) {
        links = [];
        box.innerHTML = '<div class="softpanel"><div class="errline">' +
          '<b>Could not load the links.</b><span>' + esc(failed) + '</span>' +
          '<button class="btn btn-sm" data-a="retry" type="button">Try again</button>' +
          '</div></div>';
        box.querySelector('[data-a="retry"]').addEventListener('click', loadLinks);
        $('linkCount').textContent = '';
        return;
      }
      paintLinks();
    };
    db.from('links').select('*').order('slug').then(function (r) {
      if (r.error) failed = r.error.message; else links = r.data || [];
      settle();
    }).catch(function (e) { failed = String((e && e.message) || e); settle(); });
    db.from('team_members').select('id, name, card_slug, card_key, card_on, active').order('card_slug')
      .then(function (r) {
        cards = r.error ? null : (r.data || []).filter(function (t) { return t.card_slug; });
        settle();
      }).catch(function () { cards = null; settle(); });
  }

  /* A slug is looked at far more often than it is changed, so the list is a
     table with columns rather than fifty bordered cards each holding the same
     four icons. Copy is the everyday action and stays on the row; the rest
     move into the ⋯, where this portal already puts a rare or destructive
     one. */
  function linkShown() {
    var q = $('linkSearch').value.trim().toLowerCase();
    return links.filter(function (l) {
      if (!q) return true;
      return (l.slug + ' ' + (l.target_url || '') + ' ' + (l.title || ''))
        .toLowerCase().indexOf(q) > -1;
    });
  }
  function cardShown() {
    var q = $('linkSearch').value.trim().toLowerCase();
    return (cards || []).filter(function (t) {
      return !q || (t.card_slug + ' ' + (t.name || '')).toLowerCase().indexOf(q) > -1;
    });
  }

  function paintLinks() {
    var box = $('linkList');
    var shown = linkShown();
    var cshown = cardShown();
    /* A namecard's slug is a short link on the same host, so it counts. */
    var total = links.length + (cards || []).length;
    var count = shown.length + cshown.length;
    var filtered = count !== total;

    $('linkCount').textContent = !total ? '' :
      (filtered ? count + ' of ' + total
                : total + (total === 1 ? ' link' : ' links'));

    box.innerHTML = '';
    /* A failed read of the cards is said, never drawn as none. */
    var cardsFailed = function () {
      if (cards !== null) return;
      var fail = document.createElement('div');
      fail.className = 'softpanel';
      fail.innerHTML = '<div class="errline"><b>Could not load the namecards.</b>' +
        '<button class="btn btn-sm" data-a="retry" type="button">Try again</button></div>';
      fail.querySelector('[data-a="retry"]').addEventListener('click', loadLinks);
      box.appendChild(fail);
    };
    if (!total) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline">' +
        '<b>No short links.</b>' +
        '<button class="btn btn-sm" data-a="first" type="button">Add the first link</button>' +
        '</div></div>';
      box.querySelector('[data-a="first"]').addEventListener('click', function () { openLinkForm(null, this); });
      cardsFailed();
      return;
    }
    if (!count) {
      box.innerHTML = '<div class="softpanel"><div class="emptyline">' +
        '<b>No matches.</b><button class="btn btn-sm" data-a="clear" type="button">Clear the filters</button>' +
        '</div></div>';
      box.querySelector('[data-a="clear"]').addEventListener('click', function () {
        $('linkSearch').value = '';
        paintLinks();
      });
      cardsFailed();
      return;
    }

    /* Live links and paused ones, a card each, the shape every directory in
       this console takes; Paused stays shut by default and a filter opens
       both. No Status column: Live is true of nearly every row, so the
       heading stood over a cell that was empty almost always and read as
       something broken. The exception is named beside the slug, the way the
       rate card names an inactive service. */
    var GRP = window.ADspaceGroup;
    var liveRows = shown.filter(function (l) { return l.active !== false; });
    var pausedRows = shown.filter(function (l) { return l.active === false; });
    /* The colleagues' namecards sit between, open: their slugs are taken
       while the card answers, and while it is off or its colleague stood
       down (the trigger still refuses them to a new link). */
    [['live', 'Live', liveRows, false, 'Label', 'links', linkRow],
     ['cards', 'Namecards', cshown, false, 'Colleague', 'namecards', cardRow],
     ['paused', 'Paused', pausedRows, true, 'Label', 'links', linkRow]].forEach(function (g) {
      if (!g[2].length) return;
      box.appendChild(GRP.section({
        route: 'links', key: g[0], name: g[1], count: g[2].length,
        shut: !filtered && GRP.shut('links', g[0], g[3], g[2].length === count),
        table: function () {
          var table = GRP.table('link-row', ['Short link', 'Destination', g[4], '']);
          GRP.more(table, g[2], 30, g[5], g[6]);
          return table;
        }
      }));
    });
    cardsFailed();
  }

  /* A colleague's namecard: its slug, the card's own address it answers
     with, and whose it is. Edited in Team or My namecard, never here, so
     the row copies and opens and holds no ⋯. */
  function cardRow(t) {
    var off = !t.active || t.card_on === false;
    var url = window.ADspaceCard ? window.ADspaceCard.link(t.card_key)
      : location.origin + '/card/?k=' + encodeURIComponent(t.card_key || '');
    var row = document.createElement('div');
    row.className = 'link-row is-card' + (off ? ' is-off' : '');
    row.innerHTML =
      '<span class="link-slug">/' + esc(t.card_slug) +
        (!t.active ? ' <span class="tone is-off">Inactive</span>' : off ? ' <span class="tone is-off">Card off</span>' : '') + '</span>' +
      '<span class="link-target">' + esc(url) + '</span>' +
      '<span class="link-label">' + esc(t.name || '') + '</span>' +
      '<span class="link-act">' +
        iconBtn('copy', 'copy', 'Copy short link') +
        (off ? '' : '<a class="iconbtn" data-a="open" href="' + esc(url) + '" target="_blank" rel="noopener" title="Open namecard" aria-label="Open namecard">' +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICON.out + '</svg></a>') +
      '</span>';
    row.querySelector('[data-a="copy"]').addEventListener('click', function (e) {
      window.ADspaceCopy.to(e.currentTarget, shortUrl(t.card_slug));
    });
    return row;
  }

  function linkRow(l) {
      var off = l.active === false;
      var row = document.createElement('div');
      row.className = 'link-row' + (off ? ' is-off' : '');
      row.innerHTML =
        // Live is true of nearly every row, so only the exception is named,
        // and it is named beside the thing it is true of.
        '<span class="link-slug">/' + esc(l.slug) +
          (off ? ' <span class="tone is-off">Paused</span>' : '') + '</span>' +
        '<span class="link-target">' + esc(l.target_url || '') + '</span>' +
        '<span class="link-label">' + esc(l.title || '') + '</span>' +
        '<span class="link-act">' +
          iconBtn('copy', 'copy', 'Copy short link') +
          iconBtn('qr',   'qr',   'QR codes') +
          /* Every item here changes the link, so the ⋯ is drawn at Work, as
             each item is (a View group was offered Edit, audit 2026-10-03). */
          '<button class="kmenu-btn" data-a="menu" data-need="links:work" type="button" aria-label="More actions" aria-expanded="false">' + DOTS + '</button>' +
          '<div class="kmenu" data-menu hidden>' +
            '<button class="kmenu-item" data-a="edit" data-need="links:work" type="button"><b>Edit</b></button>' +
            /* Live is a lifecycle flag flipped once in the life of a row, so
               it is a chip on the row and an item here, never a field in the
               form and never a select on every line — the shape a rate card
               line and a colleague already take. It was neither for months:
               the register banded Live and Paused and the delete sheet said
               "pause it instead", with nothing anywhere that could. */
            '<button class="kmenu-item" data-a="live" data-need="links:work" type="button"><b>' +
              (off ? 'Resume' : 'Pause') + '</b></button>' +
            '<button class="kmenu-item is-danger" data-a="del" data-need="links:manage" type="button"><b>Delete</b></button>' +
          '</div>' +
        '</span>';

      row.querySelector('[data-a="copy"]').addEventListener('click', function (e) {
        window.ADspaceCopy.to(e.currentTarget, shortUrl(l.slug));
      });
      row.querySelector('[data-a="qr"]').addEventListener('click', function () { openQr(l); });
      row.querySelector('[data-a="edit"]').addEventListener('click', function () {
        shutLinkMenus(); editLink(l);
      });
      row.querySelector('[data-a="live"]').addEventListener('click', function () {
        shutLinkMenus(); setLinkLive(l, off);
      });
      row.querySelector('[data-a="del"]').addEventListener('click', function () {
        shutLinkMenus(); removeLink(l);
      });
      wireLinkMenu(row);
      return row;
  }

  function shutLinkMenus() {
    Array.prototype.forEach.call(document.querySelectorAll('#linkList .kmenu'), function (m) { m.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('#linkList .kmenu-btn'), function (b) {
      b.setAttribute('aria-expanded', 'false');
    });
  }
  function wireLinkMenu(row) {
    var btn = row.querySelector('[data-a="menu"]');
    var menu = row.querySelector('[data-menu]');
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      shutLinkMenus();
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', String(open));
      if (open) window.ADspaceMenu.place(btn, menu);
    });
  }
  document.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('#linkList .kmenu, #linkList .kmenu-btn')) shutLinkMenus();
  });
  window.ADspaceMenu.onScroll(shutLinkMenus);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') shutLinkMenus(); });

  function openLinkForm(link, opener) {
    editingSlug = link ? link.slug : null;
    $('linkFormTitle').textContent = link ? 'Edit short link' : 'New short link';
    $('saveLink').textContent = link ? 'Save' : 'Create';
    $('newSlug').value = link ? link.slug : '';
    $('newTarget').value = link ? (link.target_url || '') : '';
    $('newLinkLabel').value = link ? (link.title || '') : '';
    $('importBox').hidden = true;
    msg('linkMsg', '');
    /* The portal's one form sheet, so it opens over the register rather than
       unfolding above it, and nothing inside takes focus: a field taking
       focus on a phone raises the keyboard and zooms the page past the rest
       of the form. */
    window.ADspaceSheet.show($('addLinkBox'), { opener: opener || null });
  }
  function shutLinkForm() {
    if (window.ADspaceSheet.isOpen($('addLinkBox'))) window.ADspaceSheet.close();
    else $('addLinkBox').hidden = true;
    editingSlug = null; msg('linkMsg', '');
  }

  function editLink(l) { openLinkForm(l); }

  function removeLink(l) {
    window.ADspaceConfirm.ask({
      title: 'Delete',
      body: 'Anywhere /' + l.slug + ' is already printed, posted or sent stops working. '
          + 'There is no restore. To turn it off and keep it, pause it instead.',
      go: 'Delete',
      tone: 'danger',
      field: { label: 'Type the short link to confirm', placeholder: l.slug, match: l.slug, need: 'Type the short link to confirm.', mismatch: 'The short link does not match.' }
    }, function () {
      db.from('links').delete().eq('slug', l.slug).select('slug').then(function (r) {
        if (r.error) { msg('linkListMsg', r.error.message, 'err'); return; }
        if (!(r.data || []).length) { msg('linkListMsg', 'Not deleted. The database refused the request.', 'err'); return; }
        logAction('shortlink.deleted', '/' + l.slug, l.target_url || '');
        loadLinks();
      });
    });
  }

  /* Pausing stops a link somebody has already printed, so it says what it
     costs before it goes; resuming is the way back and the way back never
     asks. The write takes `.select('id')`, because a policy can refuse an
     update and PostgREST answers a refused one with no error at all — a
     repaint over a row that has not changed is indistinguishable from a page
     that did not repaint. */
  function setLinkLive(l, live) {
    var run = function () {
      db.from('links').update({ active: !!live }).eq('slug', l.slug).select('slug')
        .then(function (r) {
          if (r.error) { msg('linkListMsg', r.error.message, 'err'); return; }
          if (!r.data || !r.data.length) {
            msg('linkListMsg', 'Not saved. The database refused the request.', 'err');
            return;
          }
          /* `shortlink.updated`, not a tag of its own: pausing is a change to
             the link, the record already names that, and a new tag would have
             to be added to `ACTION_LABEL` and to `activity_section()` in SQL
             in the same breath or it lands in the record with no word and no
             section. What happened is the detail. */
          logAction('shortlink.updated', '/' + l.slug, live ? 'Resumed' : 'Paused');
          /* The row leaves the card somebody was looking at, and Paused is
             shut by default and empties itself, so a pause would otherwise
             take the row off the screen with nothing saying where it went.
             The card it moves into is opened, and the fold is remembered the
             way any other fold is: somebody who has just paused a link is
             somebody who wants that card open. */
          window.ADspaceGroup.keep('links', live ? 'live' : 'paused', false);
          loadLinks();
        });
    };
    if (live) { run(); return; }
    window.ADspaceConfirm.ask({
      title: 'Pause',
      body: '/' + l.slug + ' stops redirecting, wherever it is already printed, '
          + 'posted or sent. Resume puts it back.',
      go: 'Pause',
      tone: 'warn'
    }, run);
  }

  $('showAddLink').addEventListener('click', function () { openLinkForm(null, this); });
  $('cancelAddLink').addEventListener('click', shutLinkForm);
  /* The close mark in the sheet's head is the same way back as Cancel. */
  if ($('linkClose')) $('linkClose').addEventListener('click', shutLinkForm);
  $('linkSearch').addEventListener('input', paintLinks);

  $('saveLink').addEventListener('click', function () {
    var slug = cleanSlug($('newSlug').value);
    var target = cleanTarget($('newTarget').value);
    if (!slug)       { msg('linkMsg', 'A short link needs a slug.', 'err'); return; }
    if (!slugOk(slug)) {
      msg('linkMsg', 'Use lowercase letters, digits, dots, dashes or underscores.', 'err');
      return;
    }
    if (!target) {
      msg('linkMsg', $('newTarget').value.trim()
        ? 'That destination does not look like a web address.'
        : 'A destination is required.', 'err');
      return;
    }

    // Renaming a slug is a new row plus a delete, so catch the collision first.
    var clash = links.filter(function (l) { return l.slug === slug && l.slug !== editingSlug; });
    if (clash.length) { msg('linkMsg', '/' + slug + ' is already in use.', 'err'); return; }
    if ((cards || []).some(function (t) { return t.card_slug === slug; })) {
      msg('linkMsg', '/' + slug + ' is a colleague\'s namecard.', 'err'); return;
    }

    var body = {
      slug: slug, target_url: target,
      title: $('newLinkLabel').value.trim() || null,
      created_by: actor || null
    };
    var was = editingSlug;

    db.from('links').upsert(body, { onConflict: 'slug' }).then(function (r) {
      if (r.error) {
        msg('linkMsg', /slug-taken/.test(r.error.message) ? '/' + slug + ' is a colleague\'s namecard.' : r.error.message, 'err');
        return;
      }
      if (was && was !== slug) {
        /* The old address goes once the new one stands; a refusal leaves
           both live, so it is said rather than left (audit, 2026-10-03). */
        db.from('links').delete().eq('slug', was).select('slug').then(function (d) {
          loadLinks();
          if (d.error || !(d.data || []).length) msg('linkListMsg', '/' + was + ' is still live. The database refused to remove it.', 'err');
        }).catch(function () { loadLinks(); });
      } else {
        loadLinks();
      }
      logAction(was ? 'shortlink.updated' : 'shortlink.created', '/' + slug, target);
      shutLinkForm();
    });
  });

  /* ---- QR codes ----------------------------------------------------------
     A QR is a picture of a URL. Once printed it decodes to that URL forever,
     so there is no revoking the image. Each code therefore carries its own
     identity and the redirector is what turns a revoked one away:

         https://go.adspace.me/<slug>?q=<code>

     One slug can hold several, so a single placement can be pulled without
     taking the rest of the campaign down with it. The encoded text never
     changes for a given code, which is what makes the picture permanent. */
  var qrLink = null;
  var qrCodes = [];

  function qrUrl(slug, code) { return shortUrl(slug) + '?q=' + code; }

  function makeCode() {
    var a = new Uint8Array(5);
    crypto.getRandomValues(a);
    return Array.from(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }

  /* Draws into a fresh element every time. qrcodejs appends rather than
     replaces, so reusing a node stacks images on top of each other. */
  function drawQr(box, text, size) {
    box.innerHTML = '';
    if (!window.QRCode) {
      box.innerHTML = '<span class="muted">QR library did not load.</span>';
      return;
    }
    new window.QRCode(box, {
      text: text, width: size, height: size,
      correctLevel: window.QRCode.CorrectLevel.H
    });
  }

  /* Print wants far more than the screen does, so the file is rendered at a
     size nobody has to look at, off screen, and thrown away after. */
  function downloadQr(slug, code, label) {
    var tmp = document.createElement('div');
    tmp.style.cssText = 'position:fixed;left:-9999px;top:0';
    document.body.appendChild(tmp);
    drawQr(tmp, qrUrl(slug, code), 1024);
    setTimeout(function () {
      var canvas = tmp.querySelector('canvas');
      var img = tmp.querySelector('img');
      var data = canvas ? canvas.toDataURL('image/png') : (img && img.src);
      if (data) {
        var a = document.createElement('a');
        a.href = data;
        a.download = 'qr-' + slug + (label ? '-' + label.toLowerCase().replace(/[^a-z0-9]+/g, '-') : '') + '.png';
        document.body.appendChild(a);
        a.click();
        a.remove();
      }
      tmp.remove();
    }, 120);
  }

  function openQr(l) {
    qrLink = l;
    $('qrHeading').textContent = 'QR codes for /' + l.slug;
    $('qrLabel').value = '';
    msg('qrMsg', '');
    $('qrSheet').hidden = false;
    loadQrs();
  }
  function shutQr() { $('qrSheet').hidden = true; qrLink = null; }
  $('qrSheetClose').addEventListener('click', shutQr);
  $('qrSheet').addEventListener('click', function (e) {
    if (e.target === $('qrSheet')) shutQr();
  });

  function loadQrs() {
    var box = $('qrList');
    box.innerHTML = '<div class="empty">Loading…</div>';
    db.from('link_qrs').select('*').eq('slug', qrLink.slug)
      .order('created_at').then(function (r) {
        if (r.error) {
          box.innerHTML = '<div class="empty">Could not load the codes. ' + esc(r.error.message) + '</div>';
          return;
        }
        qrCodes = r.data || [];
        paintQrs();
      });
  }

  /* The timestamp is the database's to set, so a row that has not been read
     back yet simply has none. Saying nothing beats saying "Invalid Date". */
  function made(value, prefix) {
    if (!value) return '';
    var d = new Date(value);
    if (isNaN(d.getTime())) return '';
    return prefix + d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace(/\bSep\b/, 'Sept');
  }

  function paintQrs() {
    var box = $('qrList');
    box.innerHTML = '';
    if (!qrCodes.length) {
      box.innerHTML = '<div class="empty">No codes.</div>';
      return;
    }
    qrCodes.forEach(function (q) {
      var card = document.createElement('div');
      card.className = 'qrrow' + (q.active ? '' : ' is-off');
      card.innerHTML =
        '<div class="qrrow-img"></div>' +
        '<div class="qrrow-body">' +
          '<b>' + esc(q.label || 'Untitled code') + '</b>' +
          (q.active ? '' : '<span class="tone is-off" style="margin-left:8px">Revoked</span>') +
          '<span class="qrrow-url">' + esc(qrUrl(q.slug, q.code)) + '</span>' +
          '<span class="muted">' +
            [made(q.created_at, 'Created '), made(q.revoked_at, 'revoked ')]
              .filter(Boolean).join(' · ') +
          '</span>' +
          '<div class="qrrow-acts">' +
            '<button class="btn btn-sm" data-q="dl" type="button">Download PNG</button>' +
            '<button class="btn btn-sm btn-quiet" data-q="copy" type="button">Copy URL</button>' +
            '<button class="btn btn-sm btn-quiet' + (q.active ? ' is-danger' : '') +
              '" data-q="toggle" type="button">' + (q.active ? 'Revoke' : 'Restore') + '</button>' +
          '</div>' +
        '</div>';
      drawQr(card.querySelector('.qrrow-img'), qrUrl(q.slug, q.code), 132);
      card.querySelector('[data-q="dl"]').addEventListener('click', function () {
        downloadQr(q.slug, q.code, q.label);
      });
      card.querySelector('[data-q="copy"]').addEventListener('click', function (e) {
        var b = e.currentTarget;
        navigator.clipboard.writeText(qrUrl(q.slug, q.code)).then(function () {
          b.textContent = 'Copied';
          setTimeout(function () { b.textContent = 'Copy URL'; }, 1500);
        });
      });
      card.querySelector('[data-q="toggle"]').addEventListener('click', function () { toggleQr(q); });
      box.appendChild(card);
    });
  }

  function toggleQr(q) {
    var next = !q.active;
    function save() {
      db.from('link_qrs').update({ active: next, revoked_at: next ? null : new Date().toISOString() })
        .eq('code', q.code).select('code').then(function (r) {
          if (r.error) { msg('qrMsg', r.error.message, 'err'); return; }
          if (!(r.data || []).length) { msg('qrMsg', 'Not saved. The database refused the request.', 'err'); return; }
          logAction(next ? 'qr.restored' : 'qr.revoked', '/' + q.slug, q.label || q.code);
          loadQrs();
        });
    }
    /* Reinstating asks nothing: it is the way back from this, and a way back
       that asks first is one more thing between somebody and the correction. */
    if (next) { save(); return; }
    window.ADspaceConfirm.ask({
      title: 'Revoke this code',
      body: 'Scans of ' + (q.label || 'this code') + ' are turned away. '
          + '/' + q.slug + ' keeps working, and the code can be reinstated here.',
      go: 'Revoke',
      tone: 'warn'
    }, save);
  }

  $('qrNew').addEventListener('click', function () {
    if (!qrLink) return;
    var row = {
      code: makeCode(), slug: qrLink.slug,
      label: ($('qrLabel').value || '').trim() || null,
      active: true,
      created_by: actor || null
    };
    db.from('link_qrs').insert(row).then(function (r) {
      if (r.error) { msg('qrMsg', r.error.message, 'err'); return; }
      logAction('qr.created', '/' + qrLink.slug, row.label || row.code);
      $('qrLabel').value = '';
      msg('qrMsg', '');
      loadQrs();
    });
  });

  $('showImport').addEventListener('click', function () {
    $('importBox').hidden = false;
    shutLinkForm();
    msg('importMsg', '');
    $('importText').focus();
  });
  $('cancelImport').addEventListener('click', function () { $('importBox').hidden = true; });

  /* A paste from Rebrandly is a slug, a destination, and sometimes a name.
     Splitting on tab, comma or a run of spaces covers every export shape
     without asking anyone to reformat fifty rows by hand. */
  function parseImport(text) {
    var rows = [], bad = [];
    String(text || '').split(/\r?\n/).forEach(function (line, i) {
      var raw = line.trim();
      if (!raw) return;
      var parts = raw.split(/\t|\s*,\s*|\s{2,}|\s+/);
      var slug = cleanSlug(parts.shift());
      var target = cleanTarget(parts.shift());
      var title = parts.join(' ').trim();
      if (!slug || !slugOk(slug) || !target) { bad.push(i + 1); return; }
      rows.push({ slug: slug, target_url: target, title: title || null, created_by: actor || null });
    });
    return { rows: rows, bad: bad };
  }

  $('runImport').addEventListener('click', function () {
    var parsed = parseImport($('importText').value);
    if (!parsed.rows.length) {
      msg('importMsg', 'Nothing to import. Each line needs a slug and a destination.', 'err');
      return;
    }
    // Last one wins, so a list with a repeated slug still imports cleanly.
    var seen = {};
    parsed.rows.forEach(function (r) { seen[r.slug] = r; });
    var rows = Object.keys(seen).map(function (k) { return seen[k]; });

    msg('importMsg', 'Importing ' + rows.length + '…');
    db.from('links').upsert(rows, { onConflict: 'slug' }).then(function (r) {
      if (r.error) { msg('importMsg', r.error.message, 'err'); return; }
      logAction('shortlink.imported', rows.length + ' links', '');
      var note = 'Imported ' + rows.length + (rows.length === 1 ? ' link.' : ' links.');
      if (parsed.bad.length) {
        note += ' Skipped line' + (parsed.bad.length === 1 ? ' ' : 's ') +
                parsed.bad.join(', ') + ' — could not read a slug and destination.';
      }
      msg('importMsg', note, parsed.bad.length ? 'warn' : 'ok');
      $('importText').value = '';
      loadLinks();
    });
  });
})();
