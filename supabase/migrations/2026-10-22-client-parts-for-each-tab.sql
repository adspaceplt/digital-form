-- ===========================================================================
-- CLIENT PARTS FOR EACH TAB — Quotations, Brand and Checklists are parts of
-- Clients of their own (2026-10-22)
-- ===========================================================================
-- WHY (the user, 2026-10-22: "it does not cover every parent section and
-- every child section … AMV quote, AMV Service Lines, AMV Issue documents"):
-- Clients: Services answered for quotations and service lines alike, and
-- the Brand pane and the checklists answered to the Clients level alone, so
-- no group could be given one without the other.
--
-- WHAT IT CHANGES
--   * `clients.quotes` (Quotations): Build quote, a quotation's state and
--     the quotations list (`quote_preview`, `quotation_create`,
--     `quotation_set`, policy `quotations_read`), the rate card it prices
--     from (`rate_card_current`), a quotation sent on WhatsApp
--     (`wa_may_send`) and a quotation named on a checklist
--     (`checklist_prefill`, `client_checklist`). Issue Letter of Offer from
--     a quotation (`quotation_offer`) asks it and Clients: Services at Work,
--     since it makes service lines. Every group holding a level on Services
--     is given the same on Quotations, so nobody gains or loses a thing.
--   * `clients.brand` (Brand): Meta accounts (`meta_links_save`), the
--     Brand analysis (`brand_analysis_save`, `brand_analyses_list`,
--     `brand_analysis_confirm`, `ai_analysis_claim`, `ai_analysis_left`),
--     and the content brief and brand notes written on the client (trigger
--     `clients_brand_guard`, `brand-columns`, held as `client_review_columns`
--     holds its own).
--   * `clients.checklists` (Checklists): `client_checklist`,
--     `client_checklist_set`, `client_checklist_step`, `ai_checklist_claim`,
--     `ai_checklist_left`, `client_checklists_due`.
--   Each new part follows Clients where a group sets none, as every part.
--
-- ORDER: this file, then the pages. An old page asks the same functions and
-- is answered as before for every group. Safe to run twice. Rollback: each
-- function's definition before this file, policy `quotations_read` on
-- `allowed('clients.services', 'view')`, and
--   drop trigger if exists clients_brand_guard on public.clients;
-- the parts copied into the access maps may stay.
-- ===========================================================================

update public.team_roles r
   set access = r.access || jsonb_build_object('clients.quotes', r.access -> 'clients.services')
 where r.access ? 'clients.services' and not r.access ? 'clients.quotes';

alter policy quotations_read on public.quotations using (public.allowed('clients.quotes', 'view'));

create or replace function public.clients_brand_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  /* A function writing the row has asked its own permission, and a cascade
     is not a person: only a write made on the table through the API. */
  if pg_trigger_depth() > 1 or current_user <> 'authenticated' then
    return new;
  end if;
  if (new.brief, new.brand_notes) is distinct from (old.brief, old.brand_notes)
     and not public.allowed('clients.brand', 'work') then
    raise exception 'brand-columns: the content brief and brand notes need Clients: Brand at Work.'
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.clients_brand_guard() from public, anon, authenticated;

create or replace trigger clients_brand_guard before update on public.clients
  for each row execute function public.clients_brand_guard();

create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb := public.quote_card();
  v_cl uuid;
  v_fx numeric;
begin
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  if coalesce(p_sel->>'client', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.client_scope_ok('client', (p_sel->>'client')::uuid, 'view') then
    v_cl := (p_sel->>'client')::uuid;
  end if;
  v_fx := public.quote_fx(v_cl);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  return public.quote_fx_out(public.quote_adjust(public.quote_price(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_cl), v_fx),
           p_sel - 'client'), public.quote_tax_edits(p_sel->'edits')), v_fx) || jsonb_build_object('version', v_card->>'version');
end $$;

