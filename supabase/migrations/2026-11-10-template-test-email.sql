-- ===========================================================================
-- TEMPLATE TEST EMAIL — Send test to me in Email templates (2026-11-10; the
-- user's Settings brief: "Send test to me is offered where the channel
-- allows it"). Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner.
--
-- WHAT IT ADDS
-- * `mail_tests` (RLS on, no policy, no grant): one row a test sent, who and
--   when, counted twenty a colleague a Malaysian day; never a recipient, a
--   subject or a word.
-- * `template_sample(p_field, p_kind, p_name)`: the made-up value a test
--   fills each field with (Jane Doe, COMPANY NAME SDN BHD, AC001 …), the
--   sender's own name for {sender name}; closed to every caller.
-- * `mail_test_begin(p_kind, p_subject, p_body, p_legal, p_disclaimer)`:
--   asked by `supplier-mail` `test` as the colleague. Refuses `denied`
--   unless the colleague may change that kind of template (the same parts
--   each save asks), `bad-subject`, `bad-body`, `unknown-field` as
--   `template_check` reads it, `no-email` without a sign-in address,
--   `too-many` past twenty today; answers the colleague's own sign-in
--   address (the only address a test goes to) and the words with every
--   field filled. Nothing is filed in the Email log or the Activity record.
-- ===========================================================================

create table if not exists public.mail_tests (
  id         uuid primary key default gen_random_uuid(),
  member_id  uuid not null,
  sent_at    timestamptz not null default now()
);
alter table public.mail_tests enable row level security;
revoke all on public.mail_tests from public, anon, authenticated;
create index if not exists mail_tests_member_idx on public.mail_tests (member_id, sent_at);

create or replace function public.template_sample(p_field text, p_kind text, p_name text)
returns text
language sql stable set search_path = public as $$
  select case lower(regexp_replace(coalesce(p_field, ''), '\s+', ' ', 'g'))
    when 'contact name' then 'John Doe'
    when 'creator name' then 'Jane Doe'
    when 'payee' then 'Jane Doe'
    when 'client name' then 'ADspace Advertising'
    when 'client' then 'ADspace Advertising'
    when 'company name' then 'COMPANY NAME SDN BHD'
    when 'supplier name' then 'COMPANY NAME SDN BHD'
    when 'supplier id' then 'AS001'
    when 'payment term' then 'NET 30'
    when 'currency' then 'MYR'
    when 'document title' then case p_kind when 'supplier' then 'Supplier Service Agreement' else 'Letter of Offer' end
    when 'document reference' then case p_kind when 'supplier' then 'AD/SCA/AS001/261101' else 'AQL/AC001/261101' end
    when 'document date' then public.register_day((now() at time zone 'Asia/Kuala_Lumpur')::date)
    when 'valid until' then public.register_day((now() at time zone 'Asia/Kuala_Lumpur')::date + 30)
    when 'sender name' then coalesce(nullif(p_name, ''), 'John Doe')
    when 'invoice no' then 'INV-00001'
    when 'count' then '2'
    when 'total' then 'RM 1,000.00'
    when 'sign off' then 'Yours sincerely,'
    when 'creator id' then 'ADC0001'
    when 'reference' then 'ADC0001/R001'
    when 'method' then 'Bank transfer'
    when 'account ending' then '1234'
    when 'review link' then 'https://digital.adspace.me/admin/'
    when 'job reference' then 'ADC0001/CC001'
    when 'campaign' then 'Festive Launch 2026'
    when 'posted date' then public.register_day((now() at time zone 'Asia/Kuala_Lumpur')::date)
    when 'pay by' then public.register_day((now() at time zone 'Asia/Kuala_Lumpur')::date + 14)
    when 'amount' then 'RM 500.00'
    when 'bill number' then 'PB-00001'
    else '{' || p_field || '}'
  end $$;
revoke all on function public.template_sample(text, text, text) from public, anon, authenticated;

create or replace function public.mail_test_begin(p_kind text, p_subject text, p_body text, p_legal text, p_disclaimer text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_s    text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b    text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_l    text := btrim(replace(coalesce(p_legal, ''), E'\r', ''));
  v_d    text := btrim(replace(coalesce(p_disclaimer, ''), E'\r', ''));
  v_bad  jsonb;
  v_n    integer;
  v_day  timestamptz := date_trunc('day', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  f      text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_kind not in ('supplier', 'client', 'free', 'invoice', 'creator-details', 'creator-booking') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  if not (public.ops_granted('team.settings', 'work')
          or (p_kind in ('supplier', 'free') and public.allowed('suppliers', 'manage'))) then
    return jsonb_build_object('error', 'denied');
  end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if length(v_l) > 1000 or length(v_d) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b || E'\n' || v_l || E'\n' || v_d, p_kind);
  if v_bad is not null then return v_bad; end if;
  if coalesce(btrim(me.email), '') = '' then return jsonb_build_object('error', 'no-email'); end if;
  perform pg_advisory_xact_lock(hashtext('mail_test:' || me.id::text));
  select count(*) into v_n from public.mail_tests t where t.member_id = me.id and t.sent_at >= v_day;
  if v_n >= 20 then return jsonb_build_object('error', 'too-many'); end if;
  insert into public.mail_tests (member_id) values (me.id);
  foreach f in array coalesce(public.template_fields(p_kind), '{}'::text[]) loop
    if f = 'invoices' then continue; end if;
    v_s := regexp_replace(v_s, '\{\s*' || replace(f, ' ', '\s+') || '\s*\}', public.template_sample(f, p_kind, me.name), 'gi');
    v_b := regexp_replace(v_b, '\{\s*' || replace(f, ' ', '\s+') || '\s*\}', public.template_sample(f, p_kind, me.name), 'gi');
    v_l := regexp_replace(v_l, '\{\s*' || replace(f, ' ', '\s+') || '\s*\}', public.template_sample(f, p_kind, me.name), 'gi');
    v_d := regexp_replace(v_d, '\{\s*' || replace(f, ' ', '\s+') || '\s*\}', public.template_sample(f, p_kind, me.name), 'gi');
  end loop;
  return jsonb_build_object('ok', true, 'to', lower(btrim(me.email)), 'name', me.name,
    'subject', v_s, 'body', v_b, 'legal', nullif(v_l, ''), 'disclaimer', nullif(v_d, ''), 'left', 19 - v_n);
end $$;
revoke all on function public.mail_test_begin(text, text, text, text, text) from public, anon;
grant execute on function public.mail_test_begin(text, text, text, text, text) to authenticated;

-- Rollback:
--   drop function if exists public.mail_test_begin(text, text, text, text, text);
--   drop function if exists public.template_sample(text, text, text);
--   drop table if exists public.mail_tests;

-- END OF TEMPLATE TEST EMAIL ------------------------------------------------
