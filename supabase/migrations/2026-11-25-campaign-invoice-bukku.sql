-- ===========================================================================
-- CAMPAIGN INVOICE FROM BUKKU (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25. A campaign's invoice was typed (AINV and its
-- number) and its PDF uploaded by hand in a form inside the Finance pane.
-- It is now made in Bukku as a draft from the campaign, or an invoice made
-- there is linked to it, and read from Bukku whenever it is shown.
--
-- WHAT CHANGES
--   * `campaigns`: `bukku_invoice_id` (the invoice's Bukku id), and the
--     press held ten minutes (`invoice_claimed_at`, `invoice_claimed_by`).
--     `invoice_no` keeps the number; an invoice typed and uploaded before
--     stays as it was (`invoice_url`), read only.
--   * `bukku_settings.campaign_invoice_model`: the invoice whose line a new
--     one copies (its product, account and tax code), seeded AINV2609023,
--     the user's own on CC002; set in Settings, Accounting, Bukku
--     (`bukku_campaign_model_set`, filed `team.changed`).
--   * `campaign_invoice_prep(p_campaign, p_mode)` as the caller, at
--     Campaigns: Finance Work and the client in scope: the client's Bukku
--     contact (its own link, else the company billing it), the currency,
--     the reference, and for `create` one line a booked creator at the
--     client rate, the press held (`not-linked`, `invoiced`, `nothing`,
--     `no-model`, `no-fx`, `creating`).
--   * `campaign_invoice_take(p_campaign, p_bukku, p_number, p_linked)`
--     files the number (filed `campaign.invoice`), or with no number lets
--     go of the caller's own press.
--   * `campaign_invoice_unlink(p_campaign)`: the link let go, the number
--     with it, filed; nothing changes in Bukku.
--   * `campaign_invoice_read(p_campaign)`: the Bukku id to read, at
--     Campaigns View, the client in scope.
--
-- ORDER: this file (connector), then bukku-sync, then the pages. An old
-- tab keeps its typed number and upload until refreshed. Safe to run twice.
-- ROLLBACK: the functions and columns may stay unused; redeploy the
-- previous bukku-sync and pages.
-- ===========================================================================

-- CAMPAIGN INVOICE FROM BUKKU ------------------------------------------------

alter table public.campaigns add column if not exists bukku_invoice_id bigint;
alter table public.campaigns add column if not exists invoice_claimed_at timestamptz;
alter table public.campaigns add column if not exists invoice_claimed_by uuid;
alter table public.bukku_settings add column if not exists campaign_invoice_model text default 'AINV2609023';

create or replace function public.campaign_invoice_prep(p_campaign uuid, p_mode text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  m public.campaigns;
  cl public.clients;
  b public.bukku_settings;
  v_contact bigint; v_cur text; v_fx numeric := 1; v_lines jsonb;
begin
  if me.id is null or not public.allowed('campaigns.finance', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_mode is null or p_mode not in ('create', 'link') then return jsonb_build_object('error', 'bad-request'); end if;
  select * into m from public.campaigns x where x.id = p_campaign for update;
  if m.id is null or not public.client_scope_ok('campaign', m.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  -- An invoice typed or uploaded before stays as it was (read only).
  if m.bukku_invoice_id is not null or m.invoice_no is not null or m.invoice_url is not null then
    return jsonb_build_object('error', 'invoiced', 'number', m.invoice_no);
  end if;
  select * into cl from public.clients x where x.id = m.client_id;
  select l.contact_id into v_contact from public.bukku_links l where l.kind = 'client' and l.record_id = m.client_id;
  if v_contact is null then v_contact := (public.bukku_shared('client', m.client_id)->>'contact_id')::bigint; end if;
  if v_contact is null then return jsonb_build_object('error', 'not-linked'); end if;
  v_cur := case when upper(coalesce(cl.market, '')) = 'SG' and cl.bill_sgd then 'SGD' else 'MYR' end;
  if p_mode = 'link' then
    return jsonb_build_object('ok', true, 'contact_id', v_contact, 'currency', v_cur);
  end if;
  select * into b from public.bukku_settings where id = 1;
  if nullif(btrim(coalesce(b.campaign_invoice_model, '')), '') is null then return jsonb_build_object('error', 'no-model'); end if;
  if v_cur = 'SGD' then
    v_fx := nullif(public.app_setting('fx_sgd', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0);
    if v_fx is null then return jsonb_build_object('error', 'no-fx'); end if;
  end if;
  -- One line a booked creator at the client rate, in the order they were booked.
  select coalesce(jsonb_agg(jsonb_build_object('label', left(coalesce(c.name, 'Creator') || ' · ' || m.title, 255),
           'amount', o.rate) order by o.position, o.added_at), '[]'::jsonb)
    into v_lines
    from public.campaign_options o left join public.creators c on c.id = o.creator_id
   where o.campaign_id = m.id and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'submitted',
         'reviewing', 'changes', 'scheduled', 'posted', 'completed')
     and not coalesce(o.goodwill, false) and coalesce(o.rate, 0) > 0;
  if jsonb_array_length(v_lines) = 0 then return jsonb_build_object('error', 'nothing'); end if;
  if m.invoice_claimed_at is not null and m.invoice_claimed_at > now() - interval '10 minutes' then
    return jsonb_build_object('error', 'creating');
  end if;
  update public.campaigns x set invoice_claimed_at = now(), invoice_claimed_by = me.id where x.id = m.id;
  return jsonb_build_object('ok', true, 'contact_id', v_contact, 'currency', v_cur, 'fx', v_fx, 'sst', cl.sst_applies,
    'model', btrim(b.campaign_invoice_model), 'lines', v_lines,
    'ref', left(coalesce(nullif(m.campaign_code, '') || ' · ', '') || m.title, 50),
    'date', (now() at time zone 'Asia/Kuala_Lumpur')::date, 'description', left(m.title, 200));
end $$;
revoke all on function public.campaign_invoice_prep(uuid, text) from public, anon;
grant execute on function public.campaign_invoice_prep(uuid, text) to authenticated;

create or replace function public.campaign_invoice_take(p_campaign uuid, p_bukku bigint, p_number text, p_linked boolean)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  m public.campaigns;
  v_num text := nullif(left(btrim(coalesce(p_number, '')), 60), '');
begin
  if me.id is null or not public.allowed('campaigns.finance', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.campaigns x where x.id = p_campaign for update;
  if m.id is null or not public.client_scope_ok('campaign', m.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if v_num is null or coalesce(p_bukku, 0) <= 0 then
    -- a press that made nothing lets go of the caller's own hold alone
    update public.campaigns x set invoice_claimed_at = null, invoice_claimed_by = null
     where x.id = m.id and x.invoice_claimed_by = me.id;
    return jsonb_build_object('ok', true);
  end if;
  if m.bukku_invoice_id is not null and m.bukku_invoice_id <> p_bukku then return jsonb_build_object('error', 'invoiced', 'number', m.invoice_no); end if;
  update public.campaigns x set bukku_invoice_id = p_bukku, invoice_no = v_num, invoice_claimed_at = null, invoice_claimed_by = null
   where x.id = m.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.invoice', m.title, 'Invoice ' || v_num ||
          case when p_linked then ' linked from Bukku' else ' created in Bukku as a draft' end);
  return jsonb_build_object('ok', true, 'number', v_num);
end $$;
revoke all on function public.campaign_invoice_take(uuid, bigint, text, boolean) from public, anon;
grant execute on function public.campaign_invoice_take(uuid, bigint, text, boolean) to authenticated;

create or replace function public.campaign_invoice_unlink(p_campaign uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  m public.campaigns;
begin
  if me.id is null or not public.allowed('campaigns.finance', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.campaigns x where x.id = p_campaign for update;
  if m.id is null or not public.client_scope_ok('campaign', m.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if m.bukku_invoice_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  update public.campaigns x set bukku_invoice_id = null, invoice_no = null where x.id = m.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.invoice', m.title, 'Invoice ' || coalesce(m.invoice_no, '') || ' unlinked');
  return jsonb_build_object('ok', true, 'number', m.invoice_no, 'bukku', m.bukku_invoice_id);
end $$;
revoke all on function public.campaign_invoice_unlink(uuid) from public, anon;
grant execute on function public.campaign_invoice_unlink(uuid) to authenticated;

create or replace function public.campaign_invoice_read(p_campaign uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m public.campaigns;
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.campaigns', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.campaigns x where x.id = p_campaign;
  if m.id is null or not public.client_scope_ok('campaign', m.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if m.bukku_invoice_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  return jsonb_build_object('ok', true, 'bukku', m.bukku_invoice_id, 'number', m.invoice_no);
end $$;
revoke all on function public.campaign_invoice_read(uuid) from public, anon;
grant execute on function public.campaign_invoice_read(uuid) to authenticated;

create or replace function public.bukku_campaign_model_set(p_number text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  b public.bukku_settings;
  v_num text := nullif(upper(btrim(coalesce(p_number, ''))), '');
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_num is not null and v_num !~ '^[A-Z0-9._/-]{3,40}$' then return jsonb_build_object('error', 'bad-number'); end if;
  select * into b from public.bukku_settings where id = 1 for update;
  if b.campaign_invoice_model is not distinct from v_num then return jsonb_build_object('ok', true); end if;
  insert into public.bukku_settings (id, campaign_invoice_model, set_by, set_at) values (1, v_num, me.id, now())
  on conflict (id) do update set campaign_invoice_model = excluded.campaign_invoice_model, set_by = excluded.set_by, set_at = now();
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Bukku', 'Campaign invoice model: ' || coalesce(b.campaign_invoice_model, 'not set') || ' → ' || coalesce(v_num, 'not set'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_campaign_model_set(text) from public, anon;
grant execute on function public.bukku_campaign_model_set(text) to authenticated;

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
    'bill_item_sku', b.bill_item_sku, 'bill_class_code', b.bill_class_code, 'bill_account_code', b.bill_account_code,
    'budget_account_code', b.budget_account_code, 'campaign_invoice_model', b.campaign_invoice_model, 'set_at', b.set_at);
end $$;
revoke all on function public.bukku_config() from public, anon;
grant execute on function public.bukku_config() to authenticated;

-- END OF CAMPAIGN INVOICE FROM BUKKU -----------------------------------------

select public.functions_tidy();
