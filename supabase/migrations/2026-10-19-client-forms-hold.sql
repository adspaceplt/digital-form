-- ===========================================================================
-- CLIENT FORMS HOLD — five findings of the 2026-10-19 audit of the Clients
-- section's forms. 2026-10-19. Safe to run twice. Rollback at the foot.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js compares the two.
--
-- WHAT CHANGED
--   3. A checklist never stores the registered company name or the
--      quotation reference it prefills (`details.entity`,
--      `details.quotation`): `client_checklist` works them out for each
--      reader on every read, as it did before the row existed, and
--      `client_checklist_set` seeds a new row without them. Rows already
--      holding them as prefilled lose them; a value the team typed over is
--      kept.
--   13. Sign-off (`client_checklist_step` review) is refused `own` to a
--      colleague who ticked or answered any item, not only to who prepared
--      it: a tick keeps its colleague's id (`by_id`) beside the name, an
--      answer or a note who set it (`set_by`); a tick from before reads by
--      its name (`checklist_filled_by`). `client_checklist` answers
--      `filled_by_me`, so the page draws no Sign off it would refuse.
--   10. The details form files its Activity record row as `Details form`,
--      the typed name in the detail, never as the actor.
--   15. `quotation_make`: a second press with the same key arriving while
--      the first is being written answers `again` with the first's row,
--      never a unique violation.
--   20. `meta_links_save`: two first saves at once write through
--      `insert ... on conflict ... do update`, never a unique violation.
--
-- ROLLBACK
--   Run again the earlier definitions: CLIENT CHECKLISTS'
--   client_checklist_step, CHECKLIST WRITER's client_checklist_set, DATA
--   HELD TO ITS LEVEL's client_checklist and client_details_submit,
--   QUOTATION IN SINGAPORE DOLLARS' quotation_make
--   and META LINKS' meta_links_save. The helper checklist_filled_by may
--   stay; the keys `by_id` and `set_by` are read by nothing else. Answers
--   cleared of a prefilled value are worked out again on every read.
-- ===========================================================================

-- Whether a colleague ticked or answered any item of a checklist (audit 13):
-- they never sign it off. A tick from before the colleague's id was kept is
-- read by its name.
create or replace function public.checklist_filled_by(p_answers jsonb, p_id uuid, p_name text)
returns boolean
language sql immutable set search_path = public as $$
  select coalesce(bool_or(e.value->>'by_id' = p_id::text or e.value->>'set_by' = p_id::text
                          or (e.value->>'by_id' is null and e.value ? 'state' and e.value->>'by' = p_name)), false)
    from jsonb_each(coalesce(p_answers, '{}'::jsonb)) e
$$;
revoke all on function public.checklist_filled_by(jsonb, uuid, text) from public, anon, authenticated;

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
  if me.id is null or not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
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
  if p_kind = 'onboarding' and public.allowed('clients.services', 'view') then
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
    'can_work', public.allowed('clients', 'work') and public.client_scope_ok('client', p_client, 'work'),
    'can_manage', public.allowed('clients', 'manage') and public.client_scope_ok('client', p_client, 'manage'),
    'updated_at', r.updated_at);
end $$;
revoke all on function public.client_checklist(uuid, text) from public, anon;
grant execute on function public.client_checklist(uuid, text) to authenticated;

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
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
revoke all on function public.client_checklist_set(uuid, text, text, text, text, jsonb) from public, anon;
grant execute on function public.client_checklist_set(uuid, text, text, text, text, jsonb) to authenticated;

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
  if me.id is null or not public.allowed('clients', case when p_step = 'reopen' then 'manage' else 'work' end) then
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
revoke all on function public.client_checklist_step(uuid, text, text) from public, anon;
grant execute on function public.client_checklist_step(uuid, text, text) to authenticated;

-- What was stored as prefilled is let go; a value typed over is kept.
update public.client_checklists k
   set answers = case when (k.answers->'details.entity') - 'value' = '{}'::jsonb then k.answers - 'details.entity'
                      else jsonb_set(k.answers, array['details.entity'], (k.answers->'details.entity') - 'value') end
  from public.clients c
 where c.id = k.client_id and k.kind = 'pre_ads'
   and k.answers->'details.entity'->>'value' in (nullif(btrim(c.legal_name), ''), c.name);
update public.client_checklists k
   set answers = case when (k.answers->'details.quotation') - 'value' = '{}'::jsonb then k.answers - 'details.quotation'
                      else jsonb_set(k.answers, array['details.quotation'], (k.answers->'details.quotation') - 'value') end
 where k.kind = 'pre_ads'
   and k.answers->'details.quotation'->>'value' in (select x.ref from public.quotations x where x.client_id = k.client_id);

