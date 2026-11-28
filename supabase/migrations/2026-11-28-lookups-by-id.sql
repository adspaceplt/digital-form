-- ===========================================================================
-- LOOKUPS BY ID (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 3 (docs/MAP.md §G). A client's industry, a
-- service line's tax code and a task's stage were tied to their lookup by
-- the name or code they hold: `industries` and `tax_codes` were keyed by
-- that name or code with no foreign key, an industry renamed or deleted
-- by matching names, a letter's tax rate read by code, and a task's
-- stage joined by its key. A report's and an AI draft's brand held a
-- uuid with no foreign key.
-- WHAT IT CHANGES
--   * `industries.id` and `tax_codes.id` (uuid) become each table's
--     primary key; the name and the code stay unique, as typed.
--   * `clients.industry_id` (on delete set null; select granted to a
--     signed-in colleague), `client_services.tax_code_id` (on delete
--     restrict: a code in use is never deleted) and `ops_tasks.stage_id`
--     (on delete restrict), each backfilled and stamped by a trigger:
--     the id leads and writes the name or code as its snapshot; a name or
--     code alone (a function, the public quotation form, an open tab
--     served before) takes its one row, case aside for an industry.
--   * `industries_list` answers each industry's id and counts its clients
--     by it; `industry_save(p_id, …)` and `industry_delete(p_id)` replace
--     the name versions (dropped), the rename carried to clients by id;
--     Delete requests name an industry by its id.
--   * `tax_codes_list` answers each code's id; `issue_letter` reads a
--     line's rate by `tax_code_id`; `tax_code_uses` counts lines by it.
--   * `ops_script_task`, `ops_record_tasks`, `ops_task_late`,
--     `ops_tasks_nudge` and `ops_report_of` join a task's current stage by
--     `stage_id`. A stage moved in history stays a key (`ops_task_events`).
--   * Foreign keys on `sm_reports.brand_id` and `ai_drafts.brand_id`
--     (on delete set null), added not valid, then validated.
-- ORDER: this file first, then the pages (Settings › Industries sends the
-- id; a service line's Tax select writes `tax_code_id`). An open tab served
-- before: Settings › Industries' save or delete meets "This feature is not
-- available yet" until it is refreshed (the name versions are dropped);
-- every other screen writes a name or code, which the stamps still take.
-- ROLLBACK: drop the three stamp triggers and their functions; run the
-- latest earlier bands of the eleven functions again (and the name
-- versions of `industry_save` / `industry_delete`, with Delete requests'
-- `rpc:industry_delete` row back to `p_name` / `name`); alter table
-- public.sm_reports drop constraint sm_reports_brand_id_fkey; alter table
-- public.ai_drafts drop constraint ai_drafts_brand_id_fkey. The columns
-- and the primary keys stay. Safe to run twice.

-- LOOKUPS BY ID ------------------------------------------------------------

/* The primary key moves to the id; the name or code stays unique. */
alter table public.industries add column if not exists id uuid not null default gen_random_uuid();
alter table public.tax_codes add column if not exists id uuid not null default gen_random_uuid();
do $$
declare
  t text;
  k text;
begin
  foreach t in array array['industries', 'tax_codes'] loop
    k := case t when 'industries' then 'name' else 'code' end;
    if not exists (select 1 from pg_constraint where conname = t || '_' || k || '_key') then
      execute format('alter table public.%I add constraint %I unique (%I)', t, t || '_' || k || '_key', k);
    end if;
    if (select a.attname from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
         where i.indrelid = ('public.' || t)::regclass and i.indisprimary) is distinct from 'id' then
      execute format('alter table public.%I drop constraint if exists %I', t, t || '_pkey');
      execute format('alter table public.%I add primary key (id)', t);
    end if;
  end loop;
end $$;

alter table public.clients add column if not exists industry_id uuid
  references public.industries(id) on delete set null;
create index if not exists clients_industry_id_idx on public.clients (industry_id);
grant select (industry_id) on table public.clients to authenticated;

alter table public.client_services add column if not exists tax_code_id uuid
  references public.tax_codes(id) on delete restrict;
create index if not exists client_services_tax_code_id_idx on public.client_services (tax_code_id);
grant select (tax_code_id), insert (tax_code_id), update (tax_code_id) on table public.client_services to authenticated;

alter table public.ops_tasks add column if not exists stage_id uuid
  references public.ops_workflow_stages(id) on delete restrict;
create index if not exists ops_tasks_stage_id_idx on public.ops_tasks (stage_id);

/* A client's industry: the id leads, the name its snapshot. */
create or replace function public.client_industry_id_stamp()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v public.industries;
  v_low text := lower(btrim(coalesce(new.industry, '')));
begin
  if tg_op = 'UPDATE' and new.industry is not distinct from old.industry
     and new.industry_id is not distinct from old.industry_id then
    return new;
  end if;
  if new.industry_id is not null then
    select * into v from public.industries i where i.id = new.industry_id;
    if tg_op = 'INSERT' or new.industry_id is distinct from old.industry_id
       or lower(btrim(coalesce(new.industry, ''))) is not distinct from lower(v.name) then
      new.industry := coalesce(v.name, new.industry);
      return new;
    end if;
  elsif tg_op = 'UPDATE' and old.industry_id is not null then
    new.industry := null;
    return new;
  end if;
  if nullif(btrim(coalesce(new.industry, '')), '') is null then
    new.industry := null;
    new.industry_id := null;
    return new;
  end if;
  /* The one place a name finds its industry: a name written alone. */
  select * into v from public.industries i where lower(i.name) = v_low;
  new.industry_id := v.id;
  new.industry := coalesce(v.name, new.industry);
  return new;
end $$;
revoke all on function public.client_industry_id_stamp() from public, anon, authenticated;
drop trigger if exists client_industry_id_stamp on public.clients;
create trigger client_industry_id_stamp before insert or update of industry, industry_id on public.clients
  for each row execute function public.client_industry_id_stamp();

/* A service line's tax code: the id leads, the code its snapshot. */
create or replace function public.client_services_tax_code_id_stamp()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v public.tax_codes;
begin
  if tg_op = 'UPDATE' and new.tax_code is not distinct from old.tax_code
     and new.tax_code_id is not distinct from old.tax_code_id then
    return new;
  end if;
  if new.tax_code_id is not null and (tg_op = 'INSERT' or new.tax_code_id is distinct from old.tax_code_id) then
    select * into v from public.tax_codes t where t.id = new.tax_code_id;
    new.tax_code := v.code;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.tax_code_id is null and old.tax_code_id is not null then
    new.tax_code := null;
    return new;
  end if;
  select * into v from public.tax_codes t where t.code = nullif(btrim(coalesce(new.tax_code, '')), '');
  new.tax_code_id := v.id;
  return new;
end $$;
revoke all on function public.client_services_tax_code_id_stamp() from public, anon, authenticated;
drop trigger if exists client_services_tax_code_id_stamp on public.client_services;
create trigger client_services_tax_code_id_stamp before insert or update of tax_code, tax_code_id on public.client_services
  for each row execute function public.client_services_tax_code_id_stamp();

/* A task's stage: the key a function writes takes its workflow's stage. */
create or replace function public.ops_tasks_stage_id_stamp()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v public.ops_workflow_stages;
  v_key text := coalesce(new.stage_key, '');
begin
  if tg_op = 'UPDATE' and new.stage_key is not distinct from old.stage_key
     and new.workflow_id is not distinct from old.workflow_id and new.stage_id is not distinct from old.stage_id then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.stage_id is distinct from old.stage_id and new.stage_key is not distinct from old.stage_key
     and new.stage_id is not null then
    select * into v from public.ops_workflow_stages s where s.id = new.stage_id;
    new.stage_key := v.key;
    new.workflow_id := v.workflow_id;
    return new;
  end if;
  select * into v from public.ops_workflow_stages s where s.workflow_id = new.workflow_id and s.key = v_key;
  new.stage_id := v.id;
  return new;
end $$;
revoke all on function public.ops_tasks_stage_id_stamp() from public, anon, authenticated;
drop trigger if exists ops_tasks_stage_id_stamp on public.ops_tasks;
create trigger ops_tasks_stage_id_stamp before insert or update of stage_key, workflow_id, stage_id on public.ops_tasks
  for each row execute function public.ops_tasks_stage_id_stamp();

/* Backfill: each row takes the id its name, code or key names. */
do $$
begin
  update public.clients c set industry_id = i.id
    from public.industries i
   where c.industry_id is null and nullif(btrim(coalesce(c.industry, '')), '') is not null
     and lower(i.name) = lower(btrim(c.industry));
  update public.client_services s set tax_code_id = t.id
    from public.tax_codes t
   where s.tax_code_id is null and s.tax_code is not null and t.code = s.tax_code;
  update public.ops_tasks k set stage_id = w.id
    from public.ops_workflow_stages w
   where k.stage_id is null and w.workflow_id = k.workflow_id and w.key = k.stage_key;
end $$;

/* A report's and an AI draft's brand, held to the brand. */
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sm_reports_brand_id_fkey') then
    alter table public.sm_reports add constraint sm_reports_brand_id_fkey
      foreign key (brand_id) references public.client_brands(id) on delete set null not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ai_drafts_brand_id_fkey') then
    alter table public.ai_drafts add constraint ai_drafts_brand_id_fkey
      foreign key (brand_id) references public.client_brands(id) on delete set null not valid;
  end if;
end $$;
alter table public.sm_reports validate constraint sm_reports_brand_id_fkey;
alter table public.ai_drafts validate constraint ai_drafts_brand_id_fkey;

drop function if exists public.industry_save(text, text, text);
drop function if exists public.industry_delete(text);

create or replace function public.industries_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.is_team() then
    return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'name_zh', i.name_zh,
        'clients', (select count(*)::int from public.clients c where c.industry_id = i.id))
        order by (i.name = 'Other'), lower(i.name))
      from public.industries i), '[]'::jsonb);
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'name_zh', i.name_zh) order by (i.name = 'Other'), lower(i.name))
    from public.industries i), '[]'::jsonb);
