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

- **2026-09-16, reversed 2026-09-22** — The Clients directory was one Client Register with the stages as divider rows inside it. The user sent the divider rows back (the uppercase eyebrow and its spacing) and asked for a card per stage, as the rate card draws Services and Add-ons; the Register follows the same shape, a card per family. Each card carries its own header row and a 15px heading with the count and marks; Past clients stays shut by default.
- **2026-09-16** — The client record's Overview is a summary composed only from what the record has already loaded (contacts, the billing ring, service lines, touches, documents). No second read, no stored number, no invented metric. Reason: the pane somebody lands on had less on it than any other, and a metric nobody stores is a metric that goes stale silently.

- **2026-09-16** — The client record opens on an identity area (mark, name, state, and the facts that identify rather than describe) and its Overview is the record itself: flat titled sections over the contacts, services, letters and calls the record has already read. The rail is one block per question and a block leaves when its data does not exist. Reason: the pane somebody lands on had less on it than any other, and a rail of headings over "Not set" is a rail nobody reads.
- **2026-09-16** — Billing and Brand are already dedicated panes, so their forms are not hidden inside a second disclosure card. Imported clients may correct **Client since** from Key dates; the time in the current stage is the stage clock, stated once in the rail's Account status block and never as a second duration field.
- **2026-09-21** — The record head is two parts: who this is on the left (mark, name with its stage, meta), one ⋯ on the right holding Edit and Delete. Edit is no longer a standing control beside the stage, on the client record or the campaign record. The rail opens on Account status (stage chip plus stage clock), its titles are the pane's 15px section size, the billing gate is red and opens Billing, and date and activity rows carry neutral glyphs. Decided with the user on 2026-09-21 against a reference design; the reference's `Add contact` in the head was not taken, because the Contacts pane already carries that action as its one blue primary and a second copy in the head would be a second primary on every pane.
- **2026-09-22** — The state lives in the record head's right part beside the ⋯ on both records: the campaign's chip and the client's stage select. The left part is the mark, the name and the meta only. On a phone (below 1100) the client rail splits around the panes: Account status, Next action, the billing gate and Profile stay above the tab strip, and Key dates, Details and Recent activity follow the pane (`.rail-after`, `display: contents` on the rail, `order` on the blocks). Recent activity is last by decision: it is an excerpt of the Activity pane, read after the record. The client portal's rail is excluded from the split because its rows key on the rail's own width class.
- **2026-09-22** — A revamp mockup (flat edge-to-edge registers for Services and Team) was reviewed against the documented rules. Taken: one Price heading over the amount and the unit on the rate card, counts on its category bands, a neutral `You` chip on the member's own row. Declined, each by a rule already recorded here: a page title with a blurb (explanatory copy; the bar names the route), a Status column with a dot and Active on every row (the accent marks the exception), the group as a column on every member (headings, decided 2026-09-16), and an access summary per member (`Clients + 4 more` hides four of five facts and repeats the group's access per person). The flat register without a bounded panel is a portal-wide decision across every register and the record panes, not a page at a time, and has not been made.
- **2026-09-22** — Each console route carries a one line purpose under its command bar while the team is new to the portal, on the retiring `?` pattern (three views, then behind the mark). Decided by the user against the no-explanatory-copy rule because the portal is opening to the whole team; it is an instruction, so it retires, and standing facts (the verify page, the redirect host) are `.routenote` lines instead. The Team panel folds each section's parts under its own head, taken from the Bukku permissions screen the user showed; Bukku's level codes and per-state scope ticks were not taken. **Own clients only** (a row scope for Sales under Clients) was raised and is its own batch, not built.
- **2026-09-19** — The operations system's Phase 1 (the data model, the read rules and the server functions) is in `supabase/migrations/2026-09-19-operations-system.sql`, mirrored byte for byte in `supabase/schema.sql`. **Its permissions are the existing access ladder**, not the seven booleans the brief named: `ops` View/Work/Manage for use, create and assign, and `ops.all`, `ops.reports`, `ops.workflows`, `ops.time` for the team queue, reports, templates and another person's hours. **The four parts are granted, never inherited** (`ops_granted()`), because each widens what the section opens rather than narrowing it, and an inherited widening makes the safe configuration the one somebody has to remember. Decided against a parallel boolean system on the ground that two authorisation systems is a data-integrity defect (§2 priority 1), and reported to the user with the mapping.
- **2026-09-19** — Operations writes are security-definer functions only; the `ops_` tables carry a select policy and nothing else, so a browser cannot set a stage, a date, an assignment, a completion or an event. The one direct write is marking your own notification read. `expected_version` refuses a stale write with the current row. Original commitments are written once. Cycle time, stage time and active work are three separate measures and are never summed. Verified by `node tests/ops.js tests` → `ops: ok`.
- **2026-09-19** — My Work is built for about 290 tasks a month (eight contents a week across thirty clients), so: **the read is bounded and open work is not part of the bound** (open work in full however old, finished work from a chosen period, the period select drawn only while finished work can be on the page); **Group by** re-bands the same rows by due date, client, stage or owner, with every card shut off the due axis so the page is headings and counts, the heading carrying the overdue count a shut card would hide; the fold is remembered per axis (`ADspaceGroup.section`'s new `memo`, which separates a card's identity from what its fold is filed under); and **a stage moves from the row** through the same function and gates, which is why the row is no longer a single button — the name cell opens the record instead. Three global corrections went with it: `.rectabs` no longer bleeds past the page gutter on a phone, the step under a tab strip has one owner (the strip, at 12px, as `.tabrow` already did), and the `?` no longer inherits the action's `margin-left: auto`. Decided with the user on 2026-09-19 after they raised the volume; a kanban board was weighed and deferred to phase 3, scoped to in-flight stages, because a board of 290 cards is worse than a table.
- **2026-09-22** — Operations phase 3: My Work has three views of one set of rows (List, Board per workflow with WIP counts against `wip_guidance` and an On hold column, Calendar of final due dates), `view=` in the address; a capacity strip on the board reads this week's sessions against `team_members.capacity_minutes_week`, typed as hours on the Team panel; notifications are written by the database in `ops_log` (phase 3 migration: `ops_notify`, `ops_log` redefined) under one rule (the owner is told about another person's change, the new owner is told they were assigned, nobody is told about their own act, a dedupe key collapses a repeat inside a minute) and read by a bell in the console head. No new table, column, policy or permission. Phase 4 remains the client record's Operations tab, Content Review integration and recurring rules on screen; the report shipped on 2026-09-21 (below).
- **2026-09-21** — The operations report is a **fourth view** in My Work's segment (`view=report`), not a ninth route: the segment already means "the same rows asked a different question", and the rail is two chunks of four. One function, `ops_report(p_from, p_to)` (`supabase/migrations/2026-09-21-operations-report.sql`, mirrored in `supabase/schema.sql`), returns five answers — what is running, what is late, how long each stage takes, whether the work reached client review on time, and the same per person. It adds **no table, column, policy or permission**: every figure is derived from `ops_tasks`, `ops_workflow_stages` and the append-only `ops_task_events`, so there is nothing to backfill. `ops.reports` governs it and is granted, never inherited; the button is hidden where it is not held and `view=report` in the address falls back to the list, because a link somebody was sent must not open a view the database would deny. **Median with a 90th percentile and a count, never a bare figure** — one task stuck in Editing for three months moves a mean enough to say nothing about the ordinary case. **Replanning is counted beside the on-time rate and never folded into it**, or an extension erases the miss it was granted for. By person is the foundation of a KPI and not a KPI: no score, no ranking. Asked for by the user on 2026-09-21 ("a dashboard for admin / manager to see whats running, whats pending, whats on shooting … during performance meeting"). Verified by `node tests/ops.js tests` → `ops: ok` (the arithmetic against real Postgres) and `node tests/work.js tests` → `work: ok` (the view, its controls and the address).
- **2026-09-22** — The task record states each fact once: the number as a token heading the record (no `.rec-mark` disc; `.rec-id-plain`), the dates in the rail only (with `moved from` and `Move a date` there), the owner on the identity line and in the select that changes it (no read-only People row), and the number not repeated under Details. The rail's forward move is a button at its own width, never full width, and the rail does not repeat the head's stage chip. The owner control answers with `Saved.` and puts the select back on a refusal. The Overview is Brief, Video, Progress and Links; the rail gains Recent activity. Sent back by the user on 2026-09-22 ("the serial # is showing ugly", "change owner when saved nothing moved", "buttons no need use blue all the way") against reference designs whose cleanliness, not their layout, was the standard asked for. `tests/stub2.js` refuses any function by name through `window.__refuseRpc`.
- **2026-09-19** — Operations phase 2 is **My Work** (`js/ops.js`, `?s=work`), plus four functions in `supabase/migrations/2026-09-19-operations-phase2.sql` that phase 1's gates needed and had no control for: `ops_add_link`, `ops_set_link_archived`, `ops_set_checklist`, `ops_set_video`. The queue is banded by when the work is owed and drawn by `js/group.js`; the task is the `.rec` workspace with five panes and a rail. **The route's name and its permission key differ on purpose**: My Work on the screen and `?s=work` in the address, `ops` in the ladder, mapped once in `sectionAllowed()`. **Which stage move is "forward" is read from the workflow** (`forwardOf()`: nearest ahead by `position`, skipping the stage groups beside the main line), never from a list in the page: a hand-written preference put Ready in front of Internal review, and "not waiting" then put Revision in front of Client review, because a review stage waits on a reviewer and is still on the main line. **Whose queue you are looking at is a view, not a filter**: Clear the filters leaves the scope alone, and the scope select is offered only where `ops.all` is granted. **The count is read against the view somebody chose**, so the route's own default never prints a fraction. Verified by `node tests/work.js tests` → `work: ok`.
- **2026-09-22** — Every console directory is a card per group drawn by one component (`js/group.js`): Clients by stage, Content Review one card, Campaigns by state, the Creators List by fee band, Short Links Live and Paused, Documents by family, Services a card per category, Team a card per user group. Folds rather than tabs on a long directory, a card holding everything never shut by default, the card animating open and shut in place. The Register is named **Documents** in the nav (address and identifiers unchanged). A global console search is deferred until the lists are in the hundreds; the section search filters in place. Decided with the user on 2026-09-22.
- **2026-09-22** — A portal document is corrected by Reissue (`document_reissue`, Work level): the earlier version is voided as Reissued and kept, the new version keeps the same serial and points back at it (`documents.replaces`), the unique index is over standing documents only, and `serial_taken()` still refuses the serial to anything else. The verify page answers the standing version as Valid and never says reissued; the Register names the replaced version `Reissued`. Decided with the user on 2026-09-22 ("when verify do not show the status as reissue").
- **2026-09-22** — The Documents Register: one engine (`js/documents.js` pen, `js/letters.js` letters) for the quotation cover, the client letters and the HR letters, one table (`documents`) holding the snapshot, the file redrawn on Download and never stored. The quotation cover stays separate from the Letter of Offer and takes the accounting portal's reference typed; a client letter is `AD/[SA/]{client_code}/{code}`; an HR letter is `ADHR/{staff_code}/{code}{YYMM}`. HR letters are their own section of the access ladder (`hr`) beside `register`. The public `/verify/` page answers an exact reference with the kind, the date and Valid / Void / Replaced, never the recipient, and replaces the Jotform verification form; the root `verify.html` moved to `drafts/verify-jotform.html` on 2026-09-18 (excluded from the published site), so `/verify` and `/verify/` reach the new page. Decided with the user on 2026-09-22 from the four Word templates and five sample letters. **Storage on S3 with expiring public links, renewable and revocable from the console, is batch 2 and not built.** The ALP checklists are forms, not letters, and are a later batch.
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

