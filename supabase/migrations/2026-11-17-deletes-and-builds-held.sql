-- ============================================================================
-- DELETES AND BUILDS HELD (2026-11-17)
-- ============================================================================
-- The review of the releases since #1134 (the user, 2026-11-17: "Ok fix
-- all"), findings 6, 7, 15, 16, 17 and 18:
--
--   * `team_member_purge` sets `adspace.sm_fn` before the colleague's row
--     goes, so a report they submitted, confirmed or reviewed loses the
--     name by its key (on delete set null) instead of the guard refusing
--     the whole delete (`sm-status-by-function`).
--   * `delete_request_file` reads the records of a list or an unnamed kind
--     too (`rpc:ops_delete_tasks`, `rpc:sm_report_version_delete`,
--     `table:campaign_options`): each must exist and be in the requester's
--     sight (`not-found`), and the request keeps their names, which the
--     admin's question reads.
--   * `delete_request_decide` refuses a request the admin filed themselves
--     (`own`); `delete_request_done` closes a request only for the admin
--     who approved it (`not-yours`).
--   * `build_min()` answers the commit and its time alone (never who set
--     it: `page_pulse` answers it to any caller naming the team); and
--     `build_require` refuses a build time ahead of now (`bad-build`).
--
-- ORDER: this file (connector), then the pages. A page served before reads
-- every answer as before. Safe to run twice.
-- ROLLBACK: run the DELETE REQUESTS, A COLLEAGUE DELETED PERMANENTLY and THE
-- LATEST BUILD REQUIRED bands of schema.sql again.
-- ============================================================================

-- DELETES AND BUILDS HELD ----------------------------------------------------

