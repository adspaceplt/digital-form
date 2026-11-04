-- ===========================================================================
-- QUOTATION AUDIT FIXES — a signed quotation held as the contract (2026-11-04)
-- ===========================================================================
-- WHY (the audit of 2026-11-04; the user: "fix all"): a signed and approved
-- quotation could be revised by Adjust and send and approved again, its
-- lines confirmed twice; a signed quotation could be cancelled under its
-- review and still approved; a website quotation that matched an existing
-- lead read that lead's billing and primary contact on its link; the code
-- went to any address typed with nothing told to the reviewer; a colleague's
-- Mark signed while the client typed the code was written over; a reviewer
-- outside the client's scope could be chosen, leaving the quotation stuck;
-- and a day that is no date (30 February) answered the database's words.
--
-- WHAT CHANGED
--   * `quotation_replace`: `signed` for a quotation signed or reviewed.
--   * `quotation_set`: the row held while it changes; Cancel and Remove of
--     a signed quotation refused `signed` (Request again sets it aside).
--   * `quotation_submit`, `quotation_review` (approve): `not-proceeding`
--     for a cancelled quotation, `revised` for one a later one revises.
--   * `quote_sign_member_sees(p_member, p_client)` (internal): a
--     colleague's client scope at Work, as `client_row_seen_by` reads it;
--     `quotation_reviewers` lists, and `quotation_submit` takes, only a
--     reviewer it reaches (`bad-reviewer`).
--   * `quotation_paper`: a day that is no date is `bad-day`.
--   * The Activity record names a corrected field by its label, counts
--     service lines in the singular for one, says Billing not changed in
--     words, and a signature on paper keyed in by (its panel's word).
--   * `quote_sign_code`, `quote_sign_finish`: the link read again once the
--     row is held; the signing record keeps `in_contacts`, whether the
--     address the code went to is a live contact's or the website contact's.
--   * `quote_website_read`: the record's company and primary contact
--     prefill a team quotation's link or the website quotation that made
--     the lead, never one that matched an existing lead; a closed or expired
--     link prefills nothing.
--
-- ORDER: this file (connector), then the pages (the console reads
-- `in_contacts` and draws no Adjust and send, Cancel or Remove on a signed
-- quotation). An open tab before the pages meets the new refusals in words
-- it already holds (`signed`, `not-proceeding`, `revised`). Safe to run
-- twice.
--
-- ROLLBACK: run QUOTATION SIGNING, QUOTATION REVIEW FIXES and QUOTATION
-- CANCELLED's functions again; the helper is then unused and harmless.
-- ===========================================================================

/* Whether a colleague's own client scope reaches a client at Work, as
   client_row_seen_by reads it for the caller. Internal. */
create or replace function public.quote_sign_member_sees(p_member uuid, p_client uuid)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  t public.team_members;
  c public.clients;
  band text;
begin
  select * into t from public.team_members m where m.id = p_member;
  if t.id is null then return false; end if;
  if coalesce(t.is_admin, false) or coalesce(t.role, '') = 'admin' then return true; end if;
  select * into c from public.clients x where x.id = p_client;
  if c.id is null then return false; end if;
  band := case when c.stage in ('lead', 'contacted', 'proposal') then 'clients.leads'
               when c.stage = 'past' then 'clients.past' end;
  if band is not null and public.level_rank(coalesce(t.access ->> band, t.access ->> 'clients')) < public.level_rank('work') then
    return false;
  end if;
  if coalesce(t.client_scope, 'all') = 'own' then
    if c.sales_by is not null and c.sales_by = t.id then return true; end if;
    if nullif(btrim(coalesce(c.owner, '')), '') is null then return coalesce(band = 'clients.leads', false); end if;
    return lower(btrim(c.owner)) = lower(btrim(coalesce(t.name, '')));
  end if;
  return true;
end $$;
revoke all on function public.quote_sign_member_sees(uuid, uuid) from public, anon, authenticated;

create or replace function public.quotation_replace(p_new uuid, p_old uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  n public.quotations;
  o public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into n from public.quotations where id = p_new for update;
  -- Held while it is revised, so a Send meanwhile waits and then reads it
  -- revised (audit 2026-10-30).
  select * into o from public.quotations where id = p_old for update;
  if n.id is null or o.id is null or n.client_id <> o.client_id or n.id = o.id
     or n.removed_at is not null or o.removed_at is not null
     or not public.client_scope_ok('client', n.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if n.source <> 'console' or n.replaces is not null then return jsonb_build_object('error', 'bad-quotation'); end if;
  -- A quotation the client signed is the contract: it is asked again, never
  -- revised over (audit 2026-11-04).
  if o.signed_at is not null or o.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  update public.quotations set replaces = o.id where id = n.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', n.brand, n.ref || ' revises ' || o.ref);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_replace(uuid, uuid) from public, anon;
grant execute on function public.quotation_replace(uuid, uuid) to authenticated;

create or replace function public.quotation_set(p_id uuid, p_what text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_word text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- A signed quotation is set aside with Request again, never cancelled or
  -- removed under its review (audit 2026-11-04).
  if p_what in ('not_proceeding', 'remove') and v_q.signed_at is not null then
    return jsonb_build_object('error', 'signed');
  end if;
  if p_what = 'not_proceeding' then
    update public.quotations set status = 'not_proceeding' where id = p_id; v_word := ' cancelled';
  elsif p_what = 'proceeding' then
    update public.quotations set status = case when requested_at is not null then 'requested' else 'sent' end
     where id = p_id;
    v_word := ' restored';
  elsif p_what in ('no_contact', 'contact') then
    if v_q.source <> 'website' then return jsonb_build_object('error', 'bad-what'); end if;
    update public.quotations
       set no_contact_at = case when p_what = 'no_contact' then coalesce(no_contact_at, now()) end,
           no_contact_by = case when p_what = 'no_contact' then coalesce(no_contact_by, me.name) end
     where id = p_id;
    v_word := case when p_what = 'no_contact' then ' · Do not contact: off → on' else ' · Do not contact: on → off' end;
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
revoke all on function public.quotation_set(uuid, text) from public, anon;
grant execute on function public.quotation_set(uuid, text) to authenticated;

create or replace function public.quotation_reviewers(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_last uuid;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_last := coalesce(q.reviewer_id, (select x.reviewer_id from public.quotations x
                                      where x.client_id = q.client_id and x.reviewer_id is not null and x.id <> q.id
                                      order by x.submitted_at desc nulls last limit 1));
  return jsonb_build_object('reviewers', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'code', m.staff_code, 'designation', m.designation,
                                        'last', m.id = v_last)
                     order by m.staff_code nulls last, m.name)
      from public.team_members m
     where m.id <> me.id and public.quote_sign_may_review(m.id)
       and public.quote_sign_member_sees(m.id, q.client_id)), '[]'::jsonb));
end $$;
revoke all on function public.quotation_reviewers(uuid) from public, anon;
grant execute on function public.quotation_reviewers(uuid) to authenticated;

create or replace function public.quotation_submit(p_id uuid, p_reviewer uuid, p_company jsonb)
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
        v_words := v_words || '; ' || case v_k when 'legal_name' then 'Registered name' when 'company_no' then 'Registration no.'
                                          when 'company_no_old' then 'Old registration no.' when 'tin' then 'TIN' when 'sst_no' then 'SST no.'
                                          when 'billing_address' then 'Billing address' when 'finance_email' then 'Finance email' else v_k end || ': ' || coalesce(q.signed->'company'->>v_k, 'not set') || ' → ' || coalesce(v_fix->'company'->>v_k, 'not set');
      end if;
    end loop;
    if jsonb_array_length(v_moved) > 0 then
      q.signed := q.signed
        || jsonb_build_object('company_signed', coalesce(q.signed->'company_signed', q.signed->'company'))
        || jsonb_build_object('company', v_fix->'company')
        || jsonb_build_object('corrections', coalesce(q.signed->'corrections', '[]'::jsonb) || v_moved);
    end if;
  end if;
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
revoke all on function public.quotation_submit(uuid, uuid, jsonb) from public, anon;
grant execute on function public.quotation_submit(uuid, uuid, jsonb) to authenticated;

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
  co := q.signed->'company';
  if exists (select 1 from public.bukku_links b where b.kind = 'client' and b.record_id = c.id and b.held_at is not null) then
    v_billing := 'held';
  elsif coalesce(btrim(c.legal_name), '') = '' and coalesce(btrim(c.company_no), '') = '' and coalesce(btrim(c.billing_address), '') = '' then
    if not public.allowed('clients.billing', 'work') then return jsonb_build_object('error', 'billing-access'); end if;
    update public.clients
       set legal_name = co->>'legal_name', company_no = co->>'company_no',
           company_no_old = coalesce(co->>'company_no_old', company_no_old), tin = coalesce(co->>'tin', tin),
           sst_no = coalesce(co->>'sst_no', sst_no), billing_address = co->>'billing_address',
           finance_email = coalesce(co->>'finance_email', finance_email)
     where id = c.id;
    v_billing := 'filled';
  end if;

  update public.client_services set state = 'confirmed'
   where quotation_id = q.id and archived_at is null and state <> 'confirmed';
  select count(*) into v_lines from public.client_services where quotation_id = q.id and archived_at is null;
  if v_lines = 0 then
    for v_l in select * from jsonb_array_elements(q.lines) loop
      insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                          tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
      values (q.client_id,
              case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
              v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
              case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'confirmed',
              'Quotation ' || q.ref,
              case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (q.totals->>'term')::int) else 1 end,
              v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (q.totals->>'term_pct')::numeric else 0 end,
              nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
              q.id, nullif(v_l->>'tax_code', ''));
      v_lines := v_lines + 1;
    end loop;
  end if;

  update public.quotations set reviewed_at = now(), reviewed_by = me.name, reviewed_role = nullif(btrim(coalesce(me.designation, '')), '')
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · reviewed and approved by ' || me.name ||
          case when q.reviewer_id is distinct from me.id then ' in place of ' || coalesce(q.reviewer_name, 'the reviewer') else '' end ||
          ' · ' || v_lines || case when v_lines = 1 then ' service line confirmed · ' else ' service lines confirmed · ' end ||
          case v_billing when 'filled' then 'Billing filled from the signed quotation' when 'held' then 'Billing not changed: Bukku holds the billing details'
               else 'Billing not changed' end);
  perform public.quote_sign_tell(array_remove(array[public.quote_sign_member(q.submitted_by), public.quote_sign_member(c.owner)], me.id),
    'quote.reviewed', 'Quotation approved · ' || q.brand, q.ref || ' · by ' || me.name, q.client_id, q.id::text);
  return jsonb_build_object('ok', true, 'billing', v_billing, 'lines', v_lines);
