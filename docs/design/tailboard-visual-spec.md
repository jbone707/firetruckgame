# Tailboard visual specification

Version 2.1 | Desktop visual specification

## Logo

The mark is the approved blue hose TB with a small red hydrant at its upper left. The capital T has a broad crossbar and an upright stem, with a slight natural bend rather than a J-shaped hook. Its crossbar joins the top of the B. The B has two open counters, rounded left corners and rounded outer bowls; its lower bowl is slightly larger. There are no outlets, nozzles or discharge fittings on the B. A single open coupling terminates the bottom of the T. This is a graphic letterform, not a physically continuous hose diagram.

### Geometry

Use a normalized 100 by 100 square. The occupied mark is approximately x8 to92 and y19 to79. The hydrant occupies approximately x8 to23, y19 to39: a short stem and domed crown, horizontal collar, rectangular body, side cap and broad foot. Its front cap is a cream hexagon with a red central circle. The blue inlet coupling is immediately to its right. The T stem occupies approximately x35 to44, from y34 to71; its bottom coupling occupies x34 to46, y71 to79. The crossbar runs from approximately x27,y27 to x64,y26, with a shallow downward bow. The B occupies approximately x57 to92, y26 to78. Its two cream counters are rounded, with minimum open width approximately10 units. Follow the icon's contour when redrawing rather than making perfectly straight plumbing bends.

Keep both B counters, the gap between the stems, and the T coupling opening visible at small size. Do not add detail to the hydrant. At180 pixels retain the same complete mark. No wordmark belongs inside the square icon.

### Colours

| Element | Hex |
|---|---|
| Hose letters and coupling | #3E7FA6 |
| Hydrant | #C8362B |
| Background and negative spaces | #F2EDE4 |
| Wordmark and monochrome foreground | #241F1B |

All constructed game graphics use opaque flat fills. The supplied raster references can contain minor colour variation from generation and antialiasing; these variations are not additional palette colours, lighting, grain or shading instructions.

### Wordmark

Exact spelling: Tailboard. Use Archivo ExtraBold, weight800, from Google Fonts. Archivo is distributed under the SIL Open Font License1.1. Include the font's upstream license when packaging the font with the game. The raster wordmark is a visual reference; use the actual Archivo font when redrawing text in Godot.

Place the mark to the left of the word. Use visible mark height H, gap0.14H, and a word capital height approximately0.55H. Align the word optically to the mark's vertical centre. Keep at least0.15H clear space around the complete lockup. For example, at1280x720 a menu lockup may use a160px visible mark height,22px gap and88px capital height. These are logo proportions, not a home-screen layout prescription.

### Monochrome

Replace the blue and red foreground with ink #241F1B. Preserve both B counters, the front cap and coupling openings as background cutouts. Do not merge these openings into solid foreground. On an ink background, reverse the foreground to cream and preserve the same negative spaces. The supplied monochrome PNG is ink on cream, not a transparent asset.

### Reference exports

- images/logo-icon-1024.png: square colour mark,1024x1024
- images/logo-icon-180.png: square colour mark,180x180
- images/logo-wordmark.png: horizontal colour mark and Tailboard lettering
- images/logo-mono.png: square monochrome mark

All images are references for code-drawn geometry. The icon exports retain the approved working artwork. The horizontal and monochrome exports apply the approved letterform direction to those uses. No gameplay, HUD or control change is specified by this logo section.

## Scope and reference basis

Desktop primary canvas: 1280x720 pixels. Supported smaller canvas: 960x540. All following measurements are physical UI pixels at 1280x720 unless a smaller-resolution override is explicitly listed. These are design references, not screenshots of an implemented redesign. The logo section above is retained verbatim from the merged specification.

The HUD world backdrop is James's supplied real gameplay screenshot `05_hud_normal.png`, retained for road geometry, engine placement and camera context. At the master revision read for this request, `docs/screenshots/` was not present. No generated map or live imagery substitutes for that screenshot. The home illustration is a deliberately simplified diagram based on the same kind of junction, not a geographic map. The minimap illustration explains symbols and framing; implementation must project its actual map data.

