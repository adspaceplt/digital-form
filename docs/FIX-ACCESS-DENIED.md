# Fixing "Access Denied" on mycdn.adspace.me

Written for someone who has never touched AWS. Follow it top to bottom and stop when the
test at the end passes.

## What is actually happening

Two AWS services are involved.

- **S3** is a warehouse. Your files sit there. It is private by default, and it says no to
  everyone unless told otherwise.
- **CloudFront** is the shop front. It is what `mycdn.adspace.me` really is. When a browser
  asks for a file, CloudFront goes to the warehouse, collects it, and hands it over.

`Access Denied` means CloudFront went to the warehouse and the warehouse refused it.

Your logo at `mycdn.adspace.me/adspace-brandname.png` works, so the warehouse says yes to
*some* files. The new uploads sit in a folder called `content/`, and something about that
folder is not covered by the permission. That is what we are fixing.

Nothing here risks your existing files. You are widening a permission, not moving anything.

---

## Step 1: Find your distribution

1. Sign in to the AWS console.
2. In the search bar at the top, type **CloudFront** and click it.
3. You will see a list of **Distributions**. One of them has `mycdn.adspace.me` in the
   **Alternate domain names** column. Click it.

Leave this tab open. You will come back to it.

---

## Step 2: See how CloudFront gets into the warehouse

1. On that distribution, click the **Origins** tab.
2. There will be one row, pointing at `myadspace`. Tick it and click **Edit**.
3. Look for the **Origin access** section. It says one of three things.

### If it says "Origin access control settings (recommended)"

This is the modern way. CloudFront has an identity, and the warehouse has to be told to let
that identity in.

There is a button near it, **Copy policy**. Click it. AWS has just written the exact
permission you need and put it on your clipboard. Now go to Step 3 and paste it in.

### If it says "Public"  ← this is the ADspace setup

CloudFront fetches files as an ordinary anonymous visitor, so the bucket itself has to
allow anyone to read them. There is no button to click here. Go to Step 3.

Confirmed on the ADspace distribution: **Origin access: Public**, and **Origin path** is
empty, which means the address mapping is already correct. `content/x.jpg` in the bucket
really is `mycdn.adspace.me/content/x.jpg`. The only thing missing is permission.

### If it says "Legacy access identities"

An older version of the first option. It also needs a bucket policy. Go to Step 3.

---

## Step 3: Fix the warehouse permission

1. New browser tab. Search **S3** at the top of the AWS console, click it.
2. Click the bucket named **myadspace**.
3. Click the **Permissions** tab.
4. Scroll to **Bucket policy** and click **Edit**.

You will see a box of text that looks like code. This is the list of rules about who may
read what.

**If you copied a policy in Step 2**, delete everything in the box, paste what AWS gave
you, and click **Save changes**. You are done with this step.

**For the ADspace bucket**, since origin access is Public, the box needs a rule that lets
anyone read files. If the box is empty, paste this in exactly:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadForCDN",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::myadspace/*"
    }
  ]
}
```

If the box already has text in it, **do not delete it**. Something in there is what makes
the logo work. Read on.

**If there is existing text**, look through it for lines starting with `"Resource"`. They look
like this:

```
"Resource": "arn:aws:s3:::myadspace/*"
```

The part after the last `/` is what matters.

| What you see | What it means |
| --- | --- |
| `myadspace/*` | Everything is allowed. This is not your problem, go to Step 4 |
| `myadspace/adspace-brandname.png` | Only that one file is allowed. This is your problem |
| `myadspace/images/*` | Only that folder is allowed. This is your problem |

If it names one file or a different folder, change that line to:

```
"Resource": "arn:aws:s3:::myadspace/*"
```

Keep the quotes and the comma exactly as they were. Click **Save changes**.

If it refuses to save, copy the whole box into a message to me before changing anything
else. A broken policy is worth avoiding.

### If it saves but still does not work

Same **Permissions** tab, scroll up to **Block public access (bucket settings)** and click
**Edit**.

A bucket policy that allows public reads does nothing while this is switched on. It
overrules the policy. The two settings that matter are the ones mentioning **public bucket
policies**, and they must be **off** for the policy above to take effect.

If everything here is already off, public policies are allowed and honoured, so nothing is
blocking you. That points at the policy being **missing** rather than blocked.

### Why the logo works when there is no policy

There are two old ways a file in S3 could be public, and a bucket set up years ago often
uses the older one.

- **An ACL on the individual file.** Uploading through the AWS console used to offer a
  "make public" tick, which marks that one file readable. The brand logo was almost
  certainly put there this way.
- **A bucket policy**, which covers everything at once. This is the modern way.

The portal uploads through the API and does not set per file ACLs, on purpose. Per file
permissions are exactly the sort of thing that gets forgotten and leaves a client staring
at a broken video.

So the logo works because someone ticked a box on that one file years ago, and your new
uploads fail because nothing has granted them anything. Adding the bucket policy above
fixes every file at once, including any future ones, and leaves the logo working exactly
as it does now.

### A note for later, not now

**Origin access: Public** means the bucket can also be read directly at
`myadspace.s3.ap-southeast-5.amazonaws.com`, going around CloudFront entirely. That is how
your CDN already works today, so this is not something the portal introduced and not a
reason to stop.

Tightening it means switching the origin to **Origin access control** so only CloudFront
can reach the bucket. Worth doing eventually. Not while you are debugging, because changing
it mid-fix makes it much harder to tell which change did what.

---

## Step 4: Check encryption

Skip this if Step 3 fixed it. Come back if it did not.

1. Still in the **myadspace** bucket, click the **Properties** tab.
2. Scroll to **Default encryption**.

| What it says | What to do |
| --- | --- |
| Amazon S3 managed keys (SSE-S3) | Fine, nothing to do |
| AWS Key Management Service key (SSE-KMS) | This is likely your problem, see below |

With SSE-KMS, files are locked with a separate key, and CloudFront has not been given that
key. The giveaway is that old files work and new ones do not, which matches exactly what
you are seeing.

The simplest fix is to click **Edit**, choose **Amazon S3 managed keys (SSE-S3)**, and
save. That only changes files uploaded from then on, so delete and re-import the broken
posts afterwards.

If someone chose KMS deliberately for a reason, tell me and we will give CloudFront the key
instead rather than changing it.

---

## Step 5: Clear the shop front's memory

CloudFront remembers answers, including "no". After fixing the permission it can keep
serving the old refusal for a few minutes.

1. Back on the CloudFront tab, click the **Invalidations** tab.
2. **Create invalidation**.
3. In the box, type exactly:

```
/*
```

4. **Create invalidation**. It takes a minute or two.

---

## Step 6: Test

Open this in a new tab:

```
https://mycdn.adspace.me/content/e31fa3eb-7808-44ad-b5e7-c62ffce5ddc3/ce3efc27-a07a-46dd-857c-fee6595218e0.jpg
```

- **The file downloads or plays.** Fixed. Go to `/admin/`, delete the broken posts and
  import them again.
- **Still Access Denied.** Send me a screenshot of the bucket policy box from Step 3 and
  what the Origin access section said in Step 2. Redact the numbers in any `arn:aws:iam::`
  line if you like, they are your account id.

---

## Why the portal will not let you upload until this is fixed

The portal now checks that a file is actually readable before saving the post. Until reads
are allowed you will get an error at upload time. That is deliberate. The alternative is a
client opening their review link and finding a broken video, which is worse.
