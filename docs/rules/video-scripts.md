<!-- triggers: js/scripts.js js/scriptpdf.js js/script.js script/ js/frames.js js/animatic.js supabase/functions/script-draft supabase/functions/script-pictures -->
# Video Scripts (`js/scripts.js`, `js/scriptpdf.js`, `?s=scripts`; `script/`, `js/script.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- One script is one full video (the user, 2026-10-09), its own section on
  the ladder (`scripts`, every group starting at its Content Review level;
  `2026-10-09-video-scripts.sql`), in the Work chunk after Content Review.
  Three kinds: Detailed scenes (Visual and Script a scene), Products and
  scenes (Products and context, then the scenes), Story and voice-over (Hook
  and story, the scenes, Script (read here)).
- A script is a client's content month's (`2026-10-09-scripts-by-month.sql`;
  the user: "we are working on content month, monthly basis"): `period`,
  `seq` and `code` YYMMVSNN (`2610VS01`), NN the lowest free a client a
  month (unique), `engagement_id` the client's My Work month where one
  exists (never required). New script asks the client, the month (last
  month, this month and the next six, as My Work offers) and the type,
  and Add script (at the end of the month's tabs) the month's next: each
  opens a New script editor and stores nothing until Save
  (`video_script_new`, then `video_script_save`; Cancel back to where it
  was opened; 2026-10-15); Write with AI on it says the script is saved
  first, taking its number (`script-draft` reads the row). Save takes
  the month's next number, Add script's with the header copied (platform, language,
  shooting date and time, venue, duration, cast) and the script empty; the
  editor's Content month moves it, taking that month's number (filed with
  both codes). `series_id` / `video_no` are no longer read.
- The list is a card a content month, newest first, the newest open (the
  user, 2026-10-10: thirty to fifty videos a client a year), a row a
  client's month (the client over its codes and count, the next shoot else
  the last, Published or n of N), opening its record on its first script
  (on the script a search found). A
  script opens in its content month's record (the user, 2026-10-09: one link
  for the client, the videos as tabs on top): the head names the client and
  the month (`n scripts · n published`; the month opens the client's Months
  in My Work where it is there), Preview PDF and one ⋯ of Download and Reset
  client link, then the client's link once (`.rec-linktools`: the address,
  Copy link, Preview), the key read once a client and made at Work the first
  time; under it the month (`month=` in the address; the user, 2026-10-10:
  thirty to fifty scripts a client a year) is a card of its scripts
  (`#vsMonthList`: Scripts with Add script in its head, a row a script, its
  whole code (2611VS01, as its head reads) and title over its type, the shoot, the state, in number order), a
  row opening its script on a page of its own (`script=`): Previous, `n of
  N` and Next over it (`#vsNav`, a sideways swipe on a phone), Back
  returning to the month and the month's Back to the list; the script's
  card headed by its
  code and title over its type with the state, Edit (the pen), Publish in
  blue or Unpublish (asks) and a ⋯ of Delete at the right edge
  (`.vs-cardhead`), its facts under it (`.vs-factcard`, the reference video
  with them), and the script in the next card (the user, 2026-10-09: key
  information apart from the scenes). A script deleted opens its month,
  the last one gone the list.
- On the day, in the console and the installed app alone (the user,
  2026-10-09: "make it simple to enter"): each scene's VC# (the clip number
  on the camera) is one field; Enter records it, ticks the scene shot and
  moves to the next scene's field, and an empty field offers the number
  after the last one recorded (C0042, then C0043), which Enter takes; a
  Shot tick is its own press; each saves as it changes and is put back on a
  refusal (`video_script_shot`).
- Edit is a page of its own (`#vsEditView`, `edit=1` in the address; the
  user, 2026-10-09: a sheet shut by a stray press would lose a long
  script): the head, the facts card (Video, Shoot), the script card, and
  Save / Cancel at the foot of the screen (`.vs-editfoot`, sticky above the
  tab bar). Cancel with changes asks (Discard changes?); with changes held,
  Back, the rail and a return to the section bring the editor back as it was
  ("Save or cancel the changes first."), and closing the tab asks
  (`beforeunload`). Saved by `video_script_save` (from and to, `stale` with
  the row).
