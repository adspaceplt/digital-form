-- ===========================================================================
-- CREATOR DETAILS CHANGED (2026-11-24)
-- ===========================================================================
-- WHY: the code review of 2026-11-24 (release A1). A creator's payment
-- details changed on the creator page were told only to the new email: a
-- change somebody else made with the creator's code went unseen.
--
-- WHAT CHANGED
--   * `creator_pay_requests.changes` (the words) and `prior_id` (the set on
--     file it was compared with): `creator_pay_changes(was, now)` names a
--     changed bank account (Bank account changed: ending 1234 → 5678), a
--     changed account holder, and changed contact details (email or
--     WhatsApp).
--   * `creator_pay_submit` writes them and, where details were on file and
--     something changed, queues Details changed to the email on file
--     (`creator_mail_queue('changed')`) and the WhatsApp template
--     `creator_changed` to the WhatsApp on file (`wa_enqueue`, held by
--     Automatic WhatsApp as a creator message is, sent once its template
--     is chosen in Settings).
--   * `creator_pay_json` answers `changes`; the review email fills
--     {changes} (an edited template is left alone); Details changed fills
--     {date} and {chinese date}; `template_fields('creator-details')` takes
--     the three; the Settings lists order and name Details changed.
--
-- ORDER: this file (connector), then CREATOR DETAILS CHANGED, THE SQL
-- EDITOR PART (it widens the purpose checks and seeds the template and the
-- WhatsApp row; until it runs nothing is queued, since `creator_mail_queue`
-- finds no template and `wa_enqueue` no row), then the pages. Safe to run
-- twice.
-- ROLLBACK: restate `creator_pay_submit`, `creator_mail_queue`,
-- `wa_enqueue`, `creator_pay_json`, `creator_email_templates_get`,
-- `creator_email_templates_save` and `template_fields` from their last
-- definitions before this banner; drop `creator_pay_changes`; the columns
-- may stay.
-- ===========================================================================

alter table public.creator_pay_requests add column if not exists changes text[] not null default '{}';
alter table public.creator_pay_requests add column if not exists prior_id uuid;

/* What moved between the details on file and the ones sent: the words the
   review and the email read. */
create or replace function public.creator_pay_changes(p_was public.creator_pay_requests, p_now public.creator_pay_requests)
returns text[] language sql immutable set search_path = public as $$
  select case when p_was.id is null or p_now.id is null then '{}'::text[] else array_remove(array[
    case when (p_was.method, coalesce(p_was.bank, ''), p_was.currency, p_was.account)
              is distinct from (p_now.method, coalesce(p_now.bank, ''), p_now.currency, p_now.account)
         then 'Bank account changed: ending ' || right(p_was.account, 4) || ' → ' || right(p_now.account, 4) end,
    case when btrim(p_was.payee) is distinct from btrim(p_now.payee)
         then 'Account holder changed: ' || p_was.payee || ' → ' || p_now.payee end,
    case when lower(btrim(p_was.email)) is distinct from lower(btrim(p_now.email))
           or regexp_replace(coalesce(p_was.whatsapp, ''), '\D', '', 'g') is distinct from regexp_replace(coalesce(p_now.whatsapp, ''), '\D', '', 'g')
         then 'Contact details changed' end], null) end
$$;
revoke all on function public.creator_pay_changes(public.creator_pay_requests, public.creator_pay_requests) from public, anon, authenticated;

/* A set as the creator's page reads it: the numbers as their last four. */
create or replace function public.creator_pay_json(r public.creator_pay_requests, p_whole boolean)
returns jsonb language sql stable set search_path = public as $$
  select case when r.id is null then null else jsonb_build_object(
    'id', r.id, 'ref', r.ref, 'status', r.status, 'created_at', r.created_at, 'decided_at', r.decided_at,
    'note', r.note, 'bill_kind', r.bill_kind, 'source', r.source,
    'id_no', case when p_whole then r.id_no end, 'id_end', right(regexp_replace(r.id_no, '\W', '', 'g'), 4),
    'legal_name', r.legal_name, 'tin', r.tin, 'address', r.address, 'currency', r.currency,
    'method', r.method, 'method_word', public.creator_pay_method(r.method, r.bank), 'bank', r.bank,
    'account', case when p_whole then r.account end, 'account_end', right(r.account, 4),
    'payee', r.payee, 'email', r.email, 'whatsapp', r.whatsapp, 'changes', to_jsonb(coalesce(r.changes, '{}'))) end
$$;
revoke all on function public.creator_pay_json(public.creator_pay_requests, boolean) from public, anon, authenticated;

-- The review email names what changed (an edited template is left alone).
update public.creator_email_templates
   set body = replace(body, E'Account ending: {account ending}\n', E'Account ending: {account ending}\n\n{changes}\n')
 where purpose = 'review' and updated_by is null and body not like '%{changes}%';

