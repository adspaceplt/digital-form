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
  var P = {
    plus: '<path d="M12 5v14M5 12h14"/>',
    pen: '<path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17z"/><path d="M14.5 6.5l3 3"/>',
    send: '<path d="M21 3 10.5 13.5"/><path d="M21 3l-6.8 18-3.7-7.5L3 9.8z"/>',
    hide: '<path d="m3 3 18 18"/><path d="M10.6 5.1A9.6 9.6 0 0 1 12 5c5 0 9 4.5 9 7a12 12 0 0 1-2.4 3.4"/>' +
      '<path d="M6.5 7.6C4.3 9.1 3 11.2 3 12c0 2.5 4 7 9 7a9.7 9.7 0 0 0 4.2-1"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
    file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M12 12v6M9 15l3 3 3-3"/>',
    copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/>',
    out: '<path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>'
  };
  /* [the words, the mark, after the words] */
  var ACTS = [
    [/^Publish$/, 'send'], [/^Unpublish$/, 'hide'],
    [/^Edit$/, 'pen'],
    [/^Download$/, 'file'],
    [/^Copy( link| text| title)?$/, 'copy'],
    [/^(Preview|Preview PDF)$/, 'out', true],
    [/^(Add|New) \S/, 'plus']
  ];
  var COMMIT = 'form, .sheet-foot, .askcard, .qform-acts, .changebox-actions, .zone-actions, .filearm-acts, .namebox, .undobar, .cover, .approve-row';
  function svg(name) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" data-act="' +
      name + '">' + P[name] + '</svg>';
  }
  function actOf(words) {
    for (var i = 0; i < ACTS.length; i++) if (ACTS[i][0].test(words)) return ACTS[i];
    return null;
  }
  function commit(b) {
    if (b.type === 'submit' || b.closest(COMMIT)) return true;
    var p = b.parentElement;
    return Boolean(p && p.querySelector('input:not([type=hidden]):not([type=checkbox]):not([type=radio]), select, textarea'));
  }
  function mark(b) {
    if (!b || !b.classList || !b.classList.contains('btn') || b.classList.contains('btn-quiet')) return;
    var own = b.querySelector('svg:not([data-act]), img');
    if (own) return;
    var given = b.querySelector('svg[data-act]');
    var words = (b.textContent || '').replace(/\s+/g, ' ').trim();
    var act = words && !commit(b) ? actOf(words) : null;
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

  window.ADspaceActs = { mark: mark, glyph: svg, busy: busy, of: function (w) { var a = actOf(w); return a ? a[1] : null; } };
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
}());
