/*
 * ADspaceMedia — the one place a video is given the copy a browser can play.
 *
 * Videos are uploaded as they come off a phone: an iPhone's QuickTime file
 * holding HEVC, which only Safari plays. A conversion on S3 (workers/
 * video-convert/) writes an H.264 MP4 beside each one, named after it:
 * content/…/name.mov → content/…/name.web.mp4. A player names that copy
 * first and the original second, so every browser plays the copy once it
 * exists and falls back to the original until then (Safari plays both).
 */
(function () {
  'use strict';
  var CDN = /^https:\/\/mycdn\.adspace\.me\/content\/.+\.(mov|mp4|m4v|qt)$/i;

  /* The converted copy of a video on the CDN, else null. A copy is never
     asked for a copy. */
  function webOf(url) {
    var u = String(url || '');
    if (!CDN.test(u) || /\.web\.mp4$/i.test(u)) return null;
    return u.replace(/\.[a-z0-9]+$/i, '.web.mp4');
  }
  function attr(v) {
    return String(v).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  }
  /* The <source> children for a player: the copy first, the original after. */
  function sources(url) {
    var web = webOf(url);
    return (web ? '<source src="' + attr(web) + '" type="video/mp4">' : '') +
      '<source src="' + attr(url || '') + '">';
  }
  /* A player built in markup: every attribute the caller gives, then the
     sources. */
  function tag(url, attrs) {
    return '<video' + (attrs ? ' ' + attrs : '') + '>' + sources(url) + '</video>';
  }
  /* A player built as an element. */
  function attach(video, url) {
    video.removeAttribute('src');
    video.innerHTML = sources(url);
    return video;
  }
  window.ADspaceMedia = { webOf: webOf, sources: sources, tag: tag, attach: attach };
})();
