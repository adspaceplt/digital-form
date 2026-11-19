/* HR forms as PDFs (2026-11-19, the user: "the Employee Record Form,
 * Interview Sheet, etc. based on previously uploaded pdf, once recorded or
 * added digitally, could i save and do export or download pdfs"; asked:
 * all four forms, "admins and requires verification code to download").
 *
 *   ADspaceHrForms.download(btn, kind, name, build, msgHost)
 *     kind: record | sheet | onboarding | kit; name: whom it is about (the
 *     colleague, the candidate, Welcome Kit), filed with the download.
 *     build() → Promise of a form: { title, who, ref, sections: [{ h, rows:
 *     [[label, value]], lines: [text], table: { cols, rows } }],
 *     images: [{ label, blob }], photo: blob }.
 *
 * The database answers a download only to an admin whose session proved an
 * emailed code or a passkey within fifteen minutes (`hr_form_pass`, the
 * Performance lock's proof, `perf_code_fresh`); otherwise the code is sent
 * to their sign-in address and asked here, then the download asked again.
 * Drawn in the browser on the letterhead and never stored; filed in the
 * Activity record by the database. Never a salary.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI;
  var db = API && API.client;
  if (!API || !API.configured || !db) return;
  var LH = 13.5, BODY = 10, LABEL_W = 168, FLOOR = 76;

  function msg(host, text, kind) {
    if (!host) return;
    host.textContent = text || '';
    host.className = 'msg' + (kind && text ? ' ' + kind : '');
  }
  var SAID = {
    denied: 'You do not have permission to download this form. Please ask an admin.',
    'not-team': 'You do not have permission to download this form. Please ask an admin.',
    'bad-kind': 'This form cannot be downloaded.'
  };
  function said(d) {
    if (d && d.code === 'PGRST202') return 'This feature is not available yet. Please contact an admin.';
    return SAID[d && d.error] || 'The form could not be downloaded. Please try again.';
  }
  function pass(kind, name) {
    return db.rpc('hr_form_pass', { p_kind: kind, p_name: name }).then(function (r) {
      if (r.error) return { error: r.error.code === 'PGRST202' ? 'missing' : 'failed', code: r.error.code };
      return r.data || {};
    });
  }
  /* The emailed code, as My records' lock asks it: sent to the sign-in
     address, typed back, the session proved again. */
  function askCode(email) {
    return new Promise(function (resolve) {
      var opts = { shouldCreateUser: false };
      db.auth.signInWithOtp({ email: email, options: opts }).then(function (r) {
        if (r && r.error) { resolve('Not sent. Please try again in a minute.'); return; }
        var digits = window.ADspaceOtp && window.ADspaceOtp.digits ? window.ADspaceOtp.digits() : 8;
        var settled = false;
        window.ADspaceConfirm.ask({
          title: 'Verification code', go: 'Verify', wait: true,
          body: 'A code was sent to ' + email + '. Enter it to download the form.',
          field: { label: 'Code', code: true, need: 'Enter the code from the email.' },
          no: function () { if (!settled) resolve('cancelled'); }
        }, function (v) {
          var code = String(v || '').replace(/\D/g, '');
          if (code.length !== digits) return Promise.resolve('Enter the code from the email.');
          return db.auth.verifyOtp({ email: email, token: code, type: 'email' }).then(function (x) {
            if (x && x.error) return 'The code is incorrect or has expired. Please request a new code.';
            settled = true; resolve(null); return '';
          });
        });
      }).catch(function () { resolve('Not sent. Please try again in a minute.'); });
    });
  }

  function draw(form) {
    var D = window.ADspaceDocs;
    return D.lib().then(function (PDF) {
      var pdf, fonts, logo;
      return PDF.PDFDocument.create().then(function (p) {
        pdf = p;
        return Promise.all([D.embedFonts(pdf, PDF, {}), D.embedLogo(pdf)]);
      }).then(function (got) {
        fonts = got[0]; logo = got[1];
        return embedAll(pdf, form);
      }).then(function (pics) {
        var font = fonts.font, med = fonts.med || fonts.bold;
        var pn = D.pen(PDF, fonts, logo);
        var M = pn.M, R = pn.R, W = pn.W, H = pn.H, text = pn.text, wrap = pn.wrap, mute = pn.mute;
        var pages = [], y;
        var newPage = function () { pn.page = pdf.addPage([W, H]); pages.push(pn.page); y = pn.head(); };
        var need = function (h) { if (y - h < FLOOR) newPage(); };
        newPage();
        text('PRIVATE & CONFIDENTIAL', M, y, BODY, fonts.bold); y -= 22;
        /* The photograph stands at the right of the title, as the paper
           form's box does. */
        var photoH = 0;
        if (pics.photo) {
          var ph = 96, pw = pics.photo.width * (ph / pics.photo.height);
          if (pw > 80) { pw = 80; ph = pics.photo.height * (pw / pics.photo.width); }
          pn.page.drawImage(pics.photo, { x: R - pw, y: y - ph + 12, width: pw, height: ph });
          photoH = ph;
        }
        var top = y;
        wrap(form.title, R - M - (photoH ? 100 : 0), 15, med).forEach(function (ln) { text(ln, M, y, 15, med); y -= 19; });
        if (form.who) { text(form.who, M, y, 11, font); y -= 15; }
        if (form.ref) { text(form.ref, M, y, 9, font, mute); y -= 13; }
        if (photoH) y = Math.min(y, top - photoH - 4);
        y -= 8;
        (form.sections || []).forEach(function (s) {
          need(LH * 3);
          y -= 6;
          text(s.h, M, y, 11.5, med); y -= 6;
          pn.rule(y); y -= LH;
          (s.rows || []).forEach(function (r) {
            var label = wrap(r[0], LABEL_W - 10, 9.5, font), val = wrap(String(r[1] == null || r[1] === '' ? '—' : r[1]), R - M - LABEL_W, BODY, font);
            var h = Math.max(label.length, val.length) * LH;
            need(h);
            label.forEach(function (ln, i) { text(ln, M, y - i * LH, 9.5, font, mute); });
            val.forEach(function (ln, i) { text(ln, M + LABEL_W, y - i * LH, BODY, font); });
            y -= h + 3;
          });
          (s.lines || []).forEach(function (ln0) {
            wrap(ln0, R - M, BODY, font).forEach(function (ln) { need(LH); text(ln, M, y, BODY, font); y -= LH; });
            y -= 4;
          });
          if (s.table && s.table.rows && s.table.rows.length) {
            var cols = s.table.cols, n = cols.length, cw = (R - M) / n;
            need(LH * 2);
            cols.forEach(function (c, i) { text(c, M + i * cw, y, 9, font, mute); });
            y -= LH;
            s.table.rows.forEach(function (row) {
              var cells = row.map(function (v) { return wrap(String(v == null || v === '' ? '—' : v), cw - 8, 9.5, font); });
              var h = Math.max.apply(null, cells.map(function (c) { return c.length; })) * LH;
              need(h);
              cells.forEach(function (c, i) { c.forEach(function (ln, j) { text(ln, M + i * cw, y - j * LH, 9.5, font); }); });
              y -= h + 2;
            });
          }
          y -= 8;
        });
        /* The NRIC copies, each on the form's last pages, as the paper keeps
           them: FOR ADSPACE USE ONLY. */
        pics.images.forEach(function (im) {
          var maxW = R - M, maxH = 300, sc = Math.min(maxW / im.img.width, maxH / im.img.height, 1);
          need(im.img.height * sc + 40);
          text(im.label, M, y, 10, med); text('FOR ADSPACE USE ONLY', R - pn.width('FOR ADSPACE USE ONLY', 8, font), y, 8, font, mute); y -= 10;
          pn.page.drawImage(im.img, { x: M, y: y - im.img.height * sc, width: im.img.width * sc, height: im.img.height * sc });
          y -= im.img.height * sc + 20;
        });
        D.letterFoot(pn, pages, form.ref || form.title, 'PRIVATE & CONFIDENTIAL', 0);
        D.meta(pdf, form.ref || form.title, form.title);
        return pdf.save();
      });
    });
  }
  function embedOne(pdf, blob) {
    if (!blob) return Promise.resolve(null);
    return blob.arrayBuffer().then(function (buf) {
      var u = new Uint8Array(buf);
      var png = u[0] === 0x89 && u[1] === 0x50;
      return (png ? pdf.embedPng(u) : pdf.embedJpg(u)).catch(function () { return null; });
    }).catch(function () { return null; });
  }
  function embedAll(pdf, form) {
    var imgs = form.images || [];
    return Promise.all([embedOne(pdf, form.photo)].concat(imgs.map(function (i) { return embedOne(pdf, i.blob); }))).then(function (got) {
      return { photo: got[0], images: imgs.map(function (i, n) { return { label: i.label, img: got[n + 1] }; }).filter(function (x) { return x.img; }) };
    });
  }
  function fileName(form) {
    return (form.title + ' ' + (form.who || '')).replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim() + '.pdf';
  }

  /* The press: the database's say, the code where it asks one, then the
     form drawn and saved. The tab is opened at the press (a desk browser
     allows a window only then) and shut on any refusal. */
  function download(btn, kind, name, build, host) {
    if (btn && btn.disabled) return;
    var D = window.ADspaceDocs;
    var tab = null;
    var stop = function (t) {
      if (tab && tab.close) try { tab.close(); } catch (e) { /* gone */ }
      if (btn) btn.disabled = false;
      if (t && t !== 'cancelled') msg(host, t, 'err');
    };
    if (btn) btn.disabled = true;
    msg(host, '');
    var go = function (again) {
      return pass(kind, name).then(function (d) {
        if (d.error === 'code-needed' && !again) {
          return askCode(d.email).then(function (err) { if (err) { stop(err); return; } return go(true); });
        }
        if (d.error === 'code-needed') { stop('The code is incorrect or has expired. Please request a new code.'); return; }
        if (d.error) { stop(d.error === 'missing' ? said({ code: 'PGRST202' }) : said(d)); return; }
        tab = D.previewTab ? D.previewTab() : null;
        return build().then(function (form) {
          return draw(form).then(function (bytes) {
            return D.save(new Blob([bytes], { type: 'application/pdf' }), fileName(form), tab);
          });
        }).then(function () { if (btn) btn.disabled = false; });
      });
    };
    go(false).catch(function () { stop('The form could not be downloaded. Please try again.'); });
  }

  window.ADspaceHrForms = { download: download, draw: draw, fileName: fileName };
})();
