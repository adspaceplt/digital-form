# Import from Meta — setup

Import from Meta reads a report period's figures straight from Meta: the ads
of a client's ad accounts for the Advertising Report, and the posts of its
Facebook Page and Instagram account for the Social Media Accounts Report.
Every figure is Meta's. The `meta-import` edge function holds the token; it
never reaches a browser, the repository or a chat.

Until the token is saved, the portal says **Meta is not connected.** and
everything else works as before (Import from Ads Manager and Import from
spreadsheet are unchanged).

## 1. The app

1. In Meta for Developers, create a **Business** app and link it to
   ADspace's business portfolio.
2. Add the **Marketing API** product.
3. Note the app's **App secret** (App settings → Basic) for step 4.

## 2. The system user

1. Business Settings → Users → **System users** → Add: name it
   **ADspace Portal**, role **Admin**.
2. **Assign assets** to it:
   - the app (Full control);
   - every client ad account (View performance is enough);
   - every client Facebook Page and Instagram account (View content and
     insights).
   Accounts a client shares with ADspace as a partner appear under Business
   Settings → Accounts once accepted, and are assigned the same way.
3. **Generate token** for the app with these permissions:
   `ads_read`, `read_insights`, `pages_read_engagement`, `pages_show_list`,
   `instagram_basic`, `instagram_manage_insights`, `business_management`.
   Choose **Never** for expiry where offered. Where only 60 days is offered,
   note the date: the token must be generated again before then, and the
   portal says **Meta refused the portal's access. The token needs
   renewing.** once it lapses.

## 3. The secrets

Supabase → Project settings → Edge Functions → **Secrets**:

| Name | Value |
|---|---|
| `META_SYSTEM_TOKEN` | the system user's token (step 2.3) |
| `META_APP_SECRET` | the app secret (optional; every call then carries `appsecret_proof`) |
| `META_GRAPH_VERSION` | optional; `v26.0` when unset |

Paste them in the dashboard yourself. Never send them in a chat or commit
them.

## 4. The function

`meta-import` is deployed by Claude through the Supabase connector with
**Verify JWT off**, as every console function: the browser's preflight
carries no Authorization header, and the function asks the database about
the caller itself (Clients at Work for the picker; Reports at Work, the
report a draft and the account one the client linked, for an import).

## 5. Linking a client

1. Open the client → **Brand** → **Meta** → **Edit**.
2. Tick the client's ad accounts, pick its Facebook Page and its Instagram
   account. Only what the system user can see is offered; an account that is
   missing has not been assigned to **ADspace Portal** (step 2.2).
3. Save. A white-label client's brands link their own from each brand's ⋯ →
   **Meta accounts**.

## 6. Importing

On a draft report: the Ads step's **Import from Meta** (beside Import from Ads
Manager), or the Posts step's **Import from Meta** (beside Import from
spreadsheet). With two ad accounts, or a Page and an Instagram account, it
asks which; import the other after. The usual import sheet opens with Meta's
figures in it and its line saying what it will add or update; press its
button to import. Ads are matched by Ad ID and posts by their link, so
importing again updates them rather than adding them twice.

## What Meta answers, and what the portal says

| Meta | The portal |
|---|---|
| No token | Meta is not connected. |
| Token expired or revoked | Meta refused the portal's access. The token needs renewing. |
| An account not assigned to the system user | Meta has not shared this account with the ADspace Portal system user. |
| Rate limit | Meta is busy. Try again in a few minutes. |
| Nothing in the period | Meta has no ads (posts) in this period. |

Meta's own error text is written to the function's log only.
