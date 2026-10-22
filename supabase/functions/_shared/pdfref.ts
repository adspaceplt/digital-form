/* A document's PDF, read by wa-send and supplier-mail alike (2026-10-22,
   LEAN-1: the 2026-10-18 fix to the closing line break had to land in both
   copies). Malformed base64 reads as nothing.

   A quotation's or a letter's PDF names its own reference (2026-10-15): the
   page draws it with the reference in the file's title, so a file that does
   not carry the record's reference is not that record's. pdf-lib keeps the
   title in a compressed object stream as UTF-16 hex, so each stream is
   inflated and searched as text and as that hex. A stream ends with one
   line break before `endstream`: only that is cut, since the compressed
   data may itself end in a line-feed byte (cutting every trailing break
   refused one valid file in about thirty, 2026-10-18). What one file's
   streams may inflate to, together, is capped: a crafted stream of 4 MB
   inflates to gigabytes and ends the function, so reading stops at the cap
   and the file reads as not naming its reference. */
export const isPdf = (b: Uint8Array) => b.length > 4 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46;
export function pdfFrom(b64: string): Uint8Array | null {
  if (!b64 || b64.length > 20 * 1024 * 1024) return null;
  try {
    const b = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    return isPdf(b) ? b : null;
  } catch { return null; }
}
const hexOf = (s: string) => Array.from(s).map((c) => c.charCodeAt(0).toString(16).padStart(4, '0')).join('').toUpperCase();
const INFLATE_CAP = 20 * 1024 * 1024;
async function inflate(b: Uint8Array, room: number): Promise<string | null> {
  try {
    const reader = new Blob([b]).stream().pipeThrough(new DecompressionStream('deflate')).getReader();
    const parts: Uint8Array[] = [];
    let n = 0;
    for (;;) {
      const got = await reader.read();
      if (got.done) break;
      n += got.value.length;
      if (n > room) { await reader.cancel().catch(() => {}); return null; }
      parts.push(got.value);
    }
    const all = new Uint8Array(n);
    let at = 0;
    for (const x of parts) { all.set(x, at); at += x.length; }
    return new TextDecoder('latin1').decode(all);
  } catch { return ''; }
}
export async function namesRef(b: Uint8Array, ref: string): Promise<boolean> {
  if (!ref) return false;
  const raw = new TextDecoder('latin1').decode(b);
  const hex = hexOf(ref), lit = '(' + ref;
  const hit = (t: string) => t.indexOf(lit) >= 0 || t.toUpperCase().replace(/\s+/g, '').indexOf(hex) >= 0;
  if (hit(raw)) return true;
  const re = /stream\r?\n/g;
  let m: RegExpExecArray | null, seen = 0, room = INFLATE_CAP;
  while ((m = re.exec(raw)) && seen < 400) {
    seen++;
    const start = m.index + m[0].length, end = raw.indexOf('endstream', start);
    if (end < 0) break;
    if (end - start > 4 * 1024 * 1024) continue;
    const cuts = b[end - 1] === 0x0a ? (b[end - 2] === 0x0d ? [end - 1, end - 2] : [end - 1])
      : b[end - 1] === 0x0d ? [end - 1] : [end];
    for (const stop of cuts) {
      if (stop <= start) continue;
      const text = await inflate(b.subarray(start, stop), room);
      if (text === null) return false;
      room -= text.length;
      if (hit(text)) return true;
      if (text) break;
    }
  }
  return false;
}
