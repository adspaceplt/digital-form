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
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>';
  var FILE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/></svg>';
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

  /* The purposes a template is set for, and what each message is. */
  var PURPOSE = {
    report: ['Report to client', 'A published report\'s PDF as the header document. Variables: the greeting (salutation and name), the client or brand, the report and its period.'],
    feedback: ['Feedback request', 'Sent from the client\'s record. Variables: the greeting (salutation and name), the client.'],
    reminder: ['Team reminders', 'Each reminder in a colleague\'s bell, to their mobile. Variables: their first name, the title, the message.'],
    creator: ['Creator updates', 'A booking confirmed. Variables: the creator\'s first name, the campaign. Its link button opens the creator\'s own page by their code.'],
    approval: ['Approval reminder', 'Sent from Waiting for you when a set or a draft has waited on the client. Variables: the greeting (salutation and name), the client, what waits. Its link button (https://digital.adspace.me/{{1}}) opens the page to approve it.'],
    quotation: ['Quotation to client', 'Sent from a quotation\'s ⋯ on the client\'s Services, its PDF as the header document. Variables: the greeting (salutation and name), the client, the quotation\'s reference.'],
    offer: ['Letter of Offer to client', 'Sent from a Letter of Offer\'s ⋯ on the client\'s Documents, its PDF as the header document. Variables: the greeting (salutation and name), the client, the letter\'s reference.'],
    quote_ready: ['Quotation ready', 'Sent by the portal when a colleague sends a website quotation (Send quotation), to the prospect\'s WhatsApp. Variables: the greeting (salutation and name), the brand, the quotation\'s reference. Its link button (https://digital.adspace.me/quote/?q={{1}}) opens the quotation.']
  };
  /* A purpose whose message carries a record's PDF as its Document header. */
  var DOC = { report: 1, quotation: 1, offer: 1 };
  /* What each message in the list was. */
  /* A link button's variable is filled from the record alone: a creator's
     code, or the approval link (wa-send takes it from the database, never
     from the page; the third audit, item 2). Only a purpose the portal
     sends by itself with nothing to put there refuses one (the user,
     2026-10-10: not a list of the purposes allowed). */
  var NO_BUTTON = { reminder: 'Team reminders are sent by the portal itself, which cannot fill a link button.' };
  var KIND = { report: 'Report', feedback: 'Feedback request', creator: 'Booking', approval: 'Approval reminder', reminder: 'Reminder',
    quotation: 'Quotation', offer: 'Letter of Offer', quote_ready: 'Quotation ready', message: 'Message' };
  var CATEGORY = { utility: 'Utility', marketing: 'Marketing', authentication: 'Authentication', service: 'Service' };
  var STATUS = [['queued', 'Queued', 'is-off'], ['sending', 'Sending', 'is-warn'], ['sent', 'Sent', 'is-warn'],
                ['delivered', 'Delivered', 'is-ok'], ['read', 'Read', 'is-ok'], ['unknown', 'Not confirmed', 'is-warn'],
                ['failed', 'Failed', 'is-danger']];
  /* The part each purpose sends under, and the record's own section. */
  var PART = { report: 'whatsapp.report', feedback: 'whatsapp.feedback', creator: 'whatsapp.booking', approval: 'whatsapp.approval',
    quotation: 'whatsapp.documents', offer: 'whatsapp.documents' };
  var RECORD = { report: 'reports', feedback: 'clients', creator: 'campaigns', quotation: 'clients.quotes', offer: 'clients.documents' };
  var SECRET = { WHATSAPP_PHONE_ID: 'Phone number ID', WHATSAPP_TOKEN: 'token', WHATSAPP_WABA_ID: 'Business Account ID' };

  var SAID = {
    denied: 'You do not have permission to do this in WhatsApp. Please ask an admin.',
    'bad-name': 'Choose a template approved by Meta.',
    'bad-lang': 'Choose a template approved by Meta.',
    'bad-params': 'A template set for a purpose takes 5 variables at most.',
    'bad-category': 'Choose a template approved by Meta.',
    'bad-request': 'Not sent. Try again.',
    'bad-purpose': 'This template is not sent by hand.',
    'wa-off': 'Turn this template on in WhatsApp first.',
    'no-number': 'This contact has no number to message. Add one in Contacts.',
    username: 'A WhatsApp username cannot be messaged. Add the contact\'s number in Contacts.',
    'no-creator-number': 'This creator has no WhatsApp number. Add one on their Creators List record.',
    'not-published': 'Publish the report first.',
    'not-booked': 'Only a booked creator can be sent their booking.',
    'not-found': 'This record is no longer available.',
    'not-client': 'Feedback is asked of a client, never a lead.',
    void: 'This letter is void.',
    'needs-report': 'A template with a Document header sends a report. Choose a report.',
    'wa-params-missing': 'Fill in every variable.',
    'wa-unsupported': 'The portal cannot fill this template\'s header or buttons.',
    'wa-no-link': 'This template\'s link button has no page for this recipient. Choose another template.',
    'wa-button-address': 'This template\'s link button address holds {{1}} typed as text. Correct it in WhatsApp Manager, then choose it again here.',
    'wa-not-set-up': 'WhatsApp is not set up yet. Please contact an admin.',
    'wa-token': 'WhatsApp is not available at the moment. Please contact an admin.',
    'wa-template': 'Meta does not hold this template as approved.',
    'wa-params': 'The template takes a different number of variables.',
    'wa-recipient': 'This number is not on WhatsApp.',
    'wa-busy': 'WhatsApp is busy. Try again in a minute.',
    'wa-failed': 'Not sent. Try again.',
    'wa-unknown': 'WhatsApp did not confirm the send. Check the chat before sending again.',
    sending: 'This message is being sent now. Check the messages list before sending it again.',
    'bad-file': 'The PDF could not be attached.',
    'needs-update': 'This feature is not available yet. Please contact an admin.'
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
  function esc(s) { return window.ADspaceWords.esc(s); }
  function said(e) {
    if (!e) return SAID['wa-failed'];
    if (e.code === 'wa-not-set-up' && e.missing && e.missing.length) {
      var words = e.missing.map(function (m) { return SECRET[m] || m; });
      return 'WhatsApp is not set up yet. Please contact an admin.';
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
  /* A moment as Malaysia reads it, from Malaysia's clock as the rest of
     the console reads one: `9 Oct, 2:05pm` (2026-10-22, WA-2). */
  var CK = window.ADspaceClock;
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function whenOf(iso) {
    if (!iso || !CK.parts(iso)) return '';
    return CK.date(iso, { year: false }) + ', ' + CK.clock(iso);
  }
  function monthNow() { return CK.today().slice(0, 7) + '-01'; }
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
      if (res.error || !d || d.error) throw { code: (d && d.error) || 'wa-failed', missing: d && d.missing, recent: d && d.recent };
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
  /* A link button whose fixed part holds a variable typed by hand: Meta
     stores the typed {{1}} as text (`/%7B%7B1%7D%7D{{1}}`), so no page
     address starts with it and the button can never be filled
     (2026-10-22, the approval reminder). */
  function badButton(x) {
    return Boolean(x && x.button_var && /%7B|%7D|[{}]/i.test(String(x.button_var.url || '').split('{{')[0]));
  }
  function tplWord(t) {
    return t.name + ' · ' + t.language + (CATEGORY[t.category] ? ' · ' + CATEGORY[t.category] : '');
  }

  /* ======================================================================
     THE SECTION
     ====================================================================== */
  var st = { month: monthNow(), data: null, loading: false, wired: false };

  function statusOf(x) {
    var key = x.state === 'queued' ? 'queued' : x.state === 'sending' ? 'sending' : x.state === 'failed' ? 'failed'
      : x.state === 'unknown' ? 'unknown'
      : x.read_at ? 'read' : x.delivered_at ? 'delivered' : x.failed_at ? 'failed' : 'sent';
    return STATUS.filter(function (s) { return s[0] === key; })[0];
  }
  function reasonOf(x) {
    if (/^upload/i.test(String(x.error || ''))) return REASON['131052'];
    /* Failed by the queue itself after 48 hours (wa_expire, 2026-10-18). */
    if (/^expired/i.test(String(x.error || ''))) return 'Not sent within 48 hours. Send it again if it is still needed.';
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
  }

  /* The section is the messages alone; each purpose's template is chosen
     in Settings, Templates (2026-10-29, the user: every template in one
     place). An address from before (`tab=templates`) reads the messages. */
  function enter() {
    wire();
    $('waNew').hidden = !maySend('message');
    if (st.data) paintList();
    load();
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
      paintQueue();
    }).catch(function (e) {
      if (month !== st.month) return;
      st.loading = false;
      st.data = null;
      $('waHeads').hidden = true;
      $('waQueue').hidden = true;
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
      /* New message is the bar's; the line offers it no second time
         (2026-10-27, WA-8). */
      S.emptyLine(box, 'No messages.');
      return;
    }
    if (!list.length) {
      S.emptyLine(box, 'No matches.', 'Clear filters', function () {
        $('waFind').value = ''; $('waPurpose').value = ''; $('waStatus').value = '';
        ['waFind', 'waPurpose', 'waStatus'].forEach(function (id) { $(id).dispatchEvent(new Event('change', { bubbles: true })); });
        paintList();
      });
      return;
    }
    /* One month is always chosen in the bar, so the messages are one table
       under the heads, never a card naming the month again (2026-10-22,
       WA-3). */
    var table = G.table('wam-row', ['To', 'Template', 'Sent by', 'Status']);
    G.more(table, list, 30, 'messages', rowOf);
    box.appendChild(table);
  }

  function rowOf(x) {
    var s = statusOf(x);
    var row = document.createElement('div');
    row.className = 'wam-row';
    row.setAttribute('data-id', x.id);
    /* A failed message leads to its recipient, where the number is put
       right before it is sent again (2026-10-27, WA-10). */
    var to = s[0] !== 'failed' ? ''
      : x.to_kind === 'creator' && may('campaigns.creators', 'view') ? 'creator'
      : x.to_kind === 'contact' && x.client_id && may('clients.contacts', 'view') ? 'contact' : '';
    var open = to ? ' <button class="linkbtn wam-open" type="button" data-open="' + to + '">' + (to === 'creator' ? 'Open creator' : 'Open contacts') +
      '<svg class="ovgo-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg></button>' : '';
    var why = s[0] === 'failed' ? '<small class="wam-why">' + esc(reasonOf(x)) + open + '</small>'
      : s[0] === 'unknown' ? '<small class="wam-why is-unknown">' + esc(SAID['wa-unknown']) + '</small>' : '';
    /* A line of parts, each held whole; on a phone what was sent leads it
       and the number, last, leaves first where the line runs out
       (2026-10-22, WA-4). */
    var parts = function (list) {
      return list.filter(Boolean).map(function (w, i) {
        return i ? '<wbr><span class="wam-part"><span class="wam-sep"> · </span>' + esc(w) + '</span>' : '<span class="wam-part">' + esc(w) + '</span>';
      }).join('');
    };
    row.innerHTML =
      '<span class="wam-to"><b>' + esc(x.to_name || phone(x.to_number)) + '</b>' +
        '<small class="wam-parts">' + parts([KIND[x.purpose] || 'Message', whoOf(x), phone(x.to_number)]) + '</small>' + why + '</span>' +
      '<span class="wam-tpl"><span>' + esc(KIND[x.purpose] || 'Message') + '</span>' +
        /* The template's name gives way; its category reads whole (WA-3). */
        '<small class="wam-tplline' + (CATEGORY[x.category] ? ' is-' + x.category : '') + '">' + (x.template ? '<span class="wam-tplname">' + esc(x.template) + '</span>' : '') +
          (CATEGORY[x.category] ? '<span class="wam-cat">' + (x.template ? '<span class="wam-sep"> · </span>' : '') + esc(CATEGORY[x.category]) + '</span>' : '') + '</small>' + why + '</span>' +
      '<span class="wam-by">' + esc(!x.created_by || x.created_by === 'system' ? 'Automatic' : x.created_by) + '</span>' +
      '<span class="wam-state"><span class="chip-state ' + s[2] + '">' + esc(s[1]) + '</span>' +
        '<small class="wam-when">' + esc(whenOf(x.sent_at || x.created_at)) + '</small></span>';
    Array.prototype.forEach.call(row.querySelectorAll('[data-open]'), function (b) {
      b.addEventListener('click', function () {
        var br = bridge();
        if (b.getAttribute('data-open') === 'creator') {
          history.replaceState(null, '', '/admin/?s=campaigns&tab=roster');
          if (br.show) br.show('campaigns');
          var f = $('rosterSearch');
          if (f) { f.value = x.to_name || ''; f.dispatchEvent(new Event('input', { bubbles: true })); }
          return;
        }
        history.replaceState(null, '', '/admin/?client=' + encodeURIComponent(x.client_id) + '&tab=account');
        if (br.show) br.show('clients');
      });
    });
    return row;
  }

  /* ---- The queue, over the messages at Full Access ------------------------- */
  function paintQueue() {
    var q = ((st.data || {}).queue) || {};
    var box = $('waQueue');
    if (!st.data || !may('whatsapp', 'manage')) { box.hidden = true; return; }
    /* Not confirmed (sent in the last seven days, as Not sent counts, and
       labelled so, the days kept on one line; 2026-10-18) beside Not sent (2026-10-17): either wants a
       colleague to look, the first before anything is sent again. */
    box.innerHTML = [['queued', 'Waiting to send'], ['sending', 'Sending'], ['failed', 'Not sent in\u00a07\u00a0days'],
                     ['unknown', 'Not confirmed in\u00a07\u00a0days']].map(function (c) {
      var n = Number(q[c[0]] || 0);
      return '<div class="tally-cell wam-head' + ((c[0] === 'failed' || c[0] === 'unknown') && n ? ' is-warn' : '') + '"><b>' + n + '</b><span>' + esc(c[1]) + '</span></div>';
    }).join('');
    box.hidden = false;
  }
  /* ---- Templates (Settings, Templates; Full Access) ------------------------- */
  function paintTemplates() {
    var box = $('waTplList'), S = window.ADspaceState, G = window.ADspaceGroup;
    say($('waTplMsg'), '');
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
    var mine = t.name && (m.list || []).filter(function (x) { return x.name === t.name && x.language === t.lang; })[0];
    var held = !t.name || m.error || Boolean(mine);
    var why = !held ? 'Not among Meta\'s approved templates.' : badButton(mine) ? SAID['wa-button-address'] : '';
    var row = document.createElement('div');
    row.className = 'wat-row' + (live ? '' : ' is-off');
    row.setAttribute('data-p', t.purpose);
    row.innerHTML =
      '<span class="wat-name"><b>' + esc(w[0]) + '</b>' +
        /* A line of parts wraps between its parts, never inside one
           (ux-audit WA-2, 2026-10-14). */
        '<small>' + (t.name ? [t.name, t.lang, CATEGORY[t.category], plural(t.params, 'variable')].filter(Boolean)
          .map(function (x) { return '<span class="wat-part">' + esc(x) + '</span>'; }).join(' · ') : 'No template') + '</small>' +
        (why ? '<small class="wam-why">' + esc(why) + '</small>' : '') + '</span>' +
      '<span class="wat-on"><button class="switch" type="button" role="switch" aria-checked="' + (live ? 'true' : 'false') + '"' +
        ' aria-label="' + esc(w[0]) + '" data-a="on"></button></span>' +
      /* On a phone the pen alone, beside the switch on the name's line
         (2026-10-10: the word put Edit on a line of its own). */
      '<span class="wat-act"><button class="btn btn-sm" type="button" data-a="edit" aria-label="Edit ' + esc(w[0]) + '">' + PEN + '<span class="wat-word">Edit</span></button></span>';
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
      /* Only templates this purpose can take are offered (2026-10-20,
         WA-2): the refusals below stay for a template that changed at Meta. */
      var fit = (m.list || []).filter(function (x) {
        return x.supported && (DOC[t.purpose] ? x.header === 'DOCUMENT' : x.header !== 'DOCUMENT') &&
          !x.header_var && x.body_vars.length <= 5 && !(x.button_var && NO_BUTTON[t.purpose]) && !badButton(x);
      });
      if (!fit.length) { say($('waTplMsg'), 'Meta has no approved template to choose.', 'err'); return; }
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
          if (DOC[t.purpose] && x.header !== 'DOCUMENT') return 'This template needs a Document header for the PDF.';
          if (!DOC[t.purpose] && x.header === 'DOCUMENT') return 'A template with a Document header sends a report, a quotation or a Letter of Offer.';
          if (x.header_var) return 'The portal cannot fill this template\'s header.';
          if (x.body_vars.length > 5) return SAID['bad-params'];
          if (x.button_var && NO_BUTTON[t.purpose]) return NO_BUTTON[t.purpose];
          if (badButton(x)) return SAID['wa-button-address'];
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
  function forClient(o) { return o.purpose === 'report' || o.purpose === 'feedback' || o.purpose === 'approval' || Boolean(o.doc); }
  function fillTo(d) {
    var o = cx.o, sel = $('waTo');
    if (d.error) {
      sel.innerHTML = '<option value="">No recipients</option>';
      say($('waToNote'), said(d.error), 'err');
      $('waToNote').hidden = false;
      return;
    }
    var list = [], narrow = window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
    (d.contacts || []).forEach(function (k) {
      if (forClient(o) && k.client_id !== o.clientId) return;
      if (o.purpose === 'creator') return;
      list.push({ kind: 'contact', id: k.id, name: k.name, client: k.client, client_id: k.client_id, greeting: k.greeting,
        number: k.number, username: k.username, primary: k.is_primary,
        /* On a phone the label keeps what tells two apart, Main contact
           left to the number shown under it (2026-10-20, WA-3). */
        label: k.name + ' · ' + k.client + (k.is_primary && !narrow ? ' · Primary contact' : '') });
    });
    (d.creators || []).forEach(function (k) {
      if (forClient(o)) return;
      if (o.purpose === 'creator' && k.id !== o.creatorId) return;
      list.push({ kind: 'creator', id: k.id, name: k.name, client: '', greeting: k.greeting, number: k.number, code: k.code,
        label: k.name + ' · Creator' });
    });
    /* Two recipients read alike are told apart by their number's last four
       (ux-audit WA-3, 2026-10-14). */
    var seen = {};
    list.forEach(function (r) { seen[r.label] = (seen[r.label] || 0) + 1; });
    list.forEach(function (r) {
      if (seen[r.label] > 1 && r.number) r.label += ' · ' + String(r.number).slice(-4);
      /* One who cannot be messaged is listed last and says so (2026-10-22,
         WA-5). */
      if (!r.number) r.label += ' · No number';
    });
    list = list.filter(function (r) { return r.number; }).concat(list.filter(function (r) { return !r.number; }));
    cx.recips = list;
    list.forEach(function (r) { cx.byVal[r.kind + ':' + r.id] = r; });
    /* Opened from a contact's ⋯ (2026-10-31): that contact chosen. */
    var first = o.contactId ? (list.filter(function (r) { return r.kind === 'contact' && r.id === o.contactId; })[0] || null)
      : o.purpose === 'creator' ? list[0]
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
      say($('waTplNote'), 'Meta has no approved template the portal can send.', 'warn');
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
    /* The way to add the number, where the colleague reads the client's
       Contacts: the client's Account tab, the sheet shut (WA-5). */
    if (why && r.kind === 'contact' && r.client_id && may('clients.contacts', 'view')) {
      var go = document.createElement('button');
      go.type = 'button'; go.className = 'btn btn-sm btn-quiet ovgo wa-tocontacts';
      go.innerHTML = 'Open contacts<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
      go.addEventListener('click', function () {
        window.ADspaceSheet.close();
        history.replaceState(null, '', '/admin/?client=' + encodeURIComponent(r.client_id) + '&tab=account');
        var b = bridge();
        if (b.show) b.show('clients');
      });
      $('waToNote').appendChild(document.createTextNode(' '));
      $('waToNote').appendChild(go);
    }
    $('waToNote').hidden = !why;
    /* Send rests while the line above says why (ux-audit WA-8, 2026-10-14). */
    $('waSend').disabled = Boolean(why);
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
    /* A template whose button can never be filled says so as it is chosen,
       and Send rests (2026-10-22). */
    var note = $('waTplNote');
    if (badButton(t)) { say(note, SAID['wa-button-address'], 'warn'); note.hidden = false; note.setAttribute('data-btn', '1'); }
    else if (note.getAttribute('data-btn')) { say(note, ''); note.hidden = true; note.removeAttribute('data-btn'); }
    if (!cx.sending) $('waSend').disabled = badButton(t) || Boolean(r && !r.number);
    if (!t) { box.innerHTML = ''; $('waFillSec').hidden = true; $('waReportRow').hidden = true; return; }
    var isDoc = t.header === 'DOCUMENT';
    $('waReportRow').hidden = !isDoc || !r || r.kind !== 'contact';
    /* A quotation or a letter the composer was opened on is the one
       document: a fact read, never a select of one. */
    var given = cx.o.doc;
    $('waReportLabel').textContent = given ? KIND[cx.o.purpose] : 'Report';
    $('waReport').hidden = Boolean(given);
    $('waDocOne').hidden = !given;
    $('waDocOne').value = given ? given.title : '';
    $('waReportLabel').classList.toggle('is-req', !given);
    var fields = [];
    if (t.header_var) fields.push(['h:' + t.header_var, 'Header']);
    t.body_vars.forEach(function (v) { fields.push(['b:' + v, /^\d+$/.test(v) ? numbered(v, t, r) : human(v)]); });
    if (t.button_var) fields.push(['u:' + t.button_var.name, 'Link button']);
    $('waFillSec').hidden = !fields.length;
    /* The link button is the record's: shown, never typed. */
    box.innerHTML = fields.map(function (f, i) {
      return '<div class="row"><div><label class="field-label" for="waVar' + i + '">' + esc(f[1]) + '</label>' +
        (f[0].charAt(0) === 'u'
          ? '<input class="input readfield" id="waVar' + i + '" readonly data-nodraft data-var="' + esc(f[0]) + '">'
          : '<textarea class="input" id="waVar' + i + '" rows="1" data-oneline data-nodraft aria-required="true" data-var="' + esc(f[0]) + '"></textarea>') +
        '</div></div>';
    }).join('');
    Array.prototype.forEach.call(box.querySelectorAll('[data-var]'), function (f) {
      var key = f.getAttribute('data-var');
      if (key.charAt(0) === 'u') { f.value = prefill(key, t, r); return; }
      if (Object.prototype.hasOwnProperty.call(typed, key)) { f.value = typed[key]; f.setAttribute('data-typed', '1'); }
      else f.value = prefill(key, t, r);
      f.addEventListener('input', function () { f.setAttribute('data-typed', '1'); preview(); });
    });
    if (isDoc && r && r.kind === 'contact' && !given) loadReports(r.client_id);
    else preview();
  }
  /* The approval reminder's own client: what waits and its link fill in. */
  function approving(r) { return Boolean(cx && cx.o.purpose === 'approval' && r && r.kind === 'contact' && r.client_id === cx.o.clientId); }
  /* A numbered variable is named for what `prefill` puts in it, so the
     field says what it is without reading the preview (ux-audit WA-1,
     2026-10-14); one the page does not fill keeps its number. */
  function numbered(v, t, r) {
    if (!r) return 'Variable ' + v;
    var doc = t.header === 'DOCUMENT' && r.kind === 'contact';
    if (v === '1') return 'Greeting';
    if (v === '2') return r.kind === 'creator' ? 'Campaign' : 'Client';
    if (v === '3' && doc) return cx.o.doc ? 'Reference' : 'Report';
    if (v === '3' && approving(r)) return 'What waits';
    if (v === '4' && approving(r)) return 'Link';
    return 'Variable ' + v;
  }
  function human(v) { var s = String(v).replace(/_/g, ' ').trim(); return s.charAt(0).toUpperCase() + s.slice(1); }
  /* What a variable is filled with, from what the record holds: the
     greeting first, then the client (a creator's campaign), then a report's
     title; a named variable by its name. */
  function prefill(key, t, r) {
    if (!r) return '';
    var o = cx.o, kind = key.charAt(0), v = key.slice(2), low = v.toLowerCase();
    var rep = reportWord();
    /* A link button's variable: a creator's code; on the approval
       reminder, the link to approve past the button's own fixed base
       (`https://digital.adspace.me/{{1}}` takes `review/?k=…` or
       `creators/?k=…`). */
    if (kind === 'u') {
      if (approving(r)) {
        var base = String((t.button_var && t.button_var.url) || '').split('{{')[0];
        var link = String(o.link || '');
        return base && link.indexOf(base) === 0 ? link.slice(base.length) : '';
      }
      return r.kind === 'creator' ? (r.code || '') : '';
    }
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
    if (/report|period|month|ref|quot|letter|offer|document/.test(low)) return rep ? rep.title : '';
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
    if (cx.o.doc) return { id: cx.o.doc.id, title: cx.o.doc.title, client: r.client, doc: cx.o.doc };
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
      ? '<p class="wa-doc">' + FILE + '<span>' + esc(rep ? (rep.doc ? rep.doc.title : reportTitle(rep.row)) : 'No report chosen') + '</span></p>'
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
    if (isDoc && r.kind !== 'contact') { say(m, 'A template with a Document header goes to a client contact.', 'err'); return; }
    if (isDoc && !rep) { say(m, 'Choose a report.', 'err'); return; }
    /* A document the composer was not opened on is a report; one it was
       opened on is that quotation or letter, sent under its own purpose. */
    var docOf = isDoc && rep.doc ? o.purpose : isDoc ? 'report' : null;
    if (badButton(t)) { say(m, SAID['wa-button-address'], 'err'); return; }
    var link = $('waFields').querySelector('[data-var^="u:"]');
    if (link && !String(link.value || '').trim()) { say(m, SAID['wa-no-link'], 'err'); return; }
    var empty = Array.prototype.filter.call($('waFields').querySelectorAll('[data-var]'), function (f) { return !String(f.value || '').trim(); })[0];
    if (empty) {
      var lab = $('waFields').querySelector('label[for="' + empty.id + '"]');
      say(m, 'Fill in ' + (lab ? lab.textContent : 'every variable') + '.', 'err');
      empty.focus();
      return;
    }
    var purpose = docOf || ((o.purpose === 'feedback' || approving(r) || (o.purpose === 'creator' && r.kind === 'creator' && r.id === o.creatorId)) ? o.purpose : 'message');
    if (!maySend(purpose)) { say(m, SAID.denied, 'err'); return; }
    var ref = DOC[purpose] ? rep.id : purpose === 'creator' ? o.optionId : purpose === 'approval' ? o.ref : null;
    var values = {}, header = '';
    Array.prototype.forEach.call($('waFields').querySelectorAll('[data-var]'), function (f) {
      var key = f.getAttribute('data-var'), v = String(f.value || '').trim();
      if (key.charAt(0) === 'b') values[key.slice(2)] = v;
      else if (key.charAt(0) === 'h') header = v;
    });
    var cat = CATEGORY[t.category] || 'template';
    var costLine = 'Meta charges it as a ' + cat + ' message.';
    /* Sent recently (2026-10-14; the user: "so no duplicate would be
       repeated sent"): the same message to the same person about the same
       record within `wa_repeat_hours` (24, a Business setting) asks again
       in warn, naming who sent it and when; `wa-send` refuses it unless
       the second question was answered (`again`). */
    var ask = function (rec) {
      window.ADspaceConfirm.ask(rec ? {
        title: 'Sent recently', go: 'Send again', tone: 'warn',
        body: recentLine(rec, r) + ' Send it again? ' + costLine
      } : {
        title: 'Send on WhatsApp?', go: 'Send',
        body: 'The message goes to ' + r.name + (r.kind === 'contact' && r.client ? ' of ' + r.client : '') + ' on ' + phone(r.number) +
          '. ' + costLine
      }, function () { go(Boolean(rec)); });
    };
    var go = function (again) {
      cx.sending = true;
      $('waSend').disabled = true;
      say(m, isDoc ? 'Attaching the PDF…' : 'Sending…');
      var mine = cx;
      var pdf = isDoc && rep.doc
        ? Promise.resolve().then(function () { return rep.doc.file(); })
          .then(function (f) { return toB64(f.blob).then(function (b) { return { b64: b, name: f.name }; }); })
        : isDoc
        ? (window.ADspaceReports && window.ADspaceReports.keptPdf
          ? window.ADspaceReports.keptPdf(rep.id) : Promise.reject({ code: 'bad-file' }))
          .then(function (f) { return toB64(f.blob).then(function (b) { return { b64: b, name: f.name }; }); })
        : Promise.resolve(null);
      pdf.then(function (file) {
        if (file) say(m, 'Sending…');
        return invoke({ action: 'compose', to_kind: r.kind, to_id: r.id, purpose: purpose, ref: ref,
          template: { name: t.name, language: t.language }, values: values, header_value: header,
          pdf: file ? file.b64 : undefined, filename: file ? file.name : undefined, again: again || undefined });
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
        /* Sent by somebody else while this one was asked: the question
           again, never a second message unasked. */
        if (e && e.code === 'recent' && e.recent) { say(m, ''); ask(e.recent); return; }
        /* A refusal the function named, else the report's file that could
           not be read. */
        say(m, said(e && e.code && !e.message ? e : { code: 'bad-file' }), 'err');
      });
    };
    db().rpc('wa_sent_recently', { p_to_kind: r.kind, p_to: r.id, p_purpose: purpose, p_ref: ref, p_template: t.name })
      .then(function (res) { var d = res && res.data; return d && d.recent ? d : null; })
      .catch(function () { return null; })
      .then(function (rec) { if (cx && cx.o === o && !cx.sending) ask(rec); });
  }
  /* "Sent on WhatsApp to Lim Wei Ming by Qiao Rou on 14 Oct 14:05, 3 hours
     ago." A queued one is waiting to send; the queue's own is Automatic. */
  function recentLine(rec, r) {
    var mins = Math.max(0, Math.round((Date.now() - Date.parse(rec.at)) / 60000));
    var ago = mins < 60 ? (mins <= 1 ? 'a minute ago' : mins + ' minutes ago')
      : Math.round(mins / 60) === 1 ? 'an hour ago' : Math.round(mins / 60) + ' hours ago';
    var who = rec.to || r.name;
    var by = rec.by ? ' by ' + rec.by : ' automatically';
    /* A message Not confirmed may already have been delivered: never said
       to be waiting (2026-10-17, the review's finding 11). */
    if (rec.state === 'unknown') {
      return 'Sent on WhatsApp to ' + who + by + ' on ' + whenOf(rec.at) + ', ' + ago +
        ', and not confirmed. It may already have been delivered.';
    }
    return (rec.state === 'sent' ? 'Sent on WhatsApp to ' + who : 'Already waiting to send on WhatsApp to ' + who) +
      by + ' on ' + whenOf(rec.at) + ', ' + ago + '.';
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

  /* Settings, Templates: WhatsApp templates opens the one list of them
     (2026-10-29, the user: every template in one place). */
  var tplWired = false;
  function manage(opener) {
    if (!tplWired) {
      tplWired = true;
      var shut = function () { window.ADspaceSheet.close(); };
      $('waTplClose').addEventListener('click', shut);
    }
    window.ADspaceSheet.show($('waTplSheet'), { opener: opener || null });
    paintTemplates();
  }

  window.ADspaceWhatsApp = {
    enter: enter,
    manage: manage,
    urlState: function () { return {}; },
    compose: function (o) { wireComposer(); compose(o); },
    may: maySend,
    on: on,
    /* How many purposes have a template on, of how many (the Settings
       row, 2026-10-14, ux-audit SET-7). */
    templates: function () {
      return read().then(function (k) {
        if (k.error) throw k.error;
        return { on: k.list.filter(function (t) { return t.active && t.name; }).length, all: k.list.length };
      });
    },
    said: said
  };
})();
