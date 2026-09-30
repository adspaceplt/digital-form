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
/* A file already fit for every browser (H.264 in MP4, its index first) is
   left alone; anything else gets a copy. */
export const alreadyWeb = (ext, info) =>
  /^(mp4|m4v)$/i.test(ext) && info.brand.trim() !== 'qt' && info.codecs.includes('avc1') &&
  !info.codecs.some((c) => /^(hvc1|hev1|dvh1|dvhe|ap4h|apch|apcn|apcs|apco)$/.test(c)) && info.faststart;

export function jobFor(bucket, key, hasAudio) {
  const base = key.replace(/\.[a-z0-9]+$/i, '');
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

