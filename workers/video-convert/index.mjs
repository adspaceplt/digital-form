/*
 * adspace-video-convert (AWS Lambda, Node.js 20).
 *
 * Every video uploaded under content/ gets an H.264 MP4 copy beside it that
 * every browser plays: content/…/name.mov → content/…/name.web.mp4. An
 * iPhone's own file (HEVC in QuickTime) plays only in Safari. The copy is
 * made by AWS Elemental MediaConvert; this function only decides what needs
 * one and asks for it. The pages name the copy first and the original after
 * (js/media.js), so a video plays everywhere as soon as its copy lands.
 *
 * Triggered by the bucket's ObjectCreated events under content/. It never
 * deletes and never overwrites an original: it reads, and MediaConvert
 * writes one new file next to it.
 *
 * Environment:
 *   MC_ROLE_ARN   the role MediaConvert takes to read and write the bucket
 *   AWS_REGION    set by Lambda (the bucket's region, ap-southeast-5)
 *
 * Invoked by hand with { "all": true } it walks content/ once and asks for
 * every copy still missing (the videos uploaded before it existed); with
 * { "all": true, "redo": true } it also asks again for any copy over the
 * cap (1080 × 1920, 60 fps; see logic.mjs).
 */
import { S3Client, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command } from '@aws-sdk/client-s3';
import { MediaConvertClient, CreateJobCommand } from '@aws-sdk/client-mediaconvert';

import { PREFIX, isCandidate, webKey, codecsIn, videoInfo, overCap, alreadyWeb, jobFor, u32, cc } from './logic.mjs';

const s3 = new S3Client({});
const mc = new MediaConvertClient({});

/* Four-character codes read straight from the file, never the whole file:
   the top-level boxes, then the sample entries of the movie box. */
async function range(Bucket, Key, a, b) {
  const r = await s3.send(new GetObjectCommand({ Bucket, Key, Range: `bytes=${a}-${b}` }));
  return Buffer.from(await r.Body.transformToByteArray());
}
async function inspect(Bucket, Key, size) {
  const boxes = []; let at = 0;
  for (let n = 0; n < 40 && at < size; n++) {
    const h = await range(Bucket, Key, at, Math.min(at + 15, size - 1));
    let len = u32(h, 0); const type = cc(h, 4);
    if (len === 1) len = Number(h.readBigUInt64BE(8));
    if (len === 0) len = size - at;
    boxes.push({ type, at, len });
    if (len < 8) break;
    at += len;
  }
  const moov = boxes.find((b) => b.type === 'moov');
  const mdat = boxes.find((b) => b.type === 'mdat');
  const ftyp = boxes.find((b) => b.type === 'ftyp');
  let brand = '';
  if (ftyp) brand = cc(await range(Bucket, Key, ftyp.at, ftyp.at + 11), 8);
  const whole = moov && moov.len < 64 * 1024 * 1024 ? await range(Bucket, Key, moov.at, moov.at + moov.len - 1) : null;
  return { brand, codecs: whole ? codecsIn(whole) : [], video: whole ? videoInfo(whole) : null,
    faststart: !!(moov && mdat && moov.at < mdat.at) };
}
/* The copy's size in bytes, or null where there is none. */
async function exists(Bucket, Key) {
  try { const h = await s3.send(new HeadObjectCommand({ Bucket, Key })); return h.ContentLength || 0; }
  catch (e) { return null; }
}

/* With `redo`, a copy made before the cap is asked for again where it is
   over it; MediaConvert writes the new copy under the same name. The
   original is never touched. */
async function convert(Bucket, Key, size, redo) {
  if (!isCandidate(Key)) return 'not a video';
  const had = await exists(Bucket, webKey(Key));
  if (had !== null) {
    if (!redo) return 'copy exists';
    if (!overCap((await inspect(Bucket, webKey(Key), had)).video)) return 'copy exists';
  }
  const ext = (Key.match(/\.([a-z0-9]+)$/i) || [])[1] || '';
  const info = await inspect(Bucket, Key, size);
  if (had === null && alreadyWeb(ext, info)) return 'already plays everywhere';
  const hasAudio = info.codecs.some((c) => /^(mp4a|ac-3|ec-3|lpcm|sowt|twos|alac)$/.test(c)) || !info.codecs.length;
  const r = await mc.send(new CreateJobCommand(jobFor(Bucket, Key, hasAudio, info.video)));
  return (had === null ? 'job ' : 'redo job ') + (r.Job && r.Job.Id);
}

export const handler = async (event) => {
  const done = [];
  if (event && event.all) {
    const Bucket = event.bucket || 'myadspace';
    let token;
    do {
      const page = await s3.send(new ListObjectsV2Command({ Bucket, Prefix: PREFIX, ContinuationToken: token }));
      for (const o of page.Contents || []) {
        if (isCandidate(o.Key)) done.push([o.Key, await convert(Bucket, o.Key, o.Size, !!event.redo)]);
      }
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
  } else {
    for (const rec of (event && event.Records) || []) {
      const Bucket = rec.s3.bucket.name;
      const Key = decodeURIComponent(String(rec.s3.object.key).replace(/\+/g, ' '));
      done.push([Key, await convert(Bucket, Key, rec.s3.object.size)]);
    }
  }
  done.forEach(([k, what]) => console.log(what + ': ' + k));
  return { done: done.length, results: done };
};