The written visual rules govern the redraw, including exact colour fills and font metrics. Existing screenshot terrain colours are context, not additional theme tokens. DESIGN.md governs existing gameplay; R-002's explicit control and automatic-interaction wording governs the new UI hints. This specification does not claim that the model behavior has changed.

## Palette

All surfaces use solid fills. No gradients, texture, glow, blur or realistic lighting. Antialiasing at shape edges is permitted. The merged logo reference retains its existing raster appearance; redraw game shapes from the hex values.

| Token / use | Hex |
|---|---|
| Ink, primary text, borders, wheels | #241F1B |
| Paper, panel background, light markings | #F2EDE4 |
| Engine red, hydrant, main menu action | #C8362B |
| Pressed main action | #A92D24 |
| Amber, fire-health meter, active-call direction | #E0972B |
| Water blue, water meter, hose, selected state | #3E7FA6 |
| Warning timer background | #F0DDBE |
| Empty meter track and dividers | #D6D0C5 |
| Secondary text and condition fill | #665E55 |
| Secondary pressed panel | #E6DED2 |
| Disabled fill | #D9D1C4 |
| Disabled ink | #6B6258 |
| Asphalt, minimap road | #706A60 |
| Sidewalk, driveway, equipment | #D9D1C4 |
| Kerb | #B9AFA0 |
| Fence | #8F8475 |
| Yard, minimap land | #B9C2A0 |
| Alternate yard | #C9CDB7 |
| Tree / alternate tree | #8E9B77 / #A1AD89 |
| Sand roof | #A79B8B |
| Slate roof | #939FA4 |
| Clay roof | #B58E7C |
| Sage roof | #9BA38A |
| Stone roof | #B8B2A5 |
| Roof ridge | #756D63 |
| Flat eave shadow polygon | #8D887B |
| Windscreen / pickup bed | #44565D |
| Warning light off | #8B7267 |
| Signal green | #759365 |
| Smoke discs | #A8A398 |
| Steam / water impact core | #F2EDE4 |
| Car sage / slate / sand | #89927B / #77838A / #B8A58C |
| Car plum / cream / clay | #917E87 / #D6CBB7 / #A77762 |
| Civilian taillight | #A95D50 |
| Pedestrian light / medium / deep skin | #DFC09C / #AA7350 / #694A38 |
| Hair dark / light / deep / brown / grey | #342C24 / #B99B65 / #49362A / #705037 / #92918A |
| Clothing blue / ochre / navy | #637F94 / #B3975E / #45566F |

The unchanged gameplay backdrop visibly uses asphalt #23211F, lawns including #5A784C and #55754B, sidewalk #BCB7AA, cream edging #E6DECA, and roofs including #7C6D5E, #847F75, #8E6654 and #66707F. These describe the supplied screenshot only. The warmer palette above remains the proposed world redraw palette.

## Typography and shared states

Archivo throughout, with the font and license specified in the retained logo section. Font sizes are nominal pixel sizes; use explicit line heights. Text coordinates in the tables are top-left box positions, while baseline coordinates are called out separately. Screen titles only use Title Case. Buttons, labels and body use sentence case, without heading periods. Proper nouns keep their spelling. No internal identifiers on screen.

| Role | Size / weight | Line height | Colour |
|---|---|---|---|
| Main fire-health number | 44 / 800 | 52 | Ink |
| Normal timer | 28 / 800 | 34 | Ink |
| Warning timer | 24 / 800 | 30 | Ink |
| Fire and water labels | 18 / 600 | 24 | Ink |
| Water value | 22 / 700 | 28 | Ink |
| Call count | 22 / 700 | 28 | Ink |
| Credits | 18 / 500 | 24 | Ink |
| Siren state | 18 / 600 | 24 | Ink |
| Condition label and value | 16 / 600 and 700 | 22 | Ink |
| Edge-arrow label | 16 / 700 | 22 | Ink |
| Prompt | 20 / 700 | 26 | Ink |
| Minimap label | 14 / 700 | 18 | Ink |
| Menu buttons | 22 / 700 | 28 | Paper on red, ink otherwise |
| Other screen titles | 36 / 800 | 44 | Ink |
| Other body / map notices | 20 / 500, notices 18 / 500 | 28 / 24 | Ink |

