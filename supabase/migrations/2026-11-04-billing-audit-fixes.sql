-- ===========================================================================
-- BILLING AUDIT FIXES — the nightly read, one BRN at a time, AI limits for
-- every writer (2026-11-04)
-- ===========================================================================
-- WHY (the audit of 2026-11-04; the user: "fix all"): a client's first
-- billing entity made from a Bukku contact holding a name alone refused the
-- service role's read (`bukku_take`'s own carry met `clients_billing_guard`,
-- which asked the service role for Clients: Billing), so every read of that
-- client failed; two presses of Add entity at once on two clients could
-- each pass the BRN check and make it twice; and AI usage listed no one who
-- holds only Brand analysis, Checklists or Analytics until their first use,
-- so no limit could be set for them before it.
--
-- WHAT CHANGED
--   * `clients_billing_guard`: an update with no signed-in caller (the
--     service role, the SQL Editor) passes, as an insert already did.
--   * `client_entity_add`, `client_entity_save`: a transaction lock on the
--     BRN's digits before its check, so one BRN is taken once.
--   * `ai_draft_usage`: its people include Clients: Brand at View, Clients:
--     Checklists at Work and `team.analytics`.
--
-- ORDER: this file (connector), then the pages (My Work's month sheet title
-- no longer escapes the client's name twice). Safe to run twice.
--
-- ROLLBACK: run BILLING REVIEW FIXES' and AI LIMITS EACH USE's functions
-- and the CLIENT BILLING COLUMNS guard again.
-- ===========================================================================

create or replace function public.clients_billing_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- A billing contact removed from Contacts nulls bill_contact_id by the
  -- foreign key, which is a cascade and not a person editing Billing.
  if pg_trigger_depth() > 1 then return new; end if;
  if tg_op = 'INSERT' then
    if coalesce(current_setting('role', true), '') = 'authenticated'
       and (nullif(btrim(coalesce(new.legal_name, '') || coalesce(new.company_no, '') || coalesce(new.company_no_old, '') ||
                         coalesce(new.tin, '') || coalesce(new.sst_no, '') || coalesce(new.finance_email, '') ||
                         coalesce(new.billing_address, '')), '') is not null
            or new.bill_contact_id is not null or new.sst_applies is false or new.bill_sgd is true)
       and not public.allowed('clients.billing', 'work') then
      raise exception 'You do not have permission to change billing details. Please ask an admin.' using errcode = '42501';
    end if;
    return new;
  end if;
  if (new.legal_name, new.company_no, new.company_no_old, new.tin, new.sst_no, new.sst_applies,
      new.bill_contact_id, new.finance_email, new.billing_address, new.bill_sgd)
     is distinct from
     (old.legal_name, old.company_no, old.company_no_old, old.tin, old.sst_no, old.sst_applies,
      old.bill_contact_id, old.finance_email, old.billing_address, old.bill_sgd)
     and coalesce(current_setting('role', true), '') = 'authenticated'
     and not public.allowed('clients.billing', 'work') then
    -- A write with no signed-in caller (the service role's read from Bukku,
    -- the SQL Editor) is no person editing Billing, as an insert reads it
    -- (audit 2026-11-04: a client's first entity made from a Bukku contact
    -- holding a name alone refused the nightly read).
    raise exception 'You do not have permission to change billing details. Please ask an admin.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.clients_billing_guard() from public, anon, authenticated;

create or replace function public.client_entity_save(p_client uuid, p_entity uuid, p_values jsonb,
                                                     p_expected timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_name  text;
  v_vals  jsonb;
  v_was   public.billing_entities;
  v_held  public.billing_entities;
  v_moved text[] := '{}';
  v_at    timestamptz;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  if v_name is null or not exists (select 1 from public.client_entities ce
                                    where ce.client_id = p_client and ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- An entity Bukku holds is saved to Bukku, never here: a portal save would
  -- be read over by Bukku's (audit 2026-10-30).
  if exists (select 1 from public.bukku_links l where l.kind = 'entity' and l.record_id = p_entity and l.held_at is not null) then
    return jsonb_build_object('error', 'held');
  end if;
  select * into v_was from public.billing_entities e where e.id = p_entity for update;
  if p_expected is not null and v_was.updated_at is distinct from p_expected then
    return jsonb_build_object('error', 'stale', 'entity', public.billing_entity_json(p_entity, p_client));
  end if;
  v_vals := public.billing_entity_clean(p_values);
  if v_vals ? 'error' then return v_vals; end if;
  if v_vals ->> 'bill_contact_id' is not null
     and (v_vals ->> 'bill_contact_id')::uuid is distinct from v_was.bill_contact_id
     and not exists (
       select 1 from public.client_contacts k join public.client_entities ce on ce.client_id = k.client_id
        where k.id = (v_vals ->> 'bill_contact_id')::uuid and k.archived_at is null and ce.entity_id = p_entity) then
    return jsonb_build_object('error', 'bad-contact');
  end if;
  if length(regexp_replace(coalesce(v_vals ->> 'company_no', ''), '\D', '', 'g')) > 0 then
    -- One BRN is checked and taken at a time across every client, so two
    -- presses at once never make it twice (audit 2026-11-04).
    perform pg_advisory_xact_lock(hashtextextended('entity-brn:' || regexp_replace(v_vals ->> 'company_no', '\D', '', 'g'), 0));
    select * into v_held from public.billing_entities e
     where e.id <> p_entity
       and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
       and regexp_replace(coalesce(v_was.company_no, ''), '\D', '', 'g') <> regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
     order by e.created_at limit 1;
    if v_held.id is not null then
      return jsonb_build_object('error', 'brn-taken', 'entity',
                                jsonb_build_object('id', v_held.id, 'legal_name', v_held.legal_name));
    end if;
  end if;
  v_moved := array_remove(array[
    case when v_was.legal_name is distinct from v_vals ->> 'legal_name' then 'Company name as registered' end,
    case when v_was.company_no is distinct from v_vals ->> 'company_no' then 'Business registration no.' end,
    case when v_was.company_no_old is distinct from v_vals ->> 'company_no_old' then 'Old registration no.' end,
    case when v_was.tin is distinct from v_vals ->> 'tin' then 'TIN' end,
    case when v_was.sst_no is distinct from v_vals ->> 'sst_no' then 'SST registration no.' end,
    case when v_was.bill_contact_id is distinct from (v_vals ->> 'bill_contact_id')::uuid then 'Billing contact' end,
    case when v_was.finance_email is distinct from v_vals ->> 'finance_email' then 'Finance department email' end,
    case when v_was.billing_address is distinct from v_vals ->> 'billing_address' then 'Company billing address' end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true, 'updated_at', v_was.updated_at); end if;
  update public.billing_entities e
     set legal_name = v_vals ->> 'legal_name', company_no = v_vals ->> 'company_no',
         company_no_old = v_vals ->> 'company_no_old', tin = v_vals ->> 'tin', sst_no = v_vals ->> 'sst_no',
         bill_contact_id = (v_vals ->> 'bill_contact_id')::uuid, finance_email = v_vals ->> 'finance_email',
         billing_address = v_vals ->> 'billing_address', updated_at = clock_timestamp()
   where e.id = p_entity
  returning e.updated_at into v_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name, 'Billing entity edited: ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true, 'updated_at', v_at);
end $$;
revoke all on function public.client_entity_save(uuid, uuid, jsonb, timestamptz) from public, anon;
grant execute on function public.client_entity_save(uuid, uuid, jsonb, timestamptz) to authenticated;

create or replace function public.client_entity_add(p_client uuid, p_entity uuid default null, p_values jsonb default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_name  text;
  v_vals  jsonb;
  v_ent   uuid := p_entity;
  v_main  boolean;
  v_held  public.billing_entities;
begin
  if not public.billing_entity_may(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select x.name into v_name from public.clients x where x.id = p_client;
  if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_ent is not null then
    if not exists (select 1 from public.billing_entities e where e.id = v_ent) then
      return jsonb_build_object('error', 'not-found');
    end if;
    if not public.billing_entity_reached(v_ent) then
      return jsonb_build_object('error', 'denied');
    end if;
    if exists (select 1 from public.client_entities ce where ce.entity_id = v_ent and ce.client_id = p_client) then
      return jsonb_build_object('error', 'taken');
    end if;
  else
    v_vals := public.billing_entity_clean(p_values);
    if v_vals ? 'error' then return v_vals; end if;
    if v_vals ->> 'bill_contact_id' is not null and not exists (
         select 1 from public.client_contacts k
          where k.id = (v_vals ->> 'bill_contact_id')::uuid and k.client_id = p_client and k.archived_at is null) then
      return jsonb_build_object('error', 'bad-contact');
    end if;
    if length(regexp_replace(coalesce(v_vals ->> 'company_no', ''), '\D', '', 'g')) > 0 then
    -- One BRN is checked and taken at a time across every client, so two
    -- presses at once never make it twice (audit 2026-11-04).
    perform pg_advisory_xact_lock(hashtextextended('entity-brn:' || regexp_replace(v_vals ->> 'company_no', '\D', '', 'g'), 0));
      select * into v_held from public.billing_entities e
       where regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = regexp_replace(v_vals ->> 'company_no', '\D', '', 'g')
       order by e.created_at limit 1;
      if v_held.id is not null then
        return jsonb_build_object('error', 'brn-taken', 'entity',
                                  jsonb_build_object('id', v_held.id, 'legal_name', v_held.legal_name));
      end if;
    end if;
    insert into public.billing_entities (legal_name, company_no, company_no_old, tin, sst_no, bill_contact_id,
                                         finance_email, billing_address, created_by)
    values (v_vals ->> 'legal_name', v_vals ->> 'company_no', v_vals ->> 'company_no_old', v_vals ->> 'tin',
            v_vals ->> 'sst_no', (v_vals ->> 'bill_contact_id')::uuid, v_vals ->> 'finance_email',
            v_vals ->> 'billing_address', me.id)
    returning id into v_ent;
  end if;
  -- One first entity at a time for a client (audit 2026-10-30).
  perform 1 from public.clients x where x.id = p_client for update;
  v_main := not exists (select 1 from public.client_entities ce where ce.client_id = p_client and ce.is_main);
  insert into public.client_entities (client_id, entity_id, is_main, added_by) values (p_client, v_ent, v_main, me.id);
  update public.billing_entities e set orphan_of = null where e.id = v_ent and e.orphan_of is not null;
  if v_main then perform public.billing_entity_put(v_ent, p_client); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.billing', v_name,
          case when p_entity is null then 'Billing entity added' else 'Billing entity added, already held' end
          || case when v_main then ' · main' else '' end);
  return jsonb_build_object('ok', true, 'id', v_ent, 'main', v_main);
end $$;
revoke all on function public.client_entity_add(uuid, uuid, jsonb) from public, anon;
grant execute on function public.client_entity_add(uuid, uuid, jsonb) to authenticated;

create or replace function public.ai_draft_usage()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  -- This calendar month in Malaysia, for what the calls cost.
  v_cal timestamptz := date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_uses constant text[] := array['drafts', 'checks', 'caption', 'script', 'analysis', 'checklist', 'analytics'];
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'limits', (select jsonb_object_agg(u, public.ai_cap(null, u)) from unnest(v_uses || array['per_report']) u),
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'price_search', coalesce(public.app_setting('ai_price_search', v_today), 10),
        'uses', count(*),
        'untracked', count(*) filter (where c.input_tokens is null),
        'input', coalesce(sum(c.input_tokens), 0),
        'output', coalesce(sum(c.output_tokens), 0),
        'searches', coalesce(sum(c.web_searches), 0),
        'usd', round(coalesce(sum(c.usd), 0), 2),
        'by', coalesce((select jsonb_object_agg(p.purpose, p.x) from (
            select c2.purpose, jsonb_build_object('uses', count(*), 'input', coalesce(sum(c2.input_tokens), 0),
                     'output', coalesce(sum(c2.output_tokens), 0), 'searches', coalesce(sum(c2.web_searches), 0),
                     'usd', round(coalesce(sum(c2.usd), 0), 2)) as x
              from (select d.purpose, d.input_tokens, d.output_tokens, d.web_searches,
                           (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                          + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                          + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens, d.web_searches,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                  + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
              from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'used', jsonb_build_object('drafts', u.drafts, 'checks', u.checks, 'caption', u.caption, 'script', u.script,
                                   'analysis', u.analysis, 'checklist', u.checklist, 'analytics', u.analytics),
        'cap', (select jsonb_object_agg(k, public.ai_cap(t.id, k)) from unnest(v_uses) k),
        'own', coalesce((select jsonb_object_agg(split_part(l.scope, ':', 2), l.daily) from public.ai_draft_limits l
                          where l.scope like t.id::text || ':%' and l.daily is not null), '{}'::jsonb),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed')) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
        cross join lateral (
          select count(*) filter (where d.purpose = 'draft') as drafts, count(*) filter (where d.purpose = 'check') as checks,
                 count(*) filter (where d.purpose = 'caption') as caption, count(*) filter (where d.purpose = 'script') as script,
                 count(*) filter (where d.purpose = 'analysis') as analysis, count(*) filter (where d.purpose = 'checklist') as checklist,
                 count(*) filter (where d.purpose = 'analytics') as analytics
            from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed') u
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'review', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'scripts', 'none')) >= public.level_rank('work')
              -- Brand analysis asks Clients: Brand at View, a checklist's
              -- writer Clients: Checklists at Work, Analytics its granted
              -- part: each is offered a limit before its first use (audit
              -- 2026-11-04).
              or public.level_rank(coalesce(t.access ->> 'clients.brand', t.access ->> 'clients', 'none')) >= public.level_rank('view')
              or public.level_rank(coalesce(t.access ->> 'clients.checklists', t.access ->> 'clients', 'none')) >= public.level_rank('work')
              or coalesce(t.access ->> 'team.analytics', 'none') <> 'none'
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;

-- END OF BILLING AUDIT FIXES -----------------------------------------------

select public.functions_tidy();
