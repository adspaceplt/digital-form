-- =============================================================================
-- THE QUALITY CHECK IS A GATE
-- 2026-09-21
--
-- Asked for by the user on 2026-09-21: "qc should actually be a gate, despite
-- one person two person … if unsure always pull in another person to review
-- too", and "anyone can login and review, anyone can push, just that there is
-- a record of whose actually performed the actions".
--
-- WHAT WAS WRONG. Release to client moved the booking with a direct table
-- write from the browser (`db.from('campaign_options').update({state:
-- 'reviewing'})`). The nine-check sheet was therefore a speed bump on one
-- page and not a gate: nothing in the database knew a check had been made,
-- and a second reviewer could not be required at all, because "the second may
-- not be the first" is a rule only the server can hold.
--
-- WHAT THIS ADDS. One column, one table, one function and one trigger.
--
--   campaign_options.qc_second_wanted  the first checker asked for a second
--   option_qc                          who checked, when, for which round
--   campaign_qc_pass()                 the only way to reach `reviewing`
--   campaign_options_qc_gate           refuses the move whatever is sent
--
-- THE RULE, IN ONE SENTENCE. A booking reaches Client review when at least
-- one team member has completed the check, and at least two distinct ones
-- have where somebody asked for a second.
--
-- NOBODY IS ASSIGNED. The user chose this deliberately: the second reviewer
-- is anyone on the team who is not the person who asked. So a colleague who
-- leaves, or is on a shoot, can never strand a booking behind their own
-- account, and an admin or a manager clears it like anybody else. Telling the
-- second person is verbal; there is no notification and no queue, because the
-- campaign section is already carrying more than a new person can hold.
--
-- WHAT IS RECORDED IS THE PERSON, NOT THE NINE TICKS. Every check is
-- required, so one row per person is the evidence that all nine were made;
-- storing nine booleans a person would be nine times the data for the same
-- fact. The ticks stay on the page while somebody works through them.
--
-- A SENT-BACK BOOKING IS CHECKED FROM THE TOP. The rows key on
-- `revision_round`, which Request changes already increments, so a different
-- file is a different check and last week's sign-off cannot release it.
--
-- SAFE TO RUN TWICE. `create table if not exists`, `add column if not
-- exists`, `create or replace`, and the trigger is dropped before it is made.
--
-- ROLLBACK:
--   drop trigger if exists campaign_options_qc_gate on public.campaign_options;
--   drop function if exists public.campaign_options_qc_gate();
--   drop function if exists public.campaign_qc_pass(uuid, boolean);
--   drop table if exists public.option_qc;
--   alter table public.campaign_options drop column if exists qc_second_wanted;
-- =============================================================================

alter table public.campaign_options
  add column if not exists qc_second_wanted boolean not null default false;

-- Who checked a booking, when, and for which revision round. One row a person
-- a round: pressing the check twice is the same check, which is what stops a
-- single person satisfying a two-person gate by trying again.
create table if not exists public.option_qc (
  id             uuid primary key default gen_random_uuid(),
  option_id      uuid not null references public.campaign_options(id) on delete cascade,
  team_member_id uuid not null references public.team_members(id) on delete restrict,
  round          integer not null default 0,
  checked_at     timestamptz not null default now(),
  unique (option_id, team_member_id, round)
);
alter table public.option_qc enable row level security;
create index if not exists option_qc_option on public.option_qc(option_id, round);

-- Read-only to a browser, like every other table whose writes are a function.
-- There is exactly one foreign key from here to `team_members`, so a
-- `team_members(name)` embed is unambiguous and PostgREST will answer it.
drop policy if exists option_qc_read on public.option_qc;
create policy option_qc_read on public.option_qc
  for select to authenticated using (public.is_team());

-- How many distinct people have completed the check for the round a booking
-- is on. Its own function because the page, the gate and the trigger all ask
-- the same question, and three copies of one rule drift.
create or replace function public.option_qc_count(p_option uuid)
returns integer
language sql security definer stable set search_path = public as $$
  select count(distinct q.team_member_id)::int
    from public.option_qc q
    join public.campaign_options o on o.id = q.option_id
   where q.option_id = p_option
     and q.round = coalesce(o.revision_round, 0)
$$;
grant execute on function public.option_qc_count(uuid) to authenticated;

-- Whether this booking may be released as it stands.
create or replace function public.option_qc_ok(p_option uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select case
           when coalesce(o.qc_second_wanted, false)
             then public.option_qc_count(p_option) >= 2
           else public.option_qc_count(p_option) >= 1
         end
    from public.campaign_options o where o.id = p_option
$$;
grant execute on function public.option_qc_ok(uuid) to authenticated;

-- The one way a booking reaches Client review.
--
--   p_want_second  true  record my check and hold it for somebody else
--                  false record my check and release it if the gate allows
--
-- Pressing it a second time as the same person is the same check: the insert
-- conflicts, the count does not move, and a booking held for a second
-- reviewer stays held. That is the whole of the no-self-approval rule, and it
-- is here rather than on the page because a rule a browser enforces is a rule
-- a browser can skip.
create or replace function public.campaign_qc_pass(
  p_option uuid, p_want_second boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members;
  o    public.campaign_options;
  n    integer;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;

  select * into o from public.campaign_options where id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'no-booking'); end if;
  if o.state <> 'submitted' then
    return jsonb_build_object('error', 'not-submitted');
  end if;

  insert into public.option_qc (option_id, team_member_id, round)
  values (p_option, me.id, coalesce(o.revision_round, 0))
  on conflict (option_id, team_member_id, round) do nothing;

  if p_want_second and not coalesce(o.qc_second_wanted, false) then
    update public.campaign_options set qc_second_wanted = true where id = p_option;
    o.qc_second_wanted := true;
  end if;

  n := public.option_qc_count(p_option);
  if coalesce(o.qc_second_wanted, false) and n < 2 then
    return jsonb_build_object('state', 'waiting', 'checks', n, 'second', true);
  end if;

  update public.campaign_options
     set state = 'reviewing', changes_by = null
   where id = p_option;
  return jsonb_build_object('state', 'reviewing', 'checks', n,
                            'second', coalesce(o.qc_second_wanted, false));
end $$;
grant execute on function public.campaign_qc_pass(uuid, boolean) to authenticated;

-- And the gate itself. Row level security on this table is still the
-- permissive one the repository carries as an open finding, so without this
-- the rule above would hold only for callers who chose to use the function.
-- It fires on the move INTO Client review and on nothing else, so every other
-- step on a creator's card is untouched and a booking already there is left
-- exactly as it stands.
create or replace function public.campaign_options_qc_gate()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.state = 'reviewing' and coalesce(old.state, '') is distinct from 'reviewing'
     and not public.option_qc_ok(new.id) then
    raise exception 'qc-required'
      using hint = 'Release to client needs the quality check completed.';
  end if;
  return new;
end $$;

drop trigger if exists campaign_options_qc_gate on public.campaign_options;
create trigger campaign_options_qc_gate
  before update on public.campaign_options
  for each row execute function public.campaign_options_qc_gate();

-- A booking sent back to the creator starts its check again: the round moves,
-- so the rows above no longer count, and whether a second reviewer was wanted
-- is a judgement about the file that just changed.
create or replace function public.campaign_qc_reset(p_option uuid)
returns void
language sql security definer set search_path = public as $$
  update public.campaign_options set qc_second_wanted = false where id = p_option
$$;
grant execute on function public.campaign_qc_reset(uuid) to authenticated;
