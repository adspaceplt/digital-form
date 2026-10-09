/* WhatsApp (2026-10-09; 2026-10-09-whatsapp.sql, `wa-send`): messages the
 * portal sends through the WhatsApp Business Platform, each with a template
 * Meta approved (the user: "Report to client, Team reminders, Creator
 * updates, Manually send with button a feedback approved template on
 * whatsapp").
 *
 *   ADspaceWhatsApp.manage(btn)        — Business settings: the four
 *                                        templates (name, language, how many
 *                                        variables, on or off) and the last
 *                                        fifty messages
 *   ADspaceWhatsApp.sendReport(o)      — a published report's PDF to the
 *                                        client's main contact
 *   ADspaceWhatsApp.sendFeedback(o)    — the feedback template to the main
 *                                        contact
 *   ADspaceWhatsApp.on(purpose)        — a promise of whether a purpose has
 *                                        a template on (read once a page)
 */
(function () {
  var API = window.ADspaceAPI;
  var X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  var PURPOSE = {
    report: ['Report to client', 'A published report\'s PDF as the header document. Variables: the contact\'s first name, the client, the report.'],
    feedback: ['Feedback request', 'Sent by hand from the client\'s record. Variables: the contact\'s first name, the client.'],
    reminder: ['Team reminders', 'Each reminder in a colleague\'s bell, to their mobile. Variables: their first name, the title, the message.'],
    creator: ['Creator updates', 'Booked, changes requested, cleared to post. Variables: the creator\'s first name, the campaign, the step.']
  };
  var STATE = { queued: ['Queued', 'is-off'], sending: ['Sending', 'is-warn'], sent: ['Sent', 'is-ok'], failed: ['Not sent', 'is-danger'] };
  var SAID = {
    denied: 'This needs Business settings.',
    'bad-name': 'Enter the template name exactly as Meta holds it: lower case letters, digits and underscores.',
    'bad-lang': 'Enter the language code as Meta holds it, such as en or en_US.',
    'bad-params': 'A template takes 0 to 5 variables.',
    'wa-off': 'Turn this template on in WhatsApp settings first.',
    'no-number': 'The main contact has no WhatsApp number. Add one in Contacts.',
    'not-published': 'Publish the report first.',
    'not-found': 'This record is no longer available.',
    'wa-not-set-up': 'WhatsApp needs its Phone number ID and token in Supabase.',
    'wa-token': 'The WhatsApp token was refused. Check it in Supabase.',
    'wa-template': 'Meta does not know this template name. Check WhatsApp settings.',
    'wa-params': 'The template takes a different number of variables. Check WhatsApp settings.',
    'wa-recipient': 'This number is not on WhatsApp.',
    'wa-busy': 'WhatsApp is busy. Try again in a minute.',
    'wa-failed': 'Not sent. Try again.',
    'bad-file': 'The PDF could not be attached.',
    'needs-update': 'This needs a database update.'
  };
  function db() { return API && API.client; }
  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function said(e) {
    if (!e) return SAID['wa-failed'];
    if (e.message) return /function|schema cache/i.test(e.message) ? SAID['needs-update'] : SAID['wa-failed'];
    return SAID[e] || String(e);
  }
  function when(iso) {
    var M = window.ADspaceMaintenance;
    return M && M.when ? M.when(iso) : String(iso || '');
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
      }, function (e) { return { on: {}, list: [], error: e }; });
    }
    return known;
  }
  function on(purpose) { return read().then(function (k) { return Boolean(k.on[purpose]); }); }

  /* ---- Settings ------------------------------------------------------------ */
  var sheet = null;
  function settingsSheet() {
    if (sheet) return sheet;
    sheet = document.createElement('div');
    sheet.className = 'sheet'; sheet.id = 'waSheet'; sheet.hidden = true;
    sheet.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="waTitleH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="waTitleH">WhatsApp</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        '<section class="fsec ann-sec"><h4 class="fsec-h">Templates</h4>' +
          '<div class="msg" id="waMsg" role="status"></div><div id="waTemplates"></div></section>' +
        '<section class="fsec ann-sec"><h4 class="fsec-h">Recent messages</h4><div id="waRecent"></div></section>' +
      '</div></div>';
    document.body.appendChild(sheet);
    sheet.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    return sheet;
  }
  function msg(text, tone) {
    var m = $('waMsg');
    if (!m) return;
    m.textContent = text || '';
    m.className = 'msg' + (tone ? ' ' + tone : '');
  }
  function paintTemplates() {
    var box = $('waTemplates'), S = window.ADspaceState;
    if (S && S.skeleton) S.skeleton(box, 2);
    known = null;
    read().then(function (k) {
      if (k.error) { if (S && S.failLine) S.failLine(box, 'WhatsApp templates', said(k.error), paintTemplates); return; }
      box.innerHTML = '<div class="ann-rows">' + k.list.map(function (t) {
        var w = PURPOSE[t.purpose] || [t.purpose, ''];
        var live = t.active && t.name;
        return '<div class="ann-row wa-row" data-p="' + esc(t.purpose) + '">' +
          '<div class="ann-what"><p class="ann-text">' + esc(w[0]) + '</p>' +
            '<p class="ann-meta">' + esc(t.name ? t.name + ' · ' + t.lang + ' · ' + t.params + (t.params === 1 ? ' variable' : ' variables') : 'No template') + '</p></div>' +
          '<div class="ann-ctl"><span class="chip-state ' + (live ? 'is-ok' : 'is-off') + '">' + (live ? 'On' : 'Off') + '</span></div>' +
          '<div class="ann-acts"><button class="btn btn-sm" type="button" data-a="edit">Edit</button></div></div>';
      }).join('') + '</div>';
      Array.prototype.forEach.call(box.querySelectorAll('.wa-row'), function (rw) {
        var t = k.list.filter(function (x) { return x.purpose === rw.getAttribute('data-p'); })[0];
        rw.querySelector('[data-a="edit"]').addEventListener('click', function () { edit(t); });
      });
    });
  }
  function edit(t) {
    var w = PURPOSE[t.purpose] || [t.purpose, ''];
    window.ADspaceConfirm.ask({
      title: w[0], body: w[1], go: 'Save',
      fields: [
        { name: 'name', label: 'Template name', value: t.name || '', placeholder: 'monthly_report', required: false },
        { name: 'lang', label: 'Language', value: t.lang || 'en', placeholder: 'en', half: true },
        { name: 'params', label: 'Variables', type: 'number', min: '0', value: String(t.params || 0), half: true },
        { name: 'active', label: 'On', tick: true, value: Boolean(t.active) }
      ],
      check: function (v) {
        if (v.active === 'on' && !String(v.name || '').trim()) return 'Enter the template name to turn it on.';
        var n = Number(v.params);
        if (!(n >= 0 && n <= 5 && n === Math.floor(n))) return SAID['bad-params'];
        return '';
      }
    }, function (v) {
      db().rpc('wa_template_save', { p_purpose: t.purpose, p_name: String(v.name || '').trim(), p_lang: String(v.lang || '').trim(),
        p_params: Number(v.params), p_active: v.active === 'on' }).then(function (r) {
        var d = (r && r.data) || {};
        if ((r && r.error) || d.error) { msg(said(r.error || d.error), 'err'); return; }
        msg(d.same ? 'No change.' : 'Saved.', 'ok');
        paintTemplates();
      }).catch(function (e) { msg(said(e), 'err'); });
    });
  }
  function paintRecent() {
    var box = $('waRecent'), S = window.ADspaceState;
    if (S && S.skeleton) S.skeleton(box, 2);
    db().rpc('wa_recent').then(function (r) {
      var d = (r && r.data) || {};
      if ((r && r.error) || d.error) { if (S && S.failLine) S.failLine(box, 'Recent messages', said(r.error || d.error), paintRecent); return; }
      var items = d.items || [];
      if (!items.length) { box.innerHTML = '<p class="ann-none">No messages.</p>'; return; }
      box.innerHTML = '<div class="ann-rows">' + items.map(function (x) {
        var s = STATE[x.state] || STATE.queued;
        return '<div class="ann-row wa-msg">' +
          '<div class="ann-what"><p class="ann-text">' + esc((PURPOSE[x.purpose] || [x.purpose])[0]) + ' · ' + esc(x.to_name || x.to_number) + '</p>' +
            '<p class="ann-meta">' + esc([x.to_number, when(x.sent_at || x.created_at), x.created_by && x.created_by !== 'system' ? 'By ' + x.created_by : ''].filter(Boolean).join(' · ')) + '</p></div>' +
          '<div class="ann-ctl"><span class="chip-state ' + s[1] + '">' + s[0] + '</span></div><div class="ann-acts"></div></div>';
      }).join('') + '</div>';
    }).catch(function (e) { if (S && S.failLine) S.failLine(box, 'Recent messages', said(e), paintRecent); });
  }
  function manage(btn) {
    settingsSheet();
    msg('');
    window.ADspaceSheet.show(sheet, { opener: btn || null });
    paintTemplates();
    paintRecent();
  }

  /* ---- By hand ------------------------------------------------------------- */
  function invoke(body) {
    return db().functions.invoke('wa-send', { body: body }).then(function (res) {
      var d = res && res.data;
      if (res.error || !d || d.error) throw (d && d.error) || 'wa-failed';
      return d;
    });
  }
  function toB64(blob) {
    return new Promise(function (ok, bad) {
      var fr = new FileReader();
      fr.onload = function () { ok(String(fr.result).replace(/^data:[^,]*,/, '')); };
      fr.onerror = function () { bad('bad-file'); };
      fr.readAsDataURL(blob);
    });
  }
  /* o: { reportId, title, pdf: () => Promise<Blob>, filename, btn } */
  function sendReport(o) {
    return o.pdf().then(function (blob) { return toB64(blob); }).then(function (b64) {
      return invoke({ action: 'report', report_id: o.reportId, pdf: b64, filename: o.filename, title: o.title });
    }).catch(function (e) { throw SAID[e] ? e : (e && e.message ? e : 'wa-failed'); });
  }
  /* o: { clientId } */
  function sendFeedback(o) { return invoke({ action: 'feedback', client_id: o.clientId }); }

  window.ADspaceWhatsApp = { manage: manage, on: on, sendReport: sendReport, sendFeedback: sendFeedback, said: said };
})();
