-- ===========================================================================
-- COLLEAGUES BY ID (2026-11-28)
-- ===========================================================================
-- WHY: six functions still found a colleague by the name a record holds
-- (`team_members.name` against `quotations.made_by`, `submitted_by` or
-- `clients.owner`): a renamed colleague, or two colleagues of one name,
-- lost a notification, a reviewer's reach or a client's person in charge.
-- A colleague is traced by their id, never by their name (as QUOTATION
-- MADE BY ITS COLLEAGUE'S ID, 2026-11-27).
-- WHAT IT CHANGES
--   * `quotations.submitted_by_id` (uuid, nullable, on delete set null),
--     read by a signed-in colleague as the list's other columns are.
--     `submitted_by` stays as written, a snapshot never rewritten.
--   * `quotations_submitted_by_id()` (before insert or update): the id
--     follows the name. Set to the caller's own id where the caller is the
--     colleague named, cleared with the name, never resolved from a name.
--   * Backfill: a `submitted_by` held by exactly one colleague takes that
--     colleague's id; a name two hold is left unfilled.
--   * `quote_sign_member(uuid)` replaces `quote_sign_member(text)`: the
--     colleague by id, while they work here. Its callers pass
--     `made_by_id`, `submitted_by_id` and `clients.owner_id`
--     (`quote_sign_finish`, `quotation_review`, `quote_decline`,
--     `quote_change_request`, `quote_website_read`).
--   * `quote_sign_member_sees`, `client_rep`, `client_details_submit`,
--     `sm_reports_published_notice` and `feedback_request` read the
--     client's person in charge by `clients.owner_id`.
-- ORDER: this file first, then the pages (no page changes: no page calls a
-- function whose signature moves). An open tab meets the same answers.
-- ROLLBACK: run the previous definitions again (QUOTATION SIGNING's
-- `quote_sign_member(text)`; QUOTATION REVIEW FIXES' `quote_sign_member_sees`;
-- the latest earlier band of each other function); drop trigger
-- quotations_submitted_by_id on public.quotations; drop function
-- public.quotations_submitted_by_id(); drop function
-- public.quote_sign_member(uuid). The column stays. Safe to run twice.

-- COLLEAGUES BY ID ----------------------------------------------------------

alter table public.quotations add column if not exists submitted_by_id uuid
  references public.team_members(id) on delete set null;
grant select (submitted_by_id) on table public.quotations to authenticated;

create or replace function public.quotations_submitted_by_id()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
begin
  if nullif(btrim(coalesce(new.submitted_by, '')), '') is null then
    new.submitted_by_id := null;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.submitted_by is not distinct from old.submitted_by then
    new.submitted_by_id := old.submitted_by_id;
    return new;
  end if;
  me := public.ops_me();
  new.submitted_by_id := case when me.id is not null and me.name = btrim(new.submitted_by) then me.id end;
  return new;
end $$;
revoke all on function public.quotations_submitted_by_id() from public, anon, authenticated;

/* The backfill runs with the trigger off: the trigger keeps the id an
   update leaves its name on. */
drop trigger if exists quotations_submitted_by_id on public.quotations;
with one as (
  select m.name, min(m.id::text)::uuid id from public.team_members m
   where nullif(btrim(m.name), '') is not null group by m.name having count(*) = 1
)
update public.quotations q set submitted_by_id = o.id
  from one o
 where q.submitted_by_id is null and btrim(q.submitted_by) = o.name;
create trigger quotations_submitted_by_id before insert or update on public.quotations
  for each row execute function public.quotations_submitted_by_id();

/* A colleague, by id, while they work here. */
create or replace function public.quote_sign_member(p_id uuid)
returns uuid
language sql stable security definer set search_path = public as $$
  select m.id from public.team_members m
   where m.id = p_id and m.active and not coalesce(m.system, false) and m.removed_at is null
$$;
revoke all on function public.quote_sign_member(uuid) from public, anon, authenticated;

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
    return c.owner_id is not null and c.owner_id = t.id;
  end if;
  return true;
end $$;
revoke all on function public.quote_sign_member_sees(uuid, uuid) from public, anon, authenticated;

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
         signed = jsonb_build_object('via', 'online') || (s.payload - 'device') || jsonb_build_object('record', jsonb_build_object(
           'at', v_at, 'email', s.email,
           'in_contacts', exists (select 1 from public.client_contacts k
                                   where k.client_id = q.client_id and k.archived_at is null
                                     and lower(btrim(coalesce(k.email, ''))) = lower(btrim(coalesce(s.email, ''))))
                          or lower(btrim(coalesce(q.contact->>'email', ''))) = lower(btrim(coalesce(s.email, ''))),
           'ip', nullif(public.request_ip(), ''), 'country', nullif(public.request_country(), ''),
           'agent', left(coalesce(h ->> 'user-agent', ''), 300),
           -- The device as the signer's browser reported it with the code.
           'device', s.payload->>'device',
           'fingerprint', upper(left(encode(digest(q.ref || q.lines::text || q.totals::text || s.payload::text || v_at::text, 'sha256'), 'hex'), 16)))),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  select * into c from public.clients where id = q.client_id;
  perform public.quote_activity(q, 'quotation.signed',
    q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name'),
    jsonb_build_object('name', s.payload->'signer'->>'name', 'email', s.email));
  -- Who prepared it and the person in charge are told; where neither is
  -- here (a website lead nobody has taken), the team who work leads.
  if public.quote_sign_member(q.made_by_id) is null and public.quote_sign_member(c.owner_id) is null then
    perform public.quote_tell(q.client_id, 'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.id::text || ':' || v_at::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by_id), public.quote_sign_member(c.owner_id)],
      'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.client_id, q.id::text || ':' || v_at::text);
  end if;
  return jsonb_build_object('ok', true, 'at', v_at);
end $$;
revoke all on function public.quote_sign_finish(text, text) from public;
grant execute on function public.quote_sign_finish(text, text) to anon, authenticated;

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
    perform public.quote_sign_tell(array[public.quote_sign_member(q.submitted_by_id)], 'quote.returned',
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
  perform public.quote_sign_tell(array_remove(array[public.quote_sign_member(q.submitted_by_id), public.quote_sign_member(c.owner_id)], me.id),
    'quote.reviewed', 'Quotation approved · ' || q.brand, q.ref || ' · by ' || me.name, q.client_id, q.id::text);
  return jsonb_build_object('ok', true, 'billing', v_billing, 'lines', v_lines + v_renewed);
end $$;
revoke all on function public.quotation_review(uuid, boolean, text) from public, anon;
grant execute on function public.quotation_review(uuid, boolean, text) to authenticated;

create or replace function public.quote_decline(p_key text, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  c public.clients;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if char_length(coalesce(v_reason, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id) for update;
  if q.id is null or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if q.declined_at is not null then return jsonb_build_object('ok', true, 'again', true); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unsent'); end if;
  if q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  update public.quotations set status = 'not_proceeding', declined_at = now(), decline_reason = v_reason where id = q.id;
  insert into public.signing_steps (doc_kind, doc_id, step, ip, country)
  values ('quotation', q.id, 'declined', nullif(public.request_ip(), ''), nullif(public.request_country(), ''));
  perform public.quote_activity(q, 'quotation.declined', q.ref || coalesce(' · ' || v_reason, ''), q.contact);
  select * into c from public.clients where id = q.client_id;
  if public.quote_sign_member(q.made_by_id) is null and public.quote_sign_member(c.owner_id) is null then
    perform public.quote_tell(q.client_id, 'quote.declined', 'Quotation declined · ' || q.brand,
      q.ref || coalesce(' · ' || v_reason, ''), q.id::text || ':declined');
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by_id), public.quote_sign_member(c.owner_id)],
      'quote.declined', 'Quotation declined · ' || q.brand, q.ref || coalesce(' · ' || v_reason, ''),
      q.client_id, q.id::text || ':declined');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quote_decline(text, text) from public;
grant execute on function public.quote_decline(text, text) to anon, authenticated;

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
  if public.quote_sign_member(q.made_by_id) is null and public.quote_sign_member(cl.owner_id) is null then
    perform public.quote_tell(q.client_id, 'quote.changes', 'Changes requested · ' || q.brand, v_body,
      q.id::text || ':' || v_now::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by_id), public.quote_sign_member(cl.owner_id)],
      'quote.changes', 'Changes requested · ' || q.brand, v_body, q.client_id, q.id::text || ':' || v_now::text);
  end if;
  return jsonb_build_object('ok', true, 'reply_due', q.reply_due);
