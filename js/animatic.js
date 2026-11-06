/* The animatic (2026-11-06; the user: short clips, "1 yes"): a video
 * script's scenes played in order as a rough cut, each scene's picture for
 * its own time with its camera's move, its scene number and its on-screen
 * text, on one canvas. The same drawing plays on screen and is recorded to
 * a video file in the browser (MediaRecorder), so Play and Download show
 * the same thing. Nothing is stored and no service is asked.
 *
 * ADspaceAnimatic.prepare(list, aspect) loads each scene's picture (a data
 * URL or a drawn frame's SVG; a picture that will not load is a blank
 * frame) and answers the scenes ready to play: { n, img, move, secs, text }.
 * ADspaceAnimatic.player(canvas, scenes, onTick) answers { play, pause,
 * restart, playing, total } and draws the first frame at once.
 * ADspaceAnimatic.record(scenes, aspect, onTick) answers a Promise of
 * { blob, ext }, or rejects where the browser records no video.
 */
(function () {
  'use strict';
  var SIZE = { '9:16': [720, 1280], '1:1': [960, 960], '16:9': [1280, 720] };
  var FACE = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Microsoft YaHei", Arial, sans-serif';

  function sizeOf(aspect) { return SIZE[aspect] || SIZE['9:16']; }
  function load(src) {
    return new Promise(function (resolve) {
      if (!src) { resolve(null); return; }
      var img = new Image();
      img.onload = function () { resolve(img); };
      img.onerror = function () { resolve(null); };
      img.src = /^<svg/.test(src) ? 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(src) : src;
    });
  }
  function prepare(list, aspect) {
    return Promise.all((list || []).map(function (sc) {
      return load(sc.src).then(function (img) {
        return { n: sc.n, img: img, move: sc.move || 'static', secs: sc.secs, text: sc.text || '' };
      });
    }));
  }
  function ease(p) { return p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2; }

  /* One moment of one scene: the picture fitted to cover the frame, moved
     as the camera moves, its number at the top and its words at the foot. */
  function lines(g, words, max) {
    var out = [];
    String(words).split(/\n+/).forEach(function (para) {
      var line = '';
      /* Words split at spaces; Chinese, which has none, at any character. */
      var bits = /\s/.test(para) ? para.split(/(\s+)/) : para.split('');
      bits.forEach(function (b) {
        var t = line + b;
        if (line && g.measureText(t).width > max) { out.push(line.trim()); line = b.trim() ? b : ''; }
        else line = t;
      });
      if (line.trim()) out.push(line.trim());
    });
    return out.slice(0, 4);
  }
  function paint(g, W, H, sc, p) {
    g.fillStyle = '#ffffff';
    g.fillRect(0, 0, W, H);
    var e = ease(Math.max(0, Math.min(1, p)));
    var k = 1, dx = 0, dy = 0, m = sc.move;
    if (m === 'push in') k = 1 + 0.15 * e;
    else if (m === 'pull out') k = 1.15 - 0.15 * e;
    else if (m === 'pan left' || m === 'pan right') { k = 1.12; dx = (m === 'pan right' ? 1 : -1) * (0.04 - 0.08 * e) * W; }
    else if (m === 'tilt up' || m === 'tilt down') { k = 1.12; dy = (m === 'tilt down' ? 1 : -1) * (0.04 - 0.08 * e) * H; }
    if (sc.img) {
      var iw = sc.img.naturalWidth || sc.img.width || W, ih = sc.img.naturalHeight || sc.img.height || H;
      var s = Math.max(W / iw, H / ih) * k;
      g.drawImage(sc.img, (W - iw * s) / 2 + dx, (H - ih * s) / 2 + dy, iw * s, ih * s);
    }
    var u = Math.min(W, H) / 720;
    /* The scene's number, a small pill at the top left. */
    g.font = '600 ' + Math.round(24 * u) + 'px ' + FACE;
    var tag = 'Scene ' + sc.n, tw = g.measureText(tag).width;
    g.fillStyle = 'rgba(27,26,23,.78)';
    roundRect(g, 24 * u, 24 * u, tw + 28 * u, 40 * u, 20 * u);
    g.fillStyle = '#ffffff';
    g.textBaseline = 'middle';
    g.fillText(tag, 38 * u, 44 * u);
    /* The on-screen text, centred on a white card at the foot. */
    if (sc.text) {
      g.font = '600 ' + Math.round(32 * u) + 'px ' + FACE;
      var ls = lines(g, sc.text, W - 120 * u), lh = 44 * u;
      if (ls.length) {
        var bh = ls.length * lh + 32 * u, by = H - bh - 56 * u;
        g.fillStyle = 'rgba(255,255,255,.94)';
        roundRect(g, 40 * u, by, W - 80 * u, bh, 18 * u);
        g.fillStyle = '#1b1a17';
        g.textAlign = 'center';
        ls.forEach(function (l, i) { g.fillText(l, W / 2, by + 16 * u + lh * i + lh / 2); });
        g.textAlign = 'left';
      }
    }
  }
  function roundRect(g, x, y, w, h, r) {
    g.beginPath();
    g.moveTo(x + r, y); g.lineTo(x + w - r, y); g.quadraticCurveTo(x + w, y, x + w, y + r);
    g.lineTo(x + w, y + h - r); g.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    g.lineTo(x + r, y + h); g.quadraticCurveTo(x, y + h, x, y + h - r);
    g.lineTo(x, y + r); g.quadraticCurveTo(x, y, x + r, y);
    g.closePath(); g.fill();
  }
  /* Where the cut is at `t` seconds: the scene and how far through it. */
  function at(scenes, t) {
    var start = 0;
    for (var i = 0; i < scenes.length; i++) {
      if (t < start + scenes[i].secs || i === scenes.length - 1) return { i: i, p: Math.min(1, (t - start) / scenes[i].secs) };
      start += scenes[i].secs;
    }
    return { i: 0, p: 0 };
  }
  function total(scenes) { return scenes.reduce(function (n, sc) { return n + sc.secs; }, 0); }

  function player(canvas, scenes, onTick) {
    var g = canvas.getContext('2d');
    var T = total(scenes), t = 0, last = 0, raf = 0, on = false;
    function frame(now) {
      if (!on) return;
      t = Math.min(T, t + (now - last) / 1000);
      last = now;
      draw();
      if (t >= T) { on = false; if (onTick) onTick(t, T, false); return; }
      raf = requestAnimationFrame(frame);
    }
    function draw() {
      var w = at(scenes, t);
      if (scenes[w.i]) paint(g, canvas.width, canvas.height, scenes[w.i], w.p);
      if (onTick) onTick(t, T, on, w.i);
    }
    draw();
    return {
      total: T,
      playing: function () { return on; },
      play: function () { if (on) return; if (t >= T) t = 0; on = true; last = performance.now(); raf = requestAnimationFrame(frame); },
      pause: function () { on = false; cancelAnimationFrame(raf); draw(); },
      restart: function () { on = false; cancelAnimationFrame(raf); t = 0; draw(); }
    };
  }

  /* The browser's own recorder: MP4 where it records it (Safari), else
     WebM. Recorded in real time, so a 30-second animatic takes 30 seconds. */
  function mimeOf() {
    var R = window.MediaRecorder;
    if (!R || !R.isTypeSupported) return null;
    var list = ['video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'];
    for (var i = 0; i < list.length; i++) if (R.isTypeSupported(list[i])) return list[i];
    return null;
  }
  function record(scenes, aspect, onTick) {
    var mime = mimeOf();
    var c = document.createElement('canvas');
    if (!mime || !c.captureStream) return Promise.reject(new Error('no-record'));
    var sz = sizeOf(aspect);
    c.width = sz[0]; c.height = sz[1];
    var g = c.getContext('2d');
    var T = total(scenes);
    return new Promise(function (resolve, reject) {
      var stream = c.captureStream(30), parts = [];
      var rec;
      try { rec = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 4000000 }); } catch (e) { reject(e); return; }
      rec.ondataavailable = function (ev) { if (ev.data && ev.data.size) parts.push(ev.data); };
      rec.onstop = function () {
        stream.getTracks().forEach(function (k) { k.stop(); });
        resolve({ blob: new Blob(parts, { type: mime.split(';')[0] }), ext: /mp4/.test(mime) ? 'mp4' : 'webm' });
      };
      rec.onerror = function (ev) { reject(ev.error || new Error('record')); };
      var t0 = 0;
      var tick = function (now) {
        if (!t0) t0 = now;
        var t = (now - t0) / 1000;
        var w = at(scenes, Math.min(t, T));
        paint(g, c.width, c.height, scenes[w.i], w.p);
        if (onTick) onTick(Math.min(t, T), T);
        if (t >= T) { rec.stop(); return; }
        requestAnimationFrame(tick);
      };
      paint(g, c.width, c.height, scenes[0], 0);
      rec.start(250);
      requestAnimationFrame(tick);
    });
  }

  window.ADspaceAnimatic = { prepare: prepare, player: player, record: record, size: sizeOf, canRecord: function () { return Boolean(mimeOf()); } };
})();
