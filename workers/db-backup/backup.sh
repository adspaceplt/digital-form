#!/usr/bin/env bash
# The portal's database, kept every night (the user, 2026-10-10: the Free
# plan holds no Supabase backups). Supabase's own dump (roles, schema, data,
# as its guide to restoring a project prescribes), packed, encrypted with the
# backup passphrase, and put under the bucket's private/backups/db/, which
# CloudFront never serves. Nothing here reads, lists or deletes anything in
# the bucket. Run by .github/workflows/db-backup.yml; see README.md.
#
# Needs: SUPABASE_DB_URL (the session pooler's connection string),
# BACKUP_PASSPHRASE, S3_BUCKET, S3_REGION, and the AWS key in the usual
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY. Never prints any of them.
set -euo pipefail

for v in SUPABASE_DB_URL BACKUP_PASSPHRASE S3_BUCKET S3_REGION; do
  if [ -z "${!v:-}" ]; then echo "backup: $v is not set" >&2; exit 2; fi
done

STAMP="$(TZ=Asia/Kuala_Lumpur date +%Y-%m-%d)"
NAME="db-${STAMP}.tar.gz.gpg"
KEY="private/backups/db/${NAME}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

supabase db dump --db-url "$SUPABASE_DB_URL" -f "$WORK/roles.sql" --role-only
supabase db dump --db-url "$SUPABASE_DB_URL" -f "$WORK/schema.sql"
supabase db dump --db-url "$SUPABASE_DB_URL" -f "$WORK/data.sql" --use-copy --data-only

# A dump that holds no clients is not a backup: stop before it is kept.
if ! grep -Eq '^COPY "?public"?\."?clients"? ' "$WORK/data.sql"; then
  echo "backup: the data dump holds no clients table; nothing kept" >&2
  exit 3
fi
if ! grep -Eq 'CREATE TABLE (IF NOT EXISTS )?"?public"?\."?clients"?' "$WORK/schema.sql"; then
  echo "backup: the schema dump holds no clients table; nothing kept" >&2
  exit 3
fi

tar -C "$WORK" -czf "$WORK/db.tar.gz" roles.sql schema.sql data.sql
gpg --batch --yes --quiet --symmetric --cipher-algo AES256 --pinentry-mode loopback \
  --passphrase-fd 3 -o "$WORK/$NAME" "$WORK/db.tar.gz" 3< <(printf '%s' "$BACKUP_PASSPHRASE")

aws s3 cp "$WORK/$NAME" "s3://${S3_BUCKET}/${KEY}" --region "$S3_REGION" \
  --sse AES256 --only-show-errors

BYTES="$(wc -c < "$WORK/$NAME" | tr -d ' ')"
echo "backup: kept ${KEY} (${BYTES} bytes)"
