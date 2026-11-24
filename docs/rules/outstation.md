<!-- triggers: js/outstation.js supabase/functions/outstation-geo -->
# Outstation record (`js/outstation.js`, My Work `view=outstation`)

Rules for this area (OUTSTATION RECORD, 2026-11-23; the user approved the
mockup's screens 1, 2 and 5). It replaces the Lark form "Outstation Record
Form"; claims are release 2. One place per fact, as CLAUDE.md §0.

- A tab of My Work (`view=outstation`, `ov=all` for All trips, `om=` its
  month), never a rail section; drawn by its own script, fetched on first
  ask (`#lazyScripts` `outstation`, `paintOutstation` in `js/ops.js`), into
  `#workOut`. The list's own controls (Add task, the ⋯, the period, the
  search) step away on it, as on Months.
- Who: the driver records the trip (My Work at Work); the colleagues going
  together are named at Check in and read it as their own; every trip, read
  only, with Download (a CSV, a row a stop), is the granted part
  `ops.outstation` (an admin's by itself, View alone).
- Flow: Check in at the first stop (a client from the Clients picker, else
  Other place with its venue; the purpose a segment of Meeting, Shooting,
  Event, Other; a note; Going together; the location; at least one photo),
  then Next stop (the place, the location, a photo) as often as needed, Add
  photo at any time, and Check out (the location, a note, Rate your trip, 1
  to 5 stars, optional). The visit date and the hours come from the times,
  never typed. A trip open more than four hours shows the break reminder.
- Add claim (Coming soon) stands beside Check out, tonal, its words mute,
  `aria-disabled`, opening nothing, until claims are built (the user,
  2026-11-23): the one act drawn disabled for being not yet built.
- Location: the browser's own (`watchPosition`, `enableHighAccuracy`,
  `maximumAge: 0`), watched up to 20 seconds, the best reading kept; a
  reading worse than Settings' limit (`outstation_accuracy_m`, 50 m) is
  refused on the page and by the database (`vague`, the limit and the
  reading) with the way to turn precise location on (iPhone: Precise
  Location; Android: Google Location Accuracy). A new read cancels the one
  before, and a sheet shut stops its read. Never an IP lookup.
- Photos: the camera alone (`accept=image/*`, `capture=environment`), drawn
  down to a 1600px JPEG (the picture's own metadata left behind), each with
  its time and the location at capture, private under
  `private/outstation/{trip}/` (sign-upload `outstation`, asked of
  `outstation_photo_may`; read back through sign-download `outstation`,
  asked of `outstation_photo_key`). Ten a stop, twenty stops a trip.
- The next stop and check-out wait for a photo at the stop in hand
  (`no-photo`).
- A client stop, once left, files a visit on the client's Calls and visits
  under the driver's name; one the client scope refuses is left unfiled,
  never failing the trip. Naming a client asks Clients at View and its
  client scope (`bad-client`).
- Place and distance (`outstation-geo`): the address and zone (Johor,
  Singapore, Beyond Johor) from OpenStreetMap Nominatim, once a stop, one
  request a second across the portal (`outstation_geo_turn`), credited under
  the route (Addresses © OpenStreetMap contributors); the road km from
  openrouteservice, office to each stop in order and, once checked out,
  back to the office (`km_from_prev`, `km_back`, `km_total`). The office is
  Settings' pin (`outstation_office_lat`, `outstation_office_lng`). With no
  `ORS_API_KEY` secret the route answers `{ off: true }` and the page reads
  Not available.
- Data: `outstation_trips`, `outstation_stops`, `outstation_photos`, RLS on,
  no policy, no grant; every read and write a security definer function.
  Kept for `outstation_keep_months` (24) after check-out, then pruned nightly
  (`outstation-prune`, 03:47 MYT), the filed visits kept.
- Check in carries one personal data notice line naming how long a trip is
  kept.
- Check in reads Client (and Venue), Location, the photo, then Purpose,
  Note and Going together: what it waits for first (2026-11-24).
