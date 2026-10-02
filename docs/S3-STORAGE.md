# Storage: the bucket, the keys, the lifecycle rule and the daily report

| | |
| --- | --- |
| Bucket | `myadspace` |
| Region | `ap-southeast-5` (Malaysia) |
| Prefix | `content` |
| Public read | CloudFront at `https://mycdn.adspace.me` |
| Writes | `sign-upload` edge function, signed PUT, key chosen by the function |
| Deletes | None. Every uploaded file is kept (the user, 2026-09-28) |
| Report | `s3-sweep` edge function, daily: what the bucket holds and what no row names |

Do the three parts in this order. Parts 1 and 2 are the AWS console, part 3 is
Supabase. Part 4 records that nothing is deleted.

1. [The IAM split](#1-the-iam-split): the portal's key can only upload; a
   second key can only list.
2. [The lifecycle rule](#2-the-lifecycle-rule): abandoned uploads and old
   versions are cleaned by AWS.
3. [The daily report](#3-the-daily-report): deploy, schedule, read the first
   run.
4. [Deletes: none](#4-deletes-none).
5. [Private invoices](#5-private-invoices): a campaign's invoice PDF behind a
   five-minute link.

## How a file gets in, and why it stays

The browser asks `sign-upload` for permission; the function checks who is
asking and **chooses the path itself**:

```
content/{clientId}/{uuid}.{ext}          uploaded from the console
content/creator/{optionId}/{uuid}.{ext}  handed in by a creator
```

The link is then written to a row. When the row goes (a set deleted, a client
deleted, a draft removed), the file stays in the bucket. That is deliberate:
every uploaded file is kept, Content Review files and creator drafts included
(the user, 2026-09-28: "all these couldnt be deleted or removed"). Nothing in
the portal deletes from S3, and `s3-sweep` has no delete in it. What the daily
report tells you:

- **`s3_keys_in_use(keys)`** (database, service role only) answers which keys
  are still referenced. A key is in use while **any row anywhere** in the
  database holds it: every text, JSON and list column of every table, read
  whole, including `posts.media`, Drive imports and their posters, campaign
  invoices, client logos, document file links and history rows. A column
  added later is covered the day it is added.
- A **soft-removed draft** (`campaign_deliverables.removed_at`) counts as in
  use for **30 days**, because Undo puts the row back; after that it is
  counted as named by no row, and kept like everything else.
- **`s3-sweep`** lists `content/`, skips anything **younger than 7 days** (an
  upload in flight, a row still being written), asks the database about the
  rest, and files one row in `s3_sweeps`: files and bytes in use, too young
  to judge, and named by no row. The only request it sends S3 is a list.
- A run reads **held** when the database names no file in use at all: that
  day's count of files named by no row is not trusted.
- A file put under `content/` by hand is kept like any other; the report
  counts it as named by no row. The brand mark and favicon live at the bucket
  root, outside the report.

---

## 1. The IAM split

Two users, each able to do one thing, owned by no person. Neither can
delete:

| User | Can | Used by | Supabase secrets |
| --- | --- | --- | --- |
| `adspace-portal-upload` | `s3:PutObject` on `content/*` | `sign-upload` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `adspace-s3-sweeper` | list `content/` | `s3-sweep` | `S3_SWEEP_KEY_ID`, `S3_SWEEP_SECRET` |

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
       }
     ]
   }
   ```

5. **Next** → Policy name `adspace-s3-sweeper` → **Create policy**.

A sweeper policy made before 2026-09-28 also carried a
`SweepDeletesContentOnly` statement (`s3:DeleteObject`). Take it out: IAM →
**Policies** → `adspace-s3-sweeper` → **Edit** → delete that block, and the
comma before it → **Next** → **Save changes**. The report needs only the list.

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

- **Enabled**: keep it. A file overwritten, or removed by hand in the AWS
  console, becomes a noncurrent version and can be restored for 30 days (see
  4).
- **Disabled** or **Suspended**: recommended to enable, for the same reason.
  **Edit** → **Enable** → **Save changes**. It cannot be turned back to
  Disabled later, only Suspended; the rule below keeps its cost to 30 days of
  replaced files.

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

## 3. The daily report

### 3a. Secrets

Supabase → **Edge Functions** → **Secrets**. Besides the two keys from 1c:

| Secret | Value |
| --- | --- |
| `S3_SWEEP_TOKEN` | A long random string, e.g. the output of `openssl rand -hex 32`. The schedule sends it; nothing else holds it. |
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

Every run, scheduled or by hand, files a row:

```sql
select ran_at, mode, pg_size_pretty(listed_bytes) as total, listed, young, kept,
       would_delete as unused, pg_size_pretty(would_delete_bytes) as unused_size, note, sample
  from public.s3_sweeps order by ran_at desc limit 10;
```

| Column | Means |
| --- | --- |
| `mode` | `dry` (a report), `held` (the database named no file in use; the unused count is not trusted), `failed` (S3 or the database did not answer). Nothing is deleted in any of them |
| `listed` | Every file under `content/` |
| `young` | Under 7 days old, not judged |
| `kept` | Still named by a row |
| `would_delete` | Named by no row (the column keeps its first name); kept all the same |
| `deleted` | Always 0 |
| `sample` | Up to 20 of the files named by no row |

The schedule's own trail, if a row is missing:
`select * from cron.job_run_details order by start_time desc limit 5;` and
`select status_code, content from net._http_response order by created desc limit 5;`

---

## 4. Deletes: none

Withdrawn on 2026-09-28, before it was ever turned on: the first run named 18
files (189 MB) no row points at, among them Content Review files the user
keeps, and the user decided every uploaded file stays. The sweep's delete was
taken out of its code; `S3_SWEEP_DELETE` and `S3_SWEEP_MAX` are no longer
read, and setting them changes nothing.

### Bringing back a file removed by hand (versioning on, within 30 days)

S3 → `myadspace` → **Objects** → turn on **Show versions** → find the key →
select its **Delete marker** → **Delete** → confirm. The file is current
again at the same link.

---

## 5. Private invoices

A campaign's invoice PDF is the one document the portal puts on S3. From
2026-10-02 a new one is uploaded under `private/` and is never served by
CloudFront: the console's View invoice and the client's PDF link ask
`sign-download` for a link that works for **five minutes**. The function finds
the file from what the caller may already read (the campaign row for a
colleague; what `get_campaign` gives the client's own link), never from a path
the browser sends.

```
private/{clientId}/{uuid}.pdf            a campaign's invoice, from 2026-10-02
```

Invoices uploaded before keep their public CloudFront address (nothing is
moved or deleted). To close one, open the campaign → Finance → Remove PDF,
then upload it again once the switch below is on.

Until steps 5a and 5b are done, `privateInvoices` in `js/config.js` stays
`false` and invoices upload exactly as before. Claude turns it on once you
say the two steps are done.

### 5a. The upload key may write and read `private/`

1. IAM → **Users** → open the user whose key is in Supabase as
   `AWS_ACCESS_KEY_ID` (`adspace-portal-upload`, or the older upload user if
   that key has not been rotated yet). Copy its **ARN** from the summary at
   the top (`arn:aws:iam::<account>:user/<name>`); 5b needs it.
2. **Permissions** tab → open its policy → **Edit** → **JSON**, and add this
   statement inside `"Statement": [ … ]` (a comma after the one before it):

   ```json
   {
     "Sid": "PortalPrivateInvoices",
     "Effect": "Allow",
     "Action": ["s3:PutObject", "s3:GetObject"],
     "Resource": "arn:aws:s3:::myadspace/private/*"
   }
   ```

3. **Next** → **Save changes**. It grants no delete and nothing outside
   `private/`.

### 5b. Nobody else reads `private/`

1. S3 → **myadspace** → **Permissions** → **Bucket policy** → **Edit**.
2. Add this statement inside `"Statement": [ … ]`, with the ARN from 5a in
   place of `UPLOAD-USER-ARN`:

   ```json
   {
     "Sid": "PrivateOnlyThroughSignedLinks",
     "Effect": "Deny",
     "Principal": "*",
     "Action": "s3:GetObject",
     "Resource": "arn:aws:s3:::myadspace/private/*",
     "Condition": { "StringNotEquals": { "aws:PrincipalArn": "UPLOAD-USER-ARN" } }
   }
   ```

3. **Save changes**. This shuts CloudFront and every other reader out of
   `private/` whatever the rest of the policy allows, and leaves `content/`
   and the brand files exactly as they are. A link signed by `sign-download`
   is the upload user reading, so it still works.

### 5c. Check

Tell Claude the two steps are done. Claude turns `privateInvoices` on, then:
an invoice uploaded in the console opens from View invoice and from the
client's PDF link, its link stops working after five minutes, and
`https://mycdn.adspace.me/private/…` answers **403**.

---

## Seeing what is in there

```sh
aws s3 ls s3://myadspace/content/ --recursive --human-readable --summarize
aws s3 ls s3://myadspace/content/ --recursive | sort -k3 -n -r | head -10
aws s3api list-multipart-uploads --bucket myadspace
```
