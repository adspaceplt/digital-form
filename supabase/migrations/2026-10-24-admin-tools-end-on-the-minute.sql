-- ===========================================================================
-- ADMIN TOOLS END ON THE MINUTE — a granted part stops answering the moment
-- a colleague's access ends, and Issue Letter of Offer asks Letters too
-- (2026-10-24)
-- ===========================================================================
-- WHY (permissions audit 2026-10-24, S3 and N6c): `allowed()`, `is_team()`,
-- `ops_me()` and `me()` stop counting a colleague the minute their access
-- ends (ACCESS ENDS ON THE MINUTE), but `ops_granted` asked `active` alone,
-- so for up to five minutes, until `team_expire_access` ran, a leaver kept
-- every admin tool they held (Upgrade mode, the Handbook, AI limits, Bukku,
-- white label, the task number). `quotation_offer` made a quotation's lines
-- To quote without Clients: Letters, which the page and the rule ask
-- (Issue Letter of Offer asks Quotations, Service lines and Letters at Work).
--
-- WHAT IT CHANGES
--   * `ops_granted(p_key, p_level)`: refuses a colleague who is not an admin
--     once `team_access_ends(access_until, access_until_time)` has passed;
--     an admin stays the expiry run's, as in `allowed()`.
--   * `quotation_offer(p_id)`: `denied` without Clients: Letters at Work.
--
-- ORDER: this file (the connector; it holds no drop or delete), then
-- nothing: the pages already ask both. Safe to run twice. Rollback: the two
-- functions as OVERSEAS ACCESS and CLIENT PARTS FOR EACH TAB left them.
-- ===========================================================================

create or replace function public.ops_granted(p_key text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where active and lower(email) = lower(auth.jwt() ->> 'email') limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if t.access_until is not null
     and public.team_access_ends(t.access_until, t.access_until_time) <= now() then return false; end if;
  if not public.team_place_ok(false, t.id) then return false; end if;
  return public.level_rank(t.access ->> p_key) >= public.level_rank(p_level);
end $$;
grant execute on function public.ops_granted(text, text) to authenticated;

create or replace function public.quotation_offer(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_l jsonb;
  v_ids uuid[] := '{}';
  v_id uuid;
begin
  if me.id is null or not (public.allowed('clients.quotes', 'work') and public.allowed('clients.services', 'work')
                           and public.allowed('clients.documents', 'work')) then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or v_q.removed_at is not null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  select coalesce(array_agg(s.id order by s.created_at), '{}') into v_ids
    from public.client_services s where s.quotation_id = v_q.id and s.archived_at is null;
  if array_length(v_ids, 1) is not null then return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids), 'again', true); end if;
  if v_q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  for v_l in select * from jsonb_array_elements(v_q.lines) loop
    insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                        tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
    values (v_q.client_id,
            case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
            v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
            case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'quoted',
            'Quotation ' || v_q.ref,
            case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (v_q.totals->>'term')::int) else 1 end,
            v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (v_q.totals->>'term_pct')::numeric else 0 end,
            nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
            v_q.id, nullif(v_l->>'tax_code', ''))
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' · ' || array_length(v_ids, 1) || ' lines To quote for the Letter of Offer');
  return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids));
end $$;
revoke all on function public.quotation_offer(uuid) from public, anon;
grant execute on function public.quotation_offer(uuid) to authenticated;

-- END OF ADMIN TOOLS END ON THE MINUTE -------------------------------------

select public.functions_tidy();
