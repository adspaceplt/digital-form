/* The decisions of adspace-video-convert, with no AWS in them, so they can be
   tested on their own. index.mjs does the reading and the asking. */
export const PREFIX = 'content/';
/* Every video a page lets a person upload (sign-upload's EXT_TYPE). Only the
   ISO base media files (mov, mp4, m4v, qt) are read box by box; the rest
   are always converted (2026-10-22, BE-1: an mkv or mpg never had a copy). */
export const VIDEO = /\.(mov|mp4|m4v|qt|mkv|webm|mpg|mpeg)$/i;
export const ISO_BMFF = /\.(mov|mp4|m4v|qt)$/i;
export const UNREAD = { brand: '', codecs: [], video: null, faststart: false };

import { createHash } from 'node:crypto';

/* MediaConvert's idempotency token for one upload (the review of
   2026-11-25): the key with its ETag, else its size, so S3 delivering the
   same event twice asks for one job; a new upload under the same key, or a
   redo, is a new token. 64 characters at most. */
export const tokenFor = (key, tag, redo) =>
  createHash('sha256').update(key + ':' + String(tag == null ? '' : tag) + (redo ? ':redo' : '')).digest('hex');

export const webKey = (key) => key.replace(/\.[a-z0-9]+$/i, '.web.mp4');
export const isCandidate = (key) =>
  key.startsWith(PREFIX) && VIDEO.test(key) && !/\.web\.mp4$/i.test(key);

const u32 = (b, i) => b.readUInt32BE(i);
const cc = (b, i) => b.toString('latin1', i, i + 4);
export { u32, cc };
export function codecsIn(moov) {
  const out = [];
  for (let i = 0; i + 16 < moov.length; i++) {
    if (moov[i] === 0x73 && cc(moov, i) === 'stsd') {
      const n = u32(moov, i + 8); let p = i + 12;
      for (let k = 0; k < n && p + 8 <= moov.length; k++) { out.push(cc(moov, p + 4)); p += u32(moov, p) || moov.length; }
    }
  }
  return out;
}
/* The picture as it is shown: the video track's size turned by its matrix,
   and its frame rate. Read from the movie box; null where there is none. */
function boxes(b, s, e) {
  const out = [];
  for (let p = s; p + 8 <= e;) {
    let l = u32(b, p); if (l === 0) l = e - p; if (l < 8 || p + l > e) break;
    out.push({ t: cc(b, p + 4), s: p + 8, e: p + l }); p += l;
  }
  return out;
}
const child = (b, box, t) => box && boxes(b, box.s, box.e).find((k) => k.t === t);
export function videoInfo(moov) {
  const top = { s: 8, e: moov.length };
  for (const trak of boxes(moov, top.s, top.e).filter((k) => k.t === 'trak')) {
    const mdia = child(moov, trak, 'mdia');
    const hdlr = child(moov, mdia, 'hdlr');
    if (!hdlr || cc(moov, hdlr.s + 8) !== 'vide') continue;
    const tkhd = child(moov, trak, 'tkhd');
    if (!tkhd) return null;
    const v1 = moov[tkhd.s] === 1;
    const at = tkhd.s + (v1 ? 88 : 76), mx = tkhd.s + (v1 ? 52 : 40);
    let w = Math.round(u32(moov, at) / 65536), h = Math.round(u32(moov, at + 4) / 65536);
    /* A quarter turn stores the frame on its side: a and d of the matrix are 0. */
    if (u32(moov, mx) === 0 && u32(moov, mx + 16) === 0) { const t = w; w = h; h = t; }
    let fps = 0;
    const mdhd = child(moov, mdia, 'mdhd');
    const stts = child(moov, child(moov, child(moov, mdia, 'minf'), 'stbl'), 'stts');
    if (mdhd && stts) {
      const m1 = moov[mdhd.s] === 1;
      const scale = u32(moov, mdhd.s + (m1 ? 20 : 12));
      let frames = 0, ticks = 0;
      for (let i = 0, n = u32(moov, stts.s + 4); i < n && stts.s + 16 + i * 8 <= stts.e; i++) {
        const c = u32(moov, stts.s + 8 + i * 8), d = u32(moov, stts.s + 12 + i * 8);
        frames += c; ticks += c * d;
      }
      if (ticks) fps = Math.round((frames * scale / ticks) * 100) / 100;
    }
    return { w, h, fps };
  }
  return null;
}

