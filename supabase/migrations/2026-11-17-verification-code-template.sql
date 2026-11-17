-- ===========================================================================
-- VERIFICATION CODE TEMPLATE (2026-11-17)
-- ===========================================================================
-- WHY: the user, 2026-11-17 (digital-form-tests specs/SEAL-SPEC.md, decision
-- 9): every email the portal sends appears in Email templates. The code a
-- signer is emailed was written into quote-request; it becomes one editable
-- template, Verification code, in a new group Sign-in and codes, used by
-- every code the portal sends (quotation signing now, the Employment
-- Contract later), the Supabase sign-in emails listed beside it.
--
-- WHAT IT CHANGES
--   * `code_email_template` (one row; RLS on, no policy, no grant): the
--     subject, the message and the fine print, seeded once with the words
--     quote-request sent.
--   * `template_fields('code')`: name, code, minutes, purpose (`{purpose}`
--     reads "to sign quotation ADP/QT2611-L01"); the other kinds as they
--     were. `template_fields_all()` answers it too.
--   * `code_email_template_get()` and `code_email_template_save(p_subject,
--     p_body, p_foot)` (Business settings, `team.settings`): the message
--     keeps {code} (`no-code`), the subject never holds it
--     (`code-in-subject`: a phone shows the subject on its lock screen),
--     every field one the sender fills (`unknown-field`); filed
--     `team.changed` under Email templates.
--   * `code_email_template_read()` (the service role's): what quote-request
--     sends.
--
-- ORDER: this file (connector), then quote-request, then the pages. Until
-- quote-request is deployed the code goes out in its own words, as before.
-- Safe to run twice.
--
-- ROLLBACK: quote-request and the pages from before. The table and
-- functions may stay; restate TEMPLATE FIELDS CHECKED's template_fields and
-- template_fields_all to take 'code' out.
-- ===========================================================================


-- VERIFICATION CODE TEMPLATE — the one editable email for every code the portal sends.

create table if not exists public.code_email_template (
  id         integer primary key default 1 check (id = 1),
  subject    text not null,
  body       text not null,
  foot       text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.code_email_template enable row level security;
revoke all on table public.code_email_template from public, anon, authenticated;
insert into public.code_email_template (id, subject, body, foot)
select 1, 'Your ADspace verification code {purpose}',
  E'Dear {name},\n\nPlease enter the following code {purpose}:\n\n{code}\n\nThe code expires in {minutes} minutes.\n\nYours sincerely,\nADspace',
  'The code may be used once. If you did not request it, please disregard this email; nothing is signed without the code.'
where not exists (select 1 from public.code_email_template);

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
    when 'code' then array['name', 'code', 'minutes', 'purpose']
  end $$;
revoke all on function public.template_fields(text) from public, anon, authenticated;

create or replace function public.template_fields_all() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_team() then jsonb_build_object(
    'supplier', to_jsonb(public.template_fields('supplier')),
    'client', to_jsonb(public.template_fields('client')),
    'free', to_jsonb(public.template_fields('free')),
    'invoice', to_jsonb(public.template_fields('invoice')),
    'creator-details', to_jsonb(public.template_fields('creator-details')),
    'creator-booking', to_jsonb(public.template_fields('creator-booking')),
    'meeting', to_jsonb(public.template_fields('meeting')),
    'code', to_jsonb(public.template_fields('code'))) end $$;
revoke all on function public.template_fields_all() from public, anon;
grant execute on function public.template_fields_all() to authenticated;

create or replace function public.code_email_template_get()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t public.code_email_template;
begin
  if public.ops_me() is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.code_email_template where id = 1;
  return jsonb_build_object('subject', t.subject, 'body', t.body, 'foot', t.foot);
end $$;
revoke all on function public.code_email_template_get() from public, anon;
grant execute on function public.code_email_template_get() to authenticated;

create or replace function public.code_email_template_save(p_subject text, p_body text, p_foot text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.code_email_template;
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_f text := btrim(replace(coalesce(p_foot, ''), E'\r', ''));
  moved text[] := '{}';
  v_bad jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if length(v_f) > 1000 then return jsonb_build_object('error', 'foot-long'); end if;
  if v_s ~* '\{\s*code\s*\}' then return jsonb_build_object('error', 'code-in-subject'); end if;
  if v_b !~* '\{\s*code\s*\}' then return jsonb_build_object('error', 'no-code'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b || E'\n' || v_f, 'code');
  if v_bad is not null then return v_bad; end if;
  select * into t from public.code_email_template where id = 1 for update;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if t.foot is distinct from v_f then moved := moved || 'Fine print'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.code_email_template set subject = v_s, body = v_b, foot = v_f, updated_at = now(), updated_by = me.id where id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates', 'Verification code · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.code_email_template_save(text, text, text) from public, anon;
grant execute on function public.code_email_template_save(text, text, text) to authenticated;

-- What quote-request sends (the service role's alone).
create or replace function public.code_email_template_read()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('subject', t.subject, 'body', t.body, 'foot', t.foot) from public.code_email_template t where t.id = 1 $$;
revoke all on function public.code_email_template_read() from public, anon, authenticated;
grant execute on function public.code_email_template_read() to service_role;

-- END OF VERIFICATION CODE TEMPLATE -------------------------------------------

select public.functions_tidy();
