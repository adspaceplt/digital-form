-- ===========================================================================
-- CREATOR PAYMENTS — a creator is a supplier in Bukku, their bills read back
-- as Processing or Paid, an earlier job's AKJ number kept on its booking,
-- and the payment request, posted and paid emails (2026-11-09). Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-11-08: "Go ahead R2 and subsequent"; the
-- flow approved that day: the payment request starts when a booking is
-- Posted; the team puts the Job reference in the Bukku bill's reference; the
-- portal reads that bill and shows Processing or Paid, never marked by
-- hand; AKJ bills stay as they are; "dont hardcode anything")
-- * A creator is a Bukku contact of kind `creator` (`bukku_links`), sent or
--   linked from their payment details as a supplier: the details approved
--   last, the Creator ID in Bukku's Supplier ID field, the ID number only
--   at Creator payment details View. Read at the Creators List; sent,
--   linked and unlinked at `campaigns.pay` Work. `bukku_may`,
--   `bukku_record_name`, `bukku_print`, `bukku_prepare`, `bukku_linked` and
--   `bukku_link_only` are restated with the creator; the check on
--   `bukku_links.kind` and `bukku_unlink` / `_undo` are the SQL Editor part's.
-- * `campaign_options.earlier_job`: a booking given an AKJ number before the
--   portal (the AP01 series), typed at `campaigns.pay` Work
--   (`creator_earlier_job_set`: `bad-ref`, `taken`), matched to its bill as
--   the Job reference is.
-- * `campaign_options.posted_on` and `pay_by`: stamped by trigger
--   `campaign_options_posted` on the move into Posted (the day the first
--   post went live, else today, MYT), the pay-by day that many working days
--   after it (`creator_pay_days_myr` 10, `creator_pay_days_other` 21,
--   Business settings, by the currency of the details approved last). The
--   same move queues the payment request to finance (with the bell for
--   whoever holds `campaigns.pay` at Work) and the posted email to the
--   creator; a revert clears neither.
-- * `creator_bills` (RLS on, no policy, no grant): the creator's Bukku bills
--   as last read (`bukku-sync` `bills`, and every night with the billing),
--   each matched to the booking whose Job reference or earlier job its
--   reference or number holds; Paid where Bukku holds no balance. Written by
--   `creator_bills_take` (the service role's), which sends the paid email
--   when a bill read Processing before is read Paid, never for a bill first
--   read already paid. `creator_bills_list(p_creator)` (Creators List View)
--   answers each booking from Confirmed on with its bill, and the bills
--   matching no booking (Earlier payments); `creator_bills_due()` the
--   creators the night reads.
-- * `creator_email_templates` gains Payment request, Post recorded and
--   Payment sent (the SQL Editor part, which widens the purpose checks);
--   `creator_mail_job` fills them from the booking. The finance address is
--   the one Details to review goes to.
-- ===========================================================================

alter table public.campaign_options add column if not exists earlier_job text;
alter table public.campaign_options add column if not exists posted_on date;
alter table public.campaign_options add column if not exists pay_by date;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'campaign_options_earlier_job_check') then
    alter table public.campaign_options add constraint campaign_options_earlier_job_check
      check (earlier_job is null or earlier_job ~ '^[A-Z0-9][A-Z0-9/._-]{1,39}$');
  end if;
end $$;
create unique index if not exists campaign_options_earlier_job_idx on public.campaign_options (earlier_job) where earlier_job is not null;

insert into public.app_settings (key, from_date, value)
select k, date '2026-11-01', v from (values ('creator_pay_days_myr', 10), ('creator_pay_days_other', 21)) s(k, v)
 where not exists (select 1 from public.app_settings x where x.key = s.k);

alter table public.creator_emails add column if not exists option_id uuid;

create table if not exists public.creator_bills (
  bill_id      bigint primary key,
  creator_id   uuid not null references public.creators(id) on delete cascade,
  contact_id   bigint,
  number       text,
  ref          text,
  bill_date    date,
  amount       numeric(14,2),
  balance      numeric(14,2),
  currency     text,
  status       text not null check (status in ('processing', 'paid')),
  option_id    uuid references public.campaign_options(id) on delete set null,
  gone         boolean not null default false,
  read_at      timestamptz not null default now(),
  paid_seen_at timestamptz,
  paid_told_at timestamptz
);
create index if not exists creator_bills_creator_idx on public.creator_bills (creator_id);
alter table public.creator_bills enable row level security;
revoke all on table public.creator_bills from public, anon, authenticated;

/* A reference read for matching: its letters and digits, in capitals. */
create or replace function public.creator_ref_key(p text)
returns text language sql immutable set search_path = public as $$
  select upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g'))
