-- DELETE REQUESTS (2026-11-17) -----------------------------------------------
/* The access restructure, release 2 (plan version 4, the user's decision 1,
   2026-11-17: "Full control deletes; Edit files a request an admin
   approves; View and Off cannot delete").

   A colleague at Edit on a section who presses a Delete files a request
   in its place: the screen's own call (a function and its arguments, or a
   table and its key) is kept with a reason, the record is left as it is,
   and every active admin is told. An admin approves it from Settings,
   Portal, Delete requests, and the page then makes that same call as the
   admin, so every check the delete holds still applies; or declines it
   with a note. The requester is told either way.

   `delete_kinds` is the one list of what may be requested: each delete
   function and each table a page deletes from, the section asked at Edit,
   the argument naming the record and where its name is read. Anything not
   on it cannot be requested. Both tables have RLS on, no policy, no grant.

   Safe to run twice. Rollback: drop the six functions and the two tables
   (the page then draws Delete at Full control alone, as before). */

create table if not exists public.delete_kinds (
  kind        text primary key check (kind ~ '^(rpc|table):[a-z_]+$'),
  section     text not null,
  id_arg      text not null,
  word        text not null,
  label_table text,
  label_key   text,
  label_col   text
);
alter table public.delete_kinds enable row level security;
revoke all on public.delete_kinds from public, anon, authenticated;

insert into public.delete_kinds (kind, section, id_arg, word, label_table, label_key, label_col) values
  ('rpc:delete_client',            'clients',            'p_client',      'Client',            'clients',            'id',   'name'),
  ('rpc:brand_analysis_delete',    'clients.brand',      'p_id',          'Brand analysis',    'brand_analyses',     'id',   'version'),
  ('rpc:client_entity_delete',     'clients.billing',    'p_entity',      'Billing entity',    'billing_entities',   'id',   'legal_name'),
  ('rpc:client_request_delete',    'clients.requests',   'p_id',          'Request',           'client_requests',    'id',   'kind'),
  ('rpc:letter_delete',            'clients.documents',  'p_doc',         'Letter of Offer',   'client_documents',   'id',   'number'),
  ('rpc:quotation_delete',         'clients.quotes',     'p_id',          'Quotation',         'quotations',         'id',   'ref'),
  ('rpc:document_delete',          'register',           'p_doc',         'Document',          'documents',          'id',   'serial'),
  ('rpc:ops_delete_engagement',    'ops',                'p_engagement',  'Month',             'ops_engagements',    'id',   'period'),
  ('rpc:ops_delete_task',          'ops',                'p_task',        'Task',              'ops_tasks',          'id',   'title'),
  ('rpc:ops_delete_tasks',         'ops',                'p_tasks',       'Tasks',             null,                 null,   null),
  ('rpc:sm_report_delete',         'reports',            'p_id',          'Report',            'sm_reports',         'id',   'title'),
  ('rpc:sm_report_version_delete', 'reports',            'p_version',     'Report version',    null,                 null,   null),
  ('rpc:supplier_delete',          'suppliers',          'p_id',          'Supplier',          'suppliers',          'id',   'name'),
  ('rpc:video_script_delete',      'scripts',            'p_id',          'Video script',      'video_scripts',      'id',   'code'),
  ('table:batches',                'review.sets',        'id',            'Content set',       'batches',            'id',   'title'),
  ('table:posts',                  'review.sets',        'id',            'Post',              'posts',              'id',   'title'),
  ('table:campaigns',              'campaigns.campaigns','id',            'Campaign',          'campaigns',          'id',   'title'),
  ('table:campaign_options',       'campaigns.campaigns','id',            'Booking',           null,                 null,   null),
  ('table:creators',               'campaigns.creators', 'id',            'Creator',           'creators',           'id',   'name'),
  ('table:client_contacts',        'clients.contacts',   'id',            'Contact',           'client_contacts',    'id',   'name'),
  ('table:client_requests',        'clients.requests',   'id',            'Request',           'client_requests',    'id',   'kind'),
  ('table:client_services',        'clients.services',   'id',            'Service line',      'client_services',    'id',   'label'),
  ('table:client_touches',         'clients.calls',      'id',            'Call or visit',     'client_touches',     'id',   'summary'),
  ('table:links',                  'links',              'slug',          'Short link',        'links',              'slug', 'slug')
on conflict (kind) do update set section = excluded.section, id_arg = excluded.id_arg, word = excluded.word,
  label_table = excluded.label_table, label_key = excluded.label_key, label_col = excluded.label_col;

