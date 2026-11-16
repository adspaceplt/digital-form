/* A candidate's own page (2026-11-16, release H2 step A; HR-SPEC.md
 * decision 1): `/careers/?k={key}`, the one private link a candidate holds.
 * No account and no sign-in. It reads their name, the position and where the
 * application stands (`careers_read`), never a colleague, a note or a score.
 * English alone. The link ends after `hiring_link_days` without a step. */
(function () {
  var API = window.ADspaceAPI, db = API && API.client;
  var $ = function (id) { return document.getElementById(id); };
  var esc = window.ADspaceWords.esc;
  var W = window.ADspaceWords.of({ en: {} }).en;
  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();
  var root = function () { return $('crRoot'); };
  function day(iso) { return window.ADspaceClock.date(iso, { long: true }); }
  function cover(title, text) {
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p></div></div></section>';
  }
  /* Where the application stands, in the candidate's words. The steps
     after Received arrive with the later releases. */
  var NEXT = {
    received: 'ADspace will contact you by email when there is a next step. It will also be shown on this page.'
  };
  function paint(d) {
    root().innerHTML = '<div class="qs-step cr-page" data-shown>' +
      '<div class="qs-top"><h1 class="qs-title">Your application</h1>' +
      '<p class="qs-lead">Dear ' + esc(d.name) + ', thank you for your interest in joining ADspace.</p></div>' +
      '<dl class="ovfacts cr-facts"><div><dt>Position</dt><dd>' + esc(d.position) + '</dd></div>' +
      '<div><dt>Received on</dt><dd>' + esc(day(d.received_at)) + '</dd></div>' +
      '<div><dt>Status</dt><dd>Application received</dd></div></dl>' +
      '<p class="cr-next">' + esc(NEXT[d.stage] || NEXT.received) + '</p></div>';
  }
  if (!db) { cover(W.failTitle, W.failTextAdspace); return; }
  if (!/^[a-z0-9]{8}$/.test(key)) { cover(W.notFound, W.contactAdspace); return; }
  db.rpc('careers_read', { p_key: key }).then(function (r) {
    var d = r.data || {};
    if (r.error) throw r.error;
    if (d.error === 'expired') { cover('Link expired', W.contactAdspace); return; }
    if (d.error || !d.ok) { cover(W.notFound, W.contactAdspace); return; }
    paint(d);
  }).catch(function () { cover(W.failTitle, W.failTextAdspace); });
})();
