/*
 * Copied, said one way.
 *
 * Four buttons copied something to the clipboard and each said so differently:
 * one swapped its own label, one swapped a span inside itself, one wrote a
 * message into a .msg line under the panel, and one tinted itself. A person
 * who has learned what Copy link does on Content Review should not have to
 * learn it again on a campaign, so the feedback lives here and every button
 * borrows it.
 *
 * An icon-only button has no label to swap, so it takes the tick and the
 * accent tint for the same moment instead. Either way the control answers
 * within Doherty's 400ms and puts itself back.
 */
(function () {
  var HOLD = 1600;

  function label(btn) {
    // Some buttons carry their words in a span beside an icon.
    var span = btn.querySelector('span');
    return span || btn;
  }

  function say(btn, word) {
    var el = label(btn);
    var was = btn.getAttribute('data-copy-was');
    if (was === null) {
      was = el.textContent;
      btn.setAttribute('data-copy-was', was);
    }
    if (el === btn && !btn.textContent.trim()) {
      // Icon only: nothing to swap, so the button marks itself.
      btn.classList.add('is-done');
      clearTimeout(btn._copyT);
      btn._copyT = setTimeout(function () { btn.classList.remove('is-done'); }, HOLD);
      return;
    }
    el.textContent = word;
    btn.classList.add('is-done');
    clearTimeout(btn._copyT);
    btn._copyT = setTimeout(function () {
      el.textContent = btn.getAttribute('data-copy-was');
      btn.removeAttribute('data-copy-was');
      btn.classList.remove('is-done');
    }, HOLD);
  }

  /* The old fallback for a refused clipboard was `window.prompt`, which put a
     browser dialog with an OK and a Cancel in front of somebody who had
     pressed a button labelled Copy: two more steps, and nothing copied at the
     end of them unless they also selected the text themselves. It fired far
     more often than "outside a secure context" suggests — the Clipboard API
     rejects whenever the document is not focused, which is every press made
     while a devtools panel or another window had focus.

     `document.execCommand('copy')` over a hidden textarea is the older path.
     It needs no permission, works in every browser this portal supports, and
     is synchronous, so it copies where the promise refused. It only runs
     inside the click, which is the user gesture both paths require. */
  function legacy(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    /* Off screen rather than hidden: a field with `display: none` has nothing
       to select, and one at the top of the page scrolls it there. */
    ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;top:0;left:-9999px;opacity:0';
    document.body.appendChild(ta);
    var ok = false;
    try {
      ta.select();
      ta.setSelectionRange(0, ta.value.length);
      ok = document.execCommand('copy');
    } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }

  function copy(btn, text, word) {
    var done = function () { say(btn, word || 'Copied'); };
    /* Whatever happens, the button answers: a control that says nothing when
       pressed reads as broken, and this portal has no browser dialogs. */
    var fell = function () { say(btn, legacy(text) ? (word || 'Copied') : 'Press Ctrl C'); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(fell);
    } else {
      fell();
    }
  }

  window.ADspaceCopy = { to: copy };
})();
