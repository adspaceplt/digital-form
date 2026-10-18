-- ===========================================================================
-- SLOTS HOLD THEIR BOOKINGS — a campaign never books more creators than its
-- slots, and its slots never drop below the creators booked. 2026-10-18.
-- Safe to run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (second audit, item 10)
--   confirm_selection_with compared the client's picks with the whole of
--   the slots, and campaign_confirm_creators checked no slots at all: ten
--   slots with six booked took ten more picks and booked sixteen. Both now
--   refuse `over-slots` (with the slots and the creators booked) where the
--   creators booked (campaign_booked) and those confirmed now would pass
--   the slots. Each is restated whole from CONFIRM ONCE with that one
--   check added; every other refusal stands.
--   Lowering a campaign's slots below its bookings was refused on the page
--   alone; trigger campaigns_slots_floor now refuses it (`slots-booked`,
--   a check violation naming the count), whoever writes it.
--
-- ROLLBACK
--   Run the CONFIRM ONCE section of supabase/migrations/2026-10-10-confirm-once.sql
--   again (confirm_selection_with and campaign_confirm_creators as before),
--   then: drop trigger if exists campaigns_slots_floor on public.campaigns;
--         drop function if exists public.campaigns_slots_floor();
-- ===========================================================================

create or replace function public.confirm_selection_with(
  p_token text, p_person text, p_passcode text, p_selected uuid[], p_backup uuid[],
  p_seen jsonb, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c      campaigns%rowtype;
  v_sel  uuid[];
  v_bak  uuid[];
  v_all  uuid[];
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
  v_now  jsonb;
  v_snap jsonb;
  n      integer;
  v_booked integer;
begin
  select * into c from campaigns where access_token = p_token for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  -- The same press again: the first answer stands and nothing is filed twice.
  if v_idem is not null and exists (select 1 from campaign_confirmations k
                                     where k.campaign_id = c.id and k.idem = v_idem) then
    return jsonb_build_object('ok', true, 'again', true);
  end if;

  v_sel := array(select distinct x from unnest(coalesce(p_selected, '{}'::uuid[])) x where x is not null);
  v_bak := case when coalesce(c.backups_open, false)
                then array(select distinct x from unnest(coalesce(p_backup, '{}'::uuid[])) x
                            where x is not null and not (x = any (v_sel)))
                else '{}'::uuid[] end;
  v_all := v_sel || v_bak;
  n := cardinality(v_sel);

  if c.selection_closed_at is not null and not (coalesce(c.backups_open, false) and n = 0) then
    return jsonb_build_object('error', 'closed');
  end if;
  if cardinality(v_all) = 0 then return jsonb_build_object('error', 'empty'); end if;
  -- The slots left are the slots less the creators already booked: a
  -- selection reopened for four of ten never books sixteen.
  v_booked := public.campaign_booked(c.id);
  if n > 0 and n > c.slots - v_booked then
    return jsonb_build_object('error', 'over-slots', 'slots', c.slots, 'booked', v_booked);
  end if;
  -- Every creator named is still on the campaign and open to choose.
  if (select count(*) from campaign_options o
       where o.id = any (v_all) and o.campaign_id = c.id
         and o.state in ('option', 'shortlisted', 'backup')) <> cardinality(v_all) then
    return jsonb_build_object('error', 'stale');
  end if;
  -- The prices the client read are the prices now.
  select jsonb_object_agg(o.id::text, o.rate) into v_now
    from campaign_options o where o.id = any (v_all);
  if exists (select 1 from campaign_options o
              where o.id = any (v_all)
                and coalesce(p_seen -> (o.id::text), 'null'::jsonb)
                    is distinct from coalesce(to_jsonb(o.rate), 'null'::jsonb)) then
    return jsonb_build_object('error', 'prices', 'rates', v_now);
  end if;

  update campaign_options set state = 'option'
   where campaign_id = c.id and state in ('shortlisted', 'backup');
  if n > 0 then
    update campaign_options set state = 'shortlisted'
     where campaign_id = c.id and id = any (v_sel) and state = 'option';
  end if;
  if cardinality(v_bak) > 0 then
    update campaign_options set state = 'backup'
     where campaign_id = c.id and id = any (v_bak) and state = 'option';
  end if;

  select jsonb_agg(jsonb_build_object('id', o.id, 'creator', cr.name, 'rate', o.rate, 'as', o.state)
                   order by o.position, o.added_at)
    into v_snap
    from campaign_options o join creators cr on cr.id = o.creator_id
   where o.id = any (v_all);
  insert into campaign_confirmations (campaign_id, kind, person, source, idem, snapshot)
  values (c.id, 'client', trim(p_person), 'portal', v_idem, coalesce(v_snap, '[]'::jsonb));

  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          case when n > 0 then n::text || ' creator' || case when n = 1 then '' else 's' end || ' confirmed'
               else cardinality(v_bak)::text || ' backup' || case when cardinality(v_bak) = 1 then '' else 's' end || ' confirmed' end);

  return jsonb_build_object('ok', true, 'selected', n);
