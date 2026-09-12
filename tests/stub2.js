/* Supabase stand-in with just enough query builder + the campaign RPCs. */
(function () {
  var DB = {
    clients: [{ id: 'c1', name: 'Laman Citra', logo_url: null, stage: 'active', market: 'MY', owner: 'Qiao Rou', industry: 'Property', sst_applies: true, review_hidden: false, legal_name:'LAMAN CITRA SDN BHD', company_no:'202201012345', company_no_old:'1234567-A', tin:'C 123', sst_no:'W10-1', bill_contact:'Mr Lim', bill_contact_email:'lim@lc.com', bill_contact_phone:'0123', finance_email:'acc@lc.com', billing_address:'JB' },
              { id: 'c2', name: 'Furiku Matcha', logo_url: null, stage: 'proposal', market: 'SG', owner: 'Aisyah', industry: 'F&B', sst_applies: true }],
    creators: [
      { id: 'k1', name: '香香的爆米花 🍿', followers: 12400, cost_rate: 280, client_rate: 360, industries: 'lifestyle' },
      { id: 'k2', name: '恩比', followers: 8100, cost_rate: 300, client_rate: 360, industries: 'F&B' },
      { id: 'k3', name: '小熊爱睡觉', followers: 30200, cost_rate: 400, client_rate: 500, industries: 'property' }
    ],
    creator_profiles: [
      { id: 'p1', creator_id: 'k1', platform: 'xhs', url: 'https://www.xiaohongshu.com/user/profile/5e3262fd00000000010015b6', handle: '5e3262fd00000000010015b6' },
      { id: 'p2', creator_id: 'k1', platform: 'instagram', url: 'https://instagram.com/popcorn.xx', handle: 'popcorn.xx' },
      { id: 'p3', creator_id: 'k2', platform: 'xhs', url: 'https://www.xiaohongshu.com/user/profile/5c0b42e900000000070189f5', handle: '5c0b42e900000000070189f5' },
      { id: 'p4', creator_id: 'k3', platform: 'xhs', url: 'https://xhslink.com/m/2A4ScbR8Kjg', handle: null }
    ],
    campaigns: [],
    campaign_options: [],
    campaign_confirmations: [],
    option_posts: [],
    option_reviews: [],
    activity_log: [], activity_viewers: [{ email: 'adspacestudios@gmail.com' }],
    client_contacts: [{ id: 'ct1', client_id: 'c1', name: 'Mr Lim', role: 'Director', phone: '0123', email: 'lim@lc.com', lang: 'en', is_primary: true }],
    client_touches: [],
    services: [
      { slug:'static-graphic', category:'Content', name:'Static graphic', rate:360, unit:'Per post', position:10, active:true },
      { slug:'reels-60', category:'Content', name:'Reels, up to 60 seconds', rate:800, unit:'Per video', position:14, active:true },
      { slug:'pkg-b', category:'Monthly packages', name:'Package B · 2 platforms · 4 contents', rate:2830, unit:'Per month, 6 month minimum', position:41, active:true },
      { slug:'koc-10', category:'KOC programmes', name:'KOC package · 10 creators', rate:4500, unit:'Per campaign', position:50, active:true },
      { slug:'koc-custom', category:'KOC programmes', name:'KOC custom list', rate:null, unit:'Costed list per creator', position:53, active:true }],
    client_services: [], client_documents: [],
    team_roles: [
      { slug:'admin', name:'Admin', is_admin:true, position:0, can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:true, can_billing:true, can_remove:true },
      { slug:'account', name:'Account', is_admin:false, position:1, can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:false, can_billing:true, can_remove:false },
      { slug:'sales', name:'Sales', is_admin:false, position:2, can_clients:true, can_review:false, can_campaigns:false, can_links:false, can_activity:false, can_billing:true, can_remove:false }],
    team_members: [
      { id:'t0', name:'ADspace', email:'adspacestudios@gmail.com', active:true, role:'admin', is_admin:true, can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:true, can_billing:true, can_remove:true },
      { id:'t1', name:'Qiao Rou', email:'qiaorou@adspacestudios.com', active:true, role:'sales', can_clients:true, can_review:false, can_campaigns:false, can_links:false, can_activity:false, can_billing:true, can_remove:false },
      { id:'t2', name:'Aisyah', email:'aisyah@adspacestudios.com', active:true, role:'account', can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:false, can_billing:true, can_remove:false }],
    links: [], batches: []
  };
  // Survive a reload, so "come back to the link later" is actually testable.
  try {
    var kept = sessionStorage.getItem('__stubdb');
    if (kept) DB = JSON.parse(kept);
  } catch (e) {}
  function persist() {
    try { sessionStorage.setItem('__stubdb', JSON.stringify(DB)); } catch (e) {}
  }
  window.__DB = DB;
  window.__persist = persist;
  var seq = Number(sessionStorage.getItem('__stubseq') || 0);
  function nid(p) {
    seq++;
    try { sessionStorage.setItem('__stubseq', String(seq)); } catch (e) {}
    return p + 'x' + seq;
  }

  function hydrate(table, rows, sel) {
    sel = sel || '';
    return rows.map(function (r) {
      var o = Object.assign({}, r);
      if (table === 'creators' && sel.indexOf('creator_profiles') > -1) {
        o.creator_profiles = DB.creator_profiles.filter(function (p) { return p.creator_id === r.id; });
      }
      if (table === 'campaigns' && sel.indexOf('clients') > -1) {
        o.clients = DB.clients.filter(function (c) { return c.id === r.client_id; })[0] || null;
      }
      if (table === 'campaign_options' && sel.indexOf('creators') > -1) {
        var cr = DB.creators.filter(function (c) { return c.id === r.creator_id; })[0];
        o.creators = cr ? Object.assign({}, cr, {
          creator_profiles: DB.creator_profiles.filter(function (p) { return p.creator_id === cr.id; })
        }) : null;
      }
      return o;
    });
  }

  function builder(table) {
    var rows = (DB[table] || []).slice();
    var sel = '', single = false, pending = null, mode = null;
    var api = {};
    api.select = function (s) { sel = s || '*'; return api; };
    api.order = function () { return api; };
    api.limit = function () { return api; };
    api.ilike = function (f, v) {
      // % is the wildcard, as in the real thing.
      var re = new RegExp('^' + String(v || '').toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*') + '$');
      rows = rows.filter(function (r) { return re.test(String(r[f] || '').toLowerCase()); });
      return api;
    };
    // .is(field, null) and .not(field, 'is', null), as the real client has them.
    api.is = function (f, v) {
      rows = rows.filter(function (r) { return v === null ? (r[f] === null || r[f] === undefined) : r[f] === v; });
      return api;
    };
    api.not = function (f, op, v) {
      if (op === 'is' && v === null) rows = rows.filter(function (r) { return r[f] !== null && r[f] !== undefined; });
      return api;
    };
    api.eq = function (f, v) {
      if (mode === 'delete') {
        DB[table] = DB[table].filter(function (r) { return String(r[f]) !== String(v); });
        rows = [];
      } else if (mode === 'update') {
        DB[table].forEach(function (r) { if (String(r[f]) === String(v)) Object.assign(r, pending); });
        rows = DB[table].filter(function (r) { return String(r[f]) === String(v); });
      } else {
        rows = rows.filter(function (r) { return String(r[f]) === String(v); });
      }
      return api;
    };
    api.single = function () { single = true; return api; };
    api.insert = function (row) {
      var arr = Array.isArray(row) ? row : [row];
      var err = null;
      arr.forEach(function (x) {
        x.id = x.id || nid(table[0]);
        // The real database stamps this by default.
        if (!x.created_at) x.created_at = new Date().toISOString();
        if (table === 'creator_profiles' && x.handle) {
          var clash = DB.creator_profiles.some(function (p) {
            return p.handle && p.platform === x.platform &&
                   String(p.handle).toLowerCase() === String(x.handle).toLowerCase();
          });
          if (clash) err = { message: 'duplicate key value violates unique constraint' };
        }
        if (table === 'campaign_options') {
          var dup = DB.campaign_options.some(function (o) {
            return o.campaign_id === x.campaign_id && o.creator_id === x.creator_id;
          });
          if (dup) err = { message: 'duplicate key value violates unique constraint' };
        }
        if (!err) DB[table].push(x);
      });
      rows = arr;
      if (err) { api.__err = err; }
      return api;
    };
    api.update = function (patch) { mode = 'update'; pending = patch; return api; };
    api.delete = function () { mode = 'delete'; return api; };
    api.then = function (ok, bad) {
      persist();
      var out = api.__err
        ? { data: null, error: api.__err }
        : { data: single ? (hydrate(table, rows, sel)[0] || null) : hydrate(table, rows, sel), error: null };
      return Promise.resolve(out).then(ok, bad);
    };
    return api;
  }

  var session = null, listener = null;

  function rpc(name, args) {
    if (name === 'get_campaign') {
      var c = DB.campaigns.filter(function (x) { return x.access_token === args.p_token; })[0];
      if (!c) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      if (c.passcode && args.p_passcode !== c.passcode) {
        return Promise.resolve({ data: { error: 'passcode' }, error: null });
      }
      var cl = DB.clients.filter(function (x) { return x.id === c.client_id; })[0] || {};
      var opts = DB.campaign_options.filter(function (o) {
        return o.campaign_id === c.id && o.state !== 'replaced';
      }).map(function (o) {
        var cr = DB.creators.filter(function (x) { return x.id === o.creator_id; })[0] || {};
        return {
          id: o.id, name: cr.name, followers: cr.followers, rate: o.rate,
          platforms: o.platforms, state: o.state, is_replacement: o.is_replacement,
          visit_date: o.visit_date, visit_time: o.visit_time,
          visit_location: o.visit_location, visit_pic: o.visit_pic,
          visit_pic_phone: o.visit_pic_phone, tracking_no: o.tracking_no,
          draft_url: o.draft_url, revision_round: o.revision_round,
          planned_publish: o.planned_publish,
          profiles: DB.creator_profiles.filter(function (p) { return p.creator_id === cr.id; })
                     .map(function (p) { return { platform: p.platform, url: p.url }; }),
          posts: DB.option_posts.filter(function (p) { return p.option_id === o.id; })
        };
      });
      return Promise.resolve({ data: {
        campaign: { title: c.title, title_zh: c.title_zh, purpose: c.purpose, slots: c.slots, deadline: c.deadline,
                    state: c.state, deliverable: c.deliverable, brief: c.brief,
                    push_format: c.push_format, invoice_no: c.invoice_no, invoice_url: c.invoice_url },
        client: { name: cl.name, logo_url: cl.logo_url,
                  market: cl.market || 'MY',
                  sst_applies: cl.sst_applies === undefined ? true : cl.sst_applies },
        options: opts }, error: null });
    }
    if (name === 'me') {
      var email = session && session.user && session.user.email;
      var row = DB.team_members.filter(function (t) { return t.active && String(t.email||'').toLowerCase() === String(email||'').toLowerCase(); })[0];
      return Promise.resolve({ data: row || null, error: null });
    }
    if (name === 'save_selection') {
      var cc = DB.campaigns.filter(function (x) { return x.access_token === args.p_token; })[0];
      if (!cc) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      if ((args.p_selected || []).length > cc.slots) {
        return Promise.resolve({ data: { error: 'over-slots', slots: cc.slots }, error: null });
      }
      DB.campaign_options.forEach(function (o) {
        if (o.campaign_id !== cc.id) return;
        if (o.state === 'shortlisted' || o.state === 'backup') o.state = 'option';
        if ((args.p_selected || []).indexOf(o.id) > -1) o.state = 'shortlisted';
        else if ((args.p_backup || []).indexOf(o.id) > -1) o.state = 'backup';
      });
      window.__saves = (window.__saves || 0) + 1;
      persist();
      return Promise.resolve({ data: { ok: true }, error: null });
    }
    if (name === 'confirm_selection') {
      if (!String(args.p_person || '').trim()) {
        return Promise.resolve({ data: { error: 'name-required' }, error: null });
      }
      DB.campaign_confirmations.push({ person: args.p_person, kind: 'client', at: new Date().toISOString() });
      persist();
      return Promise.resolve({ data: { ok: true }, error: null });
    }
    if (name === 'review_draft') {
      var oo = DB.campaign_options.filter(function (x) { return x.id === args.p_option; })[0];
      if (!oo) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      if (['reviewing', 'changes'].indexOf(oo.state) < 0) {
        return Promise.resolve({ data: { error: 'not-reviewing' }, error: null });
      }
      var n = oo.revision_round || 0;
      DB.option_reviews.push({ option_id: oo.id, round: Math.max(n, 1),
        decision: args.p_decision, note: args.p_note, reviewer: args.p_reviewer });
      if (args.p_decision === 'approved') oo.state = 'scheduled';
      else { oo.state = 'changes'; oo.revision_round = Math.max(n, 1) + 1; }
      persist();
      return Promise.resolve({ data: { ok: true, decision: args.p_decision }, error: null });
    }
    return Promise.resolve({ data: null, error: null });
  }

  window.supabase = { createClient: function () {
    return { from: builder, rpc: rpc,
      functions: { invoke: function (name, opts) {
        window.__signed = (window.__signed || []).concat([{ name: name, body: opts && opts.body }]);
        if (name === 'invite-member') return Promise.resolve({ data: { ok: true, already: false }, error: null });
        return Promise.resolve({ data: { uploadUrl: 'https://s3.test/put/inv.pdf',
          publicUrl: 'https://mycdn.adspace.me/content/c1/inv-' + Date.now() + '.pdf' }, error: null });
      } },
      auth: {
      getSession: function () { return Promise.resolve({ data: { session: session } }); },
      onAuthStateChange: function (fn) { listener = fn; return { data: {} }; },
      signInWithOtp: function () { return Promise.resolve({ error: null }); },
      signOut: function () { session = null; return Promise.resolve({}); }
    } };
  } };
  window.__signIn = function (e) { session = { user: { email: e } }; if (listener) listener('SIGNED_IN', session); };
})();