end $$;
revoke all on function public.industries_list() from public;
grant execute on function public.industries_list() to anon, authenticated;

create or replace function public.industry_save(p_id uuid, p_name text, p_name_zh text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_zh   text := nullif(btrim(regexp_replace(coalesce(p_name_zh, ''), '\s+', ' ', 'g')), '');
  v_was  public.industries;
  v_n    int := 0;
  v_moved text[] := '{}';
  v_low  text := lower(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')));
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_name) < 2 or length(v_name) > 40 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_zh is not null and length(v_zh) > 40 then return jsonb_build_object('error', 'bad-name-zh'); end if;
  perform pg_advisory_xact_lock(hashtextextended('industries', 0));
  if p_id is not null then
    select * into v_was from public.industries i where i.id = p_id for update;
    if v_was.id is null then return jsonb_build_object('error', 'not-found'); end if;
    -- Other keeps its name, so it stays the last choice (review 6).
    if v_was.name = 'Other' and v_name <> 'Other' then return jsonb_build_object('error', 'fixed'); end if;
  end if;
  if exists (select 1 from public.industries i where lower(i.name) = v_low and i.id is distinct from p_id) then
    return jsonb_build_object('error', 'taken');
  end if;
  if v_was.id is null then
    insert into public.industries (name, name_zh, updated_by) values (v_name, v_zh, me.id) returning * into v_was;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Industries', 'Added: ' || v_name);
    return jsonb_build_object('ok', true, 'id', v_was.id, 'name', v_name);
  end if;
  v_moved := array_remove(array[
    case when v_was.name <> v_name then 'Name: ' || v_was.name || ' → ' || v_name end,
    case when v_was.name_zh is distinct from v_zh then 'Chinese name: ' || coalesce(v_was.name_zh, 'not set') || ' → ' || coalesce(v_zh, 'not set') end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true, 'id', v_was.id, 'name', v_name, 'clients', 0); end if;
  update public.industries i set name = v_name, name_zh = v_zh, updated_at = now(), updated_by = me.id
   where i.id = v_was.id;
  -- A rename carries onto every client holding the old name (the user,
  -- 2026-11-04: "A").
  -- The rename reaches every client, the ones outside the caller's own
  -- client scope included: the guard lets it through as it does a
  -- hand-over (`adspace.team_owner`), set for this update alone (review 2).
  if v_was.name <> v_name then
    perform set_config('adspace.team_owner', 'on', true);
    update public.clients c set industry = v_name where c.industry_id = v_was.id;
    get diagnostics v_n = row_count;
    perform set_config('adspace.team_owner', 'off', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', v_name || ' · ' || array_to_string(v_moved, ' · ') ||
          case when v_n = 1 then ' · 1 client updated' when v_n > 1 then ' · ' || v_n || ' clients updated' else '' end);
  return jsonb_build_object('ok', true, 'id', v_was.id, 'name', v_name, 'clients', v_n);
end $$;
revoke all on function public.industry_save(uuid, text, text) from public, anon;
grant execute on function public.industry_save(uuid, text, text) to authenticated;

create or replace function public.industry_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_n int;
  v_i public.industries;
begin
  if not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtextextended('industries', 0));
  select * into v_i from public.industries i where i.id = p_id;
  if v_i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  -- Other stays, the website's last choice (2026-11-04, review 6).
  if v_i.name = 'Other' then return jsonb_build_object('error', 'fixed'); end if;
  select count(*)::int into v_n from public.clients c where c.industry_id = v_i.id;
  if v_n > 0 then return jsonb_build_object('error', 'in-use', 'clients', v_n); end if;
  delete from public.industries i where i.id = v_i.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', 'Deleted: ' || v_i.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.industry_delete(uuid) from public, anon;
grant execute on function public.industry_delete(uuid) to authenticated;

update public.delete_kinds set id_arg = 'p_id', label_key = 'id'
 where kind = 'rpc:industry_delete' and (id_arg, label_key) is distinct from ('p_id', 'id');

create or replace function public.tax_codes_list()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_team() then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'codes', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name, 'rate', t.rate, 'active', t.active,
                                          'bukku', t.bukku_id is not null)
                       order by t.active desc, t.rate desc, t.code)
        from public.tax_codes t), '[]'::jsonb)) end
$$;
revoke all on function public.tax_codes_list() from public, anon;
grant execute on function public.tax_codes_list() to authenticated;

