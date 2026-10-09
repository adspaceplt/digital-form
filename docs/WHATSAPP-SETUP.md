# WhatsApp setup

The portal sends four kinds of WhatsApp message through the WhatsApp Business
Platform (Cloud API), each with a template Meta has approved:

| Purpose | When | Variables, in order |
|---|---|---|
| Report to client | Send on WhatsApp, on a published report | 1 the contact's first name, 2 the client (or the white-label brand), 3 the report and its period. The PDF is the template's **document header** |
| Feedback request | Request feedback on WhatsApp, in a client's ⋯ | 1 the contact's first name, 2 the client |
| Team reminders | Each reminder in a colleague's bell (no open task, the outstation record, self-rating, reflection, health check-in) | 1 the colleague's first name, 2 the notice's title, 3 its message |
| Creator updates | A creator booked, asked for changes, or cleared to post | 1 the creator's first name, 2 the campaign, 3 the step |

A template may use fewer variables than listed: set **Variables** to the
number its body holds, and the first ones are sent. A business-initiated
message must use an approved template; free text is not allowed.

## 1. Supabase secrets (Edge Functions → Secrets)

| Secret | Value |
|---|---|
| `WHATSAPP_PHONE_ID` | The **Phone number ID** (WhatsApp Manager → Phone numbers, or the app's WhatsApp → API Setup). It is not the phone number itself. |
| `WHATSAPP_TOKEN` | A **system user** token with `whatsapp_business_messaging` (and `whatsapp_business_management`), assigned the WhatsApp Business Account. Unset, the Meta system user's `META_SYSTEM_TOKEN` is used, once that system user has the WhatsApp account assigned. |
| `META_GRAPH_VERSION` | Optional; `v26.0` unless set. |

The token is a secret: it goes into Supabase only, never into the chat or the
repository. The WhatsApp Business Account ID is not needed by the sender.

## 2. Templates (WhatsApp Manager → Message templates)

Create one template a purpose (category **Utility**, or Marketing for the
feedback request), with `{{1}}`, `{{2}}`… in the body in the order above. The
report template needs a **Document** header. Once Meta approves each, open
the console's account menu → **WhatsApp** (Business settings), press Edit on
the purpose, and enter the template's name and language exactly as Meta shows
them (for example `monthly_report`, `en`), the number of variables, and tick
On. A purpose that is Off sends nothing.

## 3. Numbers

- A client's main contact: its WhatsApp number where one is typed, else its
  phone. A WhatsApp username (`@name`) cannot be messaged.
- A colleague: their mobile (Team).
- A creator: their WhatsApp number (the creator's record in the Creators
  List).
- Malaysian numbers with a leading 0 take 60; a Singapore client's 8-digit
  number takes 65.

## 4. What happens

Reminders and creator updates are queued by the database (`wa_outbox`) and
sent by `wa-send` straight after; a refusal is tried again, three times in
all. A report or feedback request is sent at the press, and a report sent is
marked as sent today. The last fifty messages, sent or not, are listed in the
WhatsApp sheet. Meta's refusals are kept in the function's log
(Edge Functions → wa-send → Logs).