end $$;
revoke all on function public.quotation_review(uuid, boolean, text) from public, anon;
grant execute on function public.quotation_review(uuid, boolean, text) to authenticated;

create or replace function public.quotation_paper(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  pl jsonb := coalesce(p_payload, '{}'::jsonb);
  c1 jsonb; c2 jsonb;
  v_name text := btrim(regexp_replace(coalesce(pl->'signer'->>'name', ''), '\s+', ' ', 'g'));
  v_role text := btrim(regexp_replace(coalesce(pl->'signer'->>'designation', ''), '\s+', ' ', 'g'));
  v_day  text := btrim(coalesce(pl->>'day', ''));
  v_scan text := nullif(btrim(coalesce(pl->>'scan', '')), '');
  v_at timestamptz;
  v_d  date;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  c1 := public.quote_sign_company(pl->'company'); if c1 ? 'error' then return c1; end if;
  c2 := public.quote_sign_contact(pl->'contact'); if c2 ? 'error' then return c2; end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-signer_name'); end if;
  if length(v_role) < 2 or length(v_role) > 80 then return jsonb_build_object('error', 'bad-signer_designation'); end if;
  -- A day that is no date (30 February) is bad-day, never the database's
  -- own refusal (audit 2026-11-04).
  if v_day !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'bad-day'); end if;
  begin
    v_d := v_day::date;
  exception when others then
    return jsonb_build_object('error', 'bad-day');
  end;
  if v_d > (now() at time zone 'Asia/Kuala_Lumpur')::date or v_d < (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'bad-day');
  end if;
  if v_scan is not null and v_scan !~ '^https://[^\s"''<>`\\]+$' then return jsonb_build_object('error', 'bad-scan'); end if;
  -- Noon in Malaysia on the day it was signed.
  v_at := (v_d + time '12:00') at time zone 'Asia/Kuala_Lumpur';
  update public.quotations
     set signed_at = v_at,
         signed = jsonb_build_object('via', 'paper', 'company', c1->'company', 'contact', c2->'contact',
           'signer', jsonb_build_object('name', v_name, 'designation', v_role), 'signature', null, 'scan', v_scan,
           'record', jsonb_build_object('at', v_at, 'by', me.name, 'entered_at', now())),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' signed on paper by ' || v_name || ' for ' || (c1->'company'->>'legal_name') || ' on ' ||
          public.register_day(v_d) || ' · keyed in by ' || me.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_paper(uuid, jsonb) from public, anon;