Spacing scale: 4, 8, 12, 16, 24, 32. HUD panel radius 10 for the call panel, 8 for secondary panels, 6 for the arrow backing. HUD border 1.5px ink; internal divider 1px track. Bars have radius 3; condition bar radius 2. No shadow beneath panels. Menu buttons are 64px tall, radius 8, border 2px.

| Control state | Visual change |
|---|---|
| Normal main action | Engine red fill and border, paper text |
| Normal secondary / minimap zoom | Paper fill, ink border and text/glyph |
| Keyboard-focused | Normal plus 3px ink outer ring separated by a 3px paper gap |
| Pressed main action | #A92D24 fill |
| Pressed secondary / zoom | #E6DED2 fill |
| Disabled | #D9D1C4 fill, #6B6258 border and text, remains visible |

Focus is distinct from selection and never depends on hover. Menu focus begins on Start shift. The minimap zoom glyph is a plus drawn from two ink strokes, not a font-dependent character. Its accessible name is Map zoom. Mouse click and N invoke the same minimap-scale action. Neither changes camera zoom.

## Desktop HUD, 1280x720

Keep the world visible across the canvas. There are no full-width HUD bands. The active-call panel occupies the upper-left margin over land in the reference; the secondary panel sits upper-right. The projected engine is near (640,360) and facing north in the supplied screenshot. The visible road ahead, approximately x500..790, y0..320, remains uncovered.

The following offsets are relative to the named screen anchor. Top-right and bottom-right offsets locate the panel's top-left with negative X/Y values. Bottom-centre offsets are relative to (width/2,height). Child coordinates are listed as absolute top-left-anchor coordinates to remove ambiguity.

| Element | Anchor | Offset (x,y) | Size (w,h) | Fill / stroke / text |
|---|---|---|---|---|
| Active-call panel, including condition footer | top-left | (12,12) | 332x316 | Paper, ink 1.5, radius 10 |
| Call accent strip | top-left | (12,28) | 4x98 | Amber, radius 2 |
| Fire health label | top-left | (28,28) | 180x24 | 18/600 ink; baseline 46 |
| Fire-health value | top-left | (188,45) | 140x52 | 44/800 ink; right aligned, baseline 89 |
| Fire-health track | top-left | (28,102) | 300x14 | Track with amber fill fraction |
| Normal timer | top-left | (28,130) | 300x34 | 28/800 ink; baseline 158 |
| Water label | top-left | (28,177) | 100x24 | 18/600 ink; baseline 195 |
| Water value | top-left | (178,173) | 150x28 | 22/700 ink; right aligned, baseline 195 |
| Water track | top-left | (28,211) | 300x10 | Track with blue fill fraction |
| Footer divider | top-left | (28,244) | 300x1 | Track |
| Engine condition label | top-left | (28,257) | 205x22 | 16/600 ink; baseline 273 |
| Engine condition number | top-left | (242,257) | 44x22 | 16/700 ink; right aligned, baseline 273 |
| Condition track | top-left | (28,287) | 258x7 | Track with secondary-text fill |
| Contact glyph reserved box | top-left | (302,278) | 24x24 | Ink outline, amber contact stroke |
| Secondary panel | top-right | (-248,12) | 236x148 | Paper, ink 1.5, radius 8 |
| Call 2 of 3 | top-right | (-232,20) | 204x28 | 22/700 ink; baseline 42 |
| Credits | top-right | (-232,56) | 204x24 | 18/500 ink; baseline 74 |
| Siren state | top-right | (-232,86) | 204x24 | 18/600 ink; baseline 104 |
| Prompt backing, when visible | bottom-centre | (-300,-72) | 600x48 | Paper, ink 1.5, radius 8 |
| Prompt text | bottom-centre | (-284,-62) | 568x28 | 20/700 ink, centred; baseline screen y680 |
| Minimap panel | bottom-right | (-212,-162) | 200x150 | Paper, ink 1.5, radius 8 |
| Minimap title Map | bottom-right | (-200,-152) | 176x18 | 14/700 ink; baseline y582 |
| Minimap map surface | bottom-right | (-202,-128) | 180x106 | Yard, radius 3, clipped |
| Minimap zoom button | bottom-right | (-56,-58) | 32x32 | Paper, ink 1.5, radius 4 |
| Zoom plus strokes | bottom-right | (-47,-42) horizontal; (-40,-49) vertical | 14x2; 2x14 | Ink, rounded ends |

