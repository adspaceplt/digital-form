# Client-Facing CRM Portal Engineering and Design Standard

This file is the standing instruction set for all work on this project. Follow it before planning, coding, reviewing, or declaring a task complete.

> **How this sits with the other two files.** `CLAUDE.md` and `DESIGN.md` record what this portal has already decided and why, usually because something was got wrong once. This file is the general standard. Section 2 settles any conflict: documented product behaviour (priority 3) beats this standard (priority 4). Where the two genuinely differ, the difference is recorded in Project Memory at the foot of this file rather than left for somebody to trip over.

## 1. Mission

Build a reliable, polished, client-facing CRM portal that feels intentionally designed and remains correct after every change.

The product must satisfy both tracks below:

1. Functional quality: workflows, permissions, data, validation, states, integrations, and recovery behavior are correct.
2. Experience quality: hierarchy, spacing, typography, composition, responsiveness, accessibility, and visual consistency are correct.

A task is incomplete if either track fails. "Mostly done", "works on my screen", and "the happy path works" are not acceptable completion criteria.

## 2. Instruction Priority

When instructions conflict, use this order:

1. Security, privacy, authorization, and data integrity
2. Explicit user requirements and acceptance criteria
3. Existing product behavior that is intentionally documented
4. This project standard
5. Local implementation convenience

Never weaken security, permissions, data correctness, or accessibility to obtain a cleaner visual result.

## 3. Required Working Method

For every non-trivial task, use this loop:

1. Inspect the current implementation before editing.
2. Restate the requested outcome and identify affected workflows, pages, roles, data, and components.
3. Identify ambiguity, edge cases, risks, and likely regressions.
4. Define concise acceptance criteria for behavior and appearance.
5. Make the smallest coherent change that solves the root cause.
6. Test the changed path and nearby dependent paths.
7. Inspect the rendered interface at required viewport sizes.
8. Fix all issues introduced or exposed within the agreed scope.
9. Re-run validation after the final edit.
10. Report what changed, what was verified, and any genuine remaining limitation.

Do not repeatedly redesign or rewrite stable areas while completing a narrow task. Preserve working behavior unless a change is required by the request or necessary to fix a verified defect.

## 4. Plan Before Editing

Before implementation, write a short internal plan containing:

- User goal
- Primary workflow
- Affected roles and permissions
- Affected pages, components, services, and data entities
- Existing behavior that must remain unchanged
- Acceptance criteria
- Edge cases and failure cases
- Test and visual verification plan

If the request is ambiguous in a way that materially changes product behavior, ask a focused question. Otherwise, state a reasonable assumption and proceed.

Do not use broad phrases such as "improve the UI" as acceptance criteria. Convert them into observable outcomes, such as consistent card padding, no clipped text at the narrowest supported width, visible keyboard focus, and a successful retry after a simulated request failure.

## 5. Source of Truth and Product Memory

Treat the repository, schema, migrations, tests, design tokens, component library, and documented product decisions as the source of truth.

Maintain the `Project Memory` section at the end of this file when a durable fact changes. Record only facts that will help future work, including:

- Approved product decisions
- Stable design tokens and component conventions
- Important workflow rules and invariants
- Role and permission rules
- Known integration constraints
- Verified test commands and viewport matrix
- Accepted technical debt and known issues

Do not store secrets, credentials, access tokens, personal data, temporary debugging notes, guesses, or stale implementation details.

Before adding a memory item:

1. Verify it from the current code, documentation, or an explicit user decision.
2. Check that an existing memory item does not already cover it.
3. Update or replace a stale item instead of appending a contradiction.
4. Include the date and the reason the fact matters.

## 6. CRM Workflow Correctness

Model important workflows explicitly as states and allowed transitions. Do not scatter workflow meaning across unrelated UI conditionals.

For each workflow, define:

- Starting state
- Allowed actions
- Required inputs
- Validation rules
- Role or permission requirements
- Success state
- Failure state
- Retry behavior
- Cancellation behavior
- Duplicate-submission behavior
- Audit event
- Notification side effects
- Re-entry behavior after refresh or navigation

Examples include lead qualification, opportunity stages, task assignment, approval, invoice status, client onboarding, document collection, ticket escalation, and record archiving.

- **2026-09-16** — Two acts over a letter, Void and Delete, both re-checked server-side on every call through `allowed()`; no parallel permission system and no hard-coded role check. **Superseded on 2026-09-22 for the authority**: both are the Clients section's Manage level. `can_doc_void` was a separate switch and the user asked for it folded in, because the person trusted to delete a client's letter is the person trusted to void one, and two switches for one level of trust left groups with Manage on Clients and no void. The columns stay, unread; `supabase/migrations/2026-09-22-void-is-clients-manage.sql` redefines the two functions.

### Workflow invariants

- The server enforces authorization. Hiding a button is not access control.
- State transitions are validated on the server.
- Important writes are transactional where partial completion would corrupt data.
- Retried requests do not create duplicate records or repeated side effects.
- Destructive actions require explicit confirmation and communicate consequences.
- Long-running actions expose progress and do not invite repeated submission.
- Dates, time zones, currencies, locale formats, and rounding rules are explicit.
- Changes to sensitive or business-critical records are auditable.
- A failed action never displays a false success state.
- Refreshing the page does not lose a successfully persisted change.

## 7. Required Interface States

Every data-driven view and action must deliberately handle relevant states:

- Initial loading
- Background refresh
- Empty result
- Filtered empty result
- Partial data
- Success
- Validation error
- Permission denied
- Network or server failure
- Timeout
- Retry
- Offline or disconnected behavior, if applicable
- Disabled or unavailable action
- Unsaved changes
- Concurrent update or stale data
- Deleted, archived, or missing record

Do not leave raw exceptions, undefined labels, blank panels, infinite spinners, layout jumps, or silent failures in the client-facing interface.

Error messages must explain what happened, preserve the user's work when possible, and offer a useful next action. Do not expose stack traces, internal identifiers, database details, or sensitive information.

## 8. Design System First

Use shared tokens and reusable components. Do not introduce arbitrary one-off values when an appropriate token or established component exists.

At minimum, define and use tokens for:

