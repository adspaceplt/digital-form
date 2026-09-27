-- ===========================================================================
-- S3 SWEEP — a file leaves the bucket only when nothing points at it.
-- 2026-09-28. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/s3sql.js compares the
-- two.
--
-- WHAT CHANGED (the S3 build the user approved on 2026-09-27):
--   The portal writes to S3 and never removed anything, so an object whose
--   row was deleted stayed in the bucket, billed and invisible. The
--   `s3-sweep` edge function now lists `content/`, asks this database which
--   keys are still referenced, and deletes the rest. The portal itself still
--   never deletes from S3; only the sweep does.
--
--   `s3_keys_in_use(p_keys)` answers which of the keys it is given are still
--   referenced. A key is in use while ANY row anywhere in `public` holds it:
--     - a handed-in draft (`campaign_deliverables.url`) while it stands, and
--       for 30 days after it is soft removed, because Undo puts the row back
--       and the client's page would then point at a file that is gone;
--     - every other text, varchar, json, jsonb or text[] column of every
--       table in `public`, read whole: `posts.media` (url and poster inside
--       the jsonb), `drive_assets.url` and `poster_url`, `campaigns
--       .invoice_url`, `clients.logo_url`, `documents.file_url`, a pasted
--       draft link, a history row. A column added later is covered the day
--       it is added, without this file changing.
--   Matching is by the key appearing anywhere in the value, so a CDN link, a
--   bucket link and a bare key all count, and a near miss keeps a file
--   rather than losing one.
--
--   `s3_sweeps` is one row per run: listed, too young to judge (under 7
--   days), kept, deleted and would-delete, each with its bytes. Row level
--   security on, no policy: only the service role reads or writes it.
--   Read it in the SQL editor:
--     select * from public.s3_sweeps order by ran_at desc limit 10;
--
--   The daily schedule is written only where pg_cron and pg_net are both
--   installed and the two Vault secrets it reads exist (see
--   docs/S3-STORAGE.md). Otherwise the file still applies and says so.
--
-- ROLLBACK
--   select cron.unschedule('s3-sweep-daily');   -- where it was scheduled
--   drop function if exists public.s3_keys_in_use(text[]);
--   drop table if exists public.s3_sweeps;
-- ===========================================================================

create table if not exists public.s3_sweeps (
  id                 uuid primary key default gen_random_uuid(),
  ran_at             timestamptz not null default now(),
  mode               text not null check (mode in ('dry', 'delete', 'held', 'failed')),
  prefix             text not null,
  listed             integer not null default 0,
  listed_bytes       bigint  not null default 0,
  young              integer not null default 0,
  young_bytes        bigint  not null default 0,
  kept               integer not null default 0,
  kept_bytes         bigint  not null default 0,
  would_delete       integer not null default 0,
  would_delete_bytes bigint  not null default 0,
  deleted            integer not null default 0,
  deleted_bytes      bigint  not null default 0,
  failed             integer not null default 0,
  note               text,
  sample             text[] not null default '{}'
);
create index if not exists s3_sweeps_ran_idx on public.s3_sweeps (ran_at desc);

alter table public.s3_sweeps enable row level security;
revoke all on public.s3_sweeps from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant select, insert on public.s3_sweeps to service_role;
  end if;
end $$;

create or replace function public.s3_keys_in_use(p_keys text[])
returns text[]
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_ask  text[];
  v_used text[];
  v_hit  text[];
  col    record;
begin
  /* An empty key would match every value, so it is never asked. */
  select coalesce(array_agg(distinct k), '{}') into v_ask
    from unnest(coalesce(p_keys, '{}')) k
   where k is not null and btrim(k) <> '';
  if cardinality(v_ask) = 0 then return '{}'; end if;

  /* A handed-in draft: standing, or soft removed within the Undo's 30 days. */
  select coalesce(array_agg(k), '{}') into v_used
    from unnest(v_ask) k
   where exists (select 1 from public.campaign_deliverables d
                  where strpos(d.url, k) > 0
                    and (d.removed_at is null or d.removed_at > now() - interval '30 days'));

  /* Every other text-like column of every table, whole. Only the keys not
     yet known to be in use are carried to the next column. */
  for col in
    select c.relname as tbl, a.attname as att
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and a.attnum > 0 and not a.attisdropped
       and a.atttypid in ('text'::regtype, 'character varying'::regtype, 'json'::regtype,
                          'jsonb'::regtype, 'text[]'::regtype, 'character varying[]'::regtype)
       and not (c.relname = 'campaign_deliverables' and a.attname = 'url')
       and c.relname <> 's3_sweeps'
     order by c.relname, a.attnum
  loop
    exit when cardinality(v_ask) = cardinality(v_used);
    execute format(
      'select coalesce(array_agg(distinct k), ''{}'') from unnest($1) k
        where exists (select 1 from public.%I x where strpos(x.%I::text, k) > 0)',
      col.tbl, col.att)
      into v_hit
      using array(select k from unnest(v_ask) k where not (k = any(v_used)));
    v_used := v_used || v_hit;
  end loop;

  return v_used;
end $$;
revoke all on function public.s3_keys_in_use(text[]) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.s3_keys_in_use(text[]) to service_role;
  end if;
end $$;

/* Daily at 03:17 in Malaysia (19:17 UTC). The call carries the sweep's own
   token from Vault; the key and the project address never enter this file. */
do $$
declare
  n integer := 0;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 's3-sweep: pg_cron and pg_net are not both installed, so no schedule was written. See docs/S3-STORAGE.md.';
    return;
  end if;
  if to_regclass('vault.decrypted_secrets') is not null then
    execute $q$select count(*) from vault.decrypted_secrets
               where name in ('project_url', 's3_sweep_token')$q$ into n;
  end if;
  if n < 2 then
    raise notice 's3-sweep: the Vault secrets project_url and s3_sweep_token are not both set, so no schedule was written. See docs/S3-STORAGE.md.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 's3-sweep-daily';
  perform cron.schedule('s3-sweep-daily', '17 19 * * *', $cmd$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
                 || '/functions/v1/s3-sweep',
      headers := jsonb_build_object(
                   'Content-Type', 'application/json',
                   'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
                                                  where name = 's3_sweep_token')),
      body    := '{}'::jsonb,
      timeout_milliseconds := 60000);
  $cmd$);
end $$;

-- END OF S3 SWEEP ------------------------------------------------------------
