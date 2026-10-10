# WhatsApp setup

The portal sends WhatsApp messages through the WhatsApp Business Platform
(Cloud API), each with a template Meta has approved, and reads back what
became of each one (Sent, Delivered, Read, Failed). Everything is in the
console's **WhatsApp** section (after Clients in the rail):

- **Messages**: every message the portal sent, with its status, and **New
  message**, the composer (a client contact or a creator, an approved
  template, each variable filled in from the record, a report attached
  where the template has a Document header).
- **Templates** (WhatsApp Full Access): which approved template each
  automatic purpose sends, and its switch.

| Purpose | When | Variables, in order |
|---|---|---|
| Report to client | Send on WhatsApp, on a published report; or New message with a report attached | 1 the contact's greeting, 2 the client (or the white-label brand), 3 the report and its period. The PDF is the template's **document header** |
| Feedback request | Request feedback on WhatsApp, in a client's ⋯ | 1 the contact's greeting, 2 the client |
| Team reminders | Each reminder in a colleague's bell (no open task, the outstation record, self-rating, reflection, health check-in) | 1 the colleague's first name, 2 the notice's title, 3 its message |
| Creator updates | A creator's booking confirmed, and Send on WhatsApp in a booked creator's ⋯ | 1 the creator's first name, 2 the campaign. A **Visit website** button with a dynamic URL, `https://digital.adspace.me/creator/?k={{1}}`, opens the creator's own page |
| Approval reminder | Remind, in My Work's Waiting for you, once a published content set or a creator's draft at Reviewing has waited on the client for the Business setting's days (Settings → Due dates, 3 by default) | 1 the contact's greeting, 2 the client, 3 what waits ("2 posts in October posts", "Jane's draft for Raya creators"), 4 the link to approve it (the client's review page or the campaign's selection page). Category **Utility**, no header, no button |

The composer can send any other approved template too; it fills the
greeting first, then the client (or a creator's campaign), and a named
variable by its name, and everything it fills can be changed before Send.
A business-initiated message must use an approved template; free text is not
allowed. A template with an image, video or location header, or a code to
copy, cannot be filled by the portal and is not offered.

## 1. Supabase secrets (Edge Functions → Secrets)

| Secret | Value |
|---|---|
| `WHATSAPP_PHONE_ID` | The **Phone number ID** (below). It is not the phone number itself. |
| `WHATSAPP_WABA_ID` | The **WhatsApp Business Account ID** (below). The portal reads the account's approved templates with it. |
| `WHATSAPP_VERIFY_TOKEN` | Any long random string (30 characters or more, letters and digits). The same string is typed into the Meta app in step 3. |
| `META_SYSTEM_TOKEN` | Already set for Import from Meta. The sender uses it when the same system user holds the WhatsApp permissions and the WhatsApp Business Account (below). |
| `WHATSAPP_TOKEN` | Optional. Set only to send WhatsApp with a different token from Import from Meta. |
| `META_APP_SECRET` | Already set for Import from Meta. `wa-hook` checks every delivery report Meta sends against it, so it must be the secret of the app the webhook is set on (Meta for Developers → the app → App settings → Basic → App secret). |
| `META_GRAPH_VERSION` | Optional; `v26.0` unless set. |

A token or secret goes into Supabase only, never into the chat or the
repository.

### Where to find the Phone number ID and the Business Account ID

- **WhatsApp Manager**: business.facebook.com → WhatsApp Manager (All tools →
  WhatsApp Manager) → **Phone numbers** → the business number → the
  **Phone number ID**. The **WhatsApp Business Account ID** is shown at the
  top of WhatsApp Manager (Account tools → **Overview**, or the account
  selector).
- **Meta for Developers**: developers.facebook.com → My Apps → the app used
  for Import from Meta → **WhatsApp → API Setup** → under **From**, choose the
  business number; the **Phone number ID** and the **WhatsApp Business
  Account ID** are shown beneath it.

The number must show **Connected** on the Cloud API, with a display name
Meta approved.

### Using the Meta system token for WhatsApp

The token Import from Meta uses works for WhatsApp when all three hold:

1. **The app has the WhatsApp product.** Meta for Developers → the app →
   Add product → WhatsApp (already done where API Setup shows the number).
2. **The system user holds the WhatsApp Business Account.** Business
   settings → Users → **System users** → the system user → **Assign assets**
   → WhatsApp accounts → the account → **Full control** (Manage WhatsApp
   account).
3. **The token carries both WhatsApp permissions.** Business settings →
   System users → the system user → **Generate new token** → the same app →
   tick `whatsapp_business_messaging` and `whatsapp_business_management`
   beside the Page and ads permissions Import from Meta already uses → never
   expires. A token generated before the WhatsApp account was assigned does
   not reach it: generate it again and replace `META_SYSTEM_TOKEN` in
   Supabase with the new one (Import from Meta keeps working on it).

Meta's Access Token Debugger (developers.facebook.com/tools/debug/accesstoken)
lists a token's permissions, to confirm both WhatsApp permissions are on it.
`whatsapp_business_management` is what lets the portal read the templates.

## 2. Templates (WhatsApp Manager → Message templates)

Create one template a purpose (category **Utility**, or Marketing for the
feedback request), with `{{1}}`, `{{2}}`… in the body in the order above. The
report template needs a **Document** header. Once Meta approves each, open
the console's **WhatsApp** section → **Templates**, press **Edit** on the
purpose and choose the template from Meta's approved list (the name,
language and category come from Meta; nothing is typed), then turn its
switch on. A purpose that is off sends nothing, and its record button is not
drawn.

