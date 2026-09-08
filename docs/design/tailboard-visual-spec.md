# Tailboard visual specification

Version 2.1 | Logo specification

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