Normal reference values are Fire health 68%, Time left 1:26, Water 64/100, Engine condition 98, Call 2 of 3, 350 credits, Siren off. They illustrate the layout and do not assert the underlying screenshot had those model values. The prompt is hidden in the normal desktop reference. The contact glyph is deliberately shown as its transient state example.

The active call is visually dominant through the 44px number, broad amber meter and 28px timer. Condition stays small and neutral, with its own short meter. Do not duplicate a large water/condition panel elsewhere. When no call is active, suppress stale fire-health values and use the game's between-call copy without inventing a countdown.

### Under-30-seconds state

Use the exact text `Time left 0:28, running out`, with live time substituted. At 1280, replace the normal timer area with a paper-tinted warning block at (20,124), 316x66, radius 5, fill #F0DDBE. The first line starts at (54,130), baseline 154, `Time left 0:28,`; the second at (54,158), baseline 182, `running out`. Both are 24px/800. Add an amber triangle with a 1px ink outline in a 20x18 box at (28,136), and an ink exclamation. Move the water label/value down to baselines 215 and its track to y226, keeping the divider at 244. This local reflow stays inside the original panel. The warning changes weight, icon and bounded shape, not just colour. It can coexist with any bottom prompt.

### Off-screen call arrow

Project the direction from screen centre to the active fire and intersect a rectangle inset 12px from the screen edges. Triangle tip is on that inset edge, with a 24px depth and 24px base, amber fill, 1.5px ink outline. Label Call is 16px/700 ink. Use a small opaque paper backing with radius 6 and1px ink border, padding8. The illustrated left-edge backing is (8,417),91x46; triangle points are (12,440), (36,428), (36,452); label baseline is (47,446). Its screen anchor is top-left with a computed edge offset; the shown offset is an example, not a fixed call bearing.

At the right/top/bottom edges mirror or rotate the triangle and move the label inward. Keep the backing out of the call panel, secondary panel and minimap, maintaining8px clearance. If no non-overlapping label placement exists, omit the word Call and show the triangle alone. Keep edge indication to the margin, never move it into the driving corridor. Hide the off-screen arrow as soon as the active target is visible. Do not show multiple call arrows.

### Minimap

The 200x150 panel includes its zoom control. Inside the map surface draw road centrelines in asphalt #706A60 with a 9px stroke in this reference, player position as a 7px engine-red disc, and the active call as a 10x10 amber triangle with1px ink outline. Scale the real road network to the current minimap extent and clip everything to the map surface. Exact road-line endpoints are data-dependent, not fixed UI coordinates. The diagram depicts the same T-junction shape as the supplied world view; it is not a complete Windsor map.

Keep north up. M shows/hides the entire minimap panel. N and the plus button change only the minimap's extent using the implementation's existing levels. The plus button has a fixed 32px hit rectangle at 1280 and960. The map itself has no click-to-drive action. The player dot and call marker must not be hidden behind the zoom button: reserve the button rectangle for controls when fitting or clipping marker presentation. A focused zoom control gets the shared focus ring within the panel padding. If N is pressed while the map is hidden, retain the game's chosen behavior rather than inventing a camera action.

## HUD at 960x540

Reflow these UI components instead of shrinking all type by 0.75. The world reference itself is scaled by 0.75 without changing its aspect ratio. Maintain the clear road corridor around x375..593,y0..240. All unspecified colours, border widths and radii remain identical to1280. Font overrides below are intentional; there is no universal text-size multiplier.