/* Every copy fits 1080 × 1920 (either way up) at up to 60 frames a second:
   what a reel is shown at, what every browser's decoder takes (a 1920 × 3414
   copy spun forever in Edge, 2026-09-30), and the cheapest MediaConvert rate
   for it. A smaller original is never enlarged. */
export const CAP = { long: 1920, short: 1080, fps: 60 };
export const overCap = (info) => !!info &&
  (Math.max(info.w, info.h) > CAP.long || Math.min(info.w, info.h) > CAP.short || info.fps > CAP.fps + 0.5);
export function outSize(info) {
  if (!info || !info.w || !info.h) return null;
  const long = Math.max(info.w, info.h), short = Math.min(info.w, info.h);
  const k = Math.min(1, CAP.long / long, CAP.short / short);
  if (k === 1) return null;
  const even = (n) => Math.max(2, Math.round(n / 2) * 2);
  return info.h >= info.w ? { w: even(short * k), h: even(long * k) } : { w: even(long * k), h: even(short * k) };
}

/* A file already fit for every browser (H.264 in MP4, its index first,
   within the cap) is left alone; anything else gets a copy. */
export const alreadyWeb = (ext, info) =>
  /^(mp4|m4v)$/i.test(ext) && info.brand.trim() !== 'qt' && info.codecs.includes('avc1') &&
  !info.codecs.some((c) => /^(hvc1|hev1|dvh1|dvhe|ap4h|apch|apcn|apcs|apco)$/.test(c)) && info.faststart &&
  !overCap(info.video);

export function jobFor(bucket, key, hasAudio, video, token) {
  const base = key.replace(/\.[a-z0-9]+$/i, '');
  const size = outSize(video);
  const fast = !!video && video.fps > CAP.fps + 0.5;
  const output = {
    NameModifier: '.web',
    ContainerSettings: { Container: 'MP4', Mp4Settings: { MoovPlacement: 'PROGRESSIVE_DOWNLOAD' } },
    VideoDescription: {
      CodecSettings: {
        Codec: 'H_264',
        H264Settings: {
          RateControlMode: 'QVBR', QvbrSettings: { QvbrQualityLevel: 8 }, MaxBitrate: 8000000,
          CodecProfile: 'HIGH', CodecLevel: 'AUTO', SceneChangeDetect: 'TRANSITION_DETECTION'
        }
      },
      /* An iPhone records HDR; a browser shows H.264 as standard range, so
         the colour is brought into Rec. 709 rather than left washed out. */
      VideoPreprocessors: { ColorCorrector: { ColorSpaceConversion: 'FORCE_709' } }
    }
  };
  if (size) { output.VideoDescription.Width = size.w; output.VideoDescription.Height = size.h; }
  /* A size neither the file nor MediaConvert's probe could tell (an mkv or
     webm, an index past 64 MB, a probe that failed): the copy is fitted
     inside a square of the cap's long side, never enlarged and never
     padded, so a 4K clip either way up comes down to 1920 on its long side. */
  if (!video) {
    Object.assign(output.VideoDescription, { Width: CAP.long, Height: CAP.long, ScalingBehavior: 'FIT_NO_UPSCALE' });
  }
  if (fast) {
    Object.assign(output.VideoDescription.CodecSettings.H264Settings, {
      FramerateControl: 'SPECIFIED', FramerateNumerator: CAP.fps, FramerateDenominator: 1,
      FramerateConversionAlgorithm: 'DUPLICATE_DROP'
    });
  }
  if (hasAudio) {
    output.AudioDescriptions = [{
      AudioSourceName: 'Audio Selector 1',
      CodecSettings: { Codec: 'AAC', AacSettings: { Bitrate: 128000, CodingMode: 'CODING_MODE_2_0', SampleRate: 48000 } }
    }];
  }
  return {
    Role: process.env.MC_ROLE_ARN,
    Settings: {
      Inputs: [{
        FileInput: `s3://${bucket}/${key}`,
        VideoSelector: { Rotate: 'AUTO' },
        AudioSelectors: hasAudio ? { 'Audio Selector 1': { DefaultSelection: 'DEFAULT' } } : undefined,
        TimecodeSource: 'ZEROBASED'
      }],
      OutputGroups: [{
        Name: 'File Group',
        OutputGroupSettings: { Type: 'FILE_GROUP_SETTINGS', FileGroupSettings: { Destination: `s3://${bucket}/${base}` } },
        Outputs: [output]
      }]
    },
    UserMetadata: { source: key },
    ClientRequestToken: token || undefined
  };
}

