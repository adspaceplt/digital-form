/* Announcements (2026-10-07): one line under the top bar, the team's on the
 * console and the clients' on every client page, each its own and one at a
 * time. It asks `announcement_now(audience)` on load, every minute while the
 * page is on screen and on every return to it (ADspaceMaintenance.often), and
 * draws nothing when none is live. The words follow the page's language
 * (中文 where it was given). The person reading closes it for this browser
 * (`adspace-ann-hide:{id}:{updated_at}`), so an edited line comes back.
 *
 * The console's account menu opens the list (Team: Announcements,
 * `team.announce`): `ADspaceAnnounce.manage(opener)`.
 *
 *   ADspaceAnnounce.refresh()     — asks again now
 *   ADspaceAnnounce.manage(btn)   — the console's sheet
 */
(function () {
  var API = window.ADspaceAPI;
  var inConsole = /^\/admin(\/|$)/.test(location.pathname);
  var audience = inConsole ? 'team' : 'clients';
  var shown = null;
  var X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  var OUT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';
  var PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  var PEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16v4z"/></svg>';

  function zh() { return String(document.documentElement.lang || '').indexOf('zh') === 0; }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function db() { return API && API.client; }
  function key(a) { return 'adspace-ann-hide:' + a.id + ':' + (a.updated_at || ''); }
  function hiddenHere(a) { try { return localStorage.getItem(key(a)) === '1'; } catch (e) { return false; } }
  function hideHere(a) { try { localStorage.setItem(key(a), '1'); } catch (e) { /* closes for now only */ } }

  /* Where the bar sits: under the console's head (before the upgrade line),
     else under a client page's bar. */
  function host() {
    var bar = document.getElementById('annBar');
    if (bar) return bar;
    bar = document.createElement('div');
    bar.className = 'annbar';
    bar.id = 'annBar';
    bar.setAttribute('role', 'status');
    bar.hidden = true;
    var up = document.getElementById('upgradeBar');
    var top = document.querySelector('.topbar');
    if (inConsole && up && up.parentNode) up.parentNode.insertBefore(bar, up);
    else if (top && top.parentNode) top.parentNode.insertBefore(bar, top.nextSibling);
    else if (document.body) document.body.insertBefore(bar, document.body.firstChild);
    else return null;
    return bar;
  }

  function paint() {
    var a = shown;
    /* Nothing to say, or the page is under upgrade mode's cover: no bar, and
       none made (a box made after the cover would sit outside it). */
    var quiet = !a || hiddenHere(a) || (document.body && document.body.classList.contains('is-maint'));
    if (quiet) {
      var was = document.getElementById('annBar');
      if (was) { was.hidden = true; was.innerHTML = ''; }
      return;
    }
    var bar = host();
    if (!bar) return;
    var cn = zh();
    var text = cn && a.body_zh ? a.body_zh : a.body_en;
    bar.className = 'annbar' + (a.tone === 'important' ? ' is-important' : '');
    bar.innerHTML = '<p class="annbar-text">' + esc(text) + '</p>' +
      '<span class="annbar-acts">' +
        (a.link ? '<a class="btn btn-sm annbar-open" href="' + esc(a.link) + '" target="_blank" rel="noopener">' + (cn ? '查看' : 'Open') + OUT + '</a>' : '') +
        '<button class="iconbtn annbar-x" type="button" aria-label="' + (cn ? '关闭' : 'Dismiss') + '">' + X + '</button>' +
      '</span>';
    bar.hidden = false;
    bar.querySelector('.annbar-x').addEventListener('click', function () { hideHere(a); paint(); });
  }

  function refresh() {
    var c = db();
    if (!c || !c.rpc) return Promise.resolve(null);
    return Promise.resolve(c.rpc('announcement_now', { p_audience: audience })).then(function (r) {
      if (!r || r.error) return;               // a read that fails changes nothing
      shown = r.data && r.data.id ? r.data : null;
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', paint, { once: true });
      else paint();
    }).catch(function () {});
  }

  if (window.MutationObserver) {
    new MutationObserver(function () { if (shown) paint(); })
      .observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] });
  }
  /* The console asks once the person is known (ADspaceAnnounce.refresh from
     js/admin.js); a client page asks at once. */
  if (!inConsole) refresh();
  if (window.ADspaceMaintenance && window.ADspaceMaintenance.often) window.ADspaceMaintenance.often(refresh);

  /* ---- The console's list (Team: Announcements) ----------------------------- */
  var NAME = { team: 'Team', clients: 'Clients' };
  function myDay(d) {
    return new Date(d.getTime() + 8 * 3600000).toISOString().slice(0, 10);
  }
  function myTime(d) {
    return new Date(d.getTime() + 8 * 3600000).toISOString().slice(11, 16);
  }
  /* A day and an optional time in Malaysia, as one moment; none for neither. */
  function moment(day, time, fallback) {
    if (!day && !time) return null;
    var d = day || myDay(new Date());
    return new Date(d + 'T' + (time || fallback) + ':00+08:00').toISOString();
  }
  function when(iso) {
    var M = window.ADspaceMaintenance;
    return M && M.when ? M.when(iso) : String(iso || '');
  }
  function stateOf(a, now) {
    if (a.ended_at) return 'Stopped';
    if (a.ends_at && new Date(a.ends_at) <= now) return 'Ended';
    if (a.starts_at && new Date(a.starts_at) > now) return 'Scheduled';
    return 'Live';
  }
  var SAID = {
    denied: 'This needs Team: Announcements.',
    'bad-text': 'Enter the announcement, 300 characters at most.',
    'bad-link': 'The link starts with https://.',
    'bad-window': 'Choose an end after the start, and later than now.',
    'bad-tone': 'Choose Info or Important.',
    over: 'Its end has passed. Post it again with a new end.',
    'not-found': 'That announcement is no longer there.'
  };
  function said(e) {
    if (!e) return 'Not saved.';
    if (e.message) return /function|schema cache/i.test(e.message) ? 'This needs a database update.' : e.message;
    return SAID[e] || e;
  }

  var box = null, opener = null;
  function shell() {
    if (box) return box;
    box = document.createElement('div');
    box.className = 'sheet'; box.id = 'annSheet'; box.hidden = true;
    box.innerHTML = '<div class="sheet-card formsheet" role="dialog" aria-modal="true" aria-labelledby="annTitle" data-narrow="560">' +
      '<div class="sheet-head"><h3 id="annTitle">Announcements</h3>' +
      '<button class="iconbtn" type="button" data-a="x" aria-label="Close">' + X + '</button></div>' +
      '<div class="sheet-body"><div id="annList"></div><div class="msg" id="annMsg" role="status"></div></div></div>';
    document.body.appendChild(box);
    box.querySelector('[data-a="x"]').addEventListener('click', function () { window.ADspaceSheet.close(); });
    return box;
  }
  function msg(text, tone) {
    var m = document.getElementById('annMsg');
    if (!m) return;
    m.textContent = text || '';
    m.className = 'msg' + (tone ? ' ' + tone : '');
  }

  function load() {
    var list = document.getElementById('annList');
    var S = window.ADspaceState;
    if (S && S.skeleton) S.skeleton(list, 2);
    db().rpc('announcements_list').then(function (r) {
      var d = (r && r.data) || {};
      if ((r && r.error) || d.error) {
        if (S && S.failLine) S.failLine(list, 'Announcements', said(r.error || d.error), load);
        return;
      }
      var now = new Date(d.now || Date.now());
      var items = d.items || [];
      list.innerHTML = ['team', 'clients'].map(function (aud) {
        var mine = items.filter(function (a) { return a.audience === aud; });
        var cur = mine.filter(function (a) { var s = stateOf(a, now); return s === 'Live' || s === 'Scheduled'; })[0];
        var last = !cur ? mine.filter(function (a) { return stateOf(a, now) === 'Stopped' && (!a.ends_at || new Date(a.ends_at) > now); })[0] : null;
        var row = function (a, st) {
          var win = [a.starts_at ? 'From ' + when(a.starts_at) : '', a.ends_at ? 'Until ' + when(a.ends_at) : ''].filter(Boolean).join(' · ');
          return '<div class="ann-row" data-id="' + esc(a.id) + '">' +
            '<div class="ann-what"><p class="ann-text">' + esc(a.body_en) + '</p>' +
              (a.body_zh ? '<p class="ann-zh" lang="zh">' + esc(a.body_zh) + '</p>' : '') +
              '<p class="ann-meta">' + esc([win, a.updated_by ? 'By ' + a.updated_by : ''].filter(Boolean).join(' · ')) + '</p></div>' +
            '<div class="ann-ctl"><span class="chip' + (st === 'Live' ? ' tone is-ok' : st === 'Scheduled' ? ' tone is-warn' : '') + '">' + st + '</span>' +
              (a.tone === 'important' ? '<span class="chip tone is-warn">Important</span>' : '') + '</div>' +
            '<div class="ann-acts">' +
              (st === 'Stopped'
                ? '<button class="btn btn-sm" type="button" data-a="restore">Restore</button>'
                : '<button class="btn btn-sm" type="button" data-a="edit">' + PEN + 'Edit</button>' +
                  '<button class="btn btn-sm btn-warn" type="button" data-a="stop">Stop</button>') +
            '</div></div>';
        };
        return '<section class="fsec ann-sec" data-aud="' + aud + '">' +
          '<div class="ann-head"><h4 class="fsec-h">' + NAME[aud] + '</h4>' +
          '<button class="btn btn-sm" type="button" data-a="new">' + PLUS + 'New</button></div>' +
          (cur ? row(cur, stateOf(cur, now)) : last ? row(last, 'Stopped') : '<p class="ann-none">No announcement.</p>') +
          '</section>';
      }).join('');
      var byId = {};
      items.forEach(function (a) { byId[a.id] = a; });
      Array.prototype.forEach.call(list.querySelectorAll('.ann-sec'), function (sec) {
        var aud = sec.getAttribute('data-aud');
        sec.querySelector('[data-a="new"]').addEventListener('click', function () { edit(aud, null, this); });
        Array.prototype.forEach.call(sec.querySelectorAll('.ann-row'), function (rw) {
          var a = byId[rw.getAttribute('data-id')];
          var on = function (k, fn) { var b = rw.querySelector('[data-a="' + k + '"]'); if (b) b.addEventListener('click', function () { fn(b); }); };
          on('edit', function (b) { edit(aud, a, b); });
          on('stop', function () {
            window.ADspaceConfirm.ask({ title: 'Stop this announcement?', body: 'It leaves every ' + (aud === 'team' ? 'console' : 'client page') + ' at once.', go: 'Stop', tone: 'warn' },
              function () { end(a, false); });
          });
          on('restore', function () { end(a, true); });
        });
      });
    }).catch(function (e) { if (S && S.failLine) S.failLine(list, 'Announcements', said(e), load); });
  }

  function end(a, on) {
    db().rpc('announcement_end', { p_id: a.id, p_on: on }).then(function (r) {
      var d = (r && r.data) || {};
      if ((r && r.error) || d.error) { msg(said(r.error || d.error), 'err'); return; }
      msg(on ? 'Restored.' : 'Stopped.', 'ok');
      load(); refresh();
    }).catch(function (e) { msg(said(e), 'err'); });
  }

  function edit(aud, a, btn) {
    var today = myDay(new Date());
    var s = a && a.starts_at ? new Date(a.starts_at) : null, e = a && a.ends_at ? new Date(a.ends_at) : null;
    var win = function (v) {
      var starts = moment(v.sday, v.stime, '00:00'), ends = moment(v.eday, v.etime, '23:59');
      var bad = ends && (new Date(ends) <= new Date(starts || Date.now()) || new Date(ends) <= new Date());
      return { starts: starts, ends: ends, bad: bad ? SAID['bad-window'] : '' };
    };
    window.ADspaceConfirm.ask({
      title: (a ? 'Edit' : 'New') + ' ' + NAME[aud].toLowerCase() + ' announcement',
      body: aud === 'team' ? 'Shown at the top of the console.' : 'Shown at the top of every client page.',
      go: a ? 'Save' : 'Post',
      fields: [
        { name: 'tone', label: 'Tone', choices: [['info', 'Info'], ['important', 'Important']], value: a ? a.tone : 'info' },
        { name: 'en', label: 'English', rows: 2, value: a ? a.body_en : '', need: 'Enter the announcement.', placeholder: 'Our office is closed on Friday.' },
        { name: 'zh', label: '中文', rows: 2, value: a && a.body_zh || '', required: false, placeholder: 'Optional' },
        { name: 'link', label: 'Link', value: a && a.link || '', required: false, placeholder: 'https://adspace.me' },
        { name: 'sday', label: 'Starts', type: 'date', min: today, required: false, half: true, value: s ? myDay(s) : '' },
        { name: 'stime', label: 'Start time', type: 'time', required: false, half: true, hint: 'Optional', value: s ? myTime(s) : '' },
        { name: 'eday', label: 'Ends', type: 'date', min: today, required: false, half: true, value: e ? myDay(e) : '' },
        { name: 'etime', label: 'End time', type: 'time', required: false, half: true, hint: 'Optional', value: e ? myTime(e) : '' }
      ],
      check: function (v) {
        if (String(v.en || '').trim().length > 300 || String(v.zh || '').trim().length > 300) return SAID['bad-text'];
        if (v.link && !/^https:\/\/\S+$/.test(String(v.link).trim())) return SAID['bad-link'];
        return win(v).bad;
      }
    }, function (v) {
      var w = win(v);
      db().rpc('announcement_save', {
        p_id: a ? a.id : null, p_audience: aud, p_tone: v.tone || 'info', p_body_en: v.en, p_body_zh: v.zh || null,
        p_link: v.link || null, p_starts: w.starts, p_ends: w.ends
      }).then(function (r) {
        var d = (r && r.data) || {};
        if ((r && r.error) || d.error) { msg(said(r.error || d.error), 'err'); return; }
        msg(a ? 'Saved.' : 'Posted.', 'ok');
        load(); refresh();
      }).catch(function (err) { msg(said(err), 'err'); });
    });
  }

  function manage(btn) {
    opener = btn || null;
    shell();
    msg('');
    window.ADspaceSheet.show(box, { opener: opener });
    load();
  }

  window.ADspaceAnnounce = { refresh: refresh, manage: manage };
})();
