-- ===========================================================================
-- A CLIENT'S SCRIPT SHOWS ITS PICTURES (2026-11-18)
-- ===========================================================================
-- WHY: the user, 2026-11-18: the client's video script "should show the
-- drawings, else it will just be a tons of words". The scene pictures were
-- the team's alone (2026-11-05); the client's link now reads them too.
--
-- WHAT IT CHANGES
--   * `get_scripts` answers each scene's `photo_thumb` and `ai_thumb` (the
--     360px JPEG data URLs) and `ai_frame` (the drawing as data, built by
--     js/frames.js). The stored files (`photo_url`, `ai_url`), who added a
--     photo and when stay withheld: the link carries no media pass.
--
-- ORDER: this file (connector), then the page. An open page ignores the
-- new keys. Safe to run twice.
--
-- ROLLBACK: run get_scripts from PAGES IN THE CLIENT'S LANGUAGE again.
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
               'aspect', s.aspect, 'length_seconds', s.length_seconds, 'plan', s.plan,
               'context', s.context, 'vo', s.vo, 'remarks', s.remarks,
               'shared_at', s.shared_at, 'updated_at', s.updated_at,
               'scenes', coalesce((select jsonb_agg(jsonb_build_object('id', sc.id, 'position', sc.position,
                                                     'visual', sc.visual, 'line', sc.line,
                                                     't_from', sc.t_from, 't_to', sc.t_to,
                                                     'shot_size', sc.shot_size, 'angle', sc.angle,
                                                     'camera_move', sc.camera_move, 'on_screen', sc.on_screen,
                                                     'sound', sc.sound,
                                                     -- the scene's picture: the small copies and the
                                                     -- drawing, never the stored file or who added it
                                                     'photo_thumb', sc.photo_thumb, 'ai_thumb', sc.ai_thumb,
                                                     'ai_frame', sc.ai_frame)
                                                     order by sc.position)
                                     from public.video_script_scenes sc where sc.script_id = s.id), '[]'::jsonb))
             order by s.period desc, s.seq)
        from public.video_scripts s
       where s.client_id = v_cl.id and s.status = 'shared'), '[]'::jsonb),
    'lang', public.client_lang(v_cl.id));
end $$;
revoke all on function public.get_scripts(text) from public;
grant execute on function public.get_scripts(text) to anon;
grant execute on function public.get_scripts(text) to authenticated;

-- END OF A CLIENT'S SCRIPT SHOWS ITS PICTURES -------------------------------

select public.functions_tidy();
