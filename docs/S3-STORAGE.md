# Storage: what grows, what costs, and what to do about it

The portal writes to S3 and never removes anything. This file is the three
things that fixes, in the order they are worth doing. **Step 1 is ten minutes
in the AWS console and needs no code**, and while the bucket is small it is
worth doing for the leak it stops rather than for the money it saves: at this
size the storage bill is pennies and the real exposure is files nobody can
see. Steps 2 and 3 are code and are not built yet.

## What happens today

| | |
| --- | --- |
| Bucket | `myadspace` |
| Region | `ap-southeast-5` (Malaysia) |
| Prefix | `content` |
| Public read | CloudFront at `https://mycdn.adspace.me` |

A file reaches the bucket one way only. The browser asks the `sign-upload`
edge function for permission, the function checks who is asking and **chooses
the path itself** — the browser never picks it:

```
content/{clientId}/{uuid}.{ext}          uploaded from the console
content/creator/{optionId}/{uuid}.{ext}  handed in by a creator
```

The AWS keys live in that function's secrets and never reach a browser. The
resulting URL is then written to a database row, and **that row is the only
record the portal has of the object**. Nothing in the console lists the
bucket, and the portal never asks S3 what it holds.

### The gap

An **orphan** is an object in the bucket that no row points at any more:
an upload that finished after the row failed to save, a content set that was
deleted, a client that was deleted. It is invisible to the portal, invisible
in any list, and costs storage every month for ever.

There is also no expiry on anything, and no cleanup of **incomplete multipart
uploads** — a 1 GB video whose upload was abandoned half way leaves its parts
in the bucket, billable, and they are not visible in the normal object list.

---

## 1. The lifecycle rule — do this first, but only half of it now

The rule has two halves and they are worth doing at **different times**. The
housekeeping half is worth doing today and costs nothing. The storage-class
half is worth nothing today and can cost slightly more than it saves.

### Now: the housekeeping half

**AWS console → S3 → `myadspace` → Management → Lifecycle rules → Create.**

Name it `content-housekeeping`, scope it to the prefix `content/`, and set one
action only:

| Action | Value | Why |
| --- | --- | --- |
| Delete expired object delete markers or incomplete multipart uploads | **7 days** | An abandoned 1 GB upload is billable storage that does not appear in the object list, so nobody will ever notice it. At a 1 GB ceiling per file, one abandoned upload is a fifth of the Free Tier's whole 5 GB. Seven days is well past any real retry. |

```json
{
  "Rules": [
    {
      "ID": "content-housekeeping",
      "Status": "Enabled",
      "Filter": { "Prefix": "content/" },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 30 }
    }
  ]
}
```

`NoncurrentVersionExpiration` only does anything if bucket versioning is on.
It is harmless if it is off, and if it is on it is the line that stops every
overwritten file being kept for ever. Every key the portal writes carries a
UUID, so the portal itself never overwrites one.

### Later: the storage-class half

**Do not add these while the bucket is small.** The Free Tier covers S3
**Standard** only; Standard-IA and Glacier are not in it. So on a bucket
inside the free allowance, a transition moves data *out* of what is free and
*into* what is billed, and adds three charges that Standard does not have:

- a per-request charge for each object moved,
- a 30 day minimum billing period per object in IA, so a file corrected and
  replaced after a week is still billed for a month,
- a per-GB retrieval fee every time a client opens an older file.

The saving is a fraction of a cent per GB per month. Below roughly 100 GB the
whole exercise is worth pennies and can be negative.

**Add them when the monthly bill shows an S3 storage line you would rather
reduce** — in practice once the bucket is past about 100 GB, or once the Free
Tier's twelve months end, whichever comes first. Then edit the same rule and
add:

```json
"Transitions": [
  { "Days": 90,  "StorageClass": "STANDARD_IA" },
  { "Days": 365, "StorageClass": "GLACIER_IR" }
]
```

90 rather than 30 because of the IA minimum above; Glacier **Instant**
Retrieval rather than Flexible or Deep Archive because it still serves through
CloudFront with no restore step, so nothing on a client's page breaks.

**Do not add an expiration action, at any size.** A client asking for last
year's reel and being told it is gone is worse than the storage bill. Cheaper,
never deleted.

---

## 2. Deleting an object when its row goes — not built

The portal deletes rows and leaves objects. Closing that needs two pieces:

**The predicate.** Before any object is removed, the database has to answer
"does any row still point at this URL". That is not one column: it is
`campaign_deliverables.file_url`, `campaigns.invoice_url`, `clients.logo_url`,
`drive_assets.url`, and — the awkward one — **inside `posts.media`, which is a
jsonb array of `{url, type, poster}`**, so it is a jsonb scan and not a column
comparison. A soft-removed deliverable has to count as *still in use*, because
its Undo restores the row and the client's page would then point at a file
that is gone.

**The remover.** A `delete-upload` edge function beside `sign-upload`, holding
the same keys, which refuses to delete anything the predicate says is in use —
whatever the browser sends. The browser never names a key; it names a URL and
the function resolves it inside the configured prefix.

This is deliberately not written yet. It is irreversible, it is the one thing
in this portal that would destroy a client's asset with no way back, and the
lifecycle rule above removes the cost pressure that would justify rushing it.
When it is built it follows the portal's own law: soft first, then a stated
consequence, then the act.

## 3. Splitting the IAM identity — not built

Today one access key is used by `sign-upload`. Two things are wrong with that
and neither is urgent, but both are worth fixing before the team grows:

- **The portal's key should only be able to write under `content/`.** Scope it
  with a policy that names the prefix, so a leaked key cannot reach the rest
  of the bucket or any other bucket.
- **A person's console login is not a service key.** Anybody who needs to look
  in the bucket should sign in to the AWS console as themselves, with MFA, and
  the portal's key should belong to no person at all.

The policy the portal's own user needs, and nothing more:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PortalWritesContentOnly",
      "Effect": "Allow",
      "Action": ["s3:PutObject"],
      "Resource": "arn:aws:s3:::myadspace/content/*"
    }
  ]
}
```

Add `s3:DeleteObject` on the same resource only when step 2 ships, and not
before: a key that cannot delete cannot be made to delete.

**Rotating the key** is: create a second access key for the same user, put it
in the Supabase function secrets (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`), redeploy `sign-upload`, confirm an upload works from
the console, then delete the first key. Never delete the old key first.

---

## Seeing what is actually in there

Until a storage view exists in the console, this is the AWS CLI:

```sh
# Everything, with sizes
aws s3 ls s3://myadspace/content/ --recursive --human-readable --summarize

# The ten largest objects
aws s3 ls s3://myadspace/content/ --recursive \
  | sort -k3 -n -r | head -10

# What incomplete multipart uploads are costing you right now
aws s3api list-multipart-uploads --bucket myadspace
```

The last one is worth running before you set the lifecycle rule, so you can
see what it is about to clean up.
