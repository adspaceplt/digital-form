-- ===========================================================================
-- TEMPLATE FIELDS CHECKED — a template is saved only with the fields its
-- sender fills (2026-11-10)
-- ===========================================================================
-- WHY (the Settings review of 2026-11-10, finding 1): a template's {field}
-- was checked only by the Meeting message's own sheet. The creator emails go
-- out by themselves, so a mistyped {creator nmae} saved in Settings reached
-- every creator as typed, and no colleague read it first.
--
-- WHAT IT CHANGES
--   * `template_fields(p_kind)`: the one list of the fields each template
--     takes, by the sender that fills it: supplier, client (a quotation, a
--     Letter of Offer, a client letter), free (Email templates), invoice
--     (the overdue reminder and the invoice email), creator-details
--     (Details received, to review, approved), creator-booking (Payment
--     request, Post recorded, Payment sent), meeting.
--   * `template_check(p_text, p_kind)`: null where every {field} is on the
--     list (named in any case and spacing), else the refusal
--     `unknown-field` with `field` as typed and `fields`, the list.
--   * `template_fields_all()`: the lists for the team's editors.
--   * The seven saves ask it after their own checks: supplier, client,
--     free, both invoice emails, the creator emails (with `purpose`) and
--     the meeting message. Every refusal they held is kept.
--
-- Every live template held only its own fields on 2026-11-10 (read before
-- this file), so nothing saved is refused by it.
--
-- ORDER: this file (connector), then the pages, which name the refusal. A
-- page served before reads `unknown-field` as its own words or the code.
-- Safe to run twice.
--
-- ROLLBACK: restate the seven saves from their earlier sections, then drop
-- template_fields_all(), template_check(text, text) and
-- template_fields(text).
-- ===========================================================================

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
      'review link']
    when 'creator-booking' then array['creator name', 'creator id', 'job reference', 'campaign', 'posted date', 'pay by',
      'payee', 'method', 'account ending', 'amount', 'bill number', 'review link']
    when 'meeting' then array['meeting', 'date', 'time', 'month', 'channel', 'link']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

create or replace function public.template_check(p_text text, p_kind text) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('error', 'unknown-field', 'field', '{' || m[1] || '}',
           'fields', to_jsonb(public.template_fields(p_kind)))
    from regexp_matches(coalesce(p_text, ''), '\{\s*([^{}]*?)\s*\}', 'g') as m
   where lower(regexp_replace(m[1], '\s+', ' ', 'g')) <> all (coalesce(public.template_fields(p_kind), '{}'::text[]))
   limit 1 $$;
revoke all on function public.template_check(text, text) from public, anon, authenticated;

create or replace function public.template_fields_all() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_team() then jsonb_build_object(
    'supplier', to_jsonb(public.template_fields('supplier')),
    'client', to_jsonb(public.template_fields('client')),
    'free', to_jsonb(public.template_fields('free')),
    'invoice', to_jsonb(public.template_fields('invoice')),
    'creator-details', to_jsonb(public.template_fields('creator-details')),
    'creator-booking', to_jsonb(public.template_fields('creator-booking')),
    'meeting', to_jsonb(public.template_fields('meeting'))) end $$;
revoke all on function public.template_fields_all() from public, anon;
grant execute on function public.template_fields_all() to authenticated;