create or replace function public.tax_code_uses(p_code text)
returns int
language sql stable security definer set search_path = public as $$
  select (select count(*) from public.client_services s join public.tax_codes t on t.id = s.tax_code_id where t.code = p_code)::int
       + (select count(*) from public.quotations q
           where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(q.lines) = 'array' then q.lines else '[]'::jsonb end) l
                          where l ->> 'tax_code' = p_code)
              or q.selection::text like '%"tax": ' || to_jsonb(p_code)::text || '%')::int
       + (select count(*) from public.client_documents d
           where to_jsonb(d)::text like '%"tax_code": ' || to_jsonb(p_code)::text || '%')::int
$$;
revoke all on function public.tax_code_uses(text) from public, anon, authenticated;

create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  /* A reference somebody typed. Blank is the ordinary case and the counter
     below makes the number; where one is typed it is checked against every
     document that stands and the counter is not advanced, so filling a gap
     by hand never costs the next letter its place in the sequence. */
  p_serial    text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  ct     public.client_contacts%rowtype;
  me     public.team_members%rowtype;
  v_ym   text;
  v_seq  int;
  v_try  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
  v_term int;
  v_each numeric;
  v_etax numeric;
  v_once numeric;
  v_otax numeric;
  v_sub  numeric;
  v_tax  numeric;
  v_tot  numeric;
  v_pct  numeric;
  v_qid  uuid;
  v_q    public.quotations%rowtype;
  v_tp   numeric;
  v_tadj boolean;
  v_qterm int;
  v_msub numeric;
  v_span numeric;
  v_even boolean;
  v_qt   jsonb;
  v_month boolean;
  v_terms jsonb;
  v_ent  public.billing_entities%rowtype;
  v_ect  public.client_contacts%rowtype;
  v_on   date := public.doc_day_of(p_deal ->> 'date');
