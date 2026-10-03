/*
 * card.js — the public namecard page (/card/?k=…). It reads one colleague's
 * card through `namecard_get` (granted to anon: name, position, mobile and
 * email, for an active colleague only) and draws it with ADspaceCard. A key
 * nobody holds, or a colleague stood down, is the portal's own cover.
 */
(function () {
  var W = (window.ADspaceWords && window.ADspaceWords.en) || {};
  var API = window.ADspaceAPI;
  var db = API && API.client;
  var key = (new URLSearchParams(location.search).get('k') || '').trim().toLowerCase();

  function cover(title, text) {
    document.getElementById('ncHost').hidden = true;
    document.getElementById('ncCover').hidden = false;
    document.getElementById('ncCoverTitle').textContent = title;
    document.getElementById('ncCoverText').textContent = text;
  }

  if (!/^[23456789a-z]{8}$/.test(key)) { cover(W.notFound, W.notFoundText); return; }
  if (!db) { cover(W.failTitle, W.failText); return; }
  db.rpc('namecard_get', { p_key: key }).then(function (r) {
    var d = r.data;
    if (r.error || !d) { cover(W.failTitle, W.failText); return; }
    if (d.error) { cover(W.notFound, W.notFoundText); return; }
    document.title = d.name + ' · ADspace';
    window.ADspaceCard.mount(document.getElementById('ncHost'), d, key);
  }).catch(function () { cover(W.failTitle, W.failText); });
})();