create or replace function public.creator_pay_submit(p_code text, p_values jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     public.creators;
  v_held public.creator_pay_requests;
  v_in   jsonb := coalesce(p_values, '{}'::jsonb);
  v_chk  jsonb;
  v      jsonb;
  v_seq  int;
  v_new  public.creator_pay_requests;
  v_was  public.creator_pay_requests;
  v_chg  text[];
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators x where x.id = v_id for update;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;
  if not public.creator_pay_due(cr.id) then return jsonb_build_object('error', 'not-due'); end if;
  if (select count(*) from public.creator_pay_requests x where x.creator_id = cr.id
       and x.created_at > now() - interval '1 day') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  -- A number left blank keeps the one held, where nothing it belongs to moved;
  -- a detail the page shows masked, left blank, keeps the one held.
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
    if btrim(coalesce(v_in->>'legal_name', '')) = '' then v_in := v_in || jsonb_build_object('legal_name', v_held.legal_name); end if;
    if btrim(coalesce(v_in->>'tin', '')) = '' and v_held.tin is not null then v_in := v_in || jsonb_build_object('tin', v_held.tin); end if;
    if btrim(coalesce(v_in->>'address', '')) = '' then v_in := v_in || jsonb_build_object('address', v_held.address); end if;
    if btrim(coalesce(v_in->>'payee', '')) = '' then v_in := v_in || jsonb_build_object('payee', v_held.payee); end if;
    if btrim(coalesce(v_in->>'email', '')) = '' then v_in := v_in || jsonb_build_object('email', v_held.email); end if;
    if btrim(coalesce(v_in->>'whatsapp', '')) = '' then v_in := v_in || jsonb_build_object('whatsapp', v_held.whatsapp); end if;
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
    method, bank, account, payee, email, whatsapp)
  values (cr.id, v_seq, public.creator_pay_ref(cr.creator_code, v_seq), v->>'bill_kind', v->>'id_no', v->>'legal_name',
    v->>'tin', v->>'address', v->>'currency', v->>'method', v->>'bank', v->>'account', v->>'payee', v->>'email', v->>'whatsapp')
  returning * into v_new;
  v_chg := public.creator_pay_changes(v_was, v_new);
  update public.creator_pay_requests x set changes = v_chg, prior_id = v_was.id where x.id = v_new.id
  returning * into v_new;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Creator page', 'creator.updated', cr.name,
          coalesce(cr.creator_code || ' · ', '') || 'Payment details submitted · ' || v_new.ref || ' · ' ||
          public.creator_pay_method(v_new.method, v_new.bank) || ' ending ' || right(v_new.account, 4) ||
          coalesce(' · ' || nullif(array_to_string(v_chg, ' · '), ''), ''));
  perform public.creator_mail_queue('received', v_new.id);
  perform public.creator_mail_queue('review', v_new.id);
  -- Details on file changed: the email and WhatsApp on file are told too,
  -- so a change the creator did not make is seen (review 2026-11-24).
  if v_was.id is not null and cardinality(v_chg) > 0 then
    perform public.creator_mail_queue('changed', v_new.id);
    perform public.wa_enqueue('creator_changed', public.wa_number(coalesce(nullif(v_was.whatsapp, ''), cr.whatsapp), 'MY'), cr.name,
      jsonb_build_array(cr.name, public.register_day((v_new.created_at at time zone 'Asia/Kuala_Lumpur')::date)),
      'creator_pay', v_new.id, null, null);
  end if;
  return jsonb_build_object('ok', true, 'ref', v_new.ref);
end $$;
grant execute on function public.creator_pay_submit(text, jsonb) to anon, authenticated;

