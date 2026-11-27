-- ===========================================================================
-- QUOTE DETAILS ASKED (2026-11-27)
-- ===========================================================================
-- WHY: the user, 27 Nov 2026 (HANDOVER Queue 12, on the intake mockup): a
-- website request missing what the team needs is followed up, never left:
-- the team asks for the details missing (a sheet: tick what is missing,
-- Send email, Copy for WhatsApp by hand), the prospect's own link opens
-- Complete your details with the fields ticked alone, and a request the
-- team will not quote is Not quoted with its reason (Incomplete details,
-- Not a fit, Duplicate, Spam), with Undo and Reopen. Two states are added
-- (Waiting for details, Details received); the reply window and the days
-- after it before the request closes are settings.
--
-- WHAT CHANGED
--   * `quotations`: `details_ask` (fields, note), `details_asked_at`,
--     `details_asked_by`, `details_due`, `details_at`, `details` (what was
--     sent), `not_quoted` (incomplete, fit, duplicate, spam), `match` and
--     `match_taken` (QUOTE INTAKE writes them).
--   * `client_detail_forms.quotation_id`: a registration held for Use
--     details names its quotation; the link's billing step never reads it.
--   * `client_emails.kind` takes `details`; `client_email_may` and
--     `client_email_done` name it (Details request for {ref}).
--   * Settings, Clients: `quote_details_days` (3 working days) and
--     `quote_details_close_days` (7 days), `app_settings_set` restated.
--   * Settings, Messages: `quote_email_templates` (Details needed, English
--     and 中文), `template_fields('quote')`, `quote_email_templates_get`,
--     `quote_email_template_save` at `team.settings`.
--   * `quote_details_state(q)`: none, asked, late, closed (worked out on
--     read, never written) or received.
--   * `quotation_details_ask(p_id, p_fields, p_note)`,
--     `quote_details_mail_begin(p_id)` (`supplier-mail` `quoteAsk`),
--     `quotation_not_quote(p_id, p_reason)` (null reopens),
--     `quotation_match_take(p_id, p_take)`, at Clients: Quotations Work.
--   * `quote_details_submit(p_key, p_answers)` (anon) and
--     `quote_intake_check(p, fields)`, one check for the request and for
--     details sent later; `quote_details_apply` takes them onto the lead
--     the request made, else holds the registration (`quote_reg_hold`).
--   * `quote_website_read`: stage `details` (the fields asked, the note,
--     the day and what was typed) and `closed` past the close days;
--     `details_at` while the request is reviewed.
--
-- ORDER: this file (connector); 2026-10-07-function-hygiene.sql again
-- (`quote_details_submit` joins `open_to_anon`); the pages; the edge
-- function `supplier-mail`; then 2026-11-27-quote-intake.sql. An old open
-- console tab reads no new column and offers none of the new acts; an old
-- /quote/ tab never reads the `details` stage (the team asks nothing
-- before the pages land). Safe to run twice. Drops only the email kind's
-- check, added back wider.
-- ROLLBACK: restate `quote_website_read` from WEBSITE QUOTATION FINDS ITS
-- CLIENT, `app_settings_set` from its last section, `client_email_may`,
-- `client_email_done`, `template_fields` and `template_fields_all` from
-- their last sections; drop the new functions; the columns, table and
-- settings may stay.
-- ===========================================================================

alter table public.quotations add column if not exists details_ask      jsonb;
alter table public.quotations add column if not exists details_asked_at timestamptz;
alter table public.quotations add column if not exists details_asked_by text;
alter table public.quotations add column if not exists details_due      timestamptz;
alter table public.quotations add column if not exists details_at       timestamptz;
alter table public.quotations add column if not exists details          jsonb;
alter table public.quotations add column if not exists not_quoted       text;
alter table public.quotations add column if not exists match            jsonb;
alter table public.quotations add column if not exists match_taken      text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'quotations_not_quoted_check') then
    alter table public.quotations add constraint quotations_not_quoted_check
      check (not_quoted is null or not_quoted in ('incomplete', 'fit', 'duplicate', 'spam'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quotations_match_taken_check') then
    alter table public.quotations add constraint quotations_match_taken_check
      check (match_taken is null or match_taken in ('brand', 'lead'));
  end if;
end $$;

-- A registration held for Use details names the quotation it came with; the
-- link's own billing step never reads it.
alter table public.client_detail_forms add column if not exists quotation_id uuid references public.quotations(id) on delete set null;

-- The details request emailed is a client email like the quotation's.
alter table public.client_emails drop constraint if exists client_emails_kind_check;
alter table public.client_emails add constraint client_emails_kind_check
  check (kind in ('quotation', 'offer', 'letter', 'details'));

insert into public.app_settings (key, from_date, value)
select 'quote_details_days', date '2023-08-14', 3
 where not exists (select 1 from public.app_settings s where s.key = 'quote_details_days');
insert into public.app_settings (key, from_date, value)
select 'quote_details_close_days', date '2023-08-14', 7
 where not exists (select 1 from public.app_settings s where s.key = 'quote_details_close_days');

create table if not exists public.quote_email_templates (
  kind        text not null check (kind in ('details')),
  lang        text not null check (lang in ('en', 'zh')),
  subject     text not null,
  body        text not null,
  button      text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.team_members(id) on delete set null,
  primary key (kind, lang)
);
alter table public.quote_email_templates enable row level security;
revoke all on table public.quote_email_templates from public, anon, authenticated;

insert into public.quote_email_templates (kind, lang, subject, body, button)
select x.kind, x.lang, x.subject, x.body, x.button from (values
  ('details', 'en', 'Details needed for your quotation {reference}',
   E'Dear {contact name},\n\nThank you for your quotation request for {brand}. To prepare your quotation, ADspace requires the following details:\n\n{details}\n\nPlease provide them by {reply by}.',
   'Provide details'),
  ('details', 'zh', '您的报价 {reference} 需补充资料',
   E'尊敬的{contact name}：\n\n感谢您为{brand}申请报价。为拟定报价，ADspace需要以下资料：\n\n{details}\n\n请于{reply by}前提供。',
   '提供资料')
) as x (kind, lang, subject, body, button)
where not exists (select 1 from public.quote_email_templates);

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
    when 'feedback' then array['contact name', 'client name', 'link']
    when 'quote' then array['contact name', 'brand', 'reference', 'details', 'reply by', 'link']
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
    'code', to_jsonb(public.template_fields('code')),
    'candidate', to_jsonb(public.template_fields('candidate')),
    'feedback', to_jsonb(public.template_fields('feedback')),
    'quote', to_jsonb(public.template_fields('quote'))) end $$;
revoke all on function public.template_fields_all() from public, anon;
grant execute on function public.template_fields_all() to authenticated;

create or replace function public.quote_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.ops_me() is null or not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'lang', t.lang, 'subject', t.subject, 'body', t.body, 'button', t.button,
      'updated_at', t.updated_at, 'updated_by', m.name)
      order by t.kind, array_position(array['en', 'zh'], t.lang))
      from public.quote_email_templates t left join public.team_members m on m.id = t.updated_by), '[]'::jsonb)) end
