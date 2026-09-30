/* The decisions of adspace-video-convert, with no AWS in them, so they can be
   tested on their own. index.mjs does the reading and the asking. */
export const PREFIX = 'content/';
export const VIDEO = /\.(mov|mp4|m4v|qt)$/i;

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

export function jobFor(bucket, key, hasAudio, video) {
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
    UserMetadata: { source: key }
  };
}

