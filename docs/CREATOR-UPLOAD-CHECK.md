# Creator upload — production check

Run this once, on the live site, after applying
`supabase/migrations/2026-09-15-creator-add-file.sql`. It takes about ten minutes
and needs one real booking sitting at **Pending draft**.

Nothing here can be checked from a test environment: the signing function, the S3
bucket, the CORS rule and the CloudFront distribution are all live services, and
the last failure was in a database function that applied cleanly and only failed
when it was called.

## Before you start

1. Supabase dashboard → SQL editor → run the migration file above. Nothing else
   from `supabase/schema.sql` is needed for this fix.
2. Confirm it took, in the same editor:

   ```sql
   select prosrc not like '%where id = p_option%' as fixed
     from pg_proc where proname = 'creator_add_file';
   ```

   `fixed` must be `true`.
3. Open the campaign in the console, find the creator on **Pending draft**, and
   use the link icon on their card to copy their portal link.

## The check

Open the creator link on a phone, in a normal browser window.

| # | Step | What must happen |
|---|---|---|
| 1 | Pick one image | The bar moves, the percentage climbs, the right side reads `Saving` at the end, then `Uploaded.` and a thumbnail |
| 2 | Look at the console, campaign, that creator's card | The same file is listed under Draft |
| 3 | Pick two more files at once | The label counts `1/2` then `2/2`, and both appear |
| 4 | Pick a video over 1 GB (1024 MB) | Refused by name before anything uploads: `<file> is larger than 1024 MB.` Nothing is added |
| 5 | Pick a video of roughly 500 MB to 1 GB | Completes. Time it: a 1 GB file on a domestic line takes many minutes and the bar must keep moving throughout |
| 6 | Turn flight mode on midway through an upload | Within two minutes it stops and names the file that failed. Nothing is left on a full bar |
| 7 | Turn flight mode off and pick the same file again | It uploads normally |
| 8 | Remove one file with its × | It goes, on the creator's page and in the console |
| 9 | Type a caption and press Submit | The step moves to **Reviewing**, the × disappears, and Submit is gone |
| 10 | Console, same card | The files and the caption are both there |

## If step 1 fails

Open the browser console on the creator's page. The failure is logged as
`[creator upload] <file name>` with the reason.

| Reason | Cause | Fix |
|---|---|---|
| `column reference "id" is ambiguous` | The migration was not applied | Run it |
| `not_allowed` | The code, the booking or the step | The creator must be active and the booking at Pending draft or Changes requested |
| `Edge Function returned a non-2xx status code` | `sign-upload` is not deployed, or Verify JWT is on | `supabase functions deploy sign-upload`, then turn Verify JWT **off** in the dashboard |
| A CORS error on the PUT | The bucket's CORS rule | See `S3-UPLOAD-SETUP.md`, section 2 |
| `storage rejected the upload (HTTP 403)` | The signed URL or the IAM policy | See `S3-UPLOAD-SETUP.md`, section 1 |

## What is already covered by the suites

These do not replace the run above, but they are what the run is confirming:

- `tests/sql.js` runs the whole delivery path against a real Postgres 16: a code
  is issued, an upload is allowed, a file is recorded, several files land on one
  booking, 1 GB is stored to the byte, submitting moves the step and keeps the
  caption, a submitted file cannot be pulled back off, an invalid code reaches
  nothing, and the migration applies on its own and again.
- `tests/creator.js` drives a real browser: both files attach, each goes straight
  to storage under a key built from the booking, a save the database refuses is
  reported by name, a file over the limit is refused before anything uploads, and
  the console shows the file and the caption afterwards.
