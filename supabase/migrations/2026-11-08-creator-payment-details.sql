-- ===========================================================================
-- CREATOR PAYMENT DETAILS — a creator gives their payment details once, on
-- their own page, and the team approves them (2026-11-08). Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-11-08: the AP01 form's fields, "asked once,
-- from the first booking"; a change goes back for approval; "dont hardcode
-- anything")
-- * `creator_pay_requests` (RLS on, no policy, no grant): each set of
--   details a creator sends, under its own reference, the pattern held on
--   the creator row of `id_formats` (`{creator}/R{nnn}`, ADC0001/R001), set
--   in Settings beside the Creator ID. Pending until a colleague at the
--   granted part `campaigns.pay` Work approves or declines it (a reason);
--   the newest approved set is the one paid to, the one before it Replaced.
--   A set sent while another is pending stands in for it (Withdrawn).
-- * `creator_pay_form(p_code)` (anon, the creator's code counted as
--   `get_creator` counts it): whether the details are asked (a booking from
--   Confirmed on, or a set already sent), the newest set and the one paid
--   to, the ID number and account held as their last four characters alone.
--   `creator_pay_submit(p_code, p_values)` checks the AP01 fields
--   (`creator_pay_check`), keeps an ID or account number left blank where
--   the kind, or the method, bank and currency, are unchanged, and queues
--   the emails; five sets a creator a day (`too-many`).
-- * `creator_pay_list(p_creator)` (Creators List View): every set, the ID
--   and account numbers whole at `campaigns.pay` View, else their last four.
--   `creator_pay_decide(p_id, p_ok, p_note)` (`campaigns.pay` Work) approves
--   or declines a pending set; `creator_pay_states()` answers each
--   creator's standing for the Creators List.
-- * `creator_emails` (RLS on, no policy, no grant): the creator emails,
--   queued by these functions and sent by the `creator-mail` edge function
--   (woken by `creator_mail_kick`, pg_cron `creator-mail-drain` every five
--   minutes while one waits): Details received to the creator, Details to
--   review to the finance address, Details approved to the creator.
--   `creator_email_templates` holds each one's words and whether it is
--   sent, the finance address on Details to review; Settings, Templates:
--   Creator emails (`team.settings`). Resend's word reaches them through
--   `supplier_email_status`, `mail_sweep` marks one stuck Sending as Not
--   confirmed, `mail_retention` clears its address and words after twelve
--   months, and Messages' Email log lists them.
-- * `id_format_set` takes the request reference's pattern on the creator
--   row (`{creator}` and a run of n in braces); `team_roles_admin_guard`
--   holds `campaigns.pay` with the other granted parts.
-- ===========================================================================

update public.id_formats set pattern = '{creator}/R{nnn}' where kind = 'creator' and pattern is null;

create table if not exists public.creator_pay_requests (
  id          uuid primary key default gen_random_uuid(),
  creator_id  uuid not null references public.creators(id) on delete cascade,
  seq         int not null,
  ref         text not null,
  bill_kind   text not null check (bill_kind in ('nric', 'passport', 'brn')),
  id_no       text not null,
  legal_name  text not null,
  tin         text,
  address     text not null,
  currency    text not null check (currency in ('MYR', 'SGD')),
  method      text not null check (method in ('bank', 'duitnow', 'paynow', 'tng')),
  bank        text,
  account     text not null,
  payee       text not null,
  email       text not null,
  whatsapp    text not null,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'replaced', 'withdrawn')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  uuid,
  note        text,
  unique (creator_id, seq)
);
create unique index if not exists creator_pay_requests_ref_idx on public.creator_pay_requests (ref);
alter table public.creator_pay_requests enable row level security;
revoke all on table public.creator_pay_requests from public, anon, authenticated;

