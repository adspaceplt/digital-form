-- ===========================================================================
-- CREATOR FEES — each booking holds the fee agreed with the creator, which
-- the portal sends to Bukku as the creator's purchase bill and counts in
-- the creator's Totals (2026-11-13)
-- ===========================================================================
-- WHY (the user, 2026-11-13: "client rate is how much i share to clients
-- and charge them; however creator rates are different (could be different
-- in every campaigns) … how would you propose to add the creator rate for
-- creators whereby pre-agreed and this rate would push to bukku. also
-- calculate in the Totals"; "go as recommended"; "no show amount just
-- internal records creator records and bukku bill for payments").
--
-- WHAT CHANGED
--   * `creator_fees` (RLS on, no policy, no grant): a booking's fee agreed
--     with the creator, in the currency of the creator's approved payment
--     details (MYR unless SGD), never the client's rate and never on a
--     client or creator page. `creator_standard_fees` (the same): a
--     creator's standard fee, which a new booking takes (trigger
--     `campaign_options_standard_fee`, source `standard`). A booking whose
--     Bukku bill is read with no fee set takes the bill's amount (trigger
--     `creator_bills_fee`, source `bill`), and the bookings billed before
--     are filled once from their bills.
--   * `creator_fee_set(p_option, p_amount)` and
--     `creator_standard_fee_set(p_creator, p_amount)`: Creator payments at
--     Work; empty clears; `bad-amount`; a fee whose bill exists, or is being
--     made, is refused `billed`; filed `creator.updated` from and to.
--   * `bukku_settings.bill_account` / `bill_account_name`: the Bukku account
--     a creator's bill is posted to, set by `bukku_bill_account_set`
--     (`team.settings`, filed under Bukku); `bukku_config` answers it.
--   * `creator_bill_prep(p_option)` (Creator payments at Work): what
--     `bukku-sync` `createbill` sends, the booking Posted or Completed, its
--     fee above nought, the creator linked, no bill held, the account set,
--     an S$ fee's rate (`fx_sgd`); `not-posted`, `no-fee`, `not-linked`,
--     `billed`, `no-account`, `no-fx`, `creating` (a press within ten
--     minutes, `creator_bill_claims`). `creator_bill_done(p_option,
--     p_number)` lets the press go and, with a number, files it.
--   * `creator_bills_list` answers each booking's fee and the creator's
--     standard fee at Creator payments View, and whether the account is
--     set (`bill_account`); `creator_totals` adds Agreed creator fees,
--     Outstanding (fees of bookings with no paid bill) and Margin (client
--     rate less fee, a currency where both are in it), at Creator payments
--     View alone.
--
-- ORDER: this file (connector), then the pages, then `bukku-sync`. A page
-- served before reads the lists as before (the new keys unread). Safe to
-- run twice.
--
-- ROLLBACK: drop the six new functions and the two triggers; restate
-- `bukku_config` (CREATOR ID FIELD), `creator_bills_list` (CREATOR EARLIER
-- JOBS) and `creator_totals` (CREATOR TOTALS); the tables and columns are
-- left unused.
-- ===========================================================================

-- CREATOR FEES ---------------------------------------------------------------

create table if not exists public.creator_fees (
  option_id uuid primary key references public.campaign_options(id) on delete cascade,
  amount    numeric(12,2) not null check (amount >= 0 and amount <= 1000000),
  currency  text not null check (currency in ('MYR', 'SGD')),
  source    text not null default 'team' check (source in ('team', 'standard', 'bill')),
  set_by    uuid references public.team_members(id) on delete set null,
  set_at    timestamptz not null default now()
);
alter table public.creator_fees enable row level security;
revoke all on table public.creator_fees from public, anon, authenticated;

create table if not exists public.creator_standard_fees (
  creator_id uuid primary key references public.creators(id) on delete cascade,
  amount     numeric(12,2) not null check (amount >= 0 and amount <= 1000000),
  currency   text not null check (currency in ('MYR', 'SGD')),
  set_by     uuid references public.team_members(id) on delete set null,
  set_at     timestamptz not null default now()
);
alter table public.creator_standard_fees enable row level security;
revoke all on table public.creator_standard_fees from public, anon, authenticated;

