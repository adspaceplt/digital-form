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

  window.ADspaceAPI = {
    configured,
    client,
    getReviewFeed,
    submitReview
  };
})();
