/* Automatic ?v= stamps (2026-11-27; the user's approval of HANDOVER item 7).
 *
 * The repository writes every stamped address with the placeholder `dev` in
 * place of its stamp (`/js/admin.js?v=` then `dev`). The Pages workflow
 * (.github/workflows/pages.yml) runs this over the built site and each
 * becomes the first eight hex characters of the SHA-256 of the file it
 * names, as published: that file's own stamps written first, so a page
 * whose script loads another script changes when the inner one does. A file
 * keeps its stamp until its bytes change, so the console's worker
 * (admin/sw.js) keeps serving an unchanged file across releases and never
 * serves yesterday's copy for today's address. No stamp is typed by hand
 * and two branches can no longer conflict over one.
 *
 * The build stops, deploying nothing, on a stamped address naming no file,
 * an address outside the site, two files stamping each other, or any
 * placeholder left behind.
 *
 *   node .github/stamp.js <built site folder>
 *
 * tests/serve.js applies the same rewrite as it serves, so every suite
 * meets the addresses the site publishes. */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PLACEHOLDER = '?v=' + 'dev';
const TEXT = /\.(html|js|css|json|webmanifest|xml|txt|svg)$/i;
// An address on the site (root-relative, or the site's own origin) carrying the placeholder.
const REF = /(https:\/\/digital\.adspace\.me)?(\/[A-Za-z0-9_\-./]+)\?v=dev(?![A-Za-z0-9_\-])/g;

function stamper(root) {
  root = path.resolve(root);
  const done = new Map();
  const busy = [];
  function fileOf(rel) {
    const f = path.resolve(root, rel);
    if (!f.startsWith(root + path.sep)) throw new Error('stamped address outside the site: /' + rel);
    let st = null;
    try { st = fs.statSync(f); } catch (e) { st = null; }
    if (!st || !st.isFile()) throw new Error('stamped address names no file: /' + rel);
    return f;
  }
  // The bytes a file is published with: its own stamps written.
  function out(rel) {
    if (done.has(rel)) return done.get(rel);
    if (busy.indexOf(rel) > -1) throw new Error('files stamp each other: /' + busy.concat(rel).join(' > /'));
    let buf = fs.readFileSync(fileOf(rel));
    if (TEXT.test(rel) && buf.includes(PLACEHOLDER)) {
      busy.push(rel);
      buf = Buffer.from(rewrite(buf.toString('utf8')), 'utf8');
      busy.pop();
    }
    done.set(rel, buf);
    return buf;
  }
  function stamp(rel) { return crypto.createHash('sha256').update(out(rel)).digest('hex').slice(0, 8); }
  function rewrite(text) {
    return text.replace(REF, function (m, host, p) { return (host || '') + p + '?v=' + stamp(p.slice(1)); });
  }
  return { out: out, stamp: stamp, rewrite: rewrite };
}

function walk(dir, list) {
  fs.readdirSync(dir, { withFileTypes: true }).forEach(function (d) {
    const f = path.join(dir, d.name);
    if (d.isDirectory()) walk(f, list);
    else if (d.isFile() && TEXT.test(d.name)) list.push(f);
  });
  return list;
}

// Rewrites every text file under root in place; answers how many it changed.
function stampSite(root) {
  root = path.resolve(root);
  const s = stamper(root);
  const files = walk(root, []);
  const changed = [];
  files.forEach(function (f) {
    if (!fs.readFileSync(f).includes(PLACEHOLDER)) return;
    changed.push([f, s.out(path.relative(root, f).split(path.sep).join('/'))]);
  });
  // Written once every stamp is worked out, so each hash reads the files as they were built.
  changed.forEach(function (c) { fs.writeFileSync(c[0], c[1]); });
  const left = files.filter(function (f) { return fs.readFileSync(f).includes(PLACEHOLDER); });
  if (left.length) throw new Error('placeholder left in: ' + left.map(function (f) { return path.relative(root, f); }).join(', '));
  return changed.length;
}

module.exports = { stamper: stamper, stampSite: stampSite, PLACEHOLDER: PLACEHOLDER };

if (require.main === module) {
  const dir = process.argv[2];
  if (!dir) { console.error('usage: node .github/stamp.js <built site folder>'); process.exit(2); }
  try {
    console.log('stamped ' + stampSite(dir) + ' files');
  } catch (e) {
    console.error('stamp: ' + e.message);
    process.exit(1);
  }
}
