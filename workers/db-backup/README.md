# Nightly database backup

The portal's Supabase project is on the Free plan, which keeps no backups of
its own. Every night at 02:37 Malaysia time a GitHub Actions run
(`.github/workflows/db-backup.yml`) takes Supabase's own dump of the database
(roles, schema and data, as Supabase's restore guide prescribes), encrypts it
with a passphrase, and keeps it in the bucket at
`private/backups/db/db-YYYY-MM-DD.tar.gz.gpg`. CloudFront never serves
`private/`. The run never reads, lists or deletes anything in the bucket.

What it covers: every table, function, policy and trigger, and the sign-in
accounts (`auth.users`). What it does not: files in Supabase Storage (the
Handbook bucket), the edge functions and their secrets (the functions are in
this repository), and dashboard settings.

## Set up (once, by the account owner)

1. **An AWS key that can only add backups.** In IAM, create a user
   `adspace-db-backup` with this policy and nothing else, then make an access
   key for it:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": "s3:PutObject",
       "Resource": "arn:aws:s3:::myadspace/private/backups/db/*"
     }]
   }
   ```

2. **The database's connection string.** In Supabase, open the project,
   press **Connect**, and copy the **Session pooler** string (GitHub's
   machines reach the pooler; the direct address needs IPv6). Put the
   database password into it.

3. **A passphrase.** Make a long random passphrase and keep it in the
   company's password manager. Without it no backup can be opened; it is
   never stored anywhere else.

4. **Four repository secrets.** In GitHub, open this repository's
   Settings, then Secrets and variables, then Actions, and add:
   `SUPABASE_DB_URL`, `BACKUP_PASSPHRASE`, `BACKUP_AWS_ACCESS_KEY_ID`,
   `BACKUP_AWS_SECRET_ACCESS_KEY`.

5. **Make the failure emails yours.** GitHub emails a failed scheduled run
   to whoever last changed or re-enabled the schedule, which would otherwise
   be the commit that added it. In Actions, open Database backup, press the
   ⋯, Disable workflow, then Enable workflow.

6. **Run it once by hand.** Actions, Database backup, Run workflow. The last
   line reads `backup: kept private/backups/db/db-… (n bytes)`; the file is
   in the S3 console under `private/backups/db/`.

## Restore (never over the live project first)

1. Download the night's file from the S3 console.
2. Open it: `gpg -d db-YYYY-MM-DD.tar.gz.gpg | tar -xzf -` (asks for the
   passphrase), which gives `roles.sql`, `schema.sql` and `data.sql`.
3. Make a **new** Supabase project and restore into it, as Supabase's guide
   does:

   ```sh
   psql --single-transaction --variable ON_ERROR_STOP=1 \
     --file roles.sql --file schema.sql \
     --command 'SET session_replication_role = replica' \
     --file data.sql --dbname "<the new project's connection string>"
   ```

4. Check it (the clients, the team, a report), then decide whether to point
   the portal at it (`js/config.js`) or copy the lost rows back.

## How long backups are kept

Each file is a few megabytes. Nothing deletes them. An S3 lifecycle rule on
`private/backups/db/` alone may expire them after a period the owner
chooses; never on `content/` or the rest of `private/`.