| Element | Anchor | Offset / size at 960 | Type / baseline |
|---|---|---|---|
| Active-call panel | top-left | (10,10),260x268 | No text |
| Accent | top-left | (10,24),4x90 | Amber |
| Fire label | top-left | (24,21),170x22 | 16/600; baseline37 |
| Fire value | top-left | (144,41),110x44 | 36/800; baseline77; right aligned |
| Fire track | top-left | (24,90),230x12 | Amber fill fraction |
| Normal timer | top-left | (24,126),230x30 | 23/800; baseline149 |
| Warning backing | top-left | (20,114),240x62 | #F0DDBE, radius 5 |
| Warning triangle | top-left | (22,126),18x16 | Amber, ink1 |
| Warning first / second line | top-left | (47,120)/(47,144),207x24 | 19/800; baselines139/163 |
| Water label / value | top-left | (24,185)/(134,183),100x22/120x24 | 16/600 and18/700; baseline201 |
| Water track | top-left | (24,211),230x8 | Blue fill fraction |
| Divider | top-left | (24,232),230x1 | Track |
| Condition label / value | top-left | (24,239)/(224,239),190x18/30x18 | 14/600 and14/700; baseline253 |
| Condition track, no contact | top-left | (24,261),230x5 | Neutral fill |
| Condition track during contact | top-left | (24,261),196x5 | Leaves room for glyph |
| Contact glyph during contact | top-left | (234,253),18x18 | 0.75-scaled glyph, no text |
| Secondary panel | top-right | (-194,10),182x114 | Paper and ink |
| Call count / credits / siren | top-right | (-178,22)/(-178,56)/(-178,86),150px wide | 18/700,16/500,16/600; baselines40/72/102 |
| Prompt backing | bottom-centre | (-240,-66),450x48 | Slight left bias clears minimap |
| Prompt text | bottom-centre | (-224,-56),418x28 | 18/700; centred; baseline504 |
| Minimap panel | bottom-right | (-184,-144),172x132 | Same styling |
| Minimap title | bottom-right | (-172,-134),148x18 | 14/700; baseline420 |
| Map surface | bottom-right | (-174,-110),152x88 | Yard |
| Zoom button | bottom-right | (-56,-58),32x32 | Same32px control |

The narrow PNG deliberately illustrates the warning timer and `Slow down to hook up` simultaneously. It shows no contact glyph, demonstrating the idle state of the condition footer. The arrow illustration uses backing (8,309),91x46, tip(12,332), with the same marker and font sizes as1280. Keep all eight prompt strings legible on one line at 18px inside the418px text box; do not clip or abbreviate unit counts.

## Prompt and condition-contact states

Prompt text is screen UI, anchored to the bottom-centre box above. It never follows a hydrant or floats over the engine. The empty state has no backing or text. Where driving direction would put the bottom prompt over the road immediately ahead, relocate it to an empty margin below the active-call panel with the same dimensions and wrapping, or use the available side margin at the smaller resolution. Do not put a status message between the engine and its upcoming turn. Prefer stable placement for the duration of a message; do not chase the vehicle frame by frame.

| Exact string | State presentation |
|---|---|
| Slow down to hook up | Show when the relevant hydrant is within eligible distance but speed prevents hookup; nearest ring stays dashed; standard ink prompt |
| Hooking up | Show during attachment progress; add a 3px-high blue progress strip along the prompt backing's bottom inside edge, inset 12 |
| Refilling, 64/100 units | Show actual current/capacity integers; blue prompt text, rising blue water meter; use125 when upgraded |
| Tank full | Show at capacity while still attached; add a 16x16 blue check at the prompt's left inset 16, leaving text centred in remaining width |
| Hose snapped | Show for approximately1.5 seconds after the existing attachment-break event; ink text and16x16 broken-link glyph, no automatic damage implication |
| Knocking it down | Show only during effective suppression; blue text and16x16 blue impact-disc glyph; follows actual absorbed damage |
| Refill needed | Show when empty and no higher-priority service state is active; retain empty water track with2px ink outline and an ink slash, not red colour alone |
| Time left 0:28, running out | Timer state inside the active-call panel, not a competing bottom message; exact comma and spacing; heavy two-line text plus triangle and bounded shape |

