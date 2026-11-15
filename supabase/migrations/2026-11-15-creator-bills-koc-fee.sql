-- ===========================================================================
-- CREATOR BILLS ON THE KOC FEE ITEM (2026-11-15)
-- ===========================================================================
-- WHY: the user, 2026-11-15: every creator bill the portal makes in Bukku is
-- made as the team's example: the KOC FEE item (SKU P995), the line
-- "KOC Fee - Client: {brand} ({campaign}) ({creator})", classification code
-- 037 and account 6000-03 (Cost of Sales - Influencers). Until now the line
-- copied the item, unit and classification of the creator's last bill.
-- "Dont hardcode anything": each is a Business setting.
--
-- WHAT IT CHANGES
--   * `bukku_settings.bill_item_sku`, `bill_class_code`, `bill_account_code`
--     (the item's SKU, the classification code, the account's code), seeded
--     once P995, 037 and 6000-03; Settings, Money, Bukku edits them.
--   * `bukku_bill_set(p_sku, p_class, p_account, p_account_code, p_name)`
--     (`team.settings`): the three, and the account chosen from Bukku's list
--     kept as before (`bill_account`, `bill_account_name`); `bad-sku`,
--     `bad-class`, `bad-account`; filed under Bukku from and to.
--   * `bukku_bill_account_set` (a tab served before) keeps the account's code
--     with the account it sets.
--   * `bukku_config` answers the three.
--   * `creator_bill_prep` answers the SKU, the classification and account
--     codes, the client's brand, the campaign and the creator's name;
--     `no-account` while no account code is set, `no-item` while no SKU or
--     classification code is. bukku-sync finds the product and the account
--     in Bukku (`no-product`, `no-bukku-account`).
--
-- ORDER: this file, then bukku-sync, then the pages. An older bukku-sync
-- reads none of the new fields and bills as before. Safe to run twice.
--
-- ROLLBACK: restate `bukku_config`, `bukku_bill_account_set` and
-- `creator_bill_prep` from their bands before this one in schema.sql (CREATOR
-- FEES, AUDIT FIXES); the three columns can stay.
-- ===========================================================================

-- CREATOR BILLS ON THE KOC FEE ITEM —

alter table public.bukku_settings add column if not exists bill_item_sku text;
alter table public.bukku_settings add column if not exists bill_class_code text;
alter table public.bukku_settings add column if not exists bill_account_code text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'bukku_settings_bill_item_sku_check') then
    alter table public.bukku_settings add constraint bukku_settings_bill_item_sku_check
      check (bill_item_sku is null or bill_item_sku ~ '^[A-Za-z0-9._/-]{1,40}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bukku_settings_bill_class_code_check') then
    alter table public.bukku_settings add constraint bukku_settings_bill_class_code_check
      check (bill_class_code is null or bill_class_code ~ '^[0-9]{3}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bukku_settings_bill_account_code_check') then
    alter table public.bukku_settings add constraint bukku_settings_bill_account_code_check
      check (bill_account_code is null or bill_account_code ~ '^[A-Za-z0-9._/-]{1,30}$');
  end if;
end $$;

-- Seeded once: a figure the team set is never put back.
insert into public.bukku_settings (id) values (1) on conflict (id) do nothing;
update public.bukku_settings set bill_item_sku = 'P995' where id = 1 and bill_item_sku is null;
update public.bukku_settings set bill_class_code = '037' where id = 1 and bill_class_code is null;
update public.bukku_settings set bill_account_code = '6000-03' where id = 1 and bill_account_code is null;

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
    'field_creator', b.field_creator, 'bill_account', b.bill_account, 'bill_account_name', b.bill_account_name,
    'bill_item_sku', b.bill_item_sku, 'bill_class_code', b.bill_class_code, 'bill_account_code', b.bill_account_code, 'set_at', b.set_at);
end $$;
revoke all on function public.bukku_config() from public, anon;
grant execute on function public.bukku_config() to authenticated;

