-- ===========================================================================
-- QUOTATION BRAND AND COMPANY PICK (2026-11-27)
-- ===========================================================================
-- WHY: ADP/QT2611-B02 kept the prospect's typed brand ("BIZGROWTH") after
-- a colleague saved it for one brand, "Lemmermeyer Malaysia", so its
-- notifications, lists, PDF and link read the stale word; and a signed
-- company that differed from the client record was left unflagged.
-- WHAT IT CHANGES: a quotation's brand follows its one named brand
-- (`quotations_brand_follows`, before insert or a change of selection,
-- so `quotation_make` and `quotation_edit` alike), the rows already
-- standing backfilled; `quotation_submit` takes `p_record` (legal_name,
-- company_no: keep or use) where the signed value differs from the
-- client's record, refusing `pick-company` until each is chosen, kept in
-- signed.record_pick; `quotation_review` applies a use (Billing Work,
-- `updated`), never where Bukku holds the billing or it bills another.
-- A signed quotation is never deleted: `delete_client` refuses
-- `has-signed`, and `quotations_signed_kept` refuses the row's delete
-- on any path, a client's cascade included.
-- ROLLBACK: drop trigger quotations_brand_follows on public.quotations;
-- drop function public.quotations_brand_follows(); drop trigger
-- quotations_signed_kept on public.quotations; drop function
-- public.quotations_signed_kept(); re-run `delete_client` from
-- 2026-10-17-delete-client-at-manage.sql; drop function
-- public.quotation_submit(uuid, uuid, jsonb, jsonb); re-run
-- `quotation_submit` from 2026-11-10-official-terms-capitalised.sql and
-- `quotation_review` from 2026-11-25-one-time-never-one-off.sql. The
-- brands backfilled stay.
-- Safe to run twice.

create or replace function public.quotations_brand_follows()
returns trigger
language plpgsql set search_path = public as $$
declare
  v_name text;
begin
  if jsonb_typeof(new.selection->'brands') = 'array' and jsonb_array_length(new.selection->'brands') = 1 then
    v_name := nullif(btrim(coalesce(new.selection->'brands'->0->>'name', '')), '');
    if v_name is not null then new.brand := v_name; end if;
  end if;
  return new;
end $$;
revoke all on function public.quotations_brand_follows() from public, anon, authenticated;
drop trigger if exists quotations_brand_follows on public.quotations;
create trigger quotations_brand_follows before insert or update of selection on public.quotations
  for each row execute function public.quotations_brand_follows();

update public.quotations
   set brand = btrim(selection->'brands'->0->>'name')
 where jsonb_typeof(selection->'brands') = 'array' and jsonb_array_length(selection->'brands') = 1
   and nullif(btrim(coalesce(selection->'brands'->0->>'name', '')), '') is not null
   and brand is distinct from btrim(selection->'brands'->0->>'name');