$$;
revoke all on function public.quote_email_templates_get() from public, anon;
grant execute on function public.quote_email_templates_get() to authenticated;

create or replace function public.quote_email_template_save(p_kind text, p_lang text, p_subject text, p_body text, p_button text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  t     public.quote_email_templates;
  v_s   text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b   text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_btn text := btrim(regexp_replace(coalesce(p_button, ''), '\s+', ' ', 'g'));
  moved text[] := '{}';
  v_bad jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if length(v_btn) < 2 or length(v_btn) > 40 then return jsonb_build_object('error', 'bad-button'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b || E'\n' || v_btn, 'quote');
  if v_bad is not null then return v_bad; end if;
  select * into t from public.quote_email_templates x where x.kind = p_kind and x.lang = p_lang for update;
  if t.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if t.button is distinct from v_btn then moved := moved || ('Button: ' || t.button || ' → ' || v_btn); end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.quote_email_templates x set subject = v_s, body = v_b, button = v_btn, updated_at = now(), updated_by = me.id
   where x.kind = t.kind and x.lang = t.lang;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates',
          'Ask for details (' || case t.lang when 'zh' then '中文' else 'English' end || ') · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quote_email_template_save(text, text, text, text, text) from public, anon;
grant execute on function public.quote_email_template_save(text, text, text, text, text) to authenticated;

-- A day the reader waits on, with its weekday: 20 Nov 2026 (Friday), or
-- 2026年11月20日（星期五）.
create or replace function public.quote_day_word(p_day date, p_zh boolean)
returns text
language sql immutable set search_path = public as $$
  select case when p_day is null then null
    when p_zh then to_char(p_day, 'YYYY') || '年' || to_char(p_day, 'FMMM') || '月' || to_char(p_day, 'FMDD') || '日（星期' ||
      (array['日', '一', '二', '三', '四', '五', '六'])[extract(dow from p_day)::int + 1] || '）'
    else public.register_day(p_day) || ' (' || trim(to_char(p_day, 'FMDay')) || ')' end
$$;
revoke all on function public.quote_day_word(date, boolean) from public, anon, authenticated;

-- A field the team may ask for, in the prospect's words; the note last.
create or replace function public.quote_details_lines(p_fields text[], p_note text, p_zh boolean)
returns text
language sql immutable set search_path = public as $$
  select string_agg('• ' || x.w, E'\n' order by x.o) from (
    select f.o, case f.k
      when 'registration' then case when p_zh then '商业注册号码（BRN）及注册名称' else 'Business Registration No. (BRN) and Registered Name' end
      when 'industry' then case when p_zh then '行业' else 'Industry' end
      when 'online' then case when p_zh then '网站或社交媒体账号' else 'Website or social media account' end
      when 'commence' then case when p_zh then '计划开始时间' else 'Planned commencement' end end as w
      from unnest(p_fields) with ordinality as f (k, o)
    union all
    select 99, btrim(p_note) where nullif(btrim(coalesce(p_note, '')), '') is not null
  ) x where x.w is not null
$$;
revoke all on function public.quote_details_lines(text[], text, boolean) from public, anon, authenticated;

-- Where a website request stands on details: none asked, asked, late (Reply
-- by passed), closed (the close days passed too, worked out, never written)
-- or received. Read on every load, as `quote_website_read` and the console
-- row derive it.
create or replace function public.quote_details_state(p public.quotations)
returns text
language sql stable security definer set search_path = public as $$
  select case
    when p.details_asked_at is null then 'none'
    when p.details_at is not null then 'received'
    when now() > p.details_due + make_interval(days => coalesce(public.app_setting('quote_details_close_days',
           (p.details_due at time zone 'Asia/Kuala_Lumpur')::date), 7)::int) then 'closed'
    when now() > p.details_due then 'late'
    else 'asked' end
$$;
revoke all on function public.quote_details_state(public.quotations) from public, anon, authenticated;

-- What the prospect typed, for the fields asked alone.
create or replace function public.quote_details_known(p_contact jsonb, p_fields text[])
returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kind', case when 'registration' = any(p_fields) then p_contact->>'kind' end,
    'brn', case when 'registration' = any(p_fields) then p_contact->>'brn' end,
    'legal', case when 'registration' = any(p_fields) then p_contact->>'legal' end,
    'industry', case when 'industry' = any(p_fields) then p_contact->>'industry' end,
    'website', case when 'online' = any(p_fields) then p_contact->>'website' end,
    'no_site', case when 'online' = any(p_fields) then p_contact->'no_site' end,
    'platform', case when 'online' = any(p_fields) then p_contact->>'platform' end,
    'handle', case when 'online' = any(p_fields) then p_contact->>'handle' end,
    'commence', case when 'commence' = any(p_fields) then p_contact->>'commence' end,
    'commence_on', case when 'commence' = any(p_fields) then p_contact->>'commence_on' end))
$$;
revoke all on function public.quote_details_known(jsonb, text[]) from public, anon, authenticated;

-- The intake's fields checked, one copy for the request and for details
-- sent later: Registering as with its Business Registration No. (12
-- digits, the year first, the entity code: a company 01, 02 or 04, a sole
-- proprietorship or partnership 03) and registered name; the industry on
-- Settings' list; a website, else No website and a social media account;
-- Planned commencement. Answers what was asked, cleaned, or the refusal.
create or replace function public.quote_intake_check(p jsonb, p_fields text[])
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_kind text := nullif(btrim(coalesce(p->>'kind', '')), '');
  v_brn  text := regexp_replace(coalesce(p->>'brn', ''), '[\s-]+', '', 'g');
  v_code text;
  v_legal text := upper(btrim(regexp_replace(coalesce(p->>'legal', ''), '\s+', ' ', 'g')));
  v_site text := btrim(coalesce(p->>'website', ''));
  v_none boolean := coalesce(p->>'no_site', '') = 'true';
  v_plat text := nullif(btrim(coalesce(p->>'platform', '')), '');
  v_hdl  text := regexp_replace(btrim(coalesce(p->>'handle', '')), '^@+', '');
  v_ind  text := nullif(btrim(coalesce(p->>'industry', '')), '');
  v_start text := nullif(btrim(coalesce(p->>'commence', '')), '');
  v_on_t text := nullif(btrim(coalesce(p->>'commence_on', '')), '');
  v_on   date;
  v_out  jsonb := '{}'::jsonb;
