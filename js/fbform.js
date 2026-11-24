/* Client feedback's form (2026-11-24, CLIENT FEEDBACK): one copy of how a
 * request's questions are drawn and read, for /feedback/ (the link a
 * client's primary contact is emailed) and /client/ (Rate your experience).
 *
 *   ADspaceFeedback.form(questions, lang, answers) → markup: each question
 *     in order, a scale as a row of numbered options (`.rate`, a radio
 *     group) with its two ends named under it, a note as a typed box; the
 *     note the lead score's band asks appears once the lead is answered.
 *   ADspaceFeedback.wire(root, questions, answers, onChange) → presses and
 *     arrow keys on the scales; the band's note shown or hidden in place.
 *   ADspaceFeedback.check(root, questions, answers, lang) → the first
 *     question left unanswered, said under it and focused, else null.
 *   ADspaceFeedback.payload(questions, answers) → what feedback_submit takes.
 *   ADspaceFeedback.title(kind, lang), ADspaceFeedback.bandOf(questions, v).
 *
 * The questions, their scales and their bands are the database's
 * (`feedback_questions`), never typed here. */
(function () {
  var W = window.ADspaceWords;
  var esc = W.esc;
  var WORDS = W.of({
    en: { quick: 'Service rating', review: 'Performance review', optional: 'Optional',
      required: 'Please choose a score.', tooLong: 'Please shorten this to 2,000 characters or fewer.' },
    zh: { quick: '服务评分', review: '绩效评估', optional: '选填',
      required: '请选择分数。', tooLong: '请缩减至2,000字以内。' }
  });
  var t = function (lang) { return WORDS[lang === 'zh' ? 'zh' : 'en']; };
  var lead = function (qs) { return (qs || []).filter(function (q) { return q.lead; })[0] || null; };

  function bandOf(qs, v) {
    var l = lead(qs);
    if (!l || v == null || v === '') return null;
    v = Number(v);
    return v <= l.band_low_max ? 'low' : v <= l.band_mid_max ? 'mid' : 'high';
  }
  /* Which questions stand now: every one without a band, and the note of the
     lead score's band once there is one. */
  function shown(qs, answers) {
    var b = bandOf(qs, answers[(lead(qs) || {}).key]);
    return (qs || []).filter(function (q) { return !q.band || q.band === b; });
  }
  function num(qs, q) {
    /* A number a place in the form: the band's three notes share one. */
    var ns = []; (qs || []).forEach(function (x) { if (ns.indexOf(x.n) < 0) ns.push(x.n); });
    return ns.indexOf(q.n) + 1;
  }
  function scale(q, lang, v) {
    var zh = lang === 'zh', out = '';
    for (var i = q.min; i <= q.max; i++) {
      var on = v != null && Number(v) === i;
      out += '<button class="rate-opt' + (on ? ' is-on' : '') + '" type="button" role="radio" aria-checked="' + on + '"' +
        ' tabindex="' + (on || (v == null && i === q.min) ? '0' : '-1') + '" data-v="' + i + '">' + i + '</button>';
    }
    var lo = zh ? q.low_zh : q.low_en, hi = zh ? q.high_zh : q.high_en;
    return '<div class="rate" role="radiogroup" aria-labelledby="fbq-' + esc(q.key) + '-h" data-key="' + esc(q.key) + '"' +
      ' style="--rate-n: ' + (q.max - q.min + 1) + '">' + out + '</div>' +
      '<div class="rate-ends" aria-hidden="true"><span>' + q.min + ' · ' + esc(lo || '') + '</span><span>' + q.max + ' · ' + esc(hi || '') + '</span></div>';
  }
  function one(qs, q, lang, answers) {
    var zh = lang === 'zh', w = t(lang), v = answers[q.key];
    var head = '<h2 class="fbq-h" id="fbq-' + esc(q.key) + '-h"><span class="fbq-n">' + num(qs, q) + '</span>' +
      esc(zh ? q.zh : q.en) + (q.required ? '' : '<span class="fbq-opt">' + esc(w.optional) + '</span>') + '</h2>';
    var body = q.type === 'scale' ? scale(q, lang, v)
      : '<textarea class="textarea" id="fbq-' + esc(q.key) + '" data-key="' + esc(q.key) + '" rows="3" maxlength="2000"' +
        ' aria-labelledby="fbq-' + esc(q.key) + '-h">' + esc(v || '') + '</textarea>';
    return '<section class="fbq" data-q="' + esc(q.key) + '"' + (q.band ? ' data-band="' + q.band + '"' : '') + '>' + head + body +
      '<span class="msg" id="fbq-' + esc(q.key) + '-msg" role="status"></span></section>';
  }
  function form(qs, lang, answers) {
    answers = answers || {};
    return shown(qs, answers).map(function (q) { return one(qs, q, lang, answers); }).join('');
  }
  /* The band's note, redrawn in place when the lead score moves band, its
     words kept under its own key. */
  function refreshBand(root, qs, lang, answers) {
    var b = bandOf(qs, answers[(lead(qs) || {}).key]);
    var cur = root.querySelector('.fbq[data-band]');
    if (cur && cur.getAttribute('data-band') === b) return;
    var q = (qs || []).filter(function (x) { return x.band && x.band === b; })[0];
    if (cur) cur.remove();
    if (!q) return;
    var after = Array.prototype.filter.call(root.querySelectorAll('.fbq'), function (el) {
      var x = qs.filter(function (y) { return y.key === el.getAttribute('data-q'); })[0];
      return x && x.n > q.n;
    })[0];
    var tmp = document.createElement('div');
    tmp.innerHTML = one(qs, q, lang, answers);
    var el = tmp.firstChild;
    if (after) after.parentNode.insertBefore(el, after); else root.appendChild(el);
    if (window.ADspaceGrow && window.ADspaceGrow.fit) Array.prototype.forEach.call(el.querySelectorAll('textarea'), window.ADspaceGrow.fit);
  }
  function wire(root, qs, answers, onChange, lang) {
    if (!root || root.__fbWired) return;
    root.__fbWired = true;
    var pick = function (btn) {
      var g = btn.closest('.rate'), k = g.getAttribute('data-key');
      answers[k] = Number(btn.getAttribute('data-v'));
      Array.prototype.forEach.call(g.querySelectorAll('.rate-opt'), function (o) {
        var on = o === btn;
        o.classList.toggle('is-on', on); o.setAttribute('aria-checked', String(on)); o.tabIndex = on ? 0 : -1;
      });
      var m = document.getElementById('fbq-' + k + '-msg'); if (m) { m.textContent = ''; m.className = 'msg'; }
      if (lead(qs) && lead(qs).key === k) refreshBand(root, qs, lang || root.getAttribute('data-lang') || 'en', answers);
      if (onChange) onChange(k);
    };
    root.addEventListener('click', function (e) {
      var b = e.target.closest('.rate-opt');
      if (b && root.contains(b)) pick(b);
    });
    root.addEventListener('keydown', function (e) {
      var b = e.target.closest && e.target.closest('.rate-opt');
      if (!b) return;
      var all = Array.prototype.slice.call(b.closest('.rate').querySelectorAll('.rate-opt')), i = all.indexOf(b), j = i;
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') j = Math.min(all.length - 1, i + 1);
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') j = Math.max(0, i - 1);
      else if (e.key === 'Home') j = 0;
      else if (e.key === 'End') j = all.length - 1;
      else if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); pick(b); return; }
      else return;
      e.preventDefault();
      all[j].focus(); pick(all[j]);
    });
    root.addEventListener('input', function (e) {
      var k = e.target.getAttribute && e.target.getAttribute('data-key');
      if (k && e.target.tagName === 'TEXTAREA') answers[k] = e.target.value;
    });
  }
  function say(k, text) {
    var m = document.getElementById('fbq-' + k + '-msg');
    if (m) { m.textContent = text || ''; m.className = 'msg' + (text ? ' err' : ''); }
  }
  function check(root, qs, answers, lang) {
    var w = t(lang), first = null;
    shown(qs, answers).forEach(function (q) {
      say(q.key, '');
      var v = answers[q.key];
      if (q.type === 'scale' && q.required && (v == null || v === '')) { say(q.key, w.required); if (!first) first = q; }
      if (q.type === 'text' && String(v || '').length > 2000) { say(q.key, w.tooLong); if (!first) first = q; }
    });
    if (first) {
      var el = root.querySelector('[data-q="' + first.key + '"] .rate-opt[tabindex="0"], [data-q="' + first.key + '"] textarea');
      if (el) el.focus();
    }
    return first;
  }
  function payload(qs, answers) {
    var out = {};
    shown(qs, answers).forEach(function (q) {
      var v = answers[q.key];
      if (v == null || v === '') return;
      if (q.type === 'text') { v = String(v).trim(); if (!v) return; }
      out[q.key] = v;
    });
    return out;
  }
  window.ADspaceFeedback = { form: form, wire: wire, check: check, payload: payload, bandOf: bandOf, say: say,
    title: function (kind, lang) { return t(lang)[kind === 'review' ? 'review' : 'quick']; } };
})();