- **2026-09-22** — Three reports of "the owner does not save" on a task were one ambiguous PostgREST embed: `ops_task_assignees` and `ops_work_sessions` each carry two foreign keys to `team_members`, so `team_members(name)` was refused (PGRST201) and every owner in My Work was blank, Mine matched nothing, and the record's select fell back to Nobody after a save that had worked. The foreign key is named in the hint; a refused read of the assignments now fails the list and the record rather than drawing an unowned task; `tests/stub2.js` refuses a bare ambiguous embed (`TWO_WAYS`) and now honours `.order()`, which it had been discarding — so "the last event" was the oldest one and the page and the stand-in agreed on the wrong answer.
- **2026-09-22** — My Work: the stage select is toned by `stage_group` in four families (mute / no paint / warn / green, with blocked red), a move from a row says so under that row, and every forward move has a **Revert** beside it whose target is read off the last stage change in the task's own events. `ops_delete_task` (its own dated migration, mirrored in `supabase/schema.sql` and compared by `tests/ops.js`) is the first removal of a task: **ops** Manage, the number typed back, a reason, no restore, and an `ops.deleted` row in the activity record because the task's own events cascade with it. Complexity is on the new-task sheet; the date sheet's reason categories are the team's own (Client request, Scope change, Internal capacity, Pending assets, Pending confirmation, Incorrect date listed). **Who approves an extension is not decided**: the move is recorded and the owner is notified, and an approval round would be its own change.
- **2026-09-22** — Copy: a destructive control is named **Delete** and never `Delete {noun}`, because the menu it sits in has already named the noun; the consequence is stated in the sheet that asks. `.kmenu-item.is-danger` is red on the item, not only on a bold child inside it.
- **2026-09-22** — The route's purpose line is a panel from the section's name (`.aboutpop`), not a block under the command bar: from inside a record the bar is off the screen, so the control that explains the section did nothing. It opens only when pressed — a panel that opens itself lands on the command bar and on a phone intercepts the press — and while a route is new the title's glyph carries `--action` instead. One sentence a route.
- **2026-09-22** — `.rectabs` is `flex: 0 0 auto`. As a scroll container its automatic minimum size is 0, so inside the Activity sheet's fixed-height flex card the section tabs were squeezed to no height and drew nothing, a regression from the `.acttabs` pill row they replaced.
- **2026-09-22** — The Activity record's access is a part per tab (`activity.clients`, `activity.ops`, `activity.team`, `activity.review`, `activity.campaigns`, `activity.links`, `activity.register`, `activity.services`), so one section's log can be opened to the team while the rest stays gated. The read policy asks `allowed('activity.' || activity_section(action), 'view')`; `activity_section()` restates the tag-to-section map that lives in `js/admin.js`'s `ACTION_LABEL`, because about thirty of its entries do not follow their tag's prefix and it cannot be derived. `tests/sql.js` §21 reads both copies and fails on any difference, and drives the policy for a group with the section, a group with one part and a group with neither against real Postgres. A tag nothing names answers `other`, which has no part, so it falls back to the section and fails open to whoever can read the record rather than hidden from everybody.

