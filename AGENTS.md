> **Scope note for this repo (Fire Truck Game, a Godot 4.7.2 desktop game).** This file is a
> verbatim copy of `docs/PROJECT_PLAYBOOK.md` from the Fire-Bid repo, adopted here on
> 2026-09-07. Its engineering conventions apply in full: "done" means committed (and pushed
> if a remote exists), every checker is proven by a deliberate failure, estimates are given
> before work and reported against afterward, and no behaviour is claimed that was not
> observed. Its web-application sections do NOT apply here and should be read as history:
> staging/production environments, Supabase migrations and the schema ledger, database
> credentials, the 390px mobile-parity rule, and the web conventions standard. The UI copy
> standard's spirit (Title Case headings, no em dashes, honest labels) is kept for the game's
> on-screen text; its route- and form-specific rules are not applicable.

# Project Playbook

How James builds software with AI collaborators. Distilled from Fire-Bid (June–September
2026), written 2026-09-05 so the next project starts on day one where this one finished.
Every rule here was paid for by a real incident; the Fire-Bid example is kept where it
teaches. **Copy this file into a new repo as the seed of its `AGENTS.md`, then let the
project's own incidents add to it.**

## 1. The people and the loop

Four roles. **James** decides, types every credential, applies every production migration,
and does the final look. **Cowork** (a Claude chat session with file access to the repo)
plans, writes every prompt, reviews every report, drives James's browser for walkthroughs,
and records decisions. **CC** (Claude Code, in the repo) implements, verifies, commits,
pushes. **An outside reviewer** (Codex, GPT, another model) reads the product as a
stranger and reports only problems.

The loop is fixed: Cowork writes a prompt → James pastes it into a fresh CC session → CC
pre-flights with estimates and choices → James picks → CC works, pushes per part, reports
→ Cowork reviews the report with a TL;DR first and a conventions check second → findings
go on the checklist → next prompt. Nothing joins the list unless a run, a walkthrough, an
outside review, or James finds it. **No proactive code sweeps.** Reading code to answer a
question or fix a finding is work; reading code looking for work is how a finished product
never ships.

## 2. The record

- **`AGENTS.md`** holds the rules. Every rule carries the date and the incident that
  created it, so a future reader can judge whether it still applies.
- **`docs/IMPLEMENTATION_CHECKLIST.md`** holds state: numbered items, `[ ]` / `[~]` /
  `[x]`, newest decisions appended under the item they belong to. A "finish line" section
  at the top says what done means, what is left, and what is parked. Done items move to
  `docs/archive/CHECKLIST_HISTORY.md` verbatim, leaving a one-line pointer.
- **Markdown discipline:** no new `.md` unless James or Cowork asks for it by name.
  Reports go in chat; the checklist entry is the durable record. Every doc costs tokens in
  every session that reads it.
- **A machine checks the docs.** `scripts/docs-check.mjs` in CI fails on retired names,
  dead hosts, a checklist over its line budget, and any phrase a public-claims registry
  marks SUPERSEDED that still appears in `src/`. A rule that lives only in a doc drifted
  three times on Fire-Bid; the checked ones did not.

## 3. Writing a prompt for CC

One prompt, inline in chat, never a file. Its shape:

1. **Header:** fresh session, model recommendation, which files to read first (AGENTS.md,
   then the relevant checklist items), what is pre-authorised (pushes, staging writes),
   what is forbidden (production writes), where credentials are.
2. **Parts, in order of damage,** each finished with its own commit and push so partial
   progress lands. Each part says what is wrong, what right looks like, and how to verify
   it on the rendered UI, not in the diff.
3. **Skip list with reasons,** so CC does not "helpfully" do the parked thing.
4. **Verification and report:** the check suite; what to verify on staging; report format
   (TL;DR, then one block per part, root causes for anything investigated, SQL for James
   with hashes, "seen, not touched", elapsed vs estimate).
5. **Cowork's own estimate and options** at the bottom, so James sees the trade before
   pasting.