Status priority for the single prompt: recent hose snap, attachment/refill/full, refill needed, effective suppression, slow-down guidance, then hidden. The timer warning has its own dedicated area and stays visible concurrently. A contact glyph never takes over the prompt. These are presentation rules for states supplied by the implementation, not instructions to invent additional mechanics.

### Car-contact glyph

Idle: reserved space is empty. On an engine-to-car contact event, show for1.0 seconds, then hide with no fade requirement. A new distinct car-impact event restarts the one-second display; persistent overlap must not trigger the timer every render frame. The glyph has two small car-shaped outlines, each7x14 with radius 2, placed at local(0,6) and(17,6) inside a 24x24 box. Use ink1.5px outlines and an amber2px zigzag at local points(10,6),(14,10),(10,14),(14,18), plus a tiny ink impact tick at(11,1)..(11,3). No text, flashing border, screen takeover or sound is specified. At960 use an 18x18 scaled version and the narrower condition track above. Show contact whether or not the collision caused condition loss; display actual condition separately. Do not show it for buildings, kerbs or other contact categories unless the implementation request later extends its meaning. It is an acknowledgement of car contact, not a claim of injury or a new penalty.

## Home menu, 1280x720

| Element | Anchor | Offset / size | Colour / typography / state |
|---|---|---|---|
| Background | top-left | (0,0),1280x720 | Paper |
| Merged logo-wordmark image box | top-left | (96,120),720x288 | Unchanged merged reference, scaled uniformly from1200x480 |
| Start shift | top-left | (240,410),352x64 | Red/paper,22/700; text baseline450, centred |
| Data and credits | top-left | (240,490),352x64 | Paper/ink,22/700; baseline530 |
| Quit | top-left | (240,570),352x64 | Paper/ink,22/700; baseline610 |
| Decorative diagram region | top-right | (-416,0),416x720 | Yard; clip to region |
| Vertical sidewalk base | top-left | (990,0),168x720 | Sidewalk |
| Vertical asphalt | top-left | (1004,0),140x720 | Asphalt |
| Junction sidewalk arm | top-left | (1070,296),210x140 | Sidewalk; union beneath asphalt |
| Junction asphalt arm | top-left | (1070,310),210x112 | Asphalt; union with vertical asphalt |
| Lane dashes | top-left | x1074, starts y16 then every64 | 2px paper strokes,28px long; omit within junction mouth |
| Decorative engine | top-left | (1030,451),20x45 body | Red, radius 2; 0.5px per world unit |

The logo image includes both mark and exact Tailboard wordmark. Do not add a second title below it. For code text use the approved Archivo800 letterforms, with the retained logo section as the geometry reference. The screenshot export places the accepted raster unchanged at the given box; small source colour variation is not a new effect.

Five roofs in the decorative region: (886,60),82x96 sand; (886,240),82x106 slate; (886,474),82x114 clay; (1174,52),88x122 sage; (1174,498),88x136 stone. Each gets a same-size flat eave polygon offset(3,3) behind it and a 1.5px ridge through its horizontal midpoint, inset 8px top/bottom. All anchors are top-left. No house fronts, window walls or realistic roof texture. The decorative engine windscreen is(1033,457),14x7; equipment(1035,480),10x11; turret circle centre(1040,473),radius 3; barrel to(1040,467),2px equipment; four ink3x7 wheels at x1028/1049,y458/484. These are menu illustration pixels; playable world proportions remain in world units below.

At960x540 scale the home composition uniformly by 0.75, including spacing and logo box; override button text to18px if the font rasterizer rounds22x0.75 too small. Buttons become264x48. Focus outline remains at least2px. The diagram is decorative and never responds to menu navigation. All three buttons use the shared states, and the first is keyboard-focused on entry.

## Controls and copy

Where controls are listed, use these mappings exactly:

| Keys | Meaning |
|---|---|
| W/S | Accelerate, brake, reverse |
| A/D | Steer |
| Space | Handbrake |
| Q | Siren |
| Z | Camera zoom |
| M | Minimap |
| N | Minimap zoom |
| Escape | Pause |

