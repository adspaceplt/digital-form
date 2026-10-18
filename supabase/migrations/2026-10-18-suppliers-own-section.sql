-- ===========================================================================
-- SUPPLIERS, A SECTION OF THEIR OWN — Suppliers leave Documents for the rail,
-- and a supplier is named by its own form (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18: "own section"; on New supplier asking the
-- name: "i wont know the company name first lol, needs them to fill in")
--
-- WHAT IT CHANGES
--   * The section `suppliers` (View, Work, Manage) in place of the part
--     `register.suppliers`, and the granted part `suppliers.pay` in place of
--     `register.supplier_pay`. Every group keeps what it held: `suppliers`
--     takes the old part's level, else Documents' (which the part followed),
--     and `suppliers.pay` the old granted part's; the old keys are taken off.
--     `team_role_sync` copies each group's map onto its colleagues.
--   * Every supplier function asks the new keys; `register_may('supplier',
--     …)` answers `suppliers`, so a supplier's letters follow the section.
--   * `suppliers.name` may be empty until the supplier's own form names it:
--     New supplier asks the Supplier ID alone; Approve waits for a name; a
--     supplier with no name is named by its Supplier ID where one is filed,
--     and Delete takes the Supplier ID typed back.
--   * Payment terms take NET 14, and `supplier_number_ok` holds Office /
--     mobile to a Malaysian or Singapore number and Mobile / WhatsApp to a
--     mobile (the user, 2026-10-18); the BRN (12 digits), NRIC
--     (XXXXXX-XX-XXXX) and SST no. (AXX-XXXX-XXXXXXXX) rules stand.
--   * `rail_order_set()` knows `suppliers`, so Arrange sections can place it.
--   * `activity_section()` files `supplier.*` under Suppliers
--     (`activity.suppliers`, which follows the Activity record's level as
--     every tab does).
--
-- ORDER: this file, then the pages. A page served before it asks the old
-- keys, which then fall back to Documents' level: it keeps working for the
-- groups that hold Documents. `supplier_delete` holds a delete the Supabase
-- connector stops on: it is run in the SQL Editor.
-- Safe to run twice. Rollback: 2026-10-18-suppliers.sql's functions, and
-- each group's `suppliers` / `suppliers.pay` written back as
-- `register.suppliers` / `register.supplier_pay`.
-- ===========================================================================

alter table public.suppliers alter column name drop not null;

/* Each group's access to suppliers, carried across. An admin group holds
   everything already and is left as it is. */
update public.team_roles r
   set access = (r.access - 'register.suppliers' - 'register.supplier_pay')
     || jsonb_build_object('suppliers', coalesce(r.access ->> 'register.suppliers', r.access ->> 'register', 'none'))
     || case when r.access ? 'register.supplier_pay' then jsonb_build_object('suppliers.pay', r.access ->> 'register.supplier_pay') else '{}'::jsonb end
 where not r.is_admin and not (r.access ? 'suppliers');

create or replace function public.register_may(p_family text, p_level text)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
    when p_family = 'hr'       then public.allowed('register.hr', p_level)
    when p_family = 'other'    then public.allowed('register.documents', p_level)
    when p_family = 'supplier' then public.allowed('suppliers', p_level)
    else public.allowed('register.documents', p_level) or public.allowed('clients.documents', p_level)
  end
$$;
grant execute on function public.register_may(text, text) to authenticated;

create or replace function public.suppliers_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(public.supplier_json(s, false) || jsonb_build_object('waiting', exists (
             select 1 from public.supplier_forms f
              where f.supplier_id = s.id and f.voided_at is null and f.submitted_at is not null and f.used_at is null))
           order by upper(s.code))
      from public.suppliers s), '[]'::jsonb));
end $$;
revoke all on function public.suppliers_list() from public, anon;
grant execute on function public.suppliers_list() to authenticated;