drop function if exists public.quotation_submit(uuid, uuid, jsonb);
create or replace function public.quotation_submit(p_id uuid, p_reviewer uuid, p_company jsonb, p_record jsonb default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  rv public.team_members;
  v_fix jsonb;
  v_moved jsonb := '[]'::jsonb;
  v_k text;
  v_words text := '';
  c  public.clients;
  v_picks jsonb := '{}'::jsonb;
  v_pick text;
  v_rec text;
  v_sig text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is not null and q.returned_at is null then return jsonb_build_object('error', 'in-review'); end if;
  select * into rv from public.team_members where id = p_reviewer;
  if rv.id is null or not public.quote_sign_may_review(rv.id) or not public.quote_sign_member_sees(rv.id, q.client_id) then
    return jsonb_build_object('error', 'bad-reviewer');
  end if;
  if rv.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if p_company is not null and jsonb_typeof(p_company) = 'object' then
    v_fix := public.quote_sign_company((q.signed->'company') || p_company);
    if v_fix ? 'error' then return v_fix; end if;
    for v_k in select jsonb_object_keys(v_fix->'company') loop
      if (v_fix->'company'->>v_k) is distinct from (q.signed->'company'->>v_k) then
        v_moved := v_moved || jsonb_build_array(jsonb_build_object('field', v_k, 'from', q.signed->'company'->v_k,
                     'to', v_fix->'company'->v_k, 'by', me.name, 'at', now()));
        v_words := v_words || '; ' || case v_k when 'legal_name' then 'Registered Company Name' when 'company_no' then 'Business Registration No.'
                                          when 'company_no_old' then 'Old Registration No.' when 'tin' then 'TIN' when 'sst_no' then 'SST Registration No.'
                                          when 'billing_address' then 'Company billing address' when 'finance_email' then 'Finance department email' else v_k end || ': ' || coalesce(q.signed->'company'->>v_k, 'not set') || ' → ' || coalesce(v_fix->'company'->>v_k, 'not set');
      end if;
    end loop;
    if jsonb_array_length(v_moved) > 0 then
      q.signed := q.signed
        || jsonb_build_object('company_signed', coalesce(q.signed->'company_signed', q.signed->'company'))
        || jsonb_build_object('company', v_fix->'company')
        || jsonb_build_object('corrections', coalesce(q.signed->'corrections', '[]'::jsonb) || v_moved);
    end if;
  end if;
  -- The signed company against the client record (QUOTATION BRAND AND
  -- COMPANY PICK): where a name or number differs, the colleague keeps the
  -- record's or takes the signed one; approval applies it. None where
  -- Bukku holds the billing or the quotation bills another party.
  select * into c from public.clients where id = q.client_id;
  if not exists (select 1 from public.bukku_links b where b.kind = 'client' and b.record_id = q.client_id and b.held_at is not null)
     and not (q.totals ? 'bill_to') then
    foreach v_k in array array['legal_name', 'company_no'] loop
      v_rec := case v_k when 'legal_name' then c.legal_name else c.company_no end;
      v_sig := q.signed->'company'->>v_k;
      -- A name read as the details form keeps it (spaces one, upper case),
      -- a number with no spaces: a difference of case alone is none.
      v_rec := upper(regexp_replace(btrim(coalesce(v_rec, '')), '\s+', (array[' ', ''])[(v_k = 'company_no')::int + 1], 'g'));
      v_sig := upper(regexp_replace(btrim(coalesce(v_sig, '')), '\s+', (array[' ', ''])[(v_k = 'company_no')::int + 1], 'g'));
      if v_rec <> '' and v_sig <> '' and v_rec <> v_sig then
        v_pick := case when jsonb_typeof(p_record) = 'object' then p_record->>v_k end;
        if v_pick is null or v_pick not in ('keep', 'use') then
          return jsonb_build_object('error', 'pick-company', 'field', v_k, 'record', v_rec);
        end if;
        v_picks := v_picks || jsonb_build_object(v_k, jsonb_build_object('pick', v_pick, 'record', v_rec));
        v_words := v_words || '; ' || case v_k when 'legal_name' then 'Registered Company Name' else 'Business Registration No.' end ||
                   case v_pick when 'keep' then ': client record kept as ' || v_rec else ': client record will change from ' || v_rec || ' on approval' end;
      end if;
    end loop;
  end if;
  q.signed := (q.signed - 'record_pick') || case when v_picks = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('record_pick', v_picks) end;
  update public.quotations
     set signed = q.signed, submitted_at = now(), submitted_by = me.name, reviewer_id = rv.id, reviewer_name = rv.name,
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · checked and submitted to ' || rv.name || case when v_words <> '' then ' ·' || substr(v_words, 2) else '' end);
  perform public.quote_sign_tell(array[rv.id], 'quote.review', 'Quotation to review · ' || q.brand,
    q.ref || ' · from ' || me.name, q.client_id, q.id::text || ':' || now()::text);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_submit(uuid, uuid, jsonb, jsonb) from public, anon;
grant execute on function public.quotation_submit(uuid, uuid, jsonb, jsonb) to authenticated;

create or replace function public.quotation_review(p_id uuid, p_ok boolean, p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  c  public.clients;
  co jsonb;
  v_note text := btrim(coalesce(p_note, ''));
  v_billing text := 'kept';
  v_lines int := 0;
  v_l jsonb;
  v_admin boolean;
  v_renewed int := 0;
  v_sid uuid;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.reviewed_at is not null then return jsonb_build_object('error', 'reviewed'); end if;
  if q.submitted_at is null or q.returned_at is not null then return jsonb_build_object('error', 'not-submitted'); end if;
  -- A colleague with no role is no admin: a null here would let anyone through.
  v_admin := coalesce(me.is_admin, false) or coalesce(me.role, '') = 'admin';
  if q.reviewer_id is distinct from me.id and not v_admin then return jsonb_build_object('error', 'not-reviewer'); end if;

  if not coalesce(p_ok, false) then
    if length(v_note) < 2 or length(v_note) > 1000 then return jsonb_build_object('error', 'note-required'); end if;
    update public.quotations set returned_at = now(), return_note = v_note, returned_by = me.name where id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · sent back by ' || me.name || ': ' || v_note);
    perform public.quote_sign_tell(array[public.quote_sign_member(q.submitted_by)], 'quote.returned',
      'Quotation sent back · ' || q.brand, q.ref || ' · ' || v_note, q.client_id, q.id::text || ':' || now()::text);
    return jsonb_build_object('ok', true, 'returned', true);
  end if;

  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  select * into c from public.clients where id = q.client_id for update;
  v_lines := 0;
  co := q.signed->'company';
  if exists (select 1 from public.bukku_links b where b.kind = 'client' and b.record_id = c.id and b.held_at is not null) then
    v_billing := 'held';
  elsif q.totals ? 'bill_to' then
    v_billing := 'kept';
  elsif coalesce(btrim(c.legal_name), '') = '' and coalesce(btrim(c.company_no), '') = '' and coalesce(btrim(c.billing_address), '') = '' then
    if not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'billing-access'); end if;
    update public.clients
       set legal_name = co->>'legal_name', company_no = co->>'company_no',
           company_no_old = coalesce(co->>'company_no_old', company_no_old), tin = coalesce(co->>'tin', tin),
           sst_no = coalesce(co->>'sst_no', sst_no), billing_address = co->>'billing_address',
           finance_email = coalesce(co->>'finance_email', finance_email)
     where id = c.id;
    v_billing := 'filled';
  elsif exists (select 1 from jsonb_each(coalesce(q.signed->'record_pick', '{}'::jsonb)) p where p.value->>'pick' = 'use') then
    -- The signed name or number the colleague chose over the record's
    -- (QUOTATION BRAND AND COMPANY PICK).
    if not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'billing-access'); end if;
    update public.clients
       set legal_name = case when q.signed->'record_pick'->'legal_name'->>'pick' = 'use' then co->>'legal_name' else legal_name end,
           company_no = case when q.signed->'record_pick'->'company_no'->>'pick' = 'use' then co->>'company_no' else company_no end
     where id = c.id;
    v_billing := 'updated';
  end if;

  update public.client_services set state = 'confirmed'
   where quotation_id = q.id and archived_at is null and state <> 'confirmed';
  select count(*) into v_lines from public.client_services where quotation_id = q.id and archived_at is null;
  /* A renewal (2026-11-12) confirms the client's own line for its new
     term, rate and start, never a second line beside it. */
  for v_l in select * from jsonb_array_elements(q.lines) loop
    if coalesce(v_l->>'renews', '') <> '' then
      update public.client_services
         set qty = (v_l->>'qty')::numeric, rate = (v_l->>'rate')::numeric, state = 'confirmed',
             tenure = case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
             term_adjust = v_l->>'basis' = 'month', term_pct = case when v_l->>'basis' = 'month' then coalesce((v_l->>'pct')::numeric, (q.totals->>'term_pct')::numeric) else 0 end,
             start_on = coalesce(nullif(v_l->>'start', '')::date, start_on), quotation_id = q.id, note = 'Renewed by quotation ' || q.ref,
             detail = coalesce(nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''), detail)
       where id = (v_l->>'renews')::uuid and client_id = q.client_id and archived_at is null;
      if found then v_renewed := v_renewed + 1; end if;
    end if;
  end loop;
  if v_lines = 0 then
    for v_l in select * from jsonb_array_elements(q.lines) loop
      if coalesce(v_l->>'renews', '') <> '' then continue; end if;
      insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                          tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
      values (q.client_id,
              case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
              public.quote_line_label(q.totals, v_l), (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
              case when v_l->>'basis' = 'month' then 'Per month' else 'One-time' end, 'confirmed',
              'Quotation ' || q.ref,
              case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
              v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then coalesce((v_l->>'pct')::numeric, (q.totals->>'term_pct')::numeric) else 0 end,
              nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
              q.id, nullif(v_l->>'tax_code', ''))
      returning id into v_sid;
      if coalesce(v_l->>'start', '') <> '' then
        update public.client_services set start_on = (v_l->>'start')::date where id = v_sid;
      end if;
      v_lines := v_lines + 1;
    end loop;
  end if;

  update public.quotations set reviewed_at = now(), reviewed_by = me.name, reviewed_role = nullif(btrim(coalesce(me.designation, '')), '')
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · reviewed and approved by ' || me.name ||
          case when q.reviewer_id is distinct from me.id then ' in place of ' || coalesce(q.reviewer_name, 'the reviewer') else '' end ||
          ' · ' || (v_lines + v_renewed) || case when v_lines + v_renewed = 1 then ' service line confirmed · ' else ' service lines confirmed · ' end ||
          case v_renewed when 0 then '' when 1 then '1 renewed · ' else v_renewed || ' renewed · ' end ||
          case v_billing when 'filled' then 'Billing filled from the signed quotation' when 'updated' then 'Billing updated from the signed quotation' when 'held' then 'Billing not changed, as Bukku keeps this client''s billing details'
               else 'Billing not changed' end);
  perform public.quote_sign_tell(array_remove(array[public.quote_sign_member(q.submitted_by), public.quote_sign_member(c.owner)], me.id),
    'quote.reviewed', 'Quotation approved · ' || q.brand, q.ref || ' · by ' || me.name, q.client_id, q.id::text);
  return jsonb_build_object('ok', true, 'billing', v_billing, 'lines', v_lines + v_renewed);