- The shot table (`2026-11-05-script-shot-table.sql`; the user, 2026-11-05:
  the Video Script Generator spec, "Full shot table"): each scene keeps its
  time (`t_from`, `t_to`, seconds, the end after the start), Shot size,
  Angle, Camera move, On-screen text and Sound, read as one mute line over
  what is seen; a script keeps its Aspect ratio and Video length, its Brief
  (`brief`: offer, objective, audience, key message, call to action, must
  include, must avoid, tone, format, and the Location, Cast and Hour limits,
  the script's own, never a setting: the crew's limits vary a project), its
  Plan (`plan`: core message, hook, concept, call to action in the video,
  cast roles, locations, props, music mood) and its AI review (`review`,
  `review_version`, kept as Save keeps it). Add script copies the aspect,
  length and brief. The client link reads the plan and the shot fields,
  never the brief or the review. One press writes one script (one script is
  one video); a second variant is Add script and Write with AI again.
- Scene pictures (`2026-11-05-scene-pictures.sql`, its SQL Editor part,
  `2026-11-06-scene-frames-by-claude.sql`, `script-pictures`,
  `js/frames.js`; the user, 2026-11-05: all three, the team's alone, 30 a
  day; 2026-11-06: Claude's frames in place of Gemini's): each scene in the
  console and the crew PDF shows its best picture, the colleague's photo
  (Add photo, the camera on a phone; Remove with Undo), else the frame
  Draw with AI drew, else a picture Gemini drew before, else the frame
  `ADspaceFrames.svg` draws from its shot size, angle and move; the client
  link shows none. A photo is stored in the client's folder through
  `sign-upload` (`purpose` script) and kept by `video_script_picture` with a
  360px JPEG data URL (`photo_thumb`): the CDN serves no read across
  origins, so the PDF draws the thumbnail. Draw with AI (drawn where
  `script-pictures` answers its ping ready: `ANTHROPIC_API_KEY`,
  `FRAME_MODEL`) asks Claude for each scene's frame by structured output,
  four at a time: the shot it drew, a camera move from a fixed list and
  shapes, each a path of path commands and numbers alone and a tone (ink,
  light, fill, paper); the function keeps it as data through
  `video_script_frame` (`ai_frame`, `bad-frame` for anything else, the
  press its caller's own) and the page builds the drawing
  (`ADspaceFrames.draw`, the path held to the rule again), never markup
  from the model, white in both themes, its move played once. Each frame is
  one `ai_drafts` row (`picture`, `ai_picture_claim`), 30 a person a day by
  default, set on AI usage (Scene pictures), priced by its tokens
  (`ai_price_image` prices a Gemini row alone). Rounds of changes (the
  user, 2026-11-07): Draw with AI asks an optional Changes for every scene
  it draws, and a drawn scene's Redraw asks the Changes for that scene
  (`note`, `notes`, 500 each, masked); a scene already drawn goes with its
  drawing and is revised from it, and a drawing replaced comes back with
  Undo where it happened, written back under the press the function names
  (`presses`). A drawing's edge takes the box's corner (8px less its inset). On a phone the picture stands at the left of its tag, Redraw and Add photo, the scene's words under them; Redraw and Add photo are one width, 12px apart under a finger, and a scene with no picture draws no box, Add photo in its place (2026-11-07).
- The animatic (`js/animatic.js`, `#vsPlaySheet`; the user, 2026-11-06:
  short clips, "1 yes"): Play on the Scenes heading, for anyone who reads
  the script, plays its scenes in order on one canvas at the script's
  ratio, each for its own from and to (else the video's length shared out,
  else 3 seconds; 1.5 to 12), its best picture (a photo's thumbnail, a
  drawn frame) moved as its camera moves, its number and its on-screen
  text; Download records the same in the browser (MediaRecorder: MP4, else
  WebM; in real time, the tab kept open), nothing stored, no service asked.
  An SVG made a file (`svgFile`) gains `xmlns` only where it has none: a
  second one is a repeated attribute and the picture loads as nothing
  (2026-11-07: Play drew a blank frame, the crew PDF dropped it).
- Copy prompts (`#vsPrompts` on the Scenes heading, `#vsPromptSheet`; the
  user, 2026-11-09, option A of the team's AI short drama guide): anyone who
  reads the script copies its scenes as prompts for an AI video model the
  team runs outside the portal, one a segment (scenes in order, 15 seconds
  and four scenes at most, timed as Play times them), each References,
  Voices, Positions (left in brackets to fill), Picture by the second (shot
  size, angle, move, what is seen), Sound (the lines word for word, the
  sound) and Avoid, after one Whole video block (ratio, length, language,
  the plan, the context or voice-over); English or 中文 (a segment), Copy a
  block or Copy all. Built on the page: nothing is sent and no AI use is
  counted. No video service is connected (option B, held: client material
  to a China-based service is the user's decision).
- Write with AI (2026-10-09, `script-draft`, `2026-10-09-script-writer.sql`):
  on the editor's Script heading (`.readgroup-head`), at Video Scripts Work.
  It asks first (`ADspaceConfirm`: Video length 15s, 30s, 60s or 120s; XHS
  Safe Mode on a rednote script alone, unticked; Notes for the script, kept
  in this browser under `adspace-script-notes:{id}`; n scripts left today;
  Replaces the script in these fields where it holds words), then sends the
  type, title, platform, language, length, venue, how many in the cast (never
  their names), the notes and the script so far; the function reads the
  script, the client (industry, market) and the month's other titles as the
  caller, masks the client's name `{brand}` and handles `{handle}`, claims
  `ai_script_claim` before Claude (`script` 10 a person, a day from
  midnight MYT, a setting in `ai_draft_limits`;
  `ai_script_left`), and answers the type's fields by structured output
  (secrets `ANTHROPIC_API_KEY`, `SCRIPT_MODEL`, unset `claude-opus-5-5`;
  Verify JWT off). The words fill the fields in place, `{brand}` and
  `{handle}` filled on the page; Undo where it happened (Written by AI.
  Read before saving.); Save asks the declaration first (as Write caption,
  2026-10-10) and files `script.saved` Script written with AI, read and
  confirmed; an answer landing after the editor shut is put in at its next
  open. The house
  style and XHS Safe Mode's rules are the function's `SYSTEM` and `SAFE`.
  Every script is an interactive video made as local reels are (the user,
  2026-11-07): it speaks to the viewer, gives one prompt to comment, vote,
  guess, tag or save, opens a loop it closes, changes every 2 to 3 seconds
  and reads with the sound off, in a local creator's format (POV, street
  interview, taste test, A or B, a local skit) and local speech, handheld
  and phone-first; the reviewer checks the same (`INTERACTIVE`, `REELS AS
  THEY ARE MADE HERE`, review 5a).
- Publish (`video_script_share`, Undo where it happened; not drawn on a
  script with no scenes) shows a script on the
  client link, `/script/?k=` on the client's own key (`clients.script_key`,
  `script_link`; Reset link asks and retires the old key). The link is
  for the client to read the scripts (the user, 2026-10-09: "no need show the
  approve or changes at client side"; "remove from all client-facing
  site"): the name card, a tab a content month (drawn where there are two),
  then the month as a list, a row a script (code and title over its type,
  the shoot at the right); a row opens its script alone (All scripts, n of
  N, Previous and Next, a sideways swipe on a phone; `#id` in the address,
  Back returning to the list), its facts card and its script card. A month
  of one script opens it. It reads only `get_scripts` (shared scripts by
  month and their scenes; never a clip number, a tick, who ticked, a
  colleague's name or a version; `2026-10-09-script-shots-internal.sql`).
  Nobody decides or records there.
- The PDF (`ADspaceScriptPdf.draw`, drawn in the browser, never stored)
  carries the Reports PDF's furniture and scale (the user, 2026-10-09:
  "refer back to the Reports style"): the Optima wordmark in ink at the head
  of every page and the client in small capitals at its right, PRIVATE &
  CONFIDENTIAL in Slate Medium on the margin's line with the page count, the
  S(5) margin and S(k) type, white cells under a #f2f2f2 title row. Its
  content is the user's template: Video Script over its month (its type, or
  the count of scripts), the header table (Video # reads the codes,
  Platform, Client/Brand, Language, Shooting Date & Time, Venue, Est.
  Shooting Duration, Cast Members/Talent), each script under its code and
  title (its type and reference under it) by kind, every scene numbered
  with a Shot box and a VC# cell (a tick and a clip number recorded in the
  console printed, empty ones left for the pen; the context box has
  neither), the words said in Slate Regular and what is seen in Slate Book,
  and its own Notes / Remarks with room to write (2026-10-10: the crew reads
  one sheet a shoot day). Scripts of a month sharing their header share one
  header table, whatever their kind; Preview PDF (a tab
  opened at the press) and Download from the month draw the whole month;
  on a script's own page they ask This script or Whole month once there
  are two.
- Delete is Full Access, the title typed back (else the code).
