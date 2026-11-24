-- ===========================================================================
-- SAVED WHOLE AND TOLD (2026-11-24)
-- ===========================================================================
-- WHY: the findings the audit of 2026-11-24 left for the user's decision
-- (the user approved fixing them), each found in the last definition:
--   * `creator_pay_add`: the team replaced and approved a creator's bank
--     account and told the creator nothing; a change on the creator page
--     already told the email and WhatsApp on file (#1379). The team's add
--     now writes the same changes and prior set and queues Details changed
--     and `creator_changed` to the details on file where they changed.
--   * `campaign_options_posted_mail` and `client_details_submit`: the bell's
--     recipients were read from a colleague's raw `campaigns.pay` or
--     `clients.billing` key, so Sensitive details off and a part held over
--     its section still told them. `allowed_of(member, section, level)`
--     answers what `allowed()` answers for another colleague, and both
--     ask it; a removed colleague is told nothing.
--   * `hiring_email_templates_save`, `creator_email_templates_save`,
--     `mail_boxes_set`, `perf_dispute` and `video_script_share` wrote rows
--     in their loop and then refused a later one, so the rows before it
--     stood written and unrecorded. Each now checks every row first and
--     writes only when all pass.
--   * `issue_document`: an HR document's ADHR serial took no lock, so two
--     issues at once read the same number free and the second failed on
--     the unique serial. It now waits as a letter's ACL serial does.
--   * `agent_schedule_do`: a scheduled Mark as sent filed the day it ran,
--     not the sent date it wrote.
--
-- ORDER: this file (connector), then the pages (nothing on a page reads a
-- new answer). Safe to run twice.
-- ROLLBACK: run the ten functions from their last definitions before this
-- banner in schema.sql; `allowed_of` may stay unused.
-- ===========================================================================

-- SAVED WHOLE AND TOLD -------------------------------------------------------

/* What `allowed(section, level)` answers for another colleague: who is
   told of something only a part may see (a bell's recipients), read as
   the policies read the caller. Where the colleague is reached is not
   asked: a notice is read wherever they open it. */
create or replace function public.allowed_of(p_member uuid, p_section text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  k text := lower(coalesce(p_section, ''));
  sv text;
  lv text;
begin
  select * into t from public.team_members x
    where x.id = p_member and x.active
      and (x.access_until is null or x.is_admin or x.role = 'admin'
           or public.team_access_ends(x.access_until, x.access_until_time) > now());
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if k in ('clients.billing', 'campaigns.pay', 'suppliers.pay') and not t.sensitive_on then return false; end if;
  lv := t.access ->> k;
  if position('.' in k) > 0 then
    sv := t.access ->> split_part(k, '.', 1);
    if k in ('campaigns.pay', 'suppliers.pay') or lv is null then lv := sv;
    elsif not exists (select 1 from public.access_keys a where a.key = k and a.tier = 'granted')
      and public.level_rank(lv) > public.level_rank(sv) then lv := sv;
    end if;
  end if;
  return public.level_rank(lv) >= public.level_rank(p_level);
end $$;
revoke all on function public.allowed_of(uuid, text, text) from public, anon, authenticated;

create or replace function public.creator_pay_add(p_creator uuid, p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  cr     public.creators;
  v_held public.creator_pay_requests;
  v_in   jsonb := coalesce(p_values, '{}'::jsonb) || jsonb_build_object('confirm', 'true');
  v_chk  jsonb;
  v      jsonb;
  v_seq  int;
  v_new  public.creator_pay_requests;
  v_was  public.creator_pay_requests;
  v_chg  text[];
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into cr from public.creators x where x.id = p_creator for update;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  -- A number or detail left blank keeps the one held, as the creator's page does.
  select * into v_held from public.creator_pay_requests x where x.creator_id = cr.id and x.status in ('approved', 'pending')
   order by x.seq desc limit 1;
  if v_held.id is not null then
    if btrim(coalesce(v_in->>'id_no', '')) = '' and v_in->>'bill_kind' = v_held.bill_kind then
      v_in := v_in || jsonb_build_object('id_no', v_held.id_no);
    end if;
    if btrim(coalesce(v_in->>'account', '')) = '' and v_in->>'method' = v_held.method
       and upper(coalesce(v_in->>'currency', '')) = v_held.currency and coalesce(v_in->>'bank', '') = coalesce(v_held.bank, '') then
      v_in := v_in || jsonb_build_object('account', v_held.account);
    end if;
    if btrim(coalesce(v_in->>'address', '')) = '' and v_held.address is not null then v_in := v_in || jsonb_build_object('address', v_held.address); end if;
  end if;
  -- What is on file: the details approved last, the ones the bills go to.
  select * into v_was from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
   order by x.seq desc limit 1;
  v_chk := public.creator_pay_check(v_in);
  if v_chk ? 'field' then return jsonb_build_object('error', 'bad', 'field', v_chk->>'field'); end if;
  v := v_chk->'values';
  update public.creator_pay_requests x set status = 'withdrawn' where x.creator_id = cr.id and x.status = 'pending';
  select coalesce(max(x.seq), 0) + 1 into v_seq from public.creator_pay_requests x where x.creator_id = cr.id;
  insert into public.creator_pay_requests (creator_id, seq, ref, bill_kind, id_no, legal_name, tin, address, currency,
    method, bank, account, payee, email, whatsapp, entered_by)
  values (cr.id, v_seq, public.creator_pay_ref(cr.creator_code, v_seq), v->>'bill_kind', v->>'id_no', v->>'legal_name',
    v->>'tin', v->>'address', v->>'currency', v->>'method', v->>'bank', v->>'account', v->>'payee', v->>'email', v->>'whatsapp', me.id)
  returning * into v_new;
  v_chg := public.creator_pay_changes(v_was, v_new);
  update public.creator_pay_requests x set changes = v_chg, prior_id = v_was.id where x.id = v_new.id
  returning * into v_new;
  update public.creator_pay_requests x set status = 'replaced' where x.creator_id = cr.id and x.status = 'approved';
  update public.creator_pay_requests x set status = 'approved', decided_at = now(), decided_by = me.id where x.id = v_new.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', cr.name,
          coalesce(cr.creator_code || ' · ', '') || 'Payment details added by the team and approved · ' || v_new.ref || ' · ' ||
          public.creator_pay_method(v_new.method, v_new.bank) || ' ending ' || right(v_new.account, 4) ||
          coalesce(' · ' || nullif(array_to_string(v_chg, ' · '), ''), ''));
  -- Details on file changed by the team: the email and WhatsApp on file are
  -- told, as a change on the creator page tells them (review 2026-11-24).
  if v_was.id is not null and cardinality(v_chg) > 0 then
    perform public.creator_mail_queue('changed', v_new.id);
    perform public.wa_enqueue('creator_changed', public.wa_number(coalesce(nullif(v_was.whatsapp, ''), cr.whatsapp), 'MY'), cr.name,
      jsonb_build_array(cr.name, public.register_day((v_new.created_at at time zone 'Asia/Kuala_Lumpur')::date)),
      'creator', cr.id, null, null);
  end if;
  return jsonb_build_object('ok', true, 'ref', v_new.ref);
end $$;
revoke all on function public.creator_pay_add(uuid, jsonb) from public, anon;
grant execute on function public.creator_pay_add(uuid, jsonb) to authenticated;

create or replace function public.campaign_options_posted_mail()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators; m public.campaigns; v_ref text;
begin
  if new.state is distinct from 'posted' or old.state in ('posted', 'completed') then return null; end if;
  -- Told once a booking: a revert and a second move into Posted tell nobody again.
  if exists (select 1 from public.creator_emails e where e.option_id = new.id and e.purpose in ('request', 'posted')) then return null; end if;
  begin
    perform public.creator_mail_job('request', new.id);
    perform public.creator_mail_job('posted', new.id);
    select * into c from public.creators x where x.id = new.creator_id;
    select * into m from public.campaigns x where x.id = new.campaign_id;
    v_ref := public.creator_job_ref(new.id);
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.payment', 'Creator payment request · ' || coalesce(v_ref, c.name),
           c.name || ' · ' || coalesce(m.title, '') || coalesce(' · Pay by ' || public.register_day(new.pay_by), ''),
           'https://digital.adspace.me/admin/?s=campaigns&tab=payments&row=' || new.id,
           'creator.payment:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and tm.removed_at is null and not coalesce(tm.system, false)
       and public.allowed_of(tm.id, 'campaigns.pay', 'work')
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;
revoke all on function public.campaign_options_posted_mail() from public, anon, authenticated;
create or replace trigger campaign_options_posted_mail after update of state on public.campaign_options
  for each row execute function public.campaign_options_posted_mail();

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
  if exists (select 1 from public.clients c where c.id = v_f.client_id and c.stage = 'past') then
    return jsonb_build_object('error', 'not_found');
  end if;
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
   where m.active and m.removed_at is null
     and (m.is_admin or m.role = 'admin'
          or (public.allowed_of(m.id, 'clients.billing', 'work')
              -- held to the colleague's own client scope, as client_row_seen holds a reader (audit S7)
              and (v_cl.stage not in ('lead', 'contacted', 'proposal', 'past')
                   or public.level_rank(coalesce(m.access ->> case when v_cl.stage = 'past' then 'clients.past' else 'clients.leads' end,
                                                 m.access ->> 'clients')) >= 1)
              and (coalesce(m.client_scope, 'all') <> 'own'
                   or (nullif(btrim(coalesce(v_cl.owner, '')), '') is null and v_cl.stage in ('lead', 'contacted', 'proposal'))
                   or lower(btrim(coalesce(v_cl.owner, ''))) = lower(btrim(coalesce(m.name, '')))
                   or v_cl.sales_by = m.id)))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.hiring_email_templates_save(p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  x       jsonb;
  t       public.hiring_email_templates;
  v_bad   jsonb;
  v_moved text[] := '{}';
  v_word  text;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  -- Every row is checked before any is written: a refusal saves none
  -- (review 2026-11-24: rows before it stood saved and unrecorded).
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into t from public.hiring_email_templates y where y.kind = x->>'kind' for update;
    if t.kind is null then return jsonb_build_object('error', 'bad-request'); end if;
    if length(btrim(coalesce(x->>'subject', ''))) < 3 or length(x->>'subject') > 200 then
      return jsonb_build_object('error', 'bad-subject', 'kind', t.kind);
    end if;
    if length(btrim(coalesce(x->>'body', ''))) < 10 or length(x->>'body') > 5000 then
      return jsonb_build_object('error', 'bad-body', 'kind', t.kind);
    end if;
    v_bad := public.template_check(coalesce(x->>'subject', '') || ' ' || coalesce(x->>'body', ''), 'candidate');
    if v_bad is not null then return v_bad || jsonb_build_object('kind', t.kind); end if;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into t from public.hiring_email_templates y where y.kind = x->>'kind';
    if (t.on_send, t.subject, t.body) is distinct from
       (coalesce((x->>'on')::boolean, true), btrim(x->>'subject'), btrim(x->>'body')) then
      v_word := case t.kind when 'invite' then 'Interview invitation' when 'confirm' then 'Interview confirmed'
        when 'rescheduled' then 'Interview time changed'
        when 'cancelled' then 'Interview cancelled' when 'held' then 'Thank you for your interview'
        when 'moved' then 'Decision date changed' when 'pool' then 'Talent pool' when 'not' then 'Application unsuccessful'
        when 'doc' then 'Employment document' when 'doc_again' then 'Employment document sent again'
        when 'confirmed' then 'Document confirmed' else 'Document expired' end;
      v_moved := v_moved || (v_word ||
        case when t.on_send is distinct from coalesce((x->>'on')::boolean, true)
             then ': ' || case when t.on_send then 'Sent → Not sent' else 'Not sent → Sent' end
             else ': wording changed' end);
      update public.hiring_email_templates y set on_send = coalesce((x->>'on')::boolean, true), subject = btrim(x->>'subject'),
        body = btrim(x->>'body'), updated_at = now(), updated_by = me.id where y.kind = t.kind;
    end if;
  end loop;
  if cardinality(v_moved) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Candidate emails', array_to_string(v_moved, ' · '));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_email_templates_save(jsonb) from public, anon;
grant execute on function public.hiring_email_templates_save(jsonb) to authenticated;

create or replace function public.creator_email_templates_save(p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  x     jsonb;
  t     public.creator_email_templates;
  v_to  text;
  v_moved text[] := '{}';
  v_word text;
  v_bad jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  -- Every row is checked before any is written: a refusal saves none
  -- (review 2026-11-24: rows before it stood saved and unrecorded).
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into t from public.creator_email_templates y where y.purpose = x->>'purpose' for update;
    if t.purpose is null then return jsonb_build_object('error', 'bad-request'); end if;
    if length(btrim(coalesce(x->>'subject', ''))) < 3 or length(x->>'subject') > 200 then
      return jsonb_build_object('error', 'bad-subject', 'purpose', t.purpose);
    end if;
    if length(btrim(coalesce(x->>'body', ''))) < 10 or length(x->>'body') > 5000 then
      return jsonb_build_object('error', 'bad-body', 'purpose', t.purpose);
    end if;
    v_bad := public.template_check(coalesce(x->>'subject', '') || E'\n' || coalesce(x->>'body', ''),
      case when t.purpose in ('request', 'posted', 'paid') then 'creator-booking' else 'creator-details' end);
    if v_bad is not null then return v_bad || jsonb_build_object('purpose', t.purpose); end if;
    v_to := nullif(lower(btrim(coalesce(x->>'to_email', ''))), '');
    -- The finance address is held on Details to review; Payment request goes to it too.
    if t.purpose = 'review' and (v_to is null or v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_to) > 160) then
      return jsonb_build_object('error', 'bad-email');
    end if;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into t from public.creator_email_templates y where y.purpose = x->>'purpose';
    v_to := nullif(lower(btrim(coalesce(x->>'to_email', ''))), '');
    if t.purpose <> 'review' then v_to := null; end if;
    if (t.on_send, t.subject, t.body, t.to_email) is distinct from
       (coalesce((x->>'on')::boolean, true), btrim(x->>'subject'), btrim(x->>'body'), v_to) then
      v_word := case t.purpose when 'received' then 'Details received' when 'review' then 'Details to review'
        when 'approved' then 'Details approved' when 'changed' then 'Details changed' when 'request' then 'Payment request' when 'posted' then 'Post recorded'
        else 'Payment sent' end;
      v_moved := v_moved || (v_word ||
        case when t.on_send is distinct from coalesce((x->>'on')::boolean, true)
             then ': ' || case when t.on_send then 'Sent → Not sent' else 'Not sent → Sent' end
             when t.to_email is distinct from v_to then ': finance email changed'
             else ': wording changed' end);
      update public.creator_email_templates y set on_send = coalesce((x->>'on')::boolean, true), subject = btrim(x->>'subject'),
        body = btrim(x->>'body'), to_email = v_to, updated_at = now(), updated_by = me.id where y.purpose = t.purpose;
    end if;
  end loop;
  if cardinality(v_moved) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Creator emails', array_to_string(v_moved, ' · '));
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.mail_boxes_set(p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b  public.mail_boxes;
  v  text;
  v_said text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  -- Every address is checked before any is written: a refusal saves none
  -- (review 2026-11-24: mailboxes before it stood changed and unrecorded).
  for b in select * from public.mail_boxes order by array_position(array['general', 'hr', 'payables', 'finance', 'einvoice', 'legal'], key) for update loop
    v := lower(btrim(coalesce(p_values ->> b.key, b.address)));
    if v !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'bad-email', 'field', b.key); end if;
  end loop;
  for b in select * from public.mail_boxes order by array_position(array['general', 'hr', 'payables', 'finance', 'einvoice', 'legal'], key) loop
    v := lower(btrim(coalesce(p_values ->> b.key, b.address)));
    if v is distinct from b.address then
      update public.mail_boxes x set address = v where x.key = b.key;
      v_said := v_said || (b.label || ': ' || b.address || ' → ' || v);
    end if;
  end loop;
  if array_length(v_said, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Reply-to mailboxes', array_to_string(v_said, ' · '));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.mail_boxes_set(jsonb) from public, anon;
grant execute on function public.mail_boxes_set(jsonb) to authenticated;

create or replace function public.perf_dispute(p_review uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; it jsonb; n integer := 0; itm text; bid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'dispute-closed');
  end if;
  if r.dispute_until <= now() then return jsonb_build_object('error', 'window-closed'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('error', 'nothing-disputed');
  end if;
  -- Every item is checked before any is filed: a refusal files none (review
  -- 2026-11-24: items before it stood filed on a review still Shared).
  for it in select * from jsonb_array_elements(p_items) loop
    itm := it ->> 'item';
    if itm is null or itm not in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach') then
      return jsonb_build_object('error', 'bad-item');
    end if;
    if coalesce(btrim(it ->> 'reason'), '') = '' then return jsonb_build_object('error', 'reason-needed', 'item', itm); end if;
    bid := null;
    if itm = 'breach' then
      begin bid := (it ->> 'breach_id')::uuid; exception when others then bid := null; end;
      if bid is null or not exists (select 1 from public.perf_breaches b
                                     where b.id = bid and b.team_member_id = m.id
                                       and b.period = r.period and b.voided_at is null) then
        return jsonb_build_object('error', 'bad-item');
      end if;
    end if;
  end loop;
  for it in select * from jsonb_array_elements(p_items) loop
    itm := it ->> 'item';
    bid := case when itm = 'breach' then (it ->> 'breach_id')::uuid end;
    insert into public.perf_disputes (review_id, version, item, breach_id, reason)
    values (r.id, r.version, itm, bid, btrim(it ->> 'reason'));
    n := n + 1;
  end loop;
  update public.perf_reviews set status = 'disputed', rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'disputed', jsonb_build_object('items', n));
  perform public.perf_notify(r.reviewer_id, 'perf.disputed',
    m.name || ' raised a query on ' || public.perf_month_word(r.period) || '.',
    'perf.disputed.' || r.id || '.' || r.version);
  return public.perf_json(r, false);
end $$;

create or replace function public.video_script_share(p_ids uuid[], p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.video_scripts;
  v_cl  text;
  n     integer := 0;
  v_key text;
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  -- Every script's client is checked before any is moved: a refusal moves
  -- none (review 2026-11-24).
  for s in select * from public.video_scripts x where x.id = any (coalesce(p_ids, '{}')) order by x.video_no for update loop
    if not public.client_seen(s.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  end loop;
  for s in select * from public.video_scripts x where x.id = any (coalesce(p_ids, '{}')) order by x.video_no loop
    if (s.status = 'shared') = coalesce(p_on, false) then continue; end if;
    update public.video_scripts x
       set status = case when p_on then 'shared' else 'draft' end,
           shared_at = case when p_on then now() else null end
     where x.id = s.id;
    select c.name, c.script_key into v_cl, v_key from public.clients c where c.id = s.client_id;
    if p_on and v_key is null then
      loop
        v_key := public.new_link_key();
        exit when not exists (select 1 from public.clients c where c.script_key = v_key);
      end loop;
      update public.clients c set script_key = v_key where c.id = s.client_id;
    end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case when p_on then 'script.shared' else 'script.unshared' end, v_cl,
            public.video_script_label(s));
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
revoke all on function public.video_script_share(uuid[], boolean) from public, anon;
grant execute on function public.video_script_share(uuid[], boolean) to authenticated;

create or replace function public.issue_document(
  p_type      text,
  p_client    uuid,
  p_member    uuid,
  p_serial    text,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_idem      text,
  p_salutation text default null,
  p_signed    boolean default null,
  p_supplier  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who     text := lower(auth.jwt() ->> 'email');
  t       public.doc_types%rowtype;
  cl      public.clients%rowtype;
  mb      public.team_members%rowtype;
  sp      public.suppliers%rowtype;
  me      public.team_members%rowtype;
  v_old   public.documents%rowtype;
  v_serial text;
  v_base  text;
  v_n     int;
  v_id    uuid;
  v_langs text[];
  v_signed boolean;
begin
  select * into t from public.doc_types where id = p_type and active;
  -- A letter's own date, backdated where chosen (2026-11-12): never before
  -- 14 Aug 2023 or after today; its reference follows it.
  if p_issued_at is not null and not public.doc_day_ok(p_issued_at) then return jsonb_build_object('error', 'bad-date'); end if;
  if t.id is null then return jsonb_build_object('error', 'no-type'); end if;
  if not public.register_may(t.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;

  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;

  if t.family in ('quote_cover', 'client') then
    if p_client is null then return jsonb_build_object('error', 'no-client'); end if;
    select * into cl from public.clients where id = p_client;
    if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;
  end if;
  if t.family = 'hr' then
    if p_member is null then return jsonb_build_object('error', 'no-member'); end if;
    select * into mb from public.team_members where id = p_member;
    if mb.id is null then return jsonb_build_object('error', 'no-member'); end if;
    if coalesce(btrim(mb.staff_code), '') = '' then return jsonb_build_object('error', 'no-staff-code'); end if;
  end if;
  if t.family = 'supplier' then
    if p_supplier is null then return jsonb_build_object('error', 'no-supplier'); end if;
    select * into sp from public.suppliers where id = p_supplier;
    if sp.id is null then return jsonb_build_object('error', 'no-supplier'); end if;
    /* The agreement carries its schedules (2026-10-18): who the supplier is,
       when it starts, the fee and at least one account. */
    if t.id = 'supplier_sca' and not public.sca_complete(p_body) then
      return jsonb_build_object('error', 'agreement-incomplete');
    end if;
  end if;

  -- Whether the letter leaves space to be signed is the sheet's tick
  -- (2026-10-01), else the type's own setting. A signed letter is signed by
  -- a person, never by a permission; an unsigned one may still name who
  -- issued it, held to the same test.
  v_signed := coalesce(p_signed, t.signed);
  if coalesce(btrim(p_signatory ->> 'name'), '') <> '' and not public.issuer_name_ok(p_signatory ->> 'name') then
    return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
  end if;
  if v_signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;

  v_serial := nullif(btrim(coalesce(p_serial, '')), '');
  if v_serial is null then
    if t.family = 'quote_cover' then return jsonb_build_object('error', 'serial-required'); end if;
    if t.family in ('client', 'supplier') then
      if t.family = 'client' then
        if coalesce(btrim(cl.client_code), '') = '' then return jsonb_build_object('error', 'no-client-code'); end if;
        v_base := 'ACL/' || upper(btrim(cl.client_code));
      elsif t.id = 'supplier_sca' then
        v_base := 'AD/SCA/' || upper(btrim(sp.code));
      else
        v_base := 'ASL/' || upper(btrim(sp.code));
      end if;
      /* A Supplier Service Agreement is numbered by its month
         (AD/SCA/{Supplier ID}/{YYMM}{NN}, 2026-10-18); every other letter by
         its day. */
      v_base := v_base || '/' || to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
                                         case when t.id = 'supplier_sca' then 'YYMM' else 'YYMMDD' end);
      -- Two issuers on one client (or supplier) and day wait for each other
      -- here, so the second never reads the first one's number as free.
      perform pg_advisory_xact_lock(hashtext('acl:' || v_base));
      v_n := 1;
      loop
        v_serial := v_base || case when v_n < 10 then '0' else '' end || v_n;
        exit when not public.serial_taken(v_serial);
        v_n := v_n + 1;
        if v_n > 999 then return jsonb_build_object('error', 'no-serial'); end if;
      end loop;
    else
      v_base := 'ADHR/' || upper(mb.staff_code) || '/' || coalesce(t.code, 'GL') ||
                to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date), 'YYMM');
      -- Two issues for one colleague, kind and month wait for each other
      -- here, as a letter's do, so the second never takes the first's number
      -- (review 2026-11-24).
      perform pg_advisory_xact_lock(hashtext('adhr:' || v_base));
      v_serial := v_base; v_n := 1;
      while public.serial_taken(v_serial) loop
        v_n := v_n + 1; v_serial := v_base || '-' || v_n;
      end loop;
    end if;
  else
    if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
    if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  end if;

  v_langs := coalesce(p_languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;

  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, supplier_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key)
  values
    (t.id, t.family, t.name, v_serial,
     case when t.family in ('hr', 'supplier') then null else p_client end,
     case when t.family = 'hr' then p_member else null end,
     case when t.family = 'supplier' then p_supplier else null end,
     coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), t.title),
     coalesce(nullif(btrim(p_salutation), ''), t.salutation), t.closing,
     coalesce(p_recipient, '{}'::jsonb), coalesce(p_body, '{}'::jsonb), v_langs,
     case when coalesce(btrim(p_signatory ->> 'name'), '') <> '' then p_signatory else null end, v_signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''))
  returning id into v_id;

  -- The record is told an HR letter was issued and nothing about whom: the
  -- Activity record is read by more people than HR is.
  if t.family = 'hr' then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', 'HR', t.name);
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', case when t.family = 'supplier' then sp.name else cl.name end, v_serial || ' · ' || t.name);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
      end if;
    end if;
    return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.issue_document(text, uuid, uuid, text, date, text, jsonb, jsonb, jsonb, text[], text, text, boolean, uuid) to authenticated;

create or replace function public.agent_schedule_do(s public.agent_schedules, m public.team_members)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p jsonb := s.payload;
  v jsonb;
  b public.batches;
  c public.clients;
  v_on boolean;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_day   date;
  v_n integer;
  v_what text;
  v_rec jsonb;
begin
  if s.kind = 'reminder' then
    insert into public.ops_notifications (team_member_id, task_id, report_id, client_id, kind, title, body, dedupe_key)
    values (m.id,
            (select t.id from public.ops_tasks t where t.id = nullif(p ->> 'task_id', '')::uuid),
            (select r.id from public.sm_reports r where r.id = nullif(p ->> 'report_id', '')::uuid),
            (select x.id from public.clients x where x.id = nullif(p ->> 'client_id', '')::uuid),
            'assistant.reminder', left(s.title, 200), left(p ->> 'message', 500), 'agent.' || s.id)
    on conflict (dedupe_key) do nothing;
    return jsonb_build_object('ok', true, 'said', 'Reminder sent to you.');
  end if;
  if s.kind = 'mark_sent' then
    -- The record names the day written, never the day it ran (review 2026-11-24).
    v_day := coalesce(nullif(p ->> 'sent_on', '')::date, v_today);
    v := public.sm_report_sent((p ->> 'report_id')::uuid, v_day);
    if v ? 'error' then return v; end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.report', s.title, 'Marked as sent ' || public.register_day(v_day) || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Marked as sent.');
  end if;
  if s.kind = 'add_task' then
    v := public.ops_create_task(p, 'agent-schedule-' || s.id::text);
    if v ? 'error' then return v; end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.task', coalesce((select x.name from public.clients x where x.id = nullif(p ->> 'client_id', '')::uuid), 'Internal'),
            'Task added: ' || coalesce(p ->> 'title', '') || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Task added.', 'task_id', v ->> 'id');
  end if;
  if s.kind in ('publish_set', 'unpublish_set') then
    if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
    select * into b from public.batches x where x.id = (p ->> 'set_id')::uuid for update;
    if b.id is null or not public.client_seen(b.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
    v_on := s.kind = 'publish_set';
    if v_on and not exists (select 1 from public.posts po where po.batch_id = b.id) then
      return jsonb_build_object('error', 'empty');
    end if;
    if b.published = v_on then return jsonb_build_object('ok', true, 'said', case when v_on then 'Already published.' else 'Already unpublished.' end); end if;
    update public.batches x set published = v_on where x.id = b.id;
    select * into c from public.clients x where x.id = b.client_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, case when v_on then 'set.published' else 'set.withdrawn' end, c.name || ' — ' || b.title, null),
           (m.name, 'assistant.set', c.name || ' — ' || b.title,
            case when v_on then 'Published' else 'Unpublished' end || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', case when v_on then 'Published.' else 'Unpublished.' end);
  end if;
  if s.kind = 'whatsapp' then
    v := public.wa_compose_prepare('contact', (p ->> 'to_id')::uuid, p ->> 'purpose', nullif(p ->> 'ref', '')::uuid);
    if v ? 'error' then return v; end if;
    if not exists (select 1 from public.wa_templates t where t.purpose = p ->> 'purpose' and t.active and t.name <> '') then
      return jsonb_build_object('error', 'wa-off');
    end if;
    v_rec := public.wa_sent_recently('contact', (p ->> 'to_id')::uuid, p ->> 'purpose', nullif(p ->> 'ref', '')::uuid, null);
    if coalesce((v_rec ->> 'recent')::boolean, false) then
      return jsonb_build_object('skip', true, 'said', 'Not sent: it was sent on WhatsApp recently.');
    end if;
    /* What waits, as the composer words it: the set's undecided posts, or
       the creator's draft. */
    if p ->> 'purpose' = 'approval' then
      select * into b from public.batches x where x.id = nullif(p ->> 'ref', '')::uuid;
      if b.id is not null then
        select count(*)::int into v_n from public.posts po
         where po.batch_id = b.id
           and not exists (select 1 from public.reviews r where r.post_id = po.id and r.undone_at is null
                              and coalesce(r.round, 1) = coalesce(po.round, 1)
                              and (po.review_reset_at is null or r.created_at > po.review_reset_at));
        v_what := v_n || case when v_n = 1 then ' post' else ' posts' end || ' in ' || b.title;
      else
        v_what := coalesce(nullif(p ->> 'what', ''), 'A draft');
      end if;
    end if;
    perform public.wa_enqueue(p ->> 'purpose', v ->> 'number', v ->> 'name',
      jsonb_build_array(v ->> 'greeting', v ->> 'client',
        case p ->> 'purpose' when 'approval' then v_what when 'representative' then v ->> 'rep' else '' end,
        case when p ->> 'purpose' = 'approval' then 'https://digital.adspace.me/' || coalesce(v ->> 'link', '') else '' end),
      v ->> 'ref_kind', nullif(p ->> 'ref', '')::uuid, (v ->> 'client_id')::uuid,
      case p ->> 'purpose' when 'approval' then v ->> 'link' when 'representative' then v ->> 'code' end);
    /* Sent for a colleague, never Automatic. */
    update public.wa_outbox o set created_by = m.name, to_kind = 'contact', to_id = (p ->> 'to_id')::uuid
     where o.id = (select x.id from public.wa_outbox x where x.created_by = 'system' and x.created_at = now()
                      and x.purpose = p ->> 'purpose' and x.to_number = v ->> 'number' order by x.id limit 1);
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.whatsapp', coalesce(v ->> 'subject', s.title),
            'Sent on WhatsApp to ' || coalesce(v ->> 'name', '') || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Sent on WhatsApp.');
  end if;
  return jsonb_build_object('error', 'bad-kind');
end $$;
revoke all on function public.agent_schedule_do(public.agent_schedules, public.team_members) from public, anon, authenticated;

-- END OF SAVED WHOLE AND TOLD ----------------------------------------------

select public.functions_tidy();
