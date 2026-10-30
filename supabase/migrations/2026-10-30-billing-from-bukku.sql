-- ===========================================================================
-- BILLING FROM BUKKU — once a client or a billing entity is linked, Bukku
-- holds its billing details: the portal reads them and saves every change
-- to Bukku (2026-10-30)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "why not billing details we use Bukku's will
-- do so we dont need two sides update … Formal billing and einvoice would
-- always finalize at bukku"; the mockup approved 2026-10-30, option A):
-- a linked client's billing was kept twice, in the portal and in Bukku,
-- and drifted (Details changed) until somebody pressed Send to Bukku.
--
-- WHAT CHANGED
--   * `bukku_links` remembers what was last read from Bukku: `read_at`,
--     `read_hash` (the save's stale check), `person` (Bukku's billing
--     person, shown where Contacts holds nobody of that name) and
--     `held_at`, the moment Bukku became the record's holder.
--   * A link is held once the portal and Bukku agree: a Send to Bukku
--     holds it (the portal's details are what Bukku now has); a link made
--     with Link only, or one standing before this release, is held at its
--     first read where every detail that differs is empty in the portal,
--     else it waits on Send to Bukku or Use Bukku's, never overwritten.
--   * `bukku_take` (the service role's, called by `bukku-sync` after it
--     reads Bukku) writes Bukku's details into the record's billing: a
--     brand's primary entity (carried to the brand by
--     `billing_entity_mirror`), or the entity itself; the billing contact
--     follows the Bukku billing person where Contacts holds that name.
--     Filed `client.billing` naming the fields alone: Read from Bukku (by
--     Bukku), Saved to Bukku, Took Bukku's details.
--   * `bukku_read_may` answers, as the caller at Clients: Billing View or
--     Work, the contact to read and what the portal holds;
--     `bukku_prepare_with` is `bukku_prepare` with the Billing sheet's
--     values over the record's, checked, for a save to Bukku.
--   * `bukku_link_get` answers `held`, `read_at` and `person` too.
--   * Every held link is read again each night at 00:30 MYT (pg_cron
--     `bukku-read-nightly` wakes `bukku-sync` with the wake secret;
--     `bukku_held_links` lists them, the oldest read first).
--   * Suppliers are unchanged: Send to Bukku as before.
--
-- ORDER: this file (connector), then bukku-sync, then the pages. An old
-- page reads as before: every answer only gains keys, and no column a page
-- reads changes shape. Safe to run twice.
--
-- ROLLBACK: select cron.unschedule('bukku-read-nightly'); drop the five
-- functions above and bukku_nightly_kick, bukku_link_row, bukku_portal,
-- bukku_person_contact; run BUKKU BY ENTITY's bukku_link_get again; the
-- four columns may stay (nothing else reads them).
-- ===========================================================================

-- BILLING FROM BUKKU --------------------------------------------------------

alter table public.bukku_links add column if not exists read_at timestamptz;
alter table public.bukku_links add column if not exists read_hash text;
alter table public.bukku_links add column if not exists held_at timestamptz;
alter table public.bukku_links add column if not exists person text;

/* The link a client or an entity reads through: its own, else its
   company's (`bukku_shared`: a brand its primary entity's, an entity the
   brand's it is the primary of). Internal. */
create or replace function public.bukku_link_row(p_kind text, p_id uuid)
returns public.bukku_links
language plpgsql stable security definer set search_path = public as $$
declare l public.bukku_links;
begin
  select * into l from public.bukku_links x where x.kind = p_kind and x.record_id = p_id;
  if l.contact_id is not null then return l; end if;
  if p_kind = 'client' then
    select * into l from public.bukku_links x where x.kind = 'entity' and x.record_id = public.client_main_entity(p_id);
  elsif p_kind = 'entity' then
    select x.* into l from public.client_entities ce
      join public.bukku_links x on x.kind = 'client' and x.record_id = ce.client_id
      join public.clients c on c.id = ce.client_id
     where ce.entity_id = p_id and ce.is_main
     order by c.name limit 1;
  end if;
  return l;
end $$;
revoke all on function public.bukku_link_row(text, uuid) from public, anon, authenticated;

/* What the portal holds of a client's or an entity's billing, as Bukku
   reads it: the billing person with their salutation. Internal. */
