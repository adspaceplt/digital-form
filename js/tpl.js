/* The template store's page engine (2026-11-28; restructure release 11,
 * 2026-11-28-template-store.sql). The one copy of how a page fills a
 * template: the database renders what is sent (`template_render`), this
 * previews what is typed, the same way, so the two never disagree.
 *
 *   ADspaceTpl.names(text)                 the placeholders, each once, in order
 *   ADspaceTpl.fill(text, values)          { text, html, missing }
 *   ADspaceTpl.render(key, lang, opts)     the database's render, a promise
 *   ADspaceTpl.said(res)                   a refusal in the team's words
 *
 * A placeholder is `{field}`, read in any case and spacing. Each value is
 * escaped where it is inserted (ADspaceWords.esc), the words around it
 * too; a field with no value is kept as `{field}` and named in `missing`,
 * never left blank. No page loads this yet: Settings › Messages moves onto
 * the store in release 12. */
(function () {
  'use strict';
  var W = function () { return window.ADspaceWords; };
  var FIELD = /\{([^{}]*)\}/g;

  function norm(s) { return String(s == null ? '' : s).toLowerCase().replace(/\s+/g, ' ').trim(); }

  function names(text) {
    var out = [];
    String(text == null ? '' : text).replace(FIELD, function (m, k) {
      k = norm(k);
      if (out.indexOf(k) < 0) out.push(k);
      return m;
    });
    return out;
  }

  function fill(text, values) {
    var src = String(text == null ? '' : text), vals = {}, plain = '', html = '', missing = [], last = 0, m;
    Object.keys(values || {}).forEach(function (k) { vals[norm(k)] = values[k]; });
    FIELD.lastIndex = 0;
    while ((m = FIELD.exec(src))) {
      var lit = src.slice(last, m.index), k = norm(m[1]);
      var v = vals[k] == null ? '' : String(vals[k]);
      plain += lit;
      html += W().esc(lit);
      if (v.trim()) {
        plain += v;
        html += W().esc(v);
      } else {
        plain += '{' + k + '}';
        html += W().esc('{' + k + '}');
        if (missing.indexOf(k) < 0) missing.push(k);
      }
      last = FIELD.lastIndex;
    }
    plain += src.slice(last);
    html += W().esc(src.slice(last));
    return { text: plain, html: html, missing: missing };
  }

  /* opts: record (uuid), values ({ field: value }), at (YYYY-MM-DD),
     strict (refuse a field with no value). */
  function render(key, lang, opts) {
    var o = opts || {}, api = window.ADspaceAPI && window.ADspaceAPI.client;
    if (!api) return Promise.resolve({ error: 'no-client' });
    return api.rpc('template_render', {
      p_key: key, p_lang: lang, p_record: o.record || null, p_values: o.values || null,
      p_at: o.at || null, p_strict: !!o.strict
    }).then(function (r) {
      if (r.error) return { error: r.error.code === 'PGRST202' ? 'missing' : 'failed', detail: r.error };
      return r.data || { error: 'failed' };
    });
  }

  var SAID = {
    denied: 'You do not have permission to change templates. Please ask an admin.',
    'not-found': 'This template no longer exists.',
    live: 'A live version cannot be changed. Add a new version instead.',
    past: 'Choose today or a later date.',
    'bad-date': 'Choose a date.',
    'bad-subject': 'Enter a subject of 200 characters or fewer.',
    'bad-body': 'Enter a message of 20,000 characters or fewer.'
  };
  function said(res) {
    var d = res || {}, L = W().line;
    if (!d.error) return '';
    if (d.error === 'missing') return L.notYet;
    if (d.error === 'stale') return L.stale;
    if (d.error === 'unknown-field') return L.unknownField(d.field, d.fields);
    if (d.error === 'missing-field') return 'Enter a value for ' + (d.fields || []).map(function (f) { return '{' + f + '}'; }).join(', ') + '.';
    if (d.error === 'before-current') return 'Choose ' + (window.ADspaceClock ? window.ADspaceClock.date(d.from) : d.from) + ' or a later date.';
    return SAID[d.error] || W().en.notSaved;
  }

  window.ADspaceTpl = { names: names, fill: fill, render: render, said: said };
})();
