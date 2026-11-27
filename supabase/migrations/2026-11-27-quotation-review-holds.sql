-- ===========================================================================
-- QUOTATION REVIEW HOLDS (2026-11-27)
-- ===========================================================================
-- WHY: session J's review of 26 Nov, findings 5, 6, 14 and 15.
--   5  A confirmed revision a client opened by the original's link was never
--      sent out: its prices stayed editable and the stage stood short of
--      Proposal sent.
--   6  quotation_confirm took a draft past its valid-until date, so its link
--      opened on "expired".
--   14 quote_change_request checked that changes were open before taking
--      the row's lock, so a quotation signed a moment before took one.
--   15 quote_preflight's function-wide handler undid the hour's count on a
--      bad input, so bad inputs were never rate limited.
-- WHAT IT CHANGES: quote_opened also stamps the revision shown;
-- quotation_confirm refuses `draft-expired`; quote_change_request asks
-- quote_change_open again under the lock; quote_preflight's handler wraps
-- the work after the throttle alone. No table or grant changes.
-- ROLLBACK: re-run quote_opened from 2026-11-25-quotation-copier-opening.sql,
-- quotation_confirm from 2026-11-26-quotations-confirmed.sql,
-- quote_change_request from 2026-11-25-minor-abuse-paths-held.sql and
-- quote_preflight from 2026-11-25-quotation-preflight.sql.
-- Safe to run twice.