create or replace function public.bukku_portal(p_kind text, p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.clients; e public.billing_entities; k public.client_contacts; v_market text;
begin
  if p_kind = 'client' then
    select * into c from public.clients x where x.id = p_id;
    if c.id is null then return null; end if;
    select * into k from public.client_contacts x where x.id = c.bill_contact_id and x.archived_at is null;
    if k.id is null then
      select * into k from public.client_contacts x where x.client_id = c.id and x.is_primary and x.archived_at is null limit 1;
    end if;
    return jsonb_build_object('legal_name', c.legal_name, 'company_no', c.company_no, 'company_no_old', c.company_no_old,
      'tin', c.tin, 'sst_no', c.sst_no, 'finance_email', c.finance_email, 'billing_address', c.billing_address,
      'person', nullif(public.contact_named(k.salutation, k.name), ''),
      'country', case when c.market = 'SG' then 'SG' else 'MY' end);
  elsif p_kind = 'entity' then
    select * into e from public.billing_entities x where x.id = p_id;
    if e.id is null then return null; end if;
    k := public.entity_contact(e.id);
    select x.market into v_market from public.clients x where x.id = public.entity_home_client(e.id);
    return jsonb_build_object('legal_name', e.legal_name, 'company_no', e.company_no, 'company_no_old', e.company_no_old,
      'tin', e.tin, 'sst_no', e.sst_no, 'finance_email', e.finance_email, 'billing_address', e.billing_address,
      'person', nullif(public.contact_named(k.salutation, k.name), ''),
      'country', case when v_market = 'SG' then 'SG' else 'MY' end);
  end if;
  return null;
end $$;
revoke all on function public.bukku_portal(text, uuid) from public, anon, authenticated;

/* The contact a Bukku billing person names: one of the client's (an
   entity's: of a brand it bills) whose name, or name with its salutation,
   is the same words. None where nobody is. Internal. */
create or replace function public.bukku_person_contact(p_kind text, p_id uuid, p_person text)
returns public.client_contacts
language sql stable security definer set search_path = public as $$
  with w as (select btrim(regexp_replace(lower(coalesce(p_person, '')), '[^a-z0-9]+', ' ', 'g')) as p)
  select k.* from public.client_contacts k, w
   where w.p <> '' and k.archived_at is null
     and (case when p_kind = 'client' then k.client_id = p_id
               else k.client_id in (select ce.client_id from public.client_entities ce where ce.entity_id = p_id) end)
     and w.p in (btrim(regexp_replace(lower(coalesce(k.name, '')), '[^a-z0-9]+', ' ', 'g')),
                 btrim(regexp_replace(lower(public.contact_named(k.salutation, k.name)), '[^a-z0-9]+', ' ', 'g')))
   order by k.is_primary desc, k.name
   limit 1
$$;
revoke all on function public.bukku_person_contact(text, uuid, text) from public, anon, authenticated;

create or replace function public.bukku_read_may(p_kind text, p_id uuid, p_level text default 'view')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.bukku_links; me public.team_members := public.ops_me();
begin
  if p_kind not in ('client', 'entity') or p_level not in ('view', 'work')
     or not public.bukku_may(p_kind, p_id, p_level) then
    return jsonb_build_object('error', 'denied');
  end if;
  if public.bukku_record_name(p_kind, p_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  l := public.bukku_link_row(p_kind, p_id);
  if l.contact_id is null then return jsonb_build_object('ok', true, 'linked', false); end if;
  return jsonb_build_object('ok', true, 'linked', true, 'me', me.id, 'contact_id', l.contact_id, 'code', l.code,
    'held', l.held_at is not null, 'read_at', l.read_at, 'read_hash', l.read_hash,
    'portal', public.bukku_portal(p_kind, p_id));
end $$;
revoke all on function public.bukku_read_may(text, uuid, text) from public, anon;
grant execute on function public.bukku_read_may(text, uuid, text) to authenticated;

/* `bukku_prepare` with the Billing sheet's values over the record's, for
   a save straight to Bukku: each value checked as the sheet checks it,
   the billing contact one of the record's own. A value emptied is named
   in `clear`, so Bukku empties it too. */
create or replace function public.bukku_prepare_with(p_kind text, p_id uuid, p_values jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb; k public.client_contacts; v_clear text[] := '{}'; v_t text; v_key text;
  v_map constant text[][] := array[array['company_no_old', 'old_reg_no'], array['tin', 'tax_id_no'], array['sst_no', 'sst_reg_no']];
begin
  if p_kind not in ('client', 'entity') then return jsonb_build_object('error', 'bad-kind'); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  for v_key in select jsonb_object_keys(p_values) loop
    if v_key not in ('legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no', 'finance_email', 'billing_address',
                     'bill_contact_id') then
      return jsonb_build_object('error', 'bad-field', 'field', v_key);
    end if;
  end loop;
  v := public.bukku_prepare(p_kind, p_id);
  if v ? 'error' then return v; end if;
  if v->>'contact_id' is null then return jsonb_build_object('error', 'not-linked'); end if;
  if p_values ? 'legal_name' then
    v_t := btrim(regexp_replace(coalesce(p_values->>'legal_name', ''), '\s+', ' ', 'g'));
    if v_t = '' then return jsonb_build_object('error', 'no-name'); end if;
    if length(v_t) > 200 then return jsonb_build_object('error', 'too-long', 'field', 'legal_name'); end if;
    v := v || jsonb_build_object('legal_name', public.bukku_name_case(upper(v_t), true));
  end if;
  if p_values ? 'company_no' then
    v_t := nullif(regexp_replace(coalesce(p_values->>'company_no', ''), '[^0-9A-Za-z]', '', 'g'), '');
    if length(v_t) > 40 then return jsonb_build_object('error', 'too-long', 'field', 'company_no'); end if;
    v := v || jsonb_build_object('reg_no', v_t, 'reg_no_type', case when v_t is null then null else 'BRN' end);
    if v_t is null then v_clear := v_clear || 'reg_no'::text; end if;
  end if;
  for i in 1 .. array_length(v_map, 1) loop
    if p_values ? v_map[i][1] then
      v_t := nullif(btrim(coalesce(p_values->>v_map[i][1], '')), '');
      if length(v_t) > 60 then return jsonb_build_object('error', 'too-long', 'field', v_map[i][1]); end if;
      v := v || jsonb_build_object(v_map[i][2], v_t);
      if v_t is null then v_clear := v_clear || v_map[i][2]; end if;
    end if;
  end loop;
  if p_values ? 'finance_email' then
    v_t := nullif(btrim(coalesce(p_values->>'finance_email', '')), '');
    if v_t is not null and v_t !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[A-Za-z]{2,}$' then return jsonb_build_object('error', 'bad-email'); end if;
    if v_t is not null then v := v || jsonb_build_object('email', lower(v_t)); end if;
  end if;
  if p_values ? 'billing_address' then
    v_t := nullif(btrim(coalesce(p_values->>'billing_address', '')), '');
    if v_t is null then return jsonb_build_object('error', 'no-address'); end if;
    if length(v_t) > 500 then return jsonb_build_object('error', 'too-long', 'field', 'billing_address'); end if;
    v := v || jsonb_build_object('address', v_t);
  end if;
  if p_values ? 'bill_contact_id' then
    v_t := nullif(btrim(coalesce(p_values->>'bill_contact_id', '')), '');
    if v_t is null then
      if p_kind = 'client' then
        select * into k from public.client_contacts x where x.client_id = p_id and x.is_primary and x.archived_at is null limit 1;
      else
        select * into k from public.client_contacts x
         where x.client_id = public.entity_home_client(p_id) and x.is_primary and x.archived_at is null limit 1;
      end if;
    elsif v_t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select * into k from public.client_contacts x
       where x.id = v_t::uuid and x.archived_at is null
         and (case when p_kind = 'client' then x.client_id = p_id
                   else x.client_id in (select ce.client_id from public.client_entities ce where ce.entity_id = p_id) end);
      if k.id is null then return jsonb_build_object('error', 'bad-contact'); end if;
    else
      return jsonb_build_object('error', 'bad-contact');
    end if;
    v := v || jsonb_build_object('person', nullif(public.bukku_name_case(btrim(coalesce(k.name, '')), false), ''),
                                 'salutation', nullif(btrim(coalesce(k.salutation, '')), ''));
  end if;
  return v || jsonb_build_object('clear', to_jsonb(v_clear));
end $$;
revoke all on function public.bukku_prepare_with(text, uuid, jsonb) from public, anon;
grant execute on function public.bukku_prepare_with(text, uuid, jsonb) to authenticated;

/* Bukku's details written into the record (the service role's, after
   `bukku-sync` read the contact as the caller allowed it). `p_changed` is
   the fields that differ from the portal, read by the function as Bukku
   sets them out (an address in its parts). Mode `read`: a held link takes
   them; one not yet held takes them only where every field that differs is
   empty in the portal, else answers what differs and writes nothing.
   `hold` (Use Bukku's, or after Send to Bukku) and `save` (Save to Bukku)
   take them and hold the link. */
create or replace function public.bukku_take(p_actor uuid, p_kind text, p_id uuid, p_values jsonb, p_hash text,
                                             p_changed text[], p_mode text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  l public.bukku_links; p jsonb; k public.client_contacts;
  v_ent uuid; v_who text; v_name text; v_detail text; v_bc uuid; v_bc_set boolean := false;
  v_changed text[] := coalesce(p_changed, '{}');
  v_open text[];
  v_words constant jsonb := '{"legal_name": "Registered name", "company_no": "Business registration no.",
    "company_no_old": "Old registration no.", "tin": "TIN", "sst_no": "SST registration no.",
    "finance_email": "Finance email", "billing_address": "Billing address", "person": "Billing contact"}';
  v_t text;
begin
  if p_kind not in ('client', 'entity') or p_mode not in ('read', 'hold', 'save')
     or jsonb_typeof(p_values) is distinct from 'object' then
    return jsonb_build_object('error', 'bad-request');
  end if;
  l := public.bukku_link_row(p_kind, p_id);
  if l.contact_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  p := public.bukku_portal(p_kind, p_id);
  if p is null then return jsonb_build_object('error', 'not-found'); end if;
  select array_agg(f) into v_changed from unnest(v_changed) f where v_words ? f;
  v_changed := coalesce(v_changed, '{}');
  select array_agg(f) into v_open from unnest(v_changed) f
   where nullif(btrim(coalesce(p->>f, '')), '') is not null;
  v_open := coalesce(v_open, '{}');
  update public.bukku_links x set read_at = now(), read_hash = left(p_hash, 200),
         person = nullif(left(btrim(coalesce(p_values->>'person', '')), 120), '')
   where x.kind = l.kind and x.record_id = l.record_id;
  /* The first read of a link not yet held writes nothing over a detail
     the portal holds: it waits on Send to Bukku or Use Bukku's. */
  if p_mode = 'read' and l.held_at is null and cardinality(v_open) > 0 then
    return jsonb_build_object('ok', true, 'held', false, 'differs', to_jsonb(v_changed));
  end if;

  if p_kind = 'client' then
    v_ent := public.client_main_entity(p_id);
    if v_ent is null then
      insert into public.billing_entities (legal_name) values (nullif(btrim(coalesce(p_values->>'legal_name', '')), ''))
      returning id into v_ent;
      insert into public.client_entities (client_id, entity_id, is_main) values (p_id, v_ent, true);
    end if;
  else
    v_ent := p_id;
  end if;
  if p_values ? 'person' and nullif(btrim(coalesce(p_values->>'person', '')), '') is not null then
    k := public.bukku_person_contact(p_kind, p_id, p_values->>'person');
    if k.id is not null then
      v_bc_set := true;
      v_bc := case when k.is_primary and k.client_id = coalesce(case when p_kind = 'client' then p_id end,
                                                                public.entity_home_client(p_id)) then null else k.id end;
    end if;
  end if;
  update public.billing_entities e
     set legal_name = case when p_values ? 'legal_name'
                           then nullif(upper(btrim(regexp_replace(coalesce(p_values->>'legal_name', ''), '\s+', ' ', 'g'))), '')
                           else e.legal_name end,
         company_no = case when p_values ? 'company_no' then nullif(btrim(coalesce(p_values->>'company_no', '')), '') else e.company_no end,
         company_no_old = case when p_values ? 'company_no_old' then nullif(btrim(coalesce(p_values->>'company_no_old', '')), '') else e.company_no_old end,
         tin = case when p_values ? 'tin' then nullif(btrim(coalesce(p_values->>'tin', '')), '') else e.tin end,
         sst_no = case when p_values ? 'sst_no' then nullif(btrim(coalesce(p_values->>'sst_no', '')), '') else e.sst_no end,
         finance_email = case when p_values ? 'finance_email' then nullif(lower(btrim(coalesce(p_values->>'finance_email', ''))), '') else e.finance_email end,
         billing_address = case when p_values ? 'billing_address' then nullif(btrim(coalesce(p_values->>'billing_address', '')), '') else e.billing_address end,
         bill_contact_id = case when v_bc_set then v_bc else e.bill_contact_id end
   where e.id = v_ent;
  update public.bukku_links x set held_at = coalesce(x.held_at, now())
   where x.kind = l.kind and x.record_id = l.record_id;

  if cardinality(v_changed) > 0 then
    select string_agg(v_words->>f, ', ' order by array_position(array['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no',
             'person', 'finance_email', 'billing_address'], f))
      into v_t from unnest(v_changed) f;
    select x.name into v_who from public.team_members x where x.id = p_actor;
    v_detail := case p_mode when 'read' then 'Read from Bukku: ' when 'save' then 'Saved to Bukku: ' else 'Took Bukku''s details: ' end
                || v_t || ' · ' || coalesce(l.code, l.contact_id::text);
    v_who := case when p_mode = 'read' then 'Bukku' else coalesce(v_who, 'Bukku') end;
    if p_kind = 'entity' then
      perform public.bukku_file_entity(p_id, v_who, v_detail);
    else
      select x.name into v_name from public.clients x where x.id = p_id;
      insert into public.activity_log (actor, action, subject, detail) values (v_who, 'client.billing', v_name, v_detail);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'held', true, 'changed', to_jsonb(v_changed),
    'person_in', v_bc_set or nullif(btrim(coalesce(p_values->>'person', '')), '') is null);
end $$;
revoke all on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) from public, anon, authenticated;
grant execute on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) to service_role;

