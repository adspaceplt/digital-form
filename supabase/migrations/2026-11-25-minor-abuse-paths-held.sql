-- ===========================================================================
-- MINOR ABUSE PATHS HELD (2026-11-25)
-- ===========================================================================
-- WHY (the review of everything merged since 15 Nov, approved by the user
-- on 2026-11-25): four small ways to misuse a public link or a permission.
--
-- WHAT CHANGES
--   * `quote_change_request` (restated from QUOTATION LINK ACTIVITY):
--     ten requests or withdrawals on one link in an hour, then `busy`. A
--     withdrawal cleared the minute's wait, so request and withdraw in turn
--     told the team without end.
--   * `team_session_end` and `team_sessions_end_all` (restated from
--     HIRING AND RECORD LINES WORDED): an admin's devices are signed out by an admin alone,
--     `admin-only`; a colleague at Team: Sessions (Work) could sign an
--     admin out.
--   * `verify_name_wrong` / `verify_name_wait` (restated from VERIFY NAMES
--     HELD TO THE ADDRESSEE): five wrong names lock one connection and one
--     reference for 24 hours, a connection with no address counted as one;
--     the lock across all connections is gone, so callers elsewhere can no
--     longer lock the real addressee out together.
--   * `request_visit` (restated from QUOTATION LINK ACTIVITY): the device
--     header is held to 300 characters with no control characters, the
--     city to 60, and the visit's session reference is made from the
--     address, the device word and the day, so a caller cannot mint
--     sessions by changing a header; both headers are shown, never trusted.
--
-- ORDER: this file, then the pages (the console's Devices hides Sign out on
-- an admin's devices for a colleague who is not one, and /quote/ names
-- `busy`). An old page meanwhile reads `admin-only` or `busy` as its
-- general refusal. Safe to run twice.
-- ROLLBACK: run the six functions from the bands named above again.
-- ===========================================================================

-- MINOR ABUSE PATHS HELD -------------------------------------------------------

