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

  /* Clipboard access is refused outside a secure context and in some embedded
     browsers, so a refusal falls back to a prompt the person can copy out of
     rather than leaving the button looking broken. */
  function copy(btn, text, word) {
    var done = function () { say(btn, word || 'Copied'); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () {
        window.prompt('Copy this link', text);
      });
    } else {
      window.prompt('Copy this link', text);
    }
  }

  window.ADspaceCopy = { to: copy };
})();