create or replace function public.team_member_purge(p_member uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  me      public.team_members := public.ops_me();
  v_m     public.team_members;
  v_email text;
  k       record;
begin
  if me.id is null or not public.allowed('admin') then return jsonb_build_object('error', 'admin-only'); end if;
  select * into v_m from public.team_members x where x.id = p_member for update;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if v_m.removed_at is null then return jsonb_build_object('error', 'not-removed'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(btrim(v_m.name)) then return jsonb_build_object('error', 'bad-name'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  v_email := v_m.email;
  /* A report's names (submitted, confirmed, reviewer) are cleared by their
     keys, which the report's guard holds to its functions: this is one. */
  perform set_config('adspace.sm_fn', 'on', true);
  for k in
    select c.conrelid::regclass as tbl, a.attname as col, a.attnotnull as req
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.team_members'::regclass and c.confdeltype in ('a', 'r')
  loop
    if k.req then
      execute format('delete from %s where %I = $1', k.tbl, k.col) using p_member;
    else
      execute format('update %s set %I = null where %I = $1', k.tbl, k.col, k.col) using p_member;
    end if;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', v_m.name, 'Deleted permanently');
  delete from public.team_members x where x.id = p_member;
  perform set_config('adspace.sm_fn', 'off', true);
  if v_email is not null and not exists (select 1 from public.team_members x where lower(x.email) = lower(v_email))
     and not exists (select 1 from public.client_contacts k2 where lower(k2.email) = lower(v_email) and k2.archived_at is null) then
    delete from auth.users u where lower(u.email) = lower(v_email);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_member_purge(uuid, text) from public, anon;
grant execute on function public.team_member_purge(uuid, text) to authenticated;

create or replace function public.delete_request_file(p_kind text, p_args jsonb, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me       public.team_members := public.ops_me();
  k        public.delete_kinds;
  v_rec    text;
  v_label  text;
  v_client uuid;
  v_why    text := btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));
  v_id     uuid;
  v_ids    uuid[];
  v_n      integer;
  v_seen   integer;
  v_names  text;
  v_cls    uuid[];
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into k from public.delete_kinds x where x.kind = p_kind;
  if k.kind is null then return jsonb_build_object('error', 'bad-kind'); end if;
  if not public.allowed(k.section, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if public.allowed(k.section, 'manage') then return jsonb_build_object('error', 'may-delete'); end if;
  if p_args is null or jsonb_typeof(p_args) <> 'object' or length(p_args::text) > 4000 then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if length(v_why) < 3 or length(v_why) > 500 then return jsonb_build_object('error', 'bad-reason'); end if;
  if jsonb_typeof(p_args -> k.id_arg) = 'array' then
    v_rec := null;
    v_n := jsonb_array_length(p_args -> k.id_arg);
    if v_n not between 1 and 200 then return jsonb_build_object('error', 'bad-request'); end if;
    /* A list (several tasks): every one held, each in the requester's
       sight, their names kept for the admin's question. */
    if k.kind <> 'rpc:ops_delete_tasks' then return jsonb_build_object('error', 'bad-request'); end if;
    begin
      select array_agg(distinct e::uuid) into v_ids from jsonb_array_elements_text(p_args -> k.id_arg) e;
    exception when invalid_text_representation then return jsonb_build_object('error', 'bad-request');
    end;
    select count(*), string_agg(t.title, ', ' order by t.title) filter (where t.rn <= 3),
           array_agg(distinct t.client_id) filter (where t.client_id is not null)
      into v_seen, v_names, v_cls
      from (select x.id, x.title, x.client_id, row_number() over (order by x.title) as rn
              from public.ops_tasks x where x.id = any(v_ids) and public.ops_may_see_task(x.id)) t;
    if v_seen <> coalesce(array_length(v_ids, 1), 0) then return jsonb_build_object('error', 'not-found'); end if;
    v_label := v_seen::text || ' ' || lower(k.word) || ' · ' || coalesce(v_names, '')
      || case when v_seen > 3 then ' and ' || (v_seen - 3)::text || ' more' else '' end;
    if coalesce(array_length(v_cls, 1), 0) = 1 then v_client := v_cls[1]; end if;
  else
    v_rec := nullif(btrim(coalesce(p_args ->> k.id_arg, '')), '');
    if v_rec is null or length(v_rec) > 100 then return jsonb_build_object('error', 'bad-request'); end if;
    if k.label_table is not null then
      execute format('select %I::text from public.%I where %I::text = $1', k.label_col, k.label_table, k.label_key)
        into v_label using v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
      begin
        execute format('select client_id from public.%I where %I::text = $1', k.label_table, k.label_key)
          into v_client using v_rec;
      exception when undefined_column then v_client := null;
      end;
      if k.label_table = 'clients' then v_client := v_rec::uuid; end if;
      /* A supplier's client is the one it is linked to, not its owner. */
      if k.label_table = 'suppliers' then v_client := null; end if;
    elsif k.kind = 'rpc:sm_report_version_delete' then
      /* A report's version: its report's title and number. */
      select coalesce(nullif(btrim(r.title), ''), 'Report') || ' · version ' || v.version_no, r.client_id
        into v_label, v_client
        from public.sm_report_versions v join public.sm_reports r on r.id = v.report_id
       where v.id::text = v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
    elsif k.kind = 'table:campaign_options' then
      /* A booking: its creator and campaign. */
      select coalesce(c.name, 'Creator') || ' · ' || coalesce(nullif(btrim(g.title), ''), 'Campaign'), g.client_id
        into v_label, v_client
        from public.campaign_options o
        join public.campaigns g on g.id = o.campaign_id
        left join public.creators c on c.id = o.creator_id
       where o.id::text = v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
    else
      return jsonb_build_object('error', 'bad-kind');
    end if;
    if v_client is not null and not public.client_seen(v_client, 'view') then
      return jsonb_build_object('error', 'not-found');
    end if;
    v_label := coalesce(nullif(btrim(coalesce(v_label, '')), ''), k.word);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('delete-request:' || me.id::text, 0));
  if (select count(*) from public.delete_requests x where x.requested_by = me.id
        and x.created_at > now() - interval '24 hours') >= 30 then
    return jsonb_build_object('error', 'too-many');
  end if;
  if v_rec is not null and exists (select 1 from public.delete_requests x
       where x.kind = k.kind and x.record = v_rec and x.state in ('open', 'approving')) then
    return jsonb_build_object('error', 'already');
  end if;
  insert into public.delete_requests (kind, args, record, label, client_id, reason, requested_by)
  values (k.kind, p_args, v_rec, left(v_label, 200), v_client, v_why, me.id)
  returning id into v_id;
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'delete.request', 'Delete requested · ' || k.word || ' · ' || left(v_label, 120),
         me.name || ' · ' || v_why,
         v_client, 'delreq:' || v_id || ':' || m.id
    from public.team_members m
   where m.active and (m.is_admin or m.role = 'admin') and m.id <> me.id
  on conflict (dedupe_key) do nothing;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Requested: ' || k.word || ' · ' || left(v_label, 120) || ' · ' || v_why);
  return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'word', k.word);
end $$;
revoke all on function public.delete_request_file(text, jsonb, text) from public, anon;
grant execute on function public.delete_request_file(text, jsonb, text) to authenticated;

create or replace function public.delete_request_decide(p_id uuid, p_approve boolean, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r  public.delete_requests;
  v_note text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
begin
  if me.id is null or not (me.is_admin or me.role = 'admin') then return jsonb_build_object('error', 'denied'); end if;
  if length(coalesce(v_note, '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  select * into r from public.delete_requests x where x.id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* Another admin decides a request an admin filed before they were one. */
  if r.requested_by = me.id then return jsonb_build_object('error', 'own'); end if;
  if r.state not in ('open', 'approving') then return jsonb_build_object('error', 'decided', 'state', r.state); end if;
  if coalesce(p_approve, false) then
    update public.delete_requests set state = 'approving', decided_by = me.id, decided_at = now(), note = v_note where id = r.id;
    return jsonb_build_object('ok', true, 'kind', r.kind, 'args', r.args);
  end if;
  if v_note is null then return jsonb_build_object('error', 'no-note'); end if;
  update public.delete_requests set state = 'declined', decided_by = me.id, decided_at = now(), note = v_note where id = r.id;
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  values (r.requested_by, 'delete.declined', 'Delete declined · ' || r.label, me.name || ' · ' || v_note,
          r.client_id, 'delreq:' || r.id || ':declined')
  on conflict (dedupe_key) do nothing;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Declined: ' || r.label || ' · ' || v_note);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.delete_request_decide(uuid, boolean, text) from public, anon;
grant execute on function public.delete_request_decide(uuid, boolean, text) to authenticated;

create or replace function public.delete_request_done(p_id uuid, p_ok boolean, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); r public.delete_requests;
begin
  if me.id is null or not (me.is_admin or me.role = 'admin') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.delete_requests x where x.id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.state <> 'approving' then return jsonb_build_object('error', 'decided', 'state', r.state); end if;
  /* Only the admin who approved it closes it. */
  if r.decided_by is distinct from me.id then return jsonb_build_object('error', 'not-yours'); end if;
  if not coalesce(p_ok, false) then
    update public.delete_requests set state = 'open', note = left(nullif(btrim(coalesce(p_error, '')), ''), 500) where id = r.id;
    return jsonb_build_object('ok', true, 'state', 'open');
  end if;
  update public.delete_requests set state = 'approved', decided_by = me.id, decided_at = now() where id = r.id;
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  values (r.requested_by, 'delete.approved', 'Deleted · ' || r.label, me.name,
          r.client_id, 'delreq:' || r.id || ':approved')
  on conflict (dedupe_key) do nothing;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Approved: ' || r.label || ' · requested by ' ||
          coalesce((select m.name from public.team_members m where m.id = r.requested_by), 'a colleague'));
  return jsonb_build_object('ok', true, 'state', 'approved');
end $$;
revoke all on function public.delete_request_done(uuid, boolean, text) from public, anon;
grant execute on function public.delete_request_done(uuid, boolean, text) to authenticated;

create or replace function public.build_min()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('commit', f.note, 'built', f.starts_at)
    from public.app_flags f
   where f.key = 'build:min' and f.on_now and f.note is not null and f.starts_at is not null
$$;
revoke all on function public.build_min() from public, anon, authenticated;

create or replace function public.build_require(p_commit text, p_built timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_who text;
  v_was jsonb;
  v_commit text := lower(nullif(btrim(coalesce(p_commit, '')), ''));
begin
  if not public.ops_granted('team.upgrade', 'work') then return jsonb_build_object('error', 'denied'); end if;
  /* A build time ahead of now is no build Pages has served. */
  if v_commit is not null and (v_commit !~ '^[0-9a-f]{7,40}$' or p_built is null
      or p_built < timestamptz '2023-08-14 00:00+08' or p_built > now()) then
    return jsonb_build_object('error', 'bad-build');
  end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  v_was := public.build_min();
  insert into public.app_flags (key, on_now, note, starts_at, set_by, set_at)
  values ('build:min', v_commit is not null, v_commit, case when v_commit is not null then p_built end, v_who, now())
  on conflict (key) do update
    set on_now = excluded.on_now, note = excluded.note, starts_at = excluded.starts_at,
        set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Portal',
          'Latest version required: ' || public.build_word(v_was ->> 'commit', (v_was ->> 'built')::timestamptz)
          || ' → ' || public.build_word(v_commit, case when v_commit is not null then p_built end));
  return jsonb_build_object('ok', true, 'min', public.build_min(), 'was', v_was);
end $$;
revoke all on function public.build_require(text, timestamptz) from public, anon;
grant execute on function public.build_require(text, timestamptz) to authenticated;

-- END OF DELETES AND BUILDS HELD ---------------------------------------------

select public.functions_tidy();