begin
  if p_fields is null or jsonb_typeof(coalesce(p, 'null'::jsonb)) <> 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  if 'registration' = any(p_fields) then
    if v_kind is null or v_kind not in ('company', 'soleprop') then return jsonb_build_object('error', 'bad-kind'); end if;
    if v_brn !~ '^\d{12}$' or left(v_brn, 4)::int < 1900
       or left(v_brn, 4)::int > extract(year from (now() at time zone 'Asia/Kuala_Lumpur'))::int then
      return jsonb_build_object('error', 'bad-brn');
    end if;
    v_code := substr(v_brn, 5, 2);
    if v_kind = 'company' and v_code not in ('01', '02', '04') then
      return jsonb_build_object('error', case when v_code = '03' then 'brn-kind' else 'bad-brn' end, 'kind', 'soleprop');
    end if;
    if v_kind = 'soleprop' and v_code <> '03' then
      return jsonb_build_object('error', case when v_code in ('01', '02', '04') then 'brn-kind' else 'bad-brn' end, 'kind', 'company');
    end if;
    if length(v_legal) < 2 or length(v_legal) > 150 or v_legal ~* public.quote_link_like() then
      return jsonb_build_object('error', 'bad-legal');
    end if;
    v_out := v_out || jsonb_build_object('kind', v_kind, 'brn', v_brn, 'legal', v_legal);
  end if;
  if 'industry' = any(p_fields) then
    if v_ind is null then return jsonb_build_object('error', 'need-industry'); end if;
    if not exists (select 1 from public.industries i where i.name = v_ind) then return jsonb_build_object('error', 'bad-industry'); end if;
    v_out := v_out || jsonb_build_object('industry', v_ind);
  end if;
  if 'online' = any(p_fields) then
    if v_site <> '' then
      if v_site !~* '^https?://' then v_site := 'https://' || v_site; end if;
      if length(v_site) > 200 or v_site !~* '^https?://[^\s"''<>`\\/]+\.[^\s"''<>`\\]{2,}$' then
        return jsonb_build_object('error', 'bad-site');
      end if;
      v_none := false;
    elsif not v_none then
      return jsonb_build_object('error', 'need-site');
    end if;
    if v_hdl <> '' then
      if v_plat is null or v_plat not in ('instagram', 'facebook', 'tiktok', 'xhs') then return jsonb_build_object('error', 'bad-platform'); end if;
      if v_hdl !~ '^[A-Za-z0-9._-]{1,60}$' then return jsonb_build_object('error', 'bad-handle'); end if;
    elsif v_none then
      return jsonb_build_object('error', 'need-handle');
    end if;
    v_out := v_out || jsonb_build_object('website', nullif(v_site, ''), 'no_site', v_none,
      'platform', case when v_hdl <> '' then v_plat end, 'handle', case when v_hdl <> '' then '@' || v_hdl end);
  end if;
  if 'commence' = any(p_fields) then
    if v_start is null or v_start not in ('1_3', '3_6', '6_plus') then return jsonb_build_object('error', 'bad-commence'); end if;
    if v_on_t is not null then
      if v_on_t !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'bad-start-date'); end if;
      begin
        v_on := v_on_t::date;
      exception when others then
        return jsonb_build_object('error', 'bad-start-date');
      end;
      if v_on < (now() at time zone 'Asia/Kuala_Lumpur')::date or v_on > date '2099-12-31' then
        return jsonb_build_object('error', 'bad-start-date');
      end if;
    end if;
    v_out := v_out || jsonb_build_object('commence', v_start, 'commence_on', v_on);
  end if;
  return jsonb_strip_nulls(v_out);
end $$;
revoke all on function public.quote_intake_check(jsonb, text[]) from public, anon, authenticated;

-- A registration typed for a record the team already keeps is held for
-- Billing's Use details, never written over Billing: a submitted form
-- naming the quotation, unless Billing already reads the same, or a form
-- the client is still filling stands (the quotation keeps it then).
create or replace function public.quote_reg_hold(p_client uuid, p_q uuid, p_reg jsonb)
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare
  c public.clients;
  v_ref text;
begin
  if p_reg is null or not (p_reg ? 'brn') then return false; end if;
  select * into c from public.clients x where x.id = p_client;
  if c.id is null then return false; end if;
  if regexp_replace(coalesce(c.company_no, ''), '\D', '', 'g') = p_reg->>'brn'
     and upper(btrim(coalesce(c.legal_name, ''))) = p_reg->>'legal' then
    return false;
  end if;
  if exists (select 1 from public.client_detail_forms f
              where f.client_id = p_client and f.voided_at is null and f.submitted_at is null and f.expires_at > now()) then
    return false;
  end if;
  select coalesce(q.request_ref, q.ref) into v_ref from public.quotations q where q.id = p_q;
  insert into public.client_detail_forms (client_id, access_key, expires_at, submitted_at, answers, request_ref, quotation_id)
  values (p_client, public.new_link_key(), now(), now(),
          jsonb_build_object('legal_name', p_reg->>'legal', 'company_no', p_reg->>'brn'), v_ref, p_q);
  return true;
end $$;
revoke all on function public.quote_reg_hold(uuid, uuid, jsonb) from public, anon, authenticated;

-- Details the prospect sent, taken onto the record: the lead the request
-- made, matching no client, takes each value where it holds none (the
-- registration where Billing is empty and no entity holds the number);
-- any other record holds the registration for Use details and keeps the
-- rest on the quotation alone.
create or replace function public.quote_details_apply(p_q uuid, p_vals jsonb)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  q  public.quotations;
  c  public.clients;
  v_own boolean;
  v_col text;