create table if not exists public.creator_bill_claims (
  option_id  uuid primary key references public.campaign_options(id) on delete cascade,
  claimed_by uuid references public.team_members(id) on delete set null,
  claimed_at timestamptz not null default now()
);
alter table public.creator_bill_claims enable row level security;
revoke all on table public.creator_bill_claims from public, anon, authenticated;

alter table public.bukku_settings add column if not exists bill_account bigint;
alter table public.bukku_settings add column if not exists bill_account_name text;

/* The currency a creator is paid in: their approved payment details', else MYR. */
create or replace function public.creator_pay_currency(p_creator uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select r.currency from public.creator_pay_requests r
                    where r.creator_id = p_creator and r.status = 'approved'
                    order by r.decided_at desc nulls last limit 1), 'MYR')
$$;
revoke all on function public.creator_pay_currency(uuid) from public, anon, authenticated;

/* A fee as the record reads it: RM 1,200.00, S$ 300.00. */
create or replace function public.creator_fee_word(p_amount numeric, p_currency text)
returns text language sql immutable set search_path = public as $$
  select case when p_amount is null then 'not set'
              else case when p_currency = 'SGD' then 'S$ ' else 'RM ' end || to_char(p_amount, 'FM999,999,990.00') end
$$;
revoke all on function public.creator_fee_word(numeric, text) from public, anon, authenticated;

/* A new booking takes the creator's standard fee. */
create or replace function public.campaign_options_standard_fee()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.creator_fees (option_id, amount, currency, source)
  select new.id, s.amount, s.currency, 'standard'
    from public.creator_standard_fees s where s.creator_id = new.creator_id
  on conflict (option_id) do nothing;
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.campaign_options_standard_fee() from public, anon, authenticated;
drop trigger if exists campaign_options_standard_fee on public.campaign_options;
create trigger campaign_options_standard_fee after insert on public.campaign_options
  for each row execute function public.campaign_options_standard_fee();

/* A booking billed in Bukku with no fee set takes the bill's amount. */
create or replace function public.creator_bills_fee()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.option_id is not null and not new.gone and new.amount is not null and coalesce(new.currency, 'MYR') in ('MYR', 'SGD') then
    insert into public.creator_fees (option_id, amount, currency, source)
    values (new.option_id, new.amount, coalesce(new.currency, 'MYR'), 'bill')
    on conflict (option_id) do nothing;
  end if;
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.creator_bills_fee() from public, anon, authenticated;
drop trigger if exists creator_bills_fee on public.creator_bills;
create trigger creator_bills_fee after insert or update of option_id, amount on public.creator_bills
  for each row execute function public.creator_bills_fee();

insert into public.creator_fees (option_id, amount, currency, source)
select distinct on (b.option_id) b.option_id, b.amount, coalesce(b.currency, 'MYR'), 'bill'
  from public.creator_bills b
 where b.option_id is not null and not b.gone and b.amount is not null and coalesce(b.currency, 'MYR') in ('MYR', 'SGD')
 order by b.option_id, b.bill_date desc nulls last
on conflict (option_id) do nothing;

create or replace function public.creator_fee_set(p_option uuid, p_amount numeric)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  f  public.creator_fees;
  c  public.creators;
  v_cur text;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_amount is not null and (p_amount < 0 or p_amount > 1000000 or round(p_amount, 2) <> p_amount) then
    return jsonb_build_object('error', 'bad-amount');
  end if;
  if exists (select 1 from public.creator_bills b where b.option_id = o.id and not b.gone)
     or exists (select 1 from public.creator_bill_claims k where k.option_id = o.id and k.claimed_at > now() - interval '10 minutes') then
    return jsonb_build_object('error', 'billed');
  end if;
  select * into f from public.creator_fees x where x.option_id = o.id;
  v_cur := coalesce(f.currency, public.creator_pay_currency(o.creator_id));
  if p_amount is not distinct from f.amount then return jsonb_build_object('ok', true); end if;
  if p_amount is null then
    delete from public.creator_fees x where x.option_id = o.id;
  else
    v_cur := public.creator_pay_currency(o.creator_id);
    insert into public.creator_fees (option_id, amount, currency, source, set_by, set_at)
    values (o.id, p_amount, v_cur, 'team', me.id, now())
    on conflict (option_id) do update set amount = excluded.amount, currency = excluded.currency, source = 'team',
      set_by = excluded.set_by, set_at = now();
  end if;
  select * into c from public.creators x where x.id = o.creator_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name,
          coalesce(public.creator_job_ref(o.id) || ' · ', '') || 'Creator fee: '
          || public.creator_fee_word(f.amount, f.currency) || ' → ' || public.creator_fee_word(p_amount, v_cur));
  return jsonb_build_object('ok', true, 'amount', p_amount, 'currency', v_cur);