create table if not exists public.creator_email_templates (
  purpose     text primary key check (purpose in ('received', 'review', 'approved')),
  on_send     boolean not null default true,
  subject     text not null,
  body        text not null,
  to_email    text,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
alter table public.creator_email_templates enable row level security;
revoke all on table public.creator_email_templates from public, anon, authenticated;
insert into public.creator_email_templates (purpose, subject, body, to_email) values
  ('received', 'Payment details received: {reference}',
   E'Dear {creator name},\n\nThank you for submitting your payment details under reference {reference}.\n\nADspace will review them and inform you by email once they are approved.\n\nYours sincerely,\nADspace', null),
  ('review', 'Payment details to review: {creator id} {creator name}',
   E'{creator name} ({creator id}) has submitted payment details under reference {reference}.\n\nPayee: {payee}\nMethod: {method}\nAccount ending: {account ending}\n\nReview them in the portal:\n{review link}', 'ap@adspacestudios.com'),
  ('approved', 'Payment details approved: {reference}',
   E'Dear {creator name},\n\nYour payment details under reference {reference} have been approved. Payments will be made to the account ending {account ending}.\n\nYours sincerely,\nADspace', null)
on conflict (purpose) do nothing;

create table if not exists public.creator_emails (
  id           uuid primary key default gen_random_uuid(),
  purpose      text not null check (purpose in ('received', 'review', 'approved')),
  creator_id   uuid,
  request_id   uuid,
  to_email     text not null,
  subject      text not null,
  body         text not null,
  created_at   timestamptz not null default now(),
  status       text not null default 'queued'
               check (status in ('queued', 'sending', 'sent', 'failed', 'unknown', 'delivered', 'opened', 'bounced', 'complained')),
  claimed_at   timestamptz,
  provider_id  text,
  error        text,
  sent_at      timestamptz,
  delivered_at timestamptz,
  opened_at    timestamptz,
  bounced_at   timestamptz
);
create index if not exists creator_emails_created_idx on public.creator_emails (created_at desc);
create index if not exists creator_emails_queued_idx on public.creator_emails (created_at) where status = 'queued';
create unique index if not exists creator_emails_provider_idx on public.creator_emails (provider_id) where provider_id is not null;
alter table public.creator_emails enable row level security;
revoke all on table public.creator_emails from public, anon, authenticated;

/* A set's words: its method, a bank named after a bank transfer. */
create or replace function public.creator_pay_method(p_method text, p_bank text)
returns text language sql immutable set search_path = public as $$
  select case p_method when 'bank' then 'Bank transfer' || coalesce(' · ' || nullif(p_bank, ''), '')
    when 'duitnow' then 'DuitNow' when 'paynow' then 'PayNow' when 'tng' then 'Touch ''n Go eWallet' else p_method end
$$;
revoke all on function public.creator_pay_method(text, text) from public, anon, authenticated;

/* The next request's reference: the pattern's {creator} filled with the
   Creator ID and its run of n with the number, as wide as the run. */
create or replace function public.creator_pay_ref(p_code text, p_seq int)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_pat text := coalesce((select f.pattern from public.id_formats f where f.kind = 'creator'), '{creator}/R{nnn}');
  v_run text := substring(v_pat from '\{(n+)\}');
begin
  v_pat := replace(v_pat, '{creator}', coalesce(p_code, ''));
  if v_run is null then return v_pat || p_seq; end if;
  return replace(v_pat, '{' || v_run || '}', lpad(p_seq::text, greatest(length(v_run), length(p_seq::text)), '0'));
end $$;
revoke all on function public.creator_pay_ref(text, int) from public, anon, authenticated;

/* What the AP01 form checked, field by field: the first field wrong is
   named (`field`), else the values as they are kept (`values`). */
create or replace function public.creator_pay_check(p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  v_kind text := btrim(coalesce(p->>'bill_kind', ''));
  v_id   text := upper(regexp_replace(coalesce(p->>'id_no', ''), '[\s-]', '', 'g'));
  v_name text := btrim(regexp_replace(coalesce(p->>'legal_name', ''), '\s+', ' ', 'g'));
  v_tin  text := upper(regexp_replace(coalesce(p->>'tin', ''), '\s', '', 'g'));
  v_addr text := btrim(coalesce(p->>'address', ''));
  v_cur  text := upper(btrim(coalesce(p->>'currency', '')));
  v_meth text := btrim(coalesce(p->>'method', ''));
  v_bank text := btrim(coalesce(p->>'bank', ''));
  v_acct text := upper(regexp_replace(coalesce(p->>'account', ''), '[\s-]', '', 'g'));
  v_pay  text := btrim(regexp_replace(coalesce(p->>'payee', ''), '\s+', ' ', 'g'));
  v_mail text := lower(btrim(coalesce(p->>'email', '')));
  v_wa   text := regexp_replace(coalesce(p->>'whatsapp', ''), '\D', '', 'g');
  v_banks constant text[] := array['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank', 'Bank Islam',
    'Public Bank', 'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital', '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB',
    '[SG] CIMB', '[SG] Maybank', '[SG] Bank of China'];
begin
  if v_kind not in ('nric', 'passport', 'brn') then return jsonb_build_object('field', 'bill_kind'); end if;
  if v_kind = 'nric' and v_id !~ '^\d{12}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'brn' and v_id !~ '^\d{12}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'passport' and v_id !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'nric' then v_id := substr(v_id, 1, 6) || '-' || substr(v_id, 7, 2) || '-' || substr(v_id, 9, 4); end if;
  if length(v_name) < 2 or length(v_name) > 120 then return jsonb_build_object('field', 'legal_name'); end if;
  if v_tin <> '' and v_tin !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('field', 'tin'); end if;
  if length(v_addr) < 5 or length(v_addr) > 300 then return jsonb_build_object('field', 'address'); end if;
  if v_cur not in ('MYR', 'SGD') then return jsonb_build_object('field', 'currency'); end if;
  if not ((v_cur = 'MYR' and v_meth in ('bank', 'duitnow', 'tng')) or (v_cur = 'SGD' and v_meth in ('bank', 'paynow'))) then
    return jsonb_build_object('field', 'method');
  end if;
  if v_meth = 'bank' then
    if not (v_bank = any (v_banks)) or ((v_cur = 'SGD') <> (v_bank like '[SG]%')) then
      return jsonb_build_object('field', 'bank');
    end if;
  else
    v_bank := '';
  end if;
  if v_acct !~ '^[A-Z0-9]{6,34}$' then return jsonb_build_object('field', 'account'); end if;
  if length(v_pay) < 2 or length(v_pay) > 120 then return jsonb_build_object('field', 'payee'); end if;
  if v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_mail) > 160 then return jsonb_build_object('field', 'email'); end if;
  if length(v_wa) < 8 or length(v_wa) > 15 then return jsonb_build_object('field', 'whatsapp'); end if;
  if coalesce(p->>'confirm', '') not in ('true', 'on', '1') then return jsonb_build_object('field', 'confirm'); end if;
  return jsonb_build_object('values', jsonb_build_object('bill_kind', v_kind, 'id_no', v_id, 'legal_name', v_name,
    'tin', nullif(v_tin, ''), 'address', v_addr, 'currency', v_cur, 'method', v_meth, 'bank', nullif(v_bank, ''),
    'account', v_acct, 'payee', v_pay, 'email', v_mail, 'whatsapp', v_wa));
end $$;
revoke all on function public.creator_pay_check(jsonb) from public, anon, authenticated;

/* A set as the creator's page reads it: the numbers as their last four. */
create or replace function public.creator_pay_json(r public.creator_pay_requests, p_whole boolean)
returns jsonb language sql stable set search_path = public as $$
  select case when r.id is null then null else jsonb_build_object(
    'id', r.id, 'ref', r.ref, 'status', r.status, 'created_at', r.created_at, 'decided_at', r.decided_at,
    'note', r.note, 'bill_kind', r.bill_kind,
    'id_no', case when p_whole then r.id_no end, 'id_end', right(regexp_replace(r.id_no, '\W', '', 'g'), 4),
    'legal_name', r.legal_name, 'tin', r.tin, 'address', r.address, 'currency', r.currency,
    'method', r.method, 'method_word', public.creator_pay_method(r.method, r.bank), 'bank', r.bank,
    'account', case when p_whole then r.account end, 'account_end', right(r.account, 4),
    'payee', r.payee, 'email', r.email, 'whatsapp', r.whatsapp) end
$$;
revoke all on function public.creator_pay_json(public.creator_pay_requests, boolean) from public, anon, authenticated;

create or replace function public.creator_mail_kick()
returns void
language plpgsql security definer set search_path = public as $$
begin
  -- once a transaction: the one wake, sent after the commit, finds every row
  if current_setting('adspace.creator_mail_kicked', true) = '1' then return; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/creator-mail', '{"action":"drain"}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-adspace-wake',
            coalesce((select s.value from public.app_secrets s where s.key = 'wake_secret'), ''));
  perform set_config('adspace.creator_mail_kicked', '1', true);