begin
  if not public.allowed('clients.documents') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  /* The letter's own date (2026-11-12, the user: a letter may be
     backdated): its reference's month, the SST and the rate in force, and
     the quotation still standing on that day; today where none is chosen. */
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  v_on := coalesce(v_on, (timezone('Asia/Kuala_Lumpur', now()))::date);
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- Bill to (2026-10-29): a billing entity of this client other than its
  -- main, named in the deal, is the one the letter bills: its registered
  -- name, numbers, address and finance email stand in for the client's in
  -- the snapshot, and its billing contact is the letter's Attn where one is
  -- set and live. None named is the main entity, the client's own billing.
  if nullif(btrim(coalesce(p_deal ->> 'entity', '')), '') is not null then
    if (p_deal ->> 'entity') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('error', 'bad-entity');
    end if;
    select e.* into v_ent from public.billing_entities e
      join public.client_entities ce on ce.entity_id = e.id and ce.client_id = p_client
     where e.id = (p_deal ->> 'entity')::uuid;
    if v_ent.id is null then return jsonb_build_object('error', 'bad-entity'); end if;
    if coalesce(btrim(v_ent.legal_name), '') = '' or coalesce(btrim(v_ent.company_no), '') = ''
       or coalesce(btrim(v_ent.billing_address), '') = '' then
      return jsonb_build_object('error', 'entity-incomplete');
    end if;
    cl.legal_name := v_ent.legal_name; cl.company_no := v_ent.company_no;
    cl.company_no_old := v_ent.company_no_old; cl.tin := v_ent.tin; cl.sst_no := v_ent.sst_no;
    cl.finance_email := v_ent.finance_email; cl.billing_address := v_ent.billing_address;
  end if;

  -- The letter's own terms, one point a line, kept with what it was issued
  -- with and printed under TERMS after the term and the validity
  -- (2026-10-23): ten at most, each 1 to 400 characters.
  v_terms := coalesce((select jsonb_agg(btrim(t)) from jsonb_array_elements_text(
               case when jsonb_typeof(p_deal -> 'terms') = 'array' then p_deal -> 'terms' else '[]'::jsonb end) t
             where btrim(t) <> ''), '[]'::jsonb);
  if jsonb_array_length(v_terms) > 10
     or exists (select 1 from jsonb_array_elements_text(v_terms) t where length(t) > 400) then
    return jsonb_build_object('error', 'bad-terms');
  end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one. Staff enter it on the record; nothing invents it. A typed
  -- reference needs no code, because nothing is being built.
  v_no := nullif(btrim(coalesce(p_serial, '')), '');
  if v_no is null and coalesce(btrim(cl.client_code), '') = '' then
    return jsonb_build_object('error', 'no-client-code');
  end if;

  -- The same submission, pressed twice, is one letter. Answered before any
  -- number is reserved, so a double click cannot spend a serial either.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.client_documents
      where client_id = p_client and idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
    end if;
  end if;

  -- A typed reference is checked before anything is written: the same shape
  -- the Register accepts, and refused where a document still holds it.
  if v_no is not null then
    if v_no !~ '^[A-Za-z0-9/._-]{3,40}$' then
      return jsonb_build_object('error', 'serial-shape');
    end if;
    if public.serial_taken(v_no) then
      return jsonb_build_object('error', 'serial-taken');
    end if;
  end if;

  -- Every id must be this client's own live line, and in a state this letter
  -- may carry: To quote always, Confirmed only on a deliberate renewal.
  select count(*) into v_bad from unnest(p_services) s(id)
    left join public.client_services cs
      on cs.id = s.id and cs.client_id = p_client and cs.archived_at is null
    where cs.id is null
       or (cs.state = 'confirmed' and not p_renewal)
       or cs.state not in ('quoted', 'confirmed');
  if v_bad > 0 then return jsonb_build_object('error', 'bad-lines'); end if;

  -- The lines are held while this letter is made (2026-11-07): two
  -- presses on the same lines take them in turn, so the second reads the
  -- first one's letter below and is refused, never a second live letter.
  perform 1 from public.client_services where id = any(p_services) order by id for update;

  -- A line already on a live letter is not offered again by accident. The way
  -- through is to void that letter, or to name it as the one being replaced.
  select count(*) into v_bad
    from public.client_document_services m
    join public.client_documents d on d.id = m.document_id
   where m.service_id = any(p_services)
     and d.voided_at is null
     and d.superseded_by is null
     and d.verified_at is null
     and (p_replaces is null or d.id <> p_replaces);
  if v_bad > 0 then return jsonb_build_object('error', 'already-quoted'); end if;

  if p_replaces is not null then
    -- The letter replaced is held while it is read (2026-11-08, audit 5):
    -- two Replace presses at once on one letter, ticking different lines,
    -- each read it live and both issued. The second now waits and reads it
    -- replaced.
    select * into v_old from public.client_documents
      where id = p_replaces and client_id = p_client
      for update;
    if v_old.id is null then return jsonb_build_object('error', 'no-replaces'); end if;
    if v_old.verified_at is not null then return jsonb_build_object('error', 'replaces-verified'); end if;
    -- A letter already replaced, or void, is no longer the live one: a
    -- second Replace would leave two letters on its lines (2026-11-07).
    if v_old.superseded_by is not null then return jsonb_build_object('error', 'superseded'); end if;
    if v_old.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  end if;

  select * into ct from public.client_contacts
    where client_id = p_client and archived_at is null
    order by (id = cl.bill_contact_id) desc, is_primary desc, name limit 1;
  -- The brand's billing contact for the entity billed (the one named, else
  -- its primary): its own choice, else the entity's shared one, else its
  -- live main contact (2026-10-31).
  v_ect := public.entity_contact(coalesce(v_ent.id, public.client_main_entity(p_client)), p_client);
  if v_ect.id is not null then ct := v_ect; end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under the issuer's name on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory.
  if not public.issuer_name_ok(me.name) then
    return jsonb_build_object('error', 'issuer-name', 'name', coalesce(me.name, ''));
  end if;

  -- The snapshot is built from the stored rows, never from what the browser
  -- sent: the words on a letter are the words the record held at that moment.
  select jsonb_agg(jsonb_build_object(
           'label', cs.label, 'unit', coalesce(cs.unit, ''), 'note', coalesce(cs.note, ''),
           'detail', coalesce(cs.detail, ''), 'state', cs.state,
           'qty', cs.qty, 'rate', cs.rate,
           'tenure', greatest(1, coalesce(cs.tenure, 1)),
           'start_on', coalesce(cs.start_on, ''),
           -- The line's own answer to whether its term prices it. Written into
           -- the snapshot because the letter is redrawn from it, and a letter
           -- must print the same figure every time it is drawn. A snapshot
           -- taken before this key existed carries none, which money.js reads
           -- as on, so those letters redraw as they were issued.
           'term_adjust', coalesce(cs.term_adjust, false),
           -- And the percentage that tick applies, so a later rate card can
           -- never move a figure this letter printed. Null on a line quoted
           -- before the column existed, which money.js reads as that card.
           'term_pct', cs.term_pct,
           'tax', cl.sst_applies is not false,
           -- The line's own tax code and its rate as issued (2026-10-22);
           -- none is the client's SST, as before.
           'tax_code', cs.tax_code,
           'tax_pct', (select t.rate from public.tax_codes t where t.id = cs.tax_code_id),
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;
  /* A line's tax code is one the team holds and offers (2026-10-22). */
  if exists (select 1 from public.client_services cs
              where cs.id = any(p_services) and cs.tax_code is not null
                and not exists (select 1 from public.tax_codes t where t.id = cs.tax_code_id and t.active)) then
    return jsonb_build_object('error', 'bad-tax');
  end if;

  /* The price is the database's (audit S4, 2026-10-10), worked as the
     letter draws it (js/documents.js priceOf, js/money.js rateFor): each
     line's rate with its term on it, rounded to the cent. Where every line
     of more than a month shares one term, those lines are priced by the
     month and times the term, and a line of one month is a one-off item
     with its own SST (2026-10-15: a one-off item beside them no longer
     turns the letter into one whole total); otherwise every line is its
     whole amount. SST at the rate in force today unless the client is
     exempt. The page's figures are kept only where they agree to the sen,
     so a line changed since the sheet opened, or a figure typed in a
     browser, is refused (`stale`) and the sheet reads the lines again. */
  select case when count(distinct greatest(1, coalesce(cs.tenure, 1)))
                     filter (where greatest(1, coalesce(cs.tenure, 1)) > 1) = 1
              then max(greatest(1, coalesce(cs.tenure, 1))) else 0 end
    into v_term
    from public.client_services cs where cs.id = any(p_services);
  /* A letter whose every line came from one quotation is priced as that
     quotation was (audit F, 2026-10-17), exactly as `quote_price` and
     `quote_adjust` total it (2026-10-17, the review's finding 7): a line
     the quotation bills by the month (`quotation_offer` ticks its term) is
     a monthly line whatever months Build quote gave it, its percentage
     taken once on their subtotal; a line with no term is one-off; SST at
     the quotation's rate. The page's figures are held to the same price
     (js/documents.js priceOf). */
  select case when count(*) filter (where cs.quotation_id is null) = 0
                   and count(distinct cs.quotation_id) = 1 then min(cs.quotation_id::text)::uuid end,
         coalesce(bool_and(greatest(1, coalesce(cs.tenure, 1)) = 1) filter (where not coalesce(cs.term_adjust, false)), true),
         coalesce(max(cs.term_pct) filter (where coalesce(cs.term_adjust, false)), 0)
    into v_qid, v_tadj, v_tp
    from public.client_services cs where cs.id = any(p_services);
  /* Only while the quotation still stands (2026-10-17, the review's
     finding 2): unexpired by Malaysia's day and not removed. A renewal, or a
     letter replacing one after the quotation lapsed, is priced on today's
     rates, as any other letter. */
  if v_qid is not null and v_tadj and not coalesce(p_renewal, false) then
    select * into v_q from public.quotations q
     where q.id = v_qid and q.removed_at is null
       and q.valid_until >= v_on;
  end if;
  if v_q.id is not null then
    /* As quote_adjust totals it: the monthly lines' subtotal of quantity ×
       rate, the percentage once on it; where every one runs the quotation's
       term, a month's excl. SST, its SST rounded once, times the term; where
       Build quote gave a line months of its own, the whole span (each line's
       amount × its months) with the percentage and SST taken once on it.
       One-off lines and their SST apart. */
    v_qterm := greatest(1, coalesce((v_q.totals->>'term')::int, 1));
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce((v_q.totals->>'sst_pct')::numeric, 0) end;
    /* The lines as the quotation reads them (a line with its term ticked is
       monthly, on its own months), totalled by the one calculation every
       quotation shares (2026-10-18). */
    v_qt := public.quote_totals(
      (select coalesce(jsonb_agg(jsonb_build_object(
                'basis', case when coalesce(cs.term_adjust, false) then 'month' else 'once' end,
                'qty', coalesce(cs.qty, 0), 'rate', coalesce(cs.rate, 0),
                'months', greatest(1, coalesce(cs.tenure, 1)),
                /* each line its own percentage, as the quotation priced it
                   (2026-11-24); one with none takes the largest held */
                'pct', case when coalesce(cs.term_adjust, false) then cs.term_pct end,
                'sst', (select t.rate from public.tax_codes t where t.id = cs.tax_code_id))), '[]'::jsonb)
         from public.client_services cs where cs.id = any(p_services)),
      v_qterm, v_tp, v_pct);
    v_month := jsonb_typeof(v_qt->'month') = 'object';
    v_once := coalesce((v_qt->'once'->>'subtotal')::numeric, 0);
    v_otax := coalesce((v_qt->'once'->>'sst')::numeric, 0);
    if not v_month then
      v_sub := round(v_once, 2);
      v_tax := v_otax;
    elsif (v_qt->>'even')::boolean then
      v_each := (v_qt->'month'->>'excl')::numeric;
      v_etax := (v_qt->'month'->>'sst')::numeric;
      /* As the page totals it (js/documents.js quotePrice): a month incl.
         SST rounded, times the term, beside the one-off items incl. SST
         (2026-11-07: 1.5 × 333.33 for 12 months is 6,480.00, never
         6,479.94). */
      v_sub := round(round(v_each * v_qterm, 2) + v_once, 2);
      v_tax := v_etax * v_qterm + v_otax;
      v_tot := round(round(v_each + v_etax, 2) * v_qterm, 2) + round(v_once + v_otax, 2);
    else
      v_sub := (v_qt->>'span_excl')::numeric + round(v_once, 2);
      v_tax := (v_qt->>'span_incl')::numeric + round(v_once, 2) + v_otax - v_sub;
    end if;
    if not (v_month and (v_qt->>'even')::boolean) then v_tot := v_sub + v_tax; end if;
    /* The letter keeps what it was priced on, so a redraw prints the same:
       the quotation, its SST and its term (a snapshot with no `quote_term`
       was priced before this, and redraws as it was). */
    select jsonb_agg(l.e || jsonb_build_object('quotation_id', v_qid, 'quote_sst', v_pct, 'quote_term', v_qterm) order by l.n)
      into v_lines from jsonb_array_elements(v_lines) with ordinality l(e, n);
  else
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce(public.app_setting('sst_pct', v_on), 0) end;
    /* Each line at its own SST rate (2026-10-22): its tax code's, else the
       client's. The SST is worked a rate at a time, rounded once each, so
       a letter on one rate prices as it always did. */
    with x as (
      select greatest(1, coalesce(cs.tenure, 1)) as n,
             coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) as v,
             coalesce((select t.rate from public.tax_codes t where t.id = cs.tax_code_id), v_pct) as r
        from public.client_services cs where cs.id = any(p_services)
    ), y as (
      select r,
             coalesce(sum(v) filter (where v_term > 0 and n = v_term), 0) as e,
             coalesce(sum(v * n) filter (where v_term = 0 or n <> v_term), 0) as o
        from x group by r
    )
    select coalesce(sum(e), 0), coalesce(sum(o), 0),
           coalesce(sum(round(e * r) / 100), 0), coalesce(sum(round(o * r) / 100), 0)
      into v_each, v_once, v_etax, v_otax
      from y;
    v_sub := round(v_each * greatest(v_term, 1), 2) + round(v_once, 2);
    v_tax := round(v_etax * greatest(v_term, 1), 2) + v_otax;
    v_tot := round(round(v_each + v_etax, 2) * greatest(v_term, 1), 2) + round(v_once + v_otax, 2);
  end if;
  if abs(coalesce(p_subtotal, -1) - v_sub) > 0.01 or abs(coalesce(p_tax, -1) - v_tax) > 0.01
     or abs(coalesce(p_total, -1) - v_tot) > 0.01 then
    return jsonb_build_object('error', 'stale', 'subtotal', v_sub, 'tax', v_tax, 'total', v_tot);
  end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(v_on, 'YYMM');

    -- The counter still advances on every automatic issue, and the upsert's
    -- row lock is what makes the scan below safe: a second issuer blocks here
    -- until the first has committed its letter, so the two never read the same
    -- gap as free. What the counter gives is a bound to scan within, not the
    -- number itself.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- The lowest free slot, not the counter's own value. A letter removed
    -- releases its reference (serial_taken stopped counting removed letters on
    -- 2026-09-20), and without this the automatic path still counted upward
    -- past the gap: a client whose first two letters were issued in testing
    -- and removed started at 03 for ever. The counter is at least the number
    -- of letters issued this month, so a free slot exists at or below it
    -- unless somebody has typed references over the same range by hand; the
    -- cap covers that and refuses rather than looping.
    --
    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_try := 1;
    loop
      v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
              case when v_try < 100 then lpad(v_try::text, 2, '0') else v_try::text end;
      exit when not public.serial_taken(v_no);
      v_try := v_try + 1;
      if v_try > greatest(v_seq, 1) + 200 then
        return jsonb_build_object('error', 'no-serial');
      end if;
    end loop;
  end if;

  insert into public.client_documents
    (client_id, kind, number, issued_at, market, subtotal, tax, total,
     bill_to, lines, issued_by, client_code, idem_key)
  values
    (p_client, 'offer', v_no, v_on,
     public.client_bill_market(cl.market, cl.bill_sgd),
     -- the database's own figures, never the page's: the sen allowed
     -- above is for the stale check alone (2026-11-24)
     round(v_sub, 2), round(v_tax, 2), round(v_tot, 2),
     jsonb_build_object(
       'name', coalesce(cl.name, ''), 'legal_name', coalesce(cl.legal_name, ''),
       'address', coalesce(cl.billing_address, ''), 'regno', coalesce(cl.company_no, ''),
       'regno_old', coalesce(cl.company_no_old, ''), 'tin', coalesce(cl.tin, ''),
       'sst_no', coalesce(cl.sst_no, ''), 'sst_applies', cl.sst_applies is not false,
       'contact', coalesce(ct.name, ''), 'contact_role', coalesce(ct.role, ''),
       'contact_salutation', coalesce(ct.salutation, ''),
       -- A Singapore client billed in RM: its market and the rate in force,
       -- so the letter reads its figure in S$ beside it, as issued.
       'market', coalesce(cl.market, 'MY'),
       'fx_sgd', case when cl.market = 'SG' and not cl.bill_sgd then public.app_setting('fx_sgd', v_on) end,
       'phone', coalesce(ct.phone, ''), 'email', coalesce(ct.email, ''),
       'finance_email', coalesce(cl.finance_email, ''),
       'client_code', cl.client_code,
       'entity_id', v_ent.id,
       'owner', coalesce(p_deal ->> 'owner', ''), 'source', coalesce(p_deal ->> 'source', ''),
       'industry', coalesce(p_deal ->> 'industry', ''), 'stage', coalesce(p_deal ->> 'stage', ''),
       'enquiry', coalesce(p_deal ->> 'enquiry', ''),
       'terms', v_terms,
       -- The validity is one of the points typed (2026-10-23): a letter
       -- sent with it in its terms prints none of its own.
       'terms_own', coalesce(p_deal ->> 'terms_own', '') = 'true'),
     v_lines, coalesce(me.name, who), cl.client_code, nullif(btrim(p_idem), ''))
  returning id into v_id;

  insert into public.client_document_services (document_id, service_id)
    select v_id, s.id from unnest(p_services) s(id)
    on conflict do nothing;

  if p_replaces is not null then
    update public.client_documents set superseded_by = v_id where id = p_replaces;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.superseded', cl.name, v_old.number || ' replaced by ' || v_no);
  end if;

  select count(*) into v_n from public.client_document_services where document_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.issued', cl.name, v_no || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end);

  return jsonb_build_object('ok', true, 'id', v_id, 'number', v_no);
exception
  when unique_violation then
    -- Two presses that raced past the idempotency read: the loser reads the
    -- winner's letter back rather than making a second one.
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.client_documents
        where client_id = p_client and idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
      end if;
    end if;
    -- A typed reference two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;
revoke all on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) from public, anon;
grant execute on function public.issue_letter(uuid, uuid[], text, numeric, numeric, numeric, jsonb, uuid, boolean, text) to authenticated;

