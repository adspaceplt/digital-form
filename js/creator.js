/*
 * Creator Portal — what a creator sees.
 *
 * The one party in this operation with no page of their own. Drafts arrived in
 * a Drive folder somebody had to find and paste a link to, and "when am I
 * shooting" was asked on WhatsApp.
 *
 * Signing in: not an account. We hold phone numbers rather than addresses, an
 * SMS code costs money on every message for a page opened four times a
 * campaign, and a freelancer has no password to remember. The key is a code
 * they keep, carried in the link so one tap is enough and stored by the
 * browser so it is typed at most once, on a new phone.
 *
 * What is shown is their own booking and nothing else. A creator never sees
 * the client's stage, the campaign's commercial state, what the client pays,
 * who else was offered the work, or the team's notes: a creator reading that
 * we are still waiting on a client is being handed our position in somebody
 * else's negotiation. The security definer function is what withholds it, not
 * this page.
 */
(function () {
  var API = window.ADspaceAPI;
  var db  = API && API.client;
  var $   = function (id) { return document.getElementById(id); };
  var MON = window.ADspaceMoney;
  var KEY = 'adspace-creator';

  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }

  var T = window.ADspaceWords.of({
    en: {
      preparedFor: 'Signed in as',
      codeTitle: 'Access code',
      codeText: 'Enter the access code provided.',
      codeWrong: 'This code is invalid.',
      standDown: 'No bookings',
      standDownText: 'Please contact your ADspace account manager.',
      lang: '中文',
      work: 'Your bookings',
      none: 'Nothing booked yet',
      noneText: 'Confirmed campaigns appear here.',
      signOut: 'Forget this device',
      shootOn: 'Shoot', deliveryOn: 'Delivery', goLive: 'Publish on',
      whereAt: 'Location', contact: 'On the day', tracking: 'Tracking no.',
      fee: 'Your fee', platformsLabel: 'Posting on', tbc: 'To be confirmed',
      briefHead: 'The brief',
      deliverHead: 'Submission',
      changesHead: 'Changes requested',
      addFiles: 'Files', captionLabel: 'Caption',
      captionHint: 'Caption to publish with this post.',
      submit: 'Submit', submitting: 'Submitting…',
      needFiles: 'Attach at least one file.',
      uploading: 'Uploading', saving: 'Saving', remove: 'Remove',
      filesHead: 'Submitted files',
      uploaded: 'Uploaded.',
      sizeOne: '{file} is larger than {mb} MB.',
      sizeMany: '{n} files are larger than {mb} MB.',
      failOne: '{file} could not be uploaded. Please try again.',
      failMany: '{n} files could not be uploaded. Please try again.',

      payHead: 'Payment details', payLine: 'Approved. Please complete your payment details.',
      payGo: 'Fill in the form',
      ended: 'This booking has ended.',
      nextUp: {
        confirmed: 'We will confirm the shoot date with you.',
        pending_visit: 'Your shoot is booked.',
        pending_delivery: 'The product is on its way to you.',
        pending_draft: 'Your submission is due.',
        submitted: 'Your submission is under review.',
        reviewing: 'Your submission is under review.',
        changes: 'Please revise as noted below and submit again.',
        scheduled: 'Approved and scheduled.',
        posted: 'Posted. Thank you.',
        completed: 'Completed. Thank you.'
      }
    },
    zh: {
      preparedFor: '登录身份',
      codeTitle: '访问码',
      codeText: '请输入您收到的访问码。',
      codeWrong: '访问码无效。',
      standDown: '暂无合作',
      standDownText: '请联系您的 ADspace 客户经理。',
      lang: 'English',
      work: '您的合作',
      none: '暂无合作安排',
      noneText: '合作确认后将显示在此处。',
      signOut: '退出此设备',
      shootOn: '拍摄', deliveryOn: '寄送', goLive: '发布日期',
      whereAt: '地点', contact: '当天联系人', tracking: '快递单号',
      fee: '您的费用', platformsLabel: '发布平台', tbc: '待确认',
      briefHead: '合作简介',
      deliverHead: '作品提交',
      changesHead: '需要修改',
      addFiles: '文件', captionLabel: '文案',
      captionHint: '将随作品一同发布的文案。',
      submit: '提交', submitting: '提交中…',
      needFiles: '请至少上传一个文件。',
      uploading: '上传中', saving: '保存中', remove: '移除',
      filesHead: '已提交文件',
      uploaded: '已上传。',
      sizeOne: '{file} 超过 {mb} MB 上限。',
      sizeMany: '{n} 个文件超过 {mb} MB 上限。',
      failOne: '{file} 上传失败，请重试。',
      failMany: '{n} 个文件上传失败，请重试。',

      payHead: '付款资料', payLine: '已通过。请填写您的付款资料。',
      payGo: '填写表单',
      ended: '此合作已结束。',
      nextUp: {
        confirmed: '我们会与您确认拍摄日期。',
        pending_visit: '拍摄已安排。',
        pending_delivery: '产品正在寄送中。',
        pending_draft: '请提交您的作品。',
        submitted: '您的提交正在审阅中。',
        reviewing: '您的提交正在审阅中。',
        changes: '请按以下说明修改后重新提交。',
        scheduled: '已通过并排期。',
        posted: '已发布，谢谢。',
        completed: '已完成，谢谢。'
      }
    }
  });

  var W = window.ADspaceWords;
  var lang = 'en';
  var feed = null;
  var code = '';
  function t() { return T[lang]; }

  /* The fee is the creator's own, in the client's currency, because that is
     what the invoice will read. */
  function money(n, cur) { return MON.money(n, cur === 'SGD' ? 'SG' : 'MY'); }

  function fmtDate(d) {
    if (!d) return '';
    var x = new Date(d + 'T00:00:00');
    if (isNaN(x)) return d;
    if (lang === 'zh') return x.getFullYear() + '年' + (x.getMonth() + 1) + '月' + x.getDate() + '日';
    return x.getDate() + ' ' + ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sept','Oct','Nov','Dec'][x.getMonth()] +
      ' ' + x.getFullYear();
  }

  // The console stores the placement by its printed name; older rows carry the key.
  var PLAT_KEY = { rednote: 'xhs', Instagram: 'instagram', TikTok: 'tiktok', Facebook: 'facebook' };
  var PLAT = { en: { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
               zh: { xhs: '小红书', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' } };
  function platsOf(s) {
    return String(s || '').split(',').map(function (x) { return x.trim(); })
      .filter(Boolean).map(function (p) { return PLAT[lang][PLAT_KEY[p] || p] || p; });
  }

  // ---- Covers ---------------------------------------------------------------

  function cover(title, text, opts) {
    document.body.classList.add('is-plain');
    $('app').hidden = true;
    $('stateBox').hidden = false;
    $('stateTitle').textContent = title;
    $('stateText').textContent = text;
    $('codeRow').hidden = !(opts && opts.ask);
    $('stateMsg').textContent = '';
    $('stateMsg').className = 'msg';
    if (opts && opts.ask) setTimeout(function () { $('codeInput').focus(); }, 60);
  }
  function askCode() { cover(t().codeTitle, t().codeText, { ask: true }); }

  function tidy(s) { return String(s || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase(); }

  // ---- Load -----------------------------------------------------------------

  function load(c, typed) {
    if (!db) { cover(t().failTitle, t().failText); return; }
    db.rpc('get_creator', { p_code: c }).then(function (r) {
      var d = r.data;
      if (r.error || !d) { cover(t().failTitle, t().failText); return; }
      if (d.error === 'inactive') { forget(); cover(t().standDown, t().standDownText); return; }
      if (d.error) {
        // A typed code that is wrong is answered on the form they typed it in,
        // not by throwing the whole page away underneath them.
        if (typed) {
          $('stateMsg').textContent = t().codeWrong;
          $('stateMsg').className = 'msg err';
        } else { forget(); askCode(); }
        return;
      }
      code = c;
      try { localStorage.setItem(KEY, c); } catch (e) { /* private window */ }
      feed = d;
      paint();
    }, function () { cover(t().failTitle, t().failText); });
  }

  function forget() { try { localStorage.removeItem(KEY); } catch (e) {} code = ''; feed = null; }

  // ---- Paint ----------------------------------------------------------------

  function paint() {
    document.body.classList.remove('is-plain');
    $('stateBox').hidden = true;
    $('app').hidden = false;
    var cr = feed.creator || {};
    $('whoName').textContent = cr.name || '';
    $('whoLine').textContent = '';
    if (window.ADspaceChrome) window.ADspaceChrome.preparedFor(t().preparedFor, cr.name || '');
    $('signOutBtn').textContent = t().signOut;

    var rows = feed.bookings || [];
    $('workHead').hidden = !rows.length;
    $('workHead').textContent = t().work;
    $('noWork').hidden = !!rows.length;
    $('noWorkTitle').textContent = t().none;
    $('noWorkText').textContent = t().noneText;

    var box = $('workList');
    box.innerHTML = '';
    rows.forEach(function (b) { box.appendChild(bookingCard(b)); });
  }

  function chip(state) {
    return '<span class="tone ' + esc(W.tone(state)) + '">' +
      esc(t().step[state] || state) + '</span>';
  }

  function bookingCard(b) {
    var card = document.createElement('section');
    var dead = b.state === 'withdrawn' || b.state === 'replaced';
    card.className = 'booking' + (dead ? ' is-off' : '');
    card.setAttribute('data-id', b.id);

    var seeding = b.push_format === 'seeding';
    var facts = [];
    if (!dead) {
      facts.push([seeding ? t().deliveryOn : t().shootOn,
        b.visit_date ? fmtDate(b.visit_date) + (b.visit_time ? ', ' + b.visit_time : '') : t().tbc]);
      if (b.visit_location) facts.push([t().whereAt, b.visit_location]);
      if (b.visit_pic) facts.push([t().contact, b.visit_pic + (b.visit_pic_phone ? ' · ' + b.visit_pic_phone : '')]);
      if (b.tracking_no) facts.push([t().tracking, b.tracking_no]);
      var plats = platsOf(b.platforms);
      if (plats.length) facts.push([t().platformsLabel, plats.join(' · ')]);
      if (b.planned_publish) facts.push([t().goLive, fmtDate(b.planned_publish)]);
      facts.push([t().fee, money(b.rate, b.currency)]);
    }

    var title = (lang === 'zh' && b.campaign_zh) ? b.campaign_zh : b.campaign;
    var brief = (lang === 'zh' && b.brief_zh) ? b.brief_zh : b.brief;

    card.innerHTML =
      '<div class="booking-head"><b>' + esc(title) + '</b>' + (dead ? '' : chip(b.state)) + '</div>' +
      '<p class="booking-brand">' + esc(b.brand || '') + '</p>' +
      (dead ? '<p class="hint">' + esc(t().ended) + '</p>' :
        (facts.length ? '<dl class="booking-facts">' + facts.map(function (f) {
          return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
        }).join('') + '</dl>' : '') +
        (t().nextUp[b.state] ? '<p class="booking-next">' + esc(t().nextUp[b.state]) + '</p>' : '') +
        (brief ? '<div class="booking-brief"><div class="kstep-title">' + esc(t().briefHead) +
          '</div><p>' + esc(brief).replace(/\n/g, '<br>') + '</p></div>' : '') +
        (b.state === 'changes' && b.change_note
          ? '<div class="booking-brief is-warn"><div class="kstep-title">' + esc(t().changesHead) +
            '</div><p>' + esc(b.change_note) + '</p></div>' : '') +
        filesHtml(b) +
        (b.can_deliver ? deliverHtml(b) : '') +
        (payDue(b.state) ? payHtml() : ''));

    if (b.can_deliver) wireDeliver(card, b);
    if (payDue(b.state)) {
      card.querySelector('[data-a="pay"]').setAttribute('href', (window.ADSPACE_ORG && window.ADSPACE_ORG.ap01) || '/ap01.html');
    }
    return card;
  }

  /* The payment form is named once the work is approved, not the moment it is
     handed in: a creator who has to reshoot would otherwise have filed payment
     details against work nobody has accepted, and the correction lands in the
     ledger. */
  function payDue(s) { return ['scheduled', 'posted', 'completed'].indexOf(s) > -1; }

  function payHtml() {
    return '<div class="booking-pay"><div class="kstep-title">' + esc(t().payHead) + '</div>' +
      '<p>' + esc(t().payLine) + '</p>' +
      '<a class="btn btn-go" data-a="pay" target="_blank" rel="noopener">' + esc(t().payGo) + '</a></div>';
  }

  function isImg(k) { return k === 'image'; }
  function kindLabel(f) {
    return String(f.name || '').split('.').pop().toUpperCase() || 'FILE';
  }

  function filesHtml(b) {
    var files = b.files || [];
    if (!files.length) return '';
    return '<div class="booking-files"><div class="kstep-title">' +
      esc(b.can_deliver ? t().addFiles : t().filesHead) + '</div>' +
      '<div class="filegrid" data-files>' + files.map(function (f) {
        return fileHtml(f, b.can_deliver);
      }).join('') + '</div></div>';
  }

  /* Taking a file back off is theirs only while we are still waiting for the
     draft. Once it is handed in it is ours, and a × on it would offer a
     creator a way to empty a submission we are already reviewing. */
  function fileHtml(f, mine) {
    return '<div class="filecard" data-file="' + esc(f.id) + '">' +
      /* A thumbnail that cannot load shows what the file is rather than the
         browser's broken image mark, which tells a creator their work is gone
         when it is only the preview that failed. */
      (isImg(f.kind)
        ? '<img src="' + esc(f.url) + '" alt="" loading="lazy" ' +
          'onerror="this.remove()"><span class="filecard-kind">' +
          esc(kindLabel(f)) + '</span>'
        : '<span class="filecard-kind">' + esc(kindLabel(f)) + '</span>') +
      '<span class="filecard-name">' + esc(f.name) + '</span>' +
      (mine ? '<button class="filecard-x" type="button" data-a="rm" aria-label="Remove ' +
        esc(f.name) + '">×</button>' : '') +
      '</div>';
  }

  function deliverHtml(b) {
    return '<div class="booking-deliver">' +
      '<div class="kstep-title">' + esc(t().deliverHead) + '</div>' +
      '<label class="field-label" for="pick-' + esc(b.id) + '">' + esc(t().addFiles) + '</label>' +
      '<input class="input" type="file" id="pick-' + esc(b.id) + '" multiple ' +
        'accept="image/*,video/*,.pdf" data-a="pick">' +
      /* The same progress the console draws on Content Review: what is going
         up on the left, how far on the right, one bar under both. A thin bar
         with "Uploading 1/1" beside it said neither how far it had got nor
         what it was waiting for, so a 300 MB video looked identical whether
         it was moving or dead. */
      '<div class="progress" data-up hidden>' +
        '<div class="progress-head"><span data-uptext></span><span data-uppct></span></div>' +
        '<div class="progress-track"><div class="progress-fill" data-bar></div></div></div>' +
      '<label class="field-label" for="cap-' + esc(b.id) + '">' + esc(t().captionLabel) + '</label>' +
      '<textarea class="input textarea" id="cap-' + esc(b.id) + '" rows="4" data-cap ' +
        'placeholder="' + esc(t().captionHint) + '">' + esc(b.caption || '') + '</textarea>' +
      '<div class="kactions"><button class="btn btn-go" type="button" data-a="submit">' +
        esc(t().submit) + '</button></div>' +
      '<div class="msg" data-msg></div></div>';
  }

  // ---- Upload ---------------------------------------------------------------

  function kindOf(file) {
    if (/^image\//.test(file.type)) return 'image';
    if (/^video\//.test(file.type)) return 'video';
    return 'file';
  }

  /* A creator hands in video, so the ceiling is the one the team quoted them
     and not whatever the browser will attempt. Refused here, before a single
     byte moves, because a file that is turned away after a ten minute upload
     is a file uploaded twice. */
  function maxBytes() {
    var cfg = window.ADSPACE_CONFIG || {};
    return (((cfg.s3 && cfg.s3.maxUploadMB) || 300)) * 1024 * 1024;
  }

  function fill(s, map) {
    return String(s).replace(/\{(\w+)\}/g, function (m, k) {
      return map[k] == null ? m : map[k];
    });
  }

  /* No total deadline: 300 MB up a Malaysian home line is slow, not stuck.
     Silence is stuck, so the attempt ends when no byte has moved for two
     minutes, with a reason rather than a bar nobody can leave. */
  var STALL_MS = 120000;

  function putToS3(url, blob, contentType, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      var timer;
      function stop() { clearTimeout(timer); }
      function tick() {
        stop();
        timer = setTimeout(function () {
          try { xhr.abort(); } catch (e) {}
          reject(new Error('stalled'));
        }, STALL_MS);
      }
      xhr.open('PUT', url, true);
      xhr.setRequestHeader('Content-Type', contentType || 'application/octet-stream');
      xhr.setRequestHeader('Cache-Control', 'public, max-age=31536000, immutable');
      xhr.upload.onprogress = function (e) {
        tick();
        if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
      };
      // Every byte is out; S3 has still to answer, which is its own wait.
      xhr.upload.onload = function () { tick(); if (onProgress) onProgress(1); };
      xhr.onload = function () {
        stop();
        if (xhr.status >= 200 && xhr.status < 300) resolve();
        else reject(new Error('storage rejected the upload (HTTP ' + xhr.status + ')'));
      };
      xhr.onerror = function () { stop(); reject(new Error('the connection dropped')); };
      xhr.send(blob);
      tick();
    });
  }

  /* A write with no deadline is how a page comes to sit on a full bar for ever.
     Supabase's fetch has none of its own, so one is put on it here. */
  function within(p, ms) {
    return new Promise(function (resolve, reject) {
      var done = false;
      var timer = setTimeout(function () {
        if (!done) { done = true; reject(new Error('timed out')); }
      }, ms);
      p.then(function (v) {
        if (done) return; done = true; clearTimeout(timer); resolve(v);
      }, function (e) {
        if (done) return; done = true; clearTimeout(timer); reject(e);
      });
    });
  }

  // The card a repaint has just rebuilt, found again by the booking it is for.
  function sayOn(id, text, cls) {
    var el = document.querySelector('.booking[data-id="' + id + '"] [data-msg]');
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (cls ? ' ' + cls : '');
  }

  function wireDeliver(card, b) {
    var msgBox = card.querySelector('[data-msg]');
    var up     = card.querySelector('[data-up]');
    var bar    = card.querySelector('[data-bar]');
    var upText = card.querySelector('[data-uptext]');
    var upPct  = card.querySelector('[data-uppct]');
    var pick   = card.querySelector('[data-a="pick"]');
    var send   = card.querySelector('[data-a="submit"]');
    var busy   = false;

    function say(text, cls) {
      msgBox.textContent = text || '';
      msgBox.className = 'msg' + (cls ? ' ' + cls : '');
    }

    /* Submit is shut while files are still going up, or the creator is told to
       attach a file they are watching upload. That is the error they reported. */
    function lock(on) {
      busy = on;
      send.disabled = on;
      pick.disabled = on;
    }

    function show(i, n, file, pct, saving) {
      up.hidden = false;
      upText.textContent = (n > 1 ? i + '/' + n + ' · ' : '') + file.name;
      upPct.textContent = saving ? t().saving : Math.round(pct * 100) + '%';
      bar.style.width = Math.round(pct * 100) + '%';
    }

    // One file: signed, sent, then recorded. It is not uploaded until the row
    // exists, so every step's failure is a failure of the whole file.
    function sendOne(file, i, n) {
      show(i, n, file, 0, false);
      var ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '');
      return db.functions.invoke('sign-upload', {
        body: { ext: ext || 'bin', size: file.size, creatorCode: code, optionId: b.id }
      }).then(function (r) {
        if (r.error) throw new Error(r.error.message || 'could not be signed');
        if (!r.data || !r.data.uploadUrl) throw new Error((r.data && r.data.error) || 'refused');
        return putToS3(r.data.uploadUrl, file, file.type, function (p) {
          show(i, n, file, p, p >= 1);
        }).then(function () {
          show(i, n, file, 1, true);
          return within(db.rpc('creator_add_file', {
            p_code: code, p_option: b.id, p_url: r.data.publicUrl,
            p_name: file.name, p_kind: kindOf(file), p_bytes: file.size
          }), 60000);
        });
      }).then(function (res) {
        /* The file reaching storage is only half of it: until this row is
           written the upload is invisible to everybody. This check existed and
           threw from inside a fulfilment handler whose sibling rejection
           handler cannot catch it, so the one error worth reporting went
           nowhere: the bar stood at 100% and Submit then said no file was
           attached. Every failure below reaches the .catch on the queue. */
        var bad = (res && res.error) || (res && res.data && res.data.error);
        if (bad) throw new Error(typeof bad === 'string' ? bad : (bad.message || 'not saved'));
      });
    }

    pick.addEventListener('change', function () {
      var picked = Array.prototype.slice.call(this.files || []);
      this.value = '';
      if (busy || !picked.length) return;
      say('');

      var cap = maxBytes();
      var big = picked.filter(function (f) { return f.size > cap; });
      var queue = picked.filter(function (f) { return f.size <= cap; });
      var mb = Math.round(cap / 1048576);
      var tooBig = big.length === 1
        ? fill(t().sizeOne, { file: big[0].name, mb: mb })
        : fill(t().sizeMany, { n: big.length, mb: mb });

      if (!queue.length) { say(tooBig, 'err'); return; }

      lock(true);
      var total = queue.length, ok = 0, failed = [];

      function run(i) {
        if (i >= total) return Promise.resolve();
        return sendOne(queue[i], i + 1, total).then(function () { ok++; }, function (e) {
          // One bad file does not abandon the rest of the batch.
          failed.push(queue[i].name);
          if (window.console) console.warn('[creator upload] ' + queue[i].name, e);
        }).then(function () { return run(i + 1); });
      }

      run(0).then(function () {
        up.hidden = true;
        lock(false);

        var cls = 'err', text;
        if (failed.length) {
          text = (big.length ? tooBig + ' ' : '') + (failed.length === 1
            ? fill(t().failOne, { file: failed[0] })
            : fill(t().failMany, { n: failed.length }));
        } else if (big.length) {
          text = tooBig;
        } else {
          text = t().uploaded; cls = 'ok';
        }

        /* Repainted from the database, so the page shows what we actually
           hold rather than what the browser believes it sent. The repaint
           replaces this card, so the answer is written onto the new one: said
           before it, the one line explaining what happened was thrown away by
           the redraw that followed. */
        return db.rpc('get_creator', { p_code: code }).then(function (r) {
          if (r.data && !r.data.error) { feed = r.data; paint(); sayOn(b.id, text, cls); }
          else say(failed.length || big.length ? text : t().failText, 'err');
        }, function () {
          say(failed.length || big.length ? text : t().failText, 'err');
        });
      });
    });

    send.addEventListener('click', function () {
      var btn = this;
      if (busy) return;
      var cap = card.querySelector('[data-cap]').value;
      btn.disabled = true;
      var was = btn.textContent;
      btn.textContent = t().submitting;
      db.rpc('creator_submit', { p_code: code, p_option: b.id, p_caption: cap }).then(function (r) {
        btn.disabled = false; btn.textContent = was;
        var d = r.data || {};
        if (d.error === 'empty') { say(t().needFiles, 'err'); return; }
        if (r.error || d.error) { say(t().failText, 'err'); return; }
        load(code);
      }, function () { btn.disabled = false; btn.textContent = was; say(t().failText, 'err'); });
    });
  }

  // Removing a file is the creator's own, and only while we are still waiting.
  document.addEventListener('click', function (e) {
    var x = e.target.closest && e.target.closest('[data-a="rm"]');
    if (!x) return;
    var cardEl = x.closest('.filecard');
    db.rpc('creator_remove_file', { p_code: code, p_file: cardEl.getAttribute('data-file') })
      .then(function () { load(code); });
  });

  // ---- Language and sign out ------------------------------------------------

  function setLang(next) {
    lang = next;
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    $('codeInput').setAttribute('aria-label', t().codeTitle);
    if (feed) paint(); else if (!$('stateBox').hidden) {
      if (!$('codeRow').hidden) askCode();
    }
  }
  if ($('langToggle')) {
    $('langToggle').addEventListener('click', function () { setLang(lang === 'en' ? 'zh' : 'en'); });
  }

  $('signOutBtn').addEventListener('click', function () { forget(); askCode(); });

  $('codeGo').addEventListener('click', function () {
    var c = tidy($('codeInput').value);
    if (c.length !== 8) {
      $('stateMsg').textContent = t().codeWrong;
      $('stateMsg').className = 'msg err';
      return;
    }
    load(c, true);
  });
  $('codeInput').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { e.preventDefault(); $('codeGo').click(); }
  });

  // ---- Start ----------------------------------------------------------------

  setLang('en');
  var fromLink = tidy(new URLSearchParams(location.search).get('k') || '');
  var kept = '';
  try { kept = localStorage.getItem(KEY) || ''; } catch (e) {}
  var start = fromLink || kept;
  // The link's code is stored, so the address bar stops carrying it around.
  if (fromLink) history.replaceState(null, '', location.pathname);
  if (start.length === 8) { cover(t().loading, ''); load(start); }
  else askCode();
})();