create or replace function public.bukku_bill_set(p_sku text, p_class text, p_account bigint, p_account_code text, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b public.bukku_settings;
  v_sku text := nullif(btrim(coalesce(p_sku, '')), '');
  v_class text := nullif(btrim(coalesce(p_class, '')), '');
  v_code text := nullif(btrim(coalesce(p_account_code, '')), '');
  v_name text := nullif(left(btrim(coalesce(p_name, '')), 120), '');
  v_said text[] := array[]::text[];
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_sku is null or v_sku !~ '^[A-Za-z0-9._/-]{1,40}$' then return jsonb_build_object('error', 'bad-sku'); end if;
  if v_class is null or v_class !~ '^[0-9]{3}$' then return jsonb_build_object('error', 'bad-class'); end if;
  if v_code is null or v_code !~ '^[A-Za-z0-9._/-]{1,30}$' or (p_account is not null and p_account <= 0) then
    return jsonb_build_object('error', 'bad-account');
  end if;
  select * into b from public.bukku_settings where id = 1 for update;
  if b.bill_item_sku is distinct from v_sku then
    v_said := v_said || ('Creator bill item SKU: ' || coalesce(b.bill_item_sku, 'not set') || ' → ' || v_sku);
  end if;
  if b.bill_class_code is distinct from v_class then
    v_said := v_said || ('Classification code: ' || coalesce(b.bill_class_code, 'not set') || ' → ' || v_class);
  end if;
  if b.bill_account_code is distinct from v_code then
    v_said := v_said || ('Creator bill account: ' || coalesce(b.bill_account_name, b.bill_account_code, 'not set') || ' → ' || coalesce(v_name, v_code));
  end if;
  if cardinality(v_said) = 0 then return jsonb_build_object('ok', true); end if;
  insert into public.bukku_settings (id, bill_item_sku, bill_class_code, bill_account_code, bill_account, bill_account_name, set_by, set_at)
  values (1, v_sku, v_class, v_code, p_account, coalesce(v_name, v_code), me.id, now())
  on conflict (id) do update set bill_item_sku = excluded.bill_item_sku, bill_class_code = excluded.bill_class_code,
    bill_account_code = excluded.bill_account_code,
    bill_account = case when excluded.bill_account_code is distinct from public.bukku_settings.bill_account_code
                        then coalesce(excluded.bill_account, public.bukku_settings.bill_account) else public.bukku_settings.bill_account end,
    bill_account_name = case when excluded.bill_account_code is distinct from public.bukku_settings.bill_account_code
                             then excluded.bill_account_name else public.bukku_settings.bill_account_name end,
    set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Bukku', array_to_string(v_said, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_bill_set(text, text, bigint, text, text) from public, anon;
grant execute on function public.bukku_bill_set(text, text, bigint, text, text) to authenticated;

create or replace function public.bukku_bill_account_set(p_account bigint, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); b public.bukku_settings; v_name text := nullif(left(btrim(coalesce(p_name, '')), 120), '');
  v_code text;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_account is not null and p_account <= 0 then return jsonb_build_object('error', 'bad-value'); end if;
  if p_account is null then v_name := null; end if;
  -- The account's code, as the list names it ("6000-03 · Cost of Sales"), kept with it (2026-11-15).
  v_code := case when position(' · ' in coalesce(v_name, '')) > 0 then nullif(btrim(split_part(v_name, ' · ', 1)), '') end;
  if v_code !~ '^[A-Za-z0-9._/-]{1,30}$' then v_code := null; end if;
  select * into b from public.bukku_settings where id = 1;
  if b.id is not null and b.bill_account is not distinct from p_account then return jsonb_build_object('ok', true); end if;
  insert into public.bukku_settings (id, bill_account, bill_account_name, bill_account_code, set_by, set_at)
  values (1, p_account, v_name, v_code, me.id, now())
  on conflict (id) do update set bill_account = excluded.bill_account, bill_account_name = excluded.bill_account_name,
    bill_account_code = excluded.bill_account_code, set_by = excluded.set_by, set_at = now();
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
  cl public.clients;
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
  -- A fee is billed in the currency the creator is paid in now (audit 2026-11-15).
  if f.currency is distinct from public.creator_pay_currency(o.creator_id) then
    return jsonb_build_object('error', 'currency-changed', 'currency', public.creator_pay_currency(o.creator_id));
  end if;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = o.creator_id;
  if l.contact_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  if exists (select 1 from public.creator_bills x where x.option_id = o.id and not x.gone) then return jsonb_build_object('error', 'billed'); end if;
  select * into b from public.bukku_settings where id = 1;
  -- The bill's item, classification and account are Business settings (2026-11-15).
  if b.bill_account_code is null then return jsonb_build_object('error', 'no-account'); end if;
  if b.bill_item_sku is null or b.bill_class_code is null then return jsonb_build_object('error', 'no-item'); end if;
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
  select * into cl from public.clients x where x.id = m.client_id;
  return jsonb_build_object('ok', true, 'creator', o.creator_id, 'contact_id', l.contact_id, 'amount', f.amount, 'currency', f.currency,
    'fx', v_fx, 'ref', public.creator_job_ref(o.id), 'date', v_today,
    'due', case when o.pay_by >= v_today then o.pay_by end, 'account', b.bill_account,
    'sku', b.bill_item_sku, 'class_code', b.bill_class_code, 'account_code', b.bill_account_code,
    'client_name', coalesce(cl.name, ''), 'campaign', coalesce(nullif(btrim(m.title), ''), 'Creator campaign'), 'creator_name', coalesce(c.name, ''),
    'description', left(coalesce(nullif(btrim(m.title), ''), 'Creator campaign') || ' · ' || coalesce(c.name, ''), 200));
end $$;
revoke all on function public.creator_bill_prep(uuid) from public, anon;
grant execute on function public.creator_bill_prep(uuid) to authenticated;

-- END OF CREATOR BILLS ON THE KOC FEE ITEM ------------------------------------

select public.functions_tidy();
