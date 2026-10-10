# WhatsApp setup

The portal sends four kinds of WhatsApp message through the WhatsApp Business
Platform (Cloud API), each with a template Meta has approved:

| Purpose | When | Variables, in order |
|---|---|---|
| Report to client | Send on WhatsApp, on a published report | 1 the contact's first name, 2 the client (or the white-label brand), 3 the report and its period. The PDF is the template's **document header** |
| Feedback request | Request feedback on WhatsApp, in a client's ⋯ | 1 the contact's first name, 2 the client |
| Team reminders | Each reminder in a colleague's bell (no open task, the outstation record, self-rating, reflection, health check-in) | 1 the colleague's first name, 2 the notice's title, 3 its message |
| Creator updates | A creator's booking confirmed | 1 the creator's first name, 2 the campaign. A **Visit website** button with a dynamic URL, `https://digital.adspace.me/creator/?k={{1}}`, opens the creator's own page |

A template may use fewer variables than listed: set **Variables** to the
number its body holds, and the first ones are sent. A business-initiated
message must use an approved template; free text is not allowed.

## 1. Supabase secrets (Edge Functions → Secrets)

| Secret | Value |
|---|---|
| `WHATSAPP_PHONE_ID` | The **Phone number ID** (below). It is not the phone number itself, and not the WhatsApp Business Account ID. |
| `META_SYSTEM_TOKEN` | Already set for Import from Meta. The sender uses it when the same system user holds the WhatsApp permissions and the WhatsApp Business Account (below). |
| `WHATSAPP_TOKEN` | Optional. Set only to send WhatsApp with a different token from Import from Meta. |
| `META_APP_SECRET` | Already set for Import from Meta where the app requires the app secret; each WhatsApp call then carries the same proof. |
| `META_GRAPH_VERSION` | Optional; `v26.0` unless set. |

A token is a secret: it goes into Supabase only, never into the chat or the
repository.

### Where to find the Phone number ID

Either place shows it:

- **WhatsApp Manager**: business.facebook.com → WhatsApp Manager (All tools →
  WhatsApp Manager) → **Phone numbers** → the business number → the
  **Phone number ID** (a long number, often starting `1`).
- **Meta for Developers**: developers.facebook.com → My Apps → the app used
  for Import from Meta → **WhatsApp → API Setup** → under **From**, choose the
  business number; the **Phone number ID** is shown beneath it.

The number must show **Connected** on the Cloud API, with a display name
Meta approved. A number still on the WhatsApp Business app must be moved to
the Cloud API first.

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

## 2. Templates (WhatsApp Manager → Message templates)

Create one template a purpose (category **Utility**, or Marketing for the
feedback request), with `{{1}}`, `{{2}}`… in the body in the order above. The
report template needs a **Document** header. Once Meta approves each, open
the console's **Settings** page → **WhatsApp** (Business settings), press Edit on
the purpose, and enter the template's name and language exactly as Meta shows
them (for example `monthly_report`, `en`), the number of variables, and tick
On. A purpose that is Off sends nothing.

## 3. Numbers

- A client's main contact: its WhatsApp number where one is typed, else its
  phone. A WhatsApp username (`@name`) cannot be messaged.
- A colleague: their mobile (Team).
- A creator: their WhatsApp number (the creator's record in the Creators
  List).
- Numbers are read as the team types them: a leading 0 is Malaysia
  (`0123456789`, `01234567890` take 60), any other 8 digits Singapore
  (`12345678` takes 65), 9 or 10 digits starting 1 a Malaysian mobile typed
  without its 0, and a number typed with its country code is kept.
- A booked creator's ⋯ in the campaign has Send on WhatsApp, to send the
  booking and their link again.

## 4. What happens

Reminders and creator updates are queued by the database (`wa_outbox`) and
sent by `wa-send` straight after; a refusal is tried again, three times in
all. A report or feedback request is sent at the press, and a report sent is
marked as sent today. The last fifty messages, sent or not, are listed in the
WhatsApp sheet. Meta's refusals are kept in the function's log
(Edge Functions → wa-send → Logs).
