-- ===========================================================================
-- SHORT LINK CLICKS (2026-11-27)
-- ===========================================================================
-- WHY: the linked sections (the user, 27 Nov: "the link could proceed on",
-- flow 4 as recommended): a short link the team makes for a client or a
-- campaign had no owner and the redirector stored nothing, so nobody could
-- see whether a printed or posted link was used. A link now belongs to a
-- client or a campaign (a campaign's link to its client too), and the
-- redirector counts each day's visits after it has sent the visitor on.
-- Counts only: no address, device, referrer or cookie is kept.
--
-- WHAT CHANGES
--   * `links.client_id`, `links.campaign_id` (each `on delete set null`:
--     deleting a client or campaign clears the owner, never the link);
--     trigger `links_owner` sets a campaign's link's client from its
--     campaign.
--   * `link_clicks (slug, code, day, n)`: one row a link, QR code ('' for
--     the link typed) and Malaysian day; deleted with its link (`on delete
--     cascade`). RLS on, read at Short Links View, written by `link_hit`
--     alone; kept three years, as the Activity record.
--   * `link_hit(p_slug, p_qr)` (anon, called by the `adspace-links` Worker
--     after its redirect): a live link's day count +1, a live QR code of
--     that link counted under its code; anything else counted nowhere;
--     the link's counts past three years let go.
--   * 2026-10-07-function-hygiene.sql: `link_hit` joins `open_to_anon`.
--
-- ORDER: 2026-10-07-function-hygiene.sql first (its list takes `link_hit`,
-- so the tidy at this file's end keeps the anon grant), then this file
-- (connector), then the pages, then the Worker (`workers/links`, deployed by hand or the
-- coordinator's Cloudflare connector). Until the Worker is deployed nothing
-- is counted and the pages read no clicks; an old page never sends an
-- owner. Safe to run twice.
-- ROLLBACK: the Worker from main before this release (it stops counting);
-- `drop function public.link_hit(text, text)`; the table, trigger and
-- columns may stay.
-- ===========================================================================

-- SHORT LINK CLICKS ----------------------------------------------------------

alter table public.links add column if not exists client_id uuid references public.clients(id) on delete set null;
alter table public.links add column if not exists campaign_id uuid references public.campaigns(id) on delete set null;
create index if not exists links_client_idx on public.links(client_id) where client_id is not null;
create index if not exists links_campaign_idx on public.links(campaign_id) where campaign_id is not null;

/* A campaign's link belongs to its campaign's client. */
create or replace function public.links_owner()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.campaign_id is not null then
    select c.client_id into new.client_id from public.campaigns c where c.id = new.campaign_id;
  end if;
  return new;
end $$;
revoke all on function public.links_owner() from public, anon, authenticated;
drop trigger if exists links_owner on public.links;
create trigger links_owner before insert or update on public.links
  for each row execute function public.links_owner();

create table if not exists public.link_clicks (
  slug  text not null references public.links(slug) on delete cascade,
  code  text not null default '',
  day   date not null,
  n     integer not null default 0 check (n >= 0),
  primary key (slug, code, day)
);
create index if not exists link_clicks_day_idx on public.link_clicks(day);
alter table public.link_clicks enable row level security;
revoke all on public.link_clicks from public, anon, authenticated;
grant select on public.link_clicks to authenticated;
drop policy if exists link_clicks_read on public.link_clicks;
create policy link_clicks_read on public.link_clicks for select to authenticated
  using (public.allowed('links', 'view'));

create or replace function public.link_hit(p_slug text, p_qr text default null)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_code text := lower(btrim(coalesce(p_qr, '')));
  v_day  date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if not exists (select 1 from public.links l where l.slug = v_slug and l.active) then return; end if;
  if v_code <> '' and not exists (
       select 1 from public.link_qrs q where q.code = v_code and q.slug = v_slug and q.active) then
    return;
  end if;
  insert into public.link_clicks (slug, code, day, n) values (v_slug, v_code, v_day, 1)
  on conflict (slug, code, day) do update set n = public.link_clicks.n + 1;
  /* Kept three years, as the Activity record. */
  delete from public.link_clicks c where c.slug = v_slug and c.day < (v_day - interval '3 years')::date;
end $$;
revoke all on function public.link_hit(text, text) from public;
grant execute on function public.link_hit(text, text) to anon, authenticated;

-- END OF SHORT LINK CLICKS ---------------------------------------------------

select public.functions_tidy();