end $$;

revoke all on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) from public;
grant execute on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) to anon, authenticated;

create or replace function public.campaign_confirm_creators(
  p_campaign uuid, p_options uuid[], p_person text, p_source text, p_idem text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  c        public.campaigns%rowtype;
  v_ids    uuid[] := array(select distinct x from unnest(coalesce(p_options, '{}'::uuid[])) x where x is not null);
  v_idem   text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
  v_person text;
  v_source text := case when p_source in ('portal', 'whatsapp', 'email', 'call') then p_source else 'whatsapp' end;
  v_ok     integer;
  v_snap   jsonb;
  v_booked integer;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.campaigns where id = p_campaign for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_scope_ok('campaign', c.id, 'work') then
    return jsonb_build_object('error', 'client-scope');
  end if;
  if v_idem is not null and exists (select 1 from public.campaign_confirmations k
                                     where k.campaign_id = c.id and k.idem = v_idem) then
    return jsonb_build_object('ok', true, 'again', true);
  end if;
  if cardinality(v_ids) = 0 then return jsonb_build_object('error', 'empty'); end if;
  select count(*) into v_ok from public.campaign_options o
   where o.id = any (v_ids) and o.campaign_id = c.id and o.state = 'shortlisted';
  if v_ok <> cardinality(v_ids) then
    return jsonb_build_object('error', 'stale', 'count', cardinality(v_ids) - v_ok);
  end if;
  -- Never more booked than the campaign's slots (second audit, item 10).
  v_booked := public.campaign_booked(c.id);
  if v_booked + cardinality(v_ids) > coalesce(c.slots, 0) then
    return jsonb_build_object('error', 'over-slots', 'slots', c.slots, 'booked', v_booked);
  end if;
  v_person := coalesce(nullif(btrim(coalesce(p_person, '')), ''), me.name);

  select jsonb_agg(jsonb_build_object('id', o.id, 'creator', cr.name, 'rate', o.rate, 'as', o.state)
                   order by o.position, o.added_at)
    into v_snap
    from public.campaign_options o join public.creators cr on cr.id = o.creator_id
   where o.id = any (v_ids);
  insert into public.campaign_confirmations (campaign_id, kind, person, source, idem, snapshot)
  values (c.id, case when v_source = 'portal' then 'client' else 'keyed_in' end,
          v_person, v_source, v_idem, coalesce(v_snap, '[]'::jsonb));
  update public.campaign_options
     set state = 'confirmed', confirmed_at = now(), confirmed_by = v_person
   where id = any (v_ids);
  update public.campaigns set state = 'production' where id = c.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.locked', c.title,
          cardinality(v_ids)::text || ' creators · ' || v_person);

  return jsonb_build_object('ok', true, 'confirmed', cardinality(v_ids));
end $$;
revoke all on function public.campaign_confirm_creators(uuid, uuid[], text, text, text) from public, anon;
grant execute on function public.campaign_confirm_creators(uuid, uuid[], text, text, text) to authenticated;

/* A slot holding a booked creator is never taken away by editing a number:
   free the booking first, then lower the count. */
create or replace function public.campaigns_slots_floor()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_booked integer;
begin
  if new.slots is distinct from old.slots then
    v_booked := public.campaign_booked(new.id);
    if coalesce(new.slots, 0) < v_booked then
      raise exception 'slots-booked: % creators are booked', v_booked
        using errcode = '23514', hint = 'slots-booked';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.campaigns_slots_floor() from public, anon, authenticated;
create or replace trigger campaigns_slots_floor
  before update of slots on public.campaigns
  for each row execute function public.campaigns_slots_floor();

-- END OF SLOTS HOLD THEIR BOOKINGS ------------------------------------------

select public.functions_tidy();
