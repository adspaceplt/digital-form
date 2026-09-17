/*
 * Asking for one value, on the page.
 *
 * A browser dialog is not a control this portal has. `window.prompt` cannot be
 * styled, cannot be translated — the OK and Cancel stay in the browser's
 * language — and on a phone it is a system sheet that takes the reader off the
 * screen they were working on. It was reached for eight times anyway, because
 * it is one line of code and the right control is twenty.
 *
 * This is those twenty lines, written once. Two shapes, and which one a case
 * takes is decided by what the value IS:
 *
 *   rename(host)  the value is already on the screen — a title, a name. The
 *                 thing itself becomes editable where it sits and the button
 *                 that opened it becomes Save. Nothing moves.
 *
 *   inline(btn)   the value is not on the screen yet and one control needs it.
 *                 The field grows out of that control, which then confirms it.
 *                 This is the `.pbox` pattern the platform boxes already use.
 *
 * A third shape is deliberately NOT here: where an act has a consequence that
 * has to be stated before it is agreed to (a deletion, a withdrawal), the
 * answer is a sheet that says what will happen and then asks. That is a
 * different component and a different decision, and collapsing it into a
 * field that grows out of a button would hide exactly the part that matters.
 */
(function () {
  'use strict';

  function esc(s) {
    return String(s == null ? '' : s);
  }

  /* Edit the thing where it sits.
     `host` is the element showing the value; `btn` is what opened it and what
     now saves it. Returns nothing: the caller gets its value through `save`.

     The input is built once and kept, because rebuilding it on every open
     loses the caret and any composition in progress on an IME — which is not
     a detail on a portal whose titles are routinely Chinese. */
  function rename(host, btn, opts) {
    opts = opts || {};
    if (host._askOpen) return;

    var was = host.textContent;
    var field = document.createElement('input');
    field.type = 'text';
    field.className = 'input askfield';
    field.value = was;
    field.setAttribute('aria-label', opts.label || 'Name');
    if (opts.max) field.maxLength = opts.max;

    var wasLabel = btn.getAttribute('aria-label');
    var wasHtml = btn.innerHTML;

    function shut() {
      host._askOpen = false;
      field.remove();
      host.hidden = false;
      btn.innerHTML = wasHtml;
      if (wasLabel) btn.setAttribute('aria-label', wasLabel);
      btn.classList.remove('is-saving');
      btn.onclick = null;
      if (opts.onClose) opts.onClose();
    }

    function save() {
      var v = field.value.trim();
      if (!v) { field.focus(); return; }
      if (v === was) { shut(); return; }
      shut();
      opts.save(v);
    }

    host._askOpen = true;
    host.hidden = true;
    host.parentNode.insertBefore(field, host);
    /* The pen becomes a tick: the control that opened the edit is the one
       that closes it, so there is no second button to find and no row that
       grows by one while somebody is typing in it. */
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<path d="M20 6 9 17l-5-5"/></svg>';
    btn.setAttribute('aria-label', opts.saveLabel || 'Save name');
    btn.classList.add('is-saving');
    btn.onclick = save;

    field.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); save(); }
      else if (e.key === 'Escape') { e.preventDefault(); shut(); }
    });
    /* Leaving the field is not a decision either way, so it neither saves nor
       throws the typing away: it stays open until Enter, Escape or the tick.
       An input that saves on blur saves the half-typed name somebody left to
       go and check something. */
    field.focus();
    field.select();
  }

  /* The field grows out of the control that needs it, and that control then
     confirms it. Both ends of the width are stated, because `auto` does not
     animate; the box is the same one `.namebox` uses on the client pages. */
  function inline(btn, opts) {
    opts = opts || {};
    var box = document.createElement('span');
    box.className = 'namebox';
    btn.parentNode.insertBefore(box, btn);
    box.appendChild(btn);

    var field = document.createElement('input');
    field.type = 'text';
    field.className = 'input namebox-field';
    field.setAttribute('aria-label', opts.label || 'Value');
    if (opts.placeholder) field.placeholder = opts.placeholder;
    field.tabIndex = -1;
    box.appendChild(field);

    var asking = false;

    function open() {
      asking = true;
      box.classList.add('is-asking');
      btn.setAttribute('aria-expanded', 'true');
      field.tabIndex = 0;
      /* A seed may depend on when it is opened (the month a set is named
         after), so it may be given as a function. */
      field.value = (typeof opts.value === 'function' ? opts.value() : opts.value) || '';
      field.focus();
      field.select();
    }
    function shut() {
      asking = false;
      box.classList.remove('is-asking');
      btn.setAttribute('aria-expanded', 'false');
      field.tabIndex = -1;
      field.value = '';
    }
    function send() {
      var v = field.value.trim();
      if (!v) { field.focus(); return; }
      shut();
      opts.save(v);
    }

    field.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); send(); }
      else if (e.key === 'Escape') { e.preventDefault(); shut(); btn.focus(); }
    });

    return {
      /* One press asks, the next one sends. */
      press: function () { if (asking) send(); else open(); },
      close: shut,
      asking: function () { return asking; }
    };
  }

  /* A note somebody else will read: it opens under the control that sends it,
     which is the shape the client's own Request changes already has. A note is
     several lines, so it is a textarea and never a field that grows sideways. */
  function note(after, opts) {
    opts = opts || {};
    var box = document.createElement('div');
    box.className = 'changebox asknote';
    box.innerHTML =
      '<textarea class="textarea" rows="3"></textarea>' +
      '<div class="changebox-actions">' +
        '<button class="btn btn-sm" type="button" data-a="cancel">Cancel</button>' +
        '<button class="btn btn-sm btn-primary" type="button" data-a="send"></button>' +
      '</div>';
    var ta = box.querySelector('textarea');
    ta.setAttribute('aria-label', opts.label || 'Note');
    ta.placeholder = opts.placeholder || '';
    box.querySelector('[data-a="send"]').textContent = opts.send || 'Send';
    after.parentNode.insertBefore(box, after.nextSibling);

    function shut() { box.classList.remove('is-open'); ta.value = ''; }
    box.querySelector('[data-a="cancel"]').addEventListener('click', shut);
    box.querySelector('[data-a="send"]').addEventListener('click', function () {
      var v = ta.value.trim();
      if (!v) { ta.focus(); return; }
      shut();
      opts.save(v);
    });
    ta.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { e.preventDefault(); shut(); }
    });

    return {
      open: function () { box.classList.add('is-open'); ta.focus(); },
      close: shut,
      open_: function () { return box.classList.contains('is-open'); }
    };
  }

  window.ADspaceAsk = { rename: rename, inline: inline, note: note, esc: esc };
})();
