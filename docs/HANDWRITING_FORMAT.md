# Versely Ink: handwritten pages on iPhone, iPad and Android

One format for a note's handwritten page, so a page written on an iPhone
opens and can be edited on Android and the other way round (owner's choice,
27 November 2026). It's JSON text, kept in `public.notes.ink`
(migration 20261129000000_note_ink.sql, at most 2 MB like `drawing`).

```json
{
  "format": "versely-ink",
  "version": 1,
  "width": 768,
  "strokes": [
    { "ink": "pen", "color": "1C1C1EFF", "points": [[120.5, 88, 3.2, 1], [124, 90.1, 3.4, 1]] }
  ]
}
```

- `width`: the page's width in points (`HandwritingLayout.pageWidth`, 768).
  Points are in that space, y down from the top; each app scales the page
  to its own width and lets it grow downwards.
- `ink`: `pen`, `pencil`, `marker`, `monoline`, `fountainPen`,
  `watercolor` or `crayon` (PencilKit's ink types). An app that doesn't
  know a type draws it as `pen`.
- `color`: sRGB `RRGGBBAA`, the ink's colour on light paper. On dark paper
  both apps lighten dark ink as PencilKit does.
- `points`: `[x, y, size, opacity]`, the stroke's control points: a
  uniform cubic B-spline, exactly PencilKit's `PKStrokePath`. `size` is the
  nib's width at that point (pressure already applied), `opacity` 0 to 1.
  A stroke of one point is a dot. Writers repeat the first and last points
  twice more so the line reaches both ends. Numbers are rounded to two
  decimals.
- Strokes are drawn in order, later strokes over earlier ones. There is no
  transform: a moved or erased stroke is written as it looks (PencilKit's
  transform applied, erased parts left out as separate strokes).

## Sync

- `notes.ink` is what every app reads first. `notes.drawing` (PencilKit's
  data, base64) stays for iPhones on older versions: Versely on iOS writes
  both; Android writes `ink` and sets `drawing` to null, since it can't
  write PencilKit's data.
- iOS reads `drawing` when it's there (it's lossless and came with the
  same save as `ink`), else builds the page from `ink`. Pages saved before
  `ink` existed get it on the next launch (`NoteInkBackfill`).
- Android reads `ink`; a page with only `drawing` (not yet opened on an
  updated iPhone) shows a note saying so.

The cases both apps test against are in
supabase/functions/_shared/fixtures/ink.json.