- Color roles
- Typography roles
- Spacing
- Container widths
- Breakpoints
- Border radii
- Borders
- Elevation
- Motion
- Focus rings
- Layering and z-index

Prefer semantic names such as `surface`, `text-muted`, `border-subtle`, `danger`, and `focus-ring` rather than names tied to a specific color.

### Suggested spacing scale

Use a restrained base scale for local spacing:

- 4 px: icon or micro adjustment
- 8 px: tightly related items
- 12 px: compact control grouping
- 16 px: standard internal gap
- 24 px: card padding or related section separation
- 32 px: strong component separation
- 40 px: compact section rhythm
- 64 px: standard section rhythm
- 104 px: large editorial or landing-page separation

Use spacing to communicate relationships. Related items sit closer together than unrelated items. Avoid random values unless optical correction clearly requires one.

### Typography

- Use a limited type scale with named roles.
- Maintain a clear difference between page title, section title, card title, body, label, caption, and metadata.
- Keep body text readable, usually 16 px or larger for primary reading content.
- Use comfortable line height, usually 1.4 to 1.6 for body copy.
- Avoid very long line lengths. Aim for roughly 45 to 75 characters for reading-heavy content.
- Do not use font weight alone to communicate state or importance.
- Prevent clipped labels, orphaned headings, and awkward wrapping at narrow widths.

### Color and contrast

- Use color by semantic role, not decoration alone.
- Meet WCAG AA contrast for text and meaningful controls.
- Never rely on color alone to communicate status, error, or selection.
- Reserve saturated accent colors for meaningful actions and state.
- Use neutral surfaces and borders to create structure before adding shadows.

### Shape, borders, and elevation

- Use a small, consistent radius scale.
- Use shadows sparingly and consistently.
- Do not make every section a floating rounded card.
- Establish hierarchy with spacing, alignment, typography, and surface contrast before decorative effects.

## 9. Golden Ratio and Proportional Composition

Use the golden ratio as a compositional guide, not a rigid law.

Recommended applications:

- Primary and secondary page columns near 61.8% and 38.2%
- Hero copy and supporting visual proportions near `1.618fr 1fr`
- Main work area and contextual sidebar near `minmax(0, 1.618fr) minmax(280px, 1fr)`
- Large section rhythm using Fibonacci-like steps such as 16, 24, 40, 64, and 104 px
- Deliberate placement of a dominant focal element and a supporting element

Do not force golden-ratio math onto:

- Small controls
- Dense tables
- Form field heights
- Touch targets
- Mobile layouts that need one-column stacking
- Situations where accessibility or content legibility requires another proportion

For dashboards, prioritize task efficiency. Dense operational information may use balanced grids, while summary or executive views can use stronger proportional hierarchy.

## 10. Design Principles to Apply

Use these principles deliberately and explain the relevant ones when making significant design decisions:

- Visual hierarchy: the next important action or information is obvious.
- Proximity: related content is grouped together.
- Similarity: visually similar items behave similarly.
- Alignment: elements share clear visual axes.
- Repetition: tokens and components create consistency.
- Contrast: emphasis is meaningful, not everywhere.
- Common region: boundaries clarify groups without excessive boxes.
- Progressive disclosure: advanced or secondary controls appear when needed.
- Recognition over recall: users should not need to remember hidden rules.
- Jakob's law: follow familiar CRM and web interaction patterns unless there is a strong reason not to.
- Hick's law: reduce unnecessary choices at each decision point.
- Fitts's law: primary targets are comfortably sized and easy to reach.
- Error prevention: constrain invalid choices before relying on error messages.
- Content-first design: real content and realistic extremes shape the layout.

## 11. CRM Layout Guidance

### Navigation

- Keep information architecture stable and predictable.
- Clearly indicate the current location.
- Separate global navigation, workspace navigation, and record-level actions.
- Avoid hiding frequent desktop actions behind unnecessary menus.
- On mobile, prioritize the main task and collapse secondary navigation safely.

### Dashboards

- Start with decisions and actions, not decorative metrics.
- Give one area clear primary emphasis.
- Use consistent time ranges, units, and comparison logic.
- Label charts directly where possible.
- Provide empty, loading, error, and no-permission states.
- Do not use a chart when a number or compact table communicates the answer faster.

### Tables and lists

- Keep column alignment and formatting consistent.
- Provide useful sorting, filtering, search, and reset behavior.
- Preserve filter state when appropriate.
- Make row actions discoverable without creating visual clutter.
- Support long values, missing values, and narrow screens.
- Confirm bulk actions and clearly state the number of affected records.
- Use pagination or virtualization deliberately and preserve context after navigation.

### Forms

- Use a logical reading and tab order.
- Keep labels visible. Do not use placeholders as the only label.
- Group related fields and separate distinct tasks.
- Explain formatting constraints before submission.
- Validate at useful times without interrupting normal entry.
- Focus the first invalid field on failed submission and provide a clear error summary when the form is long.
- Preserve entered data after recoverable failures.
- Clearly distinguish save, cancel, delete, and secondary actions.

### Record detail pages

- Present identity, status, ownership, and primary action near the top.
- Separate stable facts from activity history.
- Make status changes explicit and auditable.
- Keep related records and contextual actions accessible without overwhelming the main task.

## 12. Responsive Design

Design from content constraints, not only named devices.

At minimum, inspect these viewport widths unless the project specifies another matrix:

- 320 px
- 375 px
- 768 px
- 1024 px
- 1440 px

Verify:

- No horizontal page overflow
- No clipped, overlapping, or hidden essential content
- Logical one-column stacking when columns no longer fit
- Touch targets are at least 44 by 44 px where practical
- Dialogs fit within the viewport and remain closable
- Tables have an intentional narrow-screen treatment
- Fixed or floating elements do not cover content or actions
- Focused inputs remain visible when the software keyboard appears
- Text remains readable at browser zoom up to 200%

Do not treat desktop shrinkage as mobile design. Reorder, collapse, or simplify based on task priority.

## 13. Accessibility Is a Completion Requirement