create or replace function public.creator_mail_queue(p_purpose text, p_req uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t   public.creator_email_templates;
  r   public.creator_pay_requests;
  c   public.creators;
  v_to text;
  v_sub text;
  v_body text;
  v_vals jsonb;
  w   public.creator_pay_requests;
  v_day date;
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into r from public.creator_pay_requests x where x.id = p_req;
  select * into c from public.creators x where x.id = r.creator_id;
  -- Details changed goes to the email on file, the set it replaced.
  select * into w from public.creator_pay_requests x where x.id = r.prior_id;
  v_to := lower(btrim(coalesce(case when p_purpose = 'review' then t.to_email
                                    when p_purpose = 'changed' then w.email else r.email end, '')));
  v_day := (r.created_at at time zone 'Asia/Kuala_Lumpur')::date;
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  v_vals := jsonb_build_object(
    'creator name', c.name, 'creator id', coalesce(c.creator_code, ''), 'reference', r.ref, 'payee', r.payee,
    'method', public.creator_pay_method(r.method, r.bank), 'account ending', right(r.account, 4),
    'review link', 'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id,
    'date', public.register_day(v_day),
    'chinese date', to_char(v_day, 'YYYY') || '年' || to_char(v_day, 'FMMM') || '月' || to_char(v_day, 'FMDD') || '日',
    'changes', array_to_string(coalesce(r.changes, '{}'), E'\n'));
  v_sub := public.creator_mail_fill(v_sub, v_vals);
  -- A field filled empty (no changes) leaves no blank lines behind it.
  v_body := regexp_replace(public.creator_mail_fill(v_body, v_vals), E'\n{3,}', E'\n\n', 'g');
  -- Off, the email is kept as Not sent and never sent later (2026-11-10).
  insert into public.creator_emails (purpose, creator_id, request_id, to_email, subject, body, status, error)
  values (p_purpose, c.id, r.id, v_to, left(v_sub, 200), v_body,
          case when public.auto_send_on('email') then 'queued' else 'failed' end,
          case when public.auto_send_on('email') then null else 'off: Automatic emails are off.' end);
  perform public.creator_mail_kick();
end $$;
revoke all on function public.creator_mail_queue(text, uuid) from public, anon, authenticated;

create or replace function public.wa_enqueue(p_purpose text, p_number text, p_name text, p_params jsonb,
                                             p_ref_kind text, p_ref_id uuid, p_client uuid, p_button text)
returns void
language plpgsql security definer set search_path = public as $$
declare t public.wa_templates;
begin
  select * into t from public.wa_templates x where x.purpose = p_purpose and x.active and x.name <> '';
  if t.purpose is null or p_number is null then return; end if;
  -- What the portal sends by itself waits on its switch (2026-11-10).
  if p_purpose in ('reminder', 'creator', 'creator_changed') and not public.auto_send_on('whatsapp') then return; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, created_by, button,
                                to_kind, to_id, category)
  values (p_purpose, p_number, p_name, t.name, t.lang,
          coalesce((select jsonb_agg(e.value) from (select value from jsonb_array_elements(coalesce(p_params, '[]'::jsonb)) with ordinality e(value, n)
                     where n <= t.params order by n) e), '[]'::jsonb),
          p_ref_kind, p_ref_id, p_client, 'system', nullif(btrim(coalesce(p_button, '')), ''),
          case p_purpose when 'reminder' then 'colleague' when 'creator' then 'creator' when 'creator_changed' then 'creator' else 'contact' end,
          case when p_purpose = 'reminder' then (select n.team_member_id from public.ops_notifications n where n.id = p_ref_id)
               when p_purpose = 'creator' then (select o.creator_id from public.campaign_options o where o.id = p_ref_id)
               when p_purpose = 'creator_changed' then (select r.creator_id from public.creator_pay_requests r where r.id = p_ref_id) end,
          nullif(t.category, ''));
  perform public.wa_kick();
end $$;

revoke all on function public.wa_enqueue(text, text, text, jsonb, text, uuid, uuid, text) from public, anon, authenticated;

create or replace function public.creator_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'purpose', t.purpose, 'on', t.on_send, 'subject', t.subject, 'body', t.body, 'to_email', t.to_email,
      'updated_at', t.updated_at, 'updated_by', m.name)
      order by array_position(array['received', 'review', 'approved', 'changed', 'request', 'posted', 'paid'], t.purpose))
      from public.creator_email_templates t left join public.team_members m on m.id = t.updated_by), '[]'::jsonb)) end
$$;
revoke all on function public.creator_email_templates_get() from public, anon;
grant execute on function public.creator_email_templates_get() to authenticated;

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

create or replace function public.template_fields(p_kind text) returns text[]
language sql immutable set search_path = public as $$
  select case p_kind
    when 'supplier' then array['contact name', 'supplier name', 'supplier id', 'payment term', 'currency',
      'document title', 'document reference', 'document date', 'sender name']
    when 'client' then array['contact name', 'client name', 'company name', 'document title', 'document reference',
      'document date', 'valid until', 'sender name']
    when 'free' then array['contact name', 'company name', 'client name', 'supplier name', 'sender name']
    when 'invoice' then array['contact name', 'client', 'invoice no', 'count', 'total', 'sign off', 'invoices']
    when 'creator-details' then array['creator name', 'creator id', 'reference', 'payee', 'method', 'account ending',
      'review link', 'date', 'chinese date', 'changes']
    when 'creator-booking' then array['creator name', 'creator id', 'job reference', 'campaign', 'posted date', 'pay by',
      'payee', 'method', 'account ending', 'amount', 'bill number', 'review link']
    when 'meeting' then array['meeting', 'date', 'time', 'month', 'channel', 'link']
    when 'code' then array['name', 'code', 'minutes', 'purpose']
    when 'candidate' then array['candidate name', 'position', 'interview length', 'where', 'times', 'reply by', 'note',
      'time', 'previous time', 'new time', 'place', 'google meet notice', 'decision date', 'months', 'document', 'reference',
      'requested action', 'purpose', 'reason', 'document date', 'contact', 'sign-off', 'button']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

-- END OF CREATOR DETAILS CHANGED -------------------------------------------

select public.functions_tidy();
