-- ===========================================================================
-- SUPPLIER EMAIL TEMPLATES, ONE RULE — every supplier email's wording is
-- edited at Suppliers Full Access or Business settings (2026-11-10)
-- ===========================================================================
-- WHY (the user, 2026-11-10: "ok", the Settings review's held item 2): a
-- supplier's two fixed emails (Supplier approved, Document) were edited at
-- Suppliers Full Access, its New email templates at Business settings alone,
-- so one recipient's emails answered two rules.
--
-- WHAT CHANGED
--   * `email_template_may(p_audience)` (no page's): a supplier's template at
--     Suppliers Full Access or `team.settings`; a client's at `team.settings`.
--   * `email_template_save`, `supplier_email_template_save` ask it;
--     `email_templates_list` answers a Suppliers Full Access colleague the
--     supplier templates alone; `supplier_email_templates_list` answers
--     `team.settings` too. The client templates keep their rule.
--   * `email_template_delete` asks it in the SQL Editor part
--     (2026-11-10-supplier-templates-one-rule-editor.sql).
--
-- ORDER: this file (connector), its SQL Editor part, then the pages. A page
-- served before offers a supplier's New email templates to Business settings
-- alone, as before. Safe to run twice.
--
-- ROLLBACK: NEW EMAIL's email_template_save and email_templates_list,
-- TEMPLATE FIELDS CHECKED's supplier_email_template_save, SUPPLIER EMAILS'
-- supplier_email_templates_list; email_template_may is then unused.
-- ===========================================================================

-- SUPPLIER EMAIL TEMPLATES, ONE RULE ----------------------------------------

create or replace function public.email_template_may(p_audience text)
returns boolean
language sql stable security definer set search_path = public as $$
  select (public.ops_me()).id is not null and case p_audience
    when 'supplier' then public.allowed('suppliers', 'manage') or public.ops_granted('team.settings', 'work')
    when 'client' then public.ops_granted('team.settings', 'work')
    else false end;
$$;
revoke all on function public.email_template_may(text) from public, anon, authenticated;

create or replace function public.email_template_save(p_id uuid, p_audience text, p_name text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  t     public.email_templates;
  v_n   text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_s   text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b   text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
  v_bad jsonb;
  v_id  uuid;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if length(v_n) < 2 or length(v_n) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b, 'free');
  if v_bad is not null then return v_bad; end if;
  if p_id is null then
    if p_audience is null or p_audience not in ('client', 'supplier') then return jsonb_build_object('error', 'bad-request'); end if;
    if not public.email_template_may(p_audience) then return jsonb_build_object('error', 'denied'); end if;
    if exists (select 1 from public.email_templates x where x.audience = p_audience and lower(x.name) = lower(v_n)) then
      return jsonb_build_object('error', 'taken');
    end if;
    insert into public.email_templates (audience, name, subject, body, updated_by) values (p_audience, v_n, v_s, v_b, me.id)
    returning id into v_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Email templates', 'Added: ' || v_n || ' (' || case p_audience when 'client' then 'Clients' else 'Suppliers' end || ')');
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;
  select * into t from public.email_templates x where x.id = p_id for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.email_template_may(t.audience) then return jsonb_build_object('error', 'denied'); end if;
  if exists (select 1 from public.email_templates x where x.audience = t.audience and lower(x.name) = lower(v_n) and x.id <> t.id) then
    return jsonb_build_object('error', 'taken');
  end if;
  if t.name is distinct from v_n then moved := moved || ('Name: ' || t.name || ' → ' || v_n); end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Message'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true, 'id', t.id); end if;
  update public.email_templates x set name = v_n, subject = v_s, body = v_b, updated_at = now(), updated_by = me.id where x.id = t.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Email templates', t.name || ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true, 'id', t.id);
end $$;

create or replace function public.email_templates_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not (public.allowed('whatsapp', 'work') or public.ops_granted('team.settings', 'view')
                                          or public.email_template_may('supplier')) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', t.id, 'audience', t.audience, 'name', t.name, 'subject', t.subject, 'body', t.body,
             'updated_at', t.updated_at, 'updated_by', (select m.name from public.team_members m where m.id = t.updated_by))
             order by t.audience, lower(t.name))
      from public.email_templates t
     where t.audience = 'supplier' or public.allowed('whatsapp', 'work') or public.ops_granted('team.settings', 'view')), '[]'::jsonb));
end $$;
revoke all on function public.email_templates_list() from public, anon;
grant execute on function public.email_templates_list() to authenticated;

create or replace function public.supplier_email_template_save(p_purpose text, p_subject text, p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.supplier_email_templates;
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  moved text[] := '{}';
  v_bad jsonb;
begin
  if me.id is null or not public.email_template_may('supplier') then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.supplier_email_templates x where x.purpose = p_purpose for update;
  if t.purpose is null then return jsonb_build_object('error', 'bad-purpose'); end if;
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  v_bad := public.template_check(v_s || E'\n' || v_b, 'supplier');
  if v_bad is not null then return v_bad; end if;
  if t.subject is distinct from v_s then moved := moved || ('Subject: ' || t.subject || ' → ' || v_s); end if;
  if t.body is distinct from v_b then moved := moved || 'Body'::text; end if;
  if array_length(moved, 1) is null then return jsonb_build_object('ok', true); end if;
  update public.supplier_email_templates x set subject = v_s, body = v_b, updated_at = now(), updated_by = me.id
   where x.purpose = p_purpose;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'supplier.edited', 'Supplier emails',
          case p_purpose when 'approved' then 'Supplier approved' else 'Document' end || ' · ' || array_to_string(moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.supplier_email_templates_list()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if (public.ops_me()).id is null or not (public.allowed('suppliers', 'view') or public.email_template_may('supplier')) then
    return jsonb_build_object('error', 'denied');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('purpose', t.purpose, 'subject', t.subject, 'body', t.body,
             'updated_at', t.updated_at, 'updated_by', m.name) order by t.purpose)
      from public.supplier_email_templates t left join public.team_members m on m.id = t.updated_by), '[]'::jsonb));
end $$;
revoke all on function public.supplier_email_templates_list() from public, anon;
grant execute on function public.supplier_email_templates_list() to authenticated;

-- END OF SUPPLIER EMAIL TEMPLATES, ONE RULE ---------------------------------

select public.functions_tidy();