exception when others then
  return;
end $$;
revoke all on function public.creator_mail_kick() from public, anon, authenticated;

/* One email queued in its template's words, where it is sent and has an
   address to go to. */
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
  v_k text;
  v_v text;
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into r from public.creator_pay_requests x where x.id = p_req;
  select * into c from public.creators x where x.id = r.creator_id;
  v_to := lower(btrim(coalesce(case when p_purpose = 'review' then t.to_email else r.email end, '')));
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  foreach v_k in array array['creator name', 'creator id', 'reference', 'payee', 'method', 'account ending', 'review link'] loop
    v_v := case v_k when 'creator name' then c.name when 'creator id' then coalesce(c.creator_code, '')
      when 'reference' then r.ref when 'payee' then r.payee
      when 'method' then public.creator_pay_method(r.method, r.bank) when 'account ending' then right(r.account, 4)
      else 'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id end;
    v_sub := regexp_replace(v_sub, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_body := regexp_replace(v_body, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  insert into public.creator_emails (purpose, creator_id, request_id, to_email, subject, body)
  values (p_purpose, c.id, r.id, v_to, left(v_sub, 200), v_body);
  perform public.creator_mail_kick();
end $$;
revoke all on function public.creator_mail_queue(text, uuid) from public, anon, authenticated;

/* Whether a creator is asked: a booking from Confirmed on, or a set sent. */
create or replace function public.creator_pay_due(p_creator uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.campaign_options o where o.creator_id = p_creator
                  and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced'))
      or exists (select 1 from public.creator_pay_requests r where r.creator_id = p_creator)
$$;
revoke all on function public.creator_pay_due(uuid) from public, anon, authenticated;

create or replace function public.creator_pay_form(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     public.creators;
  v_last public.creator_pay_requests;
  v_paid public.creator_pay_requests;
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators x where x.id = v_id;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;
  select * into v_last from public.creator_pay_requests x where x.creator_id = cr.id and x.status <> 'withdrawn'
   order by x.seq desc limit 1;
  select * into v_paid from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  return jsonb_build_object('ok', true, 'due', public.creator_pay_due(cr.id), 'whatsapp', cr.whatsapp,
    'last', public.creator_pay_json(v_last, false), 'paid', public.creator_pay_json(v_paid, false));
end $$;
grant execute on function public.creator_pay_form(text) to anon, authenticated;

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
  -- A number left blank keeps the one held, where nothing it belongs to moved.
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
  end if;
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
  insert into public.activity_log (actor, action, subject, detail)
  values ('Creator page', 'creator.updated', cr.name,
          coalesce(cr.creator_code || ' · ', '') || 'Payment details submitted · ' || v_new.ref || ' · ' ||
          public.creator_pay_method(v_new.method, v_new.bank) || ' ending ' || right(v_new.account, 4));
  perform public.creator_mail_queue('received', v_new.id);
  perform public.creator_mail_queue('review', v_new.id);
  return jsonb_build_object('ok', true, 'ref', v_new.ref);
end $$;
grant execute on function public.creator_pay_submit(text, jsonb) to anon, authenticated;

create or replace function public.creator_pay_list(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_whole boolean := public.ops_granted('campaigns.pay', 'view');
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'whole', v_whole, 'decide', public.ops_granted('campaigns.pay', 'work'),
    'rows', coalesce((select jsonb_agg(public.creator_pay_json(r, v_whole)
                                       || jsonb_build_object('decided_by', m.name) order by r.seq desc)
                        from public.creator_pay_requests r
                        left join public.team_members m on m.id = r.decided_by
                       where r.creator_id = p_creator), '[]'::jsonb),
    'emails', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'purpose', e.purpose, 'to_email', e.to_email,
                          'status', e.status, 'created_at', e.created_at) order by e.created_at desc)
                         from public.creator_emails e where e.creator_id = p_creator), '[]'::jsonb));