create table if not exists public.delete_requests (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null references public.delete_kinds (kind),
  args         jsonb not null default '{}'::jsonb,
  record       text,
  label        text not null default '',
  client_id    uuid,
  reason       text not null,
  requested_by uuid not null references public.team_members (id),
  created_at   timestamptz not null default now(),
  state        text not null default 'open'
               check (state in ('open', 'approving', 'approved', 'declined', 'withdrawn')),
  decided_by   uuid references public.team_members (id),
  decided_at   timestamptz,
  note         text
);
alter table public.delete_requests enable row level security;
revoke all on public.delete_requests from public, anon, authenticated;
create unique index if not exists delete_requests_open_idx on public.delete_requests (kind, record)
  where state in ('open', 'approving') and record is not null;

/* The kinds, for the page: which call a Delete makes and the section asked. */
create or replace function public.delete_request_kinds()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null then '[]'::jsonb else coalesce(
    (select jsonb_agg(jsonb_build_object('kind', k.kind, 'section', k.section, 'word', k.word) order by k.kind)
       from public.delete_kinds k), '[]'::jsonb) end
$$;
revoke all on function public.delete_request_kinds() from public, anon;
grant execute on function public.delete_request_kinds() to authenticated;

/* A request filed by a colleague at Edit (never at Full control, who
   deletes): the call kept whole, the record's name read here, never sent. */
create or replace function public.delete_request_file(p_kind text, p_args jsonb, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me       public.team_members := public.ops_me();
  k        public.delete_kinds;
  v_rec    text;
  v_label  text;
  v_client uuid;
  v_why    text := btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));
  v_id     uuid;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into k from public.delete_kinds x where x.kind = p_kind;
  if k.kind is null then return jsonb_build_object('error', 'bad-kind'); end if;
  if not public.allowed(k.section, 'work') then return jsonb_build_object('error', 'denied'); end if;
  if public.allowed(k.section, 'manage') then return jsonb_build_object('error', 'may-delete'); end if;
  if p_args is null or jsonb_typeof(p_args) <> 'object' or length(p_args::text) > 4000 then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if length(v_why) < 3 or length(v_why) > 500 then return jsonb_build_object('error', 'bad-reason'); end if;
  if jsonb_typeof(p_args -> k.id_arg) = 'array' then
    v_rec := null;
    v_label := jsonb_array_length(p_args -> k.id_arg)::text || ' ' || lower(k.word);
    if jsonb_array_length(p_args -> k.id_arg) not between 1 and 200 then return jsonb_build_object('error', 'bad-request'); end if;
  else
    v_rec := nullif(btrim(coalesce(p_args ->> k.id_arg, '')), '');
    if v_rec is null or length(v_rec) > 100 then return jsonb_build_object('error', 'bad-request'); end if;
    if k.label_table is not null then
      execute format('select %I::text from public.%I where %I::text = $1', k.label_col, k.label_table, k.label_key)
        into v_label using v_rec;
      if not found then return jsonb_build_object('error', 'not-found'); end if;
      begin
        execute format('select client_id from public.%I where %I::text = $1', k.label_table, k.label_key)
          into v_client using v_rec;
      exception when undefined_column then v_client := null;
      end;
      if k.label_table = 'clients' then v_client := v_rec::uuid; end if;
      /* A supplier's client is the one it is linked to, not its owner. */
      if k.label_table = 'suppliers' then v_client := null; end if;
      if v_client is not null and not public.client_seen(v_client, 'view') then
        return jsonb_build_object('error', 'not-found');
      end if;
    end if;
    v_label := coalesce(nullif(btrim(coalesce(v_label, '')), ''), k.word);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('delete-request:' || me.id::text, 0));
  if (select count(*) from public.delete_requests x where x.requested_by = me.id
        and x.created_at > now() - interval '24 hours') >= 30 then
    return jsonb_build_object('error', 'too-many');
  end if;
  if v_rec is not null and exists (select 1 from public.delete_requests x
       where x.kind = k.kind and x.record = v_rec and x.state in ('open', 'approving')) then
    return jsonb_build_object('error', 'already');
  end if;
  insert into public.delete_requests (kind, args, record, label, client_id, reason, requested_by)
  values (k.kind, p_args, v_rec, left(v_label, 200), v_client, v_why, me.id)
  returning id into v_id;
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'delete.request', 'Delete requested · ' || k.word || ' · ' || left(v_label, 120),
         me.name || ' · ' || v_why,
         v_client, 'delreq:' || v_id || ':' || m.id
    from public.team_members m
   where m.active and (m.is_admin or m.role = 'admin') and m.id <> me.id
  on conflict (dedupe_key) do nothing;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Requested: ' || k.word || ' · ' || left(v_label, 120) || ' · ' || v_why);
  return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'word', k.word);
end $$;
revoke all on function public.delete_request_file(text, jsonb, text) from public, anon;
grant execute on function public.delete_request_file(text, jsonb, text) to authenticated;

/* The requests: an admin reads all (waiting first, then the last 30 days);
   anyone else their own. */
