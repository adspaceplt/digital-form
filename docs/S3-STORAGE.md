# Storage: the bucket, the sweep, the keys and the lifecycle rule

| | |
| --- | --- |
| Bucket | `myadspace` |
| Region | `ap-southeast-5` (Malaysia) |
| Prefix | `content` |
| Public read | CloudFront at `https://mycdn.adspace.me` |
| Writes | `sign-upload` edge function, signed PUT, key chosen by the function |
| Deletes | `s3-sweep` edge function only, daily, never while a row points at the file |

Do the four parts in this order. Parts 1 and 2 are the AWS console, part 3 is
Supabase, part 4 turns the deletes on after a dry run has been read.

1. [The IAM split](#1-the-iam-split): the portal's key can only upload; a
   second key can only list and delete.
2. [The lifecycle rule](#2-the-lifecycle-rule): abandoned uploads and old
   versions are cleaned by AWS.
3. [The sweep](#3-the-sweep): deploy, schedule, read the first dry run.
4. [Turning the deletes on](#4-turning-the-deletes-on).

## How a file gets in, and how it leaves

The browser asks `sign-upload` for permission; the function checks who is
asking and **chooses the path itself**:

```
content/{clientId}/{uuid}.{ext}          uploaded from the console
content/creator/{optionId}/{uuid}.{ext}  handed in by a creator
```

The link is then written to a row. When the row goes (a set deleted, a client
deleted, a draft removed), the file used to stay in the bucket for ever. Now:

- **`s3_keys_in_use(keys)`** (database, service role only) answers which keys
  are still referenced. A key is in use while **any row anywhere** in the
  database holds it: every text, JSON and list column of every table, read
  whole, including `posts.media`, Drive imports and their posters, campaign
  invoices, client logos, document file links and history rows. A column
  added later is covered the day it is added.
- A **soft-removed draft** (`campaign_deliverables.removed_at`) stays in use
  for **30 days**, because Undo puts the row back.
- **`s3-sweep`** lists `content/`, skips anything **younger than 7 days** (an
  upload in flight, a row still being written), asks the database about the
  rest, and deletes what nothing references.
- It is a **dry run** unless the secret `S3_SWEEP_DELETE` is exactly `on`.
- Even when on, a run is **held** (deletes nothing) if the database names no
  file in use at all, or if more than 500 files (`S3_SWEEP_MAX`) would go at
  once.
- Every run files one row in `s3_sweeps`.
- **Never keep a file under `content/` by hand.** Anything there that no row
  names is removed. The brand mark and favicon live at the bucket root,
  outside the sweep.

---

## 1. The IAM split

Two users, each able to do one thing, owned by no person:

| User | Can | Used by | Supabase secrets |
| --- | --- | --- | --- |
| `adspace-portal-upload` | `s3:PutObject` on `content/*` | `sign-upload` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `adspace-s3-sweeper` | list `content/`, `s3:DeleteObject` on `content/*` | `s3-sweep` | `S3_SWEEP_KEY_ID`, `S3_SWEEP_SECRET` |

Supabase secrets are shared by every function in the project, which is why
the sweeper's key has names of its own: `sign-upload` never reads them.

### 1a. The two policies

Sign in to the AWS console as yourself (with MFA), not with a service key.

1. Search bar → **IAM** → left menu **Policies** → **Create policy**.
2. **Policy editor**: choose **JSON**, delete what is there, paste:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "PortalWritesContentOnly",
         "Effect": "Allow",
         "Action": "s3:PutObject",
         "Resource": "arn:aws:s3:::myadspace/content/*"
       }
     ]
   }
   ```

3. **Next** → Policy name `adspace-portal-upload` → **Create policy**.
4. **Create policy** again, **JSON**, paste:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "SweepListsContentOnly",
         "Effect": "Allow",
         "Action": "s3:ListBucket",
         "Resource": "arn:aws:s3:::myadspace",
         "Condition": { "StringLike": { "s3:prefix": ["content/*"] } }
       },
       {
         "Sid": "SweepDeletesContentOnly",
         "Effect": "Allow",
         "Action": "s3:DeleteObject",
         "Resource": "arn:aws:s3:::myadspace/content/*"
       }
     ]
   }
   ```

5. **Next** → Policy name `adspace-s3-sweeper` → **Create policy**.

### 1b. The two users and their keys

For each of the two names (`adspace-portal-upload`, then `adspace-s3-sweeper`):

1. IAM → **Users** → **Create user**.
2. User name: the name. Leave **Provide user access to the AWS Management
   Console** unticked. **Next**.
3. **Permissions options**: **Attach policies directly**. Search the policy of
   the same name, tick it. **Next** → **Create user**.
4. Open the new user → **Security credentials** tab → **Access keys** →
   **Create access key**.
5. Use case: **Application running outside AWS** → **Next** → description tag
   `supabase` → **Create access key**.
6. Copy the **Access key ID** and the **Secret access key** now; the secret is
   shown once. Paste them straight into Supabase (below), never into a chat,
   a file or an email. **Done**.

### 1c. Moving the portal onto its new key, in order

The upload key in use today may be a broad one. Replace it without a gap:

1. Supabase → project → **Edge Functions** → **Secrets**.
2. Edit `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to the
   `adspace-portal-upload` key. Save.
3. Add `S3_SWEEP_KEY_ID` and `S3_SWEEP_SECRET` with the `adspace-s3-sweeper`
   key.
4. Confirm uploads: in the console, open a client in Content Review and upload
   an image to a set; open a campaign and hand a file in for a creator. Both
   must finish and play. If either says the upload was refused, put the old
   two values back (step 2) and check the policy's bucket name.
5. AWS → IAM → **Users** → the **old** user → **Security credentials** →
   **Access keys** → the old key → **Actions** → **Deactivate**. Deactivate,
   not delete: it can be turned back on in one click.
6. After a week with uploads working, and the old key's **Last used** not
   moving, **Actions** → **Delete** it. If that old user belongs to a person,
   leave the person; if it was a service user with nothing else on it, delete
   the user too.

Never delete the old key first.

---

## 2. The lifecycle rule

### 2a. Check whether versioning is on

S3 → **Buckets** → `myadspace` → **Properties** → **Bucket Versioning**.

- **Enabled**: keep it. A file the sweep deletes becomes a noncurrent version
  and can be restored for 30 days (see 4c).
- **Disabled** or **Suspended**: recommended to enable before part 4, for the
  same reason. **Edit** → **Enable** → **Save changes**. It cannot be turned
  back to Disabled later, only Suspended; the rule below keeps its cost to 30
  days of deleted files.

### 2b. Create the rule

S3 → **Buckets** → `myadspace` → **Management** → **Lifecycle rules** →
**Create lifecycle rule**.

1. **Lifecycle rule name**: `content-housekeeping`.
2. **Choose a rule scope**: **Limit the scope of this rule using one or more
   filters**. **Prefix**: `content/`.
3. **Lifecycle rule actions**, tick only these two:
   - **Permanently delete noncurrent versions of objects**
   - **Delete expired object delete markers or incomplete multipart uploads**
4. **Permanently delete noncurrent versions of objects**: **Days after
   objects become noncurrent** `30`. Leave **Number of newer versions to
   retain** empty.
5. **Delete expired object delete markers or incomplete multipart uploads**:
   tick **Delete incomplete multipart uploads**, **Number of days** `7`.
   Leave **Delete expired object delete markers** unticked.
6. **Never tick "Expire current versions of objects"**, and never
   "Transition current versions" for now (2c). The review timeline at the foot
   must list only the two actions above.
7. **Create rule**. It shows in the list as **Enabled**.

The same rule as JSON, for reference:

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

The noncurrent line does nothing while versioning is off, and costs nothing.

### 2c. The storage-class half, held

Not now. The Free Tier covers S3 **Standard** only, and Standard-IA and
Glacier add a per-object transition charge, a 30-day minimum per object and a
retrieval fee each time a client opens an older file. Below about 100 GB it
saves pennies or costs money.

**Add it once the bucket nears 100 GB, or when the Free Tier's twelve months
end**, whichever comes first: edit `content-housekeeping`, tick **Transition
current versions of objects between storage classes**, and add:

| Storage class | Days after object creation |
| --- | --- |
| Standard-IA | 90 |
| Glacier Instant Retrieval | 365 |

Glacier **Instant** Retrieval because it serves through CloudFront with no
restore step. **Never an expiration action on current versions, at any
size**: cheaper, never lost.

---

## 3. The sweep

### 3a. Secrets

Supabase → **Edge Functions** → **Secrets**. Besides the two keys from 1c:

| Secret | Value |
| --- | --- |
| `S3_SWEEP_TOKEN` | A long random string, e.g. the output of `openssl rand -hex 32`. The schedule sends it; nothing else holds it. |
| `S3_SWEEP_DELETE` | **Leave unset** until part 4. |
| `S3_SWEEP_MAX` | Optional. The most one run may delete; default 500. |
| `S3_BUCKET`, `S3_REGION`, `S3_PREFIX` | Already set for `sign-upload` (`myadspace`, `ap-southeast-5`, `content`). |

### 3b. The database

Run `supabase/migrations/2026-09-28-s3-sweep.sql` in the SQL editor (or the
`-- S3 SWEEP` section at the end of `supabase/schema.sql`). It creates
`s3_keys_in_use` and `s3_sweeps`. It is safe to run again.

### 3c. Deploy the function

From the repository root:

```sh
supabase functions deploy s3-sweep --no-verify-jwt --project-ref hwwuigvdfubuymchsvyx
```

**Verify JWT** must be **off** (Edge Functions → `s3-sweep` → Details): the
caller is the database schedule carrying `S3_SWEEP_TOKEN`, which the function
checks itself. The function is two files, `index.ts` and `logic.mjs`; both
deploy together.

### 3d. The daily schedule

1. Supabase → **Database** → **Extensions**: enable **pg_cron** and
   **pg_net**.
2. SQL editor, once (paste the same token as `S3_SWEEP_TOKEN`):

   ```sql
   select vault.create_secret('https://hwwuigvdfubuymchsvyx.supabase.co', 'project_url');
   select vault.create_secret('PASTE-THE-S3_SWEEP_TOKEN-HERE', 's3_sweep_token');
   ```

3. Run the migration file again. Without steps 1 and 2 it applies and says
   `no schedule was written`; with them it writes the job `s3-sweep-daily`,
   daily at 03:17 Malaysia time.
4. Check: `select jobname, schedule, active from cron.job;`

To stop it: `select cron.unschedule('s3-sweep-daily');`

### 3e. Run it by hand and read the result

```sh
curl -X POST https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/s3-sweep \
  -H "Authorization: Bearer $S3_SWEEP_TOKEN" -H "Content-Type: application/json" -d '{}'
```

`-d '{"dryRun": true}'` forces a dry run even once deletes are on. Every run,
scheduled or by hand, files a row:

```sql
select ran_at, mode, listed, young, kept, would_delete,
       pg_size_pretty(would_delete_bytes) as would_free,
       deleted, pg_size_pretty(deleted_bytes) as freed, failed, note, sample
  from public.s3_sweeps order by ran_at desc limit 10;
```

| Column | Means |
| --- | --- |
| `mode` | `dry` (nothing deleted), `delete`, `held` (the answer looked wrong; nothing deleted), `failed` (S3 or the database did not answer; nothing deleted) |
| `listed` | Every file under `content/` |
| `young` | Under 7 days old, not judged |
| `kept` | Still referenced |
| `would_delete` | Nothing references them |
| `deleted` / `failed` | What went, and what S3 refused (named in `note`) |
| `sample` | Up to 20 of the keys it would remove, or removed |

The schedule's own trail, if a row is missing:
`select * from cron.job_run_details order by start_time desc limit 5;` and
`select status_code, content from net._http_response order by created desc limit 5;`

---

## 4. Turning the deletes on

1. Read at least one `dry` row. Open two or three `sample` keys as
   `https://mycdn.adspace.me/<key>`: each should be a file nobody needs (a
   removed draft, a deleted set's media).
2. Confirm versioning (2a) if you want the 30-day way back.
3. Supabase → Edge Functions → Secrets → add `S3_SWEEP_DELETE` = `on`.
4. The next run's row reads `delete`. To go back to dry runs, delete the
   secret or set it to anything else.

### 4c. Bringing a deleted file back (versioning on, within 30 days)

S3 → `myadspace` → **Objects** → turn on **Show versions** → find the key →
select its **Delete marker** → **Delete** → confirm. The file is current
again at the same link.

---

## Seeing what is in there

```sh
aws s3 ls s3://myadspace/content/ --recursive --human-readable --summarize
aws s3 ls s3://myadspace/content/ --recursive | sort -k3 -n -r | head -10
aws s3api list-multipart-uploads --bucket myadspace
```
