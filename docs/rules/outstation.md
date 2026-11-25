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
- Flow: Check in at the first stop (a client from the Clients picker, then
  its Place: Client's site or Another venue with its name; else No client
  with the venue's name; the user, 2026-11-24: a client's work away from
  its site is still the client's; the purpose a segment of Meeting, Shooting,
  Event, Other; a note; Colleagues; the location; at least one photo),
  then Add stop (the place, the location, a photo) as often as needed, Add
  photo at any time, and Check out (a note, Rate your trip, 1 to 5 stars,
  optional; no location: only the site is read, once; the user, 2026-11-24).
  The visit date and the hours come from the times (check-in at the first
  site to check-out), never typed. A trip open more than four hours shows
  the break reminder.
- The route lists the client sites alone, each from its check-in to its
  check-out; the office is no stop, only the road distance's start and end
  (Settings' pin; the user, 2026-11-24).
- The trip card (the user, 2026-11-25: "crumpled together with just
  text"), the trip in progress and the trip read whole alike, built from
  the v3 components: the head's title, its state (dot and word) and its ⋯
  on one line, centred on it, the title never wrapping (`tests/outstation.js`
  measures it); then the trip as `.facts` (Trip number as a copy token,
  Purpose with its glyph, Driver, Colleagues as names with their initials
  discs; two across on a phone, the last of an odd count taking the row;
  the read whole adds Hours, Rating and the notes), never one dotted
  sentence. Route: its pin glyph in the 22px disc, then the stage timeline
  (`.stl`): the office's start mark, each leg's road km on the line before
  its stop, each stop a dot (filled once left, ringed amber while on site,
  On site as its state at the right, else its time there), the client's
  logo before its name, the address on one line with an ellipsis (a press
  shows it whole), its time, accuracy and photo count as small facts with
  their glyphs, the zone a grey tag only where the address does not
  already end with it, the thumbnails; the return's leg and the office
  once checked out. Add stop and Add photo two equal tonal buttons under
  it; the map credit last, 11px mute, one line on a phone (a press shows
  it whole), never dropped. Distance: its glyph, the figure (`.tally`, So
  far, or Total once checked out), each leg and Return as rows under it.
  Check out alone, blue, nearest the thumb.
- Add claim is not drawn until claims are built (the user, 2026-11-25,
  replacing 2026-11-23's disabled button: a step that cannot apply yet is
  hidden, DESIGN.md §8).
- Location: the browser's own (`watchPosition`, `enableHighAccuracy`,
  `maximumAge: 0`), watched up to 20 seconds, the best reading kept; a
  reading worse than Settings' limit (`outstation_accuracy_m`, 50 m) is
  refused on the page and by the database (`vague`, the limit and the
  reading) with the way to turn precise location on (iPhone: Precise
  Location; Android: Google Location Accuracy). A new read cancels the one
  before, and a sheet shut stops its read. Never an IP lookup.
- Photos: the camera alone (`accept=image/*`, `capture=environment`) on
  every Add photo, Check in and Add stop alike, never a picker of the
  album: an iPhone opens the camera directly; Android may offer the gallery
  beside the camera on some devices, which the page cannot prevent
  (2026-11-25). Drawn
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
- Place and distance (`outstation-geo`), both from openrouteservice on the
  one `ORS_API_KEY` (Nominatim refused the function's servers, 403,
  2026-11-24): the address and zone (Johor, Singapore, Beyond Johor) from
  its geocoder, once a stop and once for a reading before it is saved
  (`near`, My Work at Work, nothing written), one request a second across
  the portal (`outstation_geo_turn`); the road km from its matrix (each
  leg its row i, column i; the directions answer asked without
  instructions carried no legs), office to each stop in order and, once
  checked out, back to the office (`km_from_prev`, `km_back`, `km_total`);
  credited under the route (© openrouteservice.org by HeiGIT · Map data ©
  OpenStreetMap contributors).
- A trip of the driver's own missing a stop's address or a leg is asked
  again when the driver opens the list, once a visit (each stop, then the
  legs; 2026-11-24: OS/20261101 came before the lookup worked and never
  asked again).
- The location block shows the reading's coordinates as it arrives and the
  place the geocoder names once the reading is accepted (2026-11-24).
- A photo reaches the page as `application/octet-stream` and is named by
  `ADspaceAPI.fileOf` (2026-11-24: an image/jpeg answer reached it as
  text, and every photo read Not available). The office is
  Settings' pin (`outstation_office_lat`, `outstation_office_lng`). With no
  `ORS_API_KEY` secret the route answers `{ off: true }` and the page reads
  Not available.
- Data: `outstation_trips`, `outstation_stops`, `outstation_photos`, RLS on,
  no policy, no grant; every read and write a security definer function.
  Kept for `outstation_keep_months` (24) after check-out, then pruned nightly
  (`outstation-prune`, 03:47 MYT), the filed visits kept.
- Check in carries no explanatory line: neither who records the trip nor
  the personal data notice (the user, 2026-11-24: "remove these").
- Check in reads Client (and Venue), Location, the photo, then Purpose,
  Note and Colleagues: what it waits for first (2026-11-24).
- Every trip has a number, `#OS{YYMM}{NN}` (`#OS261101`, as a task is `#WT00001`; the user, 2026-11-24) (`outstation_trips.ref`; the
  user, 2026-11-24): the Malaysian month of check-in and its count from 01,
  two digits and more past 99, given on insert from `outstation_ref_months`
  under the month's row lock, never changed (`code-fixed`) and never given
  again after a delete. It heads the trip's facts and leads a list
  row's meta line, heads the trip read whole's facts (Trip number, a copy
  control where it is not inside a row's button) and is the CSV's first
  column. Console search does not read trips (no table a page reads).
- Delete (`outstation_trip_delete(p_trip, p_confirm)`; the user,
  2026-11-24): the last item of the trip's ⋯ (the trip in progress's head,
  the trip read whole's sheet head), drawn for the driver's own trip, open
  or checked out, and for an admin on any; My Work at Full control deletes
  with the number typed back, at Edit it is Request delete, filed through
  `delete_kinds` (`rpc:outstation_trip_delete`, named by the number) for an
  admin. The trip goes with its stops, its photo rows and the visits it
  filed on the clients' Calls and visits (a deleted trip did not happen;
  the user, 2026-11-24); a visit written by hand stays, and the photo files
  stay in storage. Filed `ops.deleted` under the
  number. A deleted open trip frees its driver to check in again.
- A client's stop is filed on its Calls and visits as it begins ("from
  2:00pm (in progress)", the venue named) and completed with its end time
  once left (`outstation_file_visit`; OUTSTATION VISITS FOR THE CLIENT).
- A stop's photos are drawn under it as tiles (`.ost-thumbs`, the sheet's
  photo tile, 64px at a desk and 56px on a phone, wrapping), on the trip in
  progress and on a trip read whole, My trips and All trips alike, and the
  count beside them counts the photos shown (the user, 2026-11-25: "1
  photo" alone). Every photo of a trip is signed in one request
  (sign-download `outstation.trip`, an hour's S3 link a photo, the keys
  `outstation_photo_keys` answers the caller), never one a photo; a repaint
  asks nothing again until the links near their hour or a photo is new. A
  photo still being saved shows at once from the phone with the turning
  ring; a tile that cannot load stays shaded.
- A tile opens the photo full size in a sheet (sheets never stack: from a
  trip read whole it closes back to that trip), titled by the stop's place,
  with Taken, Accuracy (in metres) and the stop's Address; it offers no Download or
  Share of its own (the image is not draggable and carries no iPhone
  callout).
- Remove (OUTSTATION PHOTOS SHOWN AND REMOVED, 2026-11-25): the photo's ⋯
  in that sheet, offered only to the driver (who alone adds photos), only
  while the trip is in progress, and only while another photo stays at the
  stop: a stop always keeps one (`no-photo`; `outstation_photo_remove`
  refuses the same, the trip row locked so two removes cannot take a
  stop's last two). A soft remove: `removed_at`, `removed_by` on
  `outstation_photos`, asked nothing, with Undo where it happened
  (`outstation_photo_restore`, the same driver, the trip still open); the
  row and the S3 file stay. A removed photo is no photo for the next stop
  or check-out, leaves the driver's and the companions' reads and the
  count, and is answered only at `ops.outstation`: under All trips it is
  drawn faded, marked Removed, its sheet naming who removed it and when.