create or replace function public.delete_requests_list()
returns jsonb language sql stable security definer set search_path = public as $$
  with me as (select m.* from public.ops_me() m)
  select case when (select id from me) is null then jsonb_build_object('error', 'denied') else jsonb_build_object('ok', true,
    'admin', (select is_admin or role = 'admin' from me),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'kind', r.kind, 'word', k.word, 'section', k.section, 'label', r.label, 'reason', r.reason,
        'state', r.state, 'at', r.created_at, 'by', a.name, 'by_id', r.requested_by, 'mine', r.requested_by = (select id from me),
        'decided_by', d.name, 'decided_at', r.decided_at, 'note', r.note, 'client_id', r.client_id)
        order by (r.state in ('open', 'approving')) desc, r.created_at desc)
      from public.delete_requests r
      join public.delete_kinds k on k.kind = r.kind
      left join public.team_members a on a.id = r.requested_by
      left join public.team_members d on d.id = r.decided_by
     where (r.state in ('open', 'approving') or r.created_at > now() - interval '30 days')
       and ((select is_admin or role = 'admin' from me) or r.requested_by = (select id from me))), '[]'::jsonb)) end
$$;
revoke all on function public.delete_requests_list() from public, anon;
grant execute on function public.delete_requests_list() to authenticated;

create or replace function public.delete_request_withdraw(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); r public.delete_requests;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.delete_requests x where x.id = p_id for update;
  if r.id is null or r.requested_by <> me.id then return jsonb_build_object('error', 'not-found'); end if;
  if r.state <> 'open' then return jsonb_build_object('error', 'decided', 'state', r.state); end if;
  update public.delete_requests set state = 'withdrawn', decided_at = now() where id = r.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Withdrawn: ' || r.label);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.delete_request_withdraw(uuid) from public, anon;
grant execute on function public.delete_request_withdraw(uuid) to authenticated;

/* An admin decides. Approve hands the call back to the page, which makes
   it as the admin (the screen's own delete, every check it holds), then
   closes the request with delete_request_done; Decline closes it here. */
create or replace function public.delete_request_decide(p_id uuid, p_approve boolean, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r  public.delete_requests;
  v_note text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
begin
  if me.id is null or not (me.is_admin or me.role = 'admin') then return jsonb_build_object('error', 'denied'); end if;
  if length(coalesce(v_note, '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  select * into r from public.delete_requests x where x.id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.state not in ('open', 'approving') then return jsonb_build_object('error', 'decided', 'state', r.state); end if;
  if coalesce(p_approve, false) then
    update public.delete_requests set state = 'approving', decided_by = me.id, decided_at = now(), note = v_note where id = r.id;
    return jsonb_build_object('ok', true, 'kind', r.kind, 'args', r.args);
  end if;
  if v_note is null then return jsonb_build_object('error', 'no-note'); end if;
  update public.delete_requests set state = 'declined', decided_by = me.id, decided_at = now(), note = v_note where id = r.id;
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  values (r.requested_by, 'delete.declined', 'Delete declined · ' || r.label, me.name || ' · ' || v_note,
          r.client_id, 'delreq:' || r.id || ':declined')
  on conflict (dedupe_key) do nothing;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Declined: ' || r.label || ' · ' || v_note);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.delete_request_decide(uuid, boolean, text) from public, anon;
grant execute on function public.delete_request_decide(uuid, boolean, text) to authenticated;

/* The delete made (or refused, with the refusal's words): approved, the
   requester told; refused, the request waits again with the refusal. */
create or replace function public.delete_request_done(p_id uuid, p_ok boolean, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); r public.delete_requests;
begin
  if me.id is null or not (me.is_admin or me.role = 'admin') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.delete_requests x where x.id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.state <> 'approving' then return jsonb_build_object('error', 'decided', 'state', r.state); end if;
  if not coalesce(p_ok, false) then
    update public.delete_requests set state = 'open', note = left(nullif(btrim(coalesce(p_error, '')), ''), 500) where id = r.id;
    return jsonb_build_object('ok', true, 'state', 'open');
  end if;
  update public.delete_requests set state = 'approved', decided_by = me.id, decided_at = now() where id = r.id;
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  values (r.requested_by, 'delete.approved', 'Deleted · ' || r.label, me.name,
          r.client_id, 'delreq:' || r.id || ':approved')
  on conflict (dedupe_key) do nothing;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Delete requests', 'Approved: ' || r.label || ' · requested by ' ||
          coalesce((select m.name from public.team_members m where m.id = r.requested_by), 'a colleague'));
  return jsonb_build_object('ok', true, 'state', 'approved');
end $$;
revoke all on function public.delete_request_done(uuid, boolean, text) from public, anon;
grant execute on function public.delete_request_done(uuid, boolean, text) to authenticated;

-- END OF DELETE REQUESTS -----------------------------------------------------

select public.functions_tidy();
