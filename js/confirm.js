/* ADspaceConfirm — asking before an act, on the page.
 *
 * `js/ask.js` is the one copy of asking for ONE VALUE, and it deliberately
 * holds no sheet: where a value is all that is wanted, a field growing out of
 * the control that needs it is the lighter shape. This file is the other half,
 * and the portal's own rule says which: where an act has a CONSEQUENCE that
 * must be stated before it is agreed to, the question is a sheet, because a
 * field growing out of a button hides exactly the part that matters.
 *
 * Until now that rule was honoured in the console by `window.confirm` and
 * `window.prompt` thirty-one times over — a browser dialog, which this portal
 * has already ruled out twice in writing: it cannot be styled, it cannot be
 * translated (the buttons stay in the browser's language), and on a phone it
 * is a system sheet that takes the reader off the page they are acting on. The
 * client-facing pages were cleared of them in two earlier batches; this is the
 * console's.
 *
 * Nothing new is invented. The sheet is `.sheet` > `.sheet-card`, the same
 * component the Letter of Offer's void and delete already use, built once and
 * kept, so every question in the console is one shape. What it adds over a
 * browser dialog: the consequence reads as a line rather than as a second
 * paragraph of the title, the destructive answer is red and the way out is
 * quiet, Escape and the scrim both cancel, focus is trapped and handed back to
 * the control that opened it, and a value can be asked for in the same breath
 * as the question rather than in a second dialog after it.
 *
 *   ADspaceConfirm.ask({ title, body, go, tone }, onYes)
 *   ADspaceConfirm.ask({ …, field: { label, placeholder, rows, required } }, onYes)
 *   ADspaceConfirm.ask({ …, field: { …, match: 'HKL LIM' } }, onYes)
 *   ADspaceConfirm.ask({ …, field: { …, choices: [['a','A'], …] } }, onYes)
 *
 * `onYes` is called with the field's value where there is one and with `true`
 * where there is not. Cancel calls nothing: walking away is not a decision.
 */
