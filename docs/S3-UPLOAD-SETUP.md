# Uploading to S3 instead of Supabase

Switching storage to your existing S3 bucket behind CloudFront removes the 50 MB upload
limit and serves files faster to Malaysia and Singapore. Uploads go straight from the
browser to S3. Nothing large passes through Supabase.

**AWS keys never go in this repo or in the browser.** A small function on Supabase holds
them and hands the browser a one time permission to write a single file. Only someone
already signed in to `/admin/` can ask for one.

## The ADspace values

| | |
| --- | --- |
| Bucket | `myadspace` |
| Region | `ap-southeast-5` (Malaysia) |
| CloudFront | `https://mycdn.adspace.me` |
| Prefix | `content` |

Everything below is written with these filled in, so it can be pasted as is.

**Check this first, it takes a minute.** Upload any small file to `myadspace` under
`content/test.jpg` in the S3 console, then open `https://mycdn.adspace.me/content/test.jpg`
in a browser.

- **It loads.** Everything below is correct as written.
- **404 or access denied.** CloudFront most likely has an **origin path** set, which means
  it already points somewhere inside the bucket. Check the distribution → Origins → your
  S3 origin → Origin path. Tell me what it says and I will adjust `S3_PREFIX` and
  `CDN_BASE` to match.

The existing `mycdn.adspace.me/adspace-brandname.png` suggests objects map straight from
the bucket root with no origin path, which is what these steps assume.

## 1. An IAM user that can only do this one thing

The JSON box is not on the first screen. It sits behind a button that opens a new tab,
which is the usual place to get stuck.

### Create the user

1. AWS console, search **IAM**, open it.
2. Left sidebar → **Users** → **Create user** (orange button, top right).
3. User name: `adspace-portal-upload`
4. **Leave "Provide user access to the AWS Management Console" unticked.** This user is for
   the portal, not for a person.
5. **Next** → on the permissions screen just click **Next** again, then **Create user**.
   Permissions come in the next part. It is easier to add them after the user exists.

### Add the policy, this is where the JSON box lives

6. **Users** → click **adspace-portal-upload**.
7. **Permissions** tab → on the right, the **Add permissions** dropdown →
   **Create inline policy**.
8. The policy editor opens. Top right of the editor there is a **Visual** / **JSON**
   toggle. **Click JSON.**
9. Select everything already in the box and replace it with:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PortalUploadsOnly",
    "Effect": "Allow",
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::myadspace/content/*"
  }]
}
```

10. **Next** → Policy name: `ADspacePortalUpload` → **Create policy**.

Note the `/content/*` on the end. Without it the user could write anywhere in the bucket,
including over `adspace-brandname.png` and anything else already served from your CDN.

### Get the two keys

11. Still on the user → **Security credentials** tab.
12. Scroll to **Access keys** → **Create access key**.
13. Use case: **Third-party service** (some accounts word it "Application running outside
    AWS"). Tick the confirmation box → **Next** → **Create access key**.
14. **Copy both values now.** The secret is shown once and never again. If you lose it,
    delete the key and make a new one, no harm done.

These two values go into the `supabase secrets set` command in step 3. They should not be
pasted anywhere else, and never into this repo.

## 2. Let the browser PUT to the bucket

This one is also buried. S3 → **myadspace** → **Permissions** tab → scroll right to the
bottom → **Cross-origin resource sharing (CORS)** → **Edit**, then paste:

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
npm install -g supabase

supabase login
supabase link --project-ref YOUR_PROJECT_REF

supabase secrets set \
  AWS_ACCESS_KEY_ID=PASTE_THE_ACCESS_KEY \
  AWS_SECRET_ACCESS_KEY=PASTE_THE_SECRET \
  S3_BUCKET=myadspace \
  S3_REGION=ap-southeast-5 \
  S3_PREFIX=content \
  CDN_BASE=https://mycdn.adspace.me

supabase functions deploy sign-upload
```

Your project ref is the subdomain of your Supabase URL. If it is
`https://abcdefgh.supabase.co` then the ref is `abcdefgh`.

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
  what `CDN_BASE` and `S3_PREFIX` assume. Open the stored URL directly to see. This is the
  origin path question at the top of this page.
- **Works for images, fails for a large video** — check the CORS rule is on the bucket and
  not only on the distribution, and that the upload is not being blocked by a corporate
  network.

## What this does not change

- The 50 MB guard still applies while `enabled` is false, and the message still points at
  a review-copy export or a pasted CDN link.
- Files already in Supabase storage keep working. Nothing is migrated, old posts keep
  their existing URLs.
- Deleting a post removes it from the client view but leaves the file in S3. Tidy those up
  in the bucket occasionally, or set a lifecycle rule on the `content/` prefix. The signing
  user cannot delete, so this has to be done from the console.
- Uploads are stored with a one year immutable cache header. Filenames are random and never
  reused, so CloudFront can hold them indefinitely and repeat views cost nothing.

## Why not put AWS keys in the page

A static site has no secrets. Anything in `config.js` is readable by anyone who opens the
page, so a key with write access to the bucket would let a stranger fill it with whatever
they liked, at your cost. The signing function exists to keep the key server side while
still letting the file go browser to S3 directly, which is what keeps large uploads fast.