create or replace function public.supplier_get(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s   public.suppliers;
  f   public.supplier_forms;
  pay boolean := public.ops_granted('suppliers.pay', 'view');
  work boolean := public.allowed('suppliers', 'work');
  a   jsonb;
begin
  if (public.ops_me()).id is null or not public.allowed('suppliers', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into s from public.suppliers x where x.id = p_id;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into f from public.supplier_forms x where x.supplier_id = p_id and x.voided_at is null
   order by x.created_at desc limit 1;
  a := f.answers;
  if a is not null and not pay then
    a := a - array['nric', 'payee_name', 'bank_name', 'bank_account', 'swift', 'bank_address'];
  end if;
  return jsonb_build_object('ok', true, 'pay', pay, 'supplier', public.supplier_json(s, pay),
    'form', case when f.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', f.id,
      'key', case when work and f.submitted_at is null and f.expires_at > now() then f.access_key end,
      'state', case when f.used_at is not null then 'used' when f.submitted_at is not null then 'submitted'
                    when f.expires_at <= now() then 'expired' else 'open' end,
      'created_at', f.created_at, 'expires_at', f.expires_at, 'submitted_at', f.submitted_at, 'used_at', f.used_at,
      'answers', case when f.submitted_at is not null then a end)) end);
end $$;
revoke all on function public.supplier_get(uuid) from public, anon;
grant execute on function public.supplier_get(uuid) to authenticated;

