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
 * The agency's values (restructure release 9, 2026-11-28). A static file
 * cannot read the database, so a page's head, its manifest, the push
 * worker and the site's own address in a stamp name the agency through a
 * placeholder, `%agency.<key>%` (window.ADspaceAgency) or `%config.<key>%`
 * (window.ADSPACE_CONFIG), written here, before any stamp is worked out,
 * from the install's own file, js/config.js, read as a page loads it. A key
 * the install does not hold, an install file missing, or a value holding a
 * character that would need escaping where it lands (& < > " ' ` \ % or a
 * line break) stops the build.
 *
 * tests/serve.js applies the same rewrite as it serves, so every suite
 * meets the addresses the site publishes. */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const vm = require('vm');

const PLACEHOLDER = '?v=' + 'dev';
const TEXT = /\.(html|js|css|json|webmanifest|xml|txt|svg)$/i;
const AGENCY = /%(agency|config)\.([A-Za-z_]+)%/g;
const HAS_AGENCY = /%(agency|config)\.[A-Za-z_]+%/;
const UNSAFE = /[&<>"'`\\%\r\n]/;
const reEsc = (t) => t.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');

// The install's own values: js/config.js, run as a page runs it.
function install(root) {
  const f = path.join(root, 'js/config.js');
  if (!fs.existsSync(f)) return null;
  const page = { window: {} };
  vm.runInNewContext(fs.readFileSync(f, 'utf8'), page, { filename: 'js/config.js' });
  return { agency: page.window.ADspaceAgency || {}, config: page.window.ADSPACE_CONFIG || {} };
}

function stamper(root) {
  root = path.resolve(root);
  const done = new Map();
  const busy = [];
  let held;
  const values = () => (held === undefined ? (held = install(root)) : held);
  function fill(text, rel) {
    return text.replace(AGENCY, function (m, store, key) {
      const v = values();
      if (!v) throw new Error('agency value ' + m + ' in /' + rel + ' with no install file (js/config.js)');
      const val = Object.prototype.hasOwnProperty.call(v[store], key) ? v[store][key] : undefined;
      if (typeof val !== 'string' || !val) throw new Error('agency value ' + m + ' in /' + rel + ' is not held by the install');
      if (UNSAFE.test(val)) throw new Error('agency value ' + m + ' in /' + rel + ' holds a character that would need escaping');
      return val;
    });
  }
  // An address on the site (root-relative, or the site's own origin) carrying the placeholder.
  let ref = null;
  function REF() {
    if (ref) return ref;
    const v = values(), host = v && v.agency.portal_domain;
    ref = new RegExp('(' + (host ? reEsc('https://' + host) : '(?!)') + ')?(\\/[A-Za-z0-9_\\-./]+)\\?v=dev(?![A-Za-z0-9_\\-])', 'g');
    return ref;
  }
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
    if (TEXT.test(rel) && buf.includes('%')) {
      const t = buf.toString('utf8'), f = fill(t, rel);
      if (f !== t) buf = Buffer.from(f, 'utf8');
    }
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
    return text.replace(REF(), function (m, host, p) { return (host || '') + p + '?v=' + stamp(p.slice(1)); });
  }
  return { out: out, stamp: stamp, rewrite: rewrite, fill: fill };
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
    const raw = fs.readFileSync(f);
    if (!raw.includes(PLACEHOLDER) && !HAS_AGENCY.test(raw.toString('utf8'))) return;
    changed.push([f, s.out(path.relative(root, f).split(path.sep).join('/'))]);
  });
  // Written once every stamp is worked out, so each hash reads the files as they were built.
  changed.forEach(function (c) { fs.writeFileSync(c[0], c[1]); });
  const left = files.filter(function (f) {
    const t = fs.readFileSync(f).toString('utf8');
    return t.indexOf(PLACEHOLDER) > -1 || HAS_AGENCY.test(t);
  });
  if (left.length) throw new Error('placeholder left in: ' + left.map(function (f) { return path.relative(root, f); }).join(', '));
  return changed.length;
}

module.exports = { stamper: stamper, stampSite: stampSite, PLACEHOLDER: PLACEHOLDER, AGENCY: AGENCY };

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