The turret and hydrant interactions are automatic. Their state prompts do not advertise an action key. The camera remains north up. Keep camera zoom and minimap zoom as separate labels and controls.

## World-art specification

World art is code-drawn and uses game units. UI pixel widths below are explicitly called screen pixels; they do not change collision geometry. Never redraw imported streets as a new grid or change the road/building scale to fit a composition. Engine length90, width 40; residential asphalt280. Preserve the repository's map topology and adjusted building footprints.

### Engine

Facing local north, footprint40 wide by 90 long including wheels. Body32x86, centred, engine red with a 2-unit ink boundary where needed. Four wheel rectangles4x14, centred at x plus/minus18, y plus/minus25. Cab32x23 occupies the front quarter; windshield24x9 is a flat #44565D rectangle inset 4 from cab sides. A cream2-unit front bumper and two7x4 warning lamps distinguish the front. Mid-body turret is an ink circle radius 6, with a 3x12 equipment barrel rotated toward the model's target. Rear equipment/ladder uses an 18x32 equipment panel, two2-unit rails and at most three2-unit crossbars. Tailboard is a cream32x5 rectangle integrated with the rear, not a detached box. Lamp off uses #8B7267; on uses amber and paper solid rectangles, no halo. Keep the existing axle configuration if it is part of the actual approved engine rather than introducing physics changes from art. At distant zoom omit ladder crossbars before enlarging the truck.

### Hydrant, ring and hose

Hydrant silhouette18x22: red body10x14, domed top radius 5, cap/collar14x3, foot16x3, side ports4x5. The hose attaches to an uncapped side outlet, never to the crown. Body and fittings need at most1-unit ink edges. Hose is a blue polyline with rounded bends,3 screen pixels at 1280, minimum2 at 960, a short equipment-colour coupling at each endpoint. Its path follows the attachment model; it does not define a second reach rule.

Only the relevant nearby hydrant shows a ring. Ring radius comes from actual interaction reach. Width2 screen pixels; out-of-range or moving-too-fast state has12px dashes and8px gaps; eligible/attached is solid. Use blue with restrained opacity if needed to avoid obscuring road markings. Prompts stay in the HUD. Hookup extends the hose, attached/refilling keeps it continuous, snap briefly shows separated ends before the hose disappears. Do not display a permanent ring around every hydrant.

### Water, impact and steam

Stream: blue4px screen-space outer line plus paper1.5px core at 1280, narrowed to3/1 at 960; no bloom. Start at roof-barrel tip and stop at the actual hit location. Impact: three to five small blue discs, radius 3..7px, inside a 16px footprint, with two paper core discs radius 2..3. Steam during effective suppression: four to six paper discs radius 5..12px, concentrated at impact; maximum burst footprint40px. Plain wall/water hits show impact without the dense steam response. Art only follows existing hit results.

### Burning building

Keep roof geometry visible. At full health use up to six edge fire clusters, half health three, nearly-out one. Each cluster has an outer red rounded polygon or disc of about12..18 world units and an amber core around60% that size. Do not scale an enormous flame over the whole roof. Smoke uses #A8A398 discs with maximum opacity35%, at most four visible, drifting away from the targeted edge; smoke must not cover the whole target. Extinguished state removes fire and smoke. Fire-health UI stays in the dominant call panel; if the existing game retains an in-world health meter, make it a small secondary80x8px meter and keep it over the roof, never in the road corridor.

On-screen active-call marker: amber28px diamond with ink2px outline and cream centre, anchored to a clear roof/yard position, not floating over asphalt. At smaller resolution it may reduce to22px, while stroke stays at least1.5px. Off-screen use the edge arrow already specified, not an additional marker.

### Roads, roofs and street labels

Road fill asphalt, sidewalks #D9D1C4, kerb #B9AFA0, yard #B9C2A0 and alternate #C9CDB7. Road widths follow the game,280 for residential streets. Kerb line3 world units, fence2. Use real road tangent/junction geometry. The home drawing is a simplified exception, not a map-data reference.

