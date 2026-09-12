/* Stands in for the Supabase UMD bundle. Just enough of the query builder
   that the admin console cannot tell the difference. */
(function () {
  var DB = {
    clients: [{ id: 'c1', name: 'HKL Lim Motorsport', access_token: 'tok1', logo_url: null, passcode: null }],
    activity_viewers: [{ email: 'adspacestudios@gmail.com' }],
    activity_log: [
      { id: 'a1', actor: 'adspacestudios@gmail.com', action: 'set.published', subject: 'March Content', detail: '', created_at: new Date().toISOString() }
    ],
    links: [
      { slug: 'spring-launch', target_url: 'https://example.com/spring', title: 'Spring campaign', active: true, created_at: '2026-01-01T00:00:00Z' },
      { slug: 'raya-2026', target_url: 'https://example.com/raya', title: null, active: true, created_at: '2026-01-02T00:00:00Z' }
    ],
    batches: [],
    link_qrs: []
  };
  window.__DB = DB;

  function result(rows) { return { data: rows, error: null }; }

  function builder(table) {
    var rows = (DB[table] || []).slice();
    var single = false;
    var api = {};
    ['select', 'order', 'limit', 'ilike', 'eq', 'neq'].forEach(function (m) {
      api[m] = function (a, b) {
        if (m === 'eq') rows = rows.filter(function (r) { return String(r[a]) === String(b); });
        if (m === 'ilike') rows = rows.filter(function (r) {
          return String(r[a] || '').toLowerCase() === String(b || '').toLowerCase();
        });
        return api;
      };
    });
    api.is = function (f, v) {
      rows = rows.filter(function (r) { return v === null ? (r[f] === null || r[f] === undefined) : r[f] === v; });
      return api;
    };
    api.not = function (f, op, v) {
      if (op === 'is' && v === null) rows = rows.filter(function (r) { return r[f] !== null && r[f] !== undefined; });
      return api;
    };
    api.single = function () { single = true; return api; };
    api.insert = function (row) {
      var r = Array.isArray(row) ? row : [row];
      r.forEach(function (x) { x.id = x.id || 'gen' + Math.random().toString(16).slice(2, 8); DB[table].push(x); });
      rows = r; return api;
    };
    api.upsert = function (row) {
      var r = Array.isArray(row) ? row : [row];
      r.forEach(function (x) {
        var i = DB[table].findIndex(function (y) { return y.slug === x.slug; });
        if (i > -1) DB[table][i] = Object.assign({}, DB[table][i], x);
        else DB[table].push(Object.assign({ active: true, created_at: new Date().toISOString() }, x));
      });
      rows = r; return api;
    };
    // Deferred, so a following .eq() actually narrows it. Applying the patch
    // here patched every row in the table.
    api.update = function (patch) {
      api.__patch = patch;
      var origEq = api.eq;
      api.eq = function (f, v) {
        DB[table].forEach(function (r) {
          if (String(r[f]) === String(v)) Object.assign(r, api.__patch);
        });
        rows = DB[table].filter(function (r) { return String(r[f]) === String(v); });
        return api;
      };
      return api;
    };
    api.delete = function () {
      api.__del = true;
      var orig = api.eq;
      api.eq = function (a, b) {
        DB[table] = DB[table].filter(function (r) { return String(r[a]) !== String(b); });
        rows = []; return api;
      };
      return api;
    };
    api.then = function (ok, bad) {
      var out = result(single ? (rows[0] || null) : rows);
      return Promise.resolve(out).then(ok, bad);
    };
    return api;
  }

  var session = null;
  var listener = null;

  window.supabase = {
    createClient: function () {
      return {
        from: builder,
        rpc: function (name) {
          if (name === 'me') {
            var email = session && session.user && session.user.email;
            return Promise.resolve({ data: email ? {
              id: 't0', name: 'ADspace', email: email, role: 'admin', active: true,
              can_clients: true, can_review: true, can_campaigns: true, can_links: true,
              can_activity: true, can_billing: true, can_remove: true
            } : null, error: null });
          }
          return Promise.resolve({ data: null, error: null });
        },
        auth: {
          getSession: function () { return Promise.resolve({ data: { session: session } }); },
          onAuthStateChange: function (fn) { listener = fn; return { data: {} }; },
          signInWithOtp: function () { return Promise.resolve({ error: null }); },
          signOut: function () { session = null; return Promise.resolve({}); }
        }
      };
    }
  };

  window.__signIn = function (email) {
    session = { user: { email: email } };
    if (listener) listener('SIGNED_IN', session);
  };
})();
