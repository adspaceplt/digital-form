/* WhatsApp (2026-10-09; a section of its own from 2026-10-10,
 * 2026-10-10-whatsapp-section.sql, `wa-send`, `wa-hook`): messages the portal
 * sends through the WhatsApp Business Platform, each with a template Meta
 * approved.
 *
 *   ADspaceWhatsApp.enter()          the section (`?s=whatsapp`): Messages,
 *                                    every message sent with Meta's delivery
 *                                    status; Templates at Full Access, each
 *                                    purpose's template and its switch, and
 *                                    the queue
 *   ADspaceWhatsApp.urlState()       the address while the section is open
 *   ADspaceWhatsApp.compose(o)       the one composer every record shares:
 *                                    o = { purpose: 'message' | 'report' |
 *                                    'feedback' | 'creator' | 'approval',
 *                                    clientId, reportId, creatorId, optionId,
 *                                    campaign, ref, what, link, opener,
 *                                    onSent(d) }
 *   ADspaceWhatsApp.may(purpose)     whether this colleague may send for it:
 *                                    the section and its part at Work, and
 *                                    the record's section at View
 *   ADspaceWhatsApp.on(purpose)      a promise of whether a purpose has a
 *                                    template on (read once a page)
 *   ADspaceWhatsApp.said(e)          a refusal in the team's words
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>';
  var FILE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/></svg>';
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
  var MONTH = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  /* The five purposes a template is set for, and what each message is. */
  var PURPOSE = {
    report: ['Report to client', 'A published report\'s PDF as the header document. Variables: the greeting (salutation and name), the client or brand, the report and its period.'],
    feedback: ['Feedback request', 'Sent from the client\'s record. Variables: the greeting (salutation and name), the client.'],
    reminder: ['Team reminders', 'Each reminder in a colleague\'s bell, to their mobile. Variables: their first name, the title, the message.'],
    creator: ['Creator updates', 'A booking confirmed. Variables: the creator\'s first name, the campaign. Its link button opens the creator\'s own page by their code.'],
    approval: ['Approval reminder', 'Sent from Waiting for you when a set or a draft has waited on the client. Variables: the greeting (salutation and name), the client, what waits, the link to approve it.']
  };
  /* What each message in the list was. */
  var KIND = { report: 'Report', feedback: 'Feedback request', creator: 'Booking', approval: 'Approval reminder', reminder: 'Reminder', message: 'Message' };
  var CATEGORY = { utility: 'Utility', marketing: 'Marketing', authentication: 'Authentication', service: 'Service' };
  var STATUS = [['queued', 'Queued', 'is-off'], ['sending', 'Sending', 'is-warn'], ['sent', 'Sent', 'is-warn'],
                ['delivered', 'Delivered', 'is-ok'], ['read', 'Read', 'is-ok'], ['failed', 'Failed', 'is-danger']];
  /* The part each purpose sends under, and the record's own section. */
  var PART = { report: 'whatsapp.report', feedback: 'whatsapp.feedback', creator: 'whatsapp.booking', approval: 'whatsapp.approval' };
  var RECORD = { report: 'reports', feedback: 'clients', creator: 'campaigns' };
  var SECRET = { WHATSAPP_PHONE_ID: 'Phone number ID', WHATSAPP_TOKEN: 'token', WHATSAPP_WABA_ID: 'Business Account ID' };

  var SAID = {
    denied: 'This needs WhatsApp access.',
    'bad-name': 'Choose a template Meta holds.',
    'bad-lang': 'Choose a template Meta holds.',
    'bad-params': 'A template set for a purpose takes 5 variables at most.',
    'bad-category': 'Choose a template Meta holds.',
    'bad-request': 'Not sent. Try again.',
    'bad-purpose': 'This template is not sent by hand.',
    'wa-off': 'Turn this template on in WhatsApp first.',
    'no-number': 'This contact has no number to message. Add one in Contacts.',
    username: 'A WhatsApp username cannot be messaged. Add the contact\'s number in Contacts.',
    'no-creator-number': 'This creator has no WhatsApp number. Add one on their Creators List record.',
    'not-published': 'Publish the report first.',
    'not-booked': 'Only a booked creator can be sent their booking.',
    'not-found': 'This record is no longer available.',
    'needs-report': 'A template with a Document header sends a report. Choose a report.',
    'wa-params-missing': 'Fill in every variable.',
    'wa-unsupported': 'The portal cannot fill this template\'s header or buttons.',
    'wa-not-set-up': 'WhatsApp needs its Phone number ID, Business Account ID and token in Supabase.',
    'wa-token': 'The WhatsApp token was refused. Check it in Supabase.',
    'wa-template': 'Meta does not hold this template as approved.',
    'wa-params': 'The template takes a different number of variables.',
    'wa-recipient': 'This number is not on WhatsApp.',
    'wa-busy': 'WhatsApp is busy. Try again in a minute.',
    'wa-failed': 'Not sent. Try again.',
    'bad-file': 'The PDF could not be attached.',
    'needs-update': 'This needs a database update.'
  };
  /* Meta's reason a message was not delivered, in the team's words. */
  var REASON = {
    '131026': 'The number is not on WhatsApp, or cannot receive this message.',
    '131030': 'The number is not on WhatsApp, or cannot receive this message.',
    '131049': 'Meta held it back to keep marketing messages to this person within its limits.',
    '131050': 'The person has stopped marketing messages from ADspace.',
    '130472': 'Meta held it back as part of an experiment.',
    '131047': 'The person has not written in the last 24 hours.',
    '131051': 'WhatsApp does not support this message.',
    '131052': 'The PDF could not be attached.',
    '131053': 'The PDF could not be attached.',
    '131021': 'The number is the business number itself.',
    '131031': 'The WhatsApp Business Account is locked.',
    '131042': 'The WhatsApp Business Account has a payment problem.',
    '131045': 'The business number is not registered.',
    '132000': 'The template takes a different number of variables.',
    '132001': 'Meta does not hold this template.',
    '132005': 'The filled in template is too long.',
    '132007': 'The template breaks Meta\'s policy.',
    '132012': 'A variable is in the wrong format.',
    '132015': 'Meta paused this template.',
    '132016': 'Meta disabled this template.',
    '131056': 'Too many messages to this number in a short time.',
    '131048': 'WhatsApp was busy.',
    '130429': 'WhatsApp was busy.',
    '80007': 'WhatsApp was busy.',
    '190': 'The WhatsApp token was refused.',
    '401': 'The WhatsApp token was refused.'
  };

  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function bridge() { return window.ADspaceAdmin || {}; }
  function may(key, level) { var b = bridge(); return Boolean(b.may && b.may(key, level || 'work')); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function said(e) {
    if (!e) return SAID['wa-failed'];
    if (e.code === 'wa-not-set-up' && e.missing && e.missing.length) {
      var words = e.missing.map(function (m) { return SECRET[m] || m; });
      return 'WhatsApp needs its ' + (words.length > 1 ? words.slice(0, -1).join(', ') + ' and ' + words[words.length - 1] : words[0]) + ' in Supabase.';
    }
    if (e.message) return /function|schema cache|does not exist/i.test(e.message) ? SAID['needs-update'] : SAID['wa-failed'];
    if (e.code) return SAID[e.code] || SAID['wa-failed'];
    return SAID[e] || String(e);
  }
  function say(el, text, tone) {
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (text && tone ? ' ' + tone : '');
  }
  function plural(n, word) { return n + ' ' + word + (n === 1 ? '' : 's'); }
  function phone(n) {
    var C = window.ADspaceCard;
    if (!n) return '';
    return C && C.phone ? C.phone(n) : '+' + String(n).replace(/\D/g, '');
  }
  /* A moment as Malaysia reads it: `9 Oct 14:05`. */
  function myt(iso) { var t = Date.parse(iso); return isNaN(t) ? null : new Date(t + 8 * 3600000); }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function whenOf(iso) {
    var d = myt(iso);
    return d ? d.getUTCDate() + ' ' + MON[d.getUTCMonth()] + ' ' + pad(d.getUTCHours()) + ':' + pad(d.getUTCMinutes()) : '';
  }
  function monthNow() {
    var d = new Date(Date.now() + 8 * 3600000);
    return d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-01';
  }
  function rpc(name, args) {
    return db().rpc(name, args || {}).then(function (r) {
      if (r.error) throw r.error;
      var d = r.data || {};
      if (d && d.error) throw { code: d.error };
      return d;
    });
  }
  function invoke(body) {
    return db().functions.invoke('wa-send', { body: body }).then(function (res) {
      var d = res && res.data;
      if (res.error || !d || d.error) throw { code: (d && d.error) || 'wa-failed', missing: d && d.missing };
      return d;
    });
  }

  /* ---- Who may send ------------------------------------------------------- */
  function maySend(purpose) {
    if (!may('whatsapp', 'work')) return false;
    if (purpose === 'message') return may('clients.contacts', 'view') || may('campaigns.creators', 'view');
    /* An approval reminder reads the set or the booking it names. */
    if (purpose === 'approval') return may(PART.approval, 'work') && (may('review.sets', 'view') || may('campaigns.campaigns', 'view'));
    return Boolean(PART[purpose]) && may(PART[purpose], 'work') && may(RECORD[purpose], 'view');
  }

  /* Which purposes have a template on, read once a page. */
  var known = null;
  function read() {
    if (!known) {
      known = db().rpc('wa_templates_read').then(function (r) {
        var d = (r && r.data) || {};
        var on = {};
        (d.templates || []).forEach(function (t) { on[t.purpose] = t.active && Boolean(t.name); });
        return { on: on, list: d.templates || [], error: r.error || d.error || null };
      }).catch(function (e) { return { on: {}, list: [], error: e }; });
    }
    return known;
  }
  function on(purpose) { return read().then(function (k) { return Boolean(k.on[purpose]); }); }

  /* The templates Meta approved, read once a page through `wa-send`; a
     refusal is not kept, so the next open asks again. */
  var meta = null;
  function metaTemplates() {
    if (!meta) {
      meta = invoke({ action: 'templates' }).then(function (d) {
        return { list: (d.templates || []).filter(function (t) { return t.status === 'APPROVED' || !t.status; }) };
      }).catch(function (e) { meta = null; return { list: [], error: e }; });
    }
    return meta;
  }
  function tplKey(t) { return t.name + '|' + t.language; }
  function tplWord(t) {
    return t.name + ' · ' + t.language + (CATEGORY[t.category] ? ' · ' + CATEGORY[t.category] : '');
  }

  /* ======================================================================
     THE SECTION
     ====================================================================== */
  var st = { tab: 'messages', month: monthNow(), data: null, loading: false, wired: false };

  function statusOf(x) {
    var key = x.state === 'queued' ? 'queued' : x.state === 'sending' ? 'sending' : x.state === 'failed' ? 'failed'
      : x.read_at ? 'read' : x.delivered_at ? 'delivered' : x.failed_at ? 'failed' : 'sent';
    return STATUS.filter(function (s) { return s[0] === key; })[0];
  }
  function reasonOf(x) {
    if (/^upload/i.test(String(x.error || ''))) return REASON['131052'];
    var code = x.fail_code || (String(x.error || '').match(/\b(1\d{5}|80007|190|401)\b/) || [])[1];
    return REASON[code] || 'Not delivered.';
  }
  function whoOf(x) {
    var kind = x.to_kind === 'creator' ? 'Creator' : x.to_kind === 'colleague' ? 'Colleague' : '';
    return [kind, x.client].filter(Boolean).join(' · ');
  }

  function wire() {
    if (st.wired) return;
    st.wired = true;
    var sel = $('waMonth');
    var at = new Date(Date.parse(monthNow() + 'T00:00:00Z'));
    var opts = [];
    for (var i = 0; i < 12; i++) {
      var d = new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth() - i, 1));
      opts.push('<option value="' + d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-01">' + MON[d.getUTCMonth()] + ' ' + d.getUTCFullYear() + '</option>');
    }
    sel.innerHTML = opts.join('');
    sel.value = st.month;
    sel.setAttribute('data-default', st.month);
    $('waPurpose').innerHTML = '<option value="">All types</option>' + ['report', 'feedback', 'creator', 'approval', 'reminder', 'message'].map(function (k) {
      return '<option value="' + k + '">' + esc(KIND[k]) + '</option>';
    }).join('');
    $('waStatus').innerHTML = '<option value="">All statuses</option>' + STATUS.map(function (s) {
      return '<option value="' + s[0] + '">' + esc(s[1]) + '</option>';
    }).join('');
    var last = {};
    var repaint = function (el) {
      return function () {
        if (last[el.id] === el.value) return;
        last[el.id] = el.value;
        if (el.id === 'waMonth') { st.month = el.value || monthNow(); load(); return; }
        paintList();
      };
    };
    ['waMonth', 'waPurpose', 'waStatus', 'waFind'].forEach(function (id) {
      var el = $(id);
      last[id] = el.value;
      el.addEventListener('input', repaint(el));
      el.addEventListener('change', repaint(el));
    });
    $('waNew').addEventListener('click', function () { compose({ purpose: 'message', opener: this }); });
    Array.prototype.forEach.call($('waTabs').querySelectorAll('.tab'), function (b) {
      b.addEventListener('click', function () { showTab(b.getAttribute('data-tab'), true); });
    });
    $('waTabs').addEventListener('keydown', function (e) {
      var keys = { ArrowRight: 1, ArrowLeft: -1 };
      if (!keys[e.key]) return;
      var tabs = Array.prototype.filter.call($('waTabs').querySelectorAll('.tab'), function (t) { return !t.hidden; });
      var i = tabs.indexOf(document.activeElement);
      var next = tabs[(i + keys[e.key] + tabs.length) % tabs.length];
      if (next) { e.preventDefault(); showTab(next.getAttribute('data-tab'), true); next.focus(); }
    });
  }

  function enter() {
    wire();
    var q = new URLSearchParams(location.search);
    var full = may('whatsapp', 'manage');
    $('waTabs').hidden = !full;
    $('waNew').hidden = !maySend('message');
    showTab(full && q.get('tab') === 'templates' ? 'templates' : 'messages', false);
    load();
  }
  function showTab(tab, pushed) {
    if (tab === 'templates' && !may('whatsapp', 'manage')) tab = 'messages';
    st.tab = tab;
    Array.prototype.forEach.call($('waTabs').querySelectorAll('.tab'), function (b) {
      var on = b.getAttribute('data-tab') === tab;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    $('waMessagesPane').hidden = tab !== 'messages';
    $('waTemplatesPane').hidden = tab !== 'templates';
    if (pushed && bridge().setUrl) bridge().setUrl();
    if (tab === 'templates') paintTemplates();
    else if (st.data) paintList();
  }

  function load() {
    var box = $('waList'), S = window.ADspaceState;
    if (!st.data && S && S.skeleton) S.skeleton(box, 4);
    var month = st.month;
    st.loading = true;
    rpc('wa_messages', { p_month: month }).then(function (d) {
      if (month !== st.month) return;
      st.loading = false;
      st.data = d;
      paintList();
      if (st.tab === 'templates') paintQueue();
    }).catch(function (e) {
      if (month !== st.month) return;
      st.loading = false;
      st.data = null;
      $('waHeads').hidden = true;
      $('waCount').textContent = '';
      if (S && S.failLine) S.failLine(box, 'The messages', said(e), load);
    });
  }

  function shown() {
    var d = st.data || {};
    var q = String($('waFind').value || '').trim().toLowerCase();
    var digits = q.replace(/[\s+\-()]/g, '');
    var kind = $('waPurpose').value, status = $('waStatus').value;
    return (d.items || []).filter(function (x) {
      if (kind && x.purpose !== kind) return false;
      if (status && statusOf(x)[0] !== status) return false;
      if (!q) return true;
      if (/^\d{3,}$/.test(digits) && String(x.to_number || '').indexOf(digits) > -1) return true;
      return [x.to_name, x.client, x.template, KIND[x.purpose], x.created_by].join(' ').toLowerCase().indexOf(q) > -1;
    });
  }

  function paintHeads() {
    var d = st.data || {}, c = d.counts || {};
    var cells = [['utility', 'Utility'], ['marketing', 'Marketing']];
    if (Number(c.authentication)) cells.push(['authentication', 'Authentication']);
    var box = $('waHeads');
    box.innerHTML = cells.map(function (x) {
      return '<div class="tally-cell wam-head"><b>' + Number(c[x[0]] || 0) + '</b><span>' + esc(x[1]) + ' templates sent</span></div>';
    }).join('');
    box.hidden = false;
  }

  function paintList() {
    var box = $('waList'), S = window.ADspaceState, G = window.ADspaceGroup;
    var d = st.data || {};
    var all = d.items || [];
    var list = shown();
    var filtered = list.length !== all.length;
    paintHeads();
    $('waCount').textContent = !all.length ? '' : filtered ? list.length + ' of ' + all.length : plural(all.length, 'message');
    box.innerHTML = '';
    if (!all.length) {
      S.emptyLine(box, 'No messages.', maySend('message') ? 'New message' : '', function () { compose({ purpose: 'message', opener: $('waNew') }); });
      return;
    }
    if (!list.length) {
      S.emptyLine(box, 'No matches.', 'Clear the filters', function () {
        $('waFind').value = ''; $('waPurpose').value = ''; $('waStatus').value = '';
        ['waFind', 'waPurpose', 'waStatus'].forEach(function (id) { $(id).dispatchEvent(new Event('change', { bubbles: true })); });
        paintList();
      });
      return;
    }
    box.appendChild(G.section({
      route: 'whatsapp', key: 'messages', name: 'Messages', count: list.length,
      shut: false,
      table: function () {
        var table = G.table('wam-row', ['To', 'Template', 'Sent by', 'Status']);
        G.more(table, list, 30, 'messages', rowOf);
        return table;
      }
    }));
  }

  function rowOf(x) {
    var s = statusOf(x);
    var row = document.createElement('div');
    row.className = 'wam-row';
    row.setAttribute('data-id', x.id);
    var why = s[0] === 'failed' ? '<small class="wam-why">' + esc(reasonOf(x)) + '</small>' : '';
    var meta = [whoOf(x), phone(x.to_number)].filter(Boolean).join(' · ');
    row.innerHTML =
      '<span class="wam-to"><b>' + esc(x.to_name || phone(x.to_number)) + '</b>' +
        '<small>' + esc(meta) + '</small>' + why + '</span>' +
      '<span class="wam-tpl"><span>' + esc(KIND[x.purpose] || 'Message') + '</span>' +
        '<small>' + esc([x.template, CATEGORY[x.category]].filter(Boolean).join(' · ')) + '</small>' + why + '</span>' +
      '<span class="wam-by">' + esc(!x.created_by || x.created_by === 'system' ? 'Automatic' : x.created_by) + '</span>' +
      '<span class="wam-state"><span class="chip-state ' + s[2] + '">' + esc(s[1]) + '</span>' +
        '<small class="wam-when">' + esc(whenOf(x.sent_at || x.created_at)) + '</small></span>';
    return row;
  }

  /* ---- Templates and the queue (Full Access) -------------------------------- */
  function paintQueue() {
    var q = ((st.data || {}).queue) || {};
    var box = $('waQueue');
    if (!st.data) { box.hidden = true; return; }
    box.innerHTML = [['queued', 'Waiting to send'], ['sending', 'Sending'], ['failed', 'Not sent in 7 days']].map(function (c) {
      var n = Number(q[c[0]] || 0);
      return '<div class="tally-cell wam-head' + (c[0] === 'failed' && n ? ' is-warn' : '') + '"><b>' + n + '</b><span>' + esc(c[1]) + '</span></div>';
    }).join('');
    box.hidden = false;
  }
  function paintTemplates() {
    var box = $('waTplList'), S = window.ADspaceState, G = window.ADspaceGroup;
    say($('waTplMsg'), '');
    if (st.data) paintQueue(); else { $('waQueue').hidden = true; }
    if (S && S.skeleton) S.skeleton(box, 2);
    known = null;
    Promise.all([read(), metaTemplates()]).then(function (got) {
      var k = got[0], m = got[1];
      if (k.error) { S.failLine(box, 'The templates', said(k.error.message ? k.error : { code: k.error }), paintTemplates); return; }
      if (m.error) say($('waTplMsg'), said(m.error), 'err');
      box.innerHTML = '';
      box.appendChild(G.section({
        route: 'whatsapp', key: 'templates', name: 'Templates', count: k.list.length, shut: false,
        table: function () {
          var table = G.table('wat-row', ['Purpose', 'On', '']);
          k.list.forEach(function (t) { table.appendChild(tplRow(t, m)); });
          return table;
        }
      }));
    });
  }
  function tplRow(t, m) {
    var w = PURPOSE[t.purpose] || [t.purpose, ''];
    var live = t.active && t.name;
    var held = !t.name || m.error || (m.list || []).some(function (x) { return x.name === t.name && x.language === t.lang; });
    var row = document.createElement('div');
    row.className = 'wat-row' + (live ? '' : ' is-off');
    row.setAttribute('data-p', t.purpose);
    row.innerHTML =
      '<span class="wat-name"><b>' + esc(w[0]) + '</b>' +
        '<small>' + esc(t.name ? [t.name, t.lang, CATEGORY[t.category], plural(t.params, 'variable')].filter(Boolean).join(' · ') : 'No template') + '</small>' +
        (held ? '' : '<small class="wam-why">Not among Meta\'s approved templates.</small>') + '</span>' +
      '<span class="wat-on"><button class="switch" type="button" role="switch" aria-checked="' + (live ? 'true' : 'false') + '"' +
        ' aria-label="' + esc(w[0]) + '" data-a="on"></button></span>' +
      '<span class="wat-act"><button class="btn btn-sm" type="button" data-a="edit">' + PEN + 'Edit</button></span>';
    row.querySelector('[data-a="edit"]').addEventListener('click', function () { choose(t, false); });
    row.querySelector('[data-a="on"]').addEventListener('click', function () { flip(t, row, this); });
    return row;
  }
  /* The switch: on or off at the press, put back on a refusal. A purpose
     with no template yet asks for one first, and is turned on with it. */
  function flip(t, row, sw) {
    if (!t.name) { choose(t, true); return; }
    var to = sw.getAttribute('aria-checked') !== 'true';
    sw.setAttribute('aria-checked', to ? 'true' : 'false');
    sw.disabled = true;
    rpc('wa_template_set', { p_purpose: t.purpose, p_name: t.name, p_lang: t.lang, p_params: t.params,
      p_category: t.category || '', p_active: to }).then(function () {
      t.active = to; known = null;
      sw.disabled = false;
      row.classList.toggle('is-off', !to);
      say($('waTplMsg'), 'Saved.', 'ok');
    }).catch(function (e) {
      sw.setAttribute('aria-checked', to ? 'false' : 'true');
      sw.disabled = false;
      say($('waTplMsg'), said(e), 'err');
    });
  }
  /* A purpose's template, chosen from Meta's approved list. */
  function choose(t, turnOn) {
    var w = PURPOSE[t.purpose] || [t.purpose, ''];
    metaTemplates().then(function (m) {
      if (m.error) { say($('waTplMsg'), said(m.error), 'err'); return; }
      var fit = (m.list || []).filter(function (x) { return x.supported; });
      if (!fit.length) { say($('waTplMsg'), 'Meta holds no approved template to choose.', 'err'); return; }
      var byKey = {};
      fit.forEach(function (x) { byKey[tplKey(x)] = x; });
      var now = t.name ? t.name + '|' + t.lang : '';
      window.ADspaceConfirm.ask({
        title: w[0], body: w[1], go: turnOn ? 'Save and turn on' : 'Save',
        fields: [{ name: 'tpl', label: 'Template', required: true, value: byKey[now] ? now : '',
          choices: [['', 'Choose a template']].concat(fit.map(function (x) { return [tplKey(x), tplWord(x)]; })) }],
        check: function (v) {
          var x = byKey[v.tpl];
          if (!x) return 'Choose a template.';
          if (t.purpose === 'report' && x.header !== 'DOCUMENT') return 'The report template needs a Document header.';
          if (t.purpose !== 'report' && x.header === 'DOCUMENT') return 'A template with a Document header sends a report alone.';
          if (x.header_var) return 'The portal cannot fill this template\'s header.';
          if (x.body_vars.length > 5) return SAID['bad-params'];
          if (t.purpose !== 'creator' && x.button_var) return 'Only the creator template takes a link button with a variable.';
          return '';
        }
      }, function (v) {
        var x = byKey[v.tpl];
        if (!x) return;
        rpc('wa_template_set', { p_purpose: t.purpose, p_name: x.name, p_lang: x.language, p_params: x.body_vars.length,
          p_category: CATEGORY[x.category] ? x.category : '', p_active: turnOn || Boolean(t.active) }).then(function (d) {
          known = null;
          say($('waTplMsg'), d.same ? 'No change.' : 'Saved.', 'ok');
          paintTemplates();
        }).catch(function (e) { say($('waTplMsg'), said(e), 'err'); });
      });
    });
  }

  /* ======================================================================
     THE COMPOSER: one sheet every record shares
     ====================================================================== */
  var cx = null;   // { o, recips, byVal, tpls, byKey, reports, sending }

  function compose(o) {
    o = o || {};
    var sheet = $('waCompose');
    if (!sheet) return;
    cx = { o: o, recips: [], byVal: {}, tpls: [], byKey: {}, reports: {}, sending: false };
    say($('waComposeMsg'), '');
    $('waComposeTitle').textContent = o.purpose && o.purpose !== 'message' ? 'Send on WhatsApp' : 'New message';
    $('waTo').innerHTML = '<option value="">Loading…</option>';
    $('waTo').disabled = true;
    $('waTpl').innerHTML = '<option value="">Loading…</option>';
    $('waTpl').disabled = true;
    $('waNumberRow').hidden = true;
    say($('waToNote'), '');
    $('waToNote').hidden = true;
    say($('waTplNote'), '');
    $('waTplNote').hidden = true;
    $('waReportRow').hidden = true;
    $('waFillSec').hidden = true;
    $('waPreviewSec').hidden = true;
    $('waFields').innerHTML = '';
    $('waSend').disabled = false;
    window.ADspaceSheet.show(sheet, { opener: o.opener || null });
    var mine = cx;
    Promise.all([rpc('wa_recipients').catch(function (e) { return { error: e }; }), metaTemplates(), read()]).then(function (got) {
      if (cx !== mine) return;
      fillTo(got[0]);
      fillTemplates(got[1], got[2]);
      pickTo();
    });
  }

  /* A purpose sent to one client's contacts, its main contact first. */
  function forClient(o) { return o.purpose === 'report' || o.purpose === 'feedback' || o.purpose === 'approval'; }
  function fillTo(d) {
    var o = cx.o, sel = $('waTo');
    if (d.error) {
      sel.innerHTML = '<option value="">No recipients</option>';
      say($('waToNote'), said(d.error), 'err');
      $('waToNote').hidden = false;
      return;
    }
    var list = [];
    (d.contacts || []).forEach(function (k) {
      if (forClient(o) && k.client_id !== o.clientId) return;
      if (o.purpose === 'creator') return;
      list.push({ kind: 'contact', id: k.id, name: k.name, client: k.client, client_id: k.client_id, greeting: k.greeting,
        number: k.number, username: k.username, primary: k.is_primary,
        label: k.name + ' · ' + k.client + (k.is_primary ? ' · Main contact' : '') });
    });
    (d.creators || []).forEach(function (k) {
      if (forClient(o)) return;
      if (o.purpose === 'creator' && k.id !== o.creatorId) return;
      list.push({ kind: 'creator', id: k.id, name: k.name, client: '', greeting: k.greeting, number: k.number, code: k.code,
        label: k.name + ' · Creator' });
    });
    cx.recips = list;
    list.forEach(function (r) { cx.byVal[r.kind + ':' + r.id] = r; });
    var first = o.purpose === 'creator' ? list[0]
      : forClient(o) ? (list.filter(function (r) { return r.primary; })[0] || list[0]) : null;
    sel.innerHTML = (first ? '' : '<option value="">Choose a recipient</option>') + list.map(function (r) {
      return '<option value="' + esc(r.kind + ':' + r.id) + '">' + esc(r.label) + '</option>';
    }).join('');
    sel.value = first ? first.kind + ':' + first.id : '';
    sel.disabled = !list.length;
    if (!list.length) {
      sel.innerHTML = '<option value="">No recipients</option>';
      say($('waToNote'), o.purpose === 'creator' ? SAID['no-creator-number'] : 'This client has no contacts. Add one in Contacts.', 'warn');
      $('waToNote').hidden = false;
    }
  }

  function fillTemplates(m, k) {
    var o = cx.o, sel = $('waTpl');
    if (m.error) {
      sel.innerHTML = '<option value="">No templates</option>';
      say($('waTplNote'), said(m.error), 'err');
      $('waTplNote').hidden = false;
      return;
    }
    cx.tpls = (m.list || []).filter(function (t) { return t.supported; });
    cx.tpls.forEach(function (t) { cx.byKey[tplKey(t)] = t; });
    var set = (k.list || []).filter(function (t) { return t.purpose === o.purpose && t.active && t.name; })[0];
    var pre = set && cx.byKey[set.name + '|' + set.lang] ? set.name + '|' + set.lang : '';
    sel.innerHTML = (pre ? '' : '<option value="">Choose a template</option>') + cx.tpls.map(function (t) {
      return '<option value="' + esc(tplKey(t)) + '">' + esc(tplWord(t)) + '</option>';
    }).join('');
    sel.value = pre;
    sel.disabled = !cx.tpls.length;
    if (!cx.tpls.length) {
      sel.innerHTML = '<option value="">No templates</option>';
      say($('waTplNote'), 'Meta holds no approved template the portal can send.', 'warn');
      $('waTplNote').hidden = false;
    }
  }

  function recipient() { return cx && cx.byVal[$('waTo').value] || null; }
  function template() { return cx && cx.byKey[$('waTpl').value] || null; }

  /* The recipient chosen: the number it goes to, or why it cannot. */
  function pickTo() {
    if (!cx) return;
    var r = recipient();
    $('waNumberRow').hidden = !(r && r.number);
    $('waNumber').value = r && r.number ? phone(r.number) : '';
    var why = !r ? '' : r.number ? '' : r.kind === 'creator' ? SAID['no-creator-number'] : r.username ? SAID.username : SAID['no-number'];
    say($('waToNote'), why, 'warn');
    $('waToNote').hidden = !why;
    pickTemplate(true);
  }

  /* The template chosen: its report, its variables prefilled from the
     recipient's record, and the message as it will read. A field already
     typed in keeps what was typed. */
  function pickTemplate(keep) {
    if (!cx) return;
    var t = template(), r = recipient();
    var box = $('waFields');
    var typed = {};
    if (keep) Array.prototype.forEach.call(box.querySelectorAll('[data-var]'), function (f) {
      if (f.getAttribute('data-typed') === '1') typed[f.getAttribute('data-var')] = f.value;
    });
    $('waPreviewSec').hidden = !t;
    if (!t) { box.innerHTML = ''; $('waFillSec').hidden = true; $('waReportRow').hidden = true; return; }
    var isDoc = t.header === 'DOCUMENT';
    $('waReportRow').hidden = !isDoc || !r || r.kind !== 'contact';
    var fields = [];
    if (t.header_var) fields.push(['h:' + t.header_var, 'Header']);
    t.body_vars.forEach(function (v) { fields.push(['b:' + v, /^\d+$/.test(v) ? 'Variable ' + v : human(v)]); });
    if (t.button_var) fields.push(['u:' + t.button_var.name, 'Link button']);
    $('waFillSec').hidden = !fields.length;
    box.innerHTML = fields.map(function (f, i) {
      return '<div class="row"><div><label class="field-label" for="waVar' + i + '">' + esc(f[1]) + '</label>' +
        '<textarea class="input" id="waVar' + i + '" rows="1" data-oneline data-nodraft aria-required="true" data-var="' + esc(f[0]) + '"></textarea></div></div>';
    }).join('');
    Array.prototype.forEach.call(box.querySelectorAll('[data-var]'), function (f) {
      var key = f.getAttribute('data-var');
      if (Object.prototype.hasOwnProperty.call(typed, key)) { f.value = typed[key]; f.setAttribute('data-typed', '1'); }
      else f.value = prefill(key, t, r);
      f.addEventListener('input', function () { f.setAttribute('data-typed', '1'); preview(); });
    });
    if (isDoc && r && r.kind === 'contact') loadReports(r.client_id);
    else preview();
  }
  /* The approval reminder's own client: what waits and its link fill in. */
  function approving(r) { return Boolean(cx && cx.o.purpose === 'approval' && r && r.kind === 'contact' && r.client_id === cx.o.clientId); }
  function human(v) { var s = String(v).replace(/_/g, ' ').trim(); return s.charAt(0).toUpperCase() + s.slice(1); }
  /* What a variable is filled with, from what the record holds: the
     greeting first, then the client (a creator's campaign), then a report's
     title; a named variable by its name. */
  function prefill(key, t, r) {
    if (!r) return '';
    var o = cx.o, kind = key.charAt(0), v = key.slice(2), low = v.toLowerCase();
    var rep = reportWord();
    if (kind === 'u') return r.kind === 'creator' ? (r.code || '') : '';
    if (kind === 'h') return '';
    if (/^\d+$/.test(v)) {
      if (v === '1') return r.greeting || r.name || '';
      if (v === '2') return r.kind === 'creator' ? (o.campaign || '') : (rep ? rep.client : r.client) || '';
      if (v === '3') return rep ? rep.title : approving(r) ? (o.what || '') : '';
      if (v === '4') return approving(r) ? (o.link || '') : '';
      return '';
    }
    if (approving(r) && /link|url|approve/.test(low)) return o.link || '';
    if (approving(r) && /what|item|waiting|set|draft|content/.test(low)) return o.what || '';
    if (/campaign|job|booking/.test(low)) return r.kind === 'creator' ? (o.campaign || '') : '';
    if (/report|period|month/.test(low)) return rep ? rep.title : '';
    if (/client|brand|company|business/.test(low)) return r.kind === 'contact' ? ((rep ? rep.client : r.client) || '') : '';
    if (/name|greet|salut|contact|recipient|creator/.test(low)) return r.greeting || r.name || '';
    return '';
  }

  /* A published report of the recipient's client, newest first. */
  function loadReports(clientId) {
    var sel = $('waReport');
    if (cx.reports[clientId]) { fillReports(clientId); return; }
    sel.innerHTML = '<option value="">Loading…</option>';
    sel.disabled = true;
    var mine = cx;
    db().from('sm_reports').select('id, client_id, kind, title, period_start, period_end, brand_id, brand_name, status, sent_on')
      .eq('client_id', clientId).eq('status', 'published').order('period_end', { ascending: false }).then(function (r) {
        if (cx !== mine) return;
        cx.reports[clientId] = r.error ? { error: r.error } : { list: r.data || [] };
        fillReports(clientId);
      });
  }
  function reportTitle(r) {
    var SM = window.ADspaceSmReport;
    var title = SM && SM.titleOf ? SM.titleOf(r) : (r.title || 'Report');
    var when = SM && SM.periodWord ? SM.periodWord(r.period_start, r.period_end) : '';
    return title + (when ? ', ' + when : '');
  }
  function fillReports(clientId) {
    var sel = $('waReport'), got = cx.reports[clientId] || {};
    if (got.error) {
      sel.innerHTML = '<option value="">No reports</option>';
      sel.disabled = true;
      say($('waTplNote'), 'The reports could not be read.', 'err');
      $('waTplNote').hidden = false;
      preview();
      return;
    }
    var list = got.list || [];
    sel.innerHTML = list.length ? list.map(function (r) {
      return '<option value="' + esc(r.id) + '">' + esc(reportTitle(r)) + '</option>';
    }).join('') : '<option value="">No published reports</option>';
    sel.disabled = !list.length;
    var want = cx.o.reportId && list.some(function (r) { return r.id === cx.o.reportId; }) ? cx.o.reportId : (list[0] && list[0].id) || '';
    sel.value = want;
    refill();
  }
  function reportWord() {
    var r = recipient(), t = template();
    if (!cx || !r || r.kind !== 'contact' || !t || t.header !== 'DOCUMENT') return null;
    var got = cx.reports[r.client_id] || {};
    var rep = (got.list || []).filter(function (x) { return x.id === $('waReport').value; })[0];
    if (!rep) return null;
    return { id: rep.id, row: rep, title: reportTitle(rep), client: rep.brand_id && rep.brand_name ? rep.brand_name : r.client };
  }
  /* A report changed: the variables nobody typed follow it. */
  function refill() {
    var t = template(), r = recipient();
    Array.prototype.forEach.call($('waFields').querySelectorAll('[data-var]'), function (f) {
      if (f.getAttribute('data-typed') !== '1') f.value = prefill(f.getAttribute('data-var'), t, r);
    });
    preview();
  }

  function valueOf(key) {
    var f = $('waFields').querySelector('[data-var="' + key + '"]');
    return f ? String(f.value || '').trim() : '';
  }
  /* The message as it will read: the header, the body with each variable
     in its place, the footer and the buttons. */
  function preview() {
    var t = template(), box = $('waPreview');
    if (!t) { box.innerHTML = ''; return; }
    var fill = function (text, kind) {
      return esc(text).replace(/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g, function (m, v) {
        var got = valueOf(kind + ':' + v);
        return got ? '<b class="wa-fill">' + esc(got) + '</b>' : '<span class="wa-gap">' + esc(m) + '</span>';
      });
    };
    var rep = reportWord();
    var head = t.header === 'DOCUMENT'
      ? '<p class="wa-doc">' + FILE + '<span>' + esc(rep ? reportTitle(rep.row) : 'No report chosen') + '</span></p>'
      : t.header === 'TEXT' ? '<p class="wa-head">' + fill(t.header_text, 'h') + '</p>' : '';
    var buttons = (t.buttons || []).map(function (b, i) {
      var url = t.button_var && t.button_var.index === i ? fill(b.url || '', 'u') : esc(b.url || '');
      return '<li><span>' + esc(b.text) + '</span>' + (url ? '<small>' + url + '</small>' : '') + '</li>';
    }).join('');
    box.innerHTML = head + '<p class="wa-body">' + fill(t.body, 'b') + '</p>' +
      (t.footer ? '<p class="wa-foot">' + esc(t.footer) + '</p>' : '') +
      (buttons ? '<ul class="wa-btns">' + buttons + '</ul>' : '');
  }

  function toB64(blob) {
    return new Promise(function (ok, bad) {
      var fr = new FileReader();
      fr.onload = function () { ok(String(fr.result).replace(/^data:[^,]*,/, '')); };
      fr.onerror = function () { bad({ code: 'bad-file' }); };
      fr.readAsDataURL(blob);
    });
  }

  /* Send: what is missing is named, then asked first, naming who receives
     it and what Meta charges it as. */
  function send() {
    if (!cx || cx.sending) return;
    var o = cx.o, r = recipient(), t = template(), m = $('waComposeMsg');
    if (!r) { say(m, 'Choose a recipient.', 'err'); return; }
    if (!r.number) { say(m, r.kind === 'creator' ? SAID['no-creator-number'] : r.username ? SAID.username : SAID['no-number'], 'err'); return; }
    if (!t) { say(m, 'Choose a template.', 'err'); return; }
    var isDoc = t.header === 'DOCUMENT';
    var rep = reportWord();
    if (isDoc && r.kind !== 'contact') { say(m, 'A template with a Document header sends a report to a client contact.', 'err'); return; }
    if (isDoc && !rep) { say(m, 'Choose a report.', 'err'); return; }
    var empty = Array.prototype.filter.call($('waFields').querySelectorAll('[data-var]'), function (f) { return !String(f.value || '').trim(); })[0];
    if (empty) {
      var lab = $('waFields').querySelector('label[for="' + empty.id + '"]');
      say(m, 'Fill in ' + (lab ? lab.textContent : 'every variable') + '.', 'err');
      empty.focus();
      return;
    }
    var purpose = isDoc ? 'report' : (o.purpose === 'feedback' || approving(r) || (o.purpose === 'creator' && r.kind === 'creator' && r.id === o.creatorId)) ? o.purpose : 'message';
    if (!maySend(purpose)) { say(m, SAID.denied, 'err'); return; }
    var ref = purpose === 'report' ? rep.id : purpose === 'creator' ? o.optionId : purpose === 'approval' ? o.ref : null;
    var values = {}, header = '', button = '';
    Array.prototype.forEach.call($('waFields').querySelectorAll('[data-var]'), function (f) {
      var key = f.getAttribute('data-var'), v = String(f.value || '').trim();
      if (key.charAt(0) === 'b') values[key.slice(2)] = v;
      else if (key.charAt(0) === 'h') header = v;
      else button = v;
    });
    var cat = CATEGORY[t.category] || 'template';
    window.ADspaceConfirm.ask({
      title: 'Send on WhatsApp?', go: 'Send',
      body: 'The message goes to ' + r.name + (r.kind === 'contact' && r.client ? ' of ' + r.client : '') + ' on ' + phone(r.number) +
        '. Meta charges it as a ' + cat + ' message.'
    }, function () {
      cx.sending = true;
      $('waSend').disabled = true;
      say(m, isDoc ? 'Attaching the report…' : 'Sending…');
      var mine = cx;
      var pdf = isDoc
        ? (window.ADspaceReports && window.ADspaceReports.keptPdf
          ? window.ADspaceReports.keptPdf(rep.id) : Promise.reject({ code: 'bad-file' }))
          .then(function (f) { return toB64(f.blob).then(function (b) { return { b64: b, name: f.name }; }); })
        : Promise.resolve(null);
      pdf.then(function (file) {
        if (file) say(m, 'Sending…');
        return invoke({ action: 'compose', to_kind: r.kind, to_id: r.id, purpose: purpose, ref: ref,
          template: { name: t.name, language: t.language }, values: values, header_value: header, button_value: button,
          pdf: file ? file.b64 : undefined, filename: file ? file.name : undefined });
      }).then(function (d) {
        if (cx !== mine) return;
        cx.sending = false;
        var line = 'Sent on WhatsApp to ' + (d.to || r.name) + '.';
        var done = { to: d.to || r.name, purpose: purpose, reportId: purpose === 'report' ? rep.id : null };
        window.ADspaceSheet.close();
        if (o.onSent) o.onSent(done, line);
        else say($('waListMsg'), line, 'ok');
        if ($('sectionWhatsApp') && !$('sectionWhatsApp').hidden) load();
      }).catch(function (e) {
        if (cx !== mine) return;
        cx.sending = false;
        $('waSend').disabled = false;
        /* A refusal the function named, else the report's file that could
           not be read. */
        say(m, said(e && e.code && !e.message ? e : { code: 'bad-file' }), 'err');
      });
    });
  }

  function wireComposer() {
    if (!$('waCompose') || $('waCompose').__wired) return;
    $('waCompose').__wired = true;
    $('waTo').addEventListener('change', pickTo);
    $('waTpl').addEventListener('change', function () { pickTemplate(false); });
    $('waReport').addEventListener('change', refill);
    $('waSend').addEventListener('click', send);
    $('waComposeCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('waComposeClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wireComposer);
  else wireComposer();

  /* Settings' WhatsApp card (2026-10-10) opens the section's Templates:
     one copy of the templates, where WhatsApp is worked. */
  function manage() {
    history.pushState(null, '', '/admin/?s=whatsapp&tab=templates');
    if (bridge().show) bridge().show('whatsapp');
  }

  window.ADspaceWhatsApp = {
    enter: enter,
    manage: manage,
    urlState: function () { return { tab: st.tab === 'templates' ? 'templates' : '' }; },
    compose: function (o) { wireComposer(); compose(o); },
    may: maySend,
    on: on,
    said: said
  };
})();
