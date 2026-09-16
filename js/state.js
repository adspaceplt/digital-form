/* The only copy of how a list says it is loading, has nothing in it, or could
   not be read.

   Three pages had written these three states four different ways: a dashed
   box saying "Loading…", a `.msg.err` line under a heading with an empty card
   area beside it, and — the one that actually cost somebody time — a failed
   read reported as an empty list, so "No content sets." and "0 posts" were
   printed over a network fault and sent people to build records that were
   already there. A read that failed is not an empty list, and saying so once
   is the only way the whole console can agree on it. */
(function () {
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  /* The shape of what is coming, rather than the word for it. */
  function skeleton(box, n) {
    if (!box) return;
    var s = '';
    for (var i = 0; i < (n || 3); i++) s += '<div class="skel-row"></div>';
    box.innerHTML = '<div class="softpanel"><div class="skel">' + s + '</div></div>';
  }

  /* What could not be read, what the database said about it, and the one
     thing that helps. */
  function failLine(box, what, why, again) {
    if (!box) return;
    box.innerHTML = '<div class="softpanel"><div class="errline">' +
      '<b>' + esc(what) + ' could not be loaded.</b>' +
      (why ? '<span>' + esc(why) + '</span>' : '') +
      (again ? '<button class="btn btn-sm" data-a="retry" type="button">Try again</button>' : '') +
      '</div></div>';
    var go = box.querySelector('[data-a="retry"]');
    if (go && again) go.addEventListener('click', again);
  }

  /* Nothing there, and nothing left after a filter, are two answers. Each
     carries its own way out. */
  function emptyLine(box, text, action, onAction) {
    if (!box) return;
    box.innerHTML = '<div class="softpanel"><div class="emptyline"><b>' + esc(text) + '</b>' +
      (action ? '<button class="btn btn-sm" data-a="go" type="button">' + esc(action) + '</button>' : '') +
      '</div></div>';
    var go = box.querySelector('[data-a="go"]');
    if (go && onAction) go.addEventListener('click', onAction);
  }

  /* The two characters a record wears when we hold no logo for it. Both
     workspaces draw the same `.rec-mark`, so the reading lives once: a Chinese
     name is one word of two or three characters, so the first two characters
     are the mark; a Latin name gives the first letter of each of the first two
     words that actually begin with a letter, or "Dale & Cecil" comes out as
     "D&" and "S P Setia" as "SP". Two copies of this drifted the moment one
     screen learned about the ampersand and the other did not. */
  function initials(name) {
    var parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    if (/[\u3400-\u9fff]/.test(parts[0])) return parts[0].slice(0, 2);
    var words = parts.filter(function (w) { return /^[A-Za-z]/.test(w); });
    if (!words.length) return parts[0].charAt(0).toUpperCase();
    if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
    return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
  }

  window.ADspaceState = {
    skeleton: skeleton, failLine: failLine, emptyLine: emptyLine, initials: initials
  };
}());