end $$;
revoke all on function public.creator_fee_set(uuid, numeric) from public, anon;
grant execute on function public.creator_fee_set(uuid, numeric) to authenticated;

create or replace function public.creator_standard_fee_set(p_creator uuid, p_amount numeric)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c  public.creators;
  f  public.creator_standard_fees;
  v_cur text;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.creators x where x.id = p_creator;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_amount is not null and (p_amount < 0 or p_amount > 1000000 or round(p_amount, 2) <> p_amount) then
    return jsonb_build_object('error', 'bad-amount');
  end if;
  select * into f from public.creator_standard_fees x where x.creator_id = c.id for update;
  if p_amount is not distinct from f.amount then return jsonb_build_object('ok', true); end if;
  v_cur := public.creator_pay_currency(c.id);
  if p_amount is null then
    delete from public.creator_standard_fees x where x.creator_id = c.id;
  else
    insert into public.creator_standard_fees (creator_id, amount, currency, set_by, set_at)
    values (c.id, p_amount, v_cur, me.id, now())
    on conflict (creator_id) do update set amount = excluded.amount, currency = excluded.currency, set_by = excluded.set_by, set_at = now();
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name,
          coalesce(c.creator_code || ' · ', '') || 'Standard fee: '
          || public.creator_fee_word(f.amount, f.currency) || ' → ' || public.creator_fee_word(p_amount, v_cur));
  return jsonb_build_object('ok', true, 'amount', p_amount, 'currency', v_cur);
end $$;
revoke all on function public.creator_standard_fee_set(uuid, numeric) from public, anon;
grant execute on function public.creator_standard_fee_set(uuid, numeric) to authenticated;

create or replace function public.bukku_config()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b public.bukku_settings;
begin
  if (public.ops_me()).id is null or not (public.allowed('clients.billing', 'work') or public.allowed('suppliers', 'work')
      or public.ops_granted('team.settings', 'work')) then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into b from public.bukku_settings where id = 1;
  return jsonb_build_object('ok', true, 'field_client', b.field_client, 'field_supplier', b.field_supplier,
    'field_creator', b.field_creator, 'bill_account', b.bill_account, 'bill_account_name', b.bill_account_name, 'set_at', b.set_at);
end $$;
revoke all on function public.bukku_config() from public, anon;
grant execute on function public.bukku_config() to authenticated;

create or replace function public.bukku_bill_account_set(p_account bigint, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); b public.bukku_settings; v_name text := nullif(left(btrim(coalesce(p_name, '')), 120), '');
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_account is not null and p_account <= 0 then return jsonb_build_object('error', 'bad-value'); end if;
  if p_account is null then v_name := null; end if;
  select * into b from public.bukku_settings where id = 1;
  if b.id is not null and b.bill_account is not distinct from p_account then return jsonb_build_object('ok', true); end if;
  insert into public.bukku_settings (id, bill_account, bill_account_name, set_by, set_at)
  values (1, p_account, v_name, me.id, now())
  on conflict (id) do update set bill_account = excluded.bill_account, bill_account_name = excluded.bill_account_name,
    set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Bukku', 'Creator bill account: ' || coalesce(b.bill_account_name, 'not set') || ' → ' || coalesce(v_name, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_bill_account_set(bigint, text) from public, anon;
grant execute on function public.bukku_bill_account_set(bigint, text) to authenticated;

