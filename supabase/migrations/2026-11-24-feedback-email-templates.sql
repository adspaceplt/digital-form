-- ===========================================================================
-- FEEDBACK EMAIL TEMPLATES (2026-11-24)
-- ===========================================================================
-- WHY (the user, 2026-11-24: "dont u have a rule to remove duplication.. to
-- deduplicate every sections"): every email's wording is edited in the one
-- section whose emails they are, Clients for a client's. A feedback
-- request's email was the one client email whose words were fixed in
-- `feedback_mail_begin`; it joins the Clients templates as Feedback.
--
-- WHAT CHANGED
--   * `feedback_email_templates` (kind `quick` Service rating or `review`
--     Performance review, lang `en` or `zh`; subject, body, button; RLS on,
--     no policy, no grant), seeded once into an empty table with the words
--     `feedback_mail_begin` wrote until today.
--   * `template_fields('feedback')`: {contact name}, {client name}, {link};
--     `template_fields_all()` answers it.
--   * `feedback_email_templates_get()` and
--     `feedback_email_template_save(p_kind, p_lang, p_subject, p_body,
--     p_button)` at `team.settings` (Clients: Edit email templates), each
--     field checked (`bad-subject`, `bad-body`, `bad-button`,
--     `unknown-field`), filed `team.changed` under Email templates.
--   * `feedback_mail_begin` reads the template in the primary contact's
--     language and fills its fields; every refusal it held stays, and a
--     missing template refuses `not-found` before a request is made. It
--     answers the same keys, so `supplier-mail` is unchanged.
--
-- ORDER: this file (connector), then the pages. An old page lists no
-- Feedback templates; the email reads the same words either way. Safe to
-- run twice.
-- ROLLBACK: restate `feedback_mail_begin` from FEEDBACK SENT BY EMAIL,
-- `template_fields` from CREATOR DETAILS CHANGED and `template_fields_all`
-- from CANDIDATE EMAILS; drop the two template functions; the table may
-- stay.
-- ===========================================================================

create table if not exists public.feedback_email_templates (
  kind        text not null check (kind in ('quick', 'review')),
  lang        text not null check (lang in ('en', 'zh')),
  subject     text not null,
  body        text not null,
  button      text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.team_members(id) on delete set null,
  primary key (kind, lang)
);
alter table public.feedback_email_templates enable row level security;
revoke all on table public.feedback_email_templates from public, anon, authenticated;

insert into public.feedback_email_templates (kind, lang, subject, body, button)
select x.kind, x.lang, x.subject, x.body, x.button from (values
  ('quick', 'en', 'Service rating · ADspace',
   E'Dear {contact name},\n\nADspace would be grateful for your feedback on the services provided to {client name}. The form takes about one minute to complete.\n\nThis link is intended for {client name} only.',
   'Rate your experience'),
  ('review', 'en', 'Performance review · ADspace',
   E'Dear {contact name},\n\nADspace would be grateful for your feedback on the services provided to {client name}. The form takes about three minutes to complete.\n\nThis link is intended for {client name} only.',
   'Rate your experience'),
  ('quick', 'zh', '服务评分 · ADspace',
   E'尊敬的{contact name}：\n\nADspace诚邀您对其为{client name}提供的服务作出评价，填写约需一分钟。\n\n此链接仅供{client name}使用。',
   '请评价您的体验'),
  ('review', 'zh', '绩效评估 · ADspace',
   E'尊敬的{contact name}：\n\nADspace诚邀您对其为{client name}提供的服务作出评价，填写约需三分钟。\n\n此链接仅供{client name}使用。',
   '请评价您的体验')
) as x (kind, lang, subject, body, button)
where not exists (select 1 from public.feedback_email_templates);

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
    'feedback', to_jsonb(public.template_fields('feedback'))) end $$;
revoke all on function public.template_fields_all() from public, anon;
grant execute on function public.template_fields_all() to authenticated;

create or replace function public.feedback_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.ops_me() is null or not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'kind', t.kind, 'lang', t.lang, 'subject', t.subject, 'body', t.body, 'button', t.button,
      'updated_at', t.updated_at, 'updated_by', m.name)
      order by array_position(array['quick', 'review'], t.kind), array_position(array['en', 'zh'], t.lang))
      from public.feedback_email_templates t left join public.team_members m on m.id = t.updated_by), '[]'::jsonb)) end
$$;
revoke all on function public.feedback_email_templates_get() from public, anon;
grant execute on function public.feedback_email_templates_get() to authenticated;

create or replace function public.feedback_email_template_save(p_kind text, p_lang text, p_subject text, p_body text, p_button text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  t     public.feedback_email_templates;
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
  v_bad := public.template_check(v_s || E'\n' || v_b || E'\n' || v_btn, 'feedback');
  if v_bad is not null then return v_bad; end if;
  select * into t from public.feedback_email_templates x where x.kind = p_kind and x.lang = p_lang for update;
  if t.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if t.button is distinct from v_btn then moved := moved || ('Button: ' || t.button || ' → ' || v_btn); end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.feedback_email_templates x set subject = v_s, body = v_b, button = v_btn, updated_at = now(), updated_by = me.id
   where x.kind = t.kind and x.lang = t.lang;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates',
          (case t.kind when 'quick' then 'Service rating' else 'Performance review' end)
          || ' (' || case t.lang when 'zh' then '中文' else 'English' end || ') · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.feedback_email_template_save(text, text, text, text, text) from public, anon;
grant execute on function public.feedback_email_template_save(text, text, text, text, text) to authenticated;

create or replace function public.feedback_mail_begin(p_client uuid, p_kind text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  r     jsonb;
  v_cl  public.clients;
  v_ct  public.client_contacts;
  v_t   public.feedback_email_templates;
  v_zh  boolean;
  v_s   text;
  v_b   text;
  v_btn text;
  v_k   text;
  v_v   text;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  if p_kind in ('quick', 'review')
     and (select count(*) from public.feedback_email_templates x where x.kind = p_kind) < 2 then
    return jsonb_build_object('error', 'not-found');
  end if;
  r := public.feedback_request(p_client, p_kind);
  if r ? 'error' then return r; end if;
  select * into v_cl from public.clients c where c.id = p_client;
  select * into v_ct from public.client_contacts k
   where k.id = (select q.contact_id from public.feedback_requests q where q.id = (r->>'id')::uuid);
  v_zh := coalesce(v_ct.lang, 'en') = 'zh';
  select * into v_t from public.feedback_email_templates x
   where x.kind = p_kind and x.lang = case when v_zh then 'zh' else 'en' end;
  v_s := v_t.subject;
  v_b := v_t.body;
  v_btn := v_t.button;
  foreach v_k in array array['contact name', 'client name', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(v_ct.salutation, v_ct.name)
      when 'client name' then v_cl.name
      else 'https://digital.adspace.me/feedback/?k=' || (r->>'key') end;
    v_s := regexp_replace(v_s, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_b := regexp_replace(v_b, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_btn := regexp_replace(v_btn, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  update public.feedback_requests q set mail_status = 'sending' where q.id = (r->>'id')::uuid;
  return r || jsonb_build_object('subject', left(v_s, 200), 'body', v_b, 'button', v_btn, 'lang', case when v_zh then 'zh' else 'en' end);
end $$;
revoke all on function public.feedback_mail_begin(uuid, text) from public, anon;
grant execute on function public.feedback_mail_begin(uuid, text) to authenticated;

-- END OF FEEDBACK EMAIL TEMPLATES --------------------------------------------

select public.functions_tidy();