create or replace function public.supplier_email_template_save(p_purpose text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.supplier_email_templates;
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
  v_bad jsonb;
begin
  if me.id is null or not public.allowed('suppliers', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.supplier_email_templates x where x.purpose = p_purpose for update;
  if t.purpose is null then return jsonb_build_object('error', 'bad-purpose'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b, 'supplier');
  if v_bad is not null then return v_bad; end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Body'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.supplier_email_templates x set subject = v_s, body = v_b, updated_at = now(), updated_by = me.id
   where x.purpose = p_purpose;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', 'Supplier emails',
          case p_purpose when 'approved' then 'Supplier approved' else 'Document' end || ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.client_email_template_save(p_kind text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.client_email_templates;
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
  v_bad jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.client_email_templates x where x.kind = p_kind for update;
  if t.kind is null then return jsonb_build_object('error', 'bad-kind'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b, 'client');
  if v_bad is not null then return v_bad; end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.client_email_templates x set subject = v_s, body = v_b, updated_at = now(), updated_by = me.id
   where x.kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Client emails',
          case p_kind when 'quotation' then 'Quotation' when 'offer' then 'Letter of Offer' else 'Client letter' end ||
          ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.email_template_save(p_id uuid, p_audience text, p_name text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  t     public.email_templates;
  v_n   text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_s   text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b   text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
  v_bad jsonb;
  v_id  uuid;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_n) < 2 or length(v_n) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b, 'free');
  if v_bad is not null then return v_bad; end if;
  if p_id is null then
    if p_audience is null or p_audience not in ('client', 'supplier') then return jsonb_build_object('error', 'bad-request'); end if;
    if exists (select 1 from public.email_templates x where x.audience = p_audience and lower(x.name) = lower(v_n)) then
      return jsonb_build_object('error', 'taken');
    end if;
    insert into public.email_templates (audience, name, subject, body, updated_by) values (p_audience, v_n, v_s, v_b, me.id)
    returning id into v_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Email templates', 'Added: ' || v_n || ' (' || case p_audience when 'client' then 'Clients' else 'Suppliers' end || ')');
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;
  select * into t from public.email_templates x where x.id = p_id for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if exists (select 1 from public.email_templates x where x.audience = t.audience and lower(x.name) = lower(v_n) and x.id <> t.id) then
    return jsonb_build_object('error', 'taken');
  end if;
  if t.name is distinct from v_n then moved := moved || ('Name: ' || t.name || ' → ' || v_n); end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true, 'id', t.id); end if;
  update public.email_templates x set name = v_n, subject = v_s, body = v_b, updated_at = now(), updated_by = me.id where x.id = t.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates', t.name || ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true, 'id', t.id);
end $$;

create or replace function public.invoice_email_template_save(p_subject_one text, p_subject_many text, p_body text,
  p_legal text, p_disclaimer text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.invoice_email_template;
  v_1 text := btrim(regexp_replace(coalesce(p_subject_one, ''), '\s+', ' ', 'g'));
  v_n text := btrim(regexp_replace(coalesce(p_subject_many, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_l text := btrim(regexp_replace(coalesce(p_legal, ''), '\s+', ' ', 'g'));
  v_d text := btrim(regexp_replace(coalesce(p_disclaimer, ''), '\s+', ' ', 'g'));
  moved text[] := '{}';
  v_bad jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_1) < 2 or length(v_1) > 200 or length(v_n) < 2 or length(v_n) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  if length(v_l) > 1000 or length(v_d) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  v_bad := public.template_check(concat_ws(E'\n', v_1, v_n, v_b, v_l, v_d), 'invoice');
  if v_bad is not null then return v_bad; end if;
  select * into t from public.invoice_email_template x where x.id = 1 for update;
  if t.subject_one is distinct from v_1 then moved := moved || ('Subject, one invoice: ' || t.subject_one || ' → ' || v_1); end if;
  if t.subject_many is distinct from v_n then moved := moved || ('Subject, several invoices: ' || t.subject_many || ' → ' || v_n); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if t.legal is distinct from v_l then moved := moved || 'Legal note'::text; end if;
  if t.disclaimer is distinct from v_d then moved := moved || 'Disclaimer'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.invoice_email_template x set subject_one = v_1, subject_many = v_n, body = v_b, legal = v_l,
    disclaimer = v_d, updated_at = now(), updated_by = me.id where x.id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Overdue reminder', array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.invoice_send_template_save(p_subject_one text, p_subject_many text, p_body text,
  p_legal text, p_disclaimer text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.invoice_send_template;
  v_1 text := btrim(regexp_replace(coalesce(p_subject_one, ''), '\s+', ' ', 'g'));
  v_n text := btrim(regexp_replace(coalesce(p_subject_many, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_l text := btrim(regexp_replace(coalesce(p_legal, ''), '\s+', ' ', 'g'));
  v_d text := btrim(regexp_replace(coalesce(p_disclaimer, ''), '\s+', ' ', 'g'));
  moved text[] := '{}';
  v_bad jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_1) < 2 or length(v_1) > 200 or length(v_n) < 2 or length(v_n) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  if length(v_l) > 1000 or length(v_d) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  v_bad := public.template_check(concat_ws(E'\n', v_1, v_n, v_b, v_l, v_d), 'invoice');
  if v_bad is not null then return v_bad; end if;
  select * into t from public.invoice_send_template x where x.id = 1 for update;
  if t.subject_one is distinct from v_1 then moved := moved || ('Subject, one invoice: ' || t.subject_one || ' → ' || v_1); end if;
  if t.subject_many is distinct from v_n then moved := moved || ('Subject, several invoices: ' || t.subject_many || ' → ' || v_n); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if t.legal is distinct from v_l then moved := moved || 'Legal note'::text; end if;
  if t.disclaimer is distinct from v_d then moved := moved || 'Disclaimer'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.invoice_send_template x set subject_one = v_1, subject_many = v_n, body = v_b, legal = v_l,
    disclaimer = v_d, updated_at = now(), updated_by = me.id where x.id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Invoice email', array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;

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
        when 'approved' then 'Details approved' when 'request' then 'Payment request' when 'posted' then 'Post recorded'
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

create or replace function public.meeting_message_save(p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.meeting_message_template;
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_bad jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_b) < 2 or length(v_b) > 3000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*date\s*\}' then return jsonb_build_object('error', 'no-date'); end if;
  v_bad := public.template_check(v_b, 'meeting');
  if v_bad is not null then return v_bad; end if;
  select * into t from public.meeting_message_template x where x.id = 1 for update;
  if t.body is not distinct from v_b then return jsonb_build_object('ok', true); end if;
  update public.meeting_message_template x set body = v_b, updated_at = now(), updated_by = me.id where x.id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Meeting message', 'Message');
  return jsonb_build_object('ok', true);
end $$;

-- END OF TEMPLATE FIELDS CHECKED --------------------------------------------

select public.functions_tidy();