end $$;
revoke all on function public.quotation_review(uuid, boolean, text) from public, anon;
grant execute on function public.quotation_review(uuid, boolean, text) to authenticated;

-- A signed quotation is the contract (the user, through the coordinator:
-- "YES"): `delete_client` refuses `has-signed` before anything goes, and
-- no path deletes a signed row, a client's cascade included
-- (`quotations_signed_kept`).
create or replace function public.delete_client(p_client uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  want text;
  who  text := auth.jwt() ->> 'email';
  cl   public.clients%rowtype;
  me   public.team_members%rowtype;
begin
  if who is null then
    raise exception 'Not signed in';
  end if;
  /* The team's alone, at Clients Full Access: a client's login holds no team
     row, and hiding the menu item is not access control. */
  if not public.is_team() or not public.allowed('clients', 'manage') then
    raise exception 'Not allowed';
  end if;

  select value into want from public.app_secrets where key = 'delete_code';

  -- No code set: the interface asks for the client's name instead, and has
  -- already checked it. Nothing more to enforce here.
  if want is not null and want <> '' then
    if p_code is null or p_code <> want then
      return 'wrong-code';
    end if;
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then
    return 'not-found';
  end if;
  if exists (select 1 from public.quotations q where q.client_id = p_client and q.signed_at is not null) then
    return 'has-signed';
  end if;
  delete from public.clients where id = p_client;
  if not found then
    return 'not-found';
  end if;
  /* Filed here, in the same transaction, never by the page after the answer
     (audit R1, 2026-10-10): a reply lost on the way left no record. */
  select * into me from public.team_members where lower(email) = lower(who) and active limit 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, who), 'client.deleted', cl.name, coalesce(cl.client_code, ''));
  return 'deleted';
end $$;
revoke all on function public.delete_client(uuid, text) from public, anon;
grant execute on function public.delete_client(uuid, text) to authenticated;

create or replace function public.quotations_signed_kept()
returns trigger
language plpgsql set search_path = public as $$
begin
  if old.signed_at is not null then
    raise exception 'A signed quotation cannot be deleted.' using errcode = '42501', hint = 'has-signed';
  end if;
  return old;
end $$;
revoke all on function public.quotations_signed_kept() from public, anon, authenticated;
drop trigger if exists quotations_signed_kept on public.quotations;
create trigger quotations_signed_kept before delete on public.quotations
  for each row execute function public.quotations_signed_kept();
