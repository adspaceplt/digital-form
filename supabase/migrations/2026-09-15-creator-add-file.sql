-- ===========================================================================
-- 2026-09-15  creator_add_file: the ambiguous `id`
--
-- WHAT WAS WRONG
--   The function declared a variable called `id` and then looked the booking
--   up with an unqualified `where id = p_option`. PL/pgSQL resolves that
--   ambiguity when the function is CALLED, not when it is created, so the
--   schema applied cleanly and every creator upload failed with
--   `column reference "id" is ambiguous`. The file reached S3; the row that
--   makes it visible was never written, so Submit then refused the booking as
--   empty.
--
-- WHAT THIS CHANGES
--   One function body. No tables, no columns, no policies, no data. The
--   signature is unchanged, so `create or replace` keeps the existing owner
--   and grants; the grant below is repeated only so the file stands alone.
--
-- HOW TO RUN IT
--   Supabase dashboard > SQL editor > paste this file > Run. Safe to run more
--   than once. Nothing else in supabase/schema.sql needs to be re-run for
--   this fix: a full re-run of that file would also re-apply fifteen
--   unrelated data migrations (team roles, rate card minimums, client slugs,
--   the stage clock backfill, the team stand-down repair) and briefly drop
--   and recreate fifty-six policies and triggers on a live database.
--
-- ROLLBACK
--   At the foot of this file, commented out. It restores the previous
--   definition exactly, which means it restores the defect: uploads stop
--   recording again. It is here for completeness, not as a recommended step.
-- ===========================================================================

create or replace function public.creator_add_file(
  p_code text, p_option uuid, p_url text, p_name text, p_kind text, p_bytes bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr     creators%rowtype;
  o      campaign_options%rowtype;
  new_id uuid;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  -- Qualified, and the variable is not called `id`.
  select * into o from campaign_options co
   where co.id = p_option and co.creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  insert into campaign_deliverables (option_id, url, name, kind, bytes, round)
  values (p_option, p_url, p_name, coalesce(p_kind, 'file'), p_bytes,
          greatest(o.revision_round, 1))
  returning campaign_deliverables.id into new_id;
  return jsonb_build_object('id', new_id);
end $$;

grant execute on function
  public.creator_add_file(text, uuid, text, text, text, bigint) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Check it took. Both should return true.
-- ---------------------------------------------------------------------------
-- select prosrc not like '%where id = p_option%' as no_longer_ambiguous
--   from pg_proc where proname = 'creator_add_file';
--
-- select has_function_privilege('anon',
--   'public.creator_add_file(text, uuid, text, text, text, bigint)', 'execute');

-- ---------------------------------------------------------------------------
-- ROLLBACK (restores the previous, broken definition)
-- ---------------------------------------------------------------------------
-- create or replace function public.creator_add_file(
--   p_code text, p_option uuid, p_url text, p_name text, p_kind text, p_bytes bigint)
-- returns jsonb
-- language plpgsql security definer set search_path = public as $$
-- declare
--   cr creators%rowtype;
--   o  campaign_options%rowtype;
--   id uuid;
-- begin
--   select * into cr from creators where access_code = upper(p_code) and active;
--   if not found then return jsonb_build_object('error', 'not-found'); end if;
--   select * into o from campaign_options where id = p_option and creator_id = cr.id;
--   if not found then return jsonb_build_object('error', 'not-found'); end if;
--   if not public.creator_can_deliver(o.state) then
--     return jsonb_build_object('error', 'closed');
--   end if;
--   insert into campaign_deliverables (option_id, url, name, kind, bytes, round)
--   values (p_option, p_url, p_name, coalesce(p_kind, 'file'), p_bytes,
--           greatest(o.revision_round, 1))
--   returning campaign_deliverables.id into id;
--   return jsonb_build_object('id', id);
-- end $$;
--
-- Files already recorded are untouched by either direction: this migration
-- changes behaviour from the next call onwards and writes nothing itself.