## 3. Delivery reports (the webhook), once

Without this step every message reads **Sent**; with it, Delivered, Read
and Failed (with the reason) arrive by themselves.

1. Meta for Developers → My Apps → the app → **WhatsApp → Configuration**.
2. Under **Webhook**, press **Edit**:
   - **Callback URL**: `https://hwwuigvdfubuymchsvyx.supabase.co/functions/v1/wa-hook`
   - **Verify token**: the same string as `WHATSAPP_VERIFY_TOKEN` in
     Supabase.
   - Press **Verify and save**. Meta calls the address once; `wa-hook`
     answers only when the verify token matches.
3. Under **Webhook fields**, press **Manage** and **Subscribe** to
   **messages**. (Nothing else is needed in this phase.)
4. The WhatsApp Business Account must be subscribed to the app. Send one
   message from the composer; if it still reads Sent a minute after the
   recipient has it, subscribe the app once: developers.facebook.com/tools/explorer
   → the app, the system user's token → **POST** `{WhatsApp Business Account
   ID}/subscribed_apps` → Submit (the answer reads `"success": true`).

`wa-hook` reads only the delivery reports of messages the portal sent.
Messages people send to the business number are not read in this phase,
and nothing from WhatsApp is ever sent to an AI service.

## 4. Who may send

The WhatsApp section is on the Team panel like any other: **View** reads the
messages, **Manage** sends from the composer and from records, **Full
Access** chooses the templates. Under its Advanced, **Send a published
report**, **Feedback request** and **Booking message** follow the section
or are set to No Access. A send also needs the record's own section: Reports
for a report, Clients for a feedback request or a contact, Creator
Campaigns for a booking or a creator.

## 5. Numbers

- A client's contact: its WhatsApp number where one is typed, else its
  phone. A WhatsApp username (`@name`) cannot be messaged; the composer says
  so.
- A colleague: their mobile (Team).
- A creator: their WhatsApp number (the creator's record in the Creators
  List).
- Numbers are read as the team types them: a leading 0 is Malaysia
  (`0123456789`, `01234567890` take 60), any other 8 digits Singapore
  (`12345678` takes 65), 9 or 10 digits starting 1 a Malaysian mobile typed
  without its 0, and a number typed with its country code is kept. The
  composer and the Messages list show it as it will be sent
  (`+60 12-345 6789`).

## 6. What happens

Reminders and creator confirmations are queued by the database
(`wa_outbox`) and sent by `wa-send` straight after; a refusal is tried
again, three times in all, and the Templates tab shows what is waiting and
what was not sent in the last 7 days. A message from the composer or a
record is sent at the press, after the question naming the recipient, the
number and the category Meta charges it as; a report sent is marked as sent
today. Meta's refusals are kept in the function's log (Edge Functions →
wa-send → Logs) and read in the team's words on the Messages list.
