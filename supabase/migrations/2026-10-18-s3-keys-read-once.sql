-- ===========================================================================
-- S3 KEYS READ ONCE — the S3 report's in-use check reads each column once
-- a run, whatever the number of files asked about. 2026-10-18. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in supabase/schema.sql
-- under the same banner; tests/s3sql.js compares the two.
--
-- WHAT CHANGED (second audit, item 16)
--   s3_keys_in_use scanned every text, json and array column of every table
--   once for each key still unresolved: with thousands of files listed and
--   586 such columns live (about 20 MB of text), the nightly report read
--   the database thousands of times over. The rule is unchanged (a file is
--   in use while a handed-in draft holds it, standing or removed within the
--   Undo's 30 days, or while any other column's text contains its key);
--   only the reading is:
--   * every key asked shares a prefix (the listing's `content/`), so any
--     value holding a key holds that prefix: each column is read once, for
--     its values holding it, joined by a character no key holds (chr(1)),
--     so a key is never found across two values;
--   * each key is then sought in that text alone, by the same strpos.
--   A key holding chr(1) itself (none is uploaded) is still sought column by
--   column, as before. The answer is the same set of keys; their order is
--   the order asked.
--
-- ROLLBACK
--   Run the s3_keys_in_use definition of the S3 SWEEP section of
--   supabase/schema.sql again.
-- ===========================================================================

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
  v_rest text[];
  v_hit  text[];
  v_pre  text;
  v_blob text := '';
  v_part text;
  k      text;
  col    record;
begin
  /* An empty key would match every value, so it is never asked. */
  select coalesce(array_agg(distinct x), '{}') into v_ask
    from unnest(coalesce(p_keys, '{}')) x
   where x is not null and btrim(x) <> '';
  if cardinality(v_ask) = 0 then return '{}'; end if;

  /* A handed-in draft: standing, or soft removed within the Undo's 30 days. */
  select coalesce(array_agg(x), '{}') into v_used
    from unnest(v_ask) x
   where exists (select 1 from public.campaign_deliverables d
                  where strpos(d.url, x) > 0
                    and (d.removed_at is null or d.removed_at > now() - interval '30 days'));
  v_rest := array(select x from unnest(v_ask) x where not (x = any(v_used)));
  if cardinality(v_rest) = 0 then return v_used; end if;

  /* What every key left begins with: a value holding a key holds it. */
  v_pre := v_rest[1];
  foreach k in array v_rest loop
    while v_pre <> '' and left(k, length(v_pre)) <> v_pre loop
      v_pre := left(v_pre, length(v_pre) - 1);
    end loop;
  end loop;

  /* Every other text-like column of every table, read once, its values
     holding the prefix joined by a character no key holds. */
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
    execute format('select string_agg(x.%I::text, chr(1)) from public.%I x where strpos(x.%I::text, $1) > 0',
                   col.att, col.tbl, col.att)
      into v_part using v_pre;
    if v_part is not null then v_blob := v_blob || chr(1) || v_part; end if;
  end loop;
  v_hit := array(select x from unnest(v_rest) x where strpos(x, chr(1)) = 0 and strpos(v_blob, x) > 0);
  v_used := v_used || v_hit;

  /* A key holding the joining character itself is sought column by column. */
  if exists (select 1 from unnest(v_rest) x where strpos(x, chr(1)) > 0) then
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
      execute format(
        'select coalesce(array_agg(distinct k), ''{}'') from unnest($1) k
          where exists (select 1 from public.%I x where strpos(x.%I::text, k) > 0)',
        col.tbl, col.att)
        into v_hit
        using array(select x from unnest(v_rest) x where strpos(x, chr(1)) > 0 and not (x = any(v_used)));
      v_used := v_used || v_hit;
    end loop;
  end if;

  return v_used;
end $$;
revoke all on function public.s3_keys_in_use(text[]) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.s3_keys_in_use(text[]) to service_role;
  end if;
end $$;

-- END OF S3 KEYS READ ONCE --------------------------------------------------

select public.functions_tidy();
