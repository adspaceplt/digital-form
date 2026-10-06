-- ===========================================================================
-- HR LETTERS SHARED — an HR letter issued to a colleague is theirs to read in
-- My performance (Letters), behind the same fresh proof, and they are told.
-- 2026-10-06. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the
-- two. Runs after the documents register and PUSH (ops_notifications_push).
--
-- WHAT CHANGED (the user, 2026-10-06)
--   A letter management issues to a team member is shared with them by
--   default, a tick in the issue sheet turning it off for a sensitive one.
--   1. `documents.shared_at` / `shared_by`: when, and by whom, an HR letter
--      was shared with the colleague it names (`member_id`).
--   2. `document_share(p_id, p_on)`: HR letters at Work; an HR letter that
--      names a colleague (`not-hr`, `no-member`). Shared, the colleague is
--      told once (`ops_notifications` kind `hr.letter`, its kind and never
--      its words; a bell and a push opening Letters); stopped, it leaves
--      their list. Filed under HR with the kind alone.
--   3. `my_letters()`: the caller's own shared HR letters, behind the
--      fresh proof (`perf_mine_gate`), newest first, a letter a reissue
--      replaced left out and a voided one marked so; enough of each row to
--      draw its PDF in the browser, never another colleague's.
--   4. `ops_notifications_push` opens Letters for an `hr.letter`.
--
-- ROLLBACK
--   Run ops_notifications_push from A CLIENT PAUSED OR PAST SAYS WHY again;
--   the columns and the two functions may stay unused.
-- ===========================================================================

alter table public.documents add column if not exists shared_at timestamptz;
alter table public.documents add column if not exists shared_by text;

create or replace function public.document_share(p_id uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d public.documents;
  v_kind text;
begin
  if me.id is null or not public.register_may('hr', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.documents where id = p_id for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.family <> 'hr' then return jsonb_build_object('error', 'not-hr'); end if;
  if d.member_id is null then return jsonb_build_object('error', 'no-member'); end if;
  if coalesce(p_on, false) = (d.shared_at is not null) then
    return jsonb_build_object('ok', true, 'shared', d.shared_at is not null);
  end if;
  v_kind := coalesce(nullif(btrim(d.kind), ''), 'HR letter');
  if coalesce(p_on, false) then
    update public.documents set shared_at = now(), shared_by = me.name where id = p_id;
    insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
    values (d.member_id, 'hr.letter', 'A letter was issued to you', v_kind, 'hr.letter:' || d.id::text)
    on conflict (dedupe_key) do nothing;
  else
    update public.documents set shared_at = null, shared_by = null where id = p_id;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'register.edited', 'HR',
          case when coalesce(p_on, false) then 'Shared with the colleague: ' else 'No longer shared: ' end || v_kind);
  return jsonb_build_object('ok', true, 'shared', coalesce(p_on, false));
end $$;
revoke all on function public.document_share(uuid, boolean) from public, anon;
grant execute on function public.document_share(uuid, boolean) to authenticated;

create or replace function public.my_letters()
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  me public.team_members;
  g jsonb;
begin
  g := public.perf_mine_gate();
  if g is not null then return g; end if;
  me := public.ops_me();
  return jsonb_build_object('letters', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', d.id, 'serial', d.serial, 'kind', d.kind, 'family', d.family, 'title', d.title,
             'salutation', d.salutation, 'closing', d.closing, 'recipient', d.recipient, 'body', d.body,
             'languages', d.languages, 'signatory', d.signatory, 'signed', d.signed, 'issued_at', d.issued_at,
             'source', d.source, 'file_url', d.file_url, 'shared_at', d.shared_at,
             'void', d.voided_at is not null)
           order by coalesce(d.issued_at, d.created_at::date) desc, d.created_at desc)
      from public.documents d
     where d.member_id = me.id and d.family = 'hr' and d.shared_at is not null
       and not exists (select 1 from public.documents n where n.replaces = d.id and n.voided_at is null)), '[]'::jsonb));
end $$;
revoke all on function public.my_letters() from public, anon;
grant execute on function public.my_letters() to authenticated;

create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.kind = 'client_left' then '/admin/?s=work'
         when new.kind = 'hr.letter' then '/admin/?s=mine&view=letters'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         when new.kind = 'hr.letter' then 'hr-letter'
         else null end);
  return new;
exception when others then
  return new;
end $$;

-- END OF HR LETTERS SHARED ----------------------------------------------------
