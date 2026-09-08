# Decisions

One line per decision James has settled, dated, newest at the bottom. Each says
what it supersedes. A decision here is not reopened; a later line supersedes an
earlier one and says so.

- **2026-09-07 — The game is called Tailboard.** The working title "Fire Truck
  Game" is superseded as the product name. It survives only as the repository
  folder, the Godot `config/name`, and the older documents in `docs/history/`.
- **2026-09-07 — Desktop first: 1280x720 primary, 960x540 supported.** iPhone
  and touch are later, and nothing is designed against them now. This
  supersedes every portrait, touch, safe-area and auto-throttle instruction in
  earlier design material.
- **2026-09-07 — `docs/design/` is ChatGPT's only write path.** Everything else
  in the repository is read-only to the design side, and ChatGPT writes only on
  the `design` branch, only through pull requests James merges. Enforced by
  `.github/workflows/design-branch-guard.yml`.
- **2026-09-07 — Roads are exaggerated, land is real.** A road's drawn width
  comes from a table in world units; everything else on an imported map is the
  real place at 14 units per metre. This supersedes Milestone 5's single 25
  units per metre projection, which made the truck read as a toy.
- **2026-09-07 — OpenStreetMap is the source for real areas.** Downloaded once
  through Overpass, committed verbatim, imported by a deterministic tool. The
  game makes no network call and uses no map tiles.
- **2026-09-07 — The minimap zooms independently of the camera.** N changes the
  panel, Z changes the view, and neither touches the other.
- **2026-09-07 — Sidewalks are drivable and cost nothing.** Temporary, and
  named as temporary: it holds only while there is nobody on them. Pedestrians
  end it.
- **2026-09-07 — The hydrant hookup is automatic.** Roll into the ring at a
  creep and the hose shoots out; drive away and it snaps. This supersedes
  handoff section 6's held-E hookup, its hookup key, and its rule that spraying
  and refilling cannot happen at once.
- **2026-09-08 — Due-regard driving is the core of the game.** Getting to the
  fire through traffic without hitting anyone, with the siren as the tool that
  opens gaps. This supersedes "traffic and signals" as a decorative future item
  in `DESIGN.md`.
- **2026-09-08 — Cars are solid to the engine.** They sit on a physics layer the
  truck's mask includes and they block it. This supersedes the earlier
  no-collision placeholder in which traffic would have been scenery.
- **2026-09-08 — Signals stay simple, with preemption for the siren.** A fixed
  cycle with an all-red between phases, plus a preempt sequence when the siren
  is on and the engine is close on an approach arm. No confirmation light, no
  per-junction demand logic, no vehicle detection.
- **2026-09-08 — The turret is automatic. There is no mouse aim and no spray
  key.** The turret finds the active incident, checks line of sight, rotates at
  a bounded rate and sprays. This supersedes handoff section 5's mouse aim, the
  `spray` input action, and the "spray and miss" water cost: water is spent only
  while spraying at a valid target.