end $$;
revoke all on function public.creator_pay_list(uuid) from public, anon;
grant execute on function public.creator_pay_list(uuid) to authenticated;

create or replace function public.creator_pay_states()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then '{}'::jsonb
    else coalesce((select jsonb_object_agg(x.creator_id, x.state) from (
      select r.creator_id,
             case when bool_or(r.status = 'pending') then 'pending'
                  when bool_or(r.status = 'approved') then 'approved'
                  else 'declined' end as state
        from public.creator_pay_requests r where r.status <> 'withdrawn'
       group by r.creator_id) x), '{}'::jsonb) end
$$;
revoke all on function public.creator_pay_states() from public, anon;
grant execute on function public.creator_pay_states() to authenticated;

create or replace function public.creator_pay_decide(p_id uuid, p_ok boolean, p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  r      public.creator_pay_requests;
  cr     public.creators;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.creator_pay_requests x where x.id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'pending' then return jsonb_build_object('error', 'decided', 'status', r.status); end if;
  if not coalesce(p_ok, false) and v_note is null then return jsonb_build_object('error', 'no-note'); end if;
  if length(coalesce(v_note, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select * into cr from public.creators x where x.id = r.creator_id;
  if p_ok then
    update public.creator_pay_requests x set status = 'replaced' where x.creator_id = r.creator_id and x.status = 'approved';
  end if;
  update public.creator_pay_requests x set status = case when p_ok then 'approved' else 'declined' end,
    decided_at = now(), decided_by = me.id, note = v_note where x.id = r.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', cr.name,
          coalesce(cr.creator_code || ' · ', '') || 'Payment details ' || case when p_ok then 'approved' else 'declined' end ||
          ' · ' || r.ref || coalesce(' · ' || v_note, ''));
  if p_ok then perform public.creator_mail_queue('approved', r.id); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_pay_decide(uuid, boolean, text) from public, anon;
grant execute on function public.creator_pay_decide(uuid, boolean, text) to authenticated;

create or replace function public.creator_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'purpose', t.purpose, 'on', t.on_send, 'subject', t.subject, 'body', t.body, 'to_email', t.to_email,
      'updated_at', t.updated_at, 'updated_by', m.name) order by array_position(array['received', 'review', 'approved'], t.purpose))
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
    v_to := nullif(lower(btrim(coalesce(x->>'to_email', ''))), '');
    if t.purpose = 'review' and (v_to is null or v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_to) > 160) then
      return jsonb_build_object('error', 'bad-email');
    end if;
    if t.purpose <> 'review' then v_to := null; end if;
    if (t.on_send, t.subject, t.body, t.to_email) is distinct from
       (coalesce((x->>'on')::boolean, true), btrim(x->>'subject'), btrim(x->>'body'), v_to) then
      v_word := case t.purpose when 'received' then 'Details received' when 'review' then 'Details to review' else 'Details approved' end;
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
revoke all on function public.creator_email_templates_save(jsonb) from public, anon;
grant execute on function public.creator_email_templates_save(jsonb) to authenticated;

