# Uploading to S3 instead of Supabase

Switching storage to your existing S3 bucket behind CloudFront removes the 50 MB upload
limit and serves files faster to Malaysia and Singapore. Uploads go straight from the
browser to S3. Nothing large passes through Supabase.

**AWS keys never go in this repo or in the browser.** A small function on Supabase holds
them and hands the browser a one time permission to write a single file. Only someone
already signed in to `/admin/` can ask for one.

## What I need from you

Send me these four, or fill them in yourself at step 4:

| | Example |
| --- | --- |
| Bucket name | `adspace-cdn` |
| Region | `ap-southeast-1` |
| CloudFront domain | `https://mycdn.adspace.me` |
| Path prefix to use | `portal` |

Confirm one thing too: a file at `s3://<bucket>/portal/test.jpg` should be reachable at
`https://mycdn.adspace.me/portal/test.jpg`. If CloudFront has an origin path set, the
mapping differs and the prefix needs adjusting.

## 1. An IAM user that can only do this one thing

IAM → Users → Create user, no console access. Attach this inline policy, replacing the
bucket name. It can write, and nothing else. It cannot read, list or delete.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::adspace-cdn/portal/*"
  }]
}
```

Create an access key for it and keep the two values for step 3. Rotate them if they are
ever pasted anywhere other than Supabase secrets.

## 2. Let the browser PUT to the bucket

S3 → your bucket → Permissions → Cross-origin resource sharing:

```json
[{
  "AllowedHeaders": ["*"],
  "AllowedMethods": ["PUT"],
  "AllowedOrigins": ["https://digital.adspace.me"],
  "ExposeHeaders": ["ETag"],
  "MaxAgeSeconds": 3000
}]
```

Without this the browser blocks the upload before it leaves the page.

## 3. Deploy the signing function

Install the Supabase CLI, then from the repo root:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF

supabase secrets set \
  AWS_ACCESS_KEY_ID=AKIA... \
  AWS_SECRET_ACCESS_KEY=... \
  S3_BUCKET=adspace-cdn \
  S3_REGION=ap-southeast-1 \
  S3_PREFIX=portal \
  CDN_BASE=https://mycdn.adspace.me

supabase functions deploy sign-upload
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided automatically, do not set them.

## 4. Turn it on

In `js/config.js`:

```js
s3: {
  enabled: true,
  functionName: 'sign-upload'
},
```

Commit and push. That is the switch. With `enabled: false` everything keeps going to
Supabase exactly as before, so you can flip back at any time.

## Check it worked

Upload something larger than 50 MB in `/admin/`. It should go through without the size
warning, and the thumbnail should load from `mycdn.adspace.me`. Open the client link and
confirm the video plays.

If the upload fails:

- **"Could not start the upload"** — the function is not deployed, or a secret is missing.
  Check `supabase functions logs sign-upload`.
- **"S3 rejected the upload"** — usually the CORS rule in step 2, or the IAM policy prefix
  not matching `S3_PREFIX`.
- **Upload succeeds but the image is broken** — the CloudFront mapping is different from
  what `CDN_BASE` and `S3_PREFIX` assume. Open the stored URL directly to see.

## What this does not change

- The 50 MB guard still applies while `enabled` is false, and the message still points at
  a review-copy export or a pasted CDN link.
- Files already in Supabase storage keep working. Nothing is migrated, old posts keep
  their existing URLs.
- Deleting a post removes it from the client view but leaves the file in S3. Tidy those up
  in the bucket occasionally, or set a lifecycle rule.

## Why not put AWS keys in the page

A static site has no secrets. Anything in `config.js` is readable by anyone who opens the
page, so a key with write access to the bucket would let a stranger fill it with whatever
they liked, at your cost. The signing function exists to keep the key server side while
still letting the file go browser to S3 directly, which is what keeps large uploads fast.