grant execute on function public.quotation_paper(uuid, jsonb) to authenticated;

create or replace function public.quote_sign_code(p_key text, p_payload jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  o   jsonb := public.quote_sign_open(p_key);
  q   public.quotations;
  pl  jsonb := coalesce(p_payload, '{}'::jsonb);
  c1  jsonb; c2 jsonb; c3 jsonb;
  v_code text;
  v_id uuid;
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  -- Read again once the row is held: a colleague's Mark signed, Cancel or
  -- revision meanwhile is seen (audit 2026-11-04).
  o := public.quote_sign_open(p_key);
  if o ? 'error' then return o; end if;
  if (o->>'id')::uuid is distinct from q.id then return jsonb_build_object('error', 'not-found'); end if;
  c1 := public.quote_sign_company(pl->'company'); if c1 ? 'error' then return c1; end if;
  c2 := public.quote_sign_contact(pl->'contact'); if c2 ? 'error' then return c2; end if;
  c3 := public.quote_sign_signer(pl->'signer', pl->'signature'); if c3 ? 'error' then return c3; end if;
  if coalesce(pl->>'agree', '') <> 'true' then return jsonb_build_object('error', 'bad-agree'); end if;
  if (select count(*) from public.quote_sign_codes s
       where s.quotation_id = q.id and s.created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.quote_sign_codes (quotation_id, code_hash, email, payload, expires_at)
  values (q.id, crypt(v_code, gen_salt('bf', 6)), c2->'contact'->>'email',
          jsonb_build_object('company', c1->'company', 'contact', c2->'contact', 'signer', c3->'signer', 'signature', c3->'signature'),
          now() + interval '15 minutes')
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'code', v_code, 'email', c2->'contact'->>'email', 'ref', q.ref,
    'name', btrim(coalesce(c2->'contact'->>'salutation', '') || ' ' || (c2->'contact'->>'name')));
end $$;
revoke all on function public.quote_sign_code(text, jsonb) from public, anon, authenticated;
grant execute on function public.quote_sign_code(text, jsonb) to service_role;

create or replace function public.quote_sign_finish(p_key text, p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  o   jsonb := public.quote_sign_open(p_key);
  q   public.quotations;
  s   public.quote_sign_codes;
  c   public.clients;
  h   json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  v_at timestamptz := now();
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  -- Read again once the row is held: a colleague's Mark signed, Cancel or
  -- revision meanwhile is seen (audit 2026-11-04).
  o := public.quote_sign_open(p_key);
  if o ? 'error' then return o; end if;
  if (o->>'id')::uuid is distinct from q.id then return jsonb_build_object('error', 'not-found'); end if;
  select * into s from public.quote_sign_codes x
   where x.quotation_id = q.id and x.used_at is null
   order by x.created_at desc limit 1 for update;
  if s.id is null then return jsonb_build_object('error', 'no-code'); end if;
  if s.expires_at <= now() then return jsonb_build_object('error', 'code-expired'); end if;
  if s.tries >= 5 then return jsonb_build_object('error', 'locked'); end if;
  if regexp_replace(coalesce(p_code, ''), '\s+', '', 'g') !~ '^[0-9]{6}$'
     or crypt(regexp_replace(p_code, '\s+', '', 'g'), s.code_hash) <> s.code_hash then
    update public.quote_sign_codes set tries = tries + 1 where id = s.id;
    return jsonb_build_object('error', 'wrong', 'left', greatest(0, 4 - s.tries));
  end if;
  update public.quote_sign_codes set used_at = v_at where id = s.id;
  update public.quotations
     set signed_at = v_at,
         signed = jsonb_build_object('via', 'online') || s.payload || jsonb_build_object('record', jsonb_build_object(
           'at', v_at, 'email', s.email,
           'in_contacts', exists (select 1 from public.client_contacts k
                                   where k.client_id = q.client_id and k.archived_at is null
                                     and lower(btrim(coalesce(k.email, ''))) = lower(btrim(coalesce(s.email, ''))))
                          or lower(btrim(coalesce(q.contact->>'email', ''))) = lower(btrim(coalesce(s.email, ''))),
           'ip', nullif(public.request_ip(), ''), 'country', nullif(public.request_country(), ''),
           'agent', left(coalesce(h ->> 'user-agent', ''), 300),
           'fingerprint', upper(left(encode(digest(q.ref || q.lines::text || q.totals::text || s.payload::text || v_at::text, 'sha256'), 'hex'), 16)))),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  select * into c from public.clients where id = q.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', q.brand,
          q.ref || ' signed on the quotation link by ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name'));
  -- Who prepared it and the person in charge are told; where neither is
  -- here (a website lead nobody has taken), the team who work leads.
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(c.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.id::text || ':' || v_at::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(c.owner)],
      'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.client_id, q.id::text || ':' || v_at::text);
  end if;
  return jsonb_build_object('ok', true, 'at', v_at);
