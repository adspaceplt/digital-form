/* One glyph an act (the user, 2026-10-10: "if have the icons then need to
   add icon … all buttons didnt follow the initial ones when newly build").
   The act table is the one place an act's mark is decided: every `.btn` on
   the console whose words are an act here carries that act's mark, drawn
   in the button's own ink, whichever screen drew it and whenever. A screen
   that writes a button with its own mark keeps it; one that writes the
   words alone is given the mark as the button is drawn, so a new section
   follows without being told. A form's own commit (a sheet's foot, a
   question, a submit, a button holding its own field) stays words, as
   `DESIGN.md` §5 holds and `tests/uxaudit.js` reads it. */
(function () {
  'use strict';
  /* [the words, the mark, after the words, never a commit]. The fourth
     marks an act that is never a form's own commit, so it keeps its mark
     inside a form or beside a field: a way out (Preview, Download, Copy)
     and another way in (a passkey; 2026-11-22, the user: My records' Use
     passkey drawn as words alone beside the lock's code field). */
  var ACTS = [
    [/^Publish$/, 'send'], [/^Unpublish$/, 'hide'],
    [/^Edit$/, 'pen'], [/^(Rename|Edit description)$/, 'pen'],
    [/^Download( PDF)?$/, 'file', false, true],
    [/^Copy( link| text| title)?$/, 'copy', false, true],
    [/^(Preview|Preview PDF)$/, 'out', true, true],
    [/^(Use passkey|Sign in with a passkey)$/, 'key', false, true],
    [/^(Add|New) \S/, 'plus'], [/^Issue document$/, 'plus'],
    /* What goes out by email from a screen: an invoice and a reminder
       (2026-11-04), a candidate's interview invitation and an email of
       one's own (2026-11-19, the user: Invite drawn as words alone). */
    [/^(Send (invoice|reminders?|email)|Invite|Email (the )?candidate|Request feedback)$/, 'mail'],
    /* A code sent by email (My records' lock, 2026-11-22), beside the
       field it fills, as Use passkey is. */
    [/^(Send code|Email a code)$/, 'mail', false, true],
    /* A way out to another system opens a tab of its own (the leaving
       mark after); a way to another console page takes the chevron after
       (DESIGN.md §5; 2026-11-19). */
    [/^Open in Bukku$/, 'out', true],
    [/^Open (Work|Months|Handbook|reviews)$/, 'go', true],
    /* View opens what it names (a report's step, a colleague's salary), as
       Reports draws it (2026-11-19). */
    [/^View$/, 'go', true]
  ];
  /* An act's name in the table and the set's glyph that draws it. */
  var ACT_GLYPH = { send: 'plane', hide: 'eyeoff', letter: 'doc', go: 'chevron' };
  var HARD = '.sheet-foot, .askcard, .undobar, .cover';
  var COMMIT = 'form, .sheet-foot, .askcard, .qform-acts, .changebox-actions, .zone-actions, .filearm-acts, .namebox, .undobar, .cover, .approve-row';
  function svg(name) {
    /* The act's mark from the one set (js/icons.js); `data-act` names it. */
    return window.ADspaceIcons.glyph(ACT_GLYPH[name] || name, '', 'data-act="' + name + '"');
  }
  function actOf(words) {
    for (var i = 0; i < ACTS.length; i++) if (ACTS[i][0].test(words)) return ACTS[i];
    return null;
  }
  function commit(b, act) {
    /* A way out or another way in keeps its mark on a cover too (the
       sign-in's Use passkey, 2026-11-22); a sheet's foot, a question and
       an Undo bar stay words. */
    if (b.type === 'submit' || b.closest(act && act[3] ? '.sheet-foot, .askcard, .undobar' : HARD)) return true;
    if (act && act[3]) return false;
    if (b.closest(COMMIT)) return true;
    var p = b.parentElement;
    return Boolean(p && p.querySelector('input:not([type=hidden]):not([type=checkbox]):not([type=radio]), select, textarea'));
  }
  function mark(b) {
    /* A quiet button acts too (a record part's Add, DESIGN.md §1): only a
       form's commit stays words, and Cancel names no act of the table. */
    if (!b || !b.classList || !b.classList.contains('btn')) return;
    var own = b.querySelector('svg:not([data-act]), img');
    if (own) return;
    var given = b.querySelector('svg[data-act]');
    var words = (b.textContent || '').replace(/\s+/g, ' ').trim();
    var act = words ? actOf(words) : null;
    if (act && commit(b, act)) act = null;
    if (given && (!act || given.getAttribute('data-act') !== act[1])) { given.remove(); given = null; }
    if (!act || given) return;
    b.insertAdjacentHTML(act[2] ? 'beforeend' : 'afterbegin', svg(act[1]));
  }
  function sweep(root) {
    if (!root || root.nodeType !== 1) return;
    if (root.classList.contains('btn')) mark(root);
    var all = root.querySelectorAll('.btn');
    for (var i = 0; i < all.length; i++) mark(all[i]);
  }
  function start() {
    sweep(document.body);
    new MutationObserver(function (list) {
      var seen = [];
      list.forEach(function (m) {
        var t = m.target.nodeType === 1 ? m.target : m.target.parentElement;
        var b = t && t.closest ? t.closest('.btn') : null;
        if (b && seen.indexOf(b) < 0) { seen.push(b); mark(b); }
        Array.prototype.forEach.call(m.addedNodes || [], function (n) { if (n.nodeType === 1) sweep(n); });
      });
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  }
  /* Pending until it lands (the user, 2026-10-10: "pending until its live
     kind of animations"). A press whose act disables its button while the
     write is out (every write in the console does: a second press is the
     same act) shows it working: after 150ms, so a quick answer never
     flickers, the button keeps its width and its words give way to a small
     turning ring in its own ink, until the button is let go. Nothing is
     asked of a screen: it already disables what it sends. */
  var pressed = null, pressedAt = 0;
  document.addEventListener('click', function (e) {
    var b = e.target && e.target.closest ? e.target.closest('.btn') : null;
    if (b) { pressed = b; pressedAt = Date.now(); }
  }, true);
  function busy(b, on) {
    if (on) {
      if (b.classList.contains('is-busy')) return;
      b.style.width = b.getBoundingClientRect().width + 'px';
      b.classList.add('is-busy');
      b.setAttribute('aria-busy', 'true');
      b.insertAdjacentHTML('beforeend', '<span class="btn-spin" aria-hidden="true"></span>');
    } else {
      if (!b.classList.contains('is-busy')) return;
      b.classList.remove('is-busy');
      b.removeAttribute('aria-busy');
      b.style.width = '';
      var sp = b.querySelector('.btn-spin');
      if (sp) sp.remove();
    }
  }
  new MutationObserver(function (list) {
    list.forEach(function (m) {
      var b = m.target;
      if (!b.classList || !b.classList.contains('btn')) return;
      if (b.disabled && b === pressed && Date.now() - pressedAt < 400) {
        setTimeout(function () { if (b.disabled && b.isConnected) busy(b, true); }, 150);
      } else if (!b.disabled) busy(b, false);
    });
  }).observe(document.documentElement, { attributes: true, attributeFilter: ['disabled'], subtree: true });

  window.ADspaceActs = { mark: mark, scan: sweep, glyph: svg, busy: busy, of: function (w) { var a = actOf(w); return a ? a[1] : null; } };
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
}());
