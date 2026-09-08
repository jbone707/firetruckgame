# Design directory: rules of the road

This directory is the only place in the repository that ChatGPT writes to. It is
how the design side and the implementation side talk. Everything else in the
repository is owned by the implementation side (Cowork plans, Claude Code
implements) and is read-only to ChatGPT.

## Who does what

- Cowork (Claude): plans the game, writes every Claude Code task, reviews every
  Claude Code report for engineering. Reads this directory; writes to it only
  through Claude Code.
- ChatGPT: visual design and design review. Writes only inside this directory,
  only on the `design` branch, only through pull requests that James merges.
- Claude Code: implements on task branches, keeps `STATUS.md`, `DESIGN.md` and
  `DECISIONS.md` current, writes `REQUESTS.md` here when a task needs design
  input. Never edits any other file in this directory.
- James: decides, merges, and copies files between tools when a connection
  is missing.

## Files in this directory

| File | Written by | Purpose |
|---|---|---|
| `README.md` | implementation side | These rules. |
| `REQUESTS.md` | implementation side | What we need from ChatGPT next, newest at the top. ChatGPT reads it and answers in its own files; it does not edit it. |
| `tailboard-visual-spec.md` | ChatGPT | The one visual specification: name, logo, palette, type, layout, screen and in-world graphics specs. Versioned at the top. Replaced in place, never appended to with addenda. |
| `reviews.md` | ChatGPT | Design reviews of implemented screens, newest at the top. Each entry names the commit reviewed, the files in `docs/screenshots/selected/` examined, concrete findings, and what was not verified. |
| `images/` | ChatGPT | Logo exports, mockups, reference sheets. Named by subject and version, for example `hud-desktop-v2.1.png`, `logo-icon-1024.png`. |

No other files or folders. A pull request that adds anything else, or touches
any path outside `docs/design/`, fails the automated check and is not merged.

## Reading order for ChatGPT before any work

1. `STATUS.md` at the repository root: what is built, what is in progress.
2. `DESIGN.md`: the authoritative game specification. Where it and the visual
   spec disagree, `DESIGN.md` wins until James approves a change and it is
   recorded in `DECISIONS.md`.
3. `DECISIONS.md`: dated decisions and what they superseded.
4. `REQUESTS.md` in this directory: the current ask.
5. `docs/screenshots/selected/`: real screenshots of the current build.

Do not read `docs/history/` unless a request points to a specific file there.

## How a request is answered

A request in `REQUESTS.md` names what is wanted, which files it should land in,
and a version number. ChatGPT answers by updating the named files on the
`design` branch and opening one pull request whose description lists the files
changed and the request it answers. Nothing is considered delivered until the
pull request is merged.

## How a review is written

A review entry in `reviews.md` covers one implementation task. It names the
commit, lists the screenshot files examined by name, gives findings as concrete
sentences ("the water bar label is 12 px; spec says 14 px"), and ends with a
line stating what could not be verified from screenshots alone. It does not
claim tests passed, files were committed, or behaviour works; those are
implementation-side claims and live in `STATUS.md`.

## Standing rules that apply to every design file

- Desktop-first: 1280x720 primary, 960x540 supported. No portrait, touch,
  auto-throttle, safe-area or service-hold guidance.
- Controls: W/S accelerate, brake, reverse; A/D steer; Space handbrake; Q siren;
  Z camera zoom; M minimap; N minimap zoom; Escape pause. Turret and hydrant
  are automatic; there is no spray key, aim, or refill key.
- Everything in the game is drawn in code from flat shapes. Every image is a
  reference; the written spec beside it (hex colours, sizes in px at 1280x720,
  anchors and offsets) is what gets built.
- Copy: Title Case for screen titles only; sentence case for buttons, labels
  and body; no period at the end of headings; no em dashes; no internal names
  on screen.
- Style: warm, flat, retro-inspired geometry; no glow, gradients or textures.
- Fixed facts: name Tailboard; engine 90x40 world units; residential road 280
  units wide; three calls per shift; tank upgrade 100 to 125 units for 200
  credits; call earnings survive a failed shift.