$$;
revoke all on function public.creator_ref_key(text) from public, anon, authenticated;

/* A booking's Job reference for the database's own use (campaign_job_ref
   answers the team alone). Internal. */
create or replace function public.creator_job_ref(p_option uuid)
returns text language sql stable security definer set search_path = public as $$
  select replace(replace(f.pattern, '{creator}', coalesce(c.creator_code, '')), '{campaign}', coalesce(m.campaign_code, ''))
    from public.campaign_options o
    join public.creators c on c.id = o.creator_id
    join public.campaigns m on m.id = o.campaign_id
    join public.id_formats f on f.kind = 'job'
   where o.id = p_option
$$;
revoke all on function public.creator_job_ref(uuid) from public, anon, authenticated;

/* The booking a bill is for: the one whose Job reference, or earlier job,
   the bill's reference or number holds. Internal. */
create or replace function public.creator_bill_option(p_creator uuid, p_ref text, p_number text)
returns uuid language sql stable security definer set search_path = public as $$
  select o.id from public.campaign_options o
   where o.creator_id = p_creator
     and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
     and exists (select 1 from unnest(array[public.creator_job_ref(o.id), o.earlier_job]) k(v)
                  where length(public.creator_ref_key(k.v)) >= 4
                    and (position(public.creator_ref_key(k.v) in public.creator_ref_key(p_ref)) > 0
                      or position(public.creator_ref_key(k.v) in public.creator_ref_key(p_number)) > 0))
   order by length(public.creator_ref_key(public.creator_job_ref(o.id))) desc
   limit 1
$$;
revoke all on function public.creator_bill_option(uuid, text, text) from public, anon, authenticated;

/* A booking email (payment request, post recorded, payment sent) queued in
   its template's words, where it is sent and has an address. Internal. */
