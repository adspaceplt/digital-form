-- ===========================================================================
-- S3 REPORT READS WHAT HOLDS A FILE (2026-11-18)
-- ===========================================================================
-- WHY: the daily S3 report of 2026-11-18 failed, "canceling statement due to
-- statement timeout": `s3_keys_in_use` read every text column whole, 13.8
-- seconds against the 8 the call is given, 6.6 of them a published report's
-- snapshot (23 MB, its ads' and posts' pictures held as data) and the two
-- thumbnail columns.
--
-- WHAT IT CHANGES
--   * `s3_keys_in_use`: a `thumb_data` column (data:image alone, by its
--     check) is not read; a report version's snapshot is read in its report
--     part alone, the one part that names a file (the client's logo). Every
--     other column is read as before.
--
-- ORDER: this file (connector). Safe to run twice. No page calls it.
--
-- ROLLBACK: run s3_keys_in_use from S3 KEYS READ ONCE again.
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
       -- a picture held as data:image (its column's check) names no file
       and a.attname <> 'thumb_data'
     order by c.relname, a.attnum
  loop
    /* A published report's snapshot names a file only in its report part
       (the client's logo); its ads and posts are pictures held as data, so
       that part alone is read (2026-11-18: the whole of it took 4.8 of the
       call's 8 seconds, and the report failed). */
    execute format('select string_agg((%1$s)::text, chr(1)) from public.%2$I x where strpos((%1$s)::text, $1) > 0',
                   case when col.tbl = 'sm_report_versions' and col.att = 'snapshot'
                        then 'x.snapshot->''report''' else format('x.%I', col.att) end, col.tbl)
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
         -- a picture held as data:image (its column's check) names no file
         and a.attname <> 'thumb_data'
       order by c.relname, a.attnum
    loop
      execute format(
        'select coalesce(array_agg(distinct k), ''{}'') from unnest($1) k
          where exists (select 1 from public.%I x where strpos((%s)::text, k) > 0)',
        col.tbl, case when col.tbl = 'sm_report_versions' and col.att = 'snapshot'
                      then 'x.snapshot->''report''' else format('x.%I', col.att) end)
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

-- END OF S3 REPORT READS WHAT HOLDS A FILE -------------------------------------

select public.functions_tidy();
