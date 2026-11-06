/* Shot frames (2026-11-05): a scene's shot drawn as a small sketch from what
 * the script already says: the frame at the script's aspect ratio, the
 * figure as large as the shot size holds it, the horizon where the angle
 * puts it, and an arrow for the camera's move. No AI, nothing stored: the
 * same scene always draws the same frame.
 *
 * ADspaceFrames.svg(scene, aspect) answers an <svg> string (in ink, on the
 * card's ground), or '' where the scene names no shot size, angle or move.
 */
(function () {
  'use strict';
  var RATIO = { '9:16': [9, 16], '1:1': [1, 1], '16:9': [16, 9] };
  /* How much of the frame's height the figure's head-to-waist takes, and
     where its head sits, by shot size. */
  var SIZE = [
    [/extreme wide/i, { s: 0.16, y: 0.62 }],
    [/medium close/i, { s: 0.95, y: 0.34 }],
    [/extreme close/i, { s: 2.2, y: 0.42 }],
    [/close|insert/i, { s: 1.45, y: 0.4 }],
    [/medium/i, { s: 0.62, y: 0.3 }],
    [/wide/i, { s: 0.3, y: 0.52 }]
  ];
  function sizeOf(v) {
    for (var i = 0; i < SIZE.length; i++) if (SIZE[i][0].test(v || '')) return SIZE[i][1];
    return { s: 0.5, y: 0.38 };
  }
  /* The horizon's height in the frame (0 top, 1 bottom) and its tilt. */
  function horizonOf(a) {
    a = String(a || '');
    if (/overhead|top/i.test(a)) return null;
    if (/low/i.test(a)) return { y: 0.8, tilt: 0 };
    if (/high/i.test(a)) return { y: 0.22, tilt: 0 };
    if (/dutch/i.test(a)) return { y: 0.55, tilt: 0.12 };
    return { y: 0.55, tilt: 0 };
  }
  function n(v) { return Math.round(v * 10) / 10; }

  function svg(sc, aspect) {
    sc = sc || {};
    if (!sc.shot_size && !sc.angle && !sc.camera_move) return '';
    var r = RATIO[aspect] || RATIO['9:16'];
    var W = 90, H = n(W * r[1] / r[0]);
    if (H > 160) { H = 160; W = n(H * r[0] / r[1]); }
    var out = [];
    var line = 'stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round"';
    out.push('<rect x="1" y="1" width="' + (W - 2) + '" height="' + (H - 2) + '" rx="4" ' + line + ' stroke-width="1.2"/>');
    var ang = String(sc.angle || '');
    var hz = horizonOf(ang);
    if (hz) {
      var hy = H * hz.y, d = H * hz.tilt;
      out.push('<path d="M4 ' + n(hy + d) + ' L' + (W - 4) + ' ' + n(hy - d) + '" ' + line + ' stroke-width="0.8" stroke-dasharray="3 3" opacity=".55"/>');
    } else {
      /* Overhead: the floor seen from above, a grid. */
      for (var g = 1; g < 4; g++) {
        out.push('<path d="M' + n(W * g / 4) + ' 4 V' + (H - 4) + 'M4 ' + n(H * g / 4) + ' H' + (W - 4) + '" ' + line + ' stroke-width="0.6" opacity=".35"/>');
      }
    }
    /* The figure: a head and shoulders, set a third from the left (the
       rule of thirds) unless it is a talking head. */
    var z = sizeOf(sc.shot_size);
    var u = Math.min(W, H) * 0.32 * z.s;              // the head's radius, scaled
    var cx = /talk|direct|front/i.test(sc.visual || '') ? W / 2 : W * 0.38;
    var cy = H * z.y;
    if (hz === null) {
      out.push('<circle cx="' + n(cx) + '" cy="' + n(cy) + '" r="' + n(u * 0.6) + '" ' + line + ' stroke-width="1.2"/>');
      out.push('<ellipse cx="' + n(cx) + '" cy="' + n(cy) + '" rx="' + n(u * 1.5) + '" ry="' + n(u * 0.9) + '" ' + line + ' stroke-width="1.2"/>');
    } else {
      var head = u * 0.55;
      out.push('<circle cx="' + n(cx) + '" cy="' + n(cy) + '" r="' + n(head) + '" ' + line + ' stroke-width="1.2"/>');
      var sy = cy + head * 1.25, sw = head * 2.3, body = head * (z.s < 0.5 ? 4.2 : 3);
      out.push('<path d="M' + n(cx - sw) + ' ' + n(sy + body) + ' C' + n(cx - sw) + ' ' + n(sy + head * 0.4) + ' ' + n(cx - head) + ' ' + n(sy) + ' ' + n(cx) + ' ' + n(sy) +
        ' C' + n(cx + head) + ' ' + n(sy) + ' ' + n(cx + sw) + ' ' + n(sy + head * 0.4) + ' ' + n(cx + sw) + ' ' + n(sy + body) + '" ' + line + ' stroke-width="1.2"/>');
    }
    /* The camera's move. */
    var mv = String(sc.camera_move || '');
    var arrow = function (x1, y1, x2, y2) {
      var a = Math.atan2(y2 - y1, x2 - x1), k = 4;
      return '<path d="M' + n(x1) + ' ' + n(y1) + ' L' + n(x2) + ' ' + n(y2) + ' M' + n(x2 - k * Math.cos(a - 0.5)) + ' ' + n(y2 - k * Math.sin(a - 0.5)) +
        ' L' + n(x2) + ' ' + n(y2) + ' L' + n(x2 - k * Math.cos(a + 0.5)) + ' ' + n(y2 - k * Math.sin(a + 0.5)) + '" ' + line + ' stroke-width="1.3"/>';
    };
    var m = 7;
    if (/push|dolly in|zoom in|in\b/i.test(mv) && !/pull|out/i.test(mv)) {
      out.push(arrow(m, m, m + 9, m + 9), arrow(W - m, m, W - m - 9, m + 9), arrow(m, H - m, m + 9, H - m - 9), arrow(W - m, H - m, W - m - 9, H - m - 9));
    } else if (/pull|out|reveal/i.test(mv)) {
      out.push(arrow(m + 9, m + 9, m, m), arrow(W - m - 9, m + 9, W - m, m), arrow(m + 9, H - m - 9, m, H - m), arrow(W - m - 9, H - m - 9, W - m, H - m));
    } else if (/pan|track|follow|truck|slide/i.test(mv)) {
      var left = /left/i.test(mv);
      out.push(left ? arrow(W - m - 2, H - m - 2, W - m - 26, H - m - 2) : arrow(W - m - 26, H - m - 2, W - m - 2, H - m - 2));
    } else if (/tilt|crane|jib|rise|up|down/i.test(mv)) {
      var down = /down/i.test(mv);
      out.push(down ? arrow(W - m - 2, m + 2, W - m - 2, m + 24) : arrow(W - m - 2, m + 24, W - m - 2, m + 2));
    }
    return '<svg class="vs-frame-svg" viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" role="img" aria-label="' +
      [sc.shot_size, sc.angle, sc.camera_move].filter(Boolean).join(', ').replace(/"/g, '') + '">' + out.join('') + '</svg>';
  }

  /* A frame Claude drew (2026-11-06, video_script_scenes.ai_frame): kept
     as data, each shape a path of path commands and numbers alone and a
     tone; built here, its path held to the same rule again, so nothing in
     it is ever drawn as markup. On screen each tone is a class (the box's
     own colours) and the camera's move plays once; `print` writes the
     colours themselves on white, for the crew PDF and the animatic. */
  var BOX = { '9:16': [180, 320], '1:1': [240, 240], '16:9': [320, 180] };
  var PATH = /^[MmLlHhVvCcSsQqTtAaZz0-9 .,eE+-]{2,4000}$/;
  var INK = 'stroke-linecap="round" stroke-linejoin="round"';
  var PRINT = {
    ink: 'fill="none" stroke="#1b1a17" stroke-width="1.6" ' + INK,
    light: 'fill="none" stroke="#8e8e8e" stroke-width="1" ' + INK,
    fill: 'fill="#e6e6e6" stroke="none"',
    paper: 'fill="#ffffff" stroke="#1b1a17" stroke-width="1.6" ' + INK
  };
  var MOVE = { 'push in': 'push', 'pull out': 'pull', 'pan left': 'panl', 'pan right': 'panr', 'tilt up': 'tiltu', 'tilt down': 'tiltd' };
  function plain(v) { return String(v || '').replace(/["'<>&]/g, ''); }
  function draw(f, aspect, print) {
    if (!f || !Array.isArray(f.shapes)) return '';
    var b = BOX[aspect] || BOX['9:16'];
    var paths = f.shapes.filter(function (x) { return x && PATH.test(String(x.d || '')) && PRINT[x.t]; }).map(function (x) {
      return print ? '<path d="' + x.d + '" ' + PRINT[x.t] + '/>' : '<path class="vf-' + x.t + '" d="' + x.d + '"/>';
    });
    if (!paths.length) return '';
    var mv = !print && MOVE[f.move];
    return '<svg class="vs-frame-svg vf"' + (print ? ' xmlns="http://www.w3.org/2000/svg"' : '') + ' viewBox="0 0 ' + b[0] + ' ' + b[1] + '" width="' + b[0] + '" height="' + b[1] +
      '" role="img" aria-label="' + plain([f.shot_size, f.angle, f.move].filter(Boolean).join(', ')) + '">' +
      (print ? '<rect width="' + b[0] + '" height="' + b[1] + '" fill="#ffffff"/>' : '<rect class="vf-edge" x="1" y="1" width="' + (b[0] - 2) + '" height="' + (b[1] - 2) + '" rx="4"/>') +
      '<g class="vf-shot' + (mv ? ' vf-' + mv : '') + '">' + paths.join('') + '</g></svg>';
  }
  /* The move a frame plays, as the animatic reads it. */
  function moveOf(f, sc) {
    var m = String((f && f.move) || (sc && sc.camera_move) || '').toLowerCase();
    if (MOVE[m]) return m;
    if (/pull|out|reveal/.test(m)) return 'pull out';
    if (/push|dolly in|zoom in/.test(m)) return 'push in';
    if (/pan|track|follow|truck|slide/.test(m)) return /left/.test(m) ? 'pan left' : 'pan right';
    if (/tilt|crane|jib/.test(m)) return /down/.test(m) ? 'tilt down' : 'tilt up';
    return 'static';
  }

  window.ADspaceFrames = { svg: svg, draw: draw, moveOf: moveOf, box: function (a) { return BOX[a] || BOX['9:16']; } };
})();