/* The sender's own: queued emails claimed one at a time, never one already
   on its way. */
create or replace function public.creator_mail_claim(p_n int default 5)
returns setof public.creator_emails
language plpgsql volatile security definer set search_path = public as $$
begin
  return query
  update public.creator_emails x set status = 'sending', claimed_at = now()
   where x.id in (select y.id from public.creator_emails y where y.status = 'queued'
                   order by y.created_at limit least(greatest(coalesce(p_n, 5), 1), 10) for update skip locked)
  returning x.*;
end $$;
revoke all on function public.creator_mail_claim(int) from public, anon, authenticated;
grant execute on function public.creator_mail_claim(int) to service_role;

create or replace function public.creator_mail_done(p_id uuid, p_status text, p_provider text, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e public.creator_emails;
begin
  if p_status not in ('sent', 'failed', 'unknown') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into e from public.creator_emails x where x.id = p_id and x.status = 'sending' for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.creator_emails x set status = p_status, provider_id = nullif(p_provider, ''),
    error = left(nullif(p_error, ''), 480), sent_at = case when p_status = 'sent' then now() end
   where x.id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_mail_done(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.creator_mail_done(uuid, text, text, text) to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: creator emails are woken by their writes alone until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'creator-mail-drain';
  perform cron.schedule('creator-mail-drain', '*/5 * * * *',
    'select public.creator_mail_kick() where exists (select 1 from public.creator_emails e where e.status = ''queued'')');
end $$;

create or replace function public.id_format_set(p_kind text, p_prefix text, p_width int, p_next bigint, p_pattern text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  f   public.id_formats;
  v_p text := upper(btrim(coalesce(p_prefix, '')));
  v_t text := btrim(coalesce(p_pattern, ''));
  v_top bigint;
  v_moved text[] := '{}';
  v_word text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into f from public.id_formats where kind = p_kind for update;
  if f.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  v_word := case p_kind when 'creator' then 'Creator ID' when 'campaign' then 'Campaign ID' else 'Job reference' end;
  if p_kind = 'job' then
    if length(v_t) > 40 or position('{creator}' in v_t) = 0 or position('{campaign}' in v_t) = 0 then
      return jsonb_build_object('error', 'bad-pattern');
    end if;
    if v_t is distinct from f.pattern then
      update public.id_formats set pattern = v_t, updated_at = now(), updated_by = me.id where kind = p_kind;
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, 'team.changed', 'Creator and campaign IDs', v_word || ': ' || f.pattern || ' → ' || v_t);
    end if;
    return jsonb_build_object('ok', true);
  end if;
  if v_p !~ '^[A-Z]{1,6}$' then return jsonb_build_object('error', 'bad-prefix'); end if;
  if p_width is null or p_width < 2 or p_width > 6 then return jsonb_build_object('error', 'bad-width'); end if;
  if p_next is null or p_next < 1 then return jsonb_build_object('error', 'bad-next'); end if;
  -- A creator's payment details reference: its Creator ID and a run of n.
  if p_kind = 'creator' and v_t <> '' and (length(v_t) > 40 or position('{creator}' in v_t) = 0 or v_t !~ '\{n{1,6}\}') then
    return jsonb_build_object('error', 'bad-request-pattern');
  end if;
  -- The next number stays above every number in use under that prefix.
  if p_kind = 'creator' then
    select max(substring(c.creator_code from length(v_p) + 1)::bigint) into v_top
      from public.creators c where c.creator_code ~ ('^' || v_p || '[0-9]+$');
  else
    select max(substring(m.campaign_code from length(v_p) + 1)::bigint) into v_top
      from public.campaigns m where m.campaign_code ~ ('^' || v_p || '[0-9]+$');
  end if;
  if v_top is not null and p_next <= v_top then
    return jsonb_build_object('error', 'bad-next', 'top', v_top);
  end if;
  v_moved := array_remove(array[
    case when v_p <> f.prefix then 'prefix ' || f.prefix || ' → ' || v_p end,
    case when p_width <> f.width then 'digits ' || f.width || ' → ' || p_width end,
    case when p_next <> f.next_no then 'next ' || f.next_no || ' → ' || p_next end,
    case when p_kind = 'creator' and v_t <> '' and v_t is distinct from f.pattern
         then 'payment details reference ' || coalesce(f.pattern, 'not set') || ' → ' || v_t end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.id_formats set prefix = v_p, width = p_width, next_no = p_next,
    pattern = case when p_kind = 'creator' and v_t <> '' then v_t else pattern end,
    updated_at = now(), updated_by = me.id
   where kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Creator and campaign IDs', v_word || ': ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.id_format_set(text, text, int, bigint, text) from public, anon;
grant execute on function public.id_format_set(text, text, int, bigint, text) to authenticated;

create or replace function public.team_roles_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_granted constant text[] := array['ops.all', 'ops.reports', 'ops.workflows', 'ops.time', 'ops.numbering',
    'ops.override', 'team.performance', 'team.perfadmin', 'team.settings', 'team.upgrade', 'team.invite',
    'team.handbook', 'team.announce', 'team.notice', 'reports.whitelabel', 'reports.transfer', 'reports.ai',
    'reports.meta', 'register.types', 'campaigns.files_delete', 'clients.vic', 'suppliers.pay',
    'team.analytics', 'campaigns.pay'];
  k text;
begin
  if who = '' or pg_trigger_depth() > 1 or public.allowed('admin') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if (tg_op <> 'INSERT' and (coalesce(old.is_admin, false) or old.slug = 'admin'))
     or (tg_op <> 'DELETE' and (coalesce(new.is_admin, false) or new.slug = 'admin')) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin group.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  foreach k in array v_granted loop
    if coalesce(new.access ->> k, '') is distinct from
       (case when tg_op = 'INSERT' then '' else coalesce(old.access ->> k, '') end) then
      raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin tool.';
    end if;
  end loop;
  return new;
end $$;
revoke all on function public.team_roles_admin_guard() from public, anon, authenticated;

create or replace function public.supplier_email_status(p_provider text, p_event text, p_at timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  e    public.supplier_emails;
  i    public.invoice_emails;
  ce   public.client_emails;
  te   public.team_emails;
  cm   public.creator_emails;
  rank constant jsonb := '{"sending":0,"unknown":1,"sent":1,"failed":4,"delivered":2,"opened":3,"complained":4,"bounced":4}';
  st   text := case p_event when 'email.delivered' then 'delivered' when 'email.opened' then 'opened'
                when 'email.clicked' then 'opened' when 'email.bounced' then 'bounced'
                when 'email.complained' then 'complained' when 'email.sent' then 'sent'
                when 'email.failed' then 'failed' end;
begin
  if st is null then return jsonb_build_object('ok', true, 'ignored', true); end if;
  select * into e from public.supplier_emails x where x.provider_id = p_provider for update;
  if e.id is not null then
    update public.supplier_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = e.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into ce from public.client_emails x where x.provider_id = p_provider for update;
  if ce.id is not null then
    update public.client_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = ce.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into cm from public.creator_emails x where x.provider_id = p_provider for update;
  if cm.id is not null then
    update public.creator_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = cm.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into te from public.team_emails x where x.provider_id = p_provider for update;
  if te.id is not null then
    update public.team_emails x set
      status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
      sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
      delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
      opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
      bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
     where x.id = te.id;
    return jsonb_build_object('ok', true);
  end if;
  select * into i from public.invoice_emails x where x.provider_id = p_provider for update;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.invoice_emails x set
    status = case when (rank->>st)::int > (rank->>x.status)::int then st else x.status end,
    sent_at = coalesce(x.sent_at, case when st not in ('bounced', 'failed') then p_at end),
    delivered_at = case when st in ('delivered', 'opened') then coalesce(x.delivered_at, p_at) else x.delivered_at end,
    opened_at = case when st = 'opened' then coalesce(x.opened_at, p_at) else x.opened_at end,
    bounced_at = case when st = 'bounced' then coalesce(x.bounced_at, p_at) else x.bounced_at end
   where x.id = i.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_email_status(text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.supplier_email_status(text, text, timestamptz) to service_role;

create or replace function public.mail_sweep()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.invoice_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.client_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.team_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.creator_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_sweep() from public, anon, authenticated;

create or replace function public.mail_retention()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.team_emails x set to_email = '', to_name = null, cc_email = null, reply_to = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.client_emails x set to_email = '', cc_email = null, reply_to = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set to_email = '', cc_email = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.invoice_emails x set to_email = '', cc_email = null, body = ''
   where x.created_at < now() - interval '12 months' and x.status <> 'sending' and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  update public.creator_emails x set to_email = '', body = ''
   where x.created_at < now() - interval '12 months' and x.status not in ('queued', 'sending') and (x.to_email <> '' or x.body <> '');
  get diagnostics k = row_count; n := n + k;
  -- A signing code's details: an unused one 30 days after it expired, a
  -- used one a year on (the signature itself is kept on its quotation).
  update public.quote_sign_codes x set email = '', payload = '{}'::jsonb
   where (x.email <> '' or x.payload <> '{}'::jsonb)
     and ((x.used_at is null and x.expires_at < now() - interval '30 days') or x.used_at < now() - interval '12 months');
  get diagnostics k = row_count; n := n + k;
  -- An address an email filed in the Activity record before 2026-11-04,
  -- deleted on the email's own clock (audit 2026-11-04): the senders' own
  -- lines alone (emailed to …), never a contact or supplier edit's from
  -- and to, which the record keeps its three years (audit 2026-11-04, 4).
  update public.activity_log x
     set detail = regexp_replace(x.detail, '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+', '(address deleted)', 'g')
   where x.action in ('email.sent', 'client.edited', 'supplier.edited') and x.created_at < now() - interval '12 months'
     and (x.action = 'email.sent' or x.detail ~ '(^| )(not )?emailed(, not confirmed,| \(not confirmed\))? to ')
     and x.detail ~ '[^@\s,;<>()]+@[^@\s,;<>()]+\.[^@\s,;<>()]+';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_retention() from public, anon, authenticated;

create or replace function public.mail_log(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  v_a    timestamptz;
  v_b    timestamptz;
  v_sup  boolean;
  v_bill boolean;
  v_quo  boolean;
  v_all  boolean;
  v_cr   boolean;
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_sup := public.allowed('suppliers', 'view');
  v_bill := public.allowed('clients.billing', 'view');
  v_quo := public.allowed('clients.quotes', 'view');
  v_all := public.client_scope_free('view');
  v_cr := public.allowed('campaigns.creators', 'view');
  return jsonb_build_object(
    'month', v_from,
    'items', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
        select * from (
          select 'supplier'::text as source, e.id, e.purpose as kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name as sent_by, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null::uuid as client_id, null::text as client, e.supplier_id, s.name as supplier, s.code as supplier_code,
                 d.serial as reference, null::text as to_name
            from public.supplier_emails e
            left join public.suppliers s on s.id = e.supplier_id
            left join public.documents d on d.id = e.document_id
            left join public.team_members t on t.id = e.sent_by
           where v_sup and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'client', e.id, e.kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, k.name
            from public.client_emails e
            left join public.clients c on c.id = e.client_id
            left join public.client_contacts k on k.id = e.contact_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and public.client_email_may(e.kind, 'view')
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'invoice', e.id, e.purpose, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, coalesce(c.name, e.client_name), null, null, null,
                 (select string_agg(i->>'number', ', ' order by o) from jsonb_array_elements(e.invoices) with ordinality as a (i, o)),
                 null
            from public.invoice_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where v_bill and e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'manual', e.id, 'message', e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, e.supplier_id, s.name, s.code,
                 e.attachment, e.to_name
            from public.team_emails e
            left join public.clients c on c.id = e.client_id
            left join public.suppliers s on s.id = e.supplier_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is not null then public.allowed('clients.contacts', 'view') and public.client_seen(e.client_id, 'view')
                       when e.supplier_id is not null then v_sup else true end)
             and (not e.finance or v_bill)
          union all
          select 'creator', e.id, 'creator_' || e.purpose, e.to_email, null, e.subject, e.body,
                 null, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null, null, null, null, null,
                 r.ref, k.name
            from public.creator_emails e
            left join public.creators k on k.id = e.creator_id
            left join public.creator_pay_requests r on r.id = e.request_id
           where v_cr and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'signing', g.id, 'signing', g.email, null, 'Your ADspace signing code for quotation ' || q.ref, null,
                 null, g.created_at,
                 case when g.used_at is not null then 'used' when g.expires_at < now() then 'expired' else 'requested' end,
                 null, g.created_at, null, null, null,
                 q.client_id, c.name, null, null, null,
                 q.ref, nullif(btrim(coalesce(g.payload->'contact'->>'salutation', '') || ' ' || coalesce(g.payload->'contact'->>'name', '')), '')
            from public.quote_sign_codes g
            join public.quotations q on q.id = g.quotation_id
            left join public.clients c on c.id = q.client_id
           where v_quo and g.created_at >= v_a and g.created_at < v_b
             and (case when q.client_id is null then v_all else public.client_seen(q.client_id, 'view') end)
        ) u
        order by u.created_at desc
        limit 2000) x), '[]'::jsonb));
end $$;
revoke all on function public.mail_log(date) from public, anon;
grant execute on function public.mail_log(date) to authenticated;

-- Rollback: drop the creator_pay_* and creator_mail_* functions and
-- creator_email_templates_get / _save, unschedule creator-mail-drain, drop
-- creator_emails, creator_email_templates and creator_pay_requests, and run
-- the CREATOR AND CAMPAIGN IDS and ANALYTICS IS AN ADMIN TOOL sections'
-- id_format_set and team_roles_admin_guard again.

-- END OF CREATOR PAYMENT DETAILS ---------------------------------------------

select public.functions_tidy();