create or replace function public.quote_change_request(p_key text, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  o jsonb := public.quote_change_open(p_key);
  q public.quotations;
  cl public.clients;
  c jsonb;
  v_fx numeric;
  v_sel jsonb;
  v_p jsonb;
  v_now timestamptz := now();
  v_body text;
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  select * into cl from public.clients where id = q.client_id;
  -- Ten requests or withdrawals a link an hour (MINOR ABUSE PATHS HELD):
  -- each tells the team, and a withdrawal clears the minute's wait.
  if (select count(*) from public.activity_log a
       where a.action in ('quotation.changes', 'quotation.withdrawn') and a.meta->>'ref' = q.ref
         and a.created_at > v_now - interval '1 hour') >= 10 then
    return jsonb_build_object('error', 'busy');
  end if;
  if p_sel is null then
    if q.change_requested_at is null then return jsonb_build_object('ok', true, 'again', true); end if;
    update public.quotations set change_request = null, change_requested_at = null where id = q.id;
    perform public.quote_activity(q, 'quotation.withdrawn', q.ref, q.contact);
    return jsonb_build_object('ok', true);
  end if;
  if q.selection ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  if q.change_requested_at > v_now - interval '1 minute' then return jsonb_build_object('error', 'recent'); end if;
  c := public.quote_change_snap(q);
  if c is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := (c->>'fx')::numeric;
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_sel := public.quote_change_sel(q.selection, p_sel, c->'snap');
  if v_sel ? 'error' then return v_sel; end if;
  -- Unchanged whatever order the platforms were held in.
  if (v_sel - 'platforms') = (q.selection - 'platforms')
     and (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from jsonb_array_elements_text(coalesce(v_sel->'platforms', '[]'::jsonb)) x)
       = (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from jsonb_array_elements_text(coalesce(q.selection->'platforms', '[]'::jsonb)) x) then
    return jsonb_build_object('error', 'unchanged');
  end if;
  v_p := public.quote_fx_out(public.quote_compose(c->'snap', v_sel, q.source <> 'website'), v_fx);
  if v_p ? 'error' then return jsonb_build_object('error', v_p->>'error'); end if;
  update public.quotations
     set change_request = jsonb_build_object('selection', v_sel,
           'month', v_p->'totals'->'month'->'incl', 'once', v_p->'totals'->'once'->'incl', 'version', c->>'version'),
         change_requested_at = v_now, reply_due = public.quote_reply_by(v_now)
   where id = q.id
   returning * into q;
  perform public.quote_activity(q, 'quotation.changes', q.ref || coalesce(' · ' || coalesce(q.totals->>'currency', 'RM') || ' ' ||
    to_char((v_p->'totals'->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', ''), q.contact);
  v_body := q.ref || coalesce(' · ' || coalesce(q.totals->>'currency', 'RM') || ' ' ||
              to_char((v_p->'totals'->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', '')
            || ' · Send by ' || public.register_day((q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
            || ' (' || trim(to_char(q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
            lower(to_char(q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam'));
  -- Who prepared it and the person in charge are told; where neither is
  -- here, the team who work leads.
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(cl.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.changes', 'Changes requested · ' || q.brand, v_body,
      q.id::text || ':' || v_now::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(cl.owner)],
      'quote.changes', 'Changes requested · ' || q.brand, v_body, q.client_id, q.id::text || ':' || v_now::text);
  end if;
  return jsonb_build_object('ok', true, 'reply_due', q.reply_due);
end $$;
revoke all on function public.quote_change_request(text, jsonb) from public;
grant execute on function public.quote_change_request(text, jsonb) to anon, authenticated;

create or replace function public.team_session_end(p_id uuid, p_session uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  m      public.team_members;
  v_dev  text;
begin
  if me.id is null or not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(m.system, false) and m.id <> me.id then return jsonb_build_object('error', 'system-account'); end if;
  -- An admin's devices are an admin's to sign out (MINOR ABUSE PATHS HELD).
  if m.is_admin and not me.is_admin then return jsonb_build_object('error', 'admin-only'); end if;
  if p_session::text = coalesce(auth.jwt() ->> 'session_id', '') then return jsonb_build_object('error', 'own-session'); end if;
  select public.session_device(s.user_agent) into v_dev
    from auth.sessions s join auth.users u on u.id = s.user_id
   where s.id = p_session and lower(u.email) = lower(m.email);
  if v_dev is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from auth.sessions s where s.id = p_session;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Signed-in devices',
          m.name || ' was signed out on ' || v_dev || ' (' || left(p_session::text, 6) || ').');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_session_end(uuid, uuid) from public, anon, authenticated;
grant execute on function public.team_session_end(uuid, uuid) to authenticated;

create or replace function public.team_sessions_end_all(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  m    public.team_members;
  v_n  integer := 0;
begin
  if me.id is null or not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if m.id = me.id or lower(m.email) = lower(me.email) then return jsonb_build_object('error', 'own-account'); end if;
  if coalesce(m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if m.is_admin and not me.is_admin then return jsonb_build_object('error', 'admin-only'); end if;
  delete from auth.sessions s
   using auth.users u
   where u.id = s.user_id and lower(u.email) = lower(m.email);
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('error', 'none'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Signed-in devices',
          m.name || ' was signed out on ' || v_n || case when v_n = 1 then ' device.' else ' devices.' end);
  return jsonb_build_object('ok', true, 'ended', v_n);
end $$;
revoke all on function public.team_sessions_end_all(uuid) from public, anon, authenticated;
grant execute on function public.team_sessions_end_all(uuid) to authenticated;

create or replace function public.verify_name_wait(p_key text)
returns integer
language sql stable set search_path = public as $$
  select coalesce((select greatest(1, ceil(extract(epoch from (c.locked_until - now())) / 60)::integer)
                     from public.verify_name_caller_tries c
                    where c.serial = p_key and c.ip = coalesce(nullif(public.request_ip(), ''), 'none')
                      and c.locked_until > now()), 0)
$$;
revoke all on function public.verify_name_wait(text) from public, anon, authenticated;

create or replace function public.verify_name_wrong(p_key text)
returns void
language plpgsql volatile set search_path = public as $$
declare
  v_ip text := coalesce(nullif(public.request_ip(), ''), 'none');
begin
  insert into public.verify_name_caller_tries as t (serial, ip, n, since) values (p_key, v_ip, 1, now())
  on conflict (serial, ip) do update
    set n = case when t.since < now() - interval '24 hours' then 1 else t.n + 1 end,
        since = case when t.since < now() - interval '24 hours' then now() else t.since end;
  update public.verify_name_caller_tries t set locked_until = now() + interval '24 hours'
   where t.serial = p_key and t.ip = v_ip and t.n >= 5 and (t.locked_until is null or t.locked_until <= now());
end $$;
revoke all on function public.verify_name_wrong(text) from public, anon, authenticated;

create or replace function public.request_visit()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  h json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  v_agent text := left(regexp_replace(coalesce(public.request_relayed('agent'), h ->> 'user-agent', ''), '[[:cntrl:]]', '', 'g'), 300);
  v_country text := upper(coalesce(public.request_relayed('country'), public.request_country(), ''));
  v_city text := left(public.seal_device(left(coalesce(public.request_relayed('city'), h ->> 'cf-ipcity'), 60)), 60);
  v_ip text := coalesce(public.request_ip(), '');
  v_salt text := (select s.value from public.app_secrets s where s.key = 'activity_session_salt');
begin
  if v_country !~ '^[A-Z]{2}$' or v_country in ('XX', 'T1') then v_country := null; end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'device', public.ua_device(v_agent),
    'city', v_city,
    'country', v_country,
    'session', case when v_salt is not null and (v_ip <> '' or v_agent <> '') then
      upper(left(encode(digest(v_salt || '|' || v_ip || '|' || coalesce(public.ua_device(v_agent), '') || '|' ||
        ((now() at time zone 'Asia/Kuala_Lumpur')::date)::text, 'sha256'), 'hex'), 6)) end));
end $$;
revoke all on function public.request_visit() from public, anon, authenticated;

-- END OF MINOR ABUSE PATHS HELD ----------------------------------------------

select public.functions_tidy();