Reviewing the report: TL;DR first, a "Conventions check" line second, deviations judged
one by one (CC's deviations from the prompt are usually right and must be said so), then
exactly what James has to do next, in order.

## 4. Estimates, choices, models, subagents

- **Pre-flight, as multiple choice, before any work.** CC's first reply to a multi-part
  prompt is question cards: how to run it (serial / fanned out / cut-down) with model mix
  and minutes per option; the subagent plan for approval (one line each: part, files,
  model, must-not-touch); any scope ambiguity. James answers; then work.
- **Model mix leans light.** Protect the heavy model's allowance for migrations,
  root-cause hunts, and anything that rewrites a rule. Copy sweeps, per-doc corrections,
  route-by-route verification, screenshots go to lighter models, in parallel. A few extra
  tokens on a slower model that finishes the whole job beat a fast heavy model that runs
  out. Time is unretrievable.
- **Subagent rules:** one writer per file, ever; only the main session touches database,
  credentials, staging, git, checklist; read-only verification fans out freely; the report
  names what each subagent did and what the main session did not re-verify.
- **Say what you are waiting on.** A poll, a permission card, a hung call: name it within
  a minute; stop and ask after ten. "Taking forever, using no tokens" is always a wait.
- **Report elapsed against the estimate**, with a sentence if off by a third.
- **Integration is never estimated at less than the sum of the subagent parts.** Pulling
  loose logic into a tested function, fixing what a subagent worked around instead of
  accepting it, wiring a new route into shared routing, a new test fixture: none of that
  shows up in a subagent's file list, and the main session's half of the work regularly
  outweighs the parts fanned out. Give integration its own estimate line.
- **Push the code before applying its migration to staging.** Applying first and verifying
  in the gap before the push runs the first check against the OLD deployed build, and a
  real failure reads as a code problem when it is a sequencing one. Commit, push, wait for
  the deploy, apply, then verify.

## 5. Environments

Exactly two, both deployed from `master` on push, both at real URLs. **Production** holds
no real data until James says the launch phrase ("FireBid is live"), which is the only
thing that changes the status token. **Staging** is a persistent database branch plus its
own deploy, seeded with a fictional department, real test logins in a gitignored file,
outbound email and push keys blank so nothing sends, `noindex`, and a banner that says
what it is. **Every walkthrough, dry run, and automated UI test runs on staging.** No
localhost workflow for testing; the one Fire-Bid had pointed at a session scratchpad and
died with it.

Every script that touches a database refuses production by literal ref **and** by a
content check (production hosts the demo department; staging does not), and both guards
are tested against the real databases before trusting them. Other branches are
create-use-delete. A new branch clones a stale snapshot with fresh-project default grants;
nothing is true about it until the ACL baseline is restored.

## 6. Database discipline

- **Every migration records itself, last statement, with a hash** of everything above the
  ledger marker. The row means "ran to completion"; the hash means "this exact file". Both
  exist because a plain ledger recorded intent, not fact, and a half-applied migration
  once left an empty table 500-ing a page for weeks.
- **Never grant in bulk.** `grant all on all tables` silently handed back privileges
  earlier migrations had deliberately revoked, for a month, while a public security claim
  cited the revokes. Name each privilege, each role. Migrations **assert** their own grants
  at the end; on Fire-Bid that assertion caught Supabase's default privileges giving a
  service role DELETE on a brand-new table, on the first run.
- **`create or replace function` starts from the live body, never from an earlier migration
  file.** Take the current definition with `pg_get_functiondef` from staging, confirm it is
  identical on production, and edit that. End the migration with an assertion on
  `pg_proc.prosrc` naming the specific statements earlier migrations added, placed **above**
  the ledger record so a regressing migration never records itself. On Fire-Bid a migration
  that needed to add one line reproduced the whole body from a version two migrations stale,
  silently deleting a fix, which then reappeared in production nightly for two days: a
  migration file records what one change did, and only the catalog knows what the function
  is now.
- **Append-only tables stay append-only,** even when a delete would be convenient. Fix the
  writer, add a boundary row, never open a delete path for tidiness.
- **James applies production migrations by hand; CC verifies read-only** (ledger row,
  hash, grants, invariants query returning zero rows) and states what it checked.
  Rendering code that depends on a new column must fail soft, because the deploy lands
  before the migration.
- **A baseline snapshot of the full schema and every grant** is committed and refreshed
  after each migration batch; backups run `--no-privileges`, so this is the only record of
  grants.
- **Ask the question the read-only user can actually answer.** A grants view that returns
  zero rows for the whole schema is not "no grants", it is "cannot see"; use `aclexplode`.

## 7. Done means committed, pushed, and seen

Three finished, reviewed pieces of work once sat uncommitted for a day, marked DONE. Now:
nothing is DONE in the checklist until committed; anything user-facing says whether it is
deployed; deployability is proven from a clean clone of the exact commit. Every UI change
is verified on staging's rendered page, at desktop and ~390px, before the report.

## 8. Safety nets and checks that cannot pass vacuously

Any break-glass query, rollback, or recovery step is first run as a read that proves its
precondition (the row exists, the backup restores). A net that has never met reality is a
hope. Every checker is proven by deliberate failure before it is trusted: a hash matcher
once hashed 36 of 120 lines and would have passed forever; a copy checker's first version
matched nothing; a grants query returned zero rows because it could not see. Prefer forms
that succeed loudly or fail loudly (`INSERT ... ON CONFLICT` reporting its count) over
ones that can silently no-op.

## 9. The web conventions standard (how a screen behaves)

James's rule: "people are used to surfing the web in a common way." A screen that passes
its spec but would surprise someone who uses ordinary websites is a defect.

Placeholders are never example values. One affordance per action. Password fields: one
show/hide toggle inside the field; "Forgot password" is a link below the button. Side
flows (forgot password, first sign-in, change email) are their own routes with a heading,
one field, one button, "Back to sign in"; never inline. After a request that sends email,
the form is replaced by a confirmation that says when to try again. Errors are sentences a
person can act on; every `catch` that reaches a screen goes through one formatter; admin
surfaces show a correlation id, employee surfaces do not. Signed-in users on `/login` are
redirected home; signed-out users never see the app header. Submit on Enter, submit once,
disabled while pending, confirmation on success; Escape closes; focus moves into what
opens. Destructive actions confirm inline naming the consequence. Buttons act, links go.
Every interactive element is a real `<button>` or `<a>`, 44px minimum. Async actions
acknowledge within ~100ms. Labels, not placeholders. Navigation identical on every
signed-in page. Every page has a title, one `h1`, and no horizontal scroll at 390px. No
internal filenames, identifiers, or migration names in user-facing copy, ever.

Thrown server-action errors are swallowed by the framework; **return refusals as data**
or the user sees a generic failure. Fire-Bid shipped tested refusal sentences that never
reached a person for weeks because of this.

## 10. The UI copy standard (what a string says)

- **Title Case** for headings, page and card titles, nav items, tab titles, email
  subjects, dialog titles, however the heading is produced (tag, prop, const array).
  **Sentence case** for body, buttons, labels, placeholders, helper and status text, table
  cells, errors. No terminal period on headings. One eyebrow/label style site-wide. Proper
  nouns keep their capitals in both. Settled once, after four conversations; do not reopen
  it on the next project either. Enforced by `scripts/copy-check.mjs` in CI.
- **A glossary of decided terms** (on Fire-Bid: "Round" not "Pass", "ready" not "frozen",
  the product name's exact spelling, page names as the nav spells them). Display renames
  never touch identifiers; a wording decision must not become a migration.
- **Formatters, never inline formatting:** dates, hours, plurals, statuses each have one
  function; raw enums and floats never reach a screen.
- **No em dashes on screen.** Truthful labels: a label that overstates what happened is a
  defect. Writers change forward only; audit rows keep what they said.

## 11. Time

Two kinds of value, never interchanged: an **instant** (`timestamptz`, UTC, `*_at`,
converted only at display, one formatter call produces the whole string) and a **calendar
date** (`date`, no zone, `*_date`, never converted, compared as text). Never slice a
timestamp to get a date. Parse date-only strings with an explicit `Z`; read with `getUTC*`
only. Display zones live on the department and the owner, are display-only, and never
throw.

## 12. Invisible operations

The customer-facing experience is flawless; problems are handled behind the scenes; the
core process (a bid, an auction, a draft) is never restarted short of unrepairable data,
and James decides. Containment is a pause that holds state. Fixes ship as ordinary pushes
and migrations while paused. Bad records are corrected surgically with a logged reason,
never by re-running. Users are told the process is paused, never why; admins see why. An
owner-set status banner exists for the message that has to be said. A one-page incident
playbook (Contain → Diagnose → Repair → Resume → Restart, last and shortest) is written
before launch and linked from the status doc.

## 13. The testing ladder

1. Unit tests on pure functions; keep server-only logic out of them by design.
2. A **database simulator** script that drives the real mechanisms concurrently against
   staging. It found the two real race conditions on Fire-Bid that no reading would have.
3. A **Playwright suite** against staging only (refuses any other base URL), reseeding
   before and after, that does what a person cannot: two tabs racing one action, every
   route at 390×844 asserting no overflow and 44px targets, a print PDF that is opened
   and read. Screenshots committed as evidence.
4. A **human walkthrough** on staging: Cowork drives the browser, James types the
   credentials, every role is exercised with real accounts. This is where UX defects that
   no script sees are found (stacked headers, a button covering a footer link, a page
   that names a migration file).
5. An **outside AI review** as the target customer, with a prompt that asks for problems
   only, ranked by damage to trust, page and element named. Then a second pass on the
   fixed items plus whatever the first pass could not reach (phone width, the demo).
6. **James's own five-minute look** as a stranger, before the launch phrase.

## 14. Credentials

Never in chat. James hand-delivers secrets into named local files; a permanent
`.env.test.local` holds the one management token everything reads. The file's presence is
not permission: every new round of work gets an explicit go-ahead before first use, and
CC checks in after a few rounds. Parse credential files, never `source` them (a stray
quote hangs the shell silently). Validate a token's shape before spending a round on it,
without printing it. Cowork never types a password, even when offered permission; James
does. Test logins live in a gitignored file the UI suite reads.

## 15. Trust pages and public claims

`/security`, `/privacy`, `/terms`, `/contact` are product surfaces and drift faster than
code. A **public security claims registry** lists each published claim with its evidence
and the phrase that expresses it; a claim marked SUPERSEDED whose phrase still appears in
`src/` fails CI. The pages name the operator, the retention schedule, the support
commitment, the backup and restore arrangement, and the actual sign-in mechanism. No
integration or compatibility claims the code does not have. A contact form, not only
mailto. The demo is a prospect's first experience: fictional identities throughout,
coherent history, and the nightly reset must not leave the audit log with its people
nulled by a cascade.

## 16. Launch

A **finish line** section states what done means, in checks that were run rather than
claims. Production stays empty until the launch phrase; the phrase flips the status token,
which re-enables push confirmation and the LIVE rules. After launch the only untested
thing should be the one that could not be tested before (notifications actually arriving),
and it is named as such.

## 17. Day one of the next project

Seed `AGENTS.md` from this file. Create the checklist with a finish-line section and item
1. Set up the two environments and the launch-phrase status token. Write migration `0001`
with the ledger table and the self-recording block, and the invariants and schema-probe
queries. Add `copy-check.mjs`, `docs-check.mjs`, and an empty Playwright suite pointed at
staging, all in CI beside lint. Create the public-claims registry before the first trust
page. Write the incident playbook before the first real user. Give every prompt an
estimate and choices from the first one.

## Changelog

- v1.0, 2026-09-05, from Fire-Bid
- v1.1, 2026-09-06, from Fire-Bid item 67: §4 gains two rules — integration is never
  estimated at less than the sum of the subagent parts, and push the code before applying
  its migration to staging.
- v1.2, 2026-09-06, from Fire-Bid item 68: §6 gains one rule — `create or replace function`
  starts from the live body via `pg_get_functiondef`, never from an earlier migration file,
  and asserts on `pg_proc.prosrc` above the ledger record.

## 18. This repository: branches, the design directory, and the two records

Added 2026-09-08, when `DEVELOPMENT_STATUS.md` reached 1,819 lines and a fresh
session's first act was reading eight milestones of narrative to find out what
the game currently is.

- **Work happens on a task branch,** named `task/<what-it-is>`, cut from
  `master` and pushed after every part so partial progress lands. One pull
  request per task, whose description is the completion report.
- **`docs/design/` belongs to ChatGPT.** It is the only path the design side
  writes, on the `design` branch, through pull requests James merges.
  `.github/workflows/design-branch-guard.yml` fails a `design` pull request
  that touches anything else. The implementation side writes exactly two files
  in there, `README.md` and `REQUESTS.md`, and reads the rest.
- **Two records, both kept current in the same commit as the code they
  describe.** `STATUS.md` is the state of the project: engine version, one line
  per system, the active task and its branch, the GameBalance table, known
  issues, and the exact next action. It stays under 150 lines; when it grows,
  something in it has stopped being state and become history.
  `DECISIONS.md` is one dated line per decision James has settled, saying what
  it supersedes. A decision recorded there is not reopened.
- **History is history.** Milestone narratives live in
  `docs/history/milestone-NN.md`, unchanged once written. Nothing reads them to
  find out what is true today; that is `STATUS.md`'s job.
- **The screenshot pack under `docs/screenshots/selected/` is committed.** It is
  what the design side reviews, and a review of screenshots nobody outside the
  session can open is not a review. The rest of `docs/screenshots/` is
  generated and ignored, and `docs/.gdignore` keeps Godot from importing any of
  it.
