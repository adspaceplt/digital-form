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
  function steadyFetch(input, init) {
    const method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
    const go = () => fetch(input, init);
    if (method !== 'GET') return go();
    return go().catch((e) => {
      if (init && init.signal && init.signal.aborted) throw e;
      return new Promise((res) => setTimeout(res, 600)).then(go);
    });
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
    not_admin: 'Not allowed for this group.',
    not_team: 'Not a team login.',
    bad_email: 'The email is not valid.',
    not_portal_contact: 'The deployed function predates portal access. Redeploy invite-member.'
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
    'review_hidden, deal_value, deal_note, commence, slug, stage_since, stage_log, client_code';
  const BILL_COLS = ['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no', 'bill_contact_id',
    'bill_contact', 'bill_contact_email', 'bill_contact_phone', 'finance_email', 'billing_address'];
  /* Billing by client id: { id: row }. A row carries `missing`, the
     required fields left blank, even where the values are withheld, so the
     Active gate still names them. Before the migration has run the function
     is missing and the columns are still readable, so they are read
     straight; after it, a refusal answers {}. Never throws. */
  function clientBilling(ids) {
    if (!client) return Promise.resolve({});
    const keyed = (rows) => {
      const out = {};
      (rows || []).forEach((r) => { out[r.id] = r; });
      return out;
    };
    const direct = () => {
      let q = client.from('clients').select('id, ' + BILL_COLS.join(', '));
      if (ids) q = q.in('id', ids);
      return q.then((r) => keyed(r.error ? [] : r.data), () => ({}));
    };
    return client.rpc('client_billing', { p_ids: ids || null })
      .then((r) => (r.error ? direct() : keyed(r.data)), direct);
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

  window.ADspaceAPI = {
    accessToken,
    waNumber,
    movedKey,
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
