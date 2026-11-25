-- ===========================================================================
-- RATE CARD LINE ORDER (2026-11-25)
-- ===========================================================================
-- WHY: Services lists a category's lines by `services.position`, and a new
-- line was given the position after every line on the card, so an add-on
-- added later stood apart from its own kind (the user, 2026-11-25, Add-ons
-- on an iPhone: "This is not arrange in sequence?"), with no way to move a
-- line.
--
-- WHAT IT CHANGES
--   * `services_place` (before insert, and an update of category): a line
--     inserted without a position (the page's Add service), or moved to
--     another category with its position untouched (its Edit), takes the
--     place after the last line of that category; the lines after it move
--     one place where that place is taken. A category with no line yet goes
--     after the card. A seed or an insert naming its position is left as
--     written.
--   * `rate_card_move(p_slug, p_dir, p_seen)`: Services Full Access moves a
--     line one place up (-1) or down (1) among the lines of its category in
--     the same state (active or inactive), as the list draws them. The page
--     sends the category's order as it holds it (`p_seen`, the slugs by
--     position, then slug); any other order is refused `stale` with the
--     order as it stands, nothing written. The two lines change places in
--     one write; tied positions are spread first. Filed `service.changed`
--     (Moved up in {category}). Refusals: `denied`, `bad-dir`, `gone`,
--     `stale`, `edge`. Answers `order`, the category's lines and positions.
--
-- ORDER: this file, then the page (Move up and Move down ask this
-- function; an open tab without them meets the trigger alone, its new line
-- landing at its category's end). Safe to run twice. Holds no drop or
-- delete.
-- ROLLBACK: `drop trigger if exists services_place on public.services;`
-- `drop function if exists public.rate_card_move(text, int, text[]);`
-- `drop function if exists public.services_place();` (an SQL Editor run of
-- its own); the order already written stays.
-- ===========================================================================

-- RATE CARD LINE ORDER -------------------------------------------------------

create or replace function public.services_place()
returns trigger
language plpgsql set search_path = public as $$
declare
  v_last int;
begin
  if tg_op = 'INSERT' and coalesce(new.position, 0) <> 0 then return new; end if;
  if tg_op = 'UPDATE' and (new.category is not distinct from old.category or new.position is distinct from old.position) then return new; end if;
  select max(s.position) into v_last from public.services s where s.category = new.category and s.slug is distinct from old.slug;
  if v_last is null then
    select coalesce(max(s.position), 0) into v_last from public.services s where s.slug is distinct from old.slug;
  end if;
  if exists (select 1 from public.services s where s.position = v_last + 1 and s.slug is distinct from old.slug) then
    update public.services s set position = s.position + 1 where s.position > v_last and s.slug is distinct from old.slug;
  end if;
  new.position := v_last + 1;
  return new;
end $$;
revoke all on function public.services_place() from public, anon, authenticated;

create or replace trigger services_place
  before insert or update of category on public.services
  for each row execute function public.services_place();

create or replace function public.rate_card_move(p_slug text, p_dir int, p_seen text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  v_row   public.services;
  v_cat   text;
  v_order text[];
  v_pos   int[];
  v_on    boolean[];
  v_n     int;
  v_i     int;
  v_j     int;
  v_k     int;
begin
  if me.id is null or not public.allowed('services', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if p_dir is null or p_dir not in (-1, 1) then return jsonb_build_object('error', 'bad-dir'); end if;
  select s.category into v_cat from public.services s where s.slug = p_slug;
  if v_cat is null then return jsonb_build_object('error', 'gone'); end if;
  perform 1 from public.services s where s.category = v_cat for update;
  select * into v_row from public.services s where s.slug = p_slug;
  if v_row.slug is null or v_row.category is distinct from v_cat then return jsonb_build_object('error', 'stale'); end if;
  select array_agg(s.slug order by s.position, s.slug), array_agg(s.position order by s.position, s.slug),
         array_agg(s.active order by s.position, s.slug)
    into v_order, v_pos, v_on
    from public.services s where s.category = v_cat;
  if p_seen is null or p_seen is distinct from v_order then
    return jsonb_build_object('error', 'stale', 'order', (select jsonb_agg(jsonb_build_object('slug', s.slug, 'position', s.position) order by s.position, s.slug)
      from public.services s where s.category = v_cat));
  end if;
  v_n := array_length(v_order, 1);
  v_i := array_position(v_order, p_slug);
  v_j := v_i + p_dir;
  while v_j between 1 and v_n and v_on[v_j] is distinct from v_row.active loop
    v_j := v_j + p_dir;
  end loop;
  if v_j < 1 or v_j > v_n then return jsonb_build_object('error', 'edge'); end if;
  v_order[v_i] := v_order[v_j];
  v_order[v_j] := p_slug;
  for v_k in 2 .. v_n loop
    if v_pos[v_k] <= v_pos[v_k - 1] then v_pos[v_k] := v_pos[v_k - 1] + 1; end if;
  end loop;
  for v_k in 1 .. v_n loop
    update public.services s set position = v_pos[v_k] where s.slug = v_order[v_k] and s.position is distinct from v_pos[v_k];
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'service.changed', v_row.name, case when p_dir < 0 then 'Moved up' else 'Moved down' end || ' in ' || v_cat);
  return jsonb_build_object('ok', true, 'order', (select jsonb_agg(jsonb_build_object('slug', s.slug, 'position', s.position) order by s.position, s.slug)
    from public.services s where s.category = v_cat));
end $$;
revoke all on function public.rate_card_move(text, int, text[]) from public, anon;
grant execute on function public.rate_card_move(text, int, text[]) to authenticated;

-- END OF RATE CARD LINE ORDER ------------------------------------------------

select public.functions_tidy();
