-- ===========================================================================
-- DELETE REQUESTS HELD TO WHAT THE REQUESTER SEES (2026-11-24)
-- ===========================================================================
-- WHY: the review of 2026-11-24 (C2). A request to delete several tasks
-- checked each task against My Work's sight but not its client's: a
-- colleague whose group sees its own clients alone could file one naming
-- another client's task. And a request one admin was approving could be
-- approved again by a second, running the delete twice.
--
-- WHAT IT CHANGES
--   * `delete_request_file`: in a list of tasks, each task's client must be
--     one the requester sees (`client_seen`), else `not-found`, as one task
--     is; the titles stay in the label.
--   * `delete_request_decide`: a request another admin is approving is
--     refused `approving` for ten minutes from their press; the admin who
--     pressed, or anyone after ten minutes (a tab shut mid-way), may decide
--     it again.
--
-- ORDER: this migration, then the pages (they name `approving`). A page
-- from before reads an unknown refusal as its generic line.
--
-- ROLLBACK: run both functions as DELETES AND BUILDS HELD stated them (the
-- previous last definitions in schema.sql).
-- ===========================================================================

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
              from public.ops_tasks x where x.id = any(v_ids) and public.ops_may_see_task(x.id)
               and (x.client_id is null or public.client_seen(x.client_id, 'view'))) t;
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
  /* A request another admin is approving is theirs to finish: a second
     approve would run the delete twice. One left approving ten minutes
     (a tab shut mid-way) may be decided again. */
  if r.state = 'approving' and r.decided_by is distinct from me.id and r.decided_at > now() - interval '10 minutes' then
    return jsonb_build_object('error', 'approving');
  end if;
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

-- END OF DELETE REQUESTS HELD TO WHAT THE REQUESTER SEES ---------------------

select public.functions_tidy();
