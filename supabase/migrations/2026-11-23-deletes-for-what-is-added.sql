-- ===========================================================================
-- WHAT IS ADDED IS DELETED (2026-11-23, the user: "some of
-- the templates couldnt be deleted.. didnt i say that things have to be able
-- to create, manage or modify and delete options..?"). 2026-11-23. Safe to
-- run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED
--   * A task template (My Work) and a document type (Documents) are deleted
--     by the colleague who may add them (`ops.workflows` at Edit,
--     `register.types`), each from its own ⋯, while nothing names it: the
--     types the portal reads by name (`quote_cover`, `supplier_letter`,
--     `supplier_sca`) are never deleted (`built-in`); a
--     template a task or a repeat rule was made from, and a type a document
--     was issued under, is refused `in-use` with the counts, and is set
--     inactive instead (the history keeps what it was made from).
--   * Each delete is filed under Settings (team.changed), the name kept.
--   * A candidate's interview sheet (the user, a screenshot of two sheets
--     reading Not scored: "interview sheet couldnt be deleted..."): a
--     colleague's sheet and scores are one card, and only scores could be
--     removed. `hiring_sheet_remove(p_id, p_member)` takes both: one's own
--     (Remove, the page's Undo writes them back), another colleague's by
--     the candidate's Owner or an admin (Delete, asked first); never once
--     the candidate is hired or closed. Filed on the candidate.
--
-- ORDER: this file (Management API), then the pages. An open tab before the
-- pages draws no Delete; after them, before this file, Delete reads This
-- feature is not available yet.
--
-- ROLLBACK
--   drop function if exists public.ops_template_delete(uuid);
--   drop function if exists public.doc_type_delete(text);
--   drop function if exists public.hiring_sheet_remove(uuid, uuid);
-- ===========================================================================

create or replace function public.ops_template_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  m public.team_members := public.ops_me();
  t public.ops_task_templates;
  v_tasks integer; v_rules integer;
begin
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_granted('ops.workflows', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.ops_task_templates x where x.id = p_id for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select count(*) into v_tasks from public.ops_tasks x where x.template_id = p_id;
  select count(*) into v_rules from public.ops_recurring_rules x where x.template_id = p_id;
  if v_tasks + v_rules > 0 then
    return jsonb_build_object('error', 'in-use', 'tasks', v_tasks, 'rules', v_rules);
  end if;
  delete from public.ops_task_templates x where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (m.name, 'team.changed', 'Task templates', t.name || ' · Deleted');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ops_template_delete(uuid) from public, anon;
grant execute on function public.ops_template_delete(uuid) to authenticated;

create or replace function public.doc_type_delete(p_id text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_t public.doc_types%rowtype;
  v_docs integer;
begin
  if not public.ops_granted('register.types', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_t from public.doc_types d where d.id = p_id for update;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  /* The types the portal itself reads by name stay: the quotation's cover
     letter, the supplier's letter and its Service Agreement. */
  if v_t.id in ('quote_cover', 'supplier_letter', 'supplier_sca') then return jsonb_build_object('error', 'built-in'); end if;
  select count(*) into v_docs from public.documents x where x.type_id = p_id;
  if v_docs > 0 then return jsonb_build_object('error', 'in-use', 'documents', v_docs); end if;
  delete from public.doc_types d where d.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, lower(auth.jwt() ->> 'email')), 'team.changed', 'Document types', v_t.name || ' · Deleted');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.doc_type_delete(text) from public, anon;
grant execute on function public.doc_type_delete(text) to authenticated;

create or replace function public.hiring_sheet_remove(p_id uuid, p_member uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  v_who uuid;
  c public.hiring_candidates;
  s public.hiring_sheets;
  x public.hiring_scores;
  v_name text;
begin
  if me.id is null or v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  v_who := coalesce(p_member, me.id);
  if v_who <> me.id and v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage in ('hired', 'closed') then return jsonb_build_object('error', 'closed'); end if;
  delete from public.hiring_sheets where candidate_id = p_id and team_member_id = v_who returning * into s;
  delete from public.hiring_scores where candidate_id = p_id and team_member_id = v_who returning * into x;
  if s.candidate_id is null and x.candidate_id is null then return jsonb_build_object('error', 'not-found'); end if;
  select t.name into v_name from public.team_members t where t.id = v_who;
  perform public.hiring_log(p_id, 'candidate.scored',
    case when v_who = me.id then 'Interview sheet removed' else 'Interview sheet of ' || coalesce(v_name, 'a colleague') || ' deleted' end);
  return jsonb_build_object('ok', true, 'sheet', s.candidate_id is not null, 'rating', s.rating, 'answers', s.answers,
    'scored', x.candidate_id is not null, 'scores', x.scores, 'recommend', x.recommend, 'note', x.note);
end $$;
revoke all on function public.hiring_sheet_remove(uuid, uuid) from public, anon;
grant execute on function public.hiring_sheet_remove(uuid, uuid) to authenticated;

-- END OF WHAT IS ADDED IS DELETED ---------------------------------------------

select public.functions_tidy();