One of five roof fills is chosen stably per building ID. Draw the actual footprint, an ink or roof-line1.5-unit outline, a 2-unit ridge along its longest axis, and one eave polygon offset3 world units in #8D887B. Driveway28 units wide, length determined by actual setback and frontage; no driveway through a neighbour. Use the palette table's sand/slate/clay/sage/stone values.

Street labels are Archivo600,18 world units nominal, paper, aligned to local street tangent and flipped for upright readability. No drop shadow, outline or name plaque. Hide when projected type is below12 screen pixels instead of expanding over nearby roofs. Keep labels at least50 world units from junction mouths, one per street name unless existing long-road rules justify another. Actual names come from map data. These labels belong to asphalt artwork, not a floating HUD.

### Barricades and junction controls

Map-edge barricade spans the closed road, thickness12 world units, alternating red/paper sections each24 units, supported by two ink posts. Show only where the playable boundary closes a road. DEAD END sign is an amber48x32 rectangle with ink2-unit outline, two-line uppercase lettering, and4x18 ink post, facing approaching traffic. STOP and DEAD END retain the explicitly requested sign capitalization.

Signal head: ink12x30 rounded rectangle, three lamps radius 3 at y6,15,24. Active lamp uses red #C8362B, amber #E0972B or muted green #759365 as appropriate to the model; inactive lamps use #665E55. Exactly one active lamp per normal phase, no glow. Stop sign: red18x18 octagon, paper2-unit border, STOP only when the sign is at least18px wide on screen. Post3x12. Stop bar is a paper4-unit strip across the entering lane. Follow existing junction-control data rather than displaying stop signs and signals indiscriminately on the same approach.

### Civilian vehicles

Lengths and overall widths include tires: hatchback36x18, sedan42x19, wagon46x19, SUV46x22, pickup48x21, van47x22. Bodies are inset 2 units from full tire width, radius 3 or4. Four ink tires2.5x7 sit at x plus/minus(width/2 -1.25), y plus/minus(length*0.29). Windscreen65% of body width,5 units deep, centred y=-0.23*length, flat glass fill. Rear glass55% body width,4 deep, at y=0.31*length, omitted on pickup/van. Pickup bed occupies rear36%, with2-unit body-colour border and dark bed fill; van has a continuous roof behind cab. Wagon's longer roof and SUV's wider cabin distinguish them. Two cream2x1.5 front lamps and muted-red rear lamps, no chrome, badges or tiny plates. Below20px projected length omit lamps and extra roof lines, retaining body/glass/wheels/bed. Rotate whole model; do not rotate the map.

### Pedestrians

Shared directly overhead model,18x20-unit footprint. Shoulder rectangle14x8, radius 3, at(-7,-3); head radius 4 at(0,-4), flat hair circle radius 3.6; two3x6 arm capsules at x plus/minus7.5,y1; two3x5 ink shoes at x plus/minus3.5,y6. No faces, eyes or upright body illustrations. Eight combinations: blue jacket/dark hair; sage/light hair; clay/deep skin/dark hair; cream/brown hair; plum/light hair; slate hoodie; ochre/grey hair; navy cap. Use the palette's clothing, skin and hair values. Hoodie adds a 4.5-radius clothing disc with smaller dark inset; cap adds a 5x2 forward brim. At less than8px wide omit hands/feet and retain shoulders/head. Art variants do not establish movement behavior, injury rules or collision consequences.

## Shift and upgrade presentation

Three calls per shift. Call pay is100 credits per completed call; completed-shift bonus50 credits on its own line. Earned call pay survives a failed shift. Show calls cleared and pay separately, the shift bonus separately even when zero, and Total banked as the actual wallet balance including previous earnings. Display values from the implementation, never infer balances from the artwork.

Tank capacity upgrade is100 to125 units for200 credits, bought once. Purchase button shows Buy, Owned or Not enough credits. Owned takes precedence over insufficient balance. The latter two states are disabled but visible, with shared disabled styling. Water meters and Refilling prompts use actual upgraded capacity. This visual specification adds no new economy rules.
