<!-- triggers: js/seal.js -->
# Signed documents (`js/seal.js`, `2026-11-17-signed-seal.sql`; specs/SEAL-SPEC.md)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- One mechanism for every document a client or candidate signs (quotations
  now, the Employment Offer and Contract next): `ADspaceSeal` (`device`,
  `sha256`, `pagesFor`, `addRecord`, `rows`, `panel`, `open`), the
  `signing_steps` table (`doc_kind`, `step`: `opened`, `code`; RLS on, no
  policy, no grant) and `seal_device`. Never quotation-only code.
- A signer's steps keep the time, address, country and the device as the
  browser reports it (browser, system, screen, time zone, language; never a
  MAC address): the link read (`quote_opened`, anon, once in six hours an
  address and device, a hundred a document, never a colleague's or an unsent
  website quotation's), the code (`quote_sign_code`), the signature
  (`signed.record.device`).
- Approving a signed quotation seals it once (`quotation_review` ok, then
  the reviewer's page): drawn with its Record of this Document as the last
  page (Document ID, the SHA-256 of the signed pages, Verify with a QR code
  of `/verify/?s={ref}`, every step to the second GMT+8, Slate Book 9pt in
  every cell, every foot counting the Record page), stored private
  (`sign-upload` `seal`), kept by `quotation_seal` (Quotations Work, once;
  `not-reviewed`, `bad-key`, `bad-sha`, a second answering `kept`) with the
  whole file's SHA-256 beside the pages'. Never drawn again: every Download,
  send and Preview hands that file over (`sign-download` `quotation`); one
  confirmed before, or whose keep failed, is sealed at its next Download by
  a colleague at Work. Gated on `s3.privateInvoices`.
- The quotation's ⋯ Record (`#sealSheet`, `quotation_record`, Quotations
  View): State (Confirmed · sealed with the padlock), Document ID, SHA-256,
  Verify, and every step to the second (issued, sent on the link, WhatsApp
  or email, opened, code sent, signed, submitted, sent back, confirmed,
  sealed).
- The client's link reads Accepted · awaiting ADspace confirmation with who
  signed to the second, then Confirmed by ADspace on its day with the
  Document ID (`quote_seal_state`, anon) and Download signed copy
  (`sign-download` `quoteKey`, the service role's `quote_seal_key`), the
  main Download then gone.
- /verify/ offers a sealed copy's file check against the whole file's
  SHA-256, and its details for the Document ID (from 2026-11-20 the short
  code the Record page and every foot print; before, its uuid) (Documents,
  `/verify/`).
- Ways out (`2026-11-17-quotation-ways-out.sql`, decision 8): before
  signing the team cancels (Cancel) and the client declines on the link
  (Decline, under Accept, an optional reason of 300: `quote_decline`, anon,
  the quotation then Cancelled to the team and Declined to the client and
  on the row, the Declined step in its record, who prepared it and the
  person in charge told, `quote.declined`); once signed it is never
  deleted: the ⋯'s Mark withdrawn (Clients: Quotations Full Access;
  `quotation_withdraw`, a day from its signing to today and a reason, the
  lines its approval confirmed back to To quote where ticked, each line's
  state kept; `not-signed`, `withdrawn`, `bad-date`, `bad-reason`) with Undo
  where it happened (`quotation_withdraw_undo`), the sealed copy kept, its
  record, /verify/, the Register and the client's link reading Withdrawn
  from that day.
- Documents lists every quotation sent out or signed as its first family,
  Quotations, read from `quotations` (no copy): the reference, its state as
  the record says it, the brand, the company that signed, the day; its ⋯
  Download (the sealed copy, where sealed) and Open client record.
