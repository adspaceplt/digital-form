-- ===========================================================================
-- SERVICE SKU — a rate card line carries its Bukku item code
-- 2026-10-15. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner.
--
-- WHY (the user, 2026-10-15: "can the services or packages add the SKU
-- code"; typed to match Bukku, shown on the rate card)
--   Quotations and invoices are issued in Bukku, which names each item by its
--   own code. The rate card held no such code, so a line could not be
--   matched to its Bukku item at a glance.
--
-- WHAT CHANGED
--   * `services.sku`: the item code as typed (letters, digits and . _ / -,
--     40 at most, starting with a letter or a digit), optional, one line
--     each (`services_sku_idx`, unique ignoring case). Written by the line's
--     own sheet under the services policies (Services at Manage).
--   * It is a reference, not a priced fact: `rate_card_draft` leaves it out,
--     so changing it never marks the card as changed.
--
-- ORDER
--   This file first, then the pages (search and the line's sheet read and
--   write the column). A page from before never reads or writes it.
--
-- ROLLBACK
--   alter table public.services drop column if exists sku;
--   (the index and the check go with it)
-- ===========================================================================

alter table public.services add column if not exists sku text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'services_sku_shape') then
    alter table public.services add constraint services_sku_shape
      check (sku is null or sku ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$');
  end if;
end $$;

create unique index if not exists services_sku_idx on public.services (lower(sku)) where sku is not null;

-- END OF SERVICE SKU ----------------------------------------------------------