- Use semantic HTML and native controls where possible.
- Every interactive element is keyboard accessible.
- Focus order follows visual and task order.
- Focus indicators are clearly visible.
- Inputs have programmatic labels and useful error associations.
- Icons used as controls have accessible names.
- Dialogs trap and restore focus correctly.
- Status updates use appropriate live regions when needed.
- Headings follow a logical hierarchy.
- Reduced-motion preferences are respected.
- Color contrast meets WCAG AA.
- Critical workflows are usable without a pointer.

Automated accessibility checks are useful but do not replace keyboard and screen-reader-minded inspection.

## 14. Motion and Feedback

- Motion must explain change, preserve context, or confirm an action.
- Keep routine interface transitions subtle and short.
- Avoid decorative motion in dense operational workflows.
- Show immediate feedback after user input.
- Use optimistic updates only when rollback and error recovery are clear.
- Prevent repeated submission while a write is pending.
- Respect reduced-motion preferences.

## 15. Engineering Quality and Change Safety

- Understand the existing architecture before adding a new abstraction.
- Fix the root cause instead of layering compensating patches.
- Prefer small, typed, testable functions and clear data boundaries.
- Reuse established components when their behavior fits.
- Do not duplicate business rules in multiple layers without a defined source of truth.
- Validate untrusted input at system boundaries.
- Never trust client-provided roles, record ownership, pricing, or status.
- Avoid global style changes for a local visual problem.
- Avoid high-specificity CSS and unexplained overrides.
- Remove temporary logging, test data, dead code, and debugging UI before completion.
- Do not silently suppress errors to make tests or the interface appear clean.
- Do not replace a stable subsystem merely because a rewrite feels simpler.

When changing a shared component, identify and inspect all important consumers.

## 16. Data, Security, and Privacy

- Apply least privilege to every role.
- Test both allowed and denied actions.
- Separate authentication from authorization.
- Avoid exposing sensitive fields in responses, logs, analytics, or client state.
- Protect against common injection, request forgery, cross-site scripting, insecure direct object references, and unsafe file handling.
- Use secure defaults for sessions, cookies, password flows, and tokens.
- Define data retention, archive, restore, and deletion behavior.
- Use audit logs for security-sensitive and business-critical actions.
- Confirm destructive or irreversible operations.
- Never use real client data in screenshots, fixtures, demos, or logs without explicit authorization.

## 17. Testing Strategy

Use the appropriate combination of:

- Unit tests for business rules, formatting, and pure logic
- Integration tests for database, authorization, APIs, queues, and third-party boundaries
- End-to-end tests for critical user journeys
- Accessibility checks for semantics, contrast, and keyboard flow
- Visual regression checks for stable client-facing screens
- Manual exploratory checks for edge cases and visual quality

Critical end-to-end journeys should include, when relevant:

- Sign in, sign out, session expiry, and recovery
- Role-based access and denied actions
- Create, read, update, archive, restore, and delete
- Search, filter, sort, pagination, and empty results
- Assignment, approval, and workflow transitions
- Duplicate submission and retry
- Network failure and recovery
- Unsaved changes and navigation
- Concurrent edits or stale records
- Notification and audit-log side effects

Never change a test merely to make a failure disappear unless the required behavior has intentionally changed. Explain why the old expectation is no longer correct.

## 18. Visual QA Protocol

Code inspection alone is not visual verification.

For every meaningful interface change:

1. Render the affected screens with representative, empty, loading, error, long-content, and permission-restricted data.
2. Capture or inspect the required viewport matrix.
3. Compare alignment, spacing, typography, wrapping, contrast, component states, and responsive behavior.
4. Check nearby pages that share changed components or tokens.
5. Fix visible defects.
6. Repeat the render after the final code change.

Inspect specifically for common "AI-generated UI" symptoms:

- Too many rounded cards
- Excessive gradients, glow, glass effects, or shadows
- Repeated identical layouts without information priority
- Large empty areas beside dense content
- Arbitrary spacing and inconsistent alignment
- Too many accent colors
- Oversized headings in operational screens
- Generic marketing copy inside working product flows
- Decorative charts or metrics without a decision purpose
- Inconsistent icon styles or control shapes
- Placeholder content that hides real layout constraints

If rendered inspection is unavailable, say so explicitly. Perform all available structural and automated checks, but do not claim that visual quality was verified.

## 19. Regression Control

Before editing, establish a baseline for affected behavior and screens.

After editing, verify:

- The requested change works
- Existing critical paths still work
- Shared components did not change unexpectedly
- Permissions still deny unauthorized access
- No new console errors, failed requests, or runtime warnings appear
- No unexpected layout shift or horizontal overflow appears
- Build, type, lint, and relevant tests pass
- The final diff contains no unrelated cleanup or accidental generated files

When a new issue appears near completion, stop feature expansion. Classify it as:

- Introduced by this change
- Previously existing but exposed by this change
- Unrelated existing issue

Fix the first category before completion. Fix the second when it blocks the requested outcome or is safely within scope. Record the third clearly without pretending it was resolved.

## 20. Completion Gate

Do not say "done", "complete", "fixed", or "production-ready" until all applicable checks below pass.

### Functional gate

- Acceptance criteria are satisfied
- Happy path passes
- Relevant error and edge paths pass
- Permissions pass for allowed and denied roles
- Data persists and reloads correctly
- Duplicate actions and retries behave safely
- Integrations and side effects are verified or explicitly mocked

### Visual gate

- Rendered interface was inspected after the final edit
- Required viewport widths pass
- Loading, empty, error, success, disabled, and long-content states pass
- No overlap, clipping, overflow, broken wrapping, or unexplained layout shift
- Spacing, typography, color, icons, borders, and radii are consistent
- Primary action and information hierarchy are obvious
- The result looks intentional, not template-generated

### Technical gate

- Build passes
- Type checks pass
- Lint passes
- Relevant automated tests pass
- No new console errors or failed network requests
- No secrets, debug code, temporary fixtures, or unrelated changes remain
- Database changes include safe migration and rollback considerations

### Accessibility gate

- Keyboard-only path passes
- Visible focus passes
- Labels and error associations pass
- Contrast passes
- Dialog focus behavior passes
- Reduced-motion behavior passes when motion is present