create or replace function public.creator_mail_job(p_purpose text, p_option uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t   public.creator_email_templates;
  fin public.creator_email_templates;
  o   public.campaign_options;
  c   public.creators;
  m   public.campaigns;
  r   public.creator_pay_requests;
  b   public.creator_bills;
  v_to text; v_sub text; v_body text; v_k text; v_v text;
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into o from public.campaign_options x where x.id = p_option;
  select * into c from public.creators x where x.id = o.creator_id;
  select * into m from public.campaigns x where x.id = o.campaign_id;
  select * into r from public.creator_pay_requests x where x.creator_id = c.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  select * into b from public.creator_bills x where x.option_id = o.id and not x.gone order by x.bill_date desc nulls last limit 1;
  select * into fin from public.creator_email_templates x where x.purpose = 'review';
  v_to := lower(btrim(coalesce(case when p_purpose = 'request' then fin.to_email else r.email end, '')));
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  foreach v_k in array array['creator name', 'creator id', 'job reference', 'campaign', 'posted date', 'pay by',
                              'payee', 'method', 'account ending', 'amount', 'bill number', 'review link'] loop
    v_v := case v_k when 'creator name' then c.name when 'creator id' then coalesce(c.creator_code, '')
      when 'job reference' then coalesce(public.creator_job_ref(o.id), '') || coalesce(' (' || o.earlier_job || ')', '')
      when 'campaign' then coalesce(m.title, '')
      when 'posted date' then coalesce(public.register_day(o.posted_on), '')
      when 'pay by' then coalesce(public.register_day(o.pay_by), '')
      when 'payee' then coalesce(r.payee, 'Payment details pending approval')
      when 'method' then coalesce(public.creator_pay_method(r.method, r.bank), '')
      when 'account ending' then coalesce(right(r.account, 4), '')
      when 'amount' then case when b.amount is null then '' else
        case coalesce(b.currency, 'MYR') when 'MYR' then 'RM ' when 'SGD' then 'S$ ' else b.currency || ' ' end ||
        to_char(b.amount, 'FM999,999,990.00') end
      when 'bill number' then coalesce(b.number, '')
      else 'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id end;
    v_sub := regexp_replace(v_sub, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_body := regexp_replace(v_body, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  insert into public.creator_emails (purpose, creator_id, request_id, option_id, to_email, subject, body)
  values (p_purpose, c.id, r.id, o.id, v_to, left(v_sub, 200), v_body);
  perform public.creator_mail_kick();
end $$;
revoke all on function public.creator_mail_job(text, uuid) from public, anon, authenticated;

/* The move into Posted: its day, its pay-by day, the payment request to
   finance with the bell, and the posted email to the creator. A fault never
   fails the move. */
create or replace function public.campaign_options_posted()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_day date; v_cur text; v_days int;
begin
  if new.state is distinct from 'posted' or old.state in ('posted', 'completed') then return new; end if;
  begin
    v_day := coalesce((select min(p.published_at) from public.option_posts p where p.option_id = new.id),
                      (now() at time zone 'Asia/Kuala_Lumpur')::date);
    select r.currency into v_cur from public.creator_pay_requests r
     where r.creator_id = new.creator_id and r.status = 'approved' order by r.decided_at desc limit 1;
    v_days := coalesce(public.app_setting(case when coalesce(v_cur, 'MYR') = 'MYR' then 'creator_pay_days_myr' else 'creator_pay_days_other' end, v_day),
                       case when coalesce(v_cur, 'MYR') = 'MYR' then 10 else 21 end)::int;
    new.posted_on := coalesce(new.posted_on, v_day);
    new.pay_by := coalesce(new.pay_by,
      (public.ops_add_business_days((new.posted_on::timestamp at time zone 'Asia/Kuala_Lumpur'), v_days) at time zone 'Asia/Kuala_Lumpur')::date);
  exception when others then
    return new;
  end;
  return new;
end $$;
revoke all on function public.campaign_options_posted() from public, anon, authenticated;
create or replace trigger campaign_options_posted before update of state on public.campaign_options
  for each row execute function public.campaign_options_posted();

create or replace function public.campaign_options_posted_mail()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators; m public.campaigns; v_ref text;
begin
  if new.state is distinct from 'posted' or old.state in ('posted', 'completed') then return null; end if;
  -- Told once a booking: a revert and a second move into Posted tell nobody again.
  if exists (select 1 from public.creator_emails e where e.option_id = new.id and e.purpose in ('request', 'posted')) then return null; end if;
  begin
    perform public.creator_mail_job('request', new.id);
    perform public.creator_mail_job('posted', new.id);
    select * into c from public.creators x where x.id = new.creator_id;
    select * into m from public.campaigns x where x.id = new.campaign_id;
    v_ref := public.creator_job_ref(new.id);
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.payment', 'Creator payment request · ' || coalesce(v_ref, c.name),
           c.name || ' · ' || coalesce(m.title, '') || coalesce(' · Pay by ' || public.register_day(new.pay_by), ''),
           'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id,
           'creator.payment:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and not coalesce(tm.system, false)
       and (tm.is_admin or tm.role = 'admin' or public.level_rank(tm.access ->> 'campaigns.pay') >= 2)
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;
revoke all on function public.campaign_options_posted_mail() from public, anon, authenticated;
create or replace trigger campaign_options_posted_mail after update of state on public.campaign_options
  for each row execute function public.campaign_options_posted_mail();

/* An earlier job's AKJ number on a booking (the AP01 series), matched to its
   Bukku bill as the Job reference is; empty takes it off. */
create or replace function public.creator_earlier_job_set(p_option uuid, p_ref text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  c  public.creators;
  v  text := nullif(upper(regexp_replace(btrim(coalesce(p_ref, '')), '\s+', '', 'g')), '');
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v is not null and v !~ '^[A-Z0-9][A-Z0-9/._-]{1,39}$' then return jsonb_build_object('error', 'bad-ref'); end if;
  if v is not null and exists (select 1 from public.campaign_options x where x.earlier_job = v and x.id <> o.id) then
    return jsonb_build_object('error', 'taken');
  end if;
  if v is not distinct from o.earlier_job then return jsonb_build_object('ok', true); end if;
  update public.campaign_options x set earlier_job = v where x.id = o.id;
  select * into c from public.creators x where x.id = o.creator_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name,
          coalesce(public.creator_job_ref(o.id) || ' · ', '') || 'Earlier job ID: ' || coalesce(o.earlier_job, 'not set') || ' → ' || coalesce(v, 'not set'));
  update public.creator_bills b set option_id = public.creator_bill_option(b.creator_id, b.ref, b.number)
   where b.creator_id = o.creator_id;
  return jsonb_build_object('ok', true, 'earlier_job', v);
end $$;
revoke all on function public.creator_earlier_job_set(uuid, text) from public, anon;
grant execute on function public.creator_earlier_job_set(uuid, text) to authenticated;

/* The creator's Bukku bills as read, the service role's alone: each matched
   to its booking, those not read again marked gone, and the paid email sent
   where a bill read Processing before is now Paid. */
create or replace function public.creator_bills_take(p_creator uuid, p_contact bigint, p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  x jsonb; b public.creator_bills; v_id bigint; v_status text; v_opt uuid; v_n int := 0; v_paid int := 0;
  v_seen bigint[] := '{}';
begin
  if p_creator is null or jsonb_typeof(p_rows) is distinct from 'array' then return jsonb_build_object('error', 'bad-request'); end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    v_id := (x->>'id')::bigint;
    if v_id is null then continue; end if;
    v_seen := v_seen || v_id;
    v_status := case when coalesce((x->>'balance')::numeric, 0) <= 0 then 'paid' else 'processing' end;
    v_opt := public.creator_bill_option(p_creator, x->>'ref', x->>'number');
    select * into b from public.creator_bills y where y.bill_id = v_id for update;
    if b.bill_id is null then
      insert into public.creator_bills (bill_id, creator_id, contact_id, number, ref, bill_date, amount, balance, currency, status,
                                        option_id, read_at, paid_seen_at, paid_told_at)
      values (v_id, p_creator, p_contact, left(x->>'number', 60), left(x->>'ref', 200), nullif(x->>'date', '')::date,
              (x->>'amount')::numeric, (x->>'balance')::numeric, left(coalesce(x->>'currency', 'MYR'), 3), v_status, v_opt, now(),
              case when v_status = 'paid' then now() end,
              -- A bill first read already paid was paid before the portal read it: nobody is told.
              case when v_status = 'paid' then now() end);
    else
      update public.creator_bills y set creator_id = p_creator, contact_id = p_contact, number = left(x->>'number', 60),
        ref = left(x->>'ref', 200), bill_date = nullif(x->>'date', '')::date, amount = (x->>'amount')::numeric,
        balance = (x->>'balance')::numeric, currency = left(coalesce(x->>'currency', 'MYR'), 3), status = v_status,
        option_id = v_opt, gone = false, read_at = now(),
        paid_seen_at = case when v_status = 'paid' then coalesce(y.paid_seen_at, now()) end
       where y.bill_id = v_id;
      if v_status = 'paid' and b.status = 'processing' and b.paid_told_at is null and v_opt is not null then
        update public.creator_bills y set paid_told_at = now() where y.bill_id = v_id;
        perform public.creator_mail_job('paid', v_opt);
        v_paid := v_paid + 1;
      end if;
    end if;
    v_n := v_n + 1;
  end loop;
  update public.creator_bills y set gone = true where y.creator_id = p_creator and not (y.bill_id = any(v_seen)) and not y.gone;
  return jsonb_build_object('ok', true, 'bills', v_n, 'told', v_paid);
end $$;
revoke all on function public.creator_bills_take(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.creator_bills_take(uuid, bigint, jsonb) to service_role;

/* The creators the night reads: linked to Bukku, with a booking posted and
   not yet read Paid. The service role's alone. */
create or replace function public.creator_bills_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('creator', l.record_id, 'contact', l.contact_id)), '[]'::jsonb)
    from public.bukku_links l
   where l.kind = 'creator'
     and exists (select 1 from public.campaign_options o
                  where o.creator_id = l.record_id and o.state in ('posted', 'completed')
                    and not exists (select 1 from public.creator_bills b where b.option_id = o.id and b.status = 'paid' and not b.gone))
$$;
revoke all on function public.creator_bills_due() from public, anon, authenticated;
grant execute on function public.creator_bills_due() to service_role;

/* A creator's payments for the console: each booking from Confirmed on with
   its Job reference, earlier job, posted and pay-by days and the bill read
   for it, then the bills matching no booking. Creators List View; the bill
   figures at Creator payment details View. */
create or replace function public.creator_bills_list(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pay boolean := public.ops_granted('campaigns.pay', 'view'); l public.bukku_links;
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.creators c where c.id = p_creator) then return jsonb_build_object('error', 'not-found'); end if;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = p_creator;
  return jsonb_build_object('ok', true, 'pay', v_pay, 'linked', l.contact_id is not null,
    'read_at', (select max(b.read_at) from public.creator_bills b where b.creator_id = p_creator),
    'jobs', coalesce((select jsonb_agg(jsonb_build_object(
        'option', o.id, 'job', public.creator_job_ref(o.id), 'earlier_job', o.earlier_job, 'state', o.state,
        'campaign', m.title, 'campaign_id', m.id, 'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = p_creator and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb),
    'earlier', coalesce((select jsonb_agg(jsonb_build_object('number', b.number, 'ref', b.ref, 'status', b.status, 'date', b.bill_date,
        'amount', case when v_pay then b.amount end, 'currency', b.currency) order by b.bill_date desc nulls last)
        from public.creator_bills b where b.creator_id = p_creator and b.option_id is null and not b.gone), '[]'::jsonb));
end $$;
revoke all on function public.creator_bills_list(uuid) from public, anon;
grant execute on function public.creator_bills_list(uuid) to authenticated;

create or replace function public.creator_email_templates_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'purpose', t.purpose, 'on', t.on_send, 'subject', t.subject, 'body', t.body, 'to_email', t.to_email,
      'updated_at', t.updated_at, 'updated_by', m.name)
      order by array_position(array['received', 'review', 'approved', 'request', 'posted', 'paid'], t.purpose))
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
revoke all on function public.creator_email_templates_save(jsonb) from public, anon;
grant execute on function public.creator_email_templates_save(jsonb) to authenticated;

create or replace function public.bukku_may(p_kind text, p_id uuid, p_level text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return false; end if;
  if p_kind = 'client' then
    return public.allowed('clients.billing', p_level) and public.client_seen(p_id, 'view');
  elsif p_kind = 'supplier' then
    return public.allowed('suppliers', p_level);
  elsif p_kind = 'creator' then
    -- A creator is read at the Creators List; it is sent at Creator payment details.
    return public.allowed('campaigns.creators', 'view')
       and (p_level = 'view' or public.ops_granted('campaigns.pay', 'work'));
  elsif p_kind = 'entity' then
    return public.allowed('clients.billing', p_level)
       and exists (select 1 from public.client_entities ce
                    where ce.entity_id = p_id and public.client_seen(ce.client_id, 'view'));
  end if;
  return false;
end $$;
revoke all on function public.bukku_may(text, uuid, text) from public, anon, authenticated;

create or replace function public.bukku_record_name(p_kind text, p_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select case when p_kind = 'client'
              then (select x.name from public.clients x where x.id = p_id)
              when p_kind = 'entity'
              then (select coalesce(nullif(btrim(x.legal_name), ''), 'Billing entity') from public.billing_entities x where x.id = p_id)
              when p_kind = 'creator'
              then (select coalesce(x.name, x.creator_code) from public.creators x where x.id = p_id)
              else (select coalesce(x.name, x.code) from public.suppliers x where x.id = p_id) end
$$;
revoke all on function public.bukku_record_name(text, uuid) from public, anon, authenticated;

create or replace function public.bukku_print(p_kind text, p_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v text; v_k public.client_contacts;
begin
  if p_kind = 'client' then
    select concat_ws('|', c.legal_name, c.company_no, c.company_no_old, c.tin, c.sst_no, c.billing_address,
             c.finance_email, c.client_code, c.market, ct.name, ct.email, ct.phone)
      into v
      from public.clients c
      left join public.client_contacts ct on ct.id = coalesce(c.bill_contact_id,
        (select y.id from public.client_contacts y where y.client_id = c.id and y.is_primary and y.archived_at is null limit 1))
     where c.id = p_id;
  elsif p_kind = 'entity' then
    v_k := public.entity_contact(p_id);
    select concat_ws('|', e.legal_name, e.company_no, e.company_no_old, e.tin, e.sst_no, e.billing_address,
             e.finance_email, c.client_code, c.market, v_k.name, v_k.email, v_k.phone)
      into v
      from public.billing_entities e
      left join public.clients c on c.id = public.entity_home_client(e.id)
     where e.id = p_id;
  elsif p_kind = 'creator' then
    select concat_ws('|', r.ref, r.legal_name, r.bill_kind, r.id_no, r.tin, r.address, r.currency, r.email, r.whatsapp, c.creator_code)
      into v
      from public.creators c
      left join lateral (select * from public.creator_pay_requests y where y.creator_id = c.id and y.status = 'approved'
                          order by y.decided_at desc limit 1) r on true
     where c.id = p_id;
  else
    select concat_ws('|', s.name, s.kind, s.brn, s.tin, s.sst_no, s.address, s.email, s.finance_email,
             s.contact_name, s.mobile, s.phone, s.currency, s.code, s.payment_term)
      into v from public.suppliers s where s.id = p_id;
  end if;
  return case when v is null then null else md5(v) end;
end $$;
revoke all on function public.bukku_print(text, uuid) from public, anon, authenticated;

create or replace function public.bukku_prepare(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients; s public.suppliers; ct public.client_contacts; e public.billing_entities;
  l public.bukku_links; b public.bukku_settings; cr public.creators; rq public.creator_pay_requests;
  v_missing text[] := '{}'; v_company boolean; v_id text; v_field bigint; v_pay boolean;
  v_person text; v_out jsonb;
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into b from public.bukku_settings where id = 1;
  if p_kind = 'client' then
    select * into c from public.clients x where x.id = p_id;
    if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into ct from public.client_contacts x
     where x.id = c.bill_contact_id and x.archived_at is null;
    if ct.id is null then
      select * into ct from public.client_contacts x where x.client_id = c.id and x.is_primary and x.archived_at is null;
    end if;
    if coalesce(btrim(c.legal_name), '') = '' then v_missing := v_missing || 'Registered name'::text; end if;
    if coalesce(btrim(c.client_code), '') = '' then v_missing := v_missing || 'Client ID'::text; end if;
    if array_length(v_missing, 1) > 0 then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(v_missing)); end if;
    select * into l from public.bukku_links x where x.kind = 'client' and x.record_id = c.id;
    if l.contact_id is null then l.contact_id := (public.bukku_shared('client', c.id)->>'contact_id')::bigint; end if;
    v_person := btrim(coalesce(ct.name, ''));
    return jsonb_build_object('ok', true, 'kind', 'client', 'id', c.id,
      'legal_name', public.bukku_name_case(c.legal_name, true), 'other_name', c.name,
      'entity_type', case when c.market = 'SG' then 'FOREIGN_COMPANY' else 'MALAYSIAN_COMPANY' end,
      'reg_no_type', case when nullif(regexp_replace(coalesce(c.company_no, ''), '[^0-9A-Za-z]', '', 'g'), '') is null then null else 'BRN' end,
      'reg_no', nullif(regexp_replace(coalesce(c.company_no, ''), '[^0-9A-Za-z]', '', 'g'), ''),
      'old_reg_no', nullif(btrim(coalesce(c.company_no_old, '')), ''),
      'tax_id_no', nullif(btrim(coalesce(c.tin, '')), ''), 'sst_reg_no', nullif(btrim(coalesce(c.sst_no, '')), ''),
      'email', nullif(btrim(coalesce(c.finance_email, ct.email, '')), ''),
      'phone_no', public.wa_number(coalesce(ct.phone, ct.whatsapp), coalesce(c.market, 'MY')),
      'address', nullif(btrim(coalesce(c.billing_address, '')), ''),
      'country', case when c.market = 'SG' then 'SG' else 'MY' end,
      'currency', case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end,
      'person', nullif(public.bukku_name_case(v_person, false), ''),
      'salutation', nullif(btrim(coalesce(ct.salutation, '')), ''),
      'our_id', c.client_code, 'field_id', b.field_client, 'type', 'customer',
      'contact_id', l.contact_id);
  elsif p_kind = 'supplier' then
    select * into s from public.suppliers x where x.id = p_id;
    if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if s.status <> 'active' then return jsonb_build_object('error', 'not-active'); end if;
    v_company := coalesce(s.kind, 'company') = 'company';
    v_pay := public.ops_granted('suppliers.pay', 'view');
    select * into l from public.bukku_links x where x.kind = 'supplier' and x.record_id = s.id;
    if l.contact_id is null and s.client_id is not null then
      select * into l from public.bukku_links x where x.kind = 'client' and x.record_id = s.client_id;
    end if;
    return jsonb_build_object('ok', true, 'kind', 'supplier', 'id', s.id,
      'legal_name', public.bukku_name_case(s.name, v_company),
      'entity_type', case when s.currency = 'SGD' then (case when v_company then 'FOREIGN_COMPANY' else 'FOREIGN_INDIVIDUAL' end)
                          else (case when v_company then 'MALAYSIAN_COMPANY' else 'MALAYSIAN_INDIVIDUAL' end) end,
      'reg_no_type', case when v_company and s.brn is not null then 'BRN' when not v_company and v_pay and s.nric is not null then 'NRIC' end,
      'reg_no', case when v_company then s.brn when v_pay then regexp_replace(coalesce(s.nric, ''), '[^0-9]', '', 'g') end,
      'tax_id_no', s.tin, 'sst_reg_no', s.sst_no,
      'email', coalesce(s.finance_email, s.email),
      'phone_no', public.wa_number(coalesce(s.mobile, s.phone), case when s.currency = 'SGD' then 'SG' else 'MY' end),
      'address', s.address, 'country', case when s.currency = 'SGD' then 'SG' else 'MY' end,
      'currency', s.currency,
      'person', public.bukku_name_case(coalesce(s.contact_name, case when not v_company then s.name end), false),
      'payment_term', s.payment_term,
      'our_id', s.code, 'field_id', b.field_supplier, 'type', 'supplier',
      'client_id', s.client_id, 'contact_id', l.contact_id);
  elsif p_kind = 'creator' then
    /* A creator is a supplier in Bukku (2026-11-09, Creator R3): sent from
       the payment details approved last, the Creator ID in the Supplier ID
       field; the ID number goes only at Creator payment details View. */
    select * into cr from public.creators x where x.id = p_id;
    if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into rq from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
     order by x.decided_at desc limit 1;
    if rq.id is null then return jsonb_build_object('error', 'no-details'); end if;
    if coalesce(btrim(cr.creator_code), '') = '' then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(array['Creator ID'])); end if;
    v_company := rq.bill_kind = 'brn';
    v_pay := public.ops_granted('campaigns.pay', 'view');
    select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = cr.id;
    return jsonb_build_object('ok', true, 'kind', 'creator', 'id', cr.id,
      'legal_name', public.bukku_name_case(rq.legal_name, v_company), 'other_name', cr.name,
      'entity_type', case when rq.bill_kind = 'passport' or rq.currency = 'SGD'
                          then (case when v_company then 'FOREIGN_COMPANY' else 'FOREIGN_INDIVIDUAL' end)
                          else (case when v_company then 'MALAYSIAN_COMPANY' else 'MALAYSIAN_INDIVIDUAL' end) end,
      'reg_no_type', case when v_company then 'BRN' when v_pay and rq.bill_kind = 'nric' then 'NRIC'
                          when v_pay and rq.bill_kind = 'passport' then 'PASSPORT' end,
      'reg_no', case when v_company or v_pay then nullif(regexp_replace(rq.id_no, '[^0-9A-Za-z]', '', 'g'), '') end,
      'tax_id_no', nullif(btrim(coalesce(rq.tin, '')), ''), 'email', rq.email,
      'phone_no', public.wa_number(coalesce(rq.whatsapp, cr.whatsapp), case when rq.currency = 'SGD' then 'SG' else 'MY' end),
      'address', rq.address, 'country', case when rq.currency = 'SGD' then 'SG' else 'MY' end,
      'currency', rq.currency,
      'person', case when not v_company then public.bukku_name_case(rq.legal_name, false) end,
      'our_id', cr.creator_code, 'field_id', b.field_supplier, 'type', 'supplier',
      'contact_id', l.contact_id);
  elsif p_kind = 'entity' then
    select * into e from public.billing_entities x where x.id = p_id;
    if e.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = public.entity_home_client(e.id);
    ct := public.entity_contact(e.id);
    if coalesce(btrim(e.legal_name), '') = '' then v_missing := v_missing || 'Registered name'::text; end if;
    if coalesce(btrim(c.client_code), '') = '' then v_missing := v_missing || 'Client ID'::text; end if;
    if array_length(v_missing, 1) > 0 then return jsonb_build_object('error', 'incomplete', 'missing', to_jsonb(v_missing)); end if;
    select * into l from public.bukku_links x where x.kind = 'entity' and x.record_id = e.id;
    if l.contact_id is null then l.contact_id := (public.bukku_shared('entity', e.id)->>'contact_id')::bigint; end if;
    v_person := btrim(coalesce(ct.name, ''));
    return jsonb_build_object('ok', true, 'kind', 'entity', 'id', e.id,
      'legal_name', public.bukku_name_case(e.legal_name, true), 'other_name', c.name,
      'entity_type', case when c.market = 'SG' then 'FOREIGN_COMPANY' else 'MALAYSIAN_COMPANY' end,
      'reg_no_type', case when nullif(regexp_replace(coalesce(e.company_no, ''), '[^0-9A-Za-z]', '', 'g'), '') is null then null else 'BRN' end,
      'reg_no', nullif(regexp_replace(coalesce(e.company_no, ''), '[^0-9A-Za-z]', '', 'g'), ''),
      'old_reg_no', nullif(btrim(coalesce(e.company_no_old, '')), ''),
      'tax_id_no', nullif(btrim(coalesce(e.tin, '')), ''), 'sst_reg_no', nullif(btrim(coalesce(e.sst_no, '')), ''),
      'email', nullif(btrim(coalesce(e.finance_email, ct.email, '')), ''),
      'phone_no', public.wa_number(coalesce(ct.phone, ct.whatsapp), coalesce(c.market, 'MY')),
      'address', nullif(btrim(coalesce(e.billing_address, '')), ''),
      'country', case when c.market = 'SG' then 'SG' else 'MY' end,
      'currency', case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end,
      'person', nullif(public.bukku_name_case(v_person, false), ''),
      'salutation', nullif(btrim(coalesce(ct.salutation, '')), ''),
      'our_id', c.client_code, 'field_id', b.field_client, 'type', 'customer',
      'contact_id', l.contact_id);
  end if;
  return jsonb_build_object('error', 'bad-kind');
end $$;
revoke all on function public.bukku_prepare(text, uuid) from public, anon;
grant execute on function public.bukku_prepare(text, uuid) to authenticated;

create or replace function public.bukku_linked(p_kind text, p_id uuid, p_contact bigint, p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); v_name text; v_code text; v_client uuid;
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-contact'); end if;
  if p_kind = 'client' then
    select x.name, x.client_code into v_name, v_code from public.clients x where x.id = p_id;
  elsif p_kind = 'entity' then
    v_name := public.bukku_record_name('entity', p_id);
  elsif p_kind = 'creator' then
    select coalesce(x.name, x.creator_code), x.creator_code into v_name, v_code from public.creators x where x.id = p_id;
  else
    select coalesce(x.name, x.code), x.code, x.client_id into v_name, v_code, v_client from public.suppliers x where x.id = p_id;
  end if;
  if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
  if public.bukku_contact_taken(p_kind, p_id, p_contact) then return jsonb_build_object('error', 'taken'); end if;
  insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
  values (p_kind, p_id, p_contact, left(p_code, 40), now(), me.id, public.bukku_print(p_kind, p_id))
  on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code,
    sent_at = now(), sent_by = excluded.sent_by, sent_hash = excluded.sent_hash;
  /* One contact for a supplier that is also a client. */
  if v_client is not null then
    insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
    values ('client', v_client, p_contact, left(p_code, 40), now(), me.id, null)
    on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code;
  end if;
  if p_kind = 'entity' then
    perform public.bukku_file_entity(p_id, me.name, 'Sent to Bukku · ' || coalesce(p_code, p_contact::text));
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case p_kind when 'client' then 'client.edited' when 'creator' then 'creator.updated' else 'supplier.edited' end, v_name,
            coalesce(v_code || ' · ', '') || 'Sent to Bukku · ' || coalesce(p_code, p_contact::text));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_linked(text, uuid, bigint, text) from public, anon;
grant execute on function public.bukku_linked(text, uuid, bigint, text) to authenticated;

create or replace function public.bukku_link_only(p_kind text, p_id uuid, p_contact bigint, p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); v_name text; v_code text; v_client uuid;
begin
  if not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-contact'); end if;
  if p_kind = 'client' then
    select x.name, x.client_code into v_name, v_code from public.clients x where x.id = p_id;
  elsif p_kind = 'entity' then
    v_name := public.bukku_record_name('entity', p_id);
  elsif p_kind = 'creator' then
    select coalesce(x.name, x.creator_code), x.creator_code into v_name, v_code from public.creators x where x.id = p_id;
  else
    select coalesce(x.name, x.code), x.code, x.client_id into v_name, v_code, v_client from public.suppliers x where x.id = p_id;
  end if;
  if v_name is null then return jsonb_build_object('error', 'not-found'); end if;
  if public.bukku_contact_taken(p_kind, p_id, p_contact) then return jsonb_build_object('error', 'taken'); end if;
  insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
  values (p_kind, p_id, p_contact, left(p_code, 40), now(), me.id, public.bukku_print(p_kind, p_id))
  on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code,
    sent_at = now(), sent_by = excluded.sent_by, sent_hash = excluded.sent_hash;
  /* One contact for a supplier that is also a client. */
  if v_client is not null then
    insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
    values ('client', v_client, p_contact, left(p_code, 40), now(), me.id, null)
    on conflict (kind, record_id) do update set contact_id = excluded.contact_id, code = excluded.code;
  end if;
  if p_kind = 'entity' then
    perform public.bukku_file_entity(p_id, me.name, 'Linked to Bukku, nothing sent · ' || coalesce(p_code, p_contact::text));
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case p_kind when 'client' then 'client.edited' when 'creator' then 'creator.updated' else 'supplier.edited' end, v_name,
            coalesce(v_code || ' · ', '') || 'Linked to Bukku, nothing sent · ' || coalesce(p_code, p_contact::text));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_link_only(text, uuid, bigint, text) from public, anon;
grant execute on function public.bukku_link_only(text, uuid, bigint, text) to authenticated;

-- Rollback: drop the creator_bills_* functions, creator_earlier_job_set,
-- creator_mail_job, creator_bill_option, creator_job_ref, creator_ref_key and
-- the triggers campaign_options_posted and campaign_options_posted_mail with
-- their functions, drop creator_bills and the columns earlier_job,
-- posted_on and pay_by, and run CREATOR PAYMENT DETAILS' and BUKKU BY
-- ENTITY's functions again.

-- END OF CREATOR PAYMENTS ----------------------------------------------------

select public.functions_tidy();
