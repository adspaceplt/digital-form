-- ===========================================================================
-- A CLIENT'S HISTORY KEPT BY ITS ID (2026-11-27)
-- ===========================================================================
-- WHY: `activity_log` held no client id, and a client's Record of changes
-- read its lines by subject, the name the line was written with; a rename
-- left the earlier lines behind (Bizgrowth Business Management, renamed
-- twice on 2026-11-27, showed 1 of its 24 lines). A record is traced by its
-- id, never by its name.
-- WHAT IT CHANGES
--   * `activity_log.client_id` (uuid, nullable, on delete set null),
--     indexed.
--   * `activity_client_note()`: after a write to a client's own rows
--     (`clients` and the tables keyed on one client), the transaction
--     remembers that client's id (`adspace.log_client`) and gives it to
--     the client lines (`activity_about_client`) this transaction already
--     filed without one.
--   * `activity_log_client()` (before insert): a client line filed without a
--     client id takes the one the transaction remembers. A line given one
--     (the console names the client it acts on) keeps it. Never resolved
--     from a name; a client no longer held is never named.
--   * Backfill: a line takes the client whose name it was written with,
--     the client's name history read from its own `client.edited` lines
--     (`Brand name: A → B`), its current and legal names; a name more than
--     one client has held is left unfilled.
-- ORDER: this file first (the column must stand before the pages send it),
-- then the pages. An open tab served before reads by name as it did.
-- ROLLBACK: drop trigger activity_log_client on public.activity_log; drop
-- each `<table>_activity_client` trigger; drop function
-- public.activity_log_client(), public.activity_client_note(),
-- public.activity_about_client(text); the pages
-- read by id, so the column stays (dropping it breaks the console).
-- Safe to run twice.

-- ACTIVITY CLIENT ID ----------------------------------------------------------

alter table public.activity_log add column if not exists client_id uuid
  references public.clients(id) on delete set null;
create index if not exists activity_log_client_idx on public.activity_log (client_id, created_at desc)
  where client_id is not null;

/* The lines a client's own record files: its section's, and a document's.
   A campaign's, a task's or a colleague's line in the same transaction
   stays its own. */
create or replace function public.activity_about_client(p_action text)
returns boolean
language sql stable set search_path = public as $$
  select p_action like 'client.%' or p_action like 'contact.%' or p_action like 'quotation.%'
      or p_action like 'document.%' or p_action in ('link.reset', 'service.override')
      or public.activity_section(p_action) = 'clients'
$$;
revoke all on function public.activity_about_client(text) from public, anon, authenticated;

create or replace function public.activity_client_note()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  v uuid;
begin
  v := case when tg_table_name = 'clients' then (j ->> 'id')::uuid else (j ->> 'client_id')::uuid end;
  if v is null or not exists (select 1 from public.clients c where c.id = v) then return null; end if;
  if coalesce(current_setting('adspace.log_client', true), '') <> v::text then
    perform set_config('adspace.log_client', v::text, true);
    update public.activity_log a set client_id = v
     where a.client_id is null and a.created_at = now() and public.activity_about_client(a.action);
  end if;
  return null;
end $$;
revoke all on function public.activity_client_note() from public, anon, authenticated;

create or replace function public.activity_log_client()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v text := nullif(current_setting('adspace.log_client', true), '');
begin
  if new.client_id is null and v is not null and public.activity_about_client(new.action) then
    if exists (select 1 from public.clients c where c.id = v::uuid) then new.client_id := v::uuid; end if;
  end if;
  return new;
end $$;
revoke all on function public.activity_log_client() from public, anon, authenticated;

drop trigger if exists activity_log_client on public.activity_log;
create trigger activity_log_client before insert on public.activity_log
  for each row execute function public.activity_log_client();

do $$
declare t text;
begin
  foreach t in array array['clients', 'client_brands', 'client_entities', 'client_contacts', 'client_checklists',
                           'client_detail_forms', 'client_ad_debtors', 'client_services', 'client_touches',
                           'client_documents', 'client_emails', 'client_requests', 'quotations',
                           'quotation_drafts', 'brand_analyses', 'feedback_requests', 'feedback_responses',
                           'invoice_emails', 'meta_links', 'documents'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I on public.%I', t || '_activity_client', t);
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.activity_client_note()',
                     t || '_activity_client', t);
    end if;
  end loop;
end $$;

-- Backfill: the names each client has held, from its own rename lines.
with recursive hist(client_id, name) as (
  select c.id, lower(btrim(c.name)) from public.clients c where nullif(btrim(c.name), '') is not null
  union
  select c.id, lower(btrim(c.legal_name)) from public.clients c where nullif(btrim(c.legal_name), '') is not null
  union
  select h.client_id, lower(btrim(m[1]))
    from hist h
    join public.activity_log a on a.action = 'client.edited' and lower(btrim(a.subject)) = h.name
    cross join lateral regexp_matches(a.detail, 'Brand name: ([^;→]+) → ([^;]+)', 'g') m
   where lower(btrim(m[2])) = h.name and nullif(btrim(m[1]), '') is not null and lower(btrim(m[1])) <> 'not set'
),
one as (
  select name, min(client_id::text)::uuid client_id from hist group by name having count(distinct client_id) = 1
)
update public.activity_log a set client_id = o.client_id
  from one o
 where a.client_id is null and lower(btrim(a.subject)) = o.name;

select public.functions_tidy();