If a check cannot be run, report exactly which check was not run, why, and the resulting risk. Do not convert "not tested" into "passed".

## 21. Definition of a High-Quality Final Report

At the end of a task, report:

1. Outcome
2. Main changes
3. Workflows and roles verified
4. Viewports and visual states inspected
5. Automated checks run and their results
6. Any unverified area or remaining risk

Use precise language. Example:

> Implemented opportunity-stage validation for Sales Manager and Sales Rep roles. Verified create, permitted transition, denied transition, retry, and refresh persistence. Inspected the opportunity board at 320, 768, and 1440 px in populated, empty, and request-error states. Build, type checks, targeted tests, keyboard flow, and console checks passed. Email delivery was mocked, so live provider delivery remains unverified.

## 22. Rules Against Superficial Completion

- Do not stop after the first successful render.
- Do not validate only the screen that was directly edited.
- Do not assume a responsive layout works because CSS contains media queries.
- Do not assume a workflow works because the button triggers a request.
- Do not hide an error instead of resolving or clearly handling it.
- Do not create broad redesign churn late in a task.
- Do not polish only the happy path.
- Do not mark known introduced defects as future improvements.
- Do not claim visual verification without inspecting the rendered result.
- Do not call a task complete while required checks are failing.

## 23. Recommended Project Artifacts

Maintain these artifacts as the project matures:

- Design tokens and component documentation
- Role and permission matrix
- Workflow state-transition diagrams or tables
- Critical user-journey test list
- Viewport and browser support matrix
- Error-message and status-language conventions
- Architecture decision records
- Database migration and rollback notes
- Known-issues register with severity and ownership
- Release checklist and rollback procedure

## 24. Project Memory

Update this section only with verified, durable facts. Keep entries short and remove stale or contradictory entries.

### Product decisions

- **2026-09-15** — The portal is an internal operations console plus three client-facing pages, not a public product. Sections and their rules are enumerated in `CLAUDE.md`; the design system and the reasoning behind each rule are in `DESIGN.md`. Both are imported by `CLAUDE.md` and take priority 3 under §2 of this file.
- **2026-09-15** — Creators sign in with an eight character code rather than an account or an SMS one time code. Reason: the agency holds phone numbers rather than addresses, SMS costs money on every message, and a freelancer has no password to remember. The code travels in the link and is stored by the browser.
- **2026-09-15** — A creator is shown their own booking only. The client's stage, the campaign's commercial state, the client's amount, other creators, and the team's notes are withheld by the security definer function, never only by the page.
- **2026-09-15 — approved, NOT YET BUILT.** A creator's submission goes to the team before it goes to the client. `creator_submit` currently sets the step straight to `reviewing`, which on the client's page reads "Your approval": the chip asks the client to act the moment the creator uploads, while `campaign_deliverables` is team-only, so there is nothing there for them to open and the buttons only draw when somebody has separately pasted a `draft_url`. A **Submitted** step goes between `pending_draft` and `reviewing`. The client reads Submitted as "Draft in progress", because nothing has reached them. The team then either **releases to the client**, which is what exposes the creator's uploaded file URLs to the client-facing function so the client opens the creator's own files and the Drive folder leaves the loop, or sends it back to the creator as Changes requested with a note — an internal round the client never sees. Decided with the user on 2026-09-15; its own branch and PR, after the upload fix merges.

- **2026-09-16** — The Clients directory is one Client Register: one surface, one header, and the stages as labelled divider rows inside it. Reason: three panels repeated the same five headings three times and made a client's stage something read from which card it sat in rather than from the column that already says it. A group is a heading inside one table wherever two rows in different groups are still the same kind of thing.
- **2026-09-16** — The client record's Overview is a summary composed only from what the record has already loaded (contacts, the billing ring, service lines, touches, documents). No second read, no stored number, no invented metric. Reason: the pane somebody lands on had less on it than any other, and a metric nobody stores is a metric that goes stale silently.

