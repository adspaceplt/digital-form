/* Notices (2026-10-09): a notice to all colleagues, or to the colleagues
 * chosen, in each bell and as a push (the user, 2026-10-09: "send custom
 * in-app notifications to all members, or to specific team member(s)").
 * Team: Notices (`team.notice`, granted: an admin's by itself, any other
 * group's once set) opens the list from the account menu: every notice sent,
 * newest first, whom it went to and how many have read it, with Withdraw
 * (asked; it leaves every bell) and Restore (never asks). New opens the
 * second sheet: To (All colleagues, Selected colleagues), the colleagues
 * ticked, Title and Message.
 *
 *   ADspaceNotice.manage(btn)   — opens the list
 */
(function () {
  var API = window.ADspaceAPI;
  var X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var TITLE_MAX = 120, BODY_MAX = 1000;

  function db() { return API && API.client; }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function when(iso) {
    var M = window.ADspaceMaintenance;
    return M && M.when ? M.when(iso) : String(iso || '');
  }
  var SAID = {
    denied: 'This needs Team: Notices.',
    'bad-title': 'Enter a title of 120 characters at most.',
    'bad-body': 'Enter a message of 1,000 characters at most.',
    'no-one': 'Choose at least one colleague.',
    'not-found': 'That notice is no longer there.'
  };
  function said(e) {
    if (!e) return 'Not sent.';
    if (e.message) return /function|schema cache/i.test(e.message) ? 'This needs a database update.' : 'Not sent. Check the connection and try again.';
    return SAID[e] || e;
  }
  function $(id) { return document.getElementById(id); }

  /* ---- The list --------------------------------------------------------- */
  var list = null, compose = null, opener = null, people = [];
  function listSheet() {
    if (list) return list;
    list = document.createElement('div');
    list.className = 'sheet'; list.id = 'ntcSheet'; list.hidden = true;
    list.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ntcTitleH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="ntcTitleH">Notices</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body"><section class="fsec ann-sec">' +
        '<div class="ann-head"><h4 class="fsec-h">Sent</h4>' +
        '<button class="btn btn-sm" type="button" id="ntcNew">' + PLUS + 'New</button></div>' +
        '<div class="msg" id="ntcMsg" role="status"></div>' +
        '<div id="ntcList"></div></section></div></div>';
    document.body.appendChild(list);
    list.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('ntcNew').addEventListener('click', function () { openNew(); });
    return list;
  }
  function msg(text, tone) {
    var m = $('ntcMsg');
    if (!m) return;
    m.textContent = text || '';
    m.className = 'msg' + (tone ? ' ' + tone : '');
  }
  function toWord(n) {
    return n.to_all ? 'All colleagues (' + n.sent + ')' : n.sent === 1 ? (n.names || [])[0] || '1 colleague'
      : n.sent <= 3 ? (n.names || []).join(', ') : n.sent + ' colleagues';
  }
  function load() {
    var box = $('ntcList');
    var S = window.ADspaceState;
    if (S && S.skeleton) S.skeleton(box, 2);
    db().rpc('team_notices_list').then(function (r) {
      var d = (r && r.data) || {};
      if ((r && r.error) || d.error) {
        if (S && S.failLine) S.failLine(box, 'Notices', said(r.error || d.error), load);
        return;
      }
      var items = d.items || [];
      if (!items.length) { box.innerHTML = '<p class="ann-none">No notices.</p>'; return; }
      var byId = {};
      items.forEach(function (n) { byId[n.id] = n; });
      box.innerHTML = '<div class="ann-rows">' + items.map(function (n) {
        var off = Boolean(n.withdrawn_at);
        return '<div class="ann-row ntc-row' + (off ? ' is-off' : '') + '" data-id="' + esc(n.id) + '">' +
          '<div class="ann-what"><p class="ann-text ntc-title">' + esc(n.title) + '</p>' +
            (n.body ? '<p class="ann-zh ntc-body">' + esc(n.body) + '</p>' : '') +
            '<p class="ann-meta">' + esc(['To ' + toWord(n), when(n.created_at), 'By ' + (n.sent_by_name || '')].join(' · ')) + '</p></div>' +
          '<div class="ann-ctl">' + (off ? '<span class="chip is-off">Withdrawn</span>'
            : '<span class="ntc-read">Read by ' + n.read + ' of ' + n.sent + '</span>') + '</div>' +
          '<div class="ann-acts">' + (off
            ? '<button class="btn btn-sm" type="button" data-a="restore">Restore</button>'
            : '<button class="btn btn-sm btn-warn" type="button" data-a="withdraw">Withdraw</button>') + '</div></div>';
      }).join('') + '</div>';
      Array.prototype.forEach.call(box.querySelectorAll('.ntc-row'), function (rw) {
        var n = byId[rw.getAttribute('data-id')];
        var w = rw.querySelector('[data-a="withdraw"]');
        if (w) w.addEventListener('click', function () {
          window.ADspaceConfirm.ask({ title: 'Withdraw this notice?', body: 'It leaves every bell at once. A notification already on a phone stays there.', go: 'Withdraw', tone: 'warn' },
            function () { end(n, false); });
        });
        var rs = rw.querySelector('[data-a="restore"]');
        if (rs) rs.addEventListener('click', function () { end(n, true); });
      });
    }).catch(function (e) { if (S && S.failLine) S.failLine(box, 'Notices', said(e), load); });
  }
  function end(n, back) {
    db().rpc('team_notice_withdraw', { p_id: n.id, p_restore: back }).then(function (r) {
      var d = (r && r.data) || {};
      if ((r && r.error) || d.error) { msg(said(r.error || d.error), 'err'); return; }
      msg(back ? 'Restored.' : 'Withdrawn.', 'ok');
      load();
    }).catch(function (e) { msg(said(e), 'err'); });
  }

  /* ---- New notice ------------------------------------------------------- */
  function composeSheet() {
    if (compose) return compose;
    compose = document.createElement('div');
    compose.className = 'sheet'; compose.id = 'ntcNewSheet'; compose.hidden = true;
    compose.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="ntcNewH" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="ntcNewH">New notice</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body">' +
        /* Four fields: one group, no section heads (DESIGN.md: sections from
           six fields). */
        '<div class="row"><div><label class="field-label" for="ntcTo">Send to</label>' +
          '<select class="select" id="ntcTo" data-seg><option value="all">All colleagues</option><option value="some">Selected colleagues</option></select></div></div>' +
        '<div class="row" id="ntcPick" hidden><div><span class="field-label" id="ntcPeopleL">Colleagues</span>' +
          '<div class="meta-accs ntc-people" id="ntcPeople" role="group" aria-labelledby="ntcPeopleL"></div></div></div>' +
        '<div class="row"><div><label class="field-label" for="ntcTitle">Title</label>' +
          '<textarea class="input" id="ntcTitle" data-oneline rows="1" maxlength="' + TITLE_MAX + '" aria-required="true" placeholder="Town hall at 3:00 pm"></textarea></div></div>' +
        '<div class="row"><div><label class="field-label" for="ntcBody">Message</label>' +
          '<textarea class="input" id="ntcBody" rows="4" maxlength="' + BODY_MAX + '" placeholder="Optional"></textarea></div></div>' +
        '<p class="msg" id="ntcNewMsg" role="status"></p>' +
      '</div>' +
      '<div class="sheet-foot">' +
        '<button class="btn btn-primary" type="button" id="ntcSend">Send</button>' +
        '<button class="btn btn-quiet" type="button" id="ntcCancel">Cancel</button>' +
        '<span class="lpicksum" id="ntcCount"></span>' +
      '</div></div>';
    document.body.appendChild(compose);
    var F = window.ADspaceForm;
    if (F && F.segment) F.segment($('ntcTo'));
    compose.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('ntcCancel').addEventListener('click', backToList);
    $('ntcTo').addEventListener('change', count);
    $('ntcPeople').addEventListener('change', count);
    $('ntcSend').addEventListener('click', send);
    return compose;
  }
  function chosen() {
    return Array.prototype.filter.call($('ntcPeople').querySelectorAll('input[data-id]'), function (c) { return c.checked; })
      .map(function (c) { return c.getAttribute('data-id'); });
  }
  /* Who it goes to, said beside Send. */
  function count() {
    var some = $('ntcTo').value === 'some';
    $('ntcPick').hidden = !some;
    var n = some ? chosen().length : people.length;
    $('ntcCount').textContent = n === 1 ? 'To 1 colleague' : 'To ' + n + ' colleagues';
  }
  function newMsg(text, tone) {
    var m = $('ntcNewMsg');
    m.textContent = text || '';
    m.className = 'msg' + (tone ? ' ' + tone : '');
  }
  /* Every active colleague but the sender and a system account, code
     first, A to Z, as the database will send to them. */
  function readPeople() {
    var me = window.ADspaceAdmin && window.ADspaceAdmin.me ? window.ADspaceAdmin.me() : null;
    var S = window.ADspaceAdmin;
    return db().from('team_members').select('id, name, staff_code, active, system').eq('active', true).then(function (r) {
      if (r.error) throw r.error;
      var F = window.ADspaceForm;
      people = (r.data || []).filter(function (m) {
        return !m.system && !(S && S.isSystem && S.isSystem(m)) && !(me && me.id === m.id);
      }).sort(F && F.byStaff ? F.byStaff : function () { return 0; });
      return people;
    });
  }
  function openNew() {
    composeSheet();
    var F = window.ADspaceForm;
    $('ntcTo').value = 'all';
    $('ntcTo').dispatchEvent(new Event('change'));
    $('ntcTitle').value = '';
    $('ntcBody').value = '';
    $('ntcPeople').innerHTML = '';
    newMsg('');
    $('ntcSend').disabled = true;
    window.ADspaceSheet.show(compose, { opener: opener });
    readPeople().then(function () {
      $('ntcPeople').innerHTML = people.map(function (m) {
        return '<label class="tickline"><input type="checkbox" data-id="' + esc(m.id) + '"> <span>' +
          esc(F && F.named ? F.named(m.staff_code, m.name) : m.name) + '</span></label>';
      }).join('');
      $('ntcSend').disabled = false;
      count();
    }).catch(function () {
      newMsg('Could not load the colleagues. Close and try again.', 'err');
    });
  }
  function backToList() {
    window.ADspaceSheet.show(listSheet(), { opener: opener });
  }
  function send() {
    var btn = $('ntcSend');
    var title = String($('ntcTitle').value || '').replace(/\s+/g, ' ').trim();
    var body = String($('ntcBody').value || '').trim();
    var some = $('ntcTo').value === 'some';
    var to = some ? chosen() : null;
    var F = window.ADspaceForm;
    newMsg('');
    if (some && !to.length) { newMsg(SAID['no-one'], 'err'); return; }
    if (!title) {
      newMsg('Enter the title.', 'err');
      if (F && F.reveal) F.reveal($('ntcTitle'));
      $('ntcTitle').focus();
      return;
    }
    btn.disabled = true;
    btn.textContent = 'Sending…';
    db().rpc('team_notice_send', { p_title: title, p_body: body || null, p_to: to }).then(function (r) {
      var d = (r && r.data) || {};
      btn.disabled = false; btn.textContent = 'Send';
      if ((r && r.error) || d.error) { newMsg(said(r.error || d.error), 'err'); return; }
      backToList();
      msg(d.count === 1 ? 'Sent to 1 colleague.' : 'Sent to ' + d.count + ' colleagues.', 'ok');
      load();
    }).catch(function (e) {
      btn.disabled = false; btn.textContent = 'Send';
      newMsg(said(e), 'err');
    });
  }

  function manage(btn) {
    opener = btn || null;
    listSheet();
    msg('');
    window.ADspaceSheet.show(list, { opener: opener });
    load();
  }

  window.ADspaceNotice = { manage: manage };
})();
