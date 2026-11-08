-- ===========================================================================
-- CLIENT PORTAL ONE SIGN-IN — the client portal holds Content Review, Video
-- Scripts and Creator campaigns as tabs under its one sign-in, and a
-- decision made while signed in is filed under the contact's own name.
-- 2026-11-08. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (the user, 2026-11-08: "ok" to the client portal mockup,
-- release 1)
--   1. portal_contact_name(p_client): the signed-in contact of a client
--      holding live portal access, else null. A helper alone: other
--      functions call it.
--   2. portal_work(p_client): what the portal's new tabs list, for a client
--      the signed-in contact holds portal access at: the published Content
--      Review sets (posts, approved, changes, waiting), the shared video
--      scripts (code, title, kind, month, shoot), with the links that open
--      them. `no-access` for anyone else.
--   3. portal_link_pass(p_kind, p_token): a review or selection link opened
--      by a signed-in contact of its client answers the contact's name and
--      the link's access code, so the page opens with no code typed and
--      decides under that name. Nothing for anyone else.
--   4. Trigger portal_decider_stamp on `reviews` and `option_reviews`: a
--      decision a signed-in contact of the client makes is filed under the
--      contact's own name, whatever name the page sent. A colleague's, or
--      one made with no sign-in, is left as it came.
--   The links already sent keep working for anyone with no portal sign-in.
-- ===========================================================================

create or replace function public.portal_contact_name(p_client uuid)
returns text
language sql stable security definer set search_path = public as $$
  select k.name
    from public.client_contacts k
   where p_client is not null
     and k.client_id = p_client
     and k.portal_access and k.archived_at is null
     and lower(k.email) = lower(auth.jwt() ->> 'email')
     and p_client in (select public.portal_clients())
   order by k.is_primary desc
   limit 1
$$;
revoke all on function public.portal_contact_name(uuid) from public, anon, authenticated;

create or replace function public.portal_work(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cl public.clients%rowtype;
begin
  if public.portal_contact_name(p_client) is null then
    return jsonb_build_object('error', 'no-access');
  end if;
  select * into cl from public.clients where id = p_client;
  return jsonb_build_object(
    'review', case when cl.review_hidden is not true and cl.access_token is not null then jsonb_build_object(
      'token', cl.access_token,
      'sets', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'title', b.title, 'period', b.period,
                 'published_at', b.published_at, 'created_at', b.created_at,
                 'posts', n.posts, 'approved', n.approved, 'changes', n.changes,
                 'waiting', n.waiting)
               order by coalesce(b.period, '') desc, coalesce(b.published_at, b.created_at) desc)
          from public.batches b
          cross join lateral (
            select count(*)::int as posts,
                   (count(*) filter (where d.decision = 'approved'))::int as approved,
                   (count(*) filter (where d.decision = 'changes'))::int as changes,
                   (count(*) filter (where d.decision is null))::int as waiting
              from public.posts po
              left join lateral (
                select r.decision
                  from public.reviews r
                 where r.post_id = po.id and r.undone_at is null
                   and coalesce(r.round, 1) = coalesce(po.round, 1)
                   and (po.review_reset_at is null or r.created_at > po.review_reset_at)
                 order by r.created_at desc
                 limit 1) d on true
             where po.batch_id = b.id) n
         where b.client_id = p_client and b.published), '[]'::jsonb)) end,
    'scripts', case when cl.script_key is not null then jsonb_build_object(
      'key', cl.script_key,
      'list', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'code', s.code, 'title', s.title, 'kind', s.kind,
                 'period', s.period, 'shoot_on', s.shoot_on, 'shoot_time', s.shoot_time)
               order by s.period desc, s.seq)
          from public.video_scripts s
         where s.client_id = p_client and s.status = 'shared'), '[]'::jsonb)) end);
end $$;
revoke all on function public.portal_work(uuid) from public, anon;
grant execute on function public.portal_work(uuid) to authenticated;

create or replace function public.portal_link_pass(p_kind text, p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_client uuid;
  v_code   text;
  v_name   text;
begin
  if p_token is null or p_token = '' then return jsonb_build_object('none', true); end if;
  if p_kind = 'review' then
    select c.id, c.passcode into v_client, v_code
      from public.clients c
     where c.access_token = p_token and c.active and not c.review_hidden;
  elsif p_kind = 'campaign' then
    select m.client_id, m.passcode into v_client, v_code
      from public.campaigns m
     where m.access_token = p_token;
  else
    return jsonb_build_object('error', 'bad-kind');
  end if;
  v_name := public.portal_contact_name(v_client);
  if v_name is null then return jsonb_build_object('none', true); end if;
  return jsonb_build_object('name', v_name, 'passcode', nullif(v_code, ''));
end $$;
revoke all on function public.portal_link_pass(text, text) from public, anon;
grant execute on function public.portal_link_pass(text, text) to authenticated;

create or replace function public.portal_decider_stamp()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_client uuid;
  v_name   text;
begin
  if auth.uid() is null or public.is_team() then return new; end if;
  if tg_table_name = 'reviews' then
    select b.client_id into v_client
      from public.posts p join public.batches b on b.id = p.batch_id
     where p.id = new.post_id;
  else
    select m.client_id into v_client
      from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
     where o.id = new.option_id;
  end if;
  v_name := public.portal_contact_name(v_client);
  if v_name is not null then new.reviewer := v_name; end if;
  return new;
end $$;
revoke all on function public.portal_decider_stamp() from public, anon, authenticated;

drop trigger if exists reviews_portal_decider on public.reviews;
create trigger reviews_portal_decider before insert on public.reviews
  for each row execute function public.portal_decider_stamp();
drop trigger if exists option_reviews_portal_decider on public.option_reviews;
create trigger option_reviews_portal_decider before insert on public.option_reviews
  for each row execute function public.portal_decider_stamp();

-- Rollback:
--   drop trigger if exists reviews_portal_decider on public.reviews;
--   drop trigger if exists option_reviews_portal_decider on public.option_reviews;
--   drop function if exists public.portal_decider_stamp();
--   drop function if exists public.portal_link_pass(text, text);
--   drop function if exists public.portal_work(uuid);
--   drop function if exists public.portal_contact_name(uuid);

-- END OF CLIENT PORTAL ONE SIGN-IN -------------------------------------------

select public.functions_tidy();