create or replace function public.creator_bill_prep(p_option uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  m  public.campaigns;
  c  public.creators;
  f  public.creator_fees;
  l  public.bukku_links;
  b  public.bukku_settings;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_fx numeric := 1;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if o.state not in ('posted', 'completed') then return jsonb_build_object('error', 'not-posted'); end if;
  select * into f from public.creator_fees x where x.option_id = o.id;
  if f.option_id is null or f.amount <= 0 then return jsonb_build_object('error', 'no-fee'); end if;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = o.creator_id;
  if l.contact_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  if exists (select 1 from public.creator_bills x where x.option_id = o.id and not x.gone) then return jsonb_build_object('error', 'billed'); end if;
  select * into b from public.bukku_settings where id = 1;
  if b.bill_account is null then return jsonb_build_object('error', 'no-account'); end if;
  if f.currency = 'SGD' then
    v_fx := nullif(public.app_setting('fx_sgd', v_today), 0);
    if v_fx is null then return jsonb_build_object('error', 'no-fx'); end if;
  end if;
  if exists (select 1 from public.creator_bill_claims k where k.option_id = o.id and k.claimed_at > now() - interval '10 minutes') then
    return jsonb_build_object('error', 'creating');
  end if;
  insert into public.creator_bill_claims (option_id, claimed_by, claimed_at) values (o.id, me.id, now())
  on conflict (option_id) do update set claimed_by = excluded.claimed_by, claimed_at = now();
  select * into m from public.campaigns x where x.id = o.campaign_id;
  select * into c from public.creators x where x.id = o.creator_id;
  return jsonb_build_object('ok', true, 'creator', o.creator_id, 'contact_id', l.contact_id, 'amount', f.amount, 'currency', f.currency,
    'fx', v_fx, 'ref', public.creator_job_ref(o.id), 'date', v_today,
    'due', case when o.pay_by >= v_today then o.pay_by end, 'account', b.bill_account,
    'description', left(coalesce(nullif(btrim(m.title), ''), 'Creator campaign') || ' · ' || coalesce(c.name, ''), 200));
end $$;
revoke all on function public.creator_bill_prep(uuid) from public, anon;
grant execute on function public.creator_bill_prep(uuid) to authenticated;

create or replace function public.creator_bill_done(p_option uuid, p_number text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  f  public.creator_fees;
  c  public.creators;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from public.creator_bill_claims k where k.option_id = o.id;
  if nullif(btrim(coalesce(p_number, '')), '') is not null then
    select * into f from public.creator_fees x where x.option_id = o.id;
    select * into c from public.creators x where x.id = o.creator_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'creator.updated', c.name,
            coalesce(public.creator_job_ref(o.id) || ' · ', '') || 'Bill ' || left(btrim(p_number), 60) || ' created in Bukku · '
            || public.creator_fee_word(f.amount, f.currency));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_bill_done(uuid, text) from public, anon;
grant execute on function public.creator_bill_done(uuid, text) to authenticated;

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
    -- The creator fees (2026-11-13): the standard fee, and whether the
    -- account a bill is posted to is set, at Creator payments View alone.
    'standard_fee', case when v_pay then (select jsonb_build_object('amount', s.amount, 'currency', s.currency)
        from public.creator_standard_fees s where s.creator_id = p_creator) end,
    'bill_account', case when v_pay then exists (select 1 from public.bukku_settings s where s.id = 1 and s.bill_account is not null) end,
    'jobs', coalesce((select jsonb_agg(jsonb_build_object(
        'option', o.id, 'job', public.creator_job_ref(o.id), 'earlier_job', o.earlier_job, 'state', o.state,
        'campaign', m.title, 'campaign_id', m.id, 'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'fee', case when v_pay then (select jsonb_build_object('amount', f.amount, 'currency', f.currency, 'source', f.source)
                 from public.creator_fees f where f.option_id = o.id) end,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = p_creator and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb),
    -- a creator's past job IDs from before the portal, each with the bill
    -- whose reference or number holds it
    'past', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'ref', e.ref,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency)
                   from public.creator_bills b
                  where b.creator_id = p_creator and b.option_id is null and not b.gone
                    and length(public.creator_ref_key(e.ref)) >= 4
                    and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                      or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0)
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by e.ref desc)
        from public.creator_earlier_jobs e where e.creator_id = p_creator and e.removed_at is null), '[]'::jsonb),
    'earlier', coalesce((select jsonb_agg(jsonb_build_object('number', b.number, 'ref', b.ref, 'status', b.status, 'date', b.bill_date,
        'amount', case when v_pay then b.amount end, 'currency', b.currency) order by b.bill_date desc nulls last)
        from public.creator_bills b where b.creator_id = p_creator and b.option_id is null and not b.gone
         and not exists (select 1 from public.creator_earlier_jobs e
                          where e.creator_id = p_creator and e.removed_at is null and length(public.creator_ref_key(e.ref)) >= 4
                            and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                              or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0))), '[]'::jsonb));