- **2026-09-22** — The console draws its own shell while `me()` is in flight (`.console.is-booting`: the rail and the bar present, their contents withheld, the body a skeleton). What stood there was the shared page bar over an empty page, which is the client-facing composition, so a refresh read as somebody else's portal. Withholding what a person may open and withholding the shape of the page are two different things.
- **2026-09-21** — Two dates, two authorities (`supabase/migrations/2026-09-21-draft-date-is-the-teams-own.sql`). The **first draft** date is the team's own milestone, freely adjustable by anybody who may work the task and gated by nothing: `ops_due_decider(p_task, p_kind)` answers null for `first_draft`. This closes the item open since 2026-09-20, where both memory files recorded an intent the shipped function contradicted and `tests/ops.js` asserted the code while flagging the difference. The **final** date keeps the approval round back to the task's creator, confirmed by the user on 2026-09-21 ("if changes needed it requires the approval flow back to the original created owner"). `ops_due_order_ok()` refuses a draft on or after the final date, compared by calendar day, inside `ops_change_due_date` as well as the asking path, because `ops_decide_due_change` reaches the move directly. The page draws two outlined controls, one per date, and the word **Move** is gone from both and from the sheet's title. The stand-in read `p_when` where the page sends `p_value`, so every date move in a test wrote `undefined` and reported success.
- **2026-09-21 — stated, NOT YET BUILT.** The final due date is the day the work is owed **at Client review**, not a square on a calendar. A task whose final date has passed while its stage is still before Client review is a **delay** whatever its stage says, and is flagged to admins and managers. Derived on every read from the stage's position in its own workflow, never stored, so reverting a stage cannot leave a stale flag. Ships with the operations dashboard.
- **2026-09-21** — The file field's inner button is **shaded, never outlined**: it carried the same 1px `--line-ctl` ring as the field around it on the field's own white ground, so one control wore two identical borders. It takes `--line-soft` (not `--sunk`, which is 1.03:1 on white and identifies nothing), its corner is **concentric** with the field's (inner radius = outer radius less the inset, 10 − 5, written as the subtraction so it is not a third corner value), the inset is 5px, and both labels are 13px so they share a baseline. Reported three times; the first two passes measured box heights, found them symmetric and answered the wrong question.
- **2026-09-21 — S3 storage, stated; step 1 is the user's to apply.** `docs/S3-STORAGE.md`. The portal writes to S3 and never removes anything, so orphans (an object no row points at) and abandoned multipart uploads are billable for ever and invisible to the portal. **Step 1, the lifecycle rule, is two halves applied at different times** (corrected 2026-09-21, after the user asked whether it would cost them their Free Tier — it would have). Apply the **housekeeping half now**: abort incomplete uploads at 7 days and `NoncurrentVersionExpiration` at 30. It is worth doing for the leak it stops, not the money it saves — an abandoned 1 GB upload is billable and invisible in the object list, a fifth of the Free Tier's 5 GB. **Hold the storage-class half**: the Free Tier covers S3 **Standard only**, so a transition on a small bucket moves data out of what is free into what is billed and adds a per-request charge, a 30 day IA minimum and a per-GB retrieval fee to save a fraction of a cent per GB per month. Add Standard-IA at 90 and Glacier Instant Retrieval at 365 once the bill shows a storage line worth reducing (past roughly 100 GB, or when the Free Tier's twelve months end). **No expiration action at any size** — cheaper, never deleted. The lesson: a cost optimisation is sized against the actual bill before it is recommended, or it is a recommendation to spend money. **Step 2, delete on remove, is NOT built** and is deliberately not rushed: it is irreversible, and the predicate it needs is not one column (`posts.media` is a jsonb array of `{url, type, poster}`, and a soft-removed deliverable counts as still in use because Undo restores it). **Step 3, the IAM split, is NOT built**: the portal's key should hold `s3:PutObject` on `arn:aws:s3:::myadspace/content/*` and nothing else, gaining `s3:DeleteObject` only when step 2 ships, because a key that cannot delete cannot be made to delete. Rotation is add the second key, redeploy, confirm an upload, then delete the first — never the other order.
- **2026-09-21 — the delay rule, built.** A task past its `current_final_due_at` and still short of a stage whose `stage_group` is `client_review` is **late**, whatever its own stage says; one that reached review met the promise and is not. Derived on every read (`isLate()` in `js/ops.js`, off `reviewFloor()` which reads the workflow's own stages), never stored. The warn paint on the queue row, the board card and the rail's commitment row now means *late* rather than *the date has passed*, because the accent marks the exception; the cell's words still state the days over either way. A **Late** option in the stage filter is the view a manager opens, a filter and not a band because it cuts across every stage. `tests/work.js` proves the distinction against a fixture that is past its date *at* client review, which is the only thing that tells the rule apart from the old one.
- **2026-09-21 — stage time on the task record.** The Time pane leads with **how long the work sat in each stage**, walked out of the `stage_changed` events the record has already read, with a visit count where a stage was entered more than once and the total since creation. Nothing new is recorded for it. The session timer stays below under **Recorded work**, named for what it is; the two are never summed, which is phase 1's rule that cycle time, stage time and active work are three measures. `tests/stub2.js`'s creation event was `created` where the schema writes `task_created`, so the walk would have lost the stage a task started in; the fixture was corrected rather than the page taught two spellings.
- **2026-09-21** — A file field is exempt from the 16px coarse-pointer floor with the readonly ones: pressing it opens the system picker and raises no keyboard, so it cannot zoom the page. Held to the floor its own `no files selected` came out at 16px beside a 12.5px `Choose Files` inside it. `uxaudit`'s `zoom` rule carries the same exemption, which it caught on the first run after the CSS changed. `.sectionhead` is 24px above, on the scale, not 26.
- **2026-09-21** — The client's creator selection page opens on the creators. The detail card (`#engageCard`) folds and is **shut by default**, with the campaign's purpose and brief moved inside it from under the page title, the due date on the fold's head as the summary a shut fold is read for (the creator count where there is no date), and the body animating open on the `grid-template-rows` 0fr/1fr move every other fold in this portal uses. Shut it is 51px against 330. The accepted cost is that the amount fold is now a fold inside a fold, so the figure is two presses deep; that is what the user asked for when they asked for the creators to get the focus. The fold's label is a bare button and clears the control floor with the rate card's negative block margin, which `uxaudit`'s `target` rule caught on the first run. `tests/cprod.js` drives the shut default, the summary, the purpose and brief being inside the card, and the open.
- **2026-09-21** — A card whose last line is a padded control reads bottom heavy: the creators list's row measured 14px of ink above and 20 below inside a 12/12 padding, because `.plink-bare` carries 5px of its own. The cell takes that padding back as a negative bottom margin (`.is-narrow .cr-row > .cr-links`), so the row's own padding is the only space and each link keeps its target; the top half is left alone because the gap above that line is only 4px. Third component to need this device after the ⋯ and the selection tick. Reported by the user on 2026-09-21 as uneven spacing; the `/creators/` selection row (12/13) and the detail card (19/17) measured even and were not changed.
- **2026-09-21** — A `readonly` or `disabled` field is exempt from the 16px coarse-pointer floor, because iOS zooms on the keyboard appearing and neither raises one. The blanket `:root` rule added on 2026-09-20 had beaten `.linkbox .input`'s 12.5px monospace, so the client-facing link on Content Review drew at 16px — reported by the user as "suddenly so huge". `uxaudit`'s `zoom` rule carries the same exemption, so the original defect still cannot come back.
- **2026-09-22** — `/client/` uses the console record's head cell for cell (`.rec-who` + `.rec-ctl`, the console's own two-row phone template keyed on the window because here the head's width is the window's), `ADspaceState.emptyLine` for an empty section, one heading size across the pane and the rail, a sign-in address as text rather than a mailto pill, and 24px steps rather than 20 and 28. A lone reach link in a `.ct-row` keeps its own width, because the equal-widths rule is for three ways of reaching one person and Engagements borrows the row for one Open.
- **2026-09-22** — `tests/portal.js` asserted `SIGN-IN EMAIL` in uppercase and had been red on `main` since the tracked uppercase eyebrow was retired; `innerText` reflects `text-transform`. Fixed in the test, not the page. The sweep's remaining known failure is `tests/geom.js` (12), whose `no ink primary is left over` forbids any ink fill and so contradicts the documented rule that Add, Create and Save are ink; the real finding inside it is two ink fills in one view on the campaign's Creators pane, which is not changed here because it is a visible change to a stable area.

- **2026-09-20** — `get_creator` no longer sends `rate` or `currency`. `campaign_options.rate` is the client's quoted price and carries the markup; the creator's page drew it as "Your fee", so every creator could read what we charge a client and was told it was their payment. Withheld by the function, not the page. `get_campaign` still sends it, because the client is the party quoted. What a creator is paid is claimed on AP01. `tests/creator.js` had asserted the leak (`RM 380` under "their own fee, not the client's amount") and so could never catch it; it now asserts no figure appears and that the function sends neither key, and `tests/sql.js` proves both sides against real Postgres.

- **2026-09-20** — The console rail is two chunks of four, ordered by how often each route is opened: **Work** (My Work, Clients, Content Review, Creator Campaigns) and **Records and setup** (Documents, Short Links, Services, Team). Decided with the user against the serial position effect, which governs the two ends: the first slot is the queue opened on arrival, the last the settings-like route. Clients leaving the first slot supersedes "Clients first" as a *navigation* statement only; the data model is unchanged and every record still hangs off a client. The proposed client-facing / internal axis was weighed and rejected — every console route is internal. The same order drives `SECTIONS`, the Activity record's tabs and `ACT_SECTION`, `PARTS.activity`, and the Team panel's blocks.
- **2026-09-20** — The Documents register reads `client_documents` beside `documents` and bands Letters of Offer as their own family, so one list holds every reference the portal has issued; the verify page answered references the section had never heard of. The two tables stay two tables (a letter of words and a priced snapshot are not one shape) and the register is the view over both. An offer row answers to `clients.documents` and carries Open client record, not Void or Delete, because those turn on which service lines the letter holds.
- **2026-09-20** — `serial_taken()` no longer counts a deletion, and `issue_letter` takes an optional typed reference that spends no sequence number. Asked for by the user after two test letters were issued and deleted and the client's counter stood at 03 for ever. The cost is recorded: the deletion row is the only record that an earlier document held that reference. `supabase/migrations/2026-09-20-one-register-and-a-typed-serial.sql`, mirrored in `supabase/schema.sql`; the nine-argument `issue_letter` is dropped, because PostgREST would otherwise see two candidates for a call that omits `p_serial`.
- **2026-09-20** — A date on a task is moved by whoever created it. `ops_request_due_change` is the one call the page makes and the database decides: the creator moving their own task's date falls through to `ops_change_due_date`, everybody else raises an ask that notifies the creator, and `ops_decide_due_change` is the only path to the moved date, so the original-commitment rule and the `due_changed` event are unchanged. ops Manage may also decide (somebody must, when the creator has left); the person who asked never can; the first draft date was meant not to be gated, because the commitment a client is owed is the final one — but `ops_due_decider()` answers with the creator whatever the kind, so the shipped function sends both through the round. `tests/ops.js` (2026-09-20) asserts the shipped behaviour and the discrepancy is flagged rather than decided: changing it alters an approval flow the user designed. `supabase/migrations/2026-09-20-extension-approval.sql`, mirrored in `supabase/schema.sql` and compared by `tests/ops.js`. Asked for by the user on 2026-09-20 with the flow stated (A creates and assigns to B; B's change goes to A).
- **2026-09-20** — Release to client opens a **nine**-check quality sheet in three groups of three, all required, with the count saying how far it has got; `campaign.qc` records who checked and when. The user gave eight checks and asked for the essentials to be added; every risk that costs money or takes a post down is covered (safe area, duration, ad label, music licensing, prices and terms, competitors in shot). **It shipped at fourteen and was sent back the same day**: the rows overran the card, the sheet's foot — with Release in it — went off the bottom of a phone screen so the gate could be completed and not passed, and closing the sheet discarded every tick. The list scrolls inside `.sheet-body` with the foot fixed under it, the ticks are kept per booking (`qcKept`) until the release goes through, and checks of the same kind were merged because a person watching a video for spelling is watching it for brand names in the same pass. Confirm creators moved to the Client selection pane in the same batch, off the standing row above the tab strip where it was drawn over three panes it does not act on.
- **2026-09-20** — `js/confirm.js` is the one copy of a question with a consequence, and the console's thirty-one `window.confirm` / `window.prompt` sites are gone. It is the portal's own `.sheet` (440px `.askcard`), Escape and the scrim cancel, focus is trapped and handed back, a destructive question opens on Cancel, the go button takes its tone from the act, `cancel: false` reports a refusal rather than asking, and `field` / `fields` take a value — or two that belong together — in the same breath as the question, so a decision is never taken in one dialog and qualified in the next. The way back (reinstate, set active, restore) asks nothing. `#askGo` / `#askCancel` are stable ids and `tests/prod.js` keeps a dialog listener as a tripwire, so a browser dialog put back is an error rather than a hang. This completes the rule client-facing pages already followed (`js/decide.js`, `js/ask.js`).
- **2026-09-20** — The automatic Letter of Offer serial is the **lowest free slot** in the client and month, not the counter's value (`supabase/migrations/2026-09-20-the-serial-fills-the-gap.sql`). `serial_taken()` stopped counting deletions earlier the same day, but only a typed reference could reuse a freed one, so the client stuck at 03 stayed stuck. The counter is kept because its upsert's row lock is what stops two issuers reading one gap as free; it is the bound on the scan. Typed references, `serial_taken()` and letters already issued are all unchanged. The cost is stated: the counter no longer counts letters, and the scan is capped (`no-serial`) rather than unbounded.
- **2026-09-20** — The console bar's account control has no outline (`.acct-btn`). It was the last outlined thing in a bar whose other two controls carry only ink and a hover fill, so a person's own name read as the bar's one action — the same fault the bell's ring had. Asked for by the user against a phone screenshot.
- **2026-09-20** — A cut with no end marker takes everything appended afterwards, and the activity-by-section comparison in `tests/sql.js` was one: appending the extension section to `supabase/schema.sql` would have silently broken it. Both that cut and the check beside it now end at the next banner, and `tests/ops.js` compares the new section against its own migration. This is the third time this hazard has been hit; every open cut in both suites is now bounded.
- **2026-09-20** — Taking a creator's handed-in file off is two presses: the × arms the file and the confirm takes its place, naming what it costs, with the soft remove and the Undo still behind it. This supersedes the 2026-09-16 decision that there was "deliberately no confirm" on that control: the Undo covers a press somebody noticed, and the user reported the case it cannot cover — an accidental click on a control inside the card whose video they were watching, after which the creator must upload the work again.

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
- **2026-09-22** — The route's purpose line is opened by the section's name in the console head (`.console-title`, a button with a 14px info glyph, `aria-expanded`), not by a `?` in the command bar: the line is about the section, not about the list. Below 400 the glyph gives way and the name never does. `.cmdbar-help` is retired. Asked for by the user on 2026-09-22.
- **2026-09-22** — On a phone (below 640) every console command bar is one row: a search mark that grows into the field on the `.namebox` move, a Filters mark with a badge, then the count and the primary action as a filled `+`; My Work adds its view segment as a second row. The selects, the count and the `?` come up in a sheet from the floor (`js/cmdbar.js`, the bar's own elements moved in and back, never copied), a second action goes behind a ⋯ beside the primary. Reason: the three-row bar below was still 430px of controls before the first record, which the user sent back as bad UX on 2026-09-22 and approved this shape for. The desk bar is unchanged. Verified by `node tests/cmdbar.js tests` → `cmdbar: ok`, the walk's `admin my work filters` and `admin register more` states, and the matrix's keyboard pass through the sheet.
- **2026-09-22** — The command bar's tail is stated in the markup, not left to a wrap: `.cmdbar-end` > `.cmdbar-quiet` (the count and the `?`) + `.cmdbar-acts` (the route's one or two actions). On a phone the bar is three rows — the search, the filters two to a row at equal halves, and the end group at `flex-basis: 100%` with the quiet pair left and the actions right. Reason: loose in a wrapping flex row the five to seven items composed differently on every route, which the user reported as "everything being positioned everywhere"; an auto margin can only push within a line a wrap has already chosen, and two in one line split the free space and marooned the `?` mid-bar. `:nth-of-type` counting of the selects was tried and rejected — a hidden control (My Work's period select) breaks it silently. The two sub-groups are what let the end group wrap at 320 without splitting either pair; an empty count is not drawn. Verified by `allbars` measurements at 320, 390 and 1280, `matrix: ok` and `uxaudit: ok`.

- **2026-09-20** — **One button order, everywhere: the primary first, the way out after it.** Thirty-one rows already obeyed `DESIGN.md`'s "Save / secondary / Cancel" and three did not (the two Team sheet feet, every `.changebox-actions`), so a hand that had learned a position pressed the wrong control at speed — reported by the user on a phone and at a desk. Which order is right matters less than there being one, and the portal had already chosen. `uxaudit`'s `order` rule measures it by x rather than markup order, since a row can reverse itself in CSS.
- **2026-09-20** — **No form sheet focuses a field on open.** On iOS a field taking focus raises the keyboard and zooms the page, so the reader landed on a form scrolled and magnified past what they opened it to read. The `.sheet-card` takes focus (`tabindex="-1"`, no ring), which keeps Escape, the focus trap and the dialog announcement. Removed from the Team sheets, all seven newly converted forms, the Add creator sheet, the campaign form and the creator picker. Focus after a **failed save** stays, per §11 Forms. Asked for by the user on 2026-09-20.
- **2026-09-20** — Seven more forms became sheets (`crmAddBox`, `crmContactBox`, `crmServiceBox`, `crmTouchBox`, `crmReplyBox`, `svcBox`, `addLinkBox`), so Clients, Services and Short Links match Team and the creators list. The client form no longer replaces the record's head, which had hidden the client while their own details were corrected.
- **2026-09-20** — The board's drag is **pointer events**, not HTML5 drag and drop, so a finger can move a card; it starts from `.bcard-grip`, whose own `touch-action: none` is what stops the browser claiming the gesture as a scroll (a press and hold cannot work — the decision is made when the touch lands). A clone follows the hand; the real card stays put. The select stays on every card for the keyboard. Asked for by the user on 2026-09-20.
- **2026-09-20** — Adding or editing one record is a sheet over the list on every console section (`js/sheet.js`, `.sheet-card.formsheet`): the Team page's member and group panels were `.panel` blocks that unfolded at the top of the section, so on a phone pressing Edit on a row put the form a screen above it. Asked for by the user on 2026-09-20 against the creator sheet's shape. Two rules go with it: **the scrim does not dismiss a sheet that holds typed changes** (the user's own complaint — an accidental click outside the card threw a form away), while an untouched one still closes on it; and **Escape always closes**, so the keyboard path and the matrix's dialog pass are unchanged.
- **2026-09-20** — No field is under 16px under a coarse pointer (`css/portal.css`, foot of the file). iOS zooms the page when one takes focus and does not zoom back. `--field-text` had said 16px for months and six single-purpose rules stated their own size past it. `user-scalable=no` and `maximum-scale=1` were weighed and refused: they fail WCAG 1.4.4 and the matrix's 200% pass. `uxaudit`'s new `zoom` rule measures every field at 390 with a coarse pointer, so it cannot come back.
- **2026-09-20** — A creator's name is unique on a key that trims both ends, collapses runs of whitespace to one and ignores case, and the name is stored the way it is compared. `SteveCN`, `SteveCN ` and `SteveCN  ` are one creator; a space inside a name is a different name and stays a caution. The warning also runs before any profile link is typed, which is where the duplicate is actually made. The Creators List record cell counts campaigns and dates them and never names one — the user sent the name back on 2026-09-20 because a title is longer than the column and the names are on the creator's own card.

- **2026-09-20** — The board draws an empty stage column only where a task on it could move into that stage next, or where it is the workflow's entry; On hold draws only while it holds something. A card is dragged into a column through `moveTo()`, the one path the list row's select and the card's select already take, so the gates and the refusal are unchanged; the board marks the allowed columns while the card is in hand; On hold is not a drop target because Blocked needs a category. Drag is set under `(pointer: fine)` only and the select stays everywhere, so no input loses a way to move a stage. Asked for by the user on 2026-09-20 ("the card couldn't be dragged around, and the section is so long in a long row"). Verified by `node tests/work.js tests` → `work: ok`.
- **2026-09-20** — `tests/work.js` exists again, and the ops half of `tests/stub2.js` with it (twelve tables, two seeded workflows, seventeen functions mirroring every gate). Three query-builder gaps went with it: `.order()` had been discarded, so "the last event" was whichever row came first; `.gte()`/`.lte()` did not exist, which the period bound needs; and a bare ambiguous embed is now refused the way PostgREST refuses it, which is the fault class that blanked every owner in My Work in production.

### Roles and permissions

- **2026-09-15** — One user group per person (`team_roles` → trigger → `team_members` → `allowed(flag)`), never per-person switches. The groups seeded are Admin, Marketing and Sales; Marketing was renamed from Account because "Account" is the word for a login. The slug `account` is what `team_members.role` points at and does not move.
- **2026-09-22** — The Register joined the ladder as a section (`register`), and HR letters as a part of it (`register.hr`; they were a section, `hr`, for a day and the backfill moves the level across once). `register_may(family, level)` answers an HR document to `register.hr` alone, a client document to `register.documents` or `clients.documents`, and a hand-added "other" document to `register.documents`; it is the `documents` read policy and the check inside every write. A group that could open the console before this change has `none` on the Register until the Team page sets it; an admin has everything.
- **2026-09-22** — Access has parts. A part is a pane or list inside a section (`clients.contacts`, `clients.billing`, `clients.services`, `clients.documents`, `clients.requests`, `clients.calls`; `review.sets`, `review.settings`; `campaigns.campaigns`, `campaigns.creators`, `campaigns.finance`; `register.documents`, `register.hr`), keyed under its section in the same access map, with a level only where the group set one and its section's level otherwise, in `allowed()` and in the page's `may()`. Table policies key on the part; the billing columns of `clients` and the invoice columns of `campaigns` are guarded by trigger at the part's Work level because a policy cannot separate columns. The Team panel draws each section as a block, its select on the head line and its parts beneath at `Same as section`; only exceptions are stored. Decided with the user on 2026-09-22 against a select-per-pane matrix.
- **2026-09-22** — The Billing switch (`can_billing`) is retired at the user's request; Billing is the part `clients.billing`. Reason: the letters in Documents print the registered name and billing address, so the switch hid a pane and not the facts. `verify_letter` asks `clients.documents`; the column stays, unread; `allowed('billing')` refuses.
- **2026-09-16** — Activity navigation is absent when `can_activity` is false. A refused pane is not shown as an empty activity record, and a copied Activity URL falls back to Overview; database policy remains the control.
- **2026-09-15** — `is_team()` gates every team table. A signed-in account is not the team: clients hold logins too. One address is never both a colleague and a client contact (`no_team_client_overlap`), and where a legacy overlap exists the client portal is the side that yields.

### Workflow invariants

- **2026-09-15** — A campaign creator moves Confirmed → Pending visit → Pending draft → Reviewing → Changes requested → Scheduled → Posted → Completed. Each step is gated by its data and every forward move has a Revert. "In production" is derived on every load, never written by the action that caused it.
- **2026-09-15** — A creator may upload at `pending_draft` or `changes` and, since 2026-09-22, at `submitted` until the team releases it (`creator_can_deliver`); taking a file back off shuts at `submitted` (`creator_can_retract`). Handing in moves the step to `submitted`, which the team reviews and releases. The payment form (AP01) is named once the work is approved, not when it is handed in, so a reshoot does not put a bill in the ledger against work nobody accepted.
- **2026-09-19** — A client's verdict on a draft is recorded in three places, not one: the `option_reviews` row it always wrote, an `activity_log` row under the reviewer's own name, and the last decision sent back with the booking by `get_campaign` so the client's own card can name who approved it and when. Before this, approving moved the booking to Scheduled and left no trace anybody could read. The name is asked once per browser (`adspace_reviewer`) and is required for both decisions.
- **2026-09-19** — A creator rates the booking, not the agency, and only once it is `completed` (`campaign_options.creator_rating`, 1 to 5, `creator_rate`). Payment details leave the card at the same moment. The rating is never shown to the client.
- **2026-09-20** — A client has one set of platform handles and one logo, on the `handle_*` and `logo_url` columns, edited from the Brand profile and from Content Review's client settings alike. `social_*` was a second store over the same row, so a handle corrected on the record never reached the client's own mockup; it is backfilled by `handle_of()` and no longer written. A handle is stored, and the address to open it is derived per platform.
- **2026-09-20** — Deleting a client is `can_remove`, re-checked by `delete_client`, offered in the record's ⋯ behind a sheet that counts what goes and takes the name typed back. Paused and Past remain the everyday way a client leaves the working list; this is for a record that should not exist. The cascade takes contacts, calls, service lines, letters, requests, content sets and campaigns with it, and there is no restore.
- **2026-09-20** — The Clients register bands are **Leads / Clients / Past clients**. Clients holds active *and* paused (the working book of business); Past clients are ended engagements, shut by default and remembered, keeping their count because they still hold their Client ID and may renew. Leads stay first. A filter opens every band. The Client ID is drawn on the row under the name and is searchable; it remains manual and issued by the accounting system, and is load bearing for the letter serial.
- **2026-09-20** — Blue is spent once per card, not once per creator: a campaign's `advance` button is `.btn-go` only for Release to client, the one step that hands work to somebody else. The other five steps read as ordinary actions and are told apart by the word on them.
- **2026-09-22** — The team can hand a file in for a creator from the campaign's draft step at the steps the creator's page allows (pending draft, changes requested, submitted), by the console's own signed PUT, into the same hand-in; `campaign.file_added` names the creator, the file and who uploaded it. The ceiling is 1 GB a file (`ADSPACE_CONFIG.s3.maxUploadMB` 1024). The Creators List record counts every step from Confirmed onward, `submitted` included.
- **2026-09-22** — Every tag written to `activity_log` is named in `ACTION_LABEL`, every everyday Content Review write leaves a row, and `document.*` and `register.*` rows file under Documents, which is a filter tab.
- **2026-09-20** — A creator's submitted video plays in the console (`.filecard-video`), so nobody downloads a file to review it before releasing it. Media is 9:16 cards, everything else is an attachment line; one grid of mixed aspect ratios left files orphaned on their own rows.
- **2026-09-20** — `js/ask.js` is the one copy of asking for one value on the page: `rename` (edit the thing where it sits, the opening control becomes Save), `inline` (the field grows out of the control that needs it), `note` (a textarea under the control that sends it). No sheet lives in it, because an act whose consequence must be stated first is a sheet and collapsing it into a growing field hides the consequence. `tests/sets.js` fails on any `window.prompt` or `confirm` opening.
- **2026-09-20** — A client is asked for their name **on the page**, never with `window.prompt`: `js/decide.js` grows the field out of Approve (the `.pbox` pattern) and is the one copy for `/review/` and `/creators/`. A prompt cannot be styled or translated and is a system sheet on a phone. Where the note box is already open it carries the field itself.
- **2026-09-20** — `tests/stub2.js` honours an embedded select's **column list** (`clients(name, market)` yields those columns and no others). It used to hand back the whole row whatever the query asked for, which made it more generous than PostgREST and hid a missing column: the campaign record read `logo_url` off a join that never requested it, so every campaign fell back to initials.
- **2026-09-20** — `hi.adspace.me` is a Cloudflare Worker (`workers/links/`, account ADspace, zone `adspace.me`) and the Short Links list is live. It reads through `link_resolve(p_slug, p_qr)` with the **public anon key**, not with the service role: the function answers one exact slug with one destination and one state, so a redirector never needs a key that can write. Four states, because they are four pages — `ok`, `missing`, `paused`, `revoked`; a pulled QR code is turned away while the typed link keeps working. Redirects are 302 and `no-store`, since the point of a table is that a destination can be corrected. `go.adspace.me` is not served by it and is not retired: printed QR codes encode that whole address.
- **2026-09-20** — An event about a campaign is filed under the campaign's title, never under a creator's name. The campaign Activity pane reads `activity_log` by subject, so per-creator events written under the creator vanished from it; the creator belongs in the detail.
- **2026-09-15** — Reversibility vocabulary: Revert a state, Restore a record, Reinstate a person, Undo a removal, Void then Delete an issued document. A number is never reused.
- **2026-09-15, raised 2026-09-22** — A creator uploads up to 1 GB a file (`ADSPACE_CONFIG.s3.maxUploadMB`, 300 MB until the user asked for more) and as many files as a booking needs, and the console can hand a file in for them at the same steps. The file is not uploaded until `creator_add_file` has written the row, so every step's failure is the whole file's failure and is named on the page.

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
- **2026-09-19** — My Work: `node tests/work.js tests` → `work: ok`. It drives the queue's bands and counts, the task workspace and its panes, a stage move and the refusal that names the gate in the team's words, the link that opens that gate and the Undo that shuts it again, a date move with its reason, blocking, the timer, the checklist, the new-task sheet, and what a group with `ops` Work but none of the granted parts is offered. `tests/stub2.js` carries the ops half of the model, including every refusal, because a stand-in that cannot say no is one that cannot test a refusal.
- **2026-09-21** — **My Work is in `tests/uxaudit.js`'s walk and `tests/matrix.js`'s route list.** It was built across three phases and never added, so its queue, its three views and the new report had never had their alignment, contrast or touch targets measured by anything. It failed on the first run, on a real fault: `.is-narrow .rep-row` lost to `.is-narrow .svc-row` defined later in the file with the same specificity, leaving four tracks whose last was sized by its own row, so two figures started 7px apart. Measured (`grid-template-columns` read back as `241px 0px 0px 48.8px`), then the rule was moved rather than its specificity raised. The standing rule this confirms: **a new route or pane joins the walk in the same push that builds it**.
- **2026-09-19** — Operations: `node tests/ops.js tests` → `ops: ok`, required for any change to the operations system. It applies the dated migration twice against a throwaway Postgres 16, uses the real ladder cut out of `supabase/schema.sql`, and covers permissions, stages, commitments, assignment, sessions, revisions, completion, recurring generation and the append-only audit trail. **A `cut()` with no end marker takes everything appended to the schema afterwards** — the operations section landed inside `tests/sql.js`'s letters fixture the day it was added, so both open cuts now end at the next banner.
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