- **2026-09-16** — The client record opens on an identity area (mark, name, state, and the facts that identify rather than describe) and its Overview is the record itself: flat titled sections over the contacts, services, letters and calls the record has already read. The rail is one block per question and a block leaves when its data does not exist. Reason: the pane somebody lands on had less on it than any other, and a rail of headings over "Not set" is a rail nobody reads.
- **2026-09-16** — Billing and Brand are already dedicated panes, so their forms are not hidden inside a second disclosure card. Imported clients may correct **Client since** from Key dates; the time in the current stage is the stage clock, stated once in the rail's Account status block and never as a second duration field.
- **2026-09-21** — The record head is two parts: who this is on the left (mark, name with its stage, meta), one ⋯ on the right holding Edit and Delete. Edit is no longer a standing control beside the stage, on the client record or the campaign record. The rail opens on Account status (stage chip plus stage clock), its titles are the pane's 15px section size, the billing gate is red and opens Billing, and date and activity rows carry neutral glyphs. Decided with the user on 2026-09-21 against a reference design; the reference's `Add contact` in the head was not taken, because the Contacts pane already carries that action as its one blue primary and a second copy in the head would be a second primary on every pane.
- **2026-09-22** — The state lives in the record head's right part beside the ⋯ on both records: the campaign's chip and the client's stage select. The left part is the mark, the name and the meta only. On a phone (below 1100) the client rail splits around the panes: Account status, Next action, the billing gate and Profile stay above the tab strip, and Key dates, Details and Recent activity follow the pane (`.rail-after`, `display: contents` on the rail, `order` on the blocks). Recent activity is last by decision: it is an excerpt of the Activity pane, read after the record. The client portal's rail is excluded from the split because its rows key on the rail's own width class.
- **2026-09-22** — A revamp mockup (flat edge-to-edge registers for Services and Team) was reviewed against the documented rules. Taken: one Price heading over the amount and the unit on the rate card, counts on its category bands, a neutral `You` chip on the member's own row. Declined, each by a rule already recorded here: a page title with a blurb (explanatory copy; the bar names the route), a Status column with a dot and Active on every row (the accent marks the exception), the group as a column on every member (headings, decided 2026-09-16), and an access summary per member (`Clients + 4 more` hides four of five facts and repeats the group's access per person). The flat register without a bounded panel is a portal-wide decision across every register and the record panes, not a page at a time, and has not been made.
- **2026-09-22** — The Documents Register: one engine (`js/documents.js` pen, `js/letters.js` letters) for the quotation cover, the client letters and the HR letters, one table (`documents`) holding the snapshot, the file redrawn on Download and never stored. The quotation cover stays separate from the Letter of Offer and takes the accounting portal's reference typed; a client letter is `AD/[SA/]{client_code}/{code}`; an HR letter is `ADHR/{staff_code}/{code}{YYMM}`. HR letters are their own section of the access ladder (`hr`) beside `register`. The public `/verify/` page answers an exact reference with the kind, the date and Valid / Void / Replaced, never the recipient, and replaces the Jotform verification form; the root `verify.html` is the user's and is not edited. Decided with the user on 2026-09-22 from the four Word templates and five sample letters. **Storage on S3 with expiring public links, renewable and revocable from the console, is batch 2 and not built.** The ALP checklists are forms, not letters, and are a later batch.
- **2026-09-22** — `css/SlateMedium.TTF` (uploaded by the user) is named by `ADSPACE_ORG.fontMed` and heads the letters; the engine falls back to Slate Regular wherever the file cannot be fetched. The Chinese block of a quotation cover embeds Noto Sans TC from jsDelivr (`ADSPACE_ORG.fontCjk`), because Slate carries no Chinese; a letter with a Chinese block is refused by name when that face cannot be fetched. **2026-09-18**: a CFF based Chinese face is embedded whole, never subset, because pdf-lib 1.17.1 subsets a CID-keyed CFF font with the glyph order wrong and the first live cover printed ASCII glyphs for its Chinese; a cover with a Chinese block is a few megabytes for it until a TrueType face replaces the OTF.
- **2026-09-21** — `--warn` is `#a94d0c` (orange, 5.05:1 on its tint), no longer the brown `#9c5c16`. A blocking condition (the billing gate) is `--err`, not `--warn`: amber is caution, red is refusal or destruction.
- **2026-09-21** — Golden ratio, measured on the client record at 1440 and 1280: pane to rail 1.618 exactly; name 19px to meta 12px 1.58; contact label track 150px of a 652px row (0.23, the short side of a golden cut is 0.38, so labels are deliberately quieter than that); section title 15px to body 13.5px 1.11, which is the console's tight operational scale and is not brought to φ on purpose, per §9 (a φ step from 14px body puts section titles at 22px in a tool read all day). Spacing stays on 4/8/12/16/24/32.
- **2026-09-16** — A campaign schedule is an editable operational view ordered as Upcoming, then Past. It changes dates on the booking but never changes `campaign_options.position`; the client-facing creator sequence remains the sequence originally offered and selected. Time is a native optional time value, not free text.
- **2026-09-16** — A creator submission is due seven calendar days after a shoot by default. `campaign_options.submission_due` remains directly editable for delivery, remote and other no-visit work; the creator sees the date and a due/overdue countdown. Changing a shoot date updates its default deadline without changing the client-facing creator order.
- **2026-09-16** — A released client draft is reviewed in its booking card: portrait video uses a 9:16 inline player with native play, pause and fullscreen controls, and the caption sits with it. The decision sheet contains decisions only and closes with one X, not an X plus Cancel.
- **2026-09-16** — Client and campaign Activity panes use one three-column audit row: timestamp, event with its detail, and actor with a monogram. At narrow component widths the event owns the first line and date plus actor share the second. Activity never inherits the generic service-row phone grid; that collision stacked every cell at the same coordinates.

- **2026-09-16** — A letter's PDF is never stored and there is no signed upload: `client_documents` holds the snapshot and the file is redrawn on Download. A permanent deletion therefore has **no storage side, no object queue and no quarantine** — the row is the letter — and the console says the deletion is immediate and irreversible. Decided with the user on 2026-09-16 after the alternative (building a signed-letter upload first) was weighed and deferred.
- **2026-09-16** — The letter's closing carries the issuer's **name only**; no designation field was added. The guard against an internal role reaching a client's letterhead is therefore a refusal at issue time (`issuer_name_ok`), not a second field. Decided with the user on 2026-09-16.
- **2026-09-16** — Voiding a letter applies to a **verified** letter only and has no restore. An issued or signed letter has confirmed nothing, so there is nothing to reverse; removing one is a deletion. This narrows what the old `letter_set_void` accepted, and is a deliberate capability change rather than a regression.

### Design system

