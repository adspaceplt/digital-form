<!-- triggers: js/push.js js/push-sw.js supabase/functions/push-send -->
# Push notifications (`js/push.js`, `js/push-sw.js`, `push-send`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- A device follows what the page it turned on from proves: the console the
  signed-in colleague (`team`), the selection page a campaign by its token
  (`client`; never a campaign behind a passcode or a Past client's,
  `push_target`, `2026-10-18-a-clients-device-follows-only-a-link-that-opens.sql`),
  the creator's page the creator by their code (`creator`).
  - One colleague and one creator a device; a client's device any number of
    campaigns (`push_subscriptions`, unique `(endpoint, target)`). A target
    takes five new devices an hour and twenty in all (`too-many`), and none
    is pushed out for another (2026-10-22, BE-11).
  - Only a push service's address is stored (`push_endpoint_ok`: Google,
    Apple, Mozilla, Microsoft), and `push-send` checks it again: the sender
    never posts anywhere else.
- What is sent (`push_outbox`, queued by trigger only where a device
  follows):
  - a colleague: every `ops_notifications` row, opening the task;
  - the client: a draft released (Submitted → Reviewing) and a post live
    (Scheduled → Posted);
  - the creator: booked (from option, shortlisted or backup), changes
    requested, and cleared to post (Scheduled from Submitted, Reviewing or
    Changes requested).
  - Only a forward move is told; a Revert tells nobody. Words are the
    device's language (`title_zh` for a Chinese device).
  - A notification never fails the write that caused it (the triggers
    swallow their own errors).
- `pg_net` wakes `push-send` after the commit (`push_kick`, once a
  transaction, with the wake secret; WhatsApp, above). A run stops claiming
  after 90 seconds and each send waits 10 at most (2026-10-26). It claims 50 at
  a time for five minutes (`push_claim`, skip locked), sends a day's TTL, drops
  a device the service answers 404/410 for (`push_done`) and keeps a month.
- The VAPID pair is made by `push-send`'s first run and kept in `app_secrets`;
  only `push_public_key()` leaves the database. No key, no control.
- Each page registers its own worker (`/admin/sw.js`, `/client/sw.js` (files only), `/creators/sw.js`,
  `/creator/sw.js`), all importing `js/push-sw.js`. The client pages carry a
  manifest with no `start_url`, so a Home Screen copy opens its own link.
- Controls:
  - the console: Notifications in the account menu, a switch
    (`role="switch"`, On / Off at the row's right edge); the menu stays open
    and answers under the item (`#acctPushMsg`);
  - the client pages: the bar's bell (`#pushBtn`) opens `#pushPop`, a named
    dialog with one line and one action, its words in `W.push`.
  - An iPhone not on the Home Screen is told to add it; a blocked site is
    named; neither shows a button that cannot work.
- Signing out of the console, and Forget this device on the creator's page,
  stop the device's notifications first.
