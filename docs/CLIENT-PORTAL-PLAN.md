# Letters from templates, and a client portal

A plan, not yet built. Two ideas from the same session, in the order they
should be built: letters first (small, proven pieces), then the client
portal on top of the same records.

## 1. Letters from templates

Every letter the team writes by hand in Word (thank you at the end of an
engagement, appointment, reminder, notice of change) becomes a template
in the console. A person picks the client, the template and the date,
checks the preview, and issues. The letter gets its number, is kept as
issued, and is drawn on the letterhead exactly as the Letter of Offer is
today (`js/documents.js`).

### What a template is

| Field | Example |
|---|---|
| Name | End of engagement |
| Prefix | `AEND/` (one prefix per template; sequence per month, like `AQT/INT/`) |
| Subject | WITH APPRECIATION |
| Body | Paragraphs with placeholders: `{client}`, `{legal_name}`, `{contact}`, `{contact_role}`, `{owner}`, `{date}`, `{ref}`, `{services}`, `{review_link}` |
| Closing | Yours sincerely, ADSPACE PLT, `{issued_by}` |
| Signature block | none, ADspace only, or client acceptance |
| Attachments | none, the quoted lines table, the confirmed lines table |

Templates live in a `letter_templates` table (admins edit, everyone
reads), so wording changes without a code push. The body is plain text
with blank lines between paragraphs; no HTML, no Word.

### Numbering

One prefix per template, `PREFIX/YYMMXXX`, sequence per month over what
has been issued with that prefix. `AQT/INT/` stays for the Letter of
Offer. A number is never reused; Void, then Delete, as today.

### What is stored

`client_documents` already holds kind, number, date, the snapshot and
who issued it. A letter stores `template_slug` and the rendered
paragraphs in `bill_to.body`, so a later edit of the template never
changes a letter already issued. The PDF itself is never stored; it is
redrawn from the snapshot on Download. If the accountant wants files on
disk, that is a download, not a storage change.

### Console

Documents on the client record gains Issue letter → a sheet with the
template select, the date (today), the preview text, Issue. The row in
the Documents table shows the number, the template name and the date.
Nothing else changes.

### Effort

Small. The letterhead, numbering, snapshot, Void and Delete exist. New
work is the template table, the placeholder fill, the sheet, and one
test per template.

## 2. Client portal

One sign-in for a client, one page that shows them their own company as
ADspace holds it, with the Content Review and Creator Selection pages
they already use folded in. The console stays the source of truth; the
portal shows what the console marks as visible and takes requests, never
direct edits to money or services.

### Sign-in: what not to do, and what to do

- Not BRN and company name. Both are public (SSM, LinkedIn, invoices,
  the client's own website). Anyone who knows a client could open their
  billing and campaign pages.
- Not a typed OTP. Six digits from an SMS or app every visit is the
  friction the user wants to avoid.
- Do: an email link. Supabase sends a sign-in link to an address the
  console has listed for that client (a contact marked "portal access").
  One tap, no code to type, and the browser stays signed in for 30 days
  on that device. The link expires in ten minutes and works once. This is
  the same sign-in the console uses today, so nothing new to run.
- Later, if wanted: passkeys (Face ID / fingerprint) on top, once the
  Supabase project supports them. No password anywhere.
- The access-token links for `/review/` and `/creators/` keep working
  for people who are not signed in (a manager forwarding a link), and
  open without the gate for people who are.

### Who can sign in

`client_users`: a contact in `client_contacts` gains `portal_email` and
`portal_role` (owner, member). The console's Contacts table gets a
Portal column with a select (No access / Member / Owner). Owners can
invite other members from the portal; members cannot. Every row is one
person, one client; a person at two clients is two rows.

Access is enforced by the database, as the console is: every policy on
client-visible tables checks the signed-in email against `client_users`
for that `client_id`. The page hides nothing that the database would
serve, and serves nothing the database would refuse.

### What the client sees (one page, `/client/`, sections in this order)

| Section | Shows | Client can |
|---|---|---|
| Overview | Company as registered, contacts, account owner at ADspace, stage | Edit contacts (name, role, phone, email); request a change to the registered details (goes to the console as a request, not a direct write) |
| Services | Active lines: service, quantity, rate, term, start and end dates, next renewal | Request upgrade, downgrade or cancellation (see Requests) |
| Requests | Every request with its state | Raise, withdraw before it is reviewed |
| Billing | Invoices (number, date, amount, state), payment guidance (bank details, reference to quote), e-invoice details on file | Download an invoice PDF, upload proof of payment |
| Letters | Letters issued to them (Letter of Offer, others), with Signed / Not signed | Download; upload the signed copy |
| Content Review | The same `/review/` page, signed in | As today |
| Campaigns | The same `/creators/` page per campaign, signed in | As today |
| Account | Who has access, notification preferences | Owner invites or removes members |

Every number on the portal comes from the same snapshot the console
shows: a service line's amount is `qty × rate × months` from
`client_services`; an invoice amount is the stored document; nothing is
computed twice.

### Requests (upgrade, downgrade, cancel)

A request is a row in `client_requests`: client, kind (upgrade,
downgrade, cancel, change of details), the line it concerns, the
client's note, the state, and the fee the terms attach.

States, one direction, every step reversible from the console:
Requested → Reviewing → Approved or Declined → Applied. The client sees
the state word and the chip colour the console uses. A cancellation
shows the fee before the client confirms, from `service_terms`
(a table of rules: notice period, early termination fee as a percentage
or a fixed sum, per service or per package). Approval never changes a
line by itself; a person applies it in the console, so the line's
history stays a human decision.

### Payments

Phase one is guidance, not collection: bank details, the invoice number
as the reference, a place to upload proof, and the console marks the
invoice Paid. Online collection (FPX, card) is a later phase and needs a
payment provider account, a webhook function and reconciliation; it is
listed, not promised.

### Data

New: `client_users`, `client_requests`, `service_terms`, `invoices`
(number, date, amount, state, PDF URL on the CDN, since invoices are
uploaded files) and a `client_visible` flag on documents. Existing
tables stay as they are.

### Rules that carry over

Everything in `DESIGN.md`: the same tokens, components, chips, status
words, phone layout, copy register and PDPA rules. The client page is
held to the copy rules most strictly. Tesler: the console carries the
complexity, the portal does not. A client sees one client.

### Phases

1. Letters from templates (section 1). Two weeks of work at the pace of
   this session.
2. Client sign-in and a read-only portal: Overview, Services, Letters,
   Billing (invoices and guidance), the two existing pages signed in.
3. Requests with fees, contact editing, proof of payment.
4. Notifications (email on a state change) and passkeys.
5. Online collection.

Each phase ships behind a switch in the console (Portal access per
client), so one client can be onboarded first and the rest follow.

### What can go wrong, and the guard

| Risk | Guard |
|---|---|
| A client sees another client's data | Policies keyed on `client_users`; the sweep gains a suite that signs in as two clients and asserts each sees only its own rows |
| Portal and console disagree on a number | One formatter, one snapshot, no second computation on the portal |
| A request silently changes a line | Requests never write to `client_services`; a person applies them |
| A person leaves the client | Owner removes the member; the console can too; access ends at once |
| A forwarded sign-in link | Ten minute expiry, single use, tied to the listed email |
| Wording drift on letters | Templates are data; a letter keeps its rendered text |
