/*
 * namecard.js — a colleague's digital namecard (ADspaceCard), drawn the same
 * way on its public page (/card/?k=…) and in the console's My namecard.
 *
 * The card is the signboard's lockup on a #f5f5f5 card: ADspace in Optima
 * over the tagline in Slate Regular, the tagline about 1.64 times the
 * wordmark's width (the user's signboard, 2026-10-03). It turns over to the
 * person and the office, and its front turns into a QR code that opens the
 * same page on somebody else's phone. Save contact hands the phone a vCard.
 *
 * The card's words are the colleague's own row (name, position, mobile, the
 * card's email) and the office's (ADSPACE_ORG): one source each.
 */
(function () {
  var ORG = window.ADSPACE_ORG || {};

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  /* A number as Malaysia and Singapore write it with the country code:
     012-345 6789 → +60 12-345 6789; 0112345 6789 → +60 11-2345 6789;
     60187625233 → +60 18-762 5233; 07-123 4567 → +60 7-123 4567;
     a Singapore eight → +65 8123 4567. Anything else keeps its digits. */
  function digits(raw) {
    var d = String(raw || '').replace(/\D/g, '');
    if (!d) return '';
    if (/^0\d/.test(d)) d = '6' + d;
    else if (/^[689]\d{7}$/.test(d)) d = '65' + d;
    return d;
  }
  function phone(raw) {
    var d = digits(raw);
    if (!d) return '';
    var m;
    if ((m = /^60(1[0-9])(\d{3,4})(\d{4})$/.exec(d))) return '+60 ' + m[1] + '-' + m[2] + ' ' + m[3];
    if ((m = /^60([3-9])(\d{3,4})(\d{4})$/.exec(d))) return '+60 ' + m[1] + '-' + m[2] + ' ' + m[3];
    if ((m = /^65(\d{4})(\d{4})$/.exec(d))) return '+65 ' + m[1] + ' ' + m[2];
    return '+' + d;
  }

  function address() { return String(ORG.address || '').split('\n').join(', '); }
  function site() { return String(ORG.website || '').replace(/^https?:\/\//, ''); }
  function link(key) { return location.origin + '/card/?k=' + encodeURIComponent(key || ''); }

  /* vCard 3.0, the form every phone's contacts open. */
  function vcf(card) {
    var v = function (s) { return String(s || '').replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/([,;])/g, '\\$1'); };
    var lines = ['BEGIN:VCARD', 'VERSION:3.0',
      'N:;' + v(card.name) + ';;;', 'FN:' + v(card.name), 'ORG:ADspace'];
    if (card.designation) lines.push('TITLE:' + v(card.designation));
    if (card.mobile) lines.push('TEL;TYPE=CELL:+' + digits(card.mobile));
    if (ORG.phone) lines.push('TEL;TYPE=WORK:+' + digits(ORG.phone));
    if (card.email) lines.push('EMAIL;TYPE=WORK:' + v(card.email));
    if (ORG.website) lines.push('URL:https://' + site());
    if (ORG.address) lines.push('ADR;TYPE=WORK:;;' + v(address()) + ';;;;');
    lines.push('END:VCARD');
    return lines.join('\r\n') + '\r\n';
  }
  function save(card) {
    var blob = new Blob([vcf(card)], { type: 'text/vcard;charset=utf-8' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = String(card.name || 'ADspace').replace(/[\\/:*?"<>|]+/g, '') + '.vcf';
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  var TURN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 0 1 15.5-6.2L21 8M21 3v5h-5M21 12a9 9 0 0 1-15.5 6.2L3 16M3 21v-5h5"/></svg>';
  var QR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 20h4v-3"/></svg>';

  function row(label, value, href, cls) {
    return '<a class="nc-row' + (cls ? ' ' + cls : '') + '" href="' + esc(href) + '"' +
      (/^https?:/.test(href) ? ' target="_blank" rel="noopener"' : '') + '>' +
      '<span class="nc-label">' + esc(label) + '</span><span class="nc-value">' + esc(value) + '</span></a>';
  }
  function rows(card) {
    return (card.mobile ? row('Mobile', phone(card.mobile), 'tel:+' + digits(card.mobile)) : '') +
      (ORG.phone ? row('Office', phone(ORG.phone), 'tel:+' + digits(ORG.phone)) : '') +
      (card.email ? row('Email', card.email, 'mailto:' + card.email) : '') +
      (ORG.website ? row('Website', site(), 'https://' + site()) : '') +
      (ORG.address ? row('Address', address(), ORG.map || ('https://maps.google.com/?q=' + encodeURIComponent(address())), 'nc-row-long') : '');
  }

  function html(card, key) {
    var wa = card.mobile ? 'https://wa.me/' + digits(card.mobile) : '';
    return '<div class="nc-stage"><div class="nc-flip">' +
      '<section class="nc-face nc-front" aria-label="Card front">' +
        '<div class="nc-lock"><div class="nc-lock-in"><span class="nc-word">ADspace</span>' +
          '<span class="nc-tag">advertising | marketing | branding</span></div></div>' +
        '<div class="nc-qr" aria-label="QR code to this card">' +
          '<span class="nc-word nc-word-sm">ADspace</span>' +
          '<div class="nc-qrbox" data-nc="qrbox"></div>' +
          '<b class="nc-qrname">' + esc(card.name) + '</b>' +
          '<span class="nc-qrlink">' + esc(link(key).replace(/^https?:\/\//, '')) + '</span></div>' +
      '</section>' +
      '<section class="nc-face nc-back" aria-label="Contact details">' +
        '<span class="nc-word nc-word-sm">ADspace</span>' +
        '<div class="nc-who"><b class="nc-name">' + esc(card.name) + '</b>' +
          (card.designation ? '<span class="nc-post">' + esc(card.designation) + '</span>' : '') + '</div>' +
        '<div class="nc-rows" data-nc="rows">' + rows(card) + '</div>' +
        '<div class="nc-acts' + (wa ? '' : ' is-one') + '">' +
          '<button class="nc-pill nc-pill-ink" type="button" data-nc="save">Save contact</button>' +
          (wa ? '<a class="nc-pill" data-nc="wa" href="' + esc(wa) + '" target="_blank" rel="noopener">WhatsApp</a>' : '') +
        '</div>' +
      '</section>' +
    '</div></div>' +
    '<div class="nc-ctl">' +
      '<button class="nc-pill" type="button" data-nc="turn">' + TURN + '<span data-nc="turnword">Contact details</span></button>' +
      '<button class="nc-pill" type="button" data-nc="qr" aria-pressed="false">' + QR + 'QR code</button>' +
    '</div>';
  }

  /* Draws the card into host (an element with class nc). The hidden face is
     `inert`, so a keyboard never lands on a link drawn backwards. */
  function mount(host, card, key) {
    var state = { back: false, qr: false, card: card };
    host.classList.add('nc');
    host.innerHTML = html(card, key);
    var q = function (n) { return host.querySelector('[data-nc="' + n + '"]'); };
    var front = host.querySelector('.nc-front'), back = host.querySelector('.nc-back');
    function paint() {
      host.classList.toggle('is-back', state.back);
      host.classList.toggle('is-qr', state.qr && !state.back);
      front.inert = state.back; back.inert = !state.back;
      front.setAttribute('aria-hidden', String(state.back));
      back.setAttribute('aria-hidden', String(!state.back));
      q('turnword').textContent = state.back ? 'Front' : 'Contact details';
      q('qr').setAttribute('aria-pressed', String(state.qr && !state.back));
      if (state.qr && !state.back && !q('qrbox').hasChildNodes() && window.QRCode) {
        new window.QRCode(q('qrbox'), { text: link(key), width: 384, height: 384,
          colorDark: '#1a1a1a', colorLight: '#ffffff', correctLevel: window.QRCode.CorrectLevel.M });
      }
    }
    /* The lockup in golden proportion to the card it is on: the wordmark
       runs the card's width over φ², and the tagline, set at 0.46 of the
       wordmark's size (the signboard), runs it over φ. Optima sets ADspace
       about 3.9 times its size wide. */
    var stage = host.querySelector('.nc-stage');
    var fit = function () {
      var w = stage.getBoundingClientRect().width;
      if (w) host.style.setProperty('--nc-sw', (Math.round(w / 2.618 / 3.9 * 10) / 10) + 'px');
    };
    if (window.ResizeObserver && !host.__ncFit) {
      host.__ncFit = new ResizeObserver(fit);
    }
    if (host.__ncFit) host.__ncFit.observe(stage);
    fit();
    /* Landscape at a desk, portrait on a phone, following the window. */
    var wide = window.matchMedia ? window.matchMedia('(min-width: 760px)') : null;
    var lie = function () { host.classList.toggle('is-land', !!(wide && wide.matches)); };
    lie();
    if (wide && !host.__ncLie) {
      host.__ncLie = true;
      if (wide.addEventListener) wide.addEventListener('change', lie); else if (wide.addListener) wide.addListener(lie);
    }
    q('turn').addEventListener('click', function () { state.back = !state.back; paint(); });
    q('qr').addEventListener('click', function () { state.qr = !(state.qr && !state.back); state.back = false; paint(); });
    q('save').addEventListener('click', function () { save(state.card); });
    paint();
    return {
      /* The console's sheet repaints the rows as the fields are typed. */
      update: function (next) {
        state.card = next;
        q('rows').innerHTML = rows(next);
        var wa = q('wa');
        if (wa && next.mobile) wa.href = 'https://wa.me/' + digits(next.mobile);
        host.querySelector('.nc-acts').classList.toggle('is-one', !next.mobile);
        if (wa) wa.hidden = !next.mobile;
      },
      link: link(key)
    };
  }

  /* ---- The console's My namecard --------------------------------------
     The person's own card as a client sees it, the address to hand over,
     and the two facts on it they keep themselves (namecard_save_mine). */
  var SAID = {
    'bad-mobile': 'Enter a mobile number of 8 to 15 digits.',
    'bad-email': 'Enter a valid email.',
    'not-team': 'Not allowed.'
  };
  function $(id) { return document.getElementById(id); }
  function say(text, tone) { var m = $('mycMsg'); if (m) { m.textContent = text || ''; m.className = 'msg' + (tone ? ' ' + tone : ''); } }
  function openMine(opener) {
    var API = window.ADspaceAPI, db = API && API.client;
    if (!db || !$('mycSheet')) return;
    say('');
    db.rpc('namecard_mine').then(function (r) {
      var d = r.data || {};
      if (r.error || d.error || !d.key) {
        var t = r.error ? String(r.error.message || '') : '';
        say(/function|schema cache/i.test(t) ? 'This needs a database update.' : 'Unable to load. Please try again.', 'err');
        $('mycPreview').innerHTML = '';
        $('mycUrl').textContent = '';
        window.ADspaceSheet.show($('mycSheet'), { opener: opener });
        return;
      }
      var cardOf = function () {
        return { name: d.name, designation: d.designation,
                 mobile: ($('mycMobile').value || '').trim() || null,
                 email: ($('mycEmail').value || '').trim() || d.email };
      };
      $('mycMobile').value = d.mobile || '';
      $('mycEmail').value = d.card_email || '';
      $('mycEmail').placeholder = d.email || 'email@adspacestudios.com';
      var handle = mount($('mycPreview'), cardOf(), d.key);
      $('mycUrl').textContent = handle.link.replace(/^https?:\/\//, '');
      $('mycOpen').href = handle.link;
      $('mycCopy').onclick = function () { if (window.ADspaceCopy) window.ADspaceCopy.to(this, handle.link); };
      $('mycMobile').oninput = $('mycEmail').oninput = function () { handle.update(cardOf()); };
      $('mycSave').onclick = function () {
        var btn = this;
        btn.disabled = true;
        db.rpc('namecard_save_mine', { p_mobile: ($('mycMobile').value || '').trim() || null,
                                       p_email: ($('mycEmail').value || '').trim() || null })
          .then(function (s) {
            btn.disabled = false;
            var e = s.data && s.data.error;
            if (s.error || e) {
              var t = s.error ? String(s.error.message || '') : '';
              say(e ? (SAID[e] || e) : /function|schema cache/i.test(t) ? 'This needs a database update.' : t, 'err');
              if (e === 'bad-mobile') $('mycMobile').focus();
              if (e === 'bad-email') $('mycEmail').focus();
              return;
            }
            window.ADspaceSheet.close();
          })
          .catch(function () { btn.disabled = false; say('Not saved. Please try again.', 'err'); });
      };
      window.ADspaceSheet.show($('mycSheet'), { opener: opener });
    }).catch(function () { say('Unable to load. Please try again.', 'err'); });
  }
  if ($('mycSheet')) {
    $('mycCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
    $('mycClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  }

  window.ADspaceCard = { mount: mount, phone: phone, digits: digits, vcf: vcf, link: link, openMine: openMine };
})();
