/* Supabase access layer. Falls back to demo data when no project is configured. */
(function () {
  const cfg = window.ADSPACE_CONFIG || {};
  const configured = Boolean(cfg.supabaseUrl && cfg.supabaseAnonKey);

  let client = null;
  if (configured && window.supabase) {
    client = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  }

  async function getReviewFeed(token, passcode) {
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
    if (!client) {
      return { ok: true, demo: true };
    }
    const { data, error } = await client.rpc('submit_review', {
      p_token: payload.token,
      p_post_id: payload.postId,
      p_decision: payload.decision,
      p_note: payload.note || null,
      p_reviewer: payload.reviewer || null,
      p_passcode: payload.passcode || null
    });
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

  window.ADspaceAPI = {
    configured,
    client,
    getReviewFeed,
    submitReview,
    invokeFn
  };
})();
