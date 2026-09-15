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

### Design system

- **2026-09-15** — Tokens live in `css/portal.css` `:root`: colour, `--radius`, `--head-h`, `--ctl-h`, `--ctl-h-sm`, `--state-w`, `--ctl-text`, `--field-text`, `--shadow`, `--shadow-lift`, and the motion set `--t-fast` / `--t` / `--t-slow` / `--ease` / `--ease-out`. The full table and the reasoning are in `DESIGN.md`.
- **2026-09-15** — **Differs from §8 of this file.** The spacing scale is 4, 8, 12, 16, 24, 32 and stops there. 40, 64 and 104 are editorial rhythms for a landing page; this is a dense operations console where a 64px gap between two tables reads as a missing section. `uxaudit` fails a section whose sibling gaps differ.
- **2026-09-15** — **Differs from §8 of this file.** Body text is 14px, not 16px. This is an operations console read all day at a desk, not reading-heavy content, and §9 of this file allows dense operational screens their own proportions. The floor is 11px and `uxaudit` fails anything smaller.

### Roles and permissions

- **2026-09-15** — One user group per person (`team_roles` → trigger → `team_members` → `allowed(flag)`), never per-person switches. The groups seeded are Admin, Marketing and Sales; Marketing was renamed from Account because "Account" is the word for a login. The slug `account` is what `team_members.role` points at and does not move.
- **2026-09-15** — `is_team()` gates every team table. A signed-in account is not the team: clients hold logins too. One address is never both a colleague and a client contact (`no_team_client_overlap`), and where a legacy overlap exists the client portal is the side that yields.

### Workflow invariants

- **2026-09-15** — A campaign creator moves Confirmed → Pending visit → Pending draft → Reviewing → Changes requested → Scheduled → Posted → Completed. Each step is gated by its data and every forward move has a Revert. "In production" is derived on every load, never written by the action that caused it.
- **2026-09-15** — A creator may upload only at `pending_draft` or `changes`. Handing in moves the step to `reviewing` and is what the team sees. The payment form (AP01) is named once the work is approved, not when it is handed in, so a reshoot does not put a bill in the ledger against work nobody accepted.
- **2026-09-15** — Reversibility vocabulary: Revert a state, Restore a record, Reinstate a person, Undo a removal, Void then Delete an issued document. A number is never reused.
- **2026-09-15** — A creator uploads up to 300 MB a file (`ADSPACE_CONFIG.s3.maxUploadMB`) and as many files as a booking needs. The file is not uploaded until `creator_add_file` has written the row, so every step's failure is the whole file's failure and is named on the page.

### Technical constraints

- **2026-09-15** — Static site, vanilla ES5-style IIFE scripts, no build step, no framework, no bundler. GitHub Pages at digital.adspace.me. There is therefore no path routing (`404.html` is the user's own site and is never edited); state travels in `?s=`.
- **2026-09-15** — Server-side work runs in Supabase Edge Functions (`sign-upload`, `invite-member`, `portal-login`), deployed by the user with the Supabase CLI. GitHub Pages cannot hold a secret or receive a webhook.
- **2026-09-15** — `supabase/schema.sql` is re-runnable and applied by hand in the SQL editor. A seed is a first run, not a running list: catalogue rows seed only into an empty table, or a deletion made in the console comes back.
- **2026-09-15** — A change confined to one function or column ships as a dated file in `supabase/migrations/`, not as a re-run of the whole schema. The full file carries fifteen top-level data migrations and recreates fifty-six policies, triggers and indexes; all are idempotent, but running them on a live database to replace one function body is exposure with no benefit. A migration file carries its own rollback and is applied standalone, twice, by `tests/sql.js`.
- **2026-09-15** — Two failure modes that hid a production outage for two rounds, both now covered by tests. (1) PL/pgSQL resolves a declared variable against an unqualified column **at run time**, so a function that shadows a column (`declare id uuid` + `where id = p_option`) creates cleanly and fails on every call: declared names never match a column, and lookups are qualified. (2) `promise.then(onOk, onFail)` does not route what `onOk` throws to `onFail`; a check written that way reports nothing. Use `.then(...).catch(...)` wherever a handler can throw.

### Verification commands and environments

- **2026-09-15** — Server: `setsid nohup npx --yes http-server -p 8899 -s . >/dev/null 2>&1 &` from the repo root.
- **2026-09-15** — Sweep: `for s in run camp client cprod bar newbadge prod qr regress backup keyin state race chrome crm sgd team portal creator; do node tests/$s.js tests; done` — every suite `0 FAIL`, no page errors.
- **2026-09-15** — SQL: `node tests/sql.js tests` → `sql: ok`, required for any change to `supabase/schema.sql`. It runs the real file against a throwaway Postgres 16.
- **2026-09-15** — Audit: `node tests/uxaudit.js tests` → `uxaudit: ok`. Screenshots: `SHOTS=1 node tests/uxaudit.js tests` into `tests/walk/`.
- **2026-09-15** — **Differs from §12 of this file.** The viewport matrix is 1280 and 390 with a coarse pointer, and the console again in dark at both. 390 is narrower than the 375 this file asks for and is the real floor the portal supports; the desktop console is not used below 1024, so 768 and 1024 are not walked. Widening the matrix is a genuine open item, recorded below.

### Accepted known issues

- **2026-09-15** — The audit walk does not cover 320, 768 or 1024 (see above). Risk: a layout fault between 640 and 1280 would not be caught. Not yet scheduled.
- **2026-09-15** — Keyboard-only and screen-reader inspection is partly automated: `uxaudit` tabs every focusable control and fails one that takes focus without a ring, and checks labels, names and contrast. It does not replace a real screen-reader pass, which has not been done.
