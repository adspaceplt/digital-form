-- ===========================================================================
-- SUPPLIER EMAIL TEMPLATES, ONE RULE, THE SQL EDITOR PART — a New email
-- template is deleted under the rule its recipient's templates are edited
-- by (2026-11-10)
-- ===========================================================================
-- Run in the SQL Editor after SUPPLIER EMAIL TEMPLATES, ONE RULE: the
-- connector holds a statement holding the word delete. Safe to run twice.
--
-- ROLLBACK: NEW EMAIL's email_template_delete.
-- ===========================================================================

create or replace function public.email_template_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  t  public.email_templates;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.email_templates x where x.id = p_id for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.email_template_may(t.audience) then return jsonb_build_object('error', 'denied'); end if;
  delete from public.email_templates x where x.id = t.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates', 'Deleted: ' || t.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.email_template_delete(uuid) from public, anon;
grant execute on function public.email_template_delete(uuid) to authenticated;

-- END OF SUPPLIER EMAIL TEMPLATES, ONE RULE, THE SQL EDITOR PART -------------

select public.functions_tidy();