(function () {
  'use strict';

  var sheet = null, card = null, elTitle, elBody, elFields,
      elGo, elCancel, elClose, elMsg;
  var open = false, cb = null, opts = null, lastFocus = null;
  /* One row a field: { spec, input }. A question asks for nothing, for one
     value, or — where the act needs two things stated together, as setting a
     service line by hand needs the state and the reason — for a short list of
     them. Two sheets in a row is the fault this file exists to remove. */
  var rows = [];

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function build() {
    if (sheet) return;
    sheet = el('div', 'sheet');
    sheet.id = 'askSheet';
    sheet.hidden = true;

    card = el('div', 'sheet-card askcard');
    card.setAttribute('role', 'dialog');
    card.setAttribute('aria-modal', 'true');
    card.setAttribute('aria-labelledby', 'askSheetTitle');

    var head = el('div', 'sheet-head');
    elTitle = el('h3');
    elTitle.id = 'askSheetTitle';
    elClose = el('button', 'iconbtn');
    elClose.type = 'button';
    elClose.setAttribute('aria-label', 'Close');
    elClose.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" '
      + 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
      + '<path d="M6 6l12 12M18 6 6 18"/></svg>';
    head.appendChild(elTitle);
    head.appendChild(elClose);

    var body = el('div', 'sheet-body');
    elBody = el('p', 'askline');
    elFields = el('div', 'askfields');
    elFields.hidden = true;
    body.appendChild(elBody);
    body.appendChild(elFields);

    var foot = el('div', 'sheet-foot askfoot');
    elGo = el('button', 'btn btn-primary');
    elGo.type = 'button';
    elGo.id = 'askGo';
    elCancel = el('button', 'btn btn-quiet', 'Cancel');
    elCancel.type = 'button';
    elCancel.id = 'askCancel';
    foot.appendChild(elGo);
    foot.appendChild(elCancel);

    elMsg = el('div', 'msg');

    card.appendChild(head);
    card.appendChild(body);
    card.appendChild(foot);
    card.appendChild(elMsg);
    sheet.appendChild(card);
    document.body.appendChild(sheet);

    elCancel.addEventListener('click', shut);
    elClose.addEventListener('click', shut);
    elGo.addEventListener('click', go);
    /* The scrim cancels; a press inside the card does not. */
    sheet.addEventListener('mousedown', function (e) { if (e.target === sheet) shut(); });
    document.addEventListener('keydown', key, true);
  }

  /* Focus is trapped while the sheet is open, and handed back to the control
     that opened it on close: a question that steals focus and does not return
     it leaves a keyboard somewhere nobody chose. */
  function focusables() {
    return Array.prototype.filter.call(
      card.querySelectorAll('button, input, select, textarea, [href]'),
      function (n) { return !n.disabled && n.offsetParent !== null; });
  }

  function key(e) {
    if (!open) return;
    if (e.key === 'Escape') { e.preventDefault(); shut(); return; }
    if (e.key === 'Enter' && e.target !== elCancel && e.target !== elClose
        && e.target.tagName !== 'TEXTAREA') {
      e.preventDefault(); go(); return;
    }
    if (e.key !== 'Tab') return;
    var list = focusables();
    if (!list.length) return;
    var first = list[0], last = list[list.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }

  function say(text, tone) {
    elMsg.textContent = text || '';
    elMsg.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }

  function valueOf(r) {
    var raw = r.input.value == null ? '' : String(r.input.value);
    return r.input.tagName === 'SELECT' ? raw : raw.trim();
  }

  function go() {
    if (!open) return;
    var i, r, v;
    for (i = 0; i < rows.length; i++) {
      r = rows[i]; v = valueOf(r);
      if (r.spec.required !== false && !v) {
        say(r.spec.need || 'This is required.');
        r.input.focus();
        return;
      }
      if (r.spec.match && v.toLowerCase() !== String(r.spec.match).toLowerCase()) {
        say(r.spec.mismatch || 'That does not match.');
        r.input.focus();
        if (r.input.select) r.input.select();
        return;
      }
    }
    var fn = cb, arg;
    if (!rows.length) arg = true;
    else if (rows.length === 1 && !rows[0].spec.name) arg = valueOf(rows[0]);
    else {
      arg = {};
      rows.forEach(function (x, n) { arg[x.spec.name || ('f' + n)] = valueOf(x); });
    }
    shut();
    if (fn) fn(arg);
  }

  function shut() {
    if (!open) return;
    open = false; cb = null; opts = null;
    sheet.hidden = true;
    document.body.classList.remove('is-locked');
    if (lastFocus && lastFocus.focus) { try { lastFocus.focus(); } catch (e) {} }
    lastFocus = null;
  }

  function ask(o, onYes) {
    build();
    o = o || {};
    /* One question at a time. A second ask while one is open replaces it, so
       two sheets can never stack with the older one unreachable behind. */
    open = true; opts = o; cb = onYes || null;
    lastFocus = document.activeElement;

    elTitle.textContent = o.title || 'Confirm';
    elBody.textContent = o.body || '';
    elBody.hidden = !o.body;
    say('');

    elGo.textContent = o.go || 'Confirm';
    elGo.className = 'btn ' + (o.tone === 'danger' ? 'btn-danger'
                             : o.tone === 'warn' ? 'btn-warn' : 'btn-primary');
    elGo.id = 'askGo';
    /* `cancel: false` is a refusal being reported rather than a question being
       asked: there is only one thing to do with it, and a Cancel beside Close
       would be two words for that one thing. */
    elCancel.hidden = o.cancel === false;
    elCancel.textContent = o.cancel || 'Cancel';

    /* The fields are rebuilt rather than reused, because the same sheet asks
       for a reason on one press and a state and a reason on the next. */
    elFields.innerHTML = '';
    rows = [];
    var specs = o.fields || (o.field ? [o.field] : []);
    elFields.hidden = !specs.length;
    specs.forEach(function (f, n) {
      var id = 'askSheetField' + n;
      var wrap = el('div', 'askfield');
      var lab = el('label', 'field-label', f.label || 'Reason');
      lab.setAttribute('for', id);
      var input;
      if (f.choices) {
        input = el('select', 'select');
        f.choices.forEach(function (c) {
          var op = el('option', null, c[1]);
          op.value = c[0];
          input.appendChild(op);
        });
      } else if (f.rows) {
        input = el('textarea', 'input');
        input.rows = f.rows;
      } else {
        input = el('input', 'input');
        input.type = 'text';
        input.autocomplete = 'off';
        input.spellcheck = false;
      }
      input.id = id;
      if (f.placeholder) input.placeholder = f.placeholder;
      if (f.value != null) input.value = f.value;
      wrap.appendChild(lab);
      wrap.appendChild(input);
      elFields.appendChild(wrap);
      rows.push({ spec: f, input: input });
    });

    sheet.hidden = false;
    /* A destructive question opens on the way out, not on the act: the answer
       that costs nothing is the one a stray Enter should land on. Where a
       value is wanted the field takes focus, because that is the next thing
       to do either way. */
    var land = (rows[0] && rows[0].input) || (o.tone === 'danger' ? elCancel : elGo);
    setTimeout(function () { try { land.focus(); } catch (e) {} }, 0);
  }

  window.ADspaceConfirm = { ask: ask, close: shut };
}());
