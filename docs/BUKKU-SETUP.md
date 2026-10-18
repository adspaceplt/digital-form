# Bukku setup

The portal sends a client's billing, or an approved supplier's details, to
Bukku as one contact, by hand (Send to Bukku on the client's Billing and on
the supplier). Quotations, invoices and purchase orders are phase 2.

## 1. The API token (done 2026-10-18)

1. In Bukku: Control Panel › Integrations › API Access, turn it on and copy
   the access token.
2. In Supabase: Edge Functions › Secrets, set
   - `BUKKU_TOKEN`: the token;
   - `BUKKU_SUBDOMAIN`: the part before `.bukku.my` (a typed `.bukku.my` is
     cut by the function).

A token that is replaced in Bukku is replaced here too; until then every
send reads "Bukku refused the portal's token".

## 2. The ID fields

1. In Bukku: Control Panel › Custom fields, add two contact fields, text:
   Client ID and Supplier ID (the names are yours).
2. In the portal: Settings › Money › Bukku › Edit, choose each field.

Until both are chosen, Send to Bukku reads "Choose Bukku's Client ID and
Supplier ID fields …".

## 3. What a send does

- Reads Bukku's contacts and offers the one with the same registration
  number, else the same or a similar name; or a new contact under Bukku's
  next code for the name's first letter.
- Shows each field it changes, before and after.
- Creates the contact, or updates the one chosen keeping its code, terms,
  accounts, groups, other people and addresses. Its types gain Customer or
  Supplier and never lose one. Nothing in Bukku is deleted or archived.
- Files the link; the record's Bukku group reads the code, when it was sent
  and by whom, and whether the portal's details changed since.

## 4. Who may send

- A client: Clients: Billing at Full Access (Work).
- A supplier: Suppliers at Full Access (Work), once approved. The NRIC is
  sent only by a colleague holding Supplier bank details; bank details are
  never sent.
- Choosing the fields: Business settings (`team.settings`).
