-- ===========================================================================
-- MEETING MESSAGE — the content meeting's message to the client, as the
-- team words it (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "approve all, build item 5 too"): the message
-- a month's card copies for the client (date, time, agenda, channel, link)
-- was typed into js/ops.js; changing a word needed a release.
--
-- WHAT IT ADDS
--   * `meeting_message_template`: one row, the message with its words in
--     braces ({meeting}, {date}, {time}, {month}, {channel}, {link}); seeded
--     once with the wording the page used, edited at Settings, Templates,
--     Meeting message (`team.settings`).
--   * `meeting_message_get()`: any colleague (the month's card fills it).
--   * `meeting_message_save(p_body)`: `team.settings` at Work; 2 to 3,000
--     characters holding {date} (`no-date`); filed `team.changed` under
--     Meeting message; an unchanged save files nothing.
--
-- ORDER: this file (connector), then the pages. A page served before keeps
-- its own words; a page served after on a database without this file falls
-- back to the same words. Safe to run twice.
--
-- ROLLBACK
--   drop function if exists public.meeting_message_save(text);
--   drop function if exists public.meeting_message_get();
--   drop table if exists public.meeting_message_template;
-- ===========================================================================

create table if not exists public.meeting_message_template (
  id          int primary key default 1 check (id = 1),
  body        text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.team_members(id) on delete set null
);
alter table public.meeting_message_template enable row level security;
revoke all on table public.meeting_message_template from public, anon, authenticated;

insert into public.meeting_message_template (id, body)
select 1, E'Meeting Schedule {meeting}\n\nDate 日期: {date}\nTime 时间: {time}\n\nMeeting Agenda 摘要:\n•  {month} Content Discussion\n\nChannel 渠道:\n{channel}\nLink: {link}'
where not exists (select 1 from public.meeting_message_template);

create or replace function public.meeting_message_get()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t public.meeting_message_template;
begin
  if (public.ops_me()).id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into t from public.meeting_message_template x where x.id = 1;
  return jsonb_build_object('ok', true, 'body', t.body, 'updated_at', t.updated_at,
    'updated_by', (select m.name from public.team_members m where m.id = t.updated_by));
end $$;
revoke all on function public.meeting_message_get() from public, anon;
grant execute on function public.meeting_message_get() to authenticated;

create or replace function public.meeting_message_save(p_body text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  t   public.meeting_message_template;
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_b) < 2 or length(v_b) > 3000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*date\s*\}' then return jsonb_build_object('error', 'no-date'); end if;
  select * into t from public.meeting_message_template x where x.id = 1 for update;
  if t.body is not distinct from v_b then return jsonb_build_object('ok', true); end if;
  update public.meeting_message_template x set body = v_b, updated_at = now(), updated_by = me.id where x.id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Meeting message', 'Message');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.meeting_message_save(text) from public, anon;
grant execute on function public.meeting_message_save(text) to authenticated;

-- END OF MEETING MESSAGE ------------------------------------------------------

select public.functions_tidy();
