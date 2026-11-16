/*
 * ADspaceXlsx — fills rows into a workbook template and hands back the file
 * (2026-11-16, the AutoCount HRMS import). The template keeps everything it
 * holds (its sheets, rows 1 and 2, the Data sheet's lists and every
 * validation); the rows are written from row 3 of the named sheets as
 * inline strings in the column's own style. No library: the template is
 * read with the browser's DecompressionStream and written back stored
 * (uncompressed), which every spreadsheet program opens.
 *
 * ADspaceXlsx.fill(bytes, { SheetName: [[cell, …], …] }) → Promise<Blob>
 */
(function () {
  'use strict';
  var CRC = null;
  function crc32(u8) {
    if (!CRC) {
      CRC = new Uint32Array(256);
      for (var n = 0; n < 256; n++) {
        var c = n;
        for (var k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        CRC[n] = c >>> 0;
      }
    }
    var x = 0xffffffff;
    for (var i = 0; i < u8.length; i++) x = CRC[(x ^ u8[i]) & 0xff] ^ (x >>> 8);
    return (x ^ 0xffffffff) >>> 0;
  }
  function u16(v, o) { return v.getUint16(o, true); }
  function u32(v, o) { return v.getUint32(o, true); }
  function inflate(u8) {
    if (typeof DecompressionStream === 'undefined') return Promise.reject(new Error('This browser cannot read the template.'));
    var s = new Blob([u8]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return new Response(s).arrayBuffer().then(function (b) { return new Uint8Array(b); });
  }
  /* Every entry of a zip, by name, in its order. */
  function unzip(buf) {
    var u8 = new Uint8Array(buf), v = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
    var e = u8.length - 22;
    while (e >= 0 && u32(v, e) !== 0x06054b50) e--;
    if (e < 0) return Promise.reject(new Error('The template is not a workbook.'));
    var count = u16(v, e + 10), at = u32(v, e + 16), dec = new TextDecoder(), out = [];
    for (var i = 0; i < count; i++) {
      var method = u16(v, at + 10), size = u32(v, at + 20), nlen = u16(v, at + 28), xlen = u16(v, at + 30),
          clen = u16(v, at + 32), local = u32(v, at + 42);
      var name = dec.decode(u8.subarray(at + 46, at + 46 + nlen));
      var start = local + 30 + u16(v, local + 26) + u16(v, local + 28);
      out.push({ name: name, method: method, data: u8.subarray(start, start + size) });
      at += 46 + nlen + xlen + clen;
    }
    return Promise.all(out.map(function (x) {
      return (x.method === 8 ? inflate(x.data) : Promise.resolve(x.data)).then(function (d) { return { name: x.name, data: d }; });
    }));
  }
  /* A zip of stored entries. */
  function zip(entries) {
    var enc = new TextEncoder(), parts = [], dir = [], off = 0;
    entries.forEach(function (x) {
      var name = enc.encode(x.name), crc = crc32(x.data), n = x.data.length;
      var h = new DataView(new ArrayBuffer(30));
      h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true);
      h.setUint16(8, 0, true); h.setUint32(14, crc, true); h.setUint32(18, n, true); h.setUint32(22, n, true);
      h.setUint16(26, name.length, true);
      parts.push(new Uint8Array(h.buffer), name, x.data);
      var c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
      c.setUint32(16, crc, true); c.setUint32(20, n, true); c.setUint32(24, n, true); c.setUint16(28, name.length, true);
      c.setUint32(42, off, true);
      dir.push(new Uint8Array(c.buffer), name);
      off += 30 + name.length + n;
    });
    var dirLen = dir.reduce(function (a, p) { return a + p.length; }, 0);
    var end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true); end.setUint16(8, entries.length, true); end.setUint16(10, entries.length, true);
    end.setUint32(12, dirLen, true); end.setUint32(16, off, true);
    return new Blob(parts.concat(dir, [new Uint8Array(end.buffer)]),
      { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  }
  function colName(i) { var s = ''; i += 1; while (i > 0) { var m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); } return s; }
  function xesc(s) {
    return String(s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  /* Rows written into one sheet's XML, from row 3, keeping its prefix. */
  function fillSheet(xml, rows) {
    var pre = (xml.match(/<(\w+:)?sheetData\b/) || [])[1] || '';
    var close = '</' + pre + 'sheetData>';
    var at = xml.indexOf(close);
    if (at < 0) throw new Error('The template sheet holds no rows.');
    var body = rows.map(function (cells, ri) {
      var r = ri + 3;
      return '<' + pre + 'row r="' + r + '">' + cells.map(function (v, ci) {
        if (v === null || v === undefined || v === '') return '';
        return '<' + pre + 'c r="' + colName(ci) + r + '" s="1" t="inlineStr"><' + pre + 'is><' + pre + 't xml:space="preserve">' +
          xesc(v) + '</' + pre + 't></' + pre + 'is></' + pre + 'c>';
      }).join('') + '</' + pre + 'row>';
    }).join('');
    xml = xml.slice(0, at) + body + xml.slice(at);
    return xml.replace(/(<(?:\w+:)?dimension ref="A1:)([A-Z]+)\d+"/, function (m, a, col) { return a + col + (rows.length + 2) + '"'; });
  }
  function fill(buf, sheets) {
    var dec = new TextDecoder(), enc = new TextEncoder();
    return unzip(buf).then(function (entries) {
      var get = function (n) { return entries.filter(function (x) { return x.name === n; })[0]; };
      var wb = dec.decode(get('xl/workbook.xml').data), rels = dec.decode(get('xl/_rels/workbook.xml.rels').data);
      Object.keys(sheets).forEach(function (name) {
        var m = wb.match(new RegExp('<(?:\\w+:)?sheet [^>]*name="' + name + '"[^>]*r:id="([^"]+)"'));
        if (!m) throw new Error('The template has no ' + name + ' sheet.');
        var t = rels.match(new RegExp('Target="/?([^"]+)"[^>]*Id="' + m[1] + '"')) ||
                rels.match(new RegExp('Id="' + m[1] + '"[^>]*Target="/?([^"]+)"'));
        if (!t) throw new Error('The template has no ' + name + ' sheet.');
        var path = t[1].indexOf('xl/') === 0 ? t[1] : 'xl/' + t[1];
        var e = get(path);
        e.data = enc.encode(fillSheet(dec.decode(e.data), sheets[name]));
      });
      return zip(entries);
    });
  }
  window.ADspaceXlsx = { fill: fill, _zip: zip, _unzip: unzip, _col: colName };
})();