end $$;
revoke all on function public.creator_bills_list(uuid) from public, anon;
grant execute on function public.creator_bills_list(uuid) to authenticated;

create or replace function public.creator_totals(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pay boolean := public.ops_granted('campaigns.pay', 'view'); v_camp boolean := public.allowed('campaigns.campaigns', 'view');
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.creators c where c.id = p_creator) then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'pay', v_pay,
    -- What clients were billed for this creator: each booking's client rate
    -- from Confirmed on, in the currency its client is billed in, only on
    -- campaigns the caller may read.
    'billed', case when not v_camp then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end as cur,
                     sum(o.rate) as amt, count(*) as n
                from public.campaign_options o
                join public.campaigns m on m.id = o.campaign_id
                join public.clients c on c.id = m.client_id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
                 and public.client_seen(c.id, 'view')
               group by 1) x), '[]'::jsonb) end,
    -- The fees agreed with the creator, from Confirmed on, in the currency
    -- they are paid in (2026-11-13), at Creator payments View alone.
    'agreed', case when not v_pay then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select f.currency as cur, sum(f.amount) as amt, count(*) as n
                from public.campaign_options o join public.creator_fees f on f.option_id = o.id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
               group by 1) x), '[]'::jsonb) end,
    -- Outstanding: the fees of those bookings no paid bill holds.
    'owed', case when not v_pay then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select f.currency as cur, sum(f.amount) as amt, count(*) as n
                from public.campaign_options o join public.creator_fees f on f.option_id = o.id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
                 and not exists (select 1 from public.creator_bills b where b.option_id = o.id and b.status = 'paid' and not b.gone)
               group by 1) x), '[]'::jsonb) end,
    -- Margin: the client rate less the fee, each booking whose client is
    -- billed in the fee's own currency, never across currencies.
    'margin', case when not (v_pay and v_camp) then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bookings', x.n) order by x.cur)
        from (select f.currency as cur, sum(o.rate - f.amount) as amt, count(*) as n
                from public.campaign_options o
                join public.creator_fees f on f.option_id = o.id
                join public.campaigns m on m.id = o.campaign_id
                join public.clients c on c.id = m.client_id
               where o.creator_id = p_creator
                 and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')
                 and public.client_seen(c.id, 'view')
                 and f.currency = case when public.client_bill_market(c.market, c.bill_sgd) = 'SG' then 'SGD' else 'MYR' end
               group by 1) x), '[]'::jsonb) end,
    -- What was paid to the creator: every bill Bukku reads paid, earlier
    -- jobs included, at Creator payments View alone.
    'paid', case when not v_pay then null else
      coalesce((select jsonb_agg(jsonb_build_object('currency', x.cur, 'amount', x.amt, 'bills', x.n) order by x.cur)
        from (select coalesce(b.currency, 'MYR') as cur, sum(b.amount) as amt, count(*) as n
                from public.creator_bills b
               where b.creator_id = p_creator and b.status = 'paid' and not b.gone
               group by 1) x), '[]'::jsonb) end);
end $$;
revoke all on function public.creator_totals(uuid) from public, anon;
grant execute on function public.creator_totals(uuid) to authenticated;

-- END OF CREATOR FEES --------------------------------------------------------

select public.functions_tidy();