end $$;
revoke all on function public.quote_change_request(text, jsonb) from public;
grant execute on function public.quote_change_request(text, jsonb) to anon, authenticated;

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
  v_held boolean;
  v_ds   text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  -- Any quotation with a link: a website quotation, or a team's once
  -- `quotation_link` made one (QUOTATION SIGNING).
  select * into w from public.quotations x
   where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  -- Details asked of the prospect (QUOTE DETAILS ASKED, 2026-11-27).
  v_ds := public.quote_details_state(q);
  -- A website quotation the team has not sent holds back its price at every
  -- stage, Not proceeding included (audit 2026-10-30).
  v_unsent := q.source = 'website' and q.released_at is null;
  select * into c from public.clients x where x.id = w.client_id;
  -- The representative a quotation names: the client's Sales by alone, never
  -- a stand-in (CLIENT REPRESENTATIVE, 2026-11-27).
  select * into m from public.team_members x where x.id = public.client_rep(c.id, 'sales');
  -- Prepared by: the colleague who made the revision shown; a website
  -- quotation's, the person in charge.
  select * into pm from public.team_members x where x.id = public.quote_sign_member(q.made_by_id);
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
  -- A website quotation that found a client the team already serves
  -- (WEBSITE QUOTATION FINDS ITS CLIENT, 2026-11-25) says nothing of that
  -- client while the team has not sent it: no representative, no
  -- preparer, the market read from the number typed.
  v_held := v_unsent and not v_own and coalesce(c.stage, '') not in ('lead', 'contacted', 'proposal');
  if v_held then m := null; pm := null; end if;
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
  elsif q.source = 'website' and q.released_at is null and v_ds = 'closed' then
    -- Not answered past the close days: closed as Not quoted, worked out.
    v_stage := 'closed';
  elsif q.source = 'website' and q.released_at is null and v_ds in ('asked', 'late') then
    -- The team asked for details: the link opens the fields asked alone.
    v_stage := 'details';
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
    'details_at', case when v_stage = 'review' then q.details_at end,
    'ask', case when v_stage = 'details' then jsonb_build_object(
      'fields', q.details_ask->'fields', 'note', q.details_ask->>'note', 'due', q.details_due,
      'known', public.quote_details_known(q.contact, array(select jsonb_array_elements_text(q.details_ask->'fields')))) end,
    'selection', w.selection, 'attention', coalesce(w.contact->>'name', pc.name),
    'stage', v_stage,
    'status', case when d.id is not null then 'offer' else q.status end,
    'details_key', case when v_stage = 'billing' then f.access_key end,
    'portal', v_portal,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when v_held then case when w.contact->>'whatsapp' like '+65%' then 'SG' else 'MY' end
                   when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today,
    -- A Singapore client billed in RM: the S$ rate on its day of issue, so
    -- each total reads its S$ beside it (AD SPEND FIGURES, 2026-11-27).
    'fx_sgd', case when not v_unsent and not v_held and c.market = 'SG' and coalesce(q.totals->>'currency', '') <> 'SGD'
                   then nullif(public.app_setting('fx_sgd', (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date), 0) end,
    'signed', case when q.signed_at is not null then jsonb_build_object('at', q.signed_at, 'via', q.signed->>'via',
                'signer', q.signed->'signer', 'signature', q.signed->'signature', 'company', q.signed->'company',
                'contact', q.signed->'contact', 'record', case when q.signed->>'via' = 'online' then q.signed->'record' end) end,
    'prepared', case when pm.id is not null then jsonb_build_object('name', pm.name, 'title', nullif(btrim(coalesce(pm.designation, '')), ''))
                     when not v_held and nullif(btrim(coalesce(q.made_by, '')), '') is not null then jsonb_build_object('name', q.made_by, 'title', null) end,
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

create or replace function public.client_rep(p_client uuid, p_purpose text)
returns uuid
language sql stable security definer set search_path = public as $$
  select m.id from public.clients c
    join public.team_members m on m.id = case p_purpose
      when 'sales' then c.sales_by
      when 'service' then c.owner_id end
   where c.id = p_client and m.active and not coalesce(m.system, false) and m.removed_at is null
$$;
revoke all on function public.client_rep(uuid, text) from public, anon, authenticated;

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
  v_ref  text;
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
   where f.id = v_f.id
  returning f.request_ref into v_ref;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Details form', 'client.edited', v_cl.name,
          'Billing details received on the details form from ' || coalesce(v_sal || ' ', '') || v_cn || coalesce(' · ' || v_ref, ''));
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
                   or v_cl.owner_id = m.id
                   or v_cl.sales_by = m.id)))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true, 'request_ref', v_ref);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.sm_reports_published_notice()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  c public.clients;
  v_to uuid;
  v_by text;