- **2026-09-15** — Tokens live in `css/portal.css` `:root`: colour, `--radius`, `--head-h`, `--ctl-h`, `--ctl-h-sm`, `--state-w`, `--ctl-text`, `--field-text`, `--shadow`, `--shadow-lift`, and the motion set `--t-fast` / `--t` / `--t-slow` / `--ease` / `--ease-out`. The full table and the reasoning are in `DESIGN.md`.
- **2026-09-15** — **Differs from §8 of this file.** The spacing scale is 4, 8, 12, 16, 24, 32 and stops there. 40, 64 and 104 are editorial rhythms for a landing page; this is a dense operations console where a 64px gap between two tables reads as a missing section. `uxaudit` fails a section whose sibling gaps differ.
- **2026-09-16** — **Differs from §8 of this file, in the console only.** Body text is 14px in `/admin/` and **16px on the four client facing pages** (`:root[data-face="client"]` on `/creators/`, `/creator/`, `/review/`, `/client/`). The console is an operations tool read all day at a desk, not reading-heavy content, and §9 allows dense operational screens their own proportions; a client reads one page once, usually on a phone, and is being asked to decide something on it, so that side takes the 16px this standard asks for. Only what inherits moves — controls, labels and chips state their own size — so the component shapes are identical on both sides. The floor is 11px and `uxaudit` fails anything smaller.
- **2026-09-16** — Two corner values and nothing between them: `--radius` 14px for a bounded section, `--radius-sm` 10px for anything a finger operates, `--radius-lg` 18px for a sheet. `--radius-panel` and `--radius-ctl` are aliases. A third pair of tokens beside the first two is what let a table at 10px sit between two panels at 14.
- **2026-09-16** — `js/state.js` is the only copy of how a list says it is loading, has nothing in it, or could not be read. A read that failed is never reported as an empty list. It also holds `initials`, the two characters a record's `.rec-mark` wears when no logo is held, because three pages now draw that mark.
- **2026-09-16** — **Blue is the action colour.** `--action` `#0b57d0` (light) / `#a8c7fa` (dark) with `--on-action`, plus `--action-hover`, `--action-pressed` and `--action-ring`. Blue moves, green reports live state and success, amber cautions, red destroys, everything else is neutral. One prominent blue action per view, two at most; `uxaudit`'s `accent` rule counts `.btn-go`, `.btn-primary` and `.btn-approve` together. Reason: green was carrying the forward button and the live state at once, so a screen could not say "press this" and "this is running" in two voices. `#007aff` was refused at 4.02:1 with white on it.
- **2026-09-16** — Every table states its own grid tracks, on the header and on the row, hung off that table's own row class. A template hung off `.crm-head:not(.svc-row)` claimed Short Links' header and put four of its five columns up to 161px out. State the last track too: an `auto` final column is sized by its own row.
- **2026-09-16** — A rule about something inside the record pane keys on the pane's own width, never the window's: `ADspaceState.fit` sets `is-narrow` (≤640) and `is-tight` (≤460) on `.console-body`, `.rec-pane` and `.rec-rail` from a `ResizeObserver`. Reason: at a 1280px window the pane is 591px, so every `@media (max-width: 640px)` rule inside it was false exactly where it was needed. Container queries are **not** used for this: `container-type: inline-size` implies `contain: layout`, which would become the containing block for the `position: fixed` row ⋯ menus.
- **2026-09-16** — Geometry is asserted, not eyeballed: `node tests/geom.js tests` → `geom: ok`, measuring the populated campaign, services, finance and account-menu states at 1440, 1280, 1024, 768, 390 and 320 — tab rows, collapsed row heights and their spread, status and action column stability, the service name track, account menu width and row direction, finance field widths, control floors, residual ink fills and document overflow. `SHOTS=1 SHOTS_DIR=… node tests/geom.js tests` writes the same states as screenshots.
- **2026-09-20** — On a phone the last column of a list row is a **right edge**: the cell fills its fixed track and aligns its contents right, so every chip, age and price ends at the card's padding. A fixed track alone only stops the column drifting; `justify-self: start` inside it left the right margin ragged on every register. An **empty action cell gives up its track** at the same widths, or a column of prices stops short of an edge nobody can see. Enforced by `uxaudit`'s `edge` rule, which measures the ink rather than the box and exempts a cell that starts at the row's left margin.
- **2026-09-16** — Every hover state lives inside `@media (hover: hover)`. A tap leaves `:hover` on, and `.btn:hover` outranks `.btn-primary`, which is how a filled blue primary came out at 2.72:1 on a touch device.

### Roles and permissions

- **2026-09-15** — One user group per person (`team_roles` → trigger → `team_members` → `allowed(flag)`), never per-person switches. The groups seeded are Admin, Marketing and Sales; Marketing was renamed from Account because "Account" is the word for a login. The slug `account` is what `team_members.role` points at and does not move.
- **2026-09-22** — Two sections joined the ladder: `register` (the Documents Register: quotation covers, client letters, serials added by hand) and `hr` (HR letters). `register_may(family, level)` answers an HR document to `hr` alone, a client document to `register` or `clients`, and a hand-added "other" document to `register`; it is the `documents` read policy and the check inside every write. A group that could open the console before this change has `none` on both until the Team page sets them; an admin has everything.
- **2026-09-16** — Activity navigation is absent when `can_activity` is false. A refused pane is not shown as an empty activity record, and a copied Activity URL falls back to Overview; database policy remains the control.
- **2026-09-15** — `is_team()` gates every team table. A signed-in account is not the team: clients hold logins too. One address is never both a colleague and a client contact (`no_team_client_overlap`), and where a legacy overlap exists the client portal is the side that yields.

### Workflow invariants