create or replace function public.ops_script_task(p_script uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not public.allowed('scripts', 'view') then return null; end if;
  return (select jsonb_build_object(
            'id', t.id, 'serial', public.ops_serial(t.task_no), 'title', public.ops_title(t),
            'stage', coalesce(st.label, t.stage_key), 'stage_group', st.stage_group)
            from public.ops_task_links k
            join public.ops_tasks t on t.id = k.task_id
            left join public.ops_workflow_stages st on st.id = t.stage_id
           where k.script_id = p_script and k.archived_at is null and public.ops_may_see_task(t.id)
           limit 1);
end $$;
revoke all on function public.ops_script_task(uuid) from public, anon;
grant execute on function public.ops_script_task(uuid) to authenticated;

create or replace function public.ops_record_tasks(p_type text, p_ref uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null then return '[]'::jsonb; end if;
  if p_type = 'campaign' and not public.allowed('campaigns', 'view') then return '[]'::jsonb; end if;
  if p_type = 'set' and not public.allowed('review', 'view') then return '[]'::jsonb; end if;
  if p_type is null or p_type not in ('campaign', 'set') then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x.j order by x.done, x.due nulls last, x.no)
      from (
        select distinct on (t.id)
               t.id, t.task_no as no,
               (t.completed_at is not null or t.cancelled_at is not null) as done,
               t.current_final_due_at as due,
               jsonb_build_object(
                 'id', t.id,
                 'serial', public.ops_serial(t.task_no),
                 'title', public.ops_title(t),
                 'stage_key', t.stage_key,
                 'stage', coalesce(s.label, initcap(replace(t.stage_key, '_', ' '))),
                 'stage_group', s.stage_group,
                 'owner', (select m.name from public.ops_task_assignees a
                             join public.team_members m on m.id = a.team_member_id
                            where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null
                            limit 1),
                 'final_due_at', t.current_final_due_at,
                 'completed_at', t.completed_at,
                 'cancelled_at', t.cancelled_at,
                 'link_id', k.id,
                 'post_id', k.post_id,
                 'post_no', case when k.post_id is not null then public.ops_post_no(k.post_id) end) as j
          from public.ops_task_links k
          join public.ops_tasks t on t.id = k.task_id
          left join public.ops_workflow_stages s
                 on s.id = t.stage_id
         where k.ref_type = p_type and k.ref_id = p_ref and k.archived_at is null
           and public.ops_may_see_task(t.id)
         order by t.id, (k.post_id is null), k.created_at
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.ops_record_tasks(text, uuid) from public, anon;
grant execute on function public.ops_record_tasks(text, uuid) to authenticated;

create or replace function public.ops_task_late(p_task uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select
      (t.current_final_due_at is not null
        and (t.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date
            < (now() at time zone 'Asia/Kuala_Lumpur')::date
        and (f.at is null or s.position < f.at))
      or
      (p.by is not null and p.by < now()
        and (pf.at is null or s.position < pf.at or s.stage_group in ('kiv', 'blocked')))
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.id = t.stage_id
      cross join lateral (
        select public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as by) p
      cross join lateral (
        select min(w.position) as at from public.ops_workflow_stages w
         where w.workflow_id = t.workflow_id and w.stage_group = 'client_review') f
      cross join lateral (
        select coalesce(min(w.position) filter (where w.stage_group = 'client_review'),
                        min(w.position) filter (where w.stage_group = 'internal_review')) as at
          from public.ops_workflow_stages w where w.workflow_id = t.workflow_id) pf
     where t.id = p_task
       and t.completed_at is null and t.cancelled_at is null and t.archived_at is null
  ), false)
$$;
revoke all on function public.ops_task_late(uuid) from public, anon, authenticated;

create or replace function public.ops_tasks_nudge(p_at timestamptz default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_at    timestamptz := coalesce(p_at, now());
  v_local timestamp := coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur';
  v_today date := (coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur')::date;
  v_every integer;
  v_start integer;
  m record;
  v_title text;
  v_body text;
  v_parts text[];
  v_last timestamptz;
  n integer := 0;
begin
  -- Nothing on a public holiday (RETENTION AND JOBS HELD).
  if public.public_holiday_on(v_today) is not null then return 0; end if;
  v_every := coalesce(public.app_setting('task_remind_hours', v_today), 3)::integer;
  v_start := coalesce(public.app_setting('task_start_days', v_today), 2)::integer;
  if v_every <= 0 or extract(isodow from v_today) > 5
     or extract(hour from v_local) < 10 or extract(hour from v_local) >= 18 then
    return 0;
  end if;
  for m in
    with floors as (
      select workflow_id, min(position) as at
        from public.ops_workflow_stages
       where stage_group = 'client_review'
       group by workflow_id
    ),
    pfloors as (
      select workflow_id,
             coalesce(min(position) filter (where stage_group = 'client_review'),
                      min(position) filter (where stage_group = 'internal_review')) as at
        from public.ops_workflow_stages
       group by workflow_id
    ),
    mine as (
      select a.team_member_id as member, k.id, a.assigned_at, k.priority_level, (c.vic_at is not null) as vic,
             public.ops_serial(k.task_no) || ' · ' || public.ops_title(k) as label,
             coalesce(c.name, 'Internal') as client,
             s.stage_group, s.position, f.at as review_at, pf.at as prio_at,
             public.ops_priority_by(coalesce(k.priority_at, k.created_at), k.priority_level) as prio_by,
             (k.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date as due_day,
             (coalesce(k.current_first_draft_due_at, k.current_final_due_at) at time zone 'Asia/Kuala_Lumpur')::date as first_day
        from public.ops_task_assignees a
        join public.ops_tasks k on k.id = a.task_id
        join public.team_members tm on tm.id = a.team_member_id
        join public.ops_workflow_stages s on s.id = k.stage_id
        left join public.clients c on c.id = k.client_id
        left join floors f on f.workflow_id = k.workflow_id
        left join pfloors pf on pf.workflow_id = k.workflow_id
       where a.responsibility = 'owner' and a.ended_at is null
         and tm.active and not coalesce(tm.system, false)
         and k.completed_at is null and k.cancelled_at is null and k.archived_at is null
         and coalesce(s.stage_group, '') <> 'cancelled'
    ),
    sorted as (
      select x.*,
             (x.prio_by is not null and (x.prio_at is null or x.position < x.prio_at
                                         or x.stage_group in ('kiv', 'blocked'))) as prio_runs,
             (x.review_at is null or x.position < x.review_at) as short_of_review
        from mine x
    ),
    sized as (
      select y.*,
             /* When it became overdue: the earlier of its priority's deadline
                and the end of its due day. */
             least(case when y.prio_runs and y.prio_by < v_at then y.prio_by end,
                   case when y.due_day < v_today and y.short_of_review
                        then (y.due_day + 1)::timestamp at time zone 'Asia/Kuala_Lumpur' end) as late_at,
             case
        when (y.due_day < v_today and y.short_of_review) or (y.prio_runs and y.prio_by < v_at) then 1
        when y.prio_runs and y.priority_level = 1 then 2
        when (y.due_day = v_today and y.short_of_review)
          or (y.prio_runs and (y.prio_by at time zone 'Asia/Kuala_Lumpur')::date = v_today) then 3
        when v_start > 0 and y.stage_group in ('intake', 'ready')
          and ((y.first_day is not null and y.first_day <= v_today + v_start)
            or (y.first_day is null and y.assigned_at <= v_at - make_interval(days => v_start))) then 4
      end as bucket
        from sorted y
    )
    select z.member,
           count(*) as total,
           count(*) filter (where z.bucket = 1) as late,
           count(*) filter (where z.bucket = 2) as urgent,
           count(*) filter (where z.bucket = 3) as today,
           count(*) filter (where z.bucket = 4) as idle,
           count(*) filter (where z.vic) as vic,
           max(z.late_at) filter (where z.vic and z.bucket = 1) as vic_late_at,
           (array_agg(z.id order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_id,
           (array_agg(z.bucket order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_bucket,
           (array_agg(z.client order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_client,
           (array_agg(z.prio_by order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1] as first_by,
           (array_agg(z.label order by not z.vic, z.bucket, coalesce(z.due_day, z.first_day), z.label))[1:3] as labels
      from sized z
     where z.bucket is not null
     group by z.member
     order by z.member
  loop
    /* Within the window nothing is sent, but a VIC client's task that has
       become overdue since this colleague's last reminder is told at once. */
    select max(o.created_at) into v_last from public.ops_notifications o
     where o.team_member_id = m.member and o.kind = 'tasks.nudge';
    if v_last > v_at - make_interval(mins => v_every * 60 - 10)
       and (m.vic_late_at is null or m.vic_late_at <= v_last) then
      continue;
    end if;
    if m.total = 1 then
      v_title := m.labels[1] || case m.first_bucket when 1 then ' is overdue.' when 2 then ' is Urgent.'
                                                  when 3 then ' is due today.' else ' has not started.' end;
      v_body := m.first_client || case when m.first_bucket = 2 and m.first_by is not null then
        ' · deliver by ' || to_char(m.first_by at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam') || ', ' ||
        public.register_day((m.first_by at time zone 'Asia/Kuala_Lumpur')::date) || '.' else '' end;
    else
      v_parts := array_remove(array[
        case when m.vic > 0 then m.vic || ' for VIC clients' end,
        case when m.late > 0 then m.late || ' overdue' end,
        case when m.urgent > 0 then m.urgent || ' Urgent' end,
        case when m.today > 0 then m.today || ' due today' end,
        case when m.idle > 0 then m.idle || ' not started' end], null);
      v_title := m.total || ' tasks need attention: ' || array_to_string(v_parts, ', ') || '.';
      v_body := array_to_string(m.labels, '; ') ||
                case when m.total > 3 then '; and ' || (m.total - 3) || ' more.' else '.' end;
    end if;
    insert into public.ops_notifications (team_member_id, task_id, kind, title, body, created_at, dedupe_key)
    values (m.member, case when m.total = 1 then m.first_id end, 'tasks.nudge', v_title, v_body, v_at,
            'tasks.nudge.' || m.member || '.' || to_char(v_local, 'YYYY-MM-DD-HH24'))
    on conflict (dedupe_key) do nothing;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.ops_tasks_nudge(timestamptz) from public, anon, authenticated;

create or replace function public.ops_report_of(
  p_from  timestamptz,
  p_to    timestamptz,
  p_light boolean)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
begin
  if not public.ops_granted('ops.reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;

  with
  /* Where client review begins in each workflow. The final due date is the
     day the work is owed AT that stage, so everything below that position is
     "has not reached the client yet". Read from `stage_group` and never from
     a stage key: the two seeded workflows name that stage differently. */
  floors as (
    select workflow_id, min(position) as at
      from public.ops_workflow_stages
     where stage_group = 'client_review'
     group by workflow_id
  ),
  /* Where a priority's deadline is met (2026-10-11): client review, else the
     workflow's first review (an everyday task's Review). */
  pfloors as (
    select workflow_id,
           coalesce(min(position) filter (where stage_group = 'client_review'),
                    min(position) filter (where stage_group = 'internal_review')) as at
      from public.ops_workflow_stages
     group by workflow_id
  ),
  live as (
    select t.*, s.label as stage_label, s.position as stage_position,
           s.stage_group, f.at as review_at,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by, pf.at as prio_at
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.id = t.stage_id
      left join floors f on f.workflow_id = t.workflow_id
      left join pfloors pf on pf.workflow_id = t.workflow_id
     where t.completed_at is null and t.cancelled_at is null
       and t.archived_at is null
       /* Client scope: a colleague on Own clients only reads the work of
          the clients they hold, and their own tasks always (2026-10-18). */
       and public.ops_task_in_scope(t.id)
  ),

  /* 1. WHAT IS RUNNING, by the words on the screen. Grouped by the stage's
        own label rather than by its group, because "what is on shooting" is
        the question and Shooting is a label, not a group. */
  running as (
    select jsonb_agg(x order by x ->> 'position', x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key, 'label', stage_label,
               'position', stage_position, 'stage_group', stage_group,
               'count', count(*)) as x
        from live
       where not p_light
       group by stage_key, stage_label, stage_position, stage_group
    ) q
  ),

  /* 2. WHAT IS LATE. Past the commitment and still short of client review,
        or past a priority's deadline and short of its review (On hold and
        Blocked still count): whichever comes first (the user, 2026-10-11).
        The same rule the queue row draws, stated once more here because a
        report a page computes for itself is a second definition. */
  late_now as (
    select l.*,
           (l.current_final_due_at is not null and (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date
            and (l.review_at is null or l.stage_position < l.review_at)) as due_late,
           (l.prio_by is not null and l.prio_by < now()
            and (l.prio_at is null or l.stage_position < l.prio_at or l.stage_group in ('kiv', 'blocked'))) as prio_late
      from live l
  ),
  late as (
    select jsonb_agg(x order by x ->> 'due_at') as j from (
      select jsonb_build_object(
               'task_id', l.id, 'task_no', l.task_no, 'title', l.title,
               'client', c.name, 'stage', l.stage_label,
               'due_at', case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                              then l.prio_by else l.current_final_due_at end,
               'days_over', greatest(case when l.due_late then (now() at time zone 'Asia/Kuala_Lumpur')::date - (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date end,
                                     case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 86400)::int end),
               'over_minutes', case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 60)::int end,
               'owner', (select tm.name
                           from public.ops_task_assignees a
                           join public.team_members tm on tm.id = a.team_member_id
                          where a.task_id = l.id and a.responsibility = 'owner'
                            and a.ended_at is null
                          limit 1)) as x
        from late_now l
        left join public.clients c on c.id = l.client_id
       where (l.due_late or l.prio_late) and not p_light
    ) q
  ),

  /* 3. HOW LONG EACH STAGE TAKES. A task enters a stage at the event that
        names it and leaves at the next event, or at its own ending, or now.
        Only spans that were ENTERED inside the period are counted, so the
        window means what it says and a task that sat in Editing since March
        does not land in every report for ever. */
  spans as (
    select e.task_id,
           e.to_value ->> 'stage_key' as stage_key,
           e.created_at as from_at,
           coalesce(
             lead(e.created_at) over (partition by e.task_id order by e.created_at),
             t.completed_at, t.cancelled_at, now()) as to_at
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
     where e.event_type in ('task_created', 'stage_changed')
       and e.to_value ->> 'stage_key' is not null
       and public.ops_task_in_scope(t.id)
       /* Only a span entered in the period is counted, and its end is the
          task's next event, never an earlier one: what came before the
          period is not read (2026-10-18). */
       and e.created_at >= p_from
  ),
  /* One row per span and no grouping: an earlier draft grouped by the span's
     own timestamps, which silently collapsed two tasks that entered the same
     stage in the same instant into one measurement. The label is looked up
     once per stage below instead of aggregated here. */
  span_mins as (
    select s.stage_key,
           extract(epoch from (s.to_at - s.from_at)) / 60 as mins
      from spans s
     where s.from_at >= p_from and s.from_at < p_to
       and s.to_at > s.from_at
  ),
  stage_time as (
    select jsonb_agg(x order by x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key,
               'label', coalesce((select w.label from public.ops_workflow_stages w
                                   where w.key = sm.stage_key limit 1), stage_key),
               'n', count(*),
               'median_minutes', round(percentile_cont(0.5) within group (order by mins))::int,
               'p90_minutes', round(percentile_cont(0.9) within group (order by mins))::int) as x
        from span_mins sm
       where not p_light
       group by stage_key
    ) q
  ),

  /* 4. WAS IT THERE ON TIME. Of the tasks that reached client review inside
        the period, how many got there on or before the date they were owed;
        the work still late is counted beside them (`late_open`).
        Replanning is counted beside it and never folded into it: an extension
        that moves the date would otherwise erase the miss it was granted for,
        and a rate that cannot be missed is not a measurement. */
  /* A task's FIRST entry into client review ever, counted in the period it
     fell in: its return after a revision is never counted again, in its own
     period or a later one (audit 2026-11-15). */
  reached as (
    select f.* from (
      select distinct on (e.task_id)
             e.task_id, e.created_at as at, t.current_final_due_at as due,
             public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
             (t.original_final_due_at is distinct from t.current_final_due_at) as replanned
        from public.ops_task_events e
        join public.ops_tasks t on t.id = e.task_id
        join public.ops_workflow_stages w
          on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
       where e.event_type = 'stage_changed'
         and w.stage_group = 'client_review'
         and public.ops_task_in_scope(t.id)
         and e.created_at < p_to
       order by e.task_id, e.created_at
    ) f
     where f.at >= p_from
  ),
  /* Work still short of its review and past its deadline is a miss too
     (2026-10-19, the user: "there are late tasks yet showing 100% on time
     delivery"): counted in the period its first missed deadline fell in,
     and in any period that runs to now (its end within ten minutes of now:
     the page names the moment it asks), where it is still late. A task
     counted as reached in the period is not counted again. */
  late_open as (
    select l.id
      from late_now l
     where (l.due_late or l.prio_late)
       and not exists (select 1 from reached r where r.task_id = l.id)
       and (case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                 then l.prio_by else l.current_final_due_at end) < p_to
       and ((case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                  then l.prio_by else l.current_final_due_at end) >= p_from
            or p_to >= now() - interval '10 minutes')
  ),
  on_time as (
    select jsonb_build_object(
             'reached', count(*),
             'met', count(*) filter (where (due is null or (at at time zone 'Asia/Kuala_Lumpur')::date <= (due at time zone 'Asia/Kuala_Lumpur')::date)
                                       and (prio_by is null or at <= prio_by)),
             'missed', count(*) filter (where not ((due is null or (at at time zone 'Asia/Kuala_Lumpur')::date <= (due at time zone 'Asia/Kuala_Lumpur')::date)
                                                 and (prio_by is null or at <= prio_by))),
             'late_open', (select count(*) from late_open),
             'replanned', count(*) filter (where replanned)) as j
      from reached
  ),
  /* 4b. POSTED ON TIME (2026-10-19). Of the content whose post date fell in
         the period and has passed (Malaysia's day), or which went live, how
         much went live by its post date. Client approval counts here, as it
         does for the client; on-time delivery above is the team's own. */
  posted as (
    select jsonb_build_object(
             'due', count(*),
             'met', count(*) filter (where t.live_at is not null
                                       and (t.live_at at time zone 'Asia/Kuala_Lumpur')::date
                                           <= (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date)) as j
      from public.ops_tasks t
     where t.publish_at >= p_from and t.publish_at < p_to
       and t.cancelled_at is null and t.archived_at is null
       and (t.live_at is not null
            or (t.publish_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date)
       and exists (select 1 from public.ops_workflow_stages s
                    where s.workflow_id = t.workflow_id and s.stage_group = 'live')
       and public.ops_task_in_scope(t.id)
  ),

  /* 5. BY PERSON. The foundation of a KPI and not a KPI: what somebody
        finished in the window, how much of it was on time, and how long their
        work took end to end. No ranking and no score — a number a person can
        check is worth more than a league table nobody trusts. */
  done as (
    select t.id, t.created_at, t.completed_at as ended,
           t.current_final_due_at as due,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
           /* When a priority's deadline was met: the first move into its
              review or beyond (never On hold, Blocked or Cancelled). */
           (select min(e.created_at)
              from public.ops_task_events e
              join public.ops_workflow_stages w
                on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
              join pfloors pf on pf.workflow_id = t.workflow_id
             where e.task_id = t.id and e.event_type = 'stage_changed'
               and w.position >= pf.at and w.stage_group not in ('kiv', 'blocked', 'cancelled')) as met_at,
           /* When it reached client review (2026-10-22, OVW-2): the day the
              due date is owed at, as the on-time ring reads it. */
           (select min(e.created_at)
              from public.ops_task_events e
              join public.ops_workflow_stages w
                on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
             where e.task_id = t.id and e.event_type = 'stage_changed'
               and w.stage_group = 'client_review') as review_at,
           (select a.team_member_id
              from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc
             limit 1) as owner_id
      from public.ops_tasks t
     where t.completed_at is not null
       and t.completed_at >= p_from and t.completed_at < p_to
       and public.ops_task_in_scope(t.id)
  ),
  by_person as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', d.owner_id,
               'name', coalesce(tm.name, 'Unassigned'),
               'completed', count(*),
               'on_time', count(*) filter (where (d.due is null
                                                 or (coalesce(d.review_at, d.met_at, d.ended) at time zone 'Asia/Kuala_Lumpur')::date
                                                    <= (d.due at time zone 'Asia/Kuala_Lumpur')::date)
                                         and (d.prio_by is null or coalesce(d.met_at, d.ended) <= d.prio_by)),
               'median_cycle_minutes',
                 round(percentile_cont(0.5) within group (
                   order by extract(epoch from (d.ended - d.created_at)) / 60))::int) as x
        from done d
        left join public.team_members tm on tm.id = d.owner_id
       group by d.owner_id, tm.name
    ) q
  ),

  /* 6. WHO IS CARRYING THE OPEN WORK (2026-09-28). One row a Task Owner:
        the open tasks they hold, and how many of those are late by the rule
        in 2 above. The team's whole queue is `ops.all`, so it is answered
        only where that part is granted. */
  open_by_person as (
    select jsonb_agg(x order by (x ->> 'open')::int desc, x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', o.owner_id,
               'name', coalesce(tm.name, 'Unassigned'),
               'open', count(*),
               'late', count(*) filter (where o.is_late)) as x
        from (select l.id,
                     (select a.team_member_id
                        from public.ops_task_assignees a
                       where a.task_id = l.id and a.responsibility = 'owner' and a.ended_at is null
                       limit 1) as owner_id,
                     (l.due_late or l.prio_late) as is_late
                from late_now l) o
        left join public.team_members tm on tm.id = o.owner_id
       where public.ops_granted('ops.all', 'view') and not p_light
       group by o.owner_id, tm.name
    ) q
  )

  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'running',    coalesce((select j from running), '[]'::jsonb),
           'late',       coalesce((select j from late), '[]'::jsonb),
           'stage_time', coalesce((select j from stage_time), '[]'::jsonb),
           'on_time',    coalesce((select j from on_time), '{}'::jsonb),
           'posted',     coalesce((select j from posted), '{}'::jsonb),
           'by_person',  coalesce((select j from by_person), '[]'::jsonb),
           'open_by_person', case when public.ops_granted('ops.all', 'view')
                                  then coalesce((select j from open_by_person), '[]'::jsonb) end)
    into out;

  return out;
end $$;
revoke all on function public.ops_report_of(timestamptz, timestamptz, boolean) from public, anon;
grant execute on function public.ops_report_of(timestamptz, timestamptz, boolean) to authenticated;

-- END OF LOOKUPS BY ID --------------------------------------------------------

select public.functions_tidy();
