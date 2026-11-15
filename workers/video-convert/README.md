# adspace-video-convert

Every video uploaded to the portal (Content Review posts, creator drafts, team
hand-ins) lands in S3 as the phone made it. An iPhone records HEVC in a
QuickTime file, which only Safari plays. This AWS Lambda asks AWS Elemental
MediaConvert for an H.264 MP4 copy beside each one:

```
content/<folder>/<name>.mov   →   content/<folder>/<name>.web.mp4
```

The pages (`js/media.js`) name the `.web.mp4` copy first and the original
second, so a video plays in Chrome, Edge and Firefox as soon as its copy lands
(usually a minute or two after upload), and in Safari throughout.

Nothing is deleted or overwritten: the original stays, and the copy is one new
file. The daily S3 report (`s3-sweep`) counts a copy as in use while its
original is.

Everything below is done once, in the AWS console, in **Asia Pacific
(Malaysia) ap-southeast-5**, the bucket's region.

## Cost

MediaConvert charges per minute of video made: about US$0.015 a minute for a
1080p copy, about twice that for a 4K clip. A 30-second reel costs about one
cent. The Lambda and the S3 trigger stay inside AWS's free allowance; the
copies add a few cents a month of storage.

## 1. The role MediaConvert works as

IAM → Roles → Create role.

1. Trusted entity: **AWS service**, use case **MediaConvert**. Next.
2. Skip the suggested policies. Name it `adspace-mediaconvert`. Create.
3. Open the role → Add permissions → Create inline policy → JSON:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::myadspace/content/*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject"],
      "Resource": "arn:aws:s3:::myadspace/content/*.web.mp4"
    }
  ]
}
```

   Name it `read-content-write-copies`. Save. MediaConvert reads any file
   under `content/` and writes only the `.web.mp4` copies, so a job set up
   wrongly can never write over an original.
4. Copy the role's **ARN** (`arn:aws:iam::<account>:role/adspace-mediaconvert`).

## 2. The function

Lambda → Create function.

1. **Author from scratch**, name `adspace-video-convert`, runtime
   **Node.js 20.x**, architecture arm64. Create.
2. Code tab: delete the sample file. Create two files, `index.mjs` and
   `logic.mjs`, and paste this folder's files of the same names into them.
   Deploy.
3. Configuration → General configuration → Edit: memory **256 MB**, timeout
   **5 min**. Save.
4. Configuration → Environment variables → Edit → Add
   `MC_ROLE_ARN` = the ARN from step 1.4. Save.
5. Configuration → Permissions → click the execution role → Add permissions →
   Create inline policy → JSON:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::myadspace/content/*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::myadspace",
      "Condition": { "StringLike": { "s3:prefix": ["content/*"] } }
    },
    {
      "Effect": "Allow",
      "Action": ["mediaconvert:CreateJob", "mediaconvert:Probe"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["iam:PassRole"],
      "Resource": "arn:aws:iam::<account>:role/adspace-mediaconvert"
    }
  ]
}
```

   Replace `<account>` with your account number (it is in the role ARN). Name
   it `convert-videos`. Save.

The function reads and lists `content/` and asks MediaConvert for jobs. It has
no permission to write, overwrite or delete anything in the bucket.

## 3. The trigger

S3 → `myadspace` → Properties → Event notifications → Create event
notification.

- Name `convert-videos`, prefix `content/`, suffix empty.
- Event types: **All object create events**.
- Destination: Lambda function `adspace-video-convert`. Save.

The function ignores images and its own `.web.mp4` copies, so one trigger over
`content/` is enough.

## 4. The videos already uploaded

Lambda → `adspace-video-convert` → Test → Create new event, name `all`, JSON:

```json
{ "all": true }
```

Test. The result lists each video and what was done: `job …` (a copy was
asked for), `copy exists`, `already plays everywhere`, `recent: left to its
upload trigger` (uploaded in the last 30 minutes, which its own upload
covers), `error: not found` (the original is no longer in the bucket, so no
job is asked for), or `error: …` (that one file could not be read or asked
for; the rest carry on). Run it again at any time; it never asks twice for a copy
that exists.

A copy is only seen once MediaConvert finishes it, so a job still running
is asked for again by a run made meanwhile. Wait for the jobs of one run to
finish (MediaConvert → Jobs) before starting the next.

The walk stops 30 seconds before the function's 5 minutes run out. When it
does, the result ends with `"next": "content/…"`, the last file it reached.
Carry on from there with another Test event:

```json
{ "all": true, "startAfter": "content/…" }
```

Repeat with each new `next` until a result holds none.

## Size of the copy

Every copy fits 1080 × 1920 (either way up) at up to 60 frames a second. A 4K
or larger original is scaled down to it; a smaller one keeps its size. Above
that, some Windows decoders refuse the file and Edge spins without playing,
and MediaConvert charges its 4K rate.

To remake copies made before this cap, use a Test event named `redo`:

```json
{ "all": true, "redo": true }
```

It asks again only for copies over the cap (`redo job …`); every other line
reads `copy exists`. It stops and carries on as `{ "all": true }` does
(`startAfter`, with `"redo": true` kept).

The size and rate are read from the file itself (MOV, MP4, M4V). Where they
cannot be (MKV, WebM, MPEG, or a phone file whose index is over 64 MB), the
function asks MediaConvert's probe (`mediaconvert:Probe`), which also says
whether the video has sound. Where the probe cannot answer either, the copy
is fitted inside 1920 × 1920 and never enlarged: a 4K clip either way up
comes down to 1920 on its long side, but its frame rate is kept as it is,
and sound is asked for; a video with no sound track then fails its job,
named in MediaConvert → Jobs, and keeps playing as its original. The new copy replaces the old one under the same name;
the original is never touched.

CloudFront keeps serving the old copy for up to a day. To serve the new one
at once: CloudFront → the `mycdn.adspace.me` distribution → Invalidations →
Create invalidation, with the copy's path (for example
`/content/<folder>/*`). Up to 1,000 paths a month are free.

## 5. Check

MediaConvert → Jobs lists each job; **Complete** means the copy is in the
bucket beside its original. Open a review link in Chrome: the reels play.

A job marked **Error** names the reason in its detail. The portal keeps
playing the original meanwhile, so nothing is worse than before.