- **2026-09-15** — A campaign creator moves Confirmed → Pending visit → Pending draft → Reviewing → Changes requested → Scheduled → Posted → Completed. Each step is gated by its data and every forward move has a Revert. "In production" is derived on every load, never written by the action that caused it.
- **2026-09-15** — A creator may upload only at `pending_draft` or `changes`. Handing in moves the step to `reviewing` and is what the team sees. The payment form (AP01) is named once the work is approved, not when it is handed in, so a reshoot does not put a bill in the ledger against work nobody accepted.
- **2026-09-19** — A client's verdict on a draft is recorded in three places, not one: the `option_reviews` row it always wrote, an `activity_log` row under the reviewer's own name, and the last decision sent back with the booking by `get_campaign` so the client's own card can name who approved it and when. Before this, approving moved the booking to Scheduled and left no trace anybody could read. The name is asked once per browser (`adspace_reviewer`) and is required for both decisions.
- **2026-09-19** — A creator rates the booking, not the agency, and only once it is `completed` (`campaign_options.creator_rating`, 1 to 5, `creator_rate`). Payment details leave the card at the same moment. The rating is never shown to the client.
- **2026-09-20** — A client has one set of platform handles and one logo, on the `handle_*` and `logo_url` columns, edited from the Brand profile and from Content Review's client settings alike. `social_*` was a second store over the same row, so a handle corrected on the record never reached the client's own mockup; it is backfilled by `handle_of()` and no longer written. A handle is stored, and the address to open it is derived per platform.
- **2026-09-20** — Deleting a client is `can_remove`, re-checked by `delete_client`, offered in the record's ⋯ behind a sheet that counts what goes and takes the name typed back. Paused and Past remain the everyday way a client leaves the working list; this is for a record that should not exist. The cascade takes contacts, calls, service lines, letters, requests, content sets and campaigns with it, and there is no restore.
- **2026-09-20** — The Clients register bands are **Leads / Clients / Past clients**. Clients holds active *and* paused (the working book of business); Past clients are ended engagements, shut by default and remembered, keeping their count because they still hold their Client ID and may renew. Leads stay first. A filter opens every band. The Client ID is drawn on the row under the name and is searchable; it remains manual and issued by the accounting system, and is load bearing for the letter serial.
- **2026-09-20** — Blue is spent once per card, not once per creator: a campaign's `advance` button is `.btn-go` only for Release to client, the one step that hands work to somebody else. The other five steps read as ordinary actions and are told apart by the word on them.
- **2026-09-20** — A creator's submitted video plays in the console (`.filecard-video`), so nobody downloads a file to review it before releasing it. Media is 9:16 cards, everything else is an attachment line; one grid of mixed aspect ratios left files orphaned on their own rows.
- **2026-09-20** — `js/ask.js` is the one copy of asking for one value on the page: `rename` (edit the thing where it sits, the opening control becomes Save), `inline` (the field grows out of the control that needs it), `note` (a textarea under the control that sends it). No sheet lives in it, because an act whose consequence must be stated first is a sheet and collapsing it into a growing field hides the consequence. `tests/sets.js` fails on any `window.prompt` or `confirm` opening.
- **2026-09-20** — A client is asked for their name **on the page**, never with `window.prompt`: `js/decide.js` grows the field out of Approve (the `.pbox` pattern) and is the one copy for `/review/` and `/creators/`. A prompt cannot be styled or translated and is a system sheet on a phone. Where the note box is already open it carries the field itself.
- **2026-09-20** — `tests/stub2.js` honours an embedded select's **column list** (`clients(name, market)` yields those columns and no others). It used to hand back the whole row whatever the query asked for, which made it more generous than PostgREST and hid a missing column: the campaign record read `logo_url` off a join that never requested it, so every campaign fell back to initials.
- **2026-09-20** — `hi.adspace.me` is a Cloudflare Worker (`workers/links/`, account ADspace, zone `adspace.me`) and the Short Links list is live. It reads through `link_resolve(p_slug, p_qr)` with the **public anon key**, not with the service role: the function answers one exact slug with one destination and one state, so a redirector never needs a key that can write. Four states, because they are four pages — `ok`, `missing`, `paused`, `revoked`; a pulled QR code is turned away while the typed link keeps working. Redirects are 302 and `no-store`, since the point of a table is that a destination can be corrected. `go.adspace.me` is not served by it and is not retired: printed QR codes encode that whole address.
- **2026-09-20** — An event about a campaign is filed under the campaign's title, never under a creator's name. The campaign Activity pane reads `activity_log` by subject, so per-creator events written under the creator vanished from it; the creator belongs in the detail.
- **2026-09-15** — Reversibility vocabulary: Revert a state, Restore a record, Reinstate a person, Undo a removal, Void then Delete an issued document. A number is never reused.
- **2026-09-15** — A creator uploads up to 300 MB a file (`ADSPACE_CONFIG.s3.maxUploadMB`) and as many files as a booking needs. The file is not uploaded until `creator_add_file` has written the row, so every step's failure is the whole file's failure and is named on the page.

- **2026-09-16** — Voiding or deleting a letter reverts **only the service lines that letter alone was holding confirmed** (`letter_sole_services`). A line another verified, unvoided letter also maps stays confirmed, because that letter still says so. A voided or deleted serial is never reused: the counter only increments, and a deletion leaves a `client_document_deletions` row carrying the serial, the actor, the reason and the service ids, and no document content.

### Technical constraints

