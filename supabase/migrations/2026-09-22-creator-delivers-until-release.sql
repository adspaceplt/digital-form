-- 2026-09-22  A creator may add to a hand-in until the team releases it.
--
-- `creator_can_deliver` answered `pending_draft` and `changes` only, so a
-- creator who pressed Submit after one file found the upload box gone with
-- the second file still on their phone. `submitted` is ours to review and not
-- yet the client's, so it is open to more files until Release to client
-- moves it on. Taking a file back off stays shut at `submitted`, through the
-- new `creator_can_retract`, so a submission under review cannot be emptied
-- from the creator's side. Reported and decided by the user on 2026-09-22.
--
-- Three functions redefined, one added. No table, column, policy or trigger
-- changes; safe to run twice.
--
--   creator_can_deliver     adds `submitted`
--   creator_can_retract     new: `pending_draft`, `changes`
--   creator_remove_file     asks creator_can_retract instead of creator_can_deliver
--   creator_submit          a second press at `submitted` logs `· updated`
--
-- POST-MIGRATION VERIFICATION
--   select public.creator_can_deliver('submitted');   -- true
--   select public.creator_can_retract('submitted');   -- false
--
-- ROLLBACK
--   Re-run this repository's `supabase/schema.sql` at the commit before this
--   migration; `creator_can_retract` may be left in place, unread.

create or replace function public.creator_can_deliver(p_state text)
returns boolean language sql immutable as $$
  select p_state in ('pending_draft', 'changes', 'submitted')
$$;
create or replace function public.creator_can_retract(p_state text)
returns boolean language sql immutable as $$
  select p_state in ('pending_draft', 'changes')
$$;

create or replace function public.creator_remove_file(p_code text, p_file uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr creators%rowtype;
  n  integer;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  update campaign_deliverables d set removed_at = now()
   where d.id = p_file and d.removed_at is null
     and exists (select 1 from campaign_options o
                  where o.id = d.option_id and o.creator_id = cr.id
                    and public.creator_can_retract(o.state));
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.creator_submit(p_code text, p_option uuid, p_caption text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr creators%rowtype;
  o  campaign_options%rowtype;
  n  integer;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  select count(*) into n from campaign_deliverables
   where option_id = p_option and removed_at is null;
  if n = 0 then return jsonb_build_object('error', 'empty'); end if;

  update campaign_options
     set state = 'submitted', draft_caption = p_caption, submitted_at = now(),
         changes_by = null
   where id = p_option;

  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.submitted', c.title,
         n::text || ' file' || case when n = 1 then '' else 's' end || ' handed in'
         || case when o.state = 'submitted' then ' · updated' else '' end
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'files', n);
end $$;

grant execute on function public.creator_remove_file(text, uuid) to anon, authenticated;
grant execute on function public.creator_submit(text, uuid, text) to anon, authenticated;
