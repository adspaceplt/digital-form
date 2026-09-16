/* Supabase stand-in with just enough query builder + the campaign RPCs. */
(function () {
  var DB = {
    clients: [{ id: 'c1', slug: 'laman-citra', name: 'Laman Citra', logo_url: null, stage: 'active',
                stage_since: new Date(Date.now() - 12 * 864e5).toISOString(),
                stage_log: [{ stage:'lead', at: new Date(Date.now() - 40 * 864e5).toISOString() },
                            { stage:'contacted', at: new Date(Date.now() - 38 * 864e5).toISOString() },
                            { stage:'proposal', at: new Date(Date.now() - 29 * 864e5).toISOString() },
                            { stage:'active', at: new Date(Date.now() - 12 * 864e5).toISOString() }], market: 'MY', owner: 'Qiao Rou', industry: 'Property', sst_applies: true, review_hidden: false, legal_name:'LAMAN CITRA SDN BHD', company_no:'202201012345', company_no_old:'1234567-A', tin:'C 123', sst_no:'W10-1', bill_contact:'Mr Lim', bill_contact_email:'lim@lc.com', bill_contact_phone:'0123', finance_email:'acc@lc.com', billing_address:'JB' },
              { id: 'c2', slug: 'furiku-matcha', name: 'Furiku Matcha', logo_url: null, stage: 'proposal',
                stage_since: new Date(Date.now() - 3 * 864e5).toISOString(), market: 'SG', owner: 'Aisyah', industry: 'F&B', sst_applies: true }],
    creators: [
      { id: 'k1', name: '香香的爆米花 🍿', followers: 12400, cost_rate: 280, client_rate: 360, industries: 'lifestyle', active: true, access_code: 'K1AAAAAA' },
      { id: 'k2', name: '恩比', followers: 8100, cost_rate: 300, client_rate: 360, industries: 'F&B', active: true, access_code: 'K2BBBBBB' },
      { id: 'k3', name: '小熊爱睡觉', followers: 30200, cost_rate: 400, client_rate: 500, industries: 'property', active: true, access_code: 'K3CCCCCC' }
    ],
    creator_profiles: [
      { id: 'p1', creator_id: 'k1', platform: 'xhs', url: 'https://www.xiaohongshu.com/user/profile/5e3262fd00000000010015b6', handle: '5e3262fd00000000010015b6' },
      { id: 'p2', creator_id: 'k1', platform: 'instagram', url: 'https://instagram.com/popcorn.xx', handle: 'popcorn.xx' },
      { id: 'p3', creator_id: 'k2', platform: 'xhs', url: 'https://www.xiaohongshu.com/user/profile/5c0b42e900000000070189f5', handle: '5c0b42e900000000070189f5' },
      { id: 'p4', creator_id: 'k3', platform: 'xhs', url: 'https://xhslink.com/m/2A4ScbR8Kjg', handle: null }
    ],
    campaigns: [],
    campaign_options: [],
    campaign_deliverables: [],
    campaign_confirmations: [],
    option_posts: [],
    option_reviews: [],
    activity_log: [], activity_viewers: [{ email: 'adspacestudios@gmail.com' }],
    client_contacts: [{ id: 'ct1', client_id: 'c1', name: 'Mr Lim', role: 'Director', phone: '0123', email: 'lim@lc.com', lang: 'en', is_primary: true }],
    client_touches: [],
    services: [
      { slug:'static-graphic', category:'Content', name:'Static graphic', rate:360, unit:'Per post', position:10, active:true },
      { slug:'reels-60', category:'Content', name:'Reels, up to 60 seconds', rate:800, unit:'Per video', position:14, active:true },
      { slug:'pkg-b', category:'Monthly packages', name:'Package B · 2 platforms · 4 contents', rate:2830, unit:'Per month, 6 month minimum', position:41, active:true,
        min_months:6, detail:'Up to 2 platforms\n4 contents each month: 1 graphic and 3 reels up to 60s, or 4 reels up to 60s\nDedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nBasic accounts analytics report' },
      { slug:'koc-10', category:'KOC programmes', name:'KOC package · 10 creators', rate:4500, unit:'Per campaign', position:50, active:true },
      { slug:'koc-custom', category:'KOC programmes', name:'KOC custom list', rate:null, unit:'Costed list per creator', position:53, active:true },
      { slug:'rev-minor', category:'Add-ons', name:'Minor revision', rate:200, unit:'Per asset, per round', position:70, active:true },
      { slug:'urgent', category:'Add-ons', name:'Urgent fee', rate:150, unit:'Per affected asset, per round', position:72, active:true }],
    client_services: [], client_documents: [], client_requests: [],
    client_document_services: [], client_document_seq: [],
    team_roles: [
      { slug:'admin', name:'Admin', is_admin:true, position:0, can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:true, can_billing:true, can_remove:true },
      { slug:'account', name:'Marketing', is_admin:false, position:1, can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:false, can_billing:true, can_remove:false },
      { slug:'sales', name:'Sales', is_admin:false, position:2, can_clients:true, can_review:false, can_campaigns:false, can_links:false, can_activity:false, can_billing:true, can_remove:false }],
    team_members: [
      { id:'t0', name:'ADspace', email:'adspacestudios@gmail.com', active:true, role:'admin', is_admin:true, can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:true, can_billing:true, can_remove:true },
      { id:'t1', name:'Qiao Rou', email:'qiaorou@adspacestudios.com', active:true, role:'sales', can_clients:true, can_review:false, can_campaigns:false, can_links:false, can_activity:false, can_billing:true, can_remove:false },
      { id:'t2', name:'Aisyah', email:'aisyah@adspacestudios.com', active:true, role:'account', can_clients:true, can_review:true, can_campaigns:true, can_links:true, can_activity:false, can_billing:true, can_remove:false }],
    links: [
      { id:'l1', slug:'raya-2026', target_url:'https://adspacestudios.com/campaigns/raya-2026', title:'Raya landing', active:true },
      { id:'l2', slug:'menu-hkl', target_url:'https://hkllim.com/menu?utm_source=qr&utm_medium=table-tent', title:'Table tent QR', active:true },
      { id:'l3', slug:'old-promo', target_url:'https://adspacestudios.com/promo/2025', title:'', active:false }
    ], batches: []
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
  // The client-facing doors, so a test can ask what a client would be told
  // without opening the client's page.
  window.__rpc = function (name, args) { return rpc(name, args); };
  var seq = Number(sessionStorage.getItem('__stubseq') || 0);
  function nid(p) {
    seq++;
    try { sessionStorage.setItem('__stubseq', String(seq)); } catch (e) {}
    return p + 'x' + seq;
  }

  /* The clients_stage_clock trigger, in the stand-in: only a real move
     restarts the clock, and the history is appended where the move happens.
     Without it a test would measure the page rather than the behaviour. */
  function stageClock(table, row, patch) {
    if (table !== 'clients' || !patch || !('stage' in patch)) return;
    if (patch.stage === row.stage) return;
    // A patch that sets the clock itself is left alone, the way the trigger
    // now leaves a deliberate write alone: the migration writes these columns.
    if ('stage_since' in patch || 'stage_log' in patch) return;
    var now = new Date().toISOString();
    patch.stage_since = now;
    patch.stage_log = (row.stage_log || []).concat([{ stage: patch.stage, at: now }]);
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
    /* A read the database refuses. Every list in the console has a failed
       state and none of them was ever driven, because nothing here could say
       no: `window.__failRead = { clients: 'permission denied' }` is how a
       suite reaches that screen. */
    if (window.__failRead && window.__failRead[table]) api.__err = { message: window.__failRead[table] };
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
    // .in(field, [..]) — how a read is scoped to one campaign's bookings.
    api.in = function (f, vals) {
      var set = (vals || []).map(String);
      rows = rows.filter(function (r) { return set.indexOf(String(r[f])) > -1; });
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
        DB[table].forEach(function (r) {
          if (String(r[f]) !== String(v)) return;
          stageClock(table, r, pending);
          Object.assign(r, pending);
        });
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
        if (table === 'clients') {
          x.stage = x.stage || 'lead';
          x.stage_since = x.stage_since || x.created_at;
          x.stage_log = x.stage_log || [{ stage: x.stage, at: x.stage_since }];
        }
        if (table === 'creator_profiles' && x.handle) {
          var clash = DB.creator_profiles.some(function (p) {
            return p.handle && p.platform === x.platform &&
                   String(p.handle).toLowerCase() === String(x.handle).toLowerCase();
          });
          if (clash) err = { message: 'duplicate key value violates unique constraint' };
        }
        if (table === 'creators' && !x.access_code) {
          var alpha2 = '23456789ABCDEFGHJKMNPQRSTUVWXYZ', o2 = '';
          for (var z = 0; z < 8; z++) o2 += alpha2[Math.floor(Math.random() * alpha2.length)];
          x.access_code = o2;
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
      /* A read that takes a moment, so the loading state is a screen somebody
         can actually be shown. Resolved in a microtask, every list in the
         console painted its skeleton and replaced it in the same frame, and
         the state nobody could reach was the state nobody checked. */
      var wait = window.__slowRead && window.__slowRead[table];
      if (wait) return new Promise(function (go) { setTimeout(function () { go(out); }, wait); }).then(ok, bad);
      return Promise.resolve(out).then(ok, bad);
    };
    return api;
  }

  var session = null, listener = null;

  /* ---- The letter's own lifecycle -----------------------------------------
     The real thing is five security definer functions; this is the same
     behaviour in the stand-in, so a browser suite exercises the rules rather
     than a page that happens to draw them. The refusals are the refusals the
     database gives, by the same names. */
  var TEAM_CAN = { clients: true, billing: true, admin: true };
  window.__teamCan = TEAM_CAN;
  function whoNow() { return String(session && session.user && session.user.email || '').toLowerCase(); }

  function kualaYM() {
    // Asia/Kuala_Lumpur is UTC+8 all year: no daylight saving to reason about.
    var d = new Date(Date.now() + 8 * 3600 * 1000);
    return String(d.getUTCFullYear()).slice(2) + String(d.getUTCMonth() + 1).padStart(2, '0');
  }

  function issueLetter(a) {
    if (!TEAM_CAN.clients) return { error: 'not-allowed' };
    var ids = a.p_services || [];
    if (!ids.length) return { error: 'no-lines' };
    var cl = DB.clients.filter(function (c) { return c.id === a.p_client; })[0];
    if (!cl) return { error: 'no-client' };
    if (!String(cl.client_code || '').trim()) return { error: 'no-client-code' };

    var idem = String(a.p_idem || '').trim();
    if (idem) {
      var had = DB.client_documents.filter(function (d) {
        return d.client_id === a.p_client && d.idem_key === idem;
      })[0];
      if (had) return { ok: true, repeat: true, id: had.id, number: had.number };
    }

    var rows = ids.map(function (id) {
      return DB.client_services.filter(function (l) {
        return l.id === id && l.client_id === a.p_client && !l.archived_at;
      })[0];
    });
    if (rows.some(function (l) { return !l; })) return { error: 'bad-lines' };
    if (rows.some(function (l) { return ['quoted', 'confirmed'].indexOf(l.state) < 0; })) return { error: 'bad-lines' };
    if (!a.p_renewal && rows.some(function (l) { return l.state === 'confirmed'; })) return { error: 'bad-lines' };

    // A line already on a letter that can still become something.
    var held = DB.client_document_services.filter(function (m) {
      if (ids.indexOf(m.service_id) < 0) return false;
      var d = DB.client_documents.filter(function (x) { return x.id === m.document_id; })[0];
      if (!d || d.voided_at || d.superseded_by || d.verified_at) return false;
      return !a.p_replaces || d.id !== a.p_replaces;
    });
    if (held.length) return { error: 'already-quoted' };

    var prior = null;
    if (a.p_replaces) {
      prior = DB.client_documents.filter(function (d) {
        return d.id === a.p_replaces && d.client_id === a.p_client;
      })[0];
      if (!prior) return { error: 'no-replaces' };
      if (prior.verified_at) return { error: 'replaces-verified' };
    }

    var ym = kualaYM();
    var seat = DB.client_document_seq.filter(function (q) {
      return q.client_id === a.p_client && q.ym === ym;
    })[0];
    if (!seat) { seat = { client_id: a.p_client, ym: ym, next_val: 1 }; DB.client_document_seq.push(seat); }
    var n = seat.next_val;
    seat.next_val = n + 1;
    // Two digits is the floor, not the ceiling.
    var num = 'AQL/' + cl.client_code + '/' + ym + (n < 100 ? String(n).padStart(2, '0') : String(n));

    var ct = DB.client_contacts.filter(function (x) {
      return x.client_id === a.p_client && !x.archived_at;
    }).sort(function (x, y) { return (y.is_primary ? 1 : 0) - (x.is_primary ? 1 : 0); })[0] || {};
    var taxOn = cl.sst_applies !== false;
    var doc = {
      id: nid('doc'), client_id: a.p_client, kind: 'offer', number: num,
      issued_at: new Date().toISOString().slice(0, 10), market: cl.market || 'MY',
      subtotal: Number(a.p_subtotal || 0), tax: Number(a.p_tax || 0), total: Number(a.p_total || 0),
      bill_to: {
        name: cl.name || '', legal_name: cl.legal_name || '', address: cl.billing_address || '',
        regno: cl.company_no || '', regno_old: cl.company_no_old || '', tin: cl.tin || '',
        sst_no: cl.sst_no || '', sst_applies: taxOn,
        contact: ct.name || '', contact_role: ct.role || '', phone: ct.phone || '', email: ct.email || '',
        finance_email: cl.finance_email || '', client_code: cl.client_code,
        owner: (a.p_deal || {}).owner || '', source: (a.p_deal || {}).source || '',
        industry: (a.p_deal || {}).industry || '', stage: (a.p_deal || {}).stage || '',
        enquiry: (a.p_deal || {}).enquiry || ''
      },
      lines: rows.map(function (l) {
        return { label: l.label, unit: l.unit || '', note: l.note || '', detail: l.detail || '',
                 state: l.state, qty: Number(l.qty || 0), rate: Number(l.rate || 0),
                 tenure: Math.max(1, Number(l.tenure || 1)), start_on: l.start_on || '',
                 tax: taxOn, service_id: l.id };
      }),
      issued_by: whoNow(), client_code: cl.client_code,
      idem_key: idem || null, created_at: new Date().toISOString(),
      voided_at: null, signed_at: null, verified_at: null, verified_by: null, superseded_by: null
    };
    DB.client_documents.push(doc);
    ids.forEach(function (id) {
      DB.client_document_services.push({ document_id: doc.id, service_id: id, created_at: new Date().toISOString() });
    });
    if (prior) prior.superseded_by = doc.id;
    DB.activity_log.push({ id: nid('a'), actor: whoNow(), action: 'document.issued', subject: cl.name,
      detail: num + ' · ' + ids.length + ' line' + (ids.length === 1 ? '' : 's'), created_at: new Date().toISOString() });
    persist();
    return { ok: true, id: doc.id, number: num };
  }

  function letterSetSigned(a) {
    if (!TEAM_CAN.clients) return { error: 'not-allowed' };
    var d = DB.client_documents.filter(function (x) { return x.id === a.p_doc; })[0];
    if (!d) return { error: 'not-found' };
    if (d.voided_at) return { error: 'voided' };
    if (d.verified_at) return { error: 'verified' };
    var on = a.p_on !== false;
    if (Boolean(d.signed_at) === on) return { ok: true, repeat: true };
    d.signed_at = on ? new Date().toISOString() : null;
    persist();
    return { ok: true };
  }

  function verifyLetter(a) {
    if (!TEAM_CAN.billing) return { error: 'not-allowed' };
    var d = DB.client_documents.filter(function (x) { return x.id === a.p_doc; })[0];
    if (!d) return { error: 'not-found' };
    if (d.voided_at) return { error: 'voided' };
    if (d.superseded_by) return { error: 'superseded' };
    if (!d.signed_at) return { error: 'not-signed' };
    if (d.verified_at) return { ok: true, repeat: true, confirmed: 0 };
    var map = DB.client_document_services.filter(function (m) { return m.document_id === d.id; });
    if (!map.length || map.length !== (d.lines || []).length) return { error: 'no-mapping' };
    var n = 0;
    map.forEach(function (m) {
      var l = DB.client_services.filter(function (x) { return x.id === m.service_id && !x.archived_at; })[0];
      if (l && l.state !== 'confirmed') { l.state = 'confirmed'; n++; }
    });
    d.verified_at = new Date().toISOString();
    d.verified_by = whoNow();
    persist();
    return { ok: true, confirmed: n };
  }

  function letterSetVoid(a) {
    if (!TEAM_CAN.clients) return { error: 'not-allowed' };
    var d = DB.client_documents.filter(function (x) { return x.id === a.p_doc; })[0];
    if (!d) return { error: 'not-found' };
    if (d.verified_at) return { error: 'verified' };
    var on = a.p_on !== false;
    if (Boolean(d.voided_at) === on) return { ok: true, repeat: true };
    d.voided_at = on ? new Date().toISOString() : null;
    persist();
    return { ok: true };
  }

  function overrideServiceState(a) {
    if (!TEAM_CAN.admin) return { error: 'not-allowed' };
    if (['enquired', 'quoted', 'confirmed'].indexOf(a.p_state) < 0) return { error: 'bad-state' };
    if (!String(a.p_reason || '').trim()) return { error: 'reason-required' };
    var l = DB.client_services.filter(function (x) { return x.id === a.p_service && !x.archived_at; })[0];
    if (!l) return { error: 'not-found' };
    if (l.state === a.p_state) return { ok: true, repeat: true };
    var was = l.state;
    l.state = a.p_state;
    var cl = DB.clients.filter(function (c) { return c.id === l.client_id; })[0] || {};
    DB.activity_log.push({ id: nid('a'), actor: whoNow(), action: 'service.override', subject: cl.name,
      detail: l.label + ' · ' + was + ' to ' + a.p_state + ' · ' + String(a.p_reason).trim(),
      created_at: new Date().toISOString() });
    persist();
    return { ok: true };
  }

  function rpc(name, args) {
    if (name === 'issue_letter')           return Promise.resolve({ data: issueLetter(args), error: null });
    if (name === 'letter_set_signed')      return Promise.resolve({ data: letterSetSigned(args), error: null });
    if (name === 'verify_letter')          return Promise.resolve({ data: verifyLetter(args), error: null });
    if (name === 'letter_set_void')        return Promise.resolve({ data: letterSetVoid(args), error: null });
    if (name === 'override_service_state') return Promise.resolve({ data: overrideServiceState(args), error: null });
    /* The creator's own page. Same shape and the same withholding as the SQL:
       a creator sees their own bookings and never the client's stage, the
       campaign's commercial state, or what the client is paying. */
    var CR_DELIVER = ['pending_draft', 'changes'];
    var CR_SHOW = ['confirmed', 'pending_visit', 'pending_delivery', 'pending_draft',
                   'submitted', 'reviewing', 'changes', 'scheduled', 'posted',
                   'completed', 'withdrawn', 'replaced'];
    function creatorBy(code) {
      return DB.creators.filter(function (c) {
        return c.access_code && c.access_code === String(code || '').toUpperCase();
      })[0];
    }
    if (name === 'reset_creator_code') {
      var cc = DB.creators.filter(function (c) { return c.id === args.p_creator; })[0];
      if (!cc) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      var alpha = '23456789ABCDEFGHJKMNPQRSTUVWXYZ', out = '';
      for (var i = 0; i < 8; i++) out += alpha[Math.floor(Math.random() * alpha.length)];
      cc.access_code = out;
      persist();
      return Promise.resolve({ data: { code: out }, error: null });
    }
    if (name === 'get_creator') {
      var who = creatorBy(args.p_code);
      if (!who) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      if (who.active === false) return Promise.resolve({ data: { error: 'inactive' }, error: null });
      var books = DB.campaign_options.filter(function (o) {
        if (o.creator_id !== who.id || CR_SHOW.indexOf(o.state) < 0) return false;
        var cc = DB.campaigns.filter(function (x) { return x.id === o.campaign_id; })[0];
        return cc && cc.state !== 'draft';
      }).map(function (o) {
        var cc = DB.campaigns.filter(function (x) { return x.id === o.campaign_id; })[0] || {};
        var cl = DB.clients.filter(function (x) { return x.id === cc.client_id; })[0] || {};
        return {
          id: o.id, campaign: cc.title, campaign_zh: cc.title_zh, brand: cl.name,
          brief: cc.brief, brief_zh: cc.brief_zh, deliverable: cc.deliverable,
          push_format: cc.push_format, platforms: o.platforms, rate: o.rate,
          currency: cl.market === 'SG' ? 'SGD' : 'MYR', state: o.state,
          visit_date: o.visit_date, visit_time: o.visit_time,
          visit_location: o.visit_location, visit_pic: o.visit_pic,
          visit_pic_phone: o.visit_pic_phone, tracking_no: o.tracking_no,
          planned_publish: o.planned_publish, revision_round: o.revision_round,
          change_note: o.state === 'changes' ? o.drop_reason : null,
          caption: o.draft_caption, submitted_at: o.submitted_at,
          can_deliver: CR_DELIVER.indexOf(o.state) > -1,
          files: DB.campaign_deliverables.filter(function (d) {
            return d.option_id === o.id && !d.removed_at;
          })
        };
      });
      return Promise.resolve({ data: { creator: { name: who.name, code: who.access_code },
                                       bookings: books }, error: null });
    }
    if (name === 'creator_add_file') {
      /* The database refusing this call is what happened in production, and the
         page said nothing. The suite turns it on deliberately. */
      if (window.__refuseAdd) {
        return Promise.resolve({ data: null, error: { message: 'column reference "id" is ambiguous' } });
      }
      var cA = creatorBy(args.p_code);
      var oA = DB.campaign_options.filter(function (o) { return o.id === args.p_option; })[0];
      if (!cA || !oA || oA.creator_id !== cA.id) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      if (CR_DELIVER.indexOf(oA.state) < 0) return Promise.resolve({ data: { error: 'closed' }, error: null });
      var fid = 'd' + Math.random().toString(36).slice(2, 9);
      DB.campaign_deliverables.push({ id: fid, option_id: oA.id, url: args.p_url,
        name: args.p_name, kind: args.p_kind, bytes: args.p_bytes,
        round: Math.max(oA.revision_round || 0, 1) });
      persist();
      return Promise.resolve({ data: { id: fid }, error: null });
    }
    if (name === 'creator_remove_file') {
      var cR = creatorBy(args.p_code);
      var f = DB.campaign_deliverables.filter(function (d) { return d.id === args.p_file; })[0];
      var oR = f && DB.campaign_options.filter(function (o) { return o.id === f.option_id; })[0];
      if (!cR || !f || !oR || oR.creator_id !== cR.id || CR_DELIVER.indexOf(oR.state) < 0) {
        return Promise.resolve({ data: { error: 'not-found' }, error: null });
      }
      f.removed_at = new Date().toISOString();
      persist();
      return Promise.resolve({ data: { ok: true }, error: null });
    }
    if (name === 'creator_submit') {
      var cS = creatorBy(args.p_code);
      var oS = DB.campaign_options.filter(function (o) { return o.id === args.p_option; })[0];
      if (!cS || !oS || oS.creator_id !== cS.id) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      if (CR_DELIVER.indexOf(oS.state) < 0) return Promise.resolve({ data: { error: 'closed' }, error: null });
      var n = DB.campaign_deliverables.filter(function (d) {
        return d.option_id === oS.id && !d.removed_at; }).length;
      if (!n) return Promise.resolve({ data: { error: 'empty' }, error: null });
      oS.state = 'submitted';        // ours to review, not the client's to approve
      oS.changes_by = null;
      oS.draft_caption = args.p_caption;
      oS.submitted_at = new Date().toISOString();
      persist();
      return Promise.resolve({ data: { ok: true, files: n }, error: null });
    }
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
        /* The same withholding the SQL does: a draft sitting with the team is
           reported as Pending draft, and its files and caption are not sent. */
        var shown = o.state === 'submitted' ? 'pending_draft'
          : (o.state === 'changes' && (o.changes_by || 'client') === 'team') ? 'pending_draft'
          : o.state;
        var released = ['reviewing', 'changes', 'scheduled', 'posted', 'completed']
          .indexOf(shown) > -1;
        var mine = DB.campaign_deliverables.filter(function (d) {
          return d.option_id === o.id && !d.removed_at;
        });
        var top = mine.reduce(function (m, d) { return Math.max(m, d.round || 1); }, 0);
        return {
          id: o.id, name: cr.name, followers: cr.followers, rate: o.rate,
          platforms: o.platforms, state: shown, is_replacement: o.is_replacement,
          visit_date: o.visit_date, visit_time: o.visit_time,
          visit_location: o.visit_location, visit_pic: o.visit_pic,
          visit_pic_phone: o.visit_pic_phone, tracking_no: o.tracking_no,
          draft_url: released ? o.draft_url : null,
          revision_round: o.revision_round,
          files: released ? mine.filter(function (d) { return (d.round || 1) === top; }) : [],
          caption: released ? o.draft_caption : null,
          planned_publish: o.planned_publish,
          profiles: DB.creator_profiles.filter(function (p) { return p.creator_id === cr.id; })
                     .map(function (p) { return { platform: p.platform, url: p.url }; }),
          posts: DB.option_posts.filter(function (p) { return p.option_id === o.id; })
        };
      });
      // The same gate the SQL carries: no invoice until a creator is confirmed.
      var LIVE = ['confirmed', 'pending_visit', 'pending_draft', 'submitted',
                  'reviewing', 'changes', 'scheduled', 'posted', 'completed'];
      var billable = DB.campaign_options.some(function (o) {
        return o.campaign_id === c.id && LIVE.indexOf(o.state) > -1;
      });
      return Promise.resolve({ data: {
        campaign: { title: c.title, title_zh: c.title_zh, purpose: c.purpose, slots: c.slots, deadline: c.deadline,
                    backups_open: Boolean(c.backups_open),
                    state: c.state, deliverable: c.deliverable, brief: c.brief,
                    push_format: c.push_format,
                    invoice_no: billable ? c.invoice_no : null,
                    invoice_url: billable ? c.invoice_url : null },
        client: { name: cl.name, logo_url: cl.logo_url,
                  market: cl.market || 'MY',
                  sst_applies: cl.sst_applies === undefined ? true : cl.sst_applies },
        options: opts }, error: null });
    }
    // ---- Client portal: the same three doors as the SQL ----
    var who = function () { return String(session && session.user && session.user.email || '').toLowerCase(); };
    var portalClients = function () {
      var e = who();
      return (DB.client_contacts || []).filter(function (c) {
        return c.portal_access && !c.archived_at && c.email && String(c.email).toLowerCase() === e;
      }).map(function (c) { return c.client_id; });
    };
    if (name === 'get_portal') {
      DB.client_requests = DB.client_requests || [];
      if (!who()) return Promise.resolve({ data: { error: 'not-signed-in' }, error: null });
      var ids = portalClients();
      var cid = ids.indexOf(args && args.p_client) > -1 ? args.p_client : ids[0];
      if (!cid) return Promise.resolve({ data: { error: 'no-access' }, error: null });
      var pc = DB.clients.filter(function (c) { return c.id === cid; })[0] || {};
      var mine = (DB.client_contacts || []).filter(function (c) { return c.client_id === cid && !c.archived_at; });
      var meRow = mine.filter(function (c) { return c.portal_access && String(c.email || '').toLowerCase() === who(); })[0] || {};
      var pick = function (o, keys) { var out = {}; keys.forEach(function (k) { out[k] = o[k] === undefined ? null : o[k]; }); return out; };
      return Promise.resolve({ data: {
        clients: DB.clients.filter(function (c) { return ids.indexOf(c.id) > -1; }).map(function (c) { return { id: c.id, name: c.name }; }),
        client: { id: pc.id, name: pc.name, legal_name: pc.legal_name || null, company_no: pc.company_no || null,
          billing_address: pc.billing_address || null, market: pc.market || 'MY',
          sst_applies: pc.sst_applies === undefined ? true : pc.sst_applies, stage: pc.stage, owner: pc.owner || null,
          industry: pc.industry || null, website: pc.website || null, logo_url: pc.logo_url || null },
        me: { id: meRow.id, name: meRow.name, email: meRow.email },
        contacts: mine.map(function (c) { return pick(c, ['id', 'name', 'role', 'phone', 'email', 'is_primary', 'portal_access']); }),
        services: (DB.client_services || []).filter(function (s) { return s.client_id === cid && !s.archived_at && (s.state === 'quoted' || s.state === 'confirmed'); })
          .map(function (s) { return pick(s, ['id', 'label', 'unit', 'qty', 'rate', 'tenure', 'start_on', 'state', 'note']); }),
        documents: (DB.client_documents || []).filter(function (d) { return d.client_id === cid && !d.voided_at; })
          .map(function (d) { return pick(d, ['id', 'kind', 'number', 'issued_at', 'market', 'subtotal', 'tax', 'total', 'bill_to', 'lines', 'issued_by']); }),
        requests: DB.client_requests.filter(function (r) { return r.client_id === cid; }).slice().reverse()
          .map(function (r) { return pick(r, ['id', 'kind', 'service_label', 'note', 'state', 'fee', 'reply', 'created_at', 'withdrawn_at']); }),
        review: (!pc.review_hidden && (DB.batches || []).some(function (b) { return b.client_id === cid && b.published; })) ? { token: pc.access_token } : null,
        campaigns: (DB.campaigns || []).filter(function (m) { return m.client_id === cid && m.state !== 'draft'; })
          .map(function (m) { return { id: m.id, title: m.title, title_zh: m.title_zh || null, state: m.state, deadline: m.deadline || null, token: m.access_token }; }),
        access: mine.filter(function (c) { return c.portal_access; }).map(function (c) { return { name: c.name, email: c.email }; })
      }, error: null });
    }
    if (name === 'portal_request') {
      DB.client_requests = DB.client_requests || [];
      if (!who()) return Promise.resolve({ data: { error: 'not-signed-in' }, error: null });
      if (portalClients().indexOf(args.p_client) < 0) return Promise.resolve({ data: { error: 'no-access' }, error: null });
      if (['upgrade', 'downgrade', 'cancel', 'details'].indexOf(args.p_kind) < 0) return Promise.resolve({ data: { error: 'bad-kind' }, error: null });
      var svc = null;
      if (args.p_kind !== 'details') {
        svc = (DB.client_services || []).filter(function (s) { return s.id === args.p_service && s.client_id === args.p_client && !s.archived_at && s.state === 'confirmed'; })[0];
        if (!svc) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      }
      if (args.p_kind !== 'cancel' && !String(args.p_note || '').trim()) return Promise.resolve({ data: { error: 'note-required' }, error: null });
      var meC = (DB.client_contacts || []).filter(function (c) { return c.client_id === args.p_client && c.portal_access && String(c.email || '').toLowerCase() === who(); })[0] || {};
      var rq = { id: nid('r'), client_id: args.p_client, contact_id: meC.id || null, contact_name: meC.name || null, kind: args.p_kind,
        service_id: svc ? svc.id : null, service_label: svc ? svc.label : null, note: String(args.p_note || '').trim() || null,
        state: 'requested', fee: null, reply: null, withdrawn_at: null, created_at: new Date().toISOString() };
      DB.client_requests.push(rq);
      var pcl = DB.clients.filter(function (c) { return c.id === args.p_client; })[0] || {};
      DB.activity_log.push({ id: nid('a'), actor: who(), action: 'request.raised', subject: pcl.name, detail: args.p_kind + (svc ? ' · ' + svc.label : ''), created_at: new Date().toISOString() });
      persist();
      return Promise.resolve({ data: { ok: true, id: rq.id }, error: null });
    }
    if (name === 'portal_withdraw') {
      DB.client_requests = DB.client_requests || [];
      var ids2 = portalClients();
      var hit = DB.client_requests.filter(function (r) {
        return r.id === args.p_id && ids2.indexOf(r.client_id) > -1 && r.state === 'requested' && (!r.withdrawn_at) === !args.p_undo;
      })[0];
      if (!hit) return Promise.resolve({ data: { error: 'not-found' }, error: null });
      hit.withdrawn_at = args.p_undo ? null : new Date().toISOString();
      persist();
      return Promise.resolve({ data: { ok: true }, error: null });
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
      else {
        oo.state = 'changes'; oo.revision_round = Math.max(n, 1) + 1;
        oo.changes_by = 'client';       // theirs, so their page keeps the chip
      }
      persist();
      return Promise.resolve({ data: { ok: true, decision: args.p_decision }, error: null });
    }
    return Promise.resolve({ data: null, error: null });
  }

  window.supabase = { createClient: function () {
    return { from: builder, rpc: rpc,
      functions: { invoke: function (name, opts) {
        window.__signed = (window.__signed || []).concat([{ name: name, body: opts && opts.body }]);
        if (name === 'portal-login') {
          // Only an address the team has marked for portal access gets a login.
          var e = String((opts && opts.body && opts.body.email) || '').toLowerCase();
          var ok = (DB.client_contacts || []).some(function (c) {
            return c.portal_access && !c.archived_at && String(c.email || '').toLowerCase() === e;
          });
          if (ok) window.__logins = (window.__logins || []).concat([e]);
          return Promise.resolve({ data: { ok: ok }, error: null });
        }
        if (name === 'invite-member') {
          // The real client hides the function's answer behind a generic
          // message; the body is on error.context, as it is here.
          if (/^fail/.test(String(opts && opts.body && opts.body.email || ''))) return Promise.resolve({ data: null,
            error: { message: 'Edge Function returned a non-2xx status code',
                     context: { json: function () { return Promise.resolve({ error: 'invite_failed', detail: 'Error sending invite email' }); } } } });
          return Promise.resolve({ data: { ok: true, already: false,
            sent: !(opts && opts.body && opts.body.notify === false) }, error: null });
        }
        /* The real function refuses a creator whose code does not hold that
           booking, and builds the key from the option it checked rather than
           from anything the browser sent. Both are mirrored here so a test
           that loses the check fails. */
        var bd = (opts && opts.body) || {};
        if (bd.creatorCode) {
          var okC = DB.campaign_options.some(function (o) {
            var cr = DB.creators.filter(function (x) { return x.id === o.creator_id; })[0];
            return o.id === bd.optionId && cr && cr.active !== false &&
              cr.access_code === String(bd.creatorCode).toUpperCase() &&
              ['pending_draft', 'changes'].indexOf(o.state) > -1;
          });
          if (!okC) return Promise.resolve({ data: { error: 'not_allowed' }, error: null });
          var kk = 'content/creator/' + bd.optionId + '/' + Math.random().toString(36).slice(2) +
            '.' + (bd.ext || 'bin');
          return Promise.resolve({ data: { uploadUrl: 'https://s3.test/put/' + kk,
            publicUrl: 'https://mycdn.adspace.me/' + kk }, error: null });
        }
        return Promise.resolve({ data: { uploadUrl: 'https://s3.test/put/inv.pdf',
          publicUrl: 'https://mycdn.adspace.me/content/c1/inv-' + Date.now() + '.pdf' }, error: null });
      } },
      auth: {
      getSession: function () { return Promise.resolve({ data: { session: session } }); },
      onAuthStateChange: function (fn) { listener = fn; return { data: {} }; },
      /* Sign-ups are closed on the real project, so an address with no login
         is refused by Supabase in its own words. A client must never read
         those, so the page has to be given one to map. */
      signInWithOtp: function (o) {
        var e = String((o && o.email) || '');
        if (/^nologin/.test(e) && (window.__logins || []).indexOf(e.toLowerCase()) < 0) {
          return Promise.resolve({ error: { message: 'Signups not allowed for this instance' } });
        }
        window.__otp = (window.__otp || []).concat([o]);
        return Promise.resolve({ error: null });
      },
      signOut: function () { session = null; return Promise.resolve({}); }
    } };
  } };
  window.__signIn = function (e) { session = { user: { email: e } }; if (listener) listener('SIGNED_IN', session); };
  // The same door the page uses, so a test can write the way the migration
  // does rather than reaching into the store behind the query builder.
  window.__db = window.supabase.createClient();
})();