begin
  if new.status is distinct from 'published' or old.status is not distinct from 'published' then return null; end if;
  select * into c from public.clients x where x.id = new.client_id;
  if c.id is null or c.owner_id is null then return null; end if;
  select t.id into v_to from public.team_members t
   where t.id = c.owner_id and t.active and t.removed_at is null;
  if v_to is null then return null; end if;
  v_by := (public.ops_me()).name;
  perform public.sm_report_notify(v_to, new.id, 'report.published', 'Report published',
    coalesce(nullif(btrim(new.brand_name), ''), c.name) || ' · ' || public.sm_period_word(new.period_start, new.period_end) ||
    case when v_by is not null then ' · Published by ' || v_by else '' end);
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_published_notice() from public, anon, authenticated;

create or replace function public.feedback_request(p_client uuid, p_kind text, p_again boolean default false,
  p_channel text default 'email')
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_cl   public.clients;
  v_ct   public.client_contacts;
  v_mgr  public.team_members;
  v_key  text;
  v_req  public.feedback_requests;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_kind is null or p_kind not in ('quick', 'review') then return jsonb_build_object('error', 'bad-kind'); end if;
  if p_channel is null or p_channel not in ('email', 'whatsapp') then return jsonb_build_object('error', 'bad-channel'); end if;
  select * into v_cl from public.clients c where c.id = p_client;
  if v_cl.id is null or not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_cl.stage in ('lead', 'contacted', 'proposal') then return jsonb_build_object('error', 'not-active'); end if;
  -- An email needs the primary contact's address; a copy for WhatsApp
  -- needs the contact alone (their name and language).
  select * into v_ct from public.client_contacts k
   where k.client_id = p_client and k.is_primary and k.archived_at is null
     and (p_channel = 'whatsapp' or nullif(btrim(coalesce(k.email, '')), '') is not null)
   limit 1;
  if v_ct.id is null then
    return jsonb_build_object('error', case when p_channel = 'whatsapp' then 'no-primary' else 'no-contact' end);
  end if;
  perform pg_advisory_xact_lock(hashtext('feedback_request:' || p_client::text || ':' || p_kind));
  -- None while one is still going out, and none again within the repeat
  -- hours unless asked again, whichever way either went.
  if exists (select 1 from public.feedback_requests r where r.client_id = p_client and r.kind = p_kind
              and r.mail_status = 'sending' and r.created_at > now() - interval '10 minutes') then
    return jsonb_build_object('error', 'sending');
  end if;
  select * into v_req from public.feedback_requests r
   where r.client_id = p_client and r.kind = p_kind and coalesce(r.mail_status, 'sent') not in ('failed', 'sending')
     and r.closed_reason is distinct from 'withdrawn'
     and r.created_at > now() - make_interval(hours => coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24)::int)
   order by r.created_at desc limit 1;
  if v_req.id is not null and not coalesce(p_again, false) then
    return jsonb_build_object('error', 'recent', 'recent',
      jsonb_build_object('at', v_req.created_at, 'by', v_req.sent_by_name, 'to', v_req.sent_to_name,
        'channel', v_req.channel));
  end if;
  v_req := null;
  select * into v_mgr from public.team_members m
   where m.id = v_cl.owner_id and m.active and m.removed_at is null;
  update public.feedback_requests r set closed_at = now(), closed_reason = 'replaced'
   where r.client_id = p_client and r.kind = p_kind and r.closed_at is null;
  loop
    v_key := public.new_link_key() || public.new_link_key();
    exit when not exists (select 1 from public.feedback_requests r where r.access_key = v_key);
  end loop;
  insert into public.feedback_requests (client_id, kind, access_key, sent_by, sent_by_name, contact_id,
    sent_to_name, sent_to_email, manager_id, manager_name, channel)
  values (p_client, p_kind, v_key, me.id, me.name, v_ct.id, v_ct.name, nullif(lower(btrim(coalesce(v_ct.email, ''))), ''),
    v_mgr.id, coalesce(v_mgr.name, nullif(btrim(coalesce(v_cl.owner, '')), '')), p_channel)
  returning * into v_req;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', v_cl.name,
          (case p_kind when 'quick' then 'Service rating' else 'Performance review' end)
          || ' requested from ' || v_ct.name
          || case when p_channel = 'whatsapp' then ', copied for WhatsApp' else '' end);
  return jsonb_build_object('ok', true, 'id', v_req.id, 'key', v_req.access_key, 'kind', v_req.kind,
    'to_name', v_req.sent_to_name, 'to_email', v_req.sent_to_email, 'lang', coalesce(v_ct.lang, 'en'),
    'manager', v_req.manager_name, 'created_at', v_req.created_at, 'channel', v_req.channel);
end $$;
revoke all on function public.feedback_request(uuid, text, boolean, text) from public, anon;
grant execute on function public.feedback_request(uuid, text, boolean, text) to authenticated;

/* Last, once no function calls it: the name lookup goes. */
drop function if exists public.quote_sign_member(text);

-- END OF COLLEAGUES BY ID -----------------------------------------------------

select public.functions_tidy();