create or replace function public.quotation_create(p_client uuid, p_sel jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  return public.quotation_make(p_client, p_sel, nullif(btrim(coalesce(p_idem, '')), ''), 'console', me.name, null);
end $$;

create or replace function public.quotation_set(p_id uuid, p_what text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_word text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_what = 'not_proceeding' then
    update public.quotations set status = 'not_proceeding' where id = p_id; v_word := ' marked Not proceeding';
  elsif p_what = 'proceeding' then
    update public.quotations set status = case when requested_at is not null then 'requested' else 'sent' end
     where id = p_id;
    v_word := ' restored';
  elsif p_what = 'remove' then
    update public.quotations set removed_at = now(), removed_by = me.name where id = p_id; v_word := ' removed';
  elsif p_what = 'restore' then
    update public.quotations set removed_at = null, removed_by = null where id = p_id; v_word := ' restored';
  else
    return jsonb_build_object('error', 'bad-what');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || v_word);
  return jsonb_build_object('ok', true);
end $$;

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
  if me.id is null or not (public.allowed('clients.quotes', 'work') and public.allowed('clients.services', 'work')) then return jsonb_build_object('error', 'denied'); end if;
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

create or replace function public.rate_card_current()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version', v.version, 'valid_until', v.valid_until,
           'published_at', v.published_at, 'published_by', v.published_by, 'snapshot', v.snapshot)
    from public.rate_card_versions v
   where public.is_team() and (public.allowed('services', 'view') or public.allowed('clients.services', 'view')
                                or public.allowed('clients.quotes', 'view'))
   order by v.published_at desc
   limit 1
$$;

create or replace function public.wa_may_send(p_purpose text, p_to_kind text)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.allowed('whatsapp', 'work') and case p_purpose
    when 'report'   then public.allowed('whatsapp.report', 'work') and public.allowed('reports', 'view')
    when 'feedback' then public.allowed('whatsapp.feedback', 'work') and public.allowed('clients', 'view')
    when 'creator'  then public.allowed('whatsapp.booking', 'work') and public.allowed('campaigns', 'view')
    when 'approval' then p_to_kind = 'contact' and public.allowed('whatsapp.approval', 'work')
                         and (public.allowed('review.sets', 'view') or public.allowed('campaigns.campaigns', 'view'))
    when 'quotation' then p_to_kind = 'contact' and public.allowed('whatsapp.documents', 'work')
                          and public.allowed('clients.quotes', 'view')
    when 'offer'    then p_to_kind = 'contact' and public.allowed('whatsapp.documents', 'work')
                         and public.allowed('clients.documents', 'view')
    when 'message'  then case p_to_kind when 'contact' then public.allowed('clients.contacts', 'view')
                                        when 'creator' then public.allowed('campaigns.creators', 'view')
                                        else false end
    else false end
$$;

create or replace function public.checklist_prefill(p_client uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients;
  q text;
  sw jsonb;
  j text := E'\n';
begin
  select * into c from public.clients where id = p_client;
  if c.id is null or p_kind <> 'pre_ads' then return '{}'::jsonb; end if;
  select x.ref into q from public.quotations x
   where x.client_id = p_client and x.removed_at is null order by x.issued_at desc limit 1;
  select b.analysis->'swot' into sw from public.brand_analyses b
   where b.client_id = p_client and b.confirmed_at is not null order by b.version desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    -- The registered name is Billing's, and a quotation Quotations' (audit S4):
    -- each is prefilled only for a reader who may open it.
    'details.entity', nullif(coalesce(case when public.allowed('clients.billing', 'view') or public.register_may('client', 'work')
                                           then nullif(btrim(c.legal_name), '') end, c.name), ''),
    'details.quotation', case when public.allowed('clients.quotes', 'view') then q end,
    'competitors.direct', nullif(btrim(coalesce(c.brief->>'competitors', '')), ''),
    'competitors.strength', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'strengths', '[]'::jsonb))), j), ''),
    'competitors.weakness', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'weaknesses', '[]'::jsonb))), j), ''),
    'competitors.opportunities', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'opportunities', '[]'::jsonb))), j), ''),
    'competitors.threats', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'threats', '[]'::jsonb))), j), '')));
