-- ===========================================================================
-- REPORT FILE KEPT IN SCOPE — keeping a published version's PDF is a record
-- of what went out, not a change to the client's work: a colleague who may
-- read the report keeps its file, whatever their client scope lets them
-- write. 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/smsql.js
-- compares the two. Runs after CLIENT SCOPE and REPORT FILES KEPT, and
-- replaces two functions they made.
--
-- WHAT CHANGED (the audit of 2026-10-07)
--   `sm_report_keep_file` asks the client at View, but `client_scope_guard`
--   asked every update of `sm_report_versions` at Work, so a colleague at
--   Reports Work whose group sees past clients at View alone was refused
--   with the database's words: the download still worked, the file went
--   unkept and its upload was left unnamed in the bucket.
--   1. `sm_report_keep_file` marks its own write (`adspace.keep_file`, for
--      this transaction alone, cleared after the write).
--   2. `client_scope_guard` lets that one write through on
--      `sm_report_versions`; every other write is asked as before. A page
--      cannot set the mark: PostgREST reaches functions in public alone.
--
-- ROLLBACK
--   Run `client_scope_guard` from CLIENT SCOPE and `sm_report_keep_file`
--   from REPORT FILES KEPT again.
-- ===========================================================================

create or replace function public.client_scope_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  col  text := tg_argv[1];
  o jsonb;
  n jsonb := to_jsonb(new);
begin
  if pg_trigger_depth() > 1 or public.client_scope_free('work') then return new; end if;
  if tg_op = 'UPDATE' and tg_table_name = 'sm_report_versions'
     and coalesce(current_setting('adspace.keep_file', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
    if (kind = 'self' and not public.client_row_seen(o ->> 'stage', o ->> 'owner', 'work'))
       or (kind <> 'self' and not public.client_scope_ok(kind, (o ->> col)::uuid, 'work')) then
      raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
    end if;
  end if;
  if (kind = 'self' and not public.client_row_seen(n ->> 'stage', n ->> 'owner', 'work'))
     or (kind <> 'self' and not public.client_scope_ok(kind, (n ->> col)::uuid, 'work')) then
    raise exception 'This client is outside your access.' using errcode = '42501', hint = 'client-scope';
  end if;
  return new;
end $$;
revoke all on function public.client_scope_guard() from public, anon, authenticated;

create or replace function public.sm_report_keep_file(p_version uuid, p_key text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.sm_report_versions;
  v_client uuid;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.sm_report_versions where id = p_version for update;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select r.client_id into v_client from public.sm_reports r where r.id = v.report_id;
  if v_client is null or not public.client_seen(v_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if v.file_key is not null and v.file_at >= v.published_at then
    return jsonb_build_object('ok', true, 'kept', true, 'key', v.file_key);
  end if;
  if coalesce(p_key, '') !~ ('^private/' || v_client::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$') then
    return jsonb_build_object('error', 'bad-key');
  end if;
  perform set_config('adspace.keep_file', 'on', true);
  update public.sm_report_versions set file_key = p_key, file_at = now(), file_by = me.name where id = v.id;
  perform set_config('adspace.keep_file', 'off', true);
  return jsonb_build_object('ok', true, 'key', p_key);
end $$;
revoke all on function public.sm_report_keep_file(uuid, text) from public, anon;
grant execute on function public.sm_report_keep_file(uuid, text) to authenticated;

-- END OF REPORT FILE KEPT IN SCOPE --------------------------------------------

select public.functions_tidy();
