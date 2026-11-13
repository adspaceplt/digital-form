/* Supabase access layer. Falls back to demo data when no project is configured. */
(function () {
  const cfg = window.ADSPACE_CONFIG || {};
  const configured = Boolean(cfg.supabaseUrl && cfg.supabaseAnonKey);

  /* A read whose connection drops before the answer arrives ("Load failed"
     in Safari, "Failed to fetch" elsewhere) is tried once more before it is
     called a failure: a phone resuming the installed app or losing signal
     for a moment drew "Clients could not be loaded" over a list the server
     had already answered (2026-09-28). Only a GET is retried; a write is
     never sent twice. */
  /* ---- Loading, said on the page (the user, 2026-11-10: "it does stay
     there, gray out … we're not sure how long it take to complete, or is it
     really loading?") ----
     Every request the page sends counts here. Once one has been out for
     `showAfter`, a thin line slides under the page's top bar until the last
     answers, so a press that is working says so; the minute's own check
     (`page_pulse`) never shows it. A read (GET) that has not answered in
     `giveUpAfter` is given up, never tried again, so the page says it could
     not load with Try again rather than waiting for ever; a write is never
     cut off (it may have reached the database). */
  /* Read at each use, so a page (or a suite) may set its own. */
  const LOAD_FIRST = { showAfter: 300, slowAfter: 8000, giveUpAfter: 20000 };
  function LOADING() { return Object.assign({}, LOAD_FIRST, (window.ADSPACE_CONFIG || {}).loading || {}); }
  const QUIET = /\/rpc\/(page_pulse|guide_seen_mark)\b/;
  let busyN = 0, barTimer = null, bar = null;
  function barEl() {
    if (bar && bar.isConnected) return bar;
    bar = document.createElement('div');
    bar.className = 'loadbar';
    bar.setAttribute('role', 'progressbar');
    bar.setAttribute('aria-label', 'Loading');
    bar.innerHTML = '<span></span>';
    (document.body || document.documentElement).appendChild(bar);
    return bar;
  }
  /* Under the page's own bar, across its width (the console's head beside
     the rail, a client page's bar edge to edge); a page with none, at the
     top of the screen. */
  /* While a sheet is open (the Assistant, a form, a question), the line runs
     under that sheet's own head, across its card, never across the page
     behind it (the user, 2026-11-13). The top sheet is the one drawn last
     at the highest layer. */
  function sheetHead() {
    const open = Array.prototype.filter.call(document.querySelectorAll('.sheet:not([hidden])'), function (s) {
      return s.getClientRects().length && getComputedStyle(s).visibility !== 'hidden';
    });
    if (!open.length) return null;
    let top = open[0], z = -1;
    open.forEach(function (s) { const n = parseInt(getComputedStyle(s).zIndex, 10) || 0; if (n >= z) { z = n; top = s; } });
    const card = top.querySelector('.sheet-card') || top;
    const c = card.getBoundingClientRect();
    if (!c.width || !c.height) return null;
    const head = card.firstElementChild;
    const h = head && head.getBoundingClientRect();
    /* Under the head where the card leads with one, else along its top
       edge inside its corners. */
    const isHead = head && /head|ask-?top|sheet-top/i.test(head.className || '') && h.height && h.height < c.height / 2;
    const inset = isHead ? 0 : Math.min(18, c.width / 4);
    return { top: isHead ? h.bottom : c.top, left: c.left + inset, width: c.width - inset * 2, bottom: 1 };
  }
  function placeBar(el) {
    let r = sheetHead();
    if (r) {
      el.style.top = Math.round(r.top) + 'px'; el.style.left = Math.round(r.left) + 'px'; el.style.width = Math.round(r.width) + 'px';
      return;
    }
    const heads = document.querySelectorAll('.console-head, .topbar');
    for (let i = 0; i < heads.length; i++) {
      const b = heads[i].getBoundingClientRect();
      if (b.width && b.height && b.bottom > 0) { r = b; break; }
    }
    el.style.top = (r ? Math.round(r.bottom) : 0) + 'px';
    el.style.left = (r ? Math.round(r.left) : 0) + 'px';
    el.style.width = (r ? Math.round(r.width) : window.innerWidth) + 'px';
  }
  function loadBegin() {
    busyN++;
    if (bar && bar.classList.contains('is-on')) placeBar(bar);
    if (busyN === 1 && !barTimer) {
      barTimer = setTimeout(function () {
        barTimer = null;
        if (busyN <= 0 || !document.body) return;
        const el = barEl();
        placeBar(el);
        el.classList.add('is-on');
      }, LOADING().showAfter);
    }
  }
  function loadEnd() {
    busyN = Math.max(0, busyN - 1);
    if (busyN) return;
    if (barTimer) { clearTimeout(barTimer); barTimer = null; }
    if (bar) bar.classList.remove('is-on');
  }
  function urlOf(input) { return String((input && input.url) || input || ''); }

  function steadyFetch(input, init) {
    const method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
    const quiet = QUIET.test(urlOf(input));
    let opts = init;
    let timer = null, gaveUp = false;
    const giveUp = LOADING().giveUpAfter;
    if (method === 'GET' && giveUp > 0 && typeof AbortController === 'function') {
      const ctl = new AbortController();
      const theirs = init && init.signal;
      if (theirs) {
        if (theirs.aborted) ctl.abort();
        else theirs.addEventListener('abort', function () { ctl.abort(); });
      }
      timer = setTimeout(function () { gaveUp = true; ctl.abort(); }, giveUp);
      opts = Object.assign({}, init || {}, { signal: ctl.signal });
    }
    const go = () => fetch(input, opts);
    const run = method !== 'GET' ? go() : go().catch((e) => {
      if (gaveUp) {
        const t = new Error('The connection was lost or is too slow.');
        t.name = 'TimeoutError';
        throw t;
      }
      if (opts && opts.signal && opts.signal.aborted) throw e;
      return new Promise((res) => setTimeout(res, 600)).then(go);
    }).catch((e) => {
      if (gaveUp && e && e.name !== 'TimeoutError') {
        const t = new Error('The connection was lost or is too slow.');
        t.name = 'TimeoutError';
        throw t;
      }
      throw e;
    });
    if (!quiet) loadBegin();
    const done = () => { if (timer) clearTimeout(timer); if (!quiet) loadEnd(); };
    return run.then((r) => { done(); return r; }, (e) => { done(); throw e; });
  }

  let client = null;
  if (configured && window.supabase) {
    client = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { global: { fetch: steadyFetch } });
  }

  /* Demo content is for a copy with no database configured, never a
     configured page whose database library failed to load: that page says
     it could not load, and records nothing (audit F5, 2026-10-10). */
  async function getReviewFeed(token, passcode) {
    if (!client && configured) throw new Error('unavailable');
    if (!client) {
      const res = await fetch('/demo/sample.json', { cache: 'no-store' });
      if (!res.ok) throw new Error('Demo content unavailable.');
      return res.json();
    }
    const { data, error } = await client.rpc('get_review_feed', {
      p_token: token,
      p_passcode: passcode || null
    });
    if (error) throw error;
    return data;
  }

  async function submitReview(payload) {
    if (!client && configured) throw new Error('unavailable');
    if (!client) {
      return { ok: true, demo: true };
    }
    const args = {
      p_token: payload.token,
      p_post_id: payload.postId,
      p_decision: payload.decision,
      p_note: payload.note || null,
      p_reviewer: payload.reviewer || null,
      p_passcode: payload.passcode || null
    };
    /* A copy edit rides the request only where the client made one, so an
       ordinary decision is the call it always was. */
    if (payload.caption != null) args.p_caption = payload.caption;
    if (payload.captionZh != null) args.p_caption_zh = payload.captionZh;
    /* The decision is on the version on show (audit F2, 2026-10-10): a post
       changed after the page opened is refused `changed`, and what was
       decided on is kept with the decision. Any refusal is the refusal: it
       is never sent again without the version (2026-10-22, BE-13). */
    if (payload.version != null) {
      const seen = await client.rpc('submit_review_seen', Object.assign({ p_version: payload.version }, args));
      if (seen.error) throw seen.error;
      return seen.data;
    }
    const { data, error } = await client.rpc('submit_review', args);
    if (error) throw error;
    return data;
  }

  /* An edge function call with the reason for a failure read out. On a
     non-2xx reply supabase-js hands back only "Edge Function returned a
     non-2xx status code"; the function's own answer ({ error, detail }) sits
     in the response, so it is read here and put into words once. */
  const FN_WORD = {
    not_signed_in: 'Sign in again.',
    not_admin: 'You do not have permission to do this. Please ask an admin.',
    not_team: 'Not a team login.',
    bad_email: 'The email is not valid.',
    not_portal_contact: 'The deployed function predates portal access. Redeploy invite-member.',
    not_team_member: 'Only a colleague on the team list can be invited.',
    too_many: 'Twenty invitations a day is the limit. Try again tomorrow.'
  };
  function invokeFn(name, body) {
    if (!client) return Promise.resolve({ data: {}, error: { message: 'Not configured' }, why: 'Not configured.' });
    const words = (b, err) => {
      if (b && (b.detail || b.error)) return b.detail || FN_WORD[b.error] || b.error;
      const m = String((err && err.message) || err || '');
      if (/not found|404|Failed to send|Failed to fetch/i.test(m)) return name + ' is not deployed.';
      return m || 'Unknown error.';
    };
    return client.functions.invoke(name, { body }).then(r => {
      const d = r.data || {};
      if (!r.error && !d.error) return { data: d, error: null, why: '' };
      const out = { data: d, error: r.error || { message: d.error }, why: words(d, r.error) };
      const ctx = r.error && r.error.context;
      if (ctx && typeof ctx.json === 'function') {
        return ctx.json().then(b => { out.data = b || {}; out.why = words(b, r.error); return out; }, () => out);
      }
      return out;
    }, e => ({ data: {}, error: e, why: words(null, e) }));
  }

  /* The columns of `clients` the table answers to the team. The billing
     columns (registered name, registration and tax numbers, billing
     contact, finance email, billing address) are withheld by the database,
     so `select('*')` on clients is refused; they are read through
     `client_billing()`, which answers only the people Clients: Billing
     admits (2026-09-28). */
  const CLIENT_COLS = 'id, name, logo_url, access_token, passcode, active, created_at, drive_folder, ' +
    'handle_ig, handle_fb, handle_tiktok, handle_xhs, stage, industry, owner, market, sst_applies, ' +
    'website, source, brand_notes, updated_at, phone, social_ig, social_fb, social_tiktok, social_xhs, ' +
    'review_hidden, deal_value, deal_note, commence, slug, stage_since, stage_log, client_code, bill_sgd, sales_by';
  const BILL_COLS = ['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no', 'bill_contact_id',
    'bill_contact', 'bill_contact_email', 'bill_contact_phone', 'finance_email', 'billing_address'];
  /* Billing by client id: { id: row }. A row carries `missing`, the
     required fields left blank, even where the values are withheld, so the
     Active gate still names them. A refusal answers {}, never a second
     read of the withheld columns (2026-10-22, BE-13). Never throws. */
  function clientBilling(ids) {
    if (!client) return Promise.resolve({});
    const keyed = (rows) => {
      const out = {};
      (rows || []).forEach((r) => { out[r.id] = r; });
      return out;
    };
    return client.rpc('client_billing', { p_ids: ids || null })
      .then((r) => (r.error ? {} : keyed(r.data))).catch(() => ({}));
  }
  /* Lays billing onto client rows in place. Only the keys the answer holds
     are written, so a person Billing refuses keeps none. */
  function withBilling(rows) {
    const list = [].concat(rows || []).filter(Boolean);
    if (!list.length) return Promise.resolve(rows);
    const ids = list.length === 1 ? [list[0].id] : null;
    return clientBilling(ids).then((by) => {
      list.forEach((c) => {
        const b = by[c.id];
        if (!b) return;
        Object.keys(b).forEach((k) => { if (k !== 'id') c[k] = b[k]; });
      });
      return rows;
    });
  }

  /* A link from before the short keys (2026-10-01): the long key it carries
     is answered with the key that replaced it, or null. */
  async function movedKey(kind, token) {
    if (!client || !token) return null;
    try {
      const { data, error } = await client.rpc('link_moved', { p_kind: kind, p_token: token });
      return error ? null : (data || null);
    } catch (e) { return null; }
  }

  /* A review or selection link opened by a signed-in contact of its client
     (2026-11-08): the contact's name and the link's access code, so the
     page opens with no code typed and decides under that name. Null with
     no sign-in, for anyone else, or where the function is not there. */
  async function portalPass(kind, token) {
    if (!client || !token) return null;
    try {
      const { data: s } = await client.auth.getSession();
      if (!s || !s.session) return null;
      const { data, error } = await client.rpc('portal_link_pass', { p_kind: kind, p_token: token });
      return error || !data || !data.name ? null : data;
    } catch (e) { return null; }
  }

  /* The key in a client's review link and a campaign's selection link: eight
     characters from the creator code's alphabet in lower case (no 0, 1, i,
     l, o), about 850 billion links, short enough to read aloud (the user,
     2026-10-01). Rejection sampling keeps every character equally likely. */
  const TOKEN_ABC = '23456789abcdefghjkmnpqrstuvwxyz';
  function accessToken() {
    let out = '';
    while (out.length < 8) {
      const a = new Uint8Array(16);
      window.crypto.getRandomValues(a);
      for (let i = 0; i < a.length && out.length < 8; i++) {
        if (a[i] < 248) out += TOKEN_ABC[a[i] % 31];
      }
    }
    return out;
  }

  /* The one reading of a number for a wa.me link (2026-10-09), as the team
     types numbers and as `wa_number` reads them in SQL: a leading 0 is
     Malaysia (6 in front, keeping the 0 as 60), eight digits Singapore (65),
     nine or ten starting 1 a Malaysian mobile without its 0 (60); anything
     else already carries its country code. Digits alone; '' for nothing. */
  function waNumber(raw) {
    const d = String(raw || '').replace(/\D/g, '');
    if (!d) return '';
    if (d.charAt(0) === '0') return '6' + d;
    if (d.length === 8) return '65' + d;
    if ((d.length === 9 || d.length === 10) && d.charAt(0) === '1') return '60' + d;
    return d;
  }

  /* What an edge function refused, by its own code (2026-10-17): supabase-js
     puts a non-2xx answer in `r.error`, its body unread on
     `r.error.context` (the Response), so a page that looked at `r.data`
     alone showed "Edge Function returned a non-2xx status code". A 200
     answer carries it in `r.data`. '' where none is named. */
  function fnRefusal(r) {
    if (r && r.data && r.data.error) return Promise.resolve(String(r.data.error));
    const ctx = r && r.error && r.error.context;
    if (!ctx || typeof ctx.json !== 'function') return Promise.resolve('');
    return Promise.resolve()
      .then(() => (typeof ctx.clone === 'function' ? ctx.clone() : ctx).json())
      .then((b) => (b && b.error ? String(b.error) : ''))
      .catch(() => '');
  }

  /* The files sign-upload signs (its EXT_TYPE), as a picker's accept: each
     extension and its type, so a phone's library offers them and nothing it
     would refuse (2026-10-17). */
  const UPLOAD_TYPES = {
    video: { mp4: 'video/mp4', m4v: 'video/x-m4v', mov: 'video/quicktime', webm: 'video/webm',
             mkv: 'video/x-matroska', mpg: 'video/mpeg', mpeg: 'video/mpeg' },
    image: { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif',
             heic: 'image/heic', heif: 'image/heif', avif: 'image/avif' },
    pdf: { pdf: 'application/pdf' },
    zip: { zip: 'application/zip' }
  };
  function uploadAccept(kinds) {
    const out = [];
    kinds.forEach((k) => Object.keys(UPLOAD_TYPES[k] || {}).forEach((e) => {
      [ '.' + e, UPLOAD_TYPES[k][e] ].forEach((x) => { if (out.indexOf(x) < 0) out.push(x); });
    }));
    return out.join(',');
  }

  /* Every row of a read, a thousand at a time: PostgREST answers a thousand
     and no more, and past that rows left the list without a word. `make`
     builds the same query each time (a query is spent once sent), ordered
     to the row so no page repeats or skips one; `cap` stops a runaway read. */
  function readPages(make, cap) {
    let out = [];
    const last = (cap || 50000) - 1000;
    function page(from) {
      return make().range(from, from + 999).then((r) => {
        if (r.error) return r;
        const got = r.data || [];
        out = out.concat(got);
        if (got.length < 1000) return { data: out };
        /* Past the cap the list is cut, and said so: never rows dropped
           without a word (2026-10-22, BE-14). */
        if (from >= last) return { data: out, error: { message: 'too-many', code: 'too-many' } };
        return page(from + 1000);
      });
    }
    return page(0);
  }

  window.ADspaceAPI = {
    readPages,
    steadyFetch,
    loading: { begin: loadBegin, end: loadEnd, get slowAfter() { return LOADING().slowAfter; } },
    accessToken,
    fnRefusal,
    uploadAccept,
    waNumber,
    movedKey,
    portalPass,
    configured,
    client,
    CLIENT_COLS,
    BILL_COLS,
    clientBilling,
    withBilling,
    getReviewFeed,
    submitReview,
    invokeFn
  };
})();