begin
  select * into q from public.quotations x where x.id = p_q;
  select * into c from public.clients x where x.id = q.client_id;
  if c.id is null then return; end if;
  v_own := c.stage in ('lead', 'contacted', 'proposal') and q.match is null
           and c.created_at >= q.issued_at - interval '1 minute'
           and not exists (select 1 from public.quotations o where o.client_id = c.id and o.issued_at < q.issued_at and o.id <> q.id);
  if not v_own then
    perform public.quote_reg_hold(c.id, q.id, p_vals);
    return;
  end if;
  v_col := case p_vals->>'platform' when 'instagram' then 'handle_ig' when 'facebook' then 'handle_fb'
             when 'tiktok' then 'handle_tiktok' when 'xhs' then 'handle_xhs' end;
  update public.clients x set
    industry = coalesce(nullif(btrim(coalesce(x.industry, '')), ''), p_vals->>'industry'),
    website = coalesce(nullif(btrim(coalesce(x.website, '')), ''), p_vals->>'website'),
    commence = coalesce(p_vals->>'commence', x.commence),
    handle_ig = case when v_col = 'handle_ig' and nullif(btrim(coalesce(x.handle_ig, '')), '') is null then p_vals->>'handle' else x.handle_ig end,
    handle_fb = case when v_col = 'handle_fb' and nullif(btrim(coalesce(x.handle_fb, '')), '') is null then p_vals->>'handle' else x.handle_fb end,
    handle_tiktok = case when v_col = 'handle_tiktok' and nullif(btrim(coalesce(x.handle_tiktok, '')), '') is null then p_vals->>'handle' else x.handle_tiktok end,
    handle_xhs = case when v_col = 'handle_xhs' and nullif(btrim(coalesce(x.handle_xhs, '')), '') is null then p_vals->>'handle' else x.handle_xhs end
   where x.id = c.id;
  if p_vals ? 'brn' then
    if nullif(regexp_replace(coalesce(c.company_no, ''), '\D', '', 'g'), '') is null
       and not exists (select 1 from public.billing_entities e
                        where regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') = p_vals->>'brn') then
      update public.clients x set legal_name = p_vals->>'legal', company_no = p_vals->>'brn' where x.id = c.id;
    else
      perform public.quote_reg_hold(c.id, q.id, p_vals);
    end if;
  end if;
end $$;
revoke all on function public.quote_details_apply(uuid, jsonb) from public, anon, authenticated;

-- Ask for details (Clients: Quotations at Work): the fields ticked and a
-- note, owed back by the reply window's working days. Answers the reply
-- day, the link and the message in the prospect's language, for Copy for
-- WhatsApp; the email is `supplier-mail`'s (`quote_details_mail_begin`).
create or replace function public.quotation_details_ask(p_id uuid, p_fields text[], p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  q      public.quotations;
  v_f    text[];
  v_note text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '[ \t]+', ' ', 'g')), '');
  v_due  timestamptz;
  v_zh   boolean;
  v_t    public.quote_email_templates;
  v_link text;
  v_body text;
  v_k    text;
  v_v    text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.source <> 'website' or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  select coalesce(array_agg(distinct x), '{}') into v_f from unnest(coalesce(p_fields, '{}')) x;
  if exists (select 1 from unnest(v_f) x where x not in ('registration', 'industry', 'online', 'commence')) then
    return jsonb_build_object('error', 'bad-fields');
  end if;
  v_f := array(select x from unnest(array['registration', 'industry', 'online', 'commence']) x where x = any(v_f));
  if v_note is not null and (length(v_note) > 500 or v_note ~* public.quote_link_like()) then return jsonb_build_object('error', 'bad-note'); end if;
  if cardinality(v_f) = 0 and v_note is null then return jsonb_build_object('error', 'bad-fields'); end if;
  v_due := public.ops_add_business_days(now(),
    coalesce(public.app_setting('quote_details_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 3)::int);
  update public.quotations x
     set details_ask = jsonb_build_object('fields', to_jsonb(v_f), 'note', v_note),
         details_asked_at = now(), details_asked_by = me.name, details_due = v_due, details_at = null, details = null
   where x.id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand, q.ref || ' · Details asked: ' ||
          replace(substr(public.quote_details_lines(v_f, v_note, false), 3), E'\n• ', ', ') ||
          ' · Reply by ' || public.register_day((v_due at time zone 'Asia/Kuala_Lumpur')::date));
  -- The same words as the email, for WhatsApp by hand.
  v_zh := coalesce(q.contact->>'lang', 'en') = 'zh';
  select * into v_t from public.quote_email_templates x where x.kind = 'details' and x.lang = case when v_zh then 'zh' else 'en' end;
  v_link := 'https://digital.adspace.me/quote/?q=' || q.access_key;
  v_body := coalesce(v_t.body, '');
  foreach v_k in array array['contact name', 'brand', 'reference', 'details', 'reply by', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(q.contact->>'salutation', q.contact->>'name')
      when 'brand' then coalesce(q.contact->>'brand', q.brand) when 'reference' then q.ref
      when 'details' then public.quote_details_lines(v_f, v_note, v_zh)
      when 'reply by' then public.quote_day_word((v_due at time zone 'Asia/Kuala_Lumpur')::date, v_zh)
      else v_link end;
    v_body := regexp_replace(v_body, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  return jsonb_build_object('ok', true, 'due', v_due, 'key', q.access_key, 'text', v_body || E'\n\n' || v_link);
end $$;
revoke all on function public.quotation_details_ask(uuid, text[], text) from public, anon;
grant execute on function public.quotation_details_ask(uuid, text[], text) to authenticated;

-- The details request emailed to the address the prospect typed, in their
-- language, filed as a client email (the Email log reads it).
create or replace function public.quote_details_mail_begin(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  q     public.quotations;
  v_ds  text;
  v_zh  boolean;
  v_t   public.quote_email_templates;
  v_s   text;
  v_b   text;
  v_btn text;
  v_k   text;
  v_v   text;
  v_to  text;
  v_ct  uuid;
  v_id  uuid;
  v_f   text[];
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or q.source <> 'website' or q.removed_at is not null
     or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  v_ds := public.quote_details_state(q);
  if v_ds not in ('asked', 'late') or q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  v_to := lower(btrim(coalesce(q.contact->>'email', '')));
  if not (v_to ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then return jsonb_build_object('error', 'no-email'); end if;
  v_zh := coalesce(q.contact->>'lang', 'en') = 'zh';
  select * into v_t from public.quote_email_templates x where x.kind = 'details' and x.lang = case when v_zh then 'zh' else 'en' end;
  if v_t.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  v_f := array(select jsonb_array_elements_text(q.details_ask->'fields'));
  v_s := v_t.subject; v_b := v_t.body; v_btn := v_t.button;
  foreach v_k in array array['contact name', 'brand', 'reference', 'details', 'reply by', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(q.contact->>'salutation', q.contact->>'name')
      when 'brand' then coalesce(q.contact->>'brand', q.brand) when 'reference' then q.ref
      when 'details' then public.quote_details_lines(v_f, q.details_ask->>'note', v_zh)
      when 'reply by' then public.quote_day_word((q.details_due at time zone 'Asia/Kuala_Lumpur')::date, v_zh)
      else 'https://digital.adspace.me/quote/?q=' || q.access_key end;
    v_s := regexp_replace(v_s, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_b := regexp_replace(v_b, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_btn := regexp_replace(v_btn, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  select k.id into v_ct from public.client_contacts k
   where k.client_id = q.client_id and k.archived_at is null and lower(btrim(coalesce(k.email, ''))) = v_to
   order by k.is_primary desc, k.created_at limit 1;
  insert into public.client_emails (client_id, kind, ref_id, reference, contact_id, to_email, reply_to, subject, body, sent_by)
  values (q.client_id, 'details', q.id, q.ref, v_ct, v_to, public.mail_sender('clients')->>'reply_to', left(v_s, 200), v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to_email', v_to,
    'to_name', public.contact_named(q.contact->>'salutation', q.contact->>'name'),
    'subject', left(v_s, 200), 'body', v_b, 'button', v_btn, 'key', q.access_key);
end $$;
revoke all on function public.quote_details_mail_begin(uuid) from public, anon;
grant execute on function public.quote_details_mail_begin(uuid) to authenticated;

-- Not quoted (Clients: Quotations at Work): a website request the team
-- will not quote, with its reason; the link reads closed. A null reason
-- reopens it (Undo, Reopen): the request waits for review again, any
-- details asked set aside.
create or replace function public.quotation_not_quote(p_id uuid, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_word text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.source <> 'website' or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if q.released_at is not null or q.signed_at is not null then return jsonb_build_object('error', 'sent'); end if;
  if p_reason is not null then
    if p_reason not in ('incomplete', 'fit', 'duplicate', 'spam') then return jsonb_build_object('error', 'bad-reason'); end if;
    if q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
    update public.quotations x set status = 'not_proceeding', not_quoted = p_reason where x.id = q.id;
    v_word := ' not quoted: ' || case p_reason when 'incomplete' then 'Incomplete details' when 'fit' then 'Not a fit'
      when 'duplicate' then 'Duplicate' else 'Spam' end;
  else
    if q.status <> 'not_proceeding' and public.quote_details_state(q) <> 'closed' then
      return jsonb_build_object('error', 'open');
    end if;
    update public.quotations x
       set status = case when x.status = 'not_proceeding' then case when x.requested_at is not null then 'requested' else 'sent' end else x.status end,
           not_quoted = null,
           details_ask = case when public.quote_details_state(x) = 'closed' then null else x.details_ask end,
           details_asked_at = case when public.quote_details_state(x) = 'closed' then null else x.details_asked_at end,
           details_due = case when public.quote_details_state(x) = 'closed' then null else x.details_due end,
           reply_due = case when x.reply_due < now() then public.quote_reply_by(now()) else x.reply_due end
     where x.id = q.id;
    v_word := ' reopened';
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand, q.ref || v_word);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_not_quote(uuid, text) from public, anon;
grant execute on function public.quotation_not_quote(uuid, text) to authenticated;

-- A request that matched a client the team keeps under another brand
-- (QUOTE INTAKE): Add as a new brand of that client (the lead billed by
-- the client's entity, `client_entity_add`, Clients: Billing at Work) or
-- Keep as a new lead; a null choice puts Keep as a new lead back.
create or replace function public.quotation_match_take(p_id uuid, p_take text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  q   public.quotations;
  v_r jsonb;
  v_ent uuid;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.match is null then return jsonb_build_object('error', 'no-match'); end if;
  if p_take = 'brand' then
    if q.match_taken is not null then return jsonb_build_object('error', 'taken'); end if;
    v_ent := nullif(q.match->>'entity', '')::uuid;
    if v_ent is null then
      select ce.entity_id into v_ent from public.client_entities ce
       where ce.client_id = (q.match->>'client')::uuid and ce.is_main;
    end if;
    if v_ent is null then return jsonb_build_object('error', 'no-entity'); end if;
    v_r := public.client_entity_add(q.client_id, v_ent, null);
    if v_r ? 'error' and v_r->>'error' <> 'taken' then return v_r; end if;
    update public.quotations x set match_taken = 'brand' where x.id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · Added as a new brand of ' || coalesce(q.match->>'name', 'the client'));
  elsif p_take = 'lead' then
    if q.match_taken is not null then return jsonb_build_object('error', 'taken'); end if;
    update public.quotations x set match_taken = 'lead' where x.id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · Kept as a new lead');
  elsif p_take is null then
    if q.match_taken is distinct from 'lead' then return jsonb_build_object('error', 'taken'); end if;
    update public.quotations x set match_taken = null where x.id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', q.brand, q.ref || ' · Matches existing client again');
  else
    return jsonb_build_object('error', 'bad-take');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_match_take(uuid, text) from public, anon;
grant execute on function public.quotation_match_take(uuid, text) to authenticated;

-- Complete your details (anon, the prospect's own link): the fields asked
-- alone, checked as the request was, once a request; the team who work
-- leads are told, and the team owes the quotation again by the reply days.
-- Closed once the quotation is sent, set aside or past the close days.
create or replace function public.quote_details_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w   public.quotations;
  q   public.quotations;
  v_f text[];
  v   jsonb;
  v_ds text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if public.page_covered('quote') then return jsonb_build_object('error', 'unavailable'); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id) for update;
  if q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  v_ds := public.quote_details_state(q);
  if v_ds = 'received' then return jsonb_build_object('error', 'received'); end if;
  if q.status = 'not_proceeding' or v_ds not in ('asked', 'late') then return jsonb_build_object('error', 'closed'); end if;
  v_f := array(select jsonb_array_elements_text(q.details_ask->'fields'));
  v := public.quote_intake_check(coalesce(p_answers, '{}'::jsonb), v_f);
  if v ? 'error' then return v; end if;
  update public.quotations x
     set details = v, details_at = now(), contact = x.contact || v, reply_due = public.quote_reply_by(now())
   where x.id = q.id
  returning * into q;
  perform public.quote_details_apply(q.id, v);
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation portal', 'client.quotation', q.brand, q.ref || ' · Details received from ' ||
          coalesce(public.contact_named(q.contact->>'salutation', q.contact->>'name'), 'the prospect'));
  perform public.quote_tell(q.client_id, 'quote.details', 'Details received · ' || coalesce(q.contact->>'brand', q.brand),
    q.ref || ' · ' || coalesce(q.contact->>'name', '') || ' · Send by ' ||
      public.quote_day_word((q.reply_due at time zone 'Asia/Kuala_Lumpur')::date, false),
    q.id::text || ':' || extract(epoch from q.details_at)::bigint::text);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quote_details_submit(text, jsonb) from public;
grant execute on function public.quote_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.client_email_may(p_kind text, p_level text)
returns boolean
language sql stable security definer set search_path = public as $$
  select case p_kind
    when 'quotation' then public.allowed('clients.quotes', p_level)
    when 'details'   then public.allowed('clients.quotes', p_level)
    when 'offer'     then public.allowed('clients.documents', p_level)
    when 'letter'    then public.register_may('client', p_level)
    else false end
$$;
revoke all on function public.client_email_may(text, text) from public, anon, authenticated;


create or replace function public.client_email_done(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  e  public.client_emails;
  c  public.clients;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into e from public.client_emails x where x.id = p_id and x.sent_by = me.id and x.status = 'sending' for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.client_emails x set status = p_status, provider_id = nullif(p_provider, ''),
    error = left(nullif(p_error, ''), 480), sent_at = case when p_status = 'sent' then now() end
   where x.id = p_id;
  select * into c from public.clients x where x.id = e.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', coalesce(c.name, 'Client'),
          case e.kind when 'quotation' then 'Quotation ' when 'offer' then 'Letter of Offer ' when 'details' then 'Details request for ' else '' end || e.reference ||
          case p_status when 'sent' then ' emailed to ' when 'unknown' then ' emailed (not confirmed) to ' else ' not emailed to ' end ||
          coalesce((select nullif(public.contact_named(k.salutation, k.name), '') from public.client_contacts k
                     where k.client_id = e.client_id and lower(btrim(coalesce(k.email, ''))) = lower(btrim(e.to_email))
                     order by k.archived_at nulls first limit 1), 'the client') ||
          case when nullif(e.cc_email, '') is not null then ' with a copy to the finance email' else '' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_email_done(uuid, text, text, text) from public, anon;
grant execute on function public.client_email_done(uuid, text, text, text) to authenticated;


create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text; v_pre text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_18_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks', 'approval_reminder_days', 'ai_price_search',
    'reach_allowance_pct', 'priority_urgent_hours', 'priority_high_hours', 'priority_medium_hours',
    'task_remind_hours', 'task_start_days', 'quote_valid_days', 'details_form_days', 'wa_repeat_hours',
    'bench_cpr_low', 'bench_cpr_mid', 'bench_cpr_high', 'bench_cpr_top', 'bench_msg_min', 'bench_msg_target', 'bench_msg_max',
    'bench_form_min', 'bench_form_target', 'bench_form_max', 'bench_cpm_min', 'bench_cpm_max', 'bench_cpl_rise',
    'bench_reels_share', 'bench_ad_spend_pct', 'bench_adset_daily', 'vic_lead_followup_hours', 'vic_proposal_followup_days', 'fx_sgd',
    'health_keep_months', 'health_leaver_months', 'abroad_days', 'abroad_remind_hours', 'analytics_from',
    'analytics_change_pct', 'analytics_churn_pct', 'quote_reply_days', 'quote_details_days', 'quote_details_close_days', 'quote_wa_day', 'client_email_on', 'ai_price_image', 'report_post_links',
    'creator_pay_days_myr', 'creator_pay_days_other', 'task_past_days', 'hiring_invite_days', 'hiring_link_days', 'hiring_pool_months', 'hiring_keep_months', 'feedback_quiet_months', 'plan_db_mb', 'plan_db_alert_pct',
    'timely_pct', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'hiring_decision_days', 'verify_code_from',
    'work_start', 'work_end', 'work_lunch_min', 'work_weekend',
    'health_cap_default', 'health_near_pct', 'health_task_hours', 'health_remind_days', 'health_alert',
    'outstation_office_lat', 'outstation_office_lng', 'outstation_accuracy_m', 'outstation_keep_months',
    'outstation_office_radius_m', 'outstation_remind_hours',
    'reveal_seconds'];
  v_moved text[] := '{}';
  v_drop boolean; v_fw text; v_fv text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, case when v_k = 'fx_sgd' then 4 when v_k in ('outstation_office_lat', 'outstation_office_lng') then 6 else 2 end) <> v_v
       or (v_k = 'fx_sgd' and (v_v < 0.5 or v_v > 10))
       or (v_k in ('lead_followup_hours', 'vic_lead_followup_hours') and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k in ('proposal_followup_days', 'vic_proposal_followup_days') and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'approval_reminder_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') and v_v not in (0, 1))
       or (v_k = 'reach_allowance_pct' and (v_v < 0 or v_v > 5))
       or (v_k like 'priority_%_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'task_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'task_start_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'task_past_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_invite_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_link_days' and (v_v < 7 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_pool_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'feedback_quiet_months' and (v_v < 1 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_keep_months' and (v_v < 1 or v_v > 36 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_mb' and (v_v < 100 or v_v > 1000000 or v_v <> trunc(v_v)))
       or (v_k = 'plan_db_alert_pct' and (v_v < 10 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'timely_late_days' and (v_v < 0 or v_v > 30 or round(v_v, 1) <> v_v))
       or (v_k = 'stage_back_days' and (v_v < 0 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_reply_days' and (v_v < 1 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'session_idle_days' and (v_v < 0 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'reveal_seconds' and (v_v < 10 or v_v > 600 or v_v <> trunc(v_v)))
       or (v_k = 'hiring_decision_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k in ('quote_valid_days', 'details_form_days') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'quote_reply_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k = 'quote_details_days' and (v_v < 1 or v_v > 10 or v_v <> trunc(v_v)))
       or (v_k = 'quote_details_close_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k in ('creator_pay_days_myr', 'creator_pay_days_other') and (v_v < 1 or v_v > 90 or v_v <> trunc(v_v)))
       or (v_k = 'wa_repeat_hours' and (v_v < 0 or v_v > 168 or v_v <> trunc(v_v)))
       or (v_k = 'quote_wa_day' and (v_v < 0 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'health_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'health_leaver_months' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'health_cap_default' and (v_v < 1 or v_v > 80 or v_v <> trunc(v_v)))
       or (v_k = 'health_near_pct' and (v_v < 50 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k = 'health_task_hours' and (v_v < 0.5 or v_v > 40 or v_v * 2 <> trunc(v_v * 2)))
       or (v_k = 'health_remind_days' and (v_v < 0 or v_v > 14 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_office_lat' and (v_v < -90 or v_v > 90))
       or (v_k = 'outstation_office_lng' and (v_v < -180 or v_v > 180))
       or (v_k = 'outstation_accuracy_m' and (v_v < 5 or v_v > 500 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_keep_months' and (v_v < 6 or v_v > 120 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_office_radius_m' and (v_v < 20 or v_v > 1000 or v_v <> trunc(v_v)))
       or (v_k = 'outstation_remind_hours' and (v_v < 1 or v_v > 12 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_days' and (v_v < 1 or v_v > 30 or v_v <> trunc(v_v)))
       or (v_k = 'abroad_remind_hours' and (v_v < 0 or v_v > 24 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_from' and (v_v < 202308 or v_v > 209912 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 12))
       or (v_k = 'verify_code_from' and (v_v < 20230814 or v_v > 20991231 or v_v <> trunc(v_v) or mod(v_v, 100) not between 1 and 31 or mod(trunc(v_v / 100), 100) not between 1 and 12))
       or (v_k in ('work_start', 'work_end') and (v_v < 0 or v_v > 2345 or v_v <> trunc(v_v) or mod(v_v, 100) not in (0, 15, 30, 45)))
       or (v_k = 'work_lunch_min' and (v_v < 0 or v_v > 180 or v_v <> trunc(v_v) or mod(v_v, 15) <> 0))
       or (v_k = 'work_weekend' and v_v not in (0, 1, 2))
       or (v_k = 'analytics_change_pct' and (v_v < 1 or v_v > 50 or v_v <> trunc(v_v)))
       or (v_k = 'analytics_churn_pct' and (v_v < 1 or v_v > 100 or v_v <> trunc(v_v)))
       or (v_k in ('bench_reels_share') and (v_v < 0 or v_v > 100))
       or (v_k = 'bench_ad_spend_pct' and (v_v < 1 or v_v > 100))
       or (v_k = 'bench_cpl_rise' and (v_v < -100 or v_v > 100))
       or (v_k like 'bench_%' and v_k not in ('bench_reels_share', 'bench_ad_spend_pct', 'bench_cpl_rise') and (v_v < 0 or v_v > 10000)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  /* A working day ends after it starts, as the two stand on the From day. */
  if (p_values ? 'work_start' or p_values ? 'work_end')
     and coalesce((p_values ->> 'work_end')::numeric, public.app_setting('work_end', p_from))
      <= coalesce((p_values ->> 'work_start')::numeric, public.app_setting('work_start', p_from)) then
    return jsonb_build_object('error', 'bad-hours');
  end if;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      /* A planned change saved back to the value in force the day before is
         withdrawn: its row goes, rather than a second row restating it. */
      v_drop := p_from > v_today
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date = p_from)
        and exists (select 1 from public.app_settings s where s.key = v_k and s.from_date < p_from)
        and public.app_setting(v_k, p_from - 1) = v_v;
      if v_drop then
        delete from public.app_settings s where s.key = v_k and s.from_date = p_from;
      else
        insert into public.app_settings (key, from_date, value, set_by, set_at)
        values (v_k, p_from, v_v, v_me.id, now())
        on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      end if;
      v_name := case v_k when 'lead_followup_hours' then 'Lead follow-up limit' when 'proposal_followup_days' then 'Proposal follow-up limit'
        when 'vic_lead_followup_hours' then 'VIC lead follow-up limit' when 'vic_proposal_followup_days' then 'VIC proposal follow-up limit'
        when 'sst_pct' then 'SST' when 'term_1_3' then 'Under 3 months' when 'term_4_5' then '3-month commitment'
        when 'term_6_11' then '6-month commitment' when 'term_12_23' then '12-month commitment' when 'term_18_23' then '18-month commitment' when 'term_24' then '24-month commitment'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input price per million tokens'
        when 'ai_price_out' then 'AI output price per million tokens' when 'ai_price_search' then 'AI web search price per thousand searches' when 'ai_price_image' then 'AI price per scene picture' when 'meta_checks' then 'Meta checks' when 'client_email_on' then 'Send by email' when 'report_post_links' then 'Posts linked to tasks'
        when 'approval_reminder_days' then 'Approval reminder' when 'reach_allowance_pct' then 'Reach allowance'
        when 'priority_urgent_hours' then 'Urgent deadline' when 'priority_high_hours' then 'High deadline'
        when 'priority_medium_hours' then 'Medium deadline' when 'task_remind_hours' then 'Task reminders'
        when 'task_start_days' then 'Not started reminder' when 'task_past_days' then 'Past dates on new tasks' when 'hiring_invite_days' then 'Interview times within' when 'hiring_link_days' then 'Candidate link open' when 'hiring_pool_months' then 'Talent pool kept' when 'hiring_keep_months' then 'Closed candidates kept' when 'feedback_quiet_months' then 'Feedback last requested within' when 'quote_valid_days' then 'Quotation validity' when 'details_form_days' then 'Details form open'
        when 'quote_reply_days' then 'Contact within'
        when 'quote_details_days' then 'Details reply within' when 'quote_details_close_days' then 'Close after Reply by'
        when 'plan_db_mb' then 'Database plan' when 'plan_db_alert_pct' then 'Database alert'
        when 'timely_pct' then 'On time or early target' when 'timely_late_days' then 'Average lateness target'
        when 'stage_back_days' then 'Past dates on stage moves'
        when 'hiring_reply_days' then 'Interview reply time'
        when 'session_idle_days' then 'Signed-in devices'
        when 'reveal_seconds' then 'Hidden personal details'
        when 'hiring_decision_days' then 'Decision time'
        when 'creator_pay_days_myr' then 'Creator payment in MYR' when 'creator_pay_days_other' then 'Creator payment in other currencies'
        when 'wa_repeat_hours' then 'WhatsApp sent again'
        when 'quote_wa_day' then 'Website quotations on WhatsApp'
        when 'bench_cpr_low' then 'Property cost per result, tier 1 from' when 'bench_cpr_mid' then 'Property cost per result, tier 2 from'
        when 'bench_cpr_high' then 'Property cost per result, tier 3 from' when 'bench_cpr_top' then 'Property cost per result, tier 3 up to'
        when 'bench_msg_min' then 'Messaging cost per result, low' when 'bench_msg_target' then 'Messaging cost per result, target'
        when 'bench_msg_max' then 'Messaging cost per result, high' when 'bench_form_min' then 'Lead form cost per result, low'
        when 'bench_form_target' then 'Lead form cost per result, target' when 'bench_form_max' then 'Lead form cost per result, high'
        when 'bench_cpm_min' then 'Cost per 1,000 impressions, low' when 'bench_cpm_max' then 'Cost per 1,000 impressions, high'
        when 'bench_cpl_rise' then 'Yearly rise in cost per lead' when 'bench_reels_share' then 'Reels share of impressions'
        when 'bench_ad_spend_pct' then 'Ad spend share of the budget' when 'bench_adset_daily' then 'Minimum daily budget per ad set'
        when 'fx_sgd' then 'Singapore dollar rate'
        when 'health_keep_months' then 'Health check-ins kept' when 'health_leaver_months' then 'Leavers'' health data kept'
        when 'health_cap_default' then 'Health default weekly capacity' when 'health_near_pct' then 'Health near capacity'
        when 'health_task_hours' then 'Health default hours per task' when 'health_remind_days' then 'Health check-in reminder'
        when 'health_alert' then 'Health heavy workload notice'
        when 'outstation_office_lat' then 'Office latitude' when 'outstation_office_lng' then 'Office longitude'
        when 'outstation_accuracy_m' then 'Location accuracy limit' when 'outstation_keep_months' then 'Outstation trips kept'
        when 'outstation_office_radius_m' then 'Office radius' when 'outstation_remind_hours' then 'Reminder for open trips'
        when 'abroad_days' then 'Overseas approval' when 'abroad_remind_hours' then 'Overseas reminder'
        when 'analytics_from' then 'Analytics counts from'
        when 'verify_code_from' then 'Document IDs printed from'
        when 'work_start' then 'Working hours start' when 'work_end' then 'Working hours end'
        when 'work_lunch_min' then 'Lunch' when 'work_weekend' then 'Saturday and Sunday'
        when 'analytics_change_pct' then 'Analytics change threshold' when 'analytics_churn_pct' then 'Analytics quarterly churn alert'
        else 'Report due' end;
      v_pre := case when v_k = 'fx_sgd' then 'RM ' when v_k like 'ai_price_%' then 'US$' when v_k like 'bench_%' and v_k not in ('bench_cpl_rise', 'bench_reels_share', 'bench_ad_spend_pct') then 'RM ' else '' end;
      v_unit := case when v_k = 'fx_sgd' then ' per S$1' when v_k in ('lead_followup_hours', 'vic_lead_followup_hours', 'task_remind_hours', 'wa_repeat_hours', 'abroad_remind_hours', 'health_cap_default', 'health_task_hours') or v_k like 'priority_%_hours' then ' hours'
        when v_k in ('proposal_followup_days', 'vic_proposal_followup_days', 'report_due_days', 'revision_due_days', 'approval_reminder_days', 'task_start_days', 'task_past_days', 'quote_valid_days', 'details_form_days', 'quote_details_close_days', 'abroad_days', 'hiring_invite_days', 'hiring_link_days', 'timely_late_days', 'stage_back_days', 'hiring_reply_days', 'session_idle_days', 'health_remind_days') then ' days'
        when v_k in ('quote_reply_days', 'quote_details_days', 'creator_pay_days_myr', 'creator_pay_days_other', 'hiring_decision_days') then ' working days'
        when v_k = 'quote_wa_day' then ' per day'
        when v_k = 'plan_db_mb' then ' MB'
        when v_k = 'work_lunch_min' then ' minutes'
        when v_k = 'reveal_seconds' then ' seconds'
        when v_k in ('outstation_accuracy_m', 'outstation_office_radius_m') then ' m'
        when v_k = 'outstation_remind_hours' then ' hours'
        when v_k in ('outstation_office_lat', 'outstation_office_lng') then ''
        when v_k in ('health_keep_months', 'hiring_pool_months', 'hiring_keep_months', 'feedback_quiet_months', 'health_leaver_months', 'outstation_keep_months') then ' months'
        when v_pre <> '' then '' else '%' end;
      v_fw := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_was = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then coalesce(public.work_hours_word(v_k, v_was), 'not set')
              when v_k = 'analytics_from' then coalesce(substr(public.register_day(to_date(v_was::bigint::text, 'YYYYMM')), 3), 'not set')
              when v_k = 'verify_code_from' then coalesce(public.register_day(to_date(v_was::bigint::text, 'YYYYMMDD')), 'not set') else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit, 'not set') end;
      v_fv := case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then case when v_v = 1 then 'On' else 'Off' end
              when v_k like 'work\_%' and v_k <> 'work_lunch_min' then public.work_hours_word(v_k, v_v)
              when v_k = 'analytics_from' then substr(public.register_day(to_date(v_v::bigint::text, 'YYYYMM')), 3)
              when v_k = 'verify_code_from' then public.register_day(to_date(v_v::bigint::text, 'YYYYMMDD')) else v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              case when v_drop then v_name || ': planned change withdrawn · ' || v_fw || ' from ' || public.register_day(p_from) ||
                ', stays ' || v_fv else
              case when v_k in ('analytics_from', 'verify_code_from') or (v_k like 'work\_%' and v_k <> 'work_lunch_min') then v_name || ': ' || v_fw || ' → ' || v_fv || ' · from ' || public.register_day(p_from) else
              v_name || ': ' || case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k in ('meta_checks', 'client_email_on', 'report_post_links', 'health_alert') then '' else coalesce(v_pre ||
              trim(to_char(v_was, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit, 'not set') || ' → ' || v_pre ||
              trim(to_char(v_v, case when v_k = 'fx_sgd' then 'FM999999990.9999' when v_k in ('outstation_office_lat', 'outstation_office_lng') then 'FM990.999999' else 'FM999999990.99' end), '.') || v_unit ||
              ' · from ' || public.register_day(p_from) end end end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;
grant execute on function public.app_settings_set(date, jsonb) to authenticated;


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
  if nullif(btrim(coalesce(c.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = c.owner
     limit 1;
  end if;
  -- No person in charge yet: the salesperson who took the lead (Sales by,
  -- 2026-11-06) is the prospect's representative.
  if m.id is null and c.sales_by is not null then
    select * into m from public.team_members x
     where x.id = c.sales_by and x.active and not coalesce(x.system, false) and x.removed_at is null;
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


-- END OF QUOTE DETAILS ASKED ---------------------------------------------------

select public.functions_tidy();
