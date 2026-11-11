/* The code from an email, typed as one box a digit (the user, 2026-11-11:
   "can the sign in code do the 8 digits fields"). One field stays the
   value, the page's own `input[data-otp]`: it sits over a row of boxes,
   unseen, so typing, pasting, the iPhone's code from Mail and a screen
   reader all meet a plain field; the boxes draw what it holds. The number
   of digits is `ADSPACE_CONFIG.signCodeDigits` (Supabase's OTP length).
   A whole code arriving (the last digit typed, a paste, the iPhone's code)
   presses the field's Enter, which each page answers by checking it. */
(function () {
  'use strict';
  function digits() {
    var n = +((window.ADSPACE_CONFIG || {}).signCodeDigits);
    return n >= 4 && n <= 10 ? n : 8;
  }
  var DESC = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');

  function mount(inp) {
    if (!inp || inp.__otp) return;
    var k = digits();
    inp.__otp = true;
    inp.maxLength = k;
    inp.removeAttribute('placeholder');
    var box = document.createElement('div');
    box.className = 'otp';
    box.style.setProperty('--otp-n', k);
    inp.parentNode.insertBefore(box, inp);
    var cells = document.createElement('div');
    cells.className = 'otp-cells';
    cells.setAttribute('aria-hidden', 'true');
    for (var i = 0; i < k; i++) {
      var s = document.createElement('span');
      s.className = 'otp-cell';
      cells.appendChild(s);
    }
    box.appendChild(cells);
    box.appendChild(inp);
    inp.classList.add('otp-input');
    var last = '';
    function paint() {
      var raw = DESC.get.call(inp), v = raw.replace(/\D/g, '').slice(0, k);
      if (v !== raw) DESC.set.call(inp, v);
      var on = document.activeElement === inp;
      for (var i = 0; i < k; i++) {
        var c = cells.children[i];
        c.textContent = v.charAt(i);
        c.classList.toggle('is-on', on && i === Math.min(v.length, k - 1));
      }
      box.classList.toggle('is-invalid', inp.getAttribute('aria-invalid') === 'true');
      box.hidden = inp.hidden;
      return v;
    }
    /* A page that empties the field (a new code sent) draws the boxes empty. */
    Object.defineProperty(inp, 'value', {
      configurable: true,
      get: function () { return DESC.get.call(inp); },
      set: function (x) { DESC.set.call(inp, x); last = paint(); }
    });
    inp.addEventListener('input', function () {
      var v = paint();
      if (v.length === k && v !== last) {
        last = v;
        inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
      }
      last = v;
    });
    ['focus', 'blur', 'select', 'keyup', 'click'].forEach(function (e) { inp.addEventListener(e, paint); });
    /* Hiding the field hides its boxes. */
    new MutationObserver(paint).observe(inp, { attributes: true, attributeFilter: ['hidden', 'aria-invalid'] });
    last = paint();
  }

  function all() { Array.prototype.forEach.call(document.querySelectorAll('input[data-otp-boxes]'), mount); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', all); else all();
  window.ADspaceOtp = { mount: mount, digits: digits };
})();