/* What MediaConvert's probe says of a file (the Probe API, 2026-02): the
   picture as it is shown (turned by its rotation), its rate, and whether it
   has sound. Read in either case, as the SDK and the JSON name them; null
   where the probe found no video track. */
const g = (o, k) => (o ? (o[k] !== undefined ? o[k] : o[k.charAt(0).toLowerCase() + k.slice(1)]) : undefined);
export function fromProbe(res) {
  const r = (g(res, 'ProbeResults') || [])[0];
  const tracks = g(g(r, 'Container'), 'Tracks') || [];
  const kind = (t) => String(g(t, 'TrackType') || '').toLowerCase();
  const vt = tracks.find((t) => kind(t) === 'video');
  if (!vt) return null;
  const vp = g(vt, 'VideoProperties') || {};
  let w = Number(g(vp, 'Width')) || 0, h = Number(g(vp, 'Height')) || 0;
  if ([90, 270].includes(Math.abs(Number(g(vp, 'Rotation')) || 0) % 360)) { const t = w; w = h; h = t; }
  const fr = g(vp, 'FrameRate') || {};
  const num = Number(g(fr, 'Numerator')) || 0, den = Number(g(fr, 'Denominator')) || 1;
  const fps = num ? Math.round((num / den) * 100) / 100 : 0;
  return { video: w && h ? { w, h, fps } : null, audio: tracks.some((t) => kind(t) === 'audio') };
}
/* Whether the copy is asked for sound: the probe's word where it answered,
   else the codecs read from the file, else (nothing read) yes. */
export const hasAudioOf = (info) => (typeof info.audio === 'boolean' ? info.audio :
  info.codecs.some((c) => /^(mp4a|ac-3|ec-3|lpcm|sowt|twos|alac)$/.test(c)) || !info.codecs.length);

/* One file's outcome, never the run's: a damaged upload, or one deleted after
   its trigger, is recorded as an error and the walk goes on. */
export async function attempt(fn) {
  try { return await fn(); }
  catch (e) { return 'error: ' + ((e && (e.message || e.name)) || String(e)); }
}

/* The catch-up walk over content/ ({ "all": true }). It stops STOP_MS before
   Lambda's time runs out and answers the last key it reached as `next`, which
   the next run takes as `startAfter`. An original uploaded in the last
   RECENT_MS is left to its own upload trigger, so no job is asked twice. */
export const RECENT_MS = 30 * 60 * 1000;
export const STOP_MS = 30 * 1000;
export async function walk({ list, convert, startAfter, now, remaining }) {
  const done = []; let token; let last = startAfter || null;
  try {
    do {
      const page = await list(token ? undefined : (startAfter || undefined), token);
      for (const o of page.Contents || []) {
        if (remaining() < STOP_MS) return { done, next: last };
        if (isCandidate(o.Key)) {
          const at = o.LastModified ? new Date(o.LastModified).getTime() : 0;
          done.push([o.Key, at && now - at < RECENT_MS ? 'recent: left to its upload trigger'
            : await attempt(() => convert(o.Key, o.Size))]);
        }
        last = o.Key;
      }
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
  } catch (e) {
    done.push(['(list)', 'error: ' + ((e && e.message) || String(e))]);
    return { done, next: last };
  }
  return { done, next: null };
}

