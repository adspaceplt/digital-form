-- ===========================================================================
-- TEAM NOTICES — a notice to every colleague, or to the colleagues chosen,
-- in the notification bell and as a push.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-09: "add the send notice, whereby i can send custom
--   in-app notifications to all members, or to specific team member(s)".
--   1. `team_notices` (RLS on, no policy, no grant): the notice, whom it went
--      to, who sent it, and when it was withdrawn.
--   2. `ops_notifications.notice_id`, `from_name` and `hidden_at`: each
--      colleague's copy names its notice and who sent it, and a notice
--      withdrawn is hidden from every bell.
--   3. Team: Notices (`team.notice`, a granted part: an admin's by itself,
--      any other group's once set):
--      `team_notice_send(p_title, p_body, p_to)` sends to all active
--      colleagues (`p_to` null) or to those named, never a system account and
--      never the sender (`bad-title`, `bad-body`, `no-one`);
--      `team_notices_list()` answers the latest 50, each with whom it went to
--      and how many have read it;
--      `team_notice_withdraw(p_id, p_restore)` hides it from every bell (a
--      push already delivered stays on the device), and with `p_restore`
--      puts it back.
--      Each is filed `team.changed` under subject Notices.
--
-- ROLLBACK
--   Nothing reads the table but these functions; leaving them unused sends
--   nothing. The three columns may stay: the bell reads `hidden_at` only to
--   leave a withdrawn notice out, and `from_name` only to say who sent it.
-- ===========================================================================

create table if not exists public.team_notices (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  body          text,
  to_all        boolean not null default false,
  recipients    uuid[] not null default '{}',
  sent_by       uuid,
  sent_by_name  text,
  created_at    timestamptz not null default now(),
  withdrawn_at  timestamptz,
  withdrawn_by  text
);
alter table public.team_notices enable row level security;
revoke all on public.team_notices from public, anon, authenticated;

alter table public.ops_notifications add column if not exists notice_id uuid;
alter table public.ops_notifications add column if not exists from_name text;
alter table public.ops_notifications add column if not exists hidden_at timestamptz;
create index if not exists ops_notif_notice_idx on public.ops_notifications(notice_id) where notice_id is not null;

create or replace function public.team_notice_send(p_title text, p_body text, p_to uuid[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_title text := btrim(coalesce(p_title, ''));
  v_body  text := nullif(btrim(coalesce(p_body, '')), '');
  v_to    uuid[];
  v_id    uuid;
  n       int;
begin
  if me.id is null or not public.ops_granted('team.notice', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_title = '' or length(v_title) > 120 then return jsonb_build_object('error', 'bad-title'); end if;
  if v_body is not null and length(v_body) > 1000 then return jsonb_build_object('error', 'bad-body'); end if;
  select coalesce(array_agg(m.id order by m.name), '{}') into v_to
    from public.team_members m
   where m.active and not coalesce(m.system, false) and m.id <> me.id
     and (p_to is null or m.id = any(p_to));
  n := coalesce(array_length(v_to, 1), 0);
  if n = 0 then return jsonb_build_object('error', 'no-one'); end if;
  insert into public.team_notices (title, body, to_all, recipients, sent_by, sent_by_name)
  values (v_title, v_body, p_to is null, v_to, me.id, me.name)
  returning id into v_id;
  insert into public.ops_notifications (team_member_id, kind, title, body, notice_id, from_name)
  select x, 'notice', v_title, v_body, v_id, me.name from unnest(v_to) as x;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Notices',
    'Sent to ' || case when p_to is null then 'all colleagues (' || n || ')'
                       when n = 1 then '1 colleague' else n || ' colleagues' end || ': ' || v_title);
  return jsonb_build_object('ok', true, 'id', v_id, 'count', n);
end $$;
revoke all on function public.team_notice_send(text, text, uuid[]) from public, anon;
grant execute on function public.team_notice_send(text, text, uuid[]) to authenticated;

create or replace function public.team_notices_list()
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null or not public.ops_granted('team.notice', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('items', coalesce((
    select jsonb_agg(row_to_json(x) order by x.created_at desc)
      from (select tn.id, tn.title, tn.body, tn.to_all, tn.sent_by_name, tn.created_at, tn.withdrawn_at,
                   coalesce(array_length(tn.recipients, 1), 0) as sent,
                   (select count(*) from public.ops_notifications o
                     where o.notice_id = tn.id and o.read_at is not null) as read,
                   (select coalesce(jsonb_agg(m.name order by m.name), '[]'::jsonb) from public.team_members m
                     where m.id = any(tn.recipients)) as names
              from public.team_notices tn
             order by tn.created_at desc
             limit 50) x), '[]'::jsonb));
end $$;
revoke all on function public.team_notices_list() from public, anon;
grant execute on function public.team_notices_list() to authenticated;

create or replace function public.team_notice_withdraw(p_id uuid, p_restore boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v public.team_notices;
begin
  if me.id is null or not public.ops_granted('team.notice', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.team_notices tn where tn.id = p_id for update;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_restore, false) then
    if v.withdrawn_at is null then return jsonb_build_object('ok', true); end if;
    update public.team_notices tn set withdrawn_at = null, withdrawn_by = null where tn.id = p_id;
    update public.ops_notifications o set hidden_at = null where o.notice_id = p_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Notices', 'Restored: ' || v.title);
    return jsonb_build_object('ok', true);
  end if;
  if v.withdrawn_at is not null then return jsonb_build_object('ok', true); end if;
  update public.team_notices tn set withdrawn_at = now(), withdrawn_by = me.name where tn.id = p_id;
  update public.ops_notifications o set hidden_at = now() where o.notice_id = p_id and o.hidden_at is null;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Notices', 'Withdrawn: ' || v.title);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.team_notice_withdraw(uuid, boolean) from public, anon;
grant execute on function public.team_notice_withdraw(uuid, boolean) to authenticated;

-- END OF TEAM NOTICES -------------------------------------------------------

select public.functions_tidy();