end $$;

create or replace function public.client_checklist(p_client uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.client_checklists;
  t jsonb;
  pre jsonb;
  hints jsonb := '{}'::jsonb;
  q record;
  m timestamptz;
begin
  if me.id is null or not public.allowed('clients.checklists', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_kind not in ('onboarding', 'pre_ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select * into r from public.client_checklists where client_id = p_client and kind = p_kind;
  t := coalesce(r.template, public.checklist_template(p_kind));
  pre := public.checklist_prefill(p_client, p_kind);
  -- Once started, only what each reader's own access gives (the registered
  -- name, the quotation) is worked out on the read; it is never stored.
  if r.id is not null then
    pre := jsonb_strip_nulls(jsonb_build_object('details.entity', pre->'details.entity',
                                                'details.quotation', pre->'details.quotation'));
  end if;
  if p_kind = 'onboarding' and public.allowed('clients.quotes', 'view') then
    select x.ref, x.issued_at into q from public.quotations x
     where x.client_id = p_client and x.removed_at is null order by x.issued_at desc limit 1;
    if q.ref is not null then
      hints := hints || jsonb_build_object('pre.quotation', 'Quotation ' || q.ref || ' issued ' ||
        to_char(q.issued_at at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY'));
    end if;
  end if;
  if p_kind = 'onboarding' then
    select min(e.meeting_at) into m from public.ops_engagements e where e.client_id = p_client and e.meeting_at is not null;
    if m is not null then
      hints := hints || jsonb_build_object('pre.first_meeting', 'Meeting set for ' ||
        to_char(m at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY, FMHH12:MIam'));
    end if;
  end if;
  return jsonb_build_object(
    'kind', p_kind, 'title', t->>'title', 'version', t->>'version', 'lead', t->>'lead', 'sections', t->'sections',
    'started', r.id is not null, 'answers', coalesce(r.answers, '{}'::jsonb), 'prefill', coalesce(pre, '{}'::jsonb),
    'sections_na', to_jsonb(coalesce(r.sections_na, '{}'::text[])), 'status', coalesce(r.status, 'open'),
    'prepared', case when r.prepared_at is not null then jsonb_build_object('id', r.prepared_by, 'name', r.prepared_name, 'at', r.prepared_at) end,
    'reviewed', case when r.reviewed_at is not null then jsonb_build_object('id', r.reviewed_by, 'name', r.reviewed_name, 'at', r.reviewed_at) end,
    'history', jsonb_array_length(coalesce(r.history, '[]'::jsonb)),
    'hints', hints, 'me', me.id, 'filled_by_me', public.checklist_filled_by(r.answers, me.id, me.name),
    'can_work', public.allowed('clients.checklists', 'work') and public.client_scope_ok('client', p_client, 'work'),
    'can_manage', public.allowed('clients.checklists', 'manage') and public.client_scope_ok('client', p_client, 'manage'),
    'updated_at', r.updated_at);
end $$;

create or replace function public.client_checklist_set(p_client uuid, p_kind text, p_item text, p_state text,
                                                       p_note text, p_value jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.client_checklists;
  c public.clients;
  t jsonb;
  sec jsonb;
  it jsonb;
  a jsonb;
  was jsonb;
  v_sec text := split_part(coalesce(p_item, ''), '.', 1);
  v_key text := split_part(coalesce(p_item, ''), '.', 2);
  what text;
begin
  if me.id is null or not public.allowed('clients.checklists', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_kind not in ('onboarding', 'pre_ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.client_checklists (client_id, kind, version, template, answers)
  select p_client, p_kind, t0->>'version', t0,
         (select coalesce(jsonb_object_agg(k, jsonb_build_object('value', v)), '{}'::jsonb)
            from jsonb_each(public.checklist_prefill(p_client, p_kind) - 'details.entity' - 'details.quotation') e(k, v))
    from (select public.checklist_template(p_kind) t0) z
  on conflict (client_id, kind) do nothing;
  select * into r from public.client_checklists where client_id = p_client and kind = p_kind for update;
  if r.status <> 'open' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
  t := r.template;
  select s into sec from jsonb_array_elements(t->'sections') s where s->>'key' = v_sec;
  if sec is null then return jsonb_build_object('error', 'bad-item'); end if;

  if v_key = '' then
    if p_state = 'na' then
      update public.client_checklists set sections_na = array(select distinct unnest(sections_na || v_sec)),
             updated_at = now() where id = r.id;
      what := (sec->>'title') || ': not applicable';
    elsif coalesce(p_state, '') = '' then
      update public.client_checklists set sections_na = array_remove(sections_na, v_sec), updated_at = now() where id = r.id;
      what := (sec->>'title') || ': applicable';
    else return jsonb_build_object('error', 'bad-state'); end if;
  else
    select i into it from jsonb_array_elements(sec->'items') i where i->>'key' = v_key;
    if it is null then return jsonb_build_object('error', 'bad-item'); end if;
    was := coalesce(r.answers->p_item, '{}'::jsonb);
    a := was;
    if p_state is not null then
      if it->>'kind' <> 'tick' or p_state not in ('', 'done', 'na') then return jsonb_build_object('error', 'bad-state'); end if;
      a := (a - 'state' - 'by' - 'by_id' - 'at') || case when p_state = '' then '{}'::jsonb
             else jsonb_build_object('state', p_state, 'by', me.name, 'by_id', me.id, 'at', now()) end;
      what := (it->>'label') || ': ' || case p_state when 'done' then 'done' when 'na' then 'not applicable' else 'not done' end;
    end if;
    if p_note is not null then
      if char_length(p_note) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
      a := (a - 'note') || case when btrim(p_note) = '' then '{}'::jsonb else jsonb_build_object('note', btrim(p_note)) end;
      a := a || jsonb_build_object('set_by', me.id);
      what := coalesce(what, (it->>'label') || ': note changed');
    end if;
    if p_value is not null then
      if it->>'kind' = 'tick' then return jsonb_build_object('error', 'bad-value'); end if;
      if it->>'kind' = 'text' and (jsonb_typeof(p_value) <> 'string' or char_length(p_value #>> '{}') > 4000) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      if it->>'kind' = 'choice' and (jsonb_typeof(p_value) <> 'string' or
         (p_value #>> '{}' <> '' and not (it->'choices') ? (p_value #>> '{}'))) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      if it->>'kind' = 'multi' and (jsonb_typeof(p_value) <> 'array' or
         exists (select 1 from jsonb_array_elements(p_value) v where jsonb_typeof(v) <> 'string' or not (it->'choices') ? (v #>> '{}'))) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      /* A table (r1.2's Meta Campaign Setup): twelve rows at most, each
         row only the item's own columns, each cell words of 400 at most. */
      if it->>'kind' = 'table' and (jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) > 12 or
         exists (select 1 from jsonb_array_elements(p_value) rw where jsonb_typeof(rw) <> 'object' or
           exists (select 1 from jsonb_each(rw) e where jsonb_typeof(e.value) <> 'string' or char_length(e.value #>> '{}') > 400 or
             not exists (select 1 from jsonb_array_elements(it->'columns') col where col->>0 = e.key)))) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      a := (a - 'value') || case when p_value in ('""'::jsonb, '[]'::jsonb) then '{}'::jsonb
             else jsonb_build_object('value', p_value) end;
      a := a || jsonb_build_object('set_by', me.id);
      what := coalesce(what, (it->>'label') || ': ' || case when p_value in ('""'::jsonb, '[]'::jsonb) then 'cleared' else 'changed' end);
    end if;
    if a - 'set_by' = was - 'set_by' then return public.client_checklist(p_client, p_kind); end if;
    update public.client_checklists set answers = case when a = '{}'::jsonb then answers - p_item else jsonb_set(answers, array[p_item], a) end,
           updated_at = now() where id = r.id;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', c.name, (t->>'title') || ' · ' || what);
  return public.client_checklist(p_client, p_kind);
end $$;

create or replace function public.ai_checklist_claim(p_client uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('clients.checklists', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.clients c where c.id = p_client) then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('checklist_admin', 20) else public.ai_draft_limit('checklist', 10) end;
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'checklist' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'checklist', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, purpose)
  values (m.id, p_client, 'checklist') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;

create or replace function public.ai_checklist_left()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
begin
  if not public.allowed('clients.checklists', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('checklist_admin', 20) else public.ai_draft_limit('checklist', 10) end;
  return jsonb_build_object('limit', lim, 'next', since + interval '1 day',
    'left', greatest(0, lim - (select count(*) from public.ai_drafts d
      where d.team_member_id = m.id and d.purpose = 'checklist' and d.created_at >= since and d.outcome <> 'failed')::integer));
end $$;

create or replace function public.client_checklists_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null or not public.allowed('clients.checklists', 'view') then '[]'::jsonb else
    coalesce((select jsonb_agg(jsonb_build_object('client_id', c.id, 'name', c.name, 'slug', c.slug, 'owner', c.owner,
              'kind', k.kind, 'status', coalesce(r.status, 'open'), 'started', r.id is not null,
              'since', coalesce(c.stage_since, c.created_at)) order by coalesce(c.stage_since, c.created_at))
       from public.clients c
       cross join (values ('onboarding'), ('pre_ads')) k(kind)
       left join public.client_checklists r on r.client_id = c.id and r.kind = k.kind
      where c.stage = 'active'
        and coalesce(r.status, 'open') <> 'signed'
        and (r.id is not null
             or (select min((e->>'at')::timestamptz) from jsonb_array_elements(coalesce(c.stage_log, '[]'::jsonb)) e
                  where e->>'stage' = 'active' and e->>'at' is not null)
                >= ('2026-10-15'::date)::timestamp at time zone 'Asia/Kuala_Lumpur')
        and public.client_scope_ok('client', c.id, 'view')
        and not exists (select 1 from public.ops_engagement_checks x join public.ops_engagements e on e.id = x.engagement_id
                         where e.client_id = c.id and x.key = k.kind and x.state = 'na')), '[]'::jsonb) end
$$;

create or replace function public.client_checklist_step(p_client uuid, p_kind text, p_step text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.client_checklists;
  c public.clients;
  n int;
  word text;
begin
  if me.id is null or not public.allowed('clients.checklists', case when p_step = 'reopen' then 'manage' else 'work' end) then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_scope_ok('client', p_client, case when p_step = 'reopen' then 'manage' else 'work' end) then
    return jsonb_build_object('error', 'client-scope');
  end if;
  select * into c from public.clients where id = p_client;
  select * into r from public.client_checklists where client_id = p_client and kind = p_kind for update;
  if c.id is null or r.id is null then return jsonb_build_object('error', 'not-started'); end if;
  if p_step = 'prepare' then
    if r.status <> 'open' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    select count(*) into n
      from jsonb_array_elements(r.template->'sections') s, jsonb_array_elements(s->'items') i
     where i->>'kind' = 'tick' and not ((s->>'key') = any(r.sections_na))
       and coalesce(r.answers->((s->>'key') || '.' || (i->>'key'))->>'state', '') not in ('done', 'na');
    if n > 0 then return jsonb_build_object('error', 'incomplete', 'left', n); end if;
    update public.client_checklists set status = 'prepared', prepared_by = me.id, prepared_name = me.name,
           prepared_at = now(), updated_at = now() where id = r.id;
    word := 'prepared for review';
  elsif p_step = 'return' then
    if r.status <> 'prepared' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    update public.client_checklists set status = 'open', prepared_by = null, prepared_name = null, prepared_at = null,
           updated_at = now() where id = r.id;
    word := 'sent back';
  elsif p_step = 'review' then
    if r.status <> 'prepared' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    if r.prepared_by = me.id then return jsonb_build_object('error', 'own'); end if;
    if public.checklist_filled_by(r.answers, me.id, me.name) then return jsonb_build_object('error', 'own'); end if;
    update public.client_checklists set status = 'signed', reviewed_by = me.id, reviewed_name = me.name,
           reviewed_at = now(), updated_at = now() where id = r.id;
    update public.ops_engagement_checks k set state = 'ready', owner_id = me.id, updated_by = me.id, updated_at = now()
      from public.ops_engagements e
     where e.id = k.engagement_id and e.client_id = p_client and k.key = p_kind and k.state <> 'na';
    word := 'reviewed and signed off';
  elsif p_step = 'reopen' then
    if r.status <> 'signed' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    update public.client_checklists set status = 'open',
           history = history || jsonb_build_array(jsonb_build_object('answers', r.answers, 'sections_na', to_jsonb(r.sections_na),
             'version', r.version, 'prepared', r.prepared_name, 'prepared_at', r.prepared_at,
             'reviewed', r.reviewed_name, 'reviewed_at', r.reviewed_at, 'reopened_by', me.name, 'reopened_at', now())),
           prepared_by = null, prepared_name = null, prepared_at = null,
           reviewed_by = null, reviewed_name = null, reviewed_at = null, updated_at = now() where id = r.id;
    update public.ops_engagement_checks k set state = 'not_started', owner_id = null, updated_by = me.id, updated_at = now()
      from public.ops_engagements e
     where e.id = k.engagement_id and e.client_id = p_client and k.key = p_kind and k.state = 'ready';
    word := 'reopened';
  else
    return jsonb_build_object('error', 'bad-step');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', c.name, (r.template->>'title') || ' · ' || word);
  return public.client_checklist(p_client, p_kind);
end $$;

create or replace function public.meta_links_save(p_client uuid, p_brand uuid, p_ad_accounts jsonb, p_page jsonb, p_instagram jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_client text;
  v_brand text;
  v_accs jsonb := '[]'::jsonb;
  v_page jsonb := public.meta_asset_of(p_page);
  v_ig jsonb := public.meta_asset_of(p_instagram);
  e jsonb;
  a jsonb;
  v_old public.meta_links;
  v_detail text;
begin
  if me.id is null or not public.allowed('clients.brand', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select c.name into v_client from public.clients c where c.id = p_client;
  if v_client is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_brand is not null then
    select b.name into v_brand from public.client_brands b where b.id = p_brand and b.client_id = p_client;
    if v_brand is null then return jsonb_build_object('error', 'bad-brand'); end if;
  end if;
  if p_ad_accounts is not null and jsonb_typeof(p_ad_accounts) <> 'array' then return jsonb_build_object('error', 'bad-asset'); end if;
  for e in select x from jsonb_array_elements(coalesce(p_ad_accounts, '[]'::jsonb)) as t(x) loop
    a := public.meta_asset_of(e);
    if a is null or a ? 'bad' then return jsonb_build_object('error', 'bad-asset'); end if;
    if not exists (select 1 from jsonb_array_elements(v_accs) as y(z) where y.z ->> 'id' = a ->> 'id') then
      v_accs := v_accs || jsonb_build_array(a);
    end if;
  end loop;
  if jsonb_array_length(v_accs) > 20 or coalesce(v_page ? 'bad', false) or coalesce(v_ig ? 'bad', false) then
    return jsonb_build_object('error', 'bad-asset');
  end if;
  select * into v_old from public.meta_links l
   where l.client_id = p_client and l.brand_id is not distinct from p_brand for update;
  if v_old.id is not null and v_old.ad_accounts = v_accs and v_old.page is not distinct from v_page and v_old.instagram is not distinct from v_ig then
    return jsonb_build_object('ok', true);
  end if;
  if v_old.id is null and jsonb_array_length(v_accs) = 0 and v_page is null and v_ig is null then
    return jsonb_build_object('ok', true);
  end if;
  v_detail := concat_ws(' · ',
    case when coalesce(v_old.ad_accounts, '[]'::jsonb) <> v_accs
         then 'Meta ad accounts: ' || public.meta_names(v_old.ad_accounts) || ' → ' || public.meta_names(v_accs) end,
    case when v_old.page is distinct from v_page
         then 'Facebook Page: ' || public.meta_names(v_old.page) || ' → ' || public.meta_names(v_page) end,
    case when v_old.instagram is distinct from v_ig
         then 'Instagram: ' || public.meta_names(v_old.instagram) || ' → ' || public.meta_names(v_ig) end);
  -- Two first saves at once: the second writes over the first, never fails (audit 20).
  insert into public.meta_links (client_id, brand_id, ad_accounts, page, instagram, updated_by)
  values (p_client, p_brand, v_accs, v_page, v_ig, me.name)
  on conflict (client_id, coalesce(brand_id, '00000000-0000-0000-0000-000000000000'::uuid)) do update
     set ad_accounts = excluded.ad_accounts, page = excluded.page, instagram = excluded.instagram,
         updated_at = now(), updated_by = excluded.updated_by;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.brand', v_client, case when v_brand is not null then v_brand || ': ' else '' end || v_detail);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.brand_analysis_save(p_press uuid, p_analysis jsonb, p_sources jsonb,
                                                      p_basis jsonb, p_hypothesis boolean, p_model text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  d public.ai_drafts;
  c public.clients;
  a public.brand_analyses;
  v_no integer;
begin
  if not public.allowed('clients.brand', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.ai_drafts x where x.id = p_press for update;
  if d.id is null or d.team_member_id <> m.id or d.purpose <> 'analysis' or d.outcome <> 'pending'
     or exists (select 1 from public.brand_analyses x where x.press_id = d.id) then
    return jsonb_build_object('error', 'not-found');
  end if;
  select * into c from public.clients x where x.id = d.client_id;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  if jsonb_typeof(p_analysis) is distinct from 'object' or char_length(p_analysis::text) > 60000 then
    return jsonb_build_object('error', 'bad-analysis');
  end if;
  perform pg_advisory_xact_lock(hashtext('brand_analysis:' || c.id::text));
  select coalesce(max(x.version), 0) + 1 into v_no from public.brand_analyses x where x.client_id = c.id;
  insert into public.brand_analyses (client_id, version, analysis, sources, basis, hypothesis, model, press_id, created_by)
  values (c.id, v_no, p_analysis,
          case when jsonb_typeof(p_sources) = 'array' and char_length(p_sources::text) <= 12000 then p_sources else '[]'::jsonb end,
          case when jsonb_typeof(p_basis) = 'object' then p_basis else '{}'::jsonb end,
          coalesce(p_hypothesis, false), left(nullif(btrim(coalesce(p_model, '')), ''), 80), d.id, m.id)
  returning * into a;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'client.brand', c.name,
          'Brand analysis: version ' || v_no || ' run with AI' ||
          case when coalesce(p_hypothesis, false) then ', a starting hypothesis to test' else '' end);
  return public.brand_analysis_row(a);
end $$;

create or replace function public.brand_analyses_list(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.allowed('clients.brand', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  return jsonb_build_object('versions', coalesce((select jsonb_agg(public.brand_analysis_row(x) order by x.version desc)
    from (select * from public.brand_analyses a where a.client_id = p_client order by a.version desc limit 20) x), '[]'::jsonb));
end $$;

create or replace function public.ai_analysis_claim(p_client uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('clients.brand', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.clients c where c.id = p_client) then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  -- One count at a time, with the drafts, so the last analysis is taken once.
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('analysis_admin', 10) else public.ai_draft_limit('analysis', 3) end;
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'analysis' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'analysis', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, purpose)
  values (m.id, p_client, 'analysis') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;

create or replace function public.ai_analysis_left()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('clients.brand', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('analysis_admin', 10) else public.ai_draft_limit('analysis', 3) end;
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'analysis' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'analysis' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;

create or replace function public.brand_analysis_confirm(p_id uuid, p_on boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  a public.brand_analyses;
  c public.clients;
  v_an jsonb;
  v_was jsonb;
  v_new jsonb;
  v_put text;
  v_k text;
  v_filled text[] := '{}';
  v_word text;
begin
  if not public.allowed('clients.brand', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.brand_analyses x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(a.client_id, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  select * into c from public.clients x where x.id = a.client_id;
  if coalesce(p_on, true) = (a.confirmed_at is not null) then return public.brand_analysis_row(a); end if;
  update public.brand_analyses x
     set confirmed_at = case when coalesce(p_on, true) then now() end,
         confirmed_by = case when coalesce(p_on, true) then m.id end
   where x.id = p_id returning * into a;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'client.brand', c.name,
          'Brand analysis: version ' || a.version ||
          case when coalesce(p_on, true) then ' written with AI, read and confirmed' else ' confirmation withdrawn' end);

  /* The brief's empty parts, from what this analysis concluded. */
  if coalesce(p_on, true) and public.allowed('clients.brand', 'work') and public.client_scope_ok('client', c.id, 'work') then
    v_an := coalesce(a.analysis, '{}'::jsonb);
    v_was := case when jsonb_typeof(c.brief) = 'object' then c.brief else '{}'::jsonb end;
    v_new := v_was;
    foreach v_k in array array['audience', 'pains', 'pillars', 'tone', 'competitors'] loop
      if coalesce(btrim(v_was ->> v_k), '') <> '' then continue; end if;
      v_put := case v_k
        when 'audience' then coalesce(nullif(btrim(v_an #>> '{brief,audience}'), ''),
          (select string_agg(btrim(concat_ws(': ', s ->> 'name', s ->> 'who')), E'\n')
             from jsonb_array_elements(case when jsonb_typeof(v_an -> 'audiences') = 'array' then v_an -> 'audiences' else '[]'::jsonb end) s))
        when 'pains' then coalesce(nullif(btrim(v_an #>> '{brief,pains}'), ''),
          (select string_agg(btrim(s ->> 'pains'), E'\n')
             from jsonb_array_elements(case when jsonb_typeof(v_an -> 'audiences') = 'array' then v_an -> 'audiences' else '[]'::jsonb end) s
            where coalesce(btrim(s ->> 'pains'), '') <> ''))
        when 'pillars' then
          (select string_agg(btrim(p #>> '{}'), E'\n')
             from jsonb_array_elements(case when jsonb_typeof(v_an #> '{brief,pillars}') = 'array' and jsonb_array_length(v_an #> '{brief,pillars}') > 0
                                            then v_an #> '{brief,pillars}'
                                            when jsonb_typeof(v_an #> '{content,pillars}') = 'array' then v_an #> '{content,pillars}'
                                            else '[]'::jsonb end) p)
        when 'tone' then nullif(btrim(v_an #>> '{brief,tone}'), '')
        else (select string_agg(btrim(p #>> '{}'), ', ')
                from jsonb_array_elements(case when jsonb_typeof(v_an #> '{positioning,competitors}') = 'array'
                                               then v_an #> '{positioning,competitors}' else '[]'::jsonb end) p)
      end;
      v_put := left(btrim(coalesce(v_put, '')), 1000);
      if v_put = '' then continue; end if;
      v_new := v_new || jsonb_build_object(v_k, v_put);
      v_word := case v_k when 'audience' then 'Audience' when 'pains' then 'Pains' when 'pillars' then 'Content pillars'
                         when 'tone' then 'Tone of voice' else 'Competitors' end;
      v_filled := v_filled || v_word;
    end loop;
    if array_length(v_filled, 1) > 0 and char_length(v_new::text) <= 8000 then
      update public.clients x set brief = v_new where x.id = c.id;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(m.name, m.email), 'client.brand', c.name,
              'Content brief: ' || array_to_string(v_filled, ', ') || ' filled from Brand analysis version ' || a.version);
    else
      v_filled := '{}';
    end if;
  end if;
  return public.brand_analysis_row(a) || jsonb_build_object('filled', to_jsonb(v_filled));
end $$;

-- END OF CLIENT PARTS FOR EACH TAB --------------------------------------------
select public.functions_tidy();