end $$;
revoke all on function public.quote_sign_finish(text, text) from public;
grant execute on function public.quote_sign_finish(text, text) to anon, authenticated;

create or replace function public.quote_website_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  c  public.clients;
  m  public.team_members;
  pm public.team_members;
  pc public.client_contacts;
  d  public.client_documents;
  f  public.client_detail_forms;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_stage text;
  v_portal boolean := false;
  v_billed boolean;
  v_own boolean;
  v_unsent boolean;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  -- Any quotation with a link: a website quotation, or a team's once
  -- `quotation_link` made one (QUOTATION SIGNING).
  select * into w from public.quotations x
   where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  -- A website quotation the team has not sent holds back its price at every
  -- stage, Not proceeding included (audit 2026-10-30).
  v_unsent := q.source = 'website' and q.released_at is null;
  select * into c from public.clients x where x.id = w.client_id;
  if nullif(btrim(coalesce(c.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = c.owner
     limit 1;
  end if;
  -- Prepared by: the colleague who made the revision shown; a website
  -- quotation's, the person in charge.
  select * into pm from public.team_members x where x.id = public.quote_sign_member(q.made_by);
  if pm.id is null and q.source = 'website' then pm := m; end if;
  -- The letter that stands on the quotation's lines, the latest first.
  select dd.* into d from public.client_documents dd
   where dd.kind = 'offer' and dd.voided_at is null and dd.superseded_by is null
     and exists (select 1 from public.client_document_services ds
                   join public.client_services s on s.id = ds.service_id
                  where ds.document_id = dd.id and s.quotation_id = q.id)
   order by dd.created_at desc limit 1;
  -- The client's details form is offered only on the website quotation
  -- that made the lead: a later website quotation that matched an existing
  -- lead's email and number never opens that lead's form (2026-10-26, audit).
  v_own := w.source = 'website' and c.created_at >= w.issued_at - interval '1 minute'
           and not exists (select 1 from public.quotations o
                            where o.client_id = c.id and o.issued_at < w.issued_at and o.id <> w.id);
  v_billed := coalesce(btrim(c.legal_name), '') <> '' and coalesce(btrim(c.company_no), '') <> ''
              and coalesce(btrim(c.billing_address), '') <> '';

  if d.id is not null then
    if d.verified_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(w.contact->>'email', '')))) into v_portal;
    elsif d.signed_at is not null then v_stage := 'signed';
    else v_stage := 'letter';
    end if;
  elsif w.status = 'not_proceeding' or q.status = 'not_proceeding' then
    v_stage := 'closed';
  elsif q.source = 'website' and q.released_at is null then
    -- Being reviewed: nothing priced leaves the database (2026-10-29).
    v_stage := 'review';
  elsif q.signed_at is not null then
    -- Signed on the link or on paper: accepted, then welcome once reviewed
    -- and Active (QUOTATION SIGNING).
    if q.reviewed_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(q.signed->'contact'->>'email', w.contact->>'email', '')))) into v_portal;
    else v_stage := 'accepted';
    end if;
  elsif q.valid_until < v_today then
    v_stage := 'expired';
  elsif not v_billed and v_own then
    select * into f from public.client_detail_forms x
     where x.client_id = c.id and x.voided_at is null
     order by x.created_at desc limit 1;
    if f.id is not null and f.submitted_at is not null and f.used_at is null then v_stage := 'billing_sent';
    elsif f.id is not null and f.submitted_at is null and f.expires_at > now() then v_stage := 'billing';
    end if;
  elsif v_billed and w.proceed_at is not null and w.source = 'website' then
    v_stage := 'billing_sent';
  end if;
  if v_stage is null then
    v_stage := case when w.proceed_at is not null then 'ready' else 'quote' end;
  end if;
  -- The record's details prefill only its own link: a website quotation
  -- that matched an existing lead never reads that lead's billing or
  -- primary contact, and a closed or expired link prefills nothing
  -- (audit 2026-11-04).
  if q.signed_at is null and (w.source <> 'website' or v_own) then
    select * into pc from public.client_contacts x
     where x.client_id = c.id and x.archived_at is null and x.is_primary
     order by x.created_at limit 1;
  end if;

  return jsonb_build_object(
    'ref', q.ref, 'first_ref', w.ref, 'revised', q.id <> w.id,
    'brand', coalesce(w.contact->>'brand', w.brand), 'version', case when q.source <> 'website' or q.released_at is not null then q.version end,
    'issued_at', q.issued_at,
    'valid_until', case when not v_unsent then q.valid_until end,
    'lines', case when not v_unsent then q.lines end,
    'totals', case when not v_unsent then q.totals end,
    'reply_due', case when v_stage = 'review' then q.reply_due end,
    'selection', w.selection, 'attention', coalesce(w.contact->>'name', pc.name),
    'stage', v_stage,
    'status', case when d.id is not null then 'offer' else q.status end,
    'details_key', case when v_stage = 'billing' then f.access_key end,
    'portal', v_portal,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today,
    'signed', case when q.signed_at is not null then jsonb_build_object('at', q.signed_at, 'via', q.signed->>'via',
                'signer', q.signed->'signer', 'signature', q.signed->'signature', 'company', q.signed->'company',
                'contact', q.signed->'contact', 'record', case when q.signed->>'via' = 'online' then q.signed->'record' end) end,
    'prepared', case when pm.id is not null then jsonb_build_object('name', pm.name, 'title', nullif(btrim(coalesce(pm.designation, '')), ''))
                     when nullif(btrim(coalesce(q.made_by, '')), '') is not null then jsonb_build_object('name', q.made_by, 'title', null) end,
    'reviewed', case when q.reviewed_at is not null then jsonb_build_object('name', q.reviewed_by, 'title', q.reviewed_role, 'at', q.reviewed_at) end,
    'prefill', case when q.signed_at is null and not v_unsent and v_stage not in ('closed', 'expired') then jsonb_build_object(
      'company', case when w.source <> 'website' or v_own then
                   jsonb_build_object('legal_name', coalesce(c.legal_name, ''), 'company_no', coalesce(c.company_no, ''),
                                      'billing_address', coalesce(c.billing_address, ''), 'sst_no', coalesce(c.sst_no, ''), 'tin', coalesce(c.tin, ''))
                 else jsonb_build_object('legal_name', '', 'company_no', '', 'billing_address', '', 'sst_no', '', 'tin', '') end,
      'contact', case when pc.id is not null then jsonb_build_object('salutation', coalesce(pc.salutation, ''), 'name', coalesce(pc.name, ''),
                                                                    'phone', coalesce(nullif(btrim(pc.phone), ''), case when btrim(coalesce(pc.whatsapp, '')) !~ '^@' then btrim(pc.whatsapp) end, ''),
                                                                     'email', coalesce(pc.email, ''))
                      else jsonb_build_object('salutation', coalesce(w.contact->>'salutation', ''), 'name', coalesce(w.contact->>'name', ''),
                                              'phone', coalesce(w.contact->>'whatsapp', ''), 'email', coalesce(w.contact->>'email', '')) end) end);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

-- END OF QUOTATION AUDIT FIXES ----------------------------------------------

select public.functions_tidy();