create or replace function public.client_details_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_f    public.client_detail_forms;
  v_cl   public.clients;
  a      jsonb := coalesce(p_answers, '{}'::jsonb);
  t      text;
  v_name text := upper(btrim(regexp_replace(coalesce(a->>'legal_name', ''), '\s+', ' ', 'g')));
  v_brn  text := upper(regexp_replace(coalesce(a->>'company_no', ''), '\s+', '', 'g'));
  v_old  text := nullif(upper(regexp_replace(coalesce(a->>'company_no_old', ''), '\s+', '', 'g')), '');
  v_tin  text := nullif(upper(regexp_replace(coalesce(a->>'tin', ''), '\s+', '', 'g')), '');
  v_sst  text := nullif(upper(regexp_replace(coalesce(a->>'sst_no', ''), '\s+', '', 'g')), '');
  v_addr text := btrim(coalesce(a->>'billing_address', ''));
  v_fin  text := nullif(lower(btrim(coalesce(a->>'finance_email', ''))), '');
  v_sal  text := nullif(btrim(coalesce(a->>'contact_salutation', '')), '');
  v_cn   text := btrim(regexp_replace(coalesce(a->>'contact_name', ''), '\s+', ' ', 'g'));
  v_cp   text := btrim(coalesce(a->>'contact_phone', ''));
  v_ce   text := lower(btrim(coalesce(a->>'contact_email', '')));
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null for update;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if length(v_name) < 2 or length(v_name) > 160 then return jsonb_build_object('error', 'bad-legal_name'); end if;
  if v_brn !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-company_no'); end if;
  if v_old is not null and v_old !~ '^[A-Z0-9-]{4,20}$' then return jsonb_build_object('error', 'bad-company_no_old'); end if;
  if v_tin is not null and v_tin !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  if v_sst is not null and v_sst !~ '^[A-Z0-9-]{6,25}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  if length(v_addr) < 10 or length(v_addr) > 400 then return jsonb_build_object('error', 'bad-billing_address'); end if;
  if v_fin is not null and (v_fin !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_fin) > 160) then
    return jsonb_build_object('error', 'bad-finance_email');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-contact_salutation');
  end if;
  if length(v_cn) < 2 or length(v_cn) > 80 then return jsonb_build_object('error', 'bad-contact_name'); end if;
  t := regexp_replace(v_cp, '[^0-9]', '', 'g');
  if length(t) < 8 or length(t) > 15 or length(v_cp) > 30 then return jsonb_build_object('error', 'bad-contact_phone'); end if;
  if v_ce !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_ce) > 160 then return jsonb_build_object('error', 'bad-contact_email'); end if;

  update public.client_detail_forms f
     set submitted_at = now(),
         answers = jsonb_strip_nulls(jsonb_build_object(
           'legal_name', v_name, 'company_no', v_brn, 'company_no_old', v_old, 'tin', v_tin, 'sst_no', v_sst,
           'billing_address', v_addr, 'finance_email', v_fin, 'contact_salutation', v_sal,
           'contact_name', v_cn, 'contact_phone', v_cp, 'contact_email', v_ce))
   where f.id = v_f.id;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Details form', 'client.edited', v_cl.name,
          'Billing details received on the details form from ' || coalesce(v_sal || ' ', '') || v_cn);
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.details', 'Billing details received · ' || v_cl.name,
         'From ' || coalesce(v_sal || ' ', '') || v_cn || '. Review them on the client''s Billing.',
         v_cl.id, 'client.details:' || v_f.id || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or (public.level_rank(coalesce(m.access ->> 'clients.billing', m.access ->> 'clients')) >= 2
              -- held to the colleague's own client scope, as client_row_seen holds a reader (audit S7)
              and (v_cl.stage not in ('lead', 'contacted', 'proposal', 'past')
                   or public.level_rank(coalesce(m.access ->> case when v_cl.stage = 'past' then 'clients.past' else 'clients.leads' end,
                                                 m.access ->> 'clients')) >= 1)
              and (coalesce(m.client_scope, 'all') <> 'own'
                   or (nullif(btrim(coalesce(v_cl.owner, '')), '') is null and v_cl.stage in ('lead', 'contacted', 'proposal'))
                   or lower(btrim(coalesce(v_cl.owner, ''))) = lower(btrim(coalesce(m.name, ''))))))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_card jsonb := public.quote_card();
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
  v_fx numeric;
  v_sel jsonb := case when jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      when p_source = 'console' then p_sel - 'client'
                      else p_sel - 'edits' - 'client' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_p := public.quote_fx_out(public.quote_adjust(public.quote_price(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id), v_fx),
           v_sel), v_sel->'edits'), v_fx);
  if v_p ? 'error' then return v_p; end if;
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  begin
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'), p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  -- Two presses at once with one key: the second answers the first's.
  exception when unique_violation then
    select * into v_q from public.quotations q where q.idem = p_idem;
    if p_idem is null or v_q.id is null then raise; end if;
    return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true);
  end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST ' || case when v_fx is null then 'RM ' else 'S$ ' end ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

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
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
revoke all on function public.meta_links_save(uuid, uuid, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.meta_links_save(uuid, uuid, jsonb, jsonb, jsonb) to authenticated;

-- END OF CLIENT FORMS HOLD -------------------------------------------------
select public.functions_tidy();
