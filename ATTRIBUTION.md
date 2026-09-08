# Attribution and Data Terms

Fire Truck Game's Windsor test area is built from OpenStreetMap data. This file records
where that data came from, what its licence says, and what was done with it. It is a
description of the terms as they read, not legal advice and not a legal opinion. James
decides how the licence applies to this project.

## Required credit line

    © OpenStreetMap contributors

This line, together with a statement that the data is available under the Open Database
License, must appear wherever the data is used. In the game it appears on the Data and
Credits screen, reachable from the home menu, alongside the licence URL:

    https://www.openstreetmap.org/copyright

That screen is not built from this file. It reads the credit line, the licence name and the
URL out of the map resource's own `source_metadata`, which `tools/import_osm.gd` writes, so
the notice travels with the data rather than sitting in a layout that could be edited apart
from it. `tests/test_session_and_save.gd` asserts that all three reach the screen, and
`tests/test_osm_import.gd` asserts the credit line is these exact characters, copyright
symbol included. The three places that have to agree therefore cannot drift apart silently.

## Source

| Field | Value |
| --- | --- |
| Dataset | OpenStreetMap |
| Copyright holder | OpenStreetMap contributors |
| Licence | Open Data Commons Open Database License (ODbL) |
| Licence text | https://opendatacommons.org/licenses/odbl/ |
| Copyright page | https://www.openstreetmap.org/copyright |
| Access method | Overpass API, `https://overpass-api.de/api/interpreter` |
| Download date | 2026-09-07 |
| OSM data timestamp | 2026-09-07T21:43:59Z (`osm3s.timestamp_osm_base` in the response) |
| Query | `data/source/windsor_shadetree_smoketree.overpassql` |
| Raw response | `data/source/windsor_shadetree_smoketree.json` |

### Area

A 500 m by 380 m box centred on the junction of Shadetree Drive with Smoketree Street and
Smoketree Court, Windsor, California 95492.

| Field | Value |
| --- | --- |
| Centre | 38.5439893, -122.7953823 |
| South (min latitude) | 38.5422777 |
| West (min longitude) | -122.7982498 |
| North (max latitude) | 38.5457009 |
| East (max longitude) | -122.7925148 |

The box started at 250 m by 180 m, as planned. At that size the drivable network inside it
held one intersection, no loop and two disconnected pieces, so it gave the player no route
choices at all. It was grown in steps to 500 m by 380 m, which is the first size at which
the clipped network is a single connected component (81 nodes, 10 intersections, 3 loops)
with nothing left over to prune.

## What the licence says

The following summarises the OpenStreetMap copyright page and the ODbL as they read. Read
the linked sources for the terms themselves.

- **The data is open.** You may copy, distribute, transmit and adapt OpenStreetMap data.
- **You must credit.** The copyright page states two requirements where OSM data is used:
  provide credit by displaying the attribution notice, and make clear that the data is
  available under the Open Database License. Linking to the copyright page is offered as an
  acceptable way to do the second. Where links are not possible, the full URL should appear.
- **Share-alike on the data.** The page states: if you alter or build upon the data, you may
  distribute the result only under the same licence.
- **Produced Work versus Derivative Database.** The ODbL distinguishes a *Derivative
  Database* (the data, altered or built upon) from a *Produced Work* (something made *from*
  the data, such as an image, a rendering, or an application). The share-alike requirement
  attaches to a Derivative Database. A Produced Work must carry the attribution notice, and
  the licence requires that where a Produced Work is publicly used, the Derivative Database
  it was produced from is made available under the ODbL.

### How that reads against this project

Stated plainly so the position is on the record, not to settle it:

- `resources/windsor_shadetree.tres` is generated from OSM data by
  `tools/import_osm.gd`. Whether a game map resource of this kind is a Derivative Database,
  a Produced Work, or both is arguable, and this project does not attempt to decide it.
- The project takes the cautious side either way: the raw OSM response, the exact query, the
  importer, and the generated map resource are all committed to this public repository, so
  the derived data is available under the same terms as the source alongside the work made
  from it. The credit line and the licence URL appear on the Data and Credits screen in the
  game.
- The final read on the licence is James's.

## What the game does with the data

- The download was **one time**. The committed response in `data/source/` is the only copy
  the game ever reads, indirectly, through the map resource generated from it. The game
  makes no network call at runtime and runs fully offline.
- **No map tiles or rendered map images are used**, from OpenStreetMap or from any other
  provider. Only vector geometry and tags are read: road centrelines, building footprints
  and point features. This is a deliberate rule of the project (handoff §7).
- The generated map is **not an accurate map of Windsor** and is never labelled as one. Road
  centrelines and building footprints come from OSM; hydrants, some lots, and other details
  are synthesized because the source data does not contain them. Every feature in the
  generated resource is tagged `source: "osm"` or `source: "synthetic"` so the two are never
  confused. The in-game name for it is "Windsor test area", and the map select screen prints
  these two lines under it, verbatim:

      Streets from OpenStreetMap; buildings partly synthetic
      Hydrant locations are placeholders, not real

  An earlier draft of this file recorded a single line, "Streets from OpenStreetMap;
  buildings and hydrants partly synthetic". That was replaced because "partly synthetic"
  understates the hydrants: not some of them are invented, all twelve are, and the sentence
  a player reads should say so plainly. The two lines above are asserted word for word by
  `tests/test_session_and_save.gd`, so rewording either one fails the suite rather than
  quietly changing what the game claims.

  The accuracy note the Data and Credits screen prints used to end "Every feature carries
  its own source field". That sentence is true and is the reason the rest of the note can
  be trusted, but it is a sentence about a data schema shown to somebody who came to drive
  a fire truck, so it was cut from the player-facing copy and kept here, where the people
  it is for will read it. What the screen prints now:

      Not an accurate map of Windsor. Streets and building footprints are from
      OpenStreetMap; hydrants, some lots and all colours are synthetic.

- **Some real footprints are drawn smaller than they were surveyed**, and say so in the
  data. The roads on this map are drawn at fixed world-unit widths rather than at their
  real widths, because road width is what the game was tuned around (`DESIGN.md` states
  that rule). A road drawn wider than it is reaches into ground the survey says is a
  garden, so a footprint standing there is shrunk about its own centre until it clears the
  pavement and is tagged `adjusted_for_road: true`; one that cannot clear it at half its
  size is dropped rather than drawn as something it is not. On the committed import, one
  footprint was set back and one was dropped, out of 237 kept.
- **Road names are printed only where OpenStreetMap gives one.** A way with no `name` tag
  gets no label, and a slip road (`highway=*_link`) gets none either, because it carries
  the name of the road it joins. An earlier build labelled these from the highway class
  instead, which put "Unnamed secondary link" across a slip road as though that were the
  name of a street.

## Overpass API usage

The Overpass API usage policy asks that public instances be used lightly: roughly 10,000
requests and under 1 GB per day as safety limits, with heavy or repeated automated use
directed to a private instance or a planet dump instead. Three requests were made in total,
on 2026-09-07: two small exploratory queries to locate the junction and size the box, and
the one committed download above. The game itself never contacts the API.