create or replace function public.supplier_link(p_id uuid, p_reset boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  f     public.supplier_forms;
  v_key text;
  v_days int;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into f from public.supplier_forms x
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null and x.expires_at > now()
   order by x.created_at desc limit 1;
  if f.id is not null and not coalesce(p_reset, false) then
    return jsonb_build_object('ok', true, 'id', f.id, 'key', f.access_key, 'expires_at', f.expires_at);
  end if;
  update public.supplier_forms x set voided_at = now()
   where x.supplier_id = p_id and x.voided_at is null and x.submitted_at is null;
  loop
    v_key := public.new_link_key();
    exit when not exists (select 1 from public.supplier_forms x where x.access_key = v_key);
  end loop;
  v_days := coalesce(public.app_setting('details_form_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 14)::int;
  insert into public.supplier_forms (supplier_id, access_key, created_by, expires_at)
  values (p_id, v_key, me.id, now() + make_interval(days => v_days))
  returning * into f;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', coalesce(s.name, s.code),
          s.code || ' · ' || case when coalesce(p_reset, false) then 'Details form link reset' else 'Details form link created' end);
  return jsonb_build_object('ok', true, 'id', f.id, 'key', f.access_key, 'expires_at', f.expires_at);
end $$;
revoke all on function public.supplier_link(uuid, boolean) from public, anon;
grant execute on function public.supplier_link(uuid, boolean) to authenticated;

create or replace function public.supplier_create(p_code text, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
  v_name text := nullif(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), '');
  v_id   uuid;
  r      jsonb;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_code !~ '^[A-Z0-9]{2,12}$' then return jsonb_build_object('error', 'bad-code'); end if;
  if v_name is not null and (length(v_name) < 2 or length(v_name) > 160) then return jsonb_build_object('error', 'bad-name'); end if;
  if exists (select 1 from public.suppliers s where upper(s.code) = v_code) then
    return jsonb_build_object('error', 'code-taken', 'name', (select s.name from public.suppliers s where upper(s.code) = v_code));
  end if;
  insert into public.suppliers (code, name, created_by) values (v_code, v_name, me.id) returning id into v_id;
  insert into public.activity_log (actor, action, subject, detail) values (me.name, 'supplier.added', coalesce(v_name, v_code), v_code);
  r := public.supplier_link(v_id, false);
  return jsonb_build_object('ok', true, 'id', v_id, 'key', r->>'key', 'expires_at', r->'expires_at');
end $$;
revoke all on function public.supplier_create(text, text) from public, anon;
grant execute on function public.supplier_create(text, text) to authenticated;

create or replace function public.supplier_save(p_id uuid, p_values jsonb, p_form uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.suppliers;
  pay   boolean := public.ops_granted('suppliers.pay', 'work');
  v     jsonb;
  v_code text := upper(regexp_replace(coalesce(p_values->>'code', ''), '\s+', '', 'g'));
  moved text[] := '{}';
  k     text;
  word  constant jsonb := '{"code":"Supplier ID","name":"Name","kind":"Type","brn":"BRN","tin":"TIN","sst_no":"SST no.",
    "phone":"Office / mobile","address":"Billing address","contact_name":"Legal name","designation":"Designation",
    "email":"Email","mobile":"Mobile / WhatsApp","payment_term":"Payment term","currency":"Currency",
    "finance_email":"Finance email","nric":"NRIC","payee_name":"Payee name","bank_name":"Bank",
    "bank_account":"Account number","swift":"SWIFT code","bank_address":"Bank address"}';
  secret constant text[] := array['nric', 'payee_name', 'bank_name', 'bank_account', 'swift', 'bank_address'];
  was   jsonb;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_code !~ '^[A-Z0-9]{2,12}$' then return jsonb_build_object('error', 'bad-code'); end if;
  if exists (select 1 from public.suppliers x where upper(x.code) = v_code and x.id <> p_id) then
    return jsonb_build_object('error', 'code-taken', 'name', (select x.name from public.suppliers x where upper(x.code) = v_code));
  end if;
  v := public.supplier_values_check(coalesce(p_values, '{}'::jsonb), pay);
  if v ? 'error' then return v; end if;
  v := v || jsonb_build_object('code', v_code);
  was := to_jsonb(s);
  for k in select jsonb_object_keys(v) loop
    if (was->>k) is distinct from (v->>k) then
      moved := moved || case when k = any (secret) then (word->>k)
        else (word->>k) || ': ' || coalesce(was->>k, 'not set') || ' → ' || coalesce(v->>k, 'not set') end;
    end if;
  end loop;
  update public.suppliers x set
    code = v_code, name = v->>'name', kind = v->>'kind', brn = v->>'brn', tin = v->>'tin', sst_no = v->>'sst_no',
    phone = v->>'phone', address = v->>'address', contact_name = v->>'contact_name', designation = v->>'designation',
    email = v->>'email', mobile = v->>'mobile', payment_term = v->>'payment_term', currency = v->>'currency',
    finance_email = v->>'finance_email',
    nric = case when pay then v->>'nric' else x.nric end,
    payee_name = case when pay then v->>'payee_name' else x.payee_name end,
    bank_name = case when pay then v->>'bank_name' else x.bank_name end,
    bank_account = case when pay then v->>'bank_account' else x.bank_account end,
    swift = case when pay then v->>'swift' else x.swift end,
    bank_address = case when pay then v->>'bank_address' else x.bank_address end,
    updated_at = now()
   where x.id = p_id;
  if p_form is not null then
    update public.supplier_forms f set used_at = coalesce(f.used_at, now()), used_by = coalesce(f.used_by, me.id)
     where f.id = p_form and f.supplier_id = p_id and f.submitted_at is not null;
  end if;
  if array_length(moved, 1) is not null then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'supplier.edited', v->>'name', v_code || ' · ' || array_to_string(moved, ' · ') ||
            case when p_form is not null then ' · from the details form' else '' end);
  end if;
  return jsonb_build_object('ok', true, 'supplier',
    public.supplier_json((select x from public.suppliers x where x.id = p_id), public.ops_granted('suppliers.pay', 'view')));
end $$;
revoke all on function public.supplier_save(uuid, jsonb, uuid) from public, anon;
grant execute on function public.supplier_save(uuid, jsonb, uuid) to authenticated;

create or replace function public.supplier_set_status(p_id uuid, p_status text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.suppliers;
begin
  if me.id is null or not public.allowed('suppliers', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_status not in ('active', 'inactive') then return jsonb_build_object('error', 'bad-status'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if s.status = p_status then return jsonb_build_object('ok', true, 'status', s.status); end if;
  if p_status = 'active' and (s.name is null or s.kind is null or s.tin is null or s.address is null or s.email is null
      or s.payment_term is null or s.bank_account is null) then
    return jsonb_build_object('error', 'incomplete');
  end if;
  update public.suppliers x set status = p_status, updated_at = now(),
    approved_at = case when p_status = 'active' and x.approved_at is null then now() else x.approved_at end,
    approved_by = case when p_status = 'active' and x.approved_at is null then me.id else x.approved_by end
   where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, case when s.status = 'pending' then 'supplier.approved' else 'supplier.edited' end, coalesce(s.name, s.code),
          s.code || ' · ' || initcap(s.status) || ' → ' || initcap(p_status));
  return jsonb_build_object('ok', true, 'status', p_status);
end $$;
revoke all on function public.supplier_set_status(uuid, text) from public, anon;
grant execute on function public.supplier_set_status(uuid, text) to authenticated;

create or replace function public.supplier_form_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f public.supplier_forms;
  s public.suppliers;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into f from public.supplier_forms x where x.access_key = p_key and x.voided_at is null;
  if f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  select * into s from public.suppliers x where x.id = f.supplier_id;
  return jsonb_build_object('ok', true, 'name', s.name, 'code', s.code, 'expires_at', f.expires_at);
end $$;
revoke all on function public.supplier_form_read(text) from public;
grant execute on function public.supplier_form_read(text) to anon, authenticated;

create or replace function public.supplier_form_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f public.supplier_forms;
  s public.suppliers;
  v jsonb;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into f from public.supplier_forms x where x.access_key = p_key and x.voided_at is null for update;
  if f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if coalesce(p_answers->>'authorise', '') <> 'true' then return jsonb_build_object('error', 'bad-authorise'); end if;
  v := public.supplier_values_check(coalesce(p_answers, '{}'::jsonb), true);
  if v ? 'error' then return v; end if;
  update public.supplier_forms x set submitted_at = now(), answers = jsonb_strip_nulls(v) where x.id = f.id;
  select * into s from public.suppliers x where x.id = f.supplier_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (v->>'contact_name', 'supplier.edited', coalesce(s.name, v->>'name'), s.code || ' · Details received on the details form');
  insert into public.ops_notifications (team_member_id, kind, title, body, supplier_id, dedupe_key)
  select m.id, 'supplier.details', 'Supplier details received · ' || coalesce(s.name, v->>'name'),
         'From ' || (v->>'contact_name') || '. Review them on the supplier.',
         s.id, 'supplier.details:' || f.id || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or public.level_rank(m.access ->> 'suppliers') >= 2)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_form_submit(text, jsonb) from public;
grant execute on function public.supplier_form_submit(text, jsonb) to anon, authenticated;

create or replace function public.supplier_delete(p_id uuid, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.suppliers;
begin
  if me.id is null or not public.allowed('suppliers', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.suppliers x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(btrim(coalesce(s.name, s.code))) then return jsonb_build_object('error', 'bad-name'); end if;
  delete from public.suppliers x where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail) values (me.name, 'supplier.deleted', coalesce(s.name, s.code), s.code);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.supplier_delete(uuid, text) from public, anon;
grant execute on function public.supplier_delete(uuid, text) to authenticated;

/* Suppliers may be placed in a colleague's own order of the rail. */
create or replace function public.rail_order_set(p_sections text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
  v_list text[] := coalesce(p_sections, '{}');
  v_known constant text[] := array['work', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp',
    'register', 'suppliers', 'links', 'services', 'team', 'handbook'];
begin
  me := public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if exists (select 1 from unnest(v_list) k where k is null or not (k = any(v_known)))
     or (select count(distinct k) from unnest(v_list) k) <> cardinality(v_list) then
    return jsonb_build_object('error', 'bad-order');
  end if;
  insert into public.rail_orders (member_id, sections, updated_at) values (me.id, v_list, now())
  on conflict (member_id) do update set sections = excluded.sections, updated_at = now();
  return jsonb_build_object('sections', to_jsonb(v_list));
end $$;
grant execute on function public.rail_order_set(text[]) to authenticated;

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.file_deleted', 'campaign.file_hidden',
                    'campaign.file_shown', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.quotation', 'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_deleted', 'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template') then 'whatsapp'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('supplier.added', 'supplier.approved', 'supplier.deleted', 'supplier.edited') then 'suppliers'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.month', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('script.approved', 'script.changes', 'script.created', 'script.deleted',
                    'script.link', 'script.saved', 'script.shared', 'script.shot',
                    'script.unshared') then 'scripts'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on', 'service.published') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;


-- Payment terms take NET 14 (the user, 2026-10-18), and a number is a
-- Malaysian or Singapore one: an office line or a mobile for Office /
-- mobile, a mobile alone for Mobile / WhatsApp, with or without its
-- country code.
alter table public.suppliers drop constraint if exists suppliers_payment_term_check;
alter table public.suppliers add constraint suppliers_payment_term_check
  check (payment_term in ('NET 7', 'NET 14', 'NET 30', 'NET 45', 'NET 60'));

create or replace function public.supplier_number_ok(p text, p_mobile boolean)
returns boolean
language plpgsql immutable set search_path = public as $$
declare
  d text := regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g');
  sg text;
  my text;
begin
  if length(d) = 8 then sg := d;
  elsif length(d) = 10 and d ~ '^65' then sg := substr(d, 3);
  elsif d ~ '^0' then my := d;
  elsif d ~ '^60' then my := '0' || substr(d, 3);
  end if;
  if sg is not null then return sg ~ (case when p_mobile then '^[89][0-9]{7}$' else '^[689][0-9]{7}$' end); end if;
  if my is null then return false; end if;
  return my ~ '^01[0-9]{8,9}$' or (not p_mobile and my ~ '^0[3-9][0-9]{7,8}$');
end $$;
revoke all on function public.supplier_number_ok(text, boolean) from public, anon, authenticated;

create or replace function public.supplier_values_check(p jsonb, p_pay boolean)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  o jsonb := '{}'::jsonb;
  v text;
  k text;
  kind text := nullif(btrim(coalesce(p->>'kind', '')), '');
  banks constant text[] := array['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank',
    'Bank Islam', 'Public Bank', 'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital',
    '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB', '[SG] CIMB', '[SG] Maybank', '[SG] Bank of China'];
  mail constant text := '^[^@\s]+@[^@\s]+\.[^@\s]+$';
begin
  if kind is null or kind not in ('company', 'individual') then return jsonb_build_object('error', 'bad-kind'); end if;
  o := o || jsonb_build_object('kind', kind);
  v := btrim(regexp_replace(coalesce(p->>'name', ''), '\s+', ' ', 'g'));
  if length(v) < 2 or length(v) > 160 then return jsonb_build_object('error', 'bad-name'); end if;
  o := o || jsonb_build_object('name', v);
  v := regexp_replace(coalesce(p->>'brn', ''), '[^0-9]', '', 'g');
  if (kind = 'company' or v <> '') and v !~ '^[0-9]{12}$' then return jsonb_build_object('error', 'bad-brn'); end if;
  o := o || jsonb_build_object('brn', nullif(v, ''));
  v := upper(regexp_replace(coalesce(p->>'tin', ''), '\s+', '', 'g'));
  if v !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  o := o || jsonb_build_object('tin', v);
  v := upper(regexp_replace(coalesce(p->>'sst_no', ''), '\s+', '', 'g'));
  if v <> '' and v !~ '^[A-Z][0-9]{2}-[0-9]{4}-[0-9]{8}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  o := o || jsonb_build_object('sst_no', nullif(v, ''));
  foreach k in array array['phone', 'mobile'] loop
    if not public.supplier_number_ok(p->>k, k = 'mobile') then return jsonb_build_object('error', 'bad-' || k); end if;
    o := o || jsonb_build_object(k, btrim(p->>k));
  end loop;
  v := btrim(coalesce(p->>'address', ''));
  if length(v) < 10 or length(v) > 400 then return jsonb_build_object('error', 'bad-address'); end if;
  o := o || jsonb_build_object('address', v);
  foreach k in array array['contact_name', 'designation'] loop
    v := btrim(regexp_replace(coalesce(p->>k, ''), '\s+', ' ', 'g'));
    if length(v) < 2 or length(v) > 80 then return jsonb_build_object('error', 'bad-' || k); end if;
    o := o || jsonb_build_object(k, v);
  end loop;
  foreach k in array array['email', 'finance_email'] loop
    v := lower(btrim(coalesce(p->>k, '')));
    if v !~ mail or length(v) > 160 then return jsonb_build_object('error', 'bad-' || k); end if;
    o := o || jsonb_build_object(k, v);
  end loop;
  v := coalesce(p->>'payment_term', '');
  if v not in ('NET 7', 'NET 14', 'NET 30', 'NET 45', 'NET 60') then return jsonb_build_object('error', 'bad-payment_term'); end if;
  o := o || jsonb_build_object('payment_term', v);
  v := coalesce(nullif(p->>'currency', ''), 'MYR');
  if v not in ('MYR', 'SGD') then return jsonb_build_object('error', 'bad-currency'); end if;
  o := o || jsonb_build_object('currency', v);
  if not p_pay then return o; end if;
  v := regexp_replace(coalesce(p->>'nric', ''), '[^0-9]', '', 'g');
  if kind = 'individual' then
    if v !~ '^[0-9]{12}$' then return jsonb_build_object('error', 'bad-nric'); end if;
    o := o || jsonb_build_object('nric', substr(v, 1, 6) || '-' || substr(v, 7, 2) || '-' || substr(v, 9, 4));
  else
    o := o || jsonb_build_object('nric', null);
  end if;
  v := btrim(regexp_replace(coalesce(p->>'payee_name', ''), '\s+', ' ', 'g'));
  if length(v) < 2 or length(v) > 120 then return jsonb_build_object('error', 'bad-payee_name'); end if;
  o := o || jsonb_build_object('payee_name', v);
  v := coalesce(p->>'bank_name', '');
  if not (v = any (banks)) then return jsonb_build_object('error', 'bad-bank_name'); end if;
  o := o || jsonb_build_object('bank_name', v);
  v := regexp_replace(coalesce(p->>'bank_account', ''), '[\s-]', '', 'g');
  if v !~ '^[0-9]{6,20}$' then return jsonb_build_object('error', 'bad-bank_account'); end if;
  o := o || jsonb_build_object('bank_account', v);
  v := upper(regexp_replace(coalesce(p->>'swift', ''), '\s+', '', 'g'));
  if v <> '' and v !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then return jsonb_build_object('error', 'bad-swift'); end if;
  o := o || jsonb_build_object('swift', nullif(v, ''));
  v := btrim(coalesce(p->>'bank_address', ''));
  if length(v) > 300 then return jsonb_build_object('error', 'bad-bank_address'); end if;
  o := o || jsonb_build_object('bank_address', nullif(v, ''));
  return o;
end $$;
revoke all on function public.supplier_values_check(jsonb, boolean) from public, anon, authenticated;

-- END OF SUPPLIERS, A SECTION OF THEIR OWN ---------------------------------
select public.functions_tidy();
