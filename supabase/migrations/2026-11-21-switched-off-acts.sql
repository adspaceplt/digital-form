-- ===========================================================================
-- SWITCHED-OFF ACTS (2026-11-21)
-- ===========================================================================
-- WHY: the user, 2026-11-21, approving release A of the switched-off acts:
-- an act Settings or a daily limit has stopped stays drawn, disabled, and
-- says why, as the send switches already do. The page could not know a
-- colleague's daily AI limit was used until a press was refused, nor that
-- Bukku was not connected until a send failed.
--
-- WHAT IT CHANGES
--   * `ai_uses_left()` (any active colleague, their own figures alone):
--     for each AI use (`caption`, `draft`, `check`, `next`, `script`,
--     `picture`, `analysis`, `checklist`, `analytics`, `agent`) the
--     colleague's daily limit (`ai_cap`) and what is left of it today, as
--     each use's own `ai_*_left` counts it, and `next`, when the day's count
--     starts again. A per-report limit is still refused at the press.
--   * `bukku_ready()` (any active colleague): `connected` while the nightly
--     Bukku read (`job_beats` `bukku-nightly`) has run in the last three
--     days. `bukku-sync` answers `bukku-not-set-up` before that read where
--     Bukku's token is not set, so no beat is written.
--   Nothing is written; nothing else moves.
--
-- ORDER: this file, then the pages. An old page never asks either; a new
-- page on the old database reads neither and draws every act on.
-- Safe to run twice.
--
-- ROLLBACK: drop function public.ai_uses_left(); drop function
-- public.bukku_ready(); (SQL Editor).

create or replace function public.ai_uses_left()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me    public.team_members := public.ops_me();
  v_since timestamptz := public.ai_draft_day();
  v_out   jsonb := '{}'::jsonb;
  v_use   record;
  v_lim   integer;
begin
  if v_me.id is null then return jsonb_build_object('error', 'denied'); end if;
  for v_use in
    select x.purpose, x.cap
      from (values ('caption', 'caption'), ('draft', 'drafts'), ('check', 'checks'), ('next', 'next'),
                   ('script', 'script'), ('picture', 'picture'), ('analysis', 'analysis'),
                   ('checklist', 'checklist'), ('analytics', 'analytics'), ('agent', 'agent')) x(purpose, cap)
  loop
    v_lim := public.ai_cap(v_me.id, v_use.cap);
    v_out := v_out || jsonb_build_object(v_use.purpose, jsonb_build_object('limit', v_lim,
      'left', greatest(0, v_lim - (select count(*) from public.ai_drafts d
        where d.team_member_id = v_me.id and d.purpose = v_use.purpose
          and d.created_at >= v_since and d.outcome <> 'failed')::integer)));
  end loop;
  return jsonb_build_object('ok', true, 'uses', v_out, 'next', v_since + interval '1 day');
end $$;
revoke all on function public.ai_uses_left() from public, anon;
grant execute on function public.ai_uses_left() to authenticated;

create or replace function public.bukku_ready()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'connected', exists (
      select 1 from public.job_beats b where b.job = 'bukku-nightly' and b.ran_at > now() - interval '3 days')) end
$$;
revoke all on function public.bukku_ready() from public, anon;
grant execute on function public.bukku_ready() to authenticated;

-- END OF SWITCHED-OFF ACTS ---------------------------------------------------

select public.functions_tidy();
