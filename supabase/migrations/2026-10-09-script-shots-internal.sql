-- ===========================================================================
-- SCRIPT SHOTS INTERNAL — a script's clip numbers (VC#) and Shot ticks are
-- the team's alone: the client link reads the script and never the crew's
-- record of the day.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/vssql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-09: "the VC# and shot check box, remove
-- from all client-facing site; just internal admin or the pwa key in would
-- do")
--   1. `get_scripts(p_token)` sends each published script's facts, its
--      context, voice-over, scenes and notes, and no longer any scene's clip
--      number or tick, nor the voice-over's.
--   2. `script_shot_link(…)` answers `closed`: the clip numbers are recorded
--      in the console (`video_script_shot`, Video Scripts at Work). Its
--      signature and grant stay, so an open page is answered rather than
--      refused.
--
-- ROLLBACK
--   Restate get_scripts and script_shot_link from the SCRIPTS BY MONTH band.
-- ===========================================================================

create or replace function public.get_scripts(p_token text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  v_cl public.clients;
begin
  select * into v_cl from public.clients c
   where c.script_key = p_token and p_token is not null and c.active;
  if v_cl.id is null then return jsonb_build_object('error', 'not_found'); end if;
  return jsonb_build_object(
    'client', jsonb_build_object('name', v_cl.name, 'logo_url', v_cl.logo_url),
    'scripts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'code', s.code, 'period', s.period, 'kind', s.kind,
               'title', s.title, 'reference_url', s.reference_url, 'platform', s.platform,
               'language', s.language, 'shoot_on', s.shoot_on, 'shoot_time', s.shoot_time,
               'venue', s.venue, 'duration_minutes', s.duration_minutes, 'cast_names', s.cast_names,
               'context', s.context, 'vo', s.vo, 'remarks', s.remarks,
               'shared_at', s.shared_at, 'updated_at', s.updated_at,
               'scenes', coalesce((select jsonb_agg(jsonb_build_object('id', sc.id, 'position', sc.position,
                                                     'visual', sc.visual, 'line', sc.line)
                                                     order by sc.position)
                                     from public.video_script_scenes sc where sc.script_id = s.id), '[]'::jsonb))
             order by s.period desc, s.seq)
        from public.video_scripts s
       where s.client_id = v_cl.id and s.status = 'shared'), '[]'::jsonb));
end $$;

revoke all on function public.get_scripts(text) from public;

grant execute on function public.get_scripts(text) to anon;

grant execute on function public.get_scripts(text) to authenticated;

create or replace function public.script_shot_link(p_token text, p_script uuid, p_scene uuid, p_on boolean,
                                                   p_vc text default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('error', 'closed')
$$;

revoke all on function public.script_shot_link(text, uuid, uuid, boolean, text) from public;

grant execute on function public.script_shot_link(text, uuid, uuid, boolean, text) to anon;

grant execute on function public.script_shot_link(text, uuid, uuid, boolean, text) to authenticated;

-- END OF SCRIPT SHOTS INTERNAL ------------------------------------------------

select public.functions_tidy();