/* The held links the nightly read goes through, the oldest read first,
   each with what the portal holds. The service role's. */
create or replace function public.bukku_held_links()
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('kind', l.kind, 'id', l.record_id, 'contact_id', l.contact_id, 'code', l.code,
           'portal', public.bukku_portal(l.kind, l.record_id))
    from public.bukku_links l
   where l.kind in ('client', 'entity') and l.held_at is not null
     and public.bukku_portal(l.kind, l.record_id) is not null
   order by l.read_at nulls first
$$;
revoke all on function public.bukku_held_links() from public, anon, authenticated;
grant execute on function public.bukku_held_links() to service_role;

/* The nightly wake of `bukku-sync`, with the wake secret, after the
   commit. Internal. */
create or replace function public.bukku_nightly_kick()
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'net' and p.proname = 'http_post') then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 150000)'
    using 'https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/bukku-sync', '{"action":"nightly"}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-adspace-wake',
            coalesce((select s.value from public.app_secrets s where s.key = 'wake_secret'), ''));
exception when others then
  return;
end $$;
revoke all on function public.bukku_nightly_kick() from public, anon, authenticated;

create or replace function public.bukku_link_get(p_kind text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare l public.bukku_links; v_by text; v_sh jsonb; r public.bukku_links;
begin
  if not public.bukku_may(p_kind, p_id, 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into l from public.bukku_links x where x.kind = p_kind and x.record_id = p_id;
  if l.contact_id is null then
    v_sh := public.bukku_shared(p_kind, p_id);
    if v_sh is null then return jsonb_build_object('ok', true); end if;
    r := public.bukku_link_row(p_kind, p_id);
    return jsonb_build_object('ok', true, 'contact_id', (v_sh->>'contact_id')::bigint, 'code', v_sh->>'code',
      'via', v_sh->>'via', 'changed', false, 'held', r.held_at is not null, 'read_at', r.read_at, 'person', r.person);
  end if;
  select t.name into v_by from public.team_members t where t.id = l.sent_by;
  return jsonb_build_object('ok', true, 'contact_id', l.contact_id, 'code', l.code, 'sent_at', l.sent_at,
    'sent_by', v_by, 'changed', l.held_at is null and l.sent_hash is distinct from public.bukku_print(p_kind, p_id),
    'held', l.held_at is not null, 'read_at', l.read_at, 'person', l.person);
end $$;
revoke all on function public.bukku_link_get(text, uuid) from public, anon;
grant execute on function public.bukku_link_get(text, uuid) to authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: linked billing is read from Bukku only when Billing opens.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'bukku-read-nightly';
  perform cron.schedule('bukku-read-nightly', '30 16 * * *', 'select public.bukku_nightly_kick()');
end $$;

-- END OF BILLING FROM BUKKU -------------------------------------------------

select public.functions_tidy();
