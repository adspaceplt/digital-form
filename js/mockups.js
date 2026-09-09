/*
 * Platform mockups.
 * Renders a post record into a frame that reads like the real feed, so the
 * client reviews the post the way their audience will actually see it.
 */
(function () {
  const SVG = {
    heart: '<path d="M12 21s-7.5-4.9-9.6-9A5.4 5.4 0 0 1 12 6.2 5.4 5.4 0 0 1 21.6 12c-2.1 4.1-9.6 9-9.6 9z"/>',
    comment: '<path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 9.5 9.5 0 0 1-3.6-.7L3 21l1.9-5a8.2 8.2 0 0 1-.9-3.8 8.4 8.4 0 0 1 9-8.4 8.4 8.4 0 0 1 8 7.7z"/>',
    send: '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/>',
    bookmark: '<path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>',
    dots: '<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
    music: '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
    star: '<path d="m12 3 2.7 5.6 6.3.9-4.5 4.4 1 6.1-5.5-2.9L6.5 20l1-6.1L3 9.5l6.3-.9z"/>',
    thumb: '<path d="M7 22H4a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1h3m0 10 4.4-9.9V2a3 3 0 0 1 3 3v5h4.6a2 2 0 0 1 2 2.4l-1.4 7A2 2 0 0 1 18.6 21H7z"/>'
  };

  function icon(name, size) {
    return '<svg viewBox="0 0 24 24" width="' + (size || 22) + '" height="' + (size || 22) +
      '" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" ' +
      'stroke-linejoin="round" aria-hidden="true">' + SVG[name] + '</svg>';
  }

  function el(tag, className, html) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (html !== undefined) node.innerHTML = html;
    return node;
  }

  function esc(text) {
    return String(text == null ? '' : text)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  /* Turns #tags and @mentions blue, keeps line breaks. */
  function captionHtml(text) {
    return esc(text)
      .replace(/(^|\s)([#@][\w一-龥.]+)/g, '$1<span class="mk-tag">$2</span>')
      .replace(/\n/g, '<br>');
  }

  /* Instagram, Facebook and RedNote each accept a range of shapes, so the
     frame follows the real file rather than a hardcoded square. Values are the
     narrowest and widest each platform actually renders. */
  const SHAPES = {
    'instagram:feed':     { min: 0.8,  max: 1.91 },   // 4:5 up to 1.91:1
    'instagram:carousel': { min: 0.8,  max: 1.91 },
    'facebook:feed':      { min: 0.6,  max: 1.91 },
    'facebook:carousel':  { min: 0.6,  max: 1.91 },
    'xhs:note':           { min: 0.65, max: 1.5 },
    'xhs:feed':           { min: 0.65, max: 1.5 }
  };

  function clampRatio(w, h, shape) {
    if (!w || !h) return null;
    const r = w / h;
    return shape ? Math.min(shape.max, Math.max(shape.min, r)) : r;
  }

  function mediaNode(item, opts) {
    opts = opts || {};
    const wrap = el('div', 'mk-media' + (opts.ratioClass ? ' ' + opts.ratioClass : ''));
    if (!item || !item.url) {
      wrap.classList.add('mk-media-empty');
      wrap.textContent = 'No media uploaded';
      return wrap;
    }
    const report = function (w, h) { if (opts.onSize && w && h) opts.onSize(w, h); };

    if (item.type === 'video') {
      const video = document.createElement('video');
      video.src = item.url;
      if (item.poster) video.poster = item.poster;
      video.controls = true;
      video.playsInline = true;
      video.preload = 'metadata';
      video.addEventListener('loadedmetadata', function () {
        report(video.videoWidth, video.videoHeight);
      });
      wrap.appendChild(video);
    } else {
      const img = document.createElement('img');
      img.src = item.url;
      img.alt = '';
      img.loading = 'lazy';
      img.addEventListener('load', function () {
        report(img.naturalWidth, img.naturalHeight);
      });
      wrap.appendChild(img);
    }
    return wrap;
  }

  /* Swipeable carousel with dots and arrows. */
  function carouselNode(media, opts) {
    opts = opts || {};
    const wrap = el('div', 'mk-carousel');
    const track = el('div', 'mk-carousel-track');

    // Instagram sizes a carousel to its first slide and crops the rest to match.
    const sized = Boolean(opts.shape);
    if (sized) {
      wrap.classList.add('mk-carousel-sized');
      const first = media[0] || {};
      const known = clampRatio(first.width, first.height, opts.shape);
      wrap.style.aspectRatio = known || 0.8;   // 4:5 placeholder until the file loads
    }

    media.forEach(function (item, i) {
      const slide = el('div', 'mk-slide');
      slide.appendChild(mediaNode(item, {
        ratioClass: sized ? null : opts.ratioClass,
        onSize: sized && i === 0 ? function (w, h) {
          const r = clampRatio(w, h, opts.shape);
          if (r) wrap.style.aspectRatio = r;
        } : null
      }));
      track.appendChild(slide);
    });
    wrap.appendChild(track);

    if (media.length > 1) {
      const dots = el('div', 'mk-dots');
      const counter = el('div', 'mk-counter', '1/' + media.length);
      media.forEach(function (_, i) {
        const dot = el('span', 'mk-dot' + (i === 0 ? ' is-on' : ''));
        dot.addEventListener('click', function () { go(i); });
        dots.appendChild(dot);
      });

      const prev = el('button', 'mk-arrow mk-arrow-prev', '&#8249;');
      const next = el('button', 'mk-arrow mk-arrow-next', '&#8250;');
      prev.type = 'button'; next.type = 'button';
      prev.setAttribute('aria-label', 'Previous slide');
      next.setAttribute('aria-label', 'Next slide');

      let index = 0;
      function go(i) {
        index = Math.max(0, Math.min(media.length - 1, i));
        track.style.transform = 'translateX(' + (index * -100) + '%)';
        counter.textContent = (index + 1) + '/' + media.length;
        Array.prototype.forEach.call(dots.children, function (dot, n) {
          dot.classList.toggle('is-on', n === index);
        });
        prev.disabled = index === 0;
        next.disabled = index === media.length - 1;
      }
      prev.addEventListener('click', function () { go(index - 1); });
      next.addEventListener('click', function () { go(index + 1); });

      wrap.appendChild(prev);
      wrap.appendChild(next);
      wrap.appendChild(dots);
      wrap.appendChild(counter);
      go(0);
    }
    return wrap;
  }

  /* Each platform shows a different account name, so use the one set on the
     client and fall back to the brand name rather than inventing a handle. */
  /* Instagram and TikTok show an @, Facebook and RedNote do not. */
  function atHandle(h) {
    h = String(h || '');
    return h && h.charAt(0) !== '@' ? '@' + h : h;
  }

  /* Which account each placement belongs to. A cover image is shown inside the
     Reels player, so it carries the Instagram account rather than none. */
  const HANDLE_KEY = {
    instagram: 'instagram',
    facebook:  'facebook',
    tiktok:    'tiktok',
    xhs:       'xhs',
    cover:     'instagram'
  };

  function handleFor(post, cfg) {
    // The account name set on the client comes first. A handle stored on the
    // post is only a fallback, since older posts saved the brand name there.
    const key = HANDLE_KEY[post.platform || 'instagram'] || 'instagram';
    const h = (cfg.handles || {})[key];
    if (h) return h;
    if (post.handle) return post.handle;
    return cfg.clientHandle || cfg.clientName || '';
  }

  function avatar(post, cfg) {
    const url = (post.client && post.client.logo_url) || cfg.clientLogo;
    const node = el('div', 'mk-avatar');
    if (url) {
      const img = document.createElement('img');
      img.src = url; img.alt = '';
      node.appendChild(img);
    } else {
      node.textContent = (cfg.clientName || 'A').charAt(0).toUpperCase();
    }
    return node;
  }

  /* Status bar, Dynamic Island and home indicator. These are what make a frame
     read as a phone rather than a black rectangle, and they sit over the media
     exactly as they do on a real device. */
  const SYS = {
    signal: '<svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor">' +
      '<rect y="7.5" width="3" height="3.5" rx="1"/><rect x="4.6" y="5.5" width="3" height="5.5" rx="1"/>' +
      '<rect x="9.2" y="3" width="3" height="8" rx="1"/><rect x="13.8" width="3" height="11" rx="1"/></svg>',
    wifi: '<svg width="16" height="11" viewBox="0 0 16 11" fill="none" stroke="currentColor" ' +
      'stroke-width="1.6" stroke-linecap="round"><path d="M1 3.6a10 10 0 0 1 14 0"/>' +
      '<path d="M3.6 6.4a6.3 6.3 0 0 1 8.8 0"/><path d="M6.2 9a2.6 2.6 0 0 1 3.6 0"/></svg>',
    battery: '<svg width="25" height="12" viewBox="0 0 25 12" fill="none">' +
      '<rect x=".6" y=".6" width="21" height="10.8" rx="3.2" stroke="currentColor" stroke-opacity=".5"/>' +
      '<rect x="2.3" y="2.3" width="14.5" height="7.4" rx="1.8" fill="currentColor"/>' +
      '<path d="M23.2 4.3v3.4a2 2 0 0 0 0-3.4z" fill="currentColor" fill-opacity=".5"/></svg>',
    camera: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" ' +
      'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M3 8.5A2.5 2.5 0 0 1 5.5 6h1.7l1.1-1.8h6.4L15.8 6h2.7A2.5 2.5 0 0 1 21 8.5v8A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z"/>' +
      '<circle cx="12" cy="12.3" r="3.4"/></svg>'
  };

  function deviceChrome(screen) {
    screen.appendChild(el('div', 'mk-statusbar',
      '<span class="mk-time">9:41</span>' +
      '<span class="mk-sysicons">' + SYS.signal + SYS.wifi + SYS.battery + '</span>'));
    screen.appendChild(el('div', 'mk-island'));
    screen.appendChild(el('div', 'mk-home'));
  }

  function actionRow(items) {
    const row = el('div', 'mk-actions');
    const left = el('div', 'mk-actions-left');
    items.forEach(function (name) { left.appendChild(el('span', 'mk-act', icon(name))); });
    row.appendChild(left);
    row.appendChild(el('span', 'mk-act', icon('bookmark')));
    return row;
  }

  // ---- Instagram feed / carousel -------------------------------------------
  function instagramFeed(post, cfg) {
    const frame = el('article', 'mk mk-ig');
    const head = el('header', 'mk-head');
    head.appendChild(avatar(post, cfg));
    const who = el('div', 'mk-who');
    who.appendChild(el('span', 'mk-handle', esc(handleFor(post, cfg))));
    who.appendChild(el('span', 'mk-sub', 'Sponsored'));
    head.appendChild(who);
    head.appendChild(el('span', 'mk-more', icon('dots', 20)));
    frame.appendChild(head);

    frame.appendChild(carouselNode(post.media || [], { shape: SHAPES[key(post)] || SHAPES['instagram:feed'] }));

    frame.appendChild(actionRow(['heart', 'comment', 'send']));
    frame.appendChild(el('div', 'mk-likes', '1,248 likes'));

    const cap = el('div', 'mk-caption');
    cap.innerHTML = '<span class="mk-handle">' + esc(handleFor(post, cfg)) + '</span> ' +
      captionHtml(post.caption);
    frame.appendChild(clampable(cap));
    frame.appendChild(el('div', 'mk-time', 'View all 32 comments'));
    return frame;
  }

  // ---- Facebook feed --------------------------------------------------------
  function facebookFeed(post, cfg) {
    const frame = el('article', 'mk mk-fb');
    const head = el('header', 'mk-head');
    head.appendChild(avatar(post, cfg));
    const who = el('div', 'mk-who');
    who.appendChild(el('span', 'mk-handle', esc(handleFor(post, cfg))));
    who.appendChild(el('span', 'mk-sub', 'Sponsored &middot; <span>Johor Bahru</span>'));
    head.appendChild(who);
    head.appendChild(el('span', 'mk-more', icon('dots', 20)));
    frame.appendChild(head);

    const cap = el('div', 'mk-caption mk-caption-top');
    cap.innerHTML = captionHtml(post.caption);
    frame.appendChild(clampable(cap, 3, ['See more', 'See less']));

    frame.appendChild(carouselNode(post.media || [], { shape: SHAPES['facebook:feed'] }));

    const bar = el('div', 'mk-fb-bar');
    bar.innerHTML =
      '<span>' + icon('thumb', 18) + ' Like</span>' +
      '<span>' + icon('comment', 18) + ' Comment</span>' +
      '<span>' + icon('send', 18) + ' Share</span>';
    frame.appendChild(bar);
    return frame;
  }

  // ---- Reels / TikTok -------------------------------------------------------
  function vertical(post, cfg, kind) {
    const phone = el('div', 'mk mk-phone mk-' + kind);
    const screen = el('div', 'mk-screen');
    screen.appendChild(mediaNode((post.media || [])[0], { ratioClass: 'r-916' }));

    screen.appendChild(kind === 'tiktok'
      ? el('div', 'mk-topbar mk-topbar-tt', '<span>Following</span><b>For You</b>')
      : el('div', 'mk-topbar mk-topbar-ig', '<b>Reels</b>' + SYS.camera));

    const rail = el('div', 'mk-rail');
    rail.innerHTML =
      '<span>' + icon('heart', 26) + '<b>4.2K</b></span>' +
      '<span>' + icon('comment', 26) + '<b>318</b></span>' +
      '<span>' + icon('send', 26) + '<b>96</b></span>';
    screen.appendChild(rail);

    const foot = el('div', 'mk-vfoot');
    foot.appendChild(el('div', 'mk-vhandle', esc(atHandle(handleFor(post, cfg)))));
    const cap = el('div', 'mk-vcaption');
    cap.innerHTML = captionHtml(post.caption);
    foot.appendChild(clampable(cap, 2));
    foot.appendChild(el('div', 'mk-audio',
      icon('music', 14) + '<span>Original audio &middot; ' + esc(cfg.clientName) + '</span>'));
    screen.appendChild(foot);

    deviceChrome(screen);
    phone.appendChild(screen);
    return phone;
  }

  // ---- Stories --------------------------------------------------------------
  function story(post, cfg) {
    const media = post.media || [];
    const phone = el('div', 'mk mk-phone mk-story');
    const screen = el('div', 'mk-screen');

    const bars = el('div', 'mk-bars');
    (media.length ? media : [null]).forEach(function (_, i) {
      bars.appendChild(el('span', 'mk-bar' + (i === 0 ? ' is-on' : '')));
    });

    const stage = el('div', 'mk-story-stage');
    stage.appendChild(mediaNode(media[0], { ratioClass: 'r-916' }));

    const head = el('div', 'mk-story-head');
    head.appendChild(avatar(post, cfg));
    head.appendChild(el('span', 'mk-vhandle', esc(handleFor(post, cfg))));
    head.appendChild(el('span', 'mk-story-time', '2h'));

    screen.appendChild(stage);
    screen.appendChild(bars);
    screen.appendChild(head);

    if (media.length > 1) {
      let index = 0;
      const step = function (delta) {
        index = Math.max(0, Math.min(media.length - 1, index + delta));
        stage.replaceChild(mediaNode(media[index], { ratioClass: 'r-916' }), stage.firstChild);
        Array.prototype.forEach.call(bars.children, function (bar, n) {
          bar.classList.toggle('is-on', n <= index);
        });
      };
      const prev = el('button', 'mk-tap mk-tap-l', ''); prev.type = 'button';
      const next = el('button', 'mk-tap mk-tap-r', ''); next.type = 'button';
      prev.setAttribute('aria-label', 'Previous frame');
      next.setAttribute('aria-label', 'Next frame');
      prev.addEventListener('click', function () { step(-1); });
      next.addEventListener('click', function () { step(1); });
      screen.appendChild(prev);
      screen.appendChild(next);
      screen.appendChild(el('div', 'mk-counter mk-counter-story', media.length + ' frames'));
    }

    if (post.caption) {
      const sticker = el('div', 'mk-sticker');
      sticker.innerHTML = captionHtml(post.caption);
      stage.appendChild(sticker);
    }

    deviceChrome(screen);
    phone.appendChild(screen);
    return phone;
  }

  // ---- RedNote post ---------------------------------------------------------
  function xhsNote(post, cfg) {
    const frame = el('article', 'mk mk-xhs');
    frame.appendChild(carouselNode(post.media || [], { shape: SHAPES['xhs:note'] }));

    const body = el('div', 'mk-xhs-body');
    if (post.title) body.appendChild(el('h4', 'mk-xhs-title', esc(post.title)));
    const cap = el('div', 'mk-xhs-text');
    cap.innerHTML = captionHtml(post.caption_zh || post.caption);
    body.appendChild(clampable(cap, 6, ['展开', '收起']));

    const foot = el('div', 'mk-xhs-foot');
    foot.appendChild(avatar(post, cfg));
    foot.appendChild(el('span', 'mk-xhs-author', esc(handleFor(post, cfg))));
    foot.appendChild(el('span', 'mk-xhs-stats',
      icon('heart', 15) + '<b>2,341</b>' + icon('star', 15) + '<b>876</b>'));
    body.appendChild(foot);

    frame.appendChild(body);
    return frame;
  }

  /* Adds a "more" toggle when the text overflows. */
  function clampable(node, lines, labels) {
    const more = (labels && labels[0]) || 'more';
    const less = (labels && labels[1]) || 'less';
    node.classList.add('mk-clamp');
    node.style.setProperty('--mk-lines', lines || 2);
    const toggle = el('button', 'mk-morebtn', more);
    toggle.type = 'button';
    const wrap = el('div', 'mk-clampwrap');
    wrap.appendChild(node);
    wrap.appendChild(toggle);
    toggle.addEventListener('click', function () {
      const open = node.classList.toggle('is-open');
      toggle.textContent = open ? less : more;
      measureClamp(wrap);
    });
    requestAnimationFrame(function () { measureClamp(wrap); });
    return wrap;
  }

  /* Decides whether the toggle is needed. A hidden element reports zero height,
     so a card inside a folded set or filtered out would look like it never
     overflows and lose its toggle for good. Leave it alone until it can
     actually be measured. */
  function measureClamp(wrap) {
    const node = wrap.querySelector('.mk-clamp');
    const toggle = wrap.querySelector('.mk-morebtn');
    if (!node || !toggle) return;
    if (!node.clientHeight) return;                       // not laid out yet
    if (node.classList.contains('is-open')) { toggle.hidden = false; return; }
    toggle.hidden = node.scrollHeight <= node.clientHeight + 2;
  }

  /* A cover image is an asset, not a post, so it gets a plain frame with no
     platform chrome pretending otherwise. */
  function coverImage(post, cfg) {
    // A cover is what people see inside the Reels player and the profile grid,
    // so it gets the same overlays. Without them there is no safe zone to judge.
    const wrap = el('div', 'mk mk-coverwrap');
    wrap.appendChild(vertical(post, cfg, 'reel'));
    wrap.appendChild(el('div', 'mk-cover-tag', 'Cover image'));
    return wrap;
  }

  const RENDERERS = {
    'instagram:feed':     instagramFeed,
    'instagram:carousel': instagramFeed,
    'instagram:reel':     function (p, c) { return vertical(p, c, 'reel'); },
    'instagram:story':    story,
    'facebook:feed':      facebookFeed,
    'facebook:carousel':  facebookFeed,
    'facebook:story':     story,
    'facebook:reel':      function (p, c) { return vertical(p, c, 'reel'); },
    'tiktok:reel':        function (p, c) { return vertical(p, c, 'tiktok'); },
    'tiktok:feed':        function (p, c) { return vertical(p, c, 'tiktok'); },
    'xhs:note':           xhsNote,
    'xhs:feed':           xhsNote,
    'cover:image':        coverImage
  };

  const LABELS = {
    'instagram:feed':     ['Instagram Feed', '1080 x 1350'],
    'instagram:carousel': ['Instagram Carousel', '1080 x 1350'],
    'instagram:reel':     ['Instagram Reels', '1080 x 1920'],
    'instagram:story':    ['Instagram Story', '1080 x 1920'],
    'facebook:feed':      ['Facebook Post', '1200 x 1200'],
    'facebook:carousel':  ['Facebook Carousel', '1080 x 1080'],
    'facebook:story':     ['Facebook Story', '1080 x 1920'],
    'facebook:reel':      ['Facebook Reels', '1080 x 1920'],
    'tiktok:reel':        ['TikTok', '1080 x 1920'],
    'tiktok:feed':        ['TikTok', '1080 x 1920'],
    'xhs:note':           ['RedNote Post', '1080 x 1440'],
    'xhs:feed':           ['RedNote Post', '1080 x 1440'],
    'cover:image':        ['Cover Image', '']
  };

  function key(post) {
    return (post.platform || 'instagram') + ':' + (post.format || 'feed');
  }

  window.ADspaceMockups = {
    /* Re-measure every caption toggle under a root, after anything that
       changes visibility. */
    remeasure: function (root) {
      (root || document).querySelectorAll('.mk-clampwrap').forEach(measureClamp);
    },

    render: function (post, cfg) {
      const fn = RENDERERS[key(post)] || instagramFeed;
      return fn(post, cfg || {});
    },
    label: function (post) {
      return (LABELS[key(post)] || ['Post', ''])[0];
    },
    dimensions: function (post) {
      const m = (post.media || [])[0];
      if (m && m.width && m.height) return m.width + ' x ' + m.height;
      return (LABELS[key(post)] || ['Post', ''])[1];
    },
    key: key
  };
})();