create or replace function public.quote_opened(p_key text, p_device text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  v_ip  text := nullif(public.request_ip(), '');
  v_dev text := public.seal_device(p_device);
  v_team boolean := false;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if public.is_team() then return jsonb_build_object('ok', true, 'kept', false); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if q.id is null or (q.source = 'website' and q.released_at is null) then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  -- An opening from where a colleague copied this quotation's link in the
  -- last 30 days is the team's own, never the client's.
  v_team := v_ip is not null and exists (select 1 from public.quotation_link_copies c
              where c.quotation_id in (w.id, q.id) and c.ip = v_ip and c.at > now() - interval '30 days');
  -- A team's quotation reaches the client the first time its own link is
  -- opened by anyone but a colleague: it is sent out then, once. The
  -- quotation the key belongs to, never a revision still being made, nor
  -- one not proceeding.
  if w.source = 'console' and w.sent_out_at is null and w.status <> 'not_proceeding' and not v_team then
    update public.quotations set sent_out_at = now() where id = w.id and sent_out_at is null;
  end if;
  -- The confirmed revision the link shows is sent out with it, so its
  -- prices freeze and the stage reaches Proposal sent (review J5).
  if q.id <> w.id and q.source = 'console' and q.confirmed_at is not null and q.sent_out_at is null
     and q.status <> 'not_proceeding' and not v_team then
    update public.quotations set sent_out_at = now() where id = q.id and sent_out_at is null;
  end if;
  if exists (select 1 from public.signing_steps s
              where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened'
                and s.at > now() - interval '6 hours'
                and s.ip is not distinct from v_ip and s.device is not distinct from v_dev)
     or (select count(*) from public.signing_steps s
          where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened') >= 100 then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  insert into public.signing_steps (doc_kind, doc_id, step, ip, country, device)
  values ('quotation', q.id, 'opened', v_ip, nullif(public.request_country(), ''), v_dev);
  -- The same opening, kept once, is the Activity record's line.
  perform public.quote_activity(q, 'quotation.opened', q.ref || case when v_team then ' · Opened by the team' else '' end, q.contact);
  return jsonb_build_object('ok', true, 'kept', true);
end $$;


create or replace function public.quotation_confirm(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  n public.quotations;
  o public.quotations;
  v_by text;
  v_ref text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into n from public.quotations x where x.id = p_id for update;
  if n.id is null or n.removed_at is not null or not public.client_scope_ok('client', n.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if n.confirmed_at is not null then return jsonb_build_object('ok', true, 'same', true, 'ref', n.ref); end if;
  if n.source <> 'console' then return jsonb_build_object('error', 'website'); end if;
  if n.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  -- A draft past its valid-until date is never confirmed: its link would
  -- open on "expired" (review J6). Edit sets a new date first.
  if n.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'draft-expired'); end if;
  if n.revises is not null then
    select * into o from public.quotations x where x.id = n.revises for update;
  end if;
  if o.id is not null and o.removed_at is null then
    if o.signed_at is not null or o.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
    select x.ref into v_by from public.quotations x where x.replaces = o.id and x.removed_at is null and x.id <> n.id limit 1;
    if v_by is not null then return jsonb_build_object('error', 'revised', 'ref', v_by); end if;
    -- A website request revised before it was sent holds no ADP/QT number:
    -- its revision takes a fresh one; else the family's next -Rn.
    v_ref := case when o.confirmed_at is null then public.quote_ref(n.brand, n.issued_at) else public.quote_revision_ref(o.id) end;
    update public.quotations set ref = v_ref, confirmed_at = now(), confirmed_by = me.name, replaces = o.id, revises = null
     where id = n.id returning * into n;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', n.brand, n.ref || ' confirmed · revises ' || o.ref);
  else
    -- What it was to revise is gone: it stands as a quotation of its own.
    v_ref := public.quote_ref(n.brand, n.issued_at);
    update public.quotations set ref = v_ref, confirmed_at = now(), confirmed_by = me.name, revises = null
     where id = n.id returning * into n;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', n.brand, n.ref || ' confirmed');
  end if;
  return jsonb_build_object('ok', true, 'ref', n.ref);
end $$;


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
  -- Asked again under the row's lock, as signing is: a quotation signed a
  -- moment before takes no change request (review J14).
  o := public.quote_change_open(p_key);
  if o ? 'error' then return o; end if;
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


create or replace function public.quote_preflight(p_sel jsonb, p_seen jsonb default null, p_key text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_chk jsonb;
  o     jsonb;
  q     public.quotations;
  c     jsonb;
  v_fx  numeric;
  v_sel jsonb;
  v_p   jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not public.quote_throttle() then return jsonb_build_object('error', 'limit'); end if;
  -- A bad input is refused inside its own block, so the hour's count the
  -- throttle took stands (review J15: the function-wide handler undid it).
  begin
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if p_key is null then
    v_chk := public.quote_web_check(p_sel, case when jsonb_typeof(p_seen) = 'object' then p_seen->>'version' end);
    return jsonb_build_object('ok', jsonb_array_length(v_chk->'changes') = 0, 'changes', v_chk->'changes', 'version', v_chk->'version');
  end if;
  -- A sent quotation's changed selection, as quote_change_request reads it.
  o := public.quote_change_open(p_key);
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid;
  if q.selection ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  c := public.quote_change_snap(q);
  v_fx := (c->>'fx')::numeric;
  if c is null or v_fx = 0 then return jsonb_build_object('error', 'no-card'); end if;
  v_sel := public.quote_change_sel(q.selection, p_sel, c->'snap');
  if v_sel ? 'error' then
    v_out := v_out || jsonb_build_object('kind', case v_sel->>'error' when 'bad-plan' then 'plan' when 'bad-extra' then 'extra'
                                                   when 'bad-once' then 'once' when 'bad-term' then 'term' else 'selection' end);
  else
    v_p := public.quote_fx_out(public.quote_compose(c->'snap', v_sel, q.source <> 'website'), v_fx);
    if v_p ? 'error' then
      v_out := v_out || jsonb_build_object('kind', 'selection');
    elsif jsonb_typeof(p_seen) = 'object'
          and (coalesce((p_seen->>'month')::numeric, -1) is distinct from coalesce((v_p->'totals'->'month'->>'incl')::numeric, -1)
               or coalesce((p_seen->>'once')::numeric, -1) is distinct from coalesce((v_p->'totals'->'once'->>'incl')::numeric, -1)) then
      v_out := v_out || jsonb_build_object('kind', 'price');
    end if;
  end if;
  return jsonb_build_object('ok', jsonb_array_length(v_out) = 0, 'changes', v_out);
  exception when invalid_text_representation then
    return jsonb_build_object('error', 'bad-selection');
  end;
end $$;


revoke all on function public.quote_opened(text, text) from public;
grant execute on function public.quote_opened(text, text) to anon, authenticated;
revoke all on function public.quotation_confirm(uuid) from public, anon;
grant execute on function public.quotation_confirm(uuid) to authenticated;
revoke all on function public.quote_change_request(text, jsonb) from public;
grant execute on function public.quote_change_request(text, jsonb) to anon, authenticated;
revoke all on function public.quote_preflight(jsonb, jsonb, text) from public;
grant execute on function public.quote_preflight(jsonb, jsonb, text) to anon, authenticated;
