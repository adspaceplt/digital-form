-- ===========================================================================
-- OUTSTATION TRIP NUMBERS IN SETTINGS (2026-11-24)
-- ===========================================================================
-- WHY: the user, 2026-11-24: "you missed to have those numberings in the
-- settings". A trip's number (#OS261101) was typed into
-- `outstation_ref_take`, while task, creator and campaign numbers are set
-- in Settings.
--
-- WHAT IT CHANGES
--   * `id_formats` takes a `trip` row: its prefix (OS) and digits (2), set in
--     Settings' Outstation trip numbers through `id_format_set('trip', …)`
--     and read by `id_formats_list()`. Its next number is unused: a trip's
--     number counts afresh each month (`outstation_ref_months`).
--   * `outstation_ref_take` writes '#' || prefix || YYMM || the month's count
--     to that many digits. A change applies to the next trip; a trip keeps
--     the number it was given.
--
-- ORDER: this file, then the page. Safe to run twice.
-- ROLLBACK: delete the `trip` row, restore `id_formats_kind_check` to
-- creator, campaign and job, and run OUTSTATION TRIP NUMBER #OS's
-- `outstation_ref_take`, ID FORMATS' list and set again.
-- ===========================================================================

alter table public.id_formats drop constraint if exists id_formats_kind_check;
alter table public.id_formats add constraint id_formats_kind_check check (kind in ('creator', 'campaign', 'job', 'trip'));
insert into public.id_formats (kind, prefix, width, next_no) values ('trip', 'OS', 2, 1) on conflict (kind) do nothing;

create or replace function public.id_formats_list()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_team() then coalesce(jsonb_agg(jsonb_build_object(
           'kind', f.kind, 'prefix', f.prefix, 'width', f.width, 'next', f.next_no, 'pattern', f.pattern)
           order by array_position(array['creator', 'campaign', 'job', 'trip'], f.kind)), '[]'::jsonb)
         else '[]'::jsonb end
    from public.id_formats f
$$;
revoke all on function public.id_formats_list() from public, anon;
grant execute on function public.id_formats_list() to authenticated;

create or replace function public.id_format_set(p_kind text, p_prefix text, p_width int, p_next bigint, p_pattern text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  f   public.id_formats;
  v_p text := upper(btrim(coalesce(p_prefix, '')));
  v_t text := btrim(coalesce(p_pattern, ''));
  v_top bigint;
  v_moved text[] := '{}';
  v_word text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into f from public.id_formats where kind = p_kind for update;
  if f.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  v_word := case p_kind when 'creator' then 'Creator ID' when 'campaign' then 'Campaign ID' when 'trip' then 'Outstation trip number' else 'Job reference' end;
  if p_kind = 'job' then
    if length(v_t) > 40 or position('{creator}' in v_t) = 0 or position('{campaign}' in v_t) = 0 then
      return jsonb_build_object('error', 'bad-pattern');
    end if;
    if v_t is distinct from f.pattern then
      update public.id_formats set pattern = v_t, updated_at = now(), updated_by = me.id where kind = p_kind;
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, 'team.changed', 'Creator and campaign IDs', v_word || ': ' || f.pattern || ' → ' || v_t);
    end if;
    return jsonb_build_object('ok', true);
  end if;
  if v_p !~ '^[A-Z]{1,6}$' then return jsonb_build_object('error', 'bad-prefix'); end if;
  if p_width is null or p_width < 2 or p_width > 6 then return jsonb_build_object('error', 'bad-width'); end if;
  if p_next is null or p_next < 1 then return jsonb_build_object('error', 'bad-next'); end if;
  -- A creator's payment details reference: its Creator ID and a run of n.
  if p_kind = 'creator' and v_t <> '' and (length(v_t) > 40 or position('{creator}' in v_t) = 0 or v_t !~ '\{n{1,6}\}') then
    return jsonb_build_object('error', 'bad-request-pattern');
  end if;
  -- The next number stays above every number in use under that prefix; a
  -- trip's number counts afresh each month, so it keeps no next number.
  if p_kind = 'trip' then
    v_top := null;
  elsif p_kind = 'creator' then
    select max(substring(c.creator_code from length(v_p) + 1)::bigint) into v_top
      from public.creators c where c.creator_code ~ ('^' || v_p || '[0-9]+$');
  else
    select max(substring(m.campaign_code from length(v_p) + 1)::bigint) into v_top
      from public.campaigns m where m.campaign_code ~ ('^' || v_p || '[0-9]+$');
  end if;
  if v_top is not null and p_next <= v_top then
    return jsonb_build_object('error', 'bad-next', 'top', v_top);
  end if;
  v_moved := array_remove(array[
    case when v_p <> f.prefix then 'prefix ' || f.prefix || ' → ' || v_p end,
    case when p_width <> f.width then 'digits ' || f.width || ' → ' || p_width end,
    case when p_kind <> 'trip' and p_next <> f.next_no then 'next ' || f.next_no || ' → ' || p_next end,
    case when p_kind = 'creator' and v_t <> '' and v_t is distinct from f.pattern
         then 'payment details reference ' || coalesce(f.pattern, 'not set') || ' → ' || v_t end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.id_formats set prefix = v_p, width = p_width, next_no = case when p_kind = 'trip' then f.next_no else p_next end,
    pattern = case when p_kind = 'creator' and v_t <> '' then v_t else pattern end,
    updated_at = now(), updated_by = me.id
   where kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', case when p_kind = 'trip' then 'Outstation trip numbers' else 'Creator and campaign IDs' end, v_word || ': ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.id_format_set(text, text, int, bigint, text) from public, anon;
grant execute on function public.id_format_set(text, text, int, bigint, text) to authenticated;

create or replace function public.outstation_ref_take(p_at timestamptz)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_m text := to_char(coalesce(p_at, now()) at time zone 'Asia/Kuala_Lumpur', 'YYYYMM'); v_n integer;
  v_p text; v_w int;
begin
  insert into public.outstation_ref_months (month, last) values (v_m, 1)
  on conflict (month) do update set last = public.outstation_ref_months.last + 1
  returning last into v_n;
  -- The prefix and digits are Settings' (Outstation trip numbers).
  select f.prefix, f.width into v_p, v_w from public.id_formats f where f.kind = 'trip';
  v_p := coalesce(v_p, 'OS'); v_w := coalesce(v_w, 2);
  return '#' || v_p || substr(v_m, 3) || lpad(v_n::text, greatest(v_w, length(v_n::text)), '0');
end $$;
revoke all on function public.outstation_ref_take(timestamptz) from public, anon, authenticated;

-- END OF OUTSTATION TRIP NUMBERS IN SETTINGS ----------------------------------

select public.functions_tidy();