- **2026-09-15** — Static site, vanilla ES5-style IIFE scripts, no build step, no framework, no bundler. GitHub Pages at digital.adspace.me. There is therefore no path routing (`404.html` is the user's own site and is never edited); state travels in `?s=`.
- **2026-09-15** — Server-side work runs in Supabase Edge Functions (`sign-upload`, `invite-member`, `portal-login`), deployed by the user with the Supabase CLI. GitHub Pages cannot hold a secret or receive a webhook.
- **2026-09-15** — `supabase/schema.sql` is re-runnable and applied by hand in the SQL editor. A seed is a first run, not a running list: catalogue rows seed only into an empty table, or a deletion made in the console comes back.
- **2026-09-15** — A change confined to one function or column ships as a dated file in `supabase/migrations/`, not as a re-run of the whole schema. The full file carries fifteen top-level data migrations and recreates fifty-six policies, triggers and indexes; all are idempotent, but running them on a live database to replace one function body is exposure with no benefit. A migration file carries its own rollback and is applied standalone, twice, by `tests/sql.js`.
- **2026-09-15** — Two failure modes that hid a production outage for two rounds, both now covered by tests. (1) PL/pgSQL resolves a declared variable against an unqualified column **at run time**, so a function that shadows a column (`declare id uuid` + `where id = p_option`) creates cleanly and fails on every call: declared names never match a column, and lookups are qualified. (2) `promise.then(onOk, onFail)` does not route what `onOk` throws to `onFail`; a check written that way reports nothing. Use `.then(...).catch(...)` wherever a handler can throw.

### Verification commands and environments

- **2026-09-15** — Server: `setsid nohup npx --yes http-server -p 8899 -s . >/dev/null 2>&1 &` from the repo root.
- **2026-09-16** — Screens: `node tests/ovshot.js tests` draws the client record's Overview in the two shapes it has — a populated active client and a lead with almost nothing on it — at 1280 and 390. A section that reads well when it is full is not the one that has to be checked.
- **2026-09-16** — Sweep: `for s in run camp client cprod bar newbadge prod qr regress backup keyin state race chrome crm sgd team portal creator canvas register; do node tests/$s.js tests; done` — every suite `0 FAIL`, no page errors.
- **2026-09-16** — Before and after evidence: `OUT=tests/p2/<tag> node tests/p2shot.js tests` walks every route Phase 2 touches at 1280 and 390 from one set of fixtures, and the console again in dark at 1280. `ONLY=<name,name>` narrows it while iterating. Run it once on the base and once on the final code, so a before and an after are the same screen twice. `canvas` covers the Review Canvas; `register` covers the Clients directory in all five of its states and the client record's Overview summary, at 1280 and 390.
- **2026-09-22** — Register: `node tests/docs.js tests` → `docs: ok`. It issues an HR letter from the Register and a quotation cover and a thank-you letter from the client record with the real pdf-lib, reads each PDF back with pdf.js, drives Add entry, Void and Delete, the HR permission, the Sales view and the public verify page in both languages. The Chinese face is stood in for by a CJK font on the machine, because the CDN the config names is outside the sandbox's network policy. `tests/sql.js` section 20 runs the register functions against Postgres.
- **2026-09-20** — Redirector: `node tests/links.js tests` → `links: ok`. It imports `workers/links/worker.js` as a module with `fetch` stubbed and drives every answer it can give. The sandbox's network policy refuses `hi.adspace.me` exactly as it refuses `digital.adspace.me`, so `curl` from here proves nothing either way and the module is what gets checked.
- **2026-09-15** — SQL: `node tests/sql.js tests` → `sql: ok`, required for any change to `supabase/schema.sql`. It runs the real file against a throwaway Postgres 16.
- **2026-09-15** — Audit: `node tests/uxaudit.js tests` → `uxaudit: ok`. Screenshots: `SHOTS=1 node tests/uxaudit.js tests` into `tests/walk/`.
- **2026-09-16** — Wider matrix: `node tests/matrix.js tests` → `matrix: ok`. One screen from every route at 320, 375, 390, 768, 1024, 1280 and 1440, and again at 200% browser zoom (the viewport halved, not the CSS `zoom` property), plus the keyboard path through the dialogs. It reads `uxaudit`'s own `inPage()` out of that file, so a rule added there is a rule this matrix enforces.
- **2026-09-16** — `tests/stub2.js` can now refuse or delay a read: `window.__failRead = { clients: 'permission denied' }` and `window.__slowRead = { clients: 1500 }`. Every list in the console has a failed and a loading state and neither could be reached before, because the stand-in resolved in a microtask and could never say no.
- **2026-09-16** — The matrix is now both axes. `uxaudit` walks **every** page and state at 1280 and 390 with a coarse pointer, and the console again in dark at both; `tests/matrix.js` takes a representative screen from every route across **320, 375, 390, 768, 1024, 1280 and 1440**, and again at 1280 and 1440 under 200% browser zoom. Browser zoom is the CSS viewport halved, not the `zoom` property: Ctrl + is what a reader presses and it fires the media queries. `matrix.js` reads `uxaudit`'s own `inPage()` out of that file rather than copying it, so the two cannot drift.

- **2026-09-16** — PDF geometry: `node tests/pdfcases.js tests` → `pdfcases: ok` draws the letter against its extremes and asserts, with pdf.js glyph positions, that nothing drawn crosses the margins, that the four AcroForm fields are widgets with valid rectangles, and that the execution block stays on one page. `node tests/pdfshot.js tests <file.pdf>` rasterises a letter so its pages can be read. Both need `npm i pdfjs-dist@3.11.174 --prefix tests/pdfx` and the local server; they print SKIP loudly rather than passing quietly when pdf.js is missing. A text assertion cannot see a clipped line: the Attn line ran off the right edge of a real letter and decoded perfectly.

### Open security findings

- **2026-09-15 — HIGH, not yet fixed.** Row level security on the CRM and campaign tables still reads `to authenticated using (true) with check (true)`: `clients`, `batches`, `posts`, `reviews`, `drive_assets`, `client_contacts`, `client_touches`, `links`, `link_qrs`, `creators`, `creator_profiles`, `campaigns`, `campaign_options`, `campaign_confirmations`, `option_posts`, `option_reviews`. Clients hold real `authenticated` logins now (`/client/`, `portal-login`), and the anon key is public by design, so a signed-in client can reach PostgREST directly and read every other client's record, contacts and content, every creator's fee, and every campaign — and write to several of them. The `is_team()` sweep at the foot of `supabase/schema.sql` tightened `team_members`, `team_roles`, `services`, `activity_log`, `activity_viewers`, the `content` bucket and `campaign_deliverables`, and stopped there. The fix is to reissue those policies as `using (public.is_team()) with check (public.is_team())`; every client-facing path already goes through a security definer function and so is unaffected. It is held back from the release-step PR deliberately: an `is_team()` that answers false would lock the whole team out of Clients, Content Review and Campaigns at once, so it needs its own change and its own live check.

- **2026-09-19** — `tests/prod.js` had been dead from its bulk-logistics section onward: it filled `#bulkTime`, a native `input[type=time]`, with `2pm`, which throws — and a suite that throws prints no `FAIL` line, so a sweep counting `FAIL` lines read it as a pass. Fixed, and with it the suite now covers the whole campaign pipeline again. Same failure mode as `tests/crm.js` on 2026-09-16: read the exit code, never a count of `FAIL` lines.
- **2026-09-19** — `tests/sql.js` builds its own cut-down `campaign_options` and `option_reviews`, so a column or a column name added to `supabase/schema.sql` has to be added to that fixture too or the function under test fails against a table the real database does not have. Its `option_reviews` had `at` where the schema has `created_at`.

### Accepted known issues
- **2026-09-16** — The letterhead is drawn on page 1 and on any page the services table spills onto (`js/documents.js`, the `newPage(); head(); thead();` in the lines loop), but not on a page created by any other overflow — so a two page letter has no letterhead on its acceptance page while a three page one does on its middle page. Exposed by `tests/pdfcases.js`'s multi-page case, pre-existing, cosmetic, and deliberately not changed in the hotfix that found it: making it uniform changes every letter's layout budget. Not yet scheduled.

- **2026-09-16 — closed.** The gap between 640 and 1280 is covered by `tests/matrix.js`, and it was a real gap: the clients row kept five desktop columns between 640 and 760 while its header was already hidden, and `.cmdbar` did not wrap until 640, so a 1440px window at 200% zoom scrolled sideways. Both fixed.
- **2026-09-16** — Keyboard inspection is automated: `uxaudit` tabs every focusable control and fails one that takes focus without a ring, and checks labels, names and contrast; `tests/matrix.js` drives the keyboard through every control that opens a dialog and asserts Enter opens it, the dialog names itself, Escape closes it and focus goes back to the control that opened it. Neither replaces a real screen-reader pass, which has not been done.
