/*
 * The name a decision is recorded under — asked in place, once.
 *
 * Both client-facing decisions (a post on /review/, a creator's draft on
 * /creators/) record who approved them, and both used `window.prompt` to ask.
 * A browser prompt is the one shape this portal's own rules already rule out
 * for something that has to be typed: it cannot be styled, it cannot be
 * translated — the OK and Cancel stay in the browser's language, so a Chinese
 * reader got half a dialog — and on a phone it is a system sheet that takes
 * the reader off the page they were deciding on.
 *
 * So the field grows out of the button that needs it, which is the pattern
 * `.pbox` already uses for a profile link: a control that creates a need
 * answers it in place. Approve becomes the confirm, Escape closes it, and a
 * name already given is never asked for twice.
 *
 * One copy, because both pages keep the name under the same key and ask the
 * same question. Four buttons each saying "Copied" differently is what put
 * js/copy.js here; two pages each asking for a name differently is the same
 * fault one step earlier.
 */
(function () {
  'use strict';

  var KEY = 'adspace_reviewer';

  function known() {
    try { return (localStorage.getItem(KEY) || '').trim(); } catch (e) { return ''; }
  }
  function keep(name) {
    try { localStorage.setItem(KEY, name); } catch (e) {}
    tell();
  }
  /* Forget this device's name (2026-10-08): a shared computer, or a name
     typed wrong, is put right here. Decisions already made keep the name
     they were made under. */
  function forget() {
    try { localStorage.removeItem(KEY); } catch (e) {}
    tell();
  }
  var watchers = [];
  function tell() { watchers.forEach(function (fn) { try { fn(known()); } catch (e) {} }); }

  /* One quiet line naming who this device decides as, with Change and
     Forget (the user, 2026-10-08: "one wrong typo name can be removed").
     Drawn only while a name is held; Change opens the name in place. */
  function whoLine(host, w, after) {
    if (!host) return;
    var line = document.createElement('p');
    line.className = 'decide-as';
    /* Its own row under the card's head (`after`), the card's full width,
       so a phone never squeezes it beside the state. */
    if (after && after.parentNode === host) host.insertBefore(line, after.nextSibling);
    else host.appendChild(line);
    function esc(x) { return String(x).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
    function paint() {
      var name = known();
      line.hidden = !name;
      if (!name) { line.innerHTML = ''; return; }
      line.innerHTML = '<span class="decide-as-who">' + esc(w.as) + ' <b>' + esc(name) + '</b></span>' +
        '<button class="linkbtn" type="button" data-a="change">' + esc(w.change) + '</button>' +
        '<button class="linkbtn" type="button" data-a="forget">' + esc(w.forget) + '</button>';
      line.querySelector('[data-a="change"]').addEventListener('click', edit);
      line.querySelector('[data-a="forget"]').addEventListener('click', function () { forget(); });
    }
    function edit() {
      line.innerHTML = '<input class="input input-sm decide-as-field" type="text" autocomplete="name" aria-label="' + esc(w.name) + '">' +
        '<button class="btn btn-sm btn-primary" type="button" data-a="save">' + esc(w.save) + '</button>' +
        '<button class="btn btn-sm btn-quiet" type="button" data-a="cancel">' + esc(w.cancel) + '</button>';
      var f = line.querySelector('input');
      f.value = known();
      f.focus(); f.select();
      function save() { var v = (f.value || '').trim(); if (!v) { f.focus(); return; } keep(v); }
      line.querySelector('[data-a="save"]').addEventListener('click', save);
      line.querySelector('[data-a="cancel"]').addEventListener('click', paint);
      f.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); save(); }
        else if (e.key === 'Escape') { e.preventDefault(); paint(); }
      });
    }
    watchers.push(paint);
    paint();
    return { paint: paint, words: function (nw) { w = nw; paint(); } };
  }

  /* Wraps `btn` in a box the field can grow inside, and hands back the two
     things a caller needs: ask for the name when there isn't one, and shut
     everything while a request is in flight.

     `words` carries { label, placeholder, needed }, because the two pages are
     bilingual and the dictionary is theirs, not this file's. */
  function nameBox(btn, words, say) {
    var row = btn.parentNode;
    var box = document.createElement('span');
    box.className = 'namebox';
    row.insertBefore(box, btn);
    box.appendChild(btn);

    var field = document.createElement('input');
    field.className = 'input namebox-field';
    field.type = 'text';
    field.autocomplete = 'name';
    field.setAttribute('aria-label', words.label);
    field.placeholder = words.placeholder;
    /* Out of the tab order while it is shut. A field nobody can see is not a
       stop on the way to Request changes. */
    field.tabIndex = -1;
    box.appendChild(field);

    var asking = false;
    var run = null;

    function open() {
      asking = true;
      box.classList.add('is-asking');
      row.classList.add('is-asking');
      btn.setAttribute('aria-expanded', 'true');
      field.tabIndex = 0;
      field.focus();
    }
    function close() {
      asking = false;
      run = null;
      box.classList.remove('is-asking');
      row.classList.remove('is-asking');
      btn.setAttribute('aria-expanded', 'false');
      field.tabIndex = -1;
      field.value = '';
    }
    function confirm() {
      var name = (field.value || '').trim();
      if (!name) { if (say) say(words.needed, true); field.focus(); return; }
      keep(name);
      var go = run;
      close();
      if (say) say('');
      if (go) go(name);
    }

    /* Enter sends it, because a field with one value and a button beside it is
       a form in every way but the tag. Escape puts the row back. */
    field.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); confirm(); }
      else if (e.key === 'Escape') { e.preventDefault(); close(); btn.focus(); }
    });

    return {
      /* The whole point: a name we already hold never opens anything, so the
         client who has approved a post before just presses Approve. */
      need: function (then) {
        var name = known();
        if (name) { then(name); return; }
        if (asking) { confirm(); return; }
        run = then;
        open();
      },
      close: close,
      asking: function () { return asking; },
      lock: function (on) { field.disabled = on; }
    };
  }

  window.ADspaceDecide = { KEY: KEY, known: known, keep: keep, forget: forget, whoLine: whoLine, nameBox: nameBox };
})();
