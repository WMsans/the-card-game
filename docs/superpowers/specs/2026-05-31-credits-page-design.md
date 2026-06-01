# Credits Page Design

## Overview

A full-screen credits panel that displays artist names (extracted from deck CSVs)
in a movie-credits-style auto-scrolling roll. The credit data lives in a plain
`.txt` file so it's trivial to update by hand.

## Data: `src/data/credits.txt`

- One artist per line, no duplicates.
- Initial content extracted from the **Image** column of the 4 deck CSVs
  (`strike.csv`, `writing.csv`, `raccoon.csv`, `audio.csv`). Values that are
  image file paths, empty, or `^^^` are skipped.
- Initial artists: `Quin`, `Samuel Gines`, `Alexander C`, `henri`, `melina`
  (5 unique).

## Scene: `src/ui/shell/credits_panel.tscn` (modify existing)

- **Root**: `CreditsPanel` (Control, full-screen anchors)
- **Back button** (`%Back`): stays as-is, on top so always clickable
- **RichTextLabel**: added as child, fills the width of the screen, positioned
  to start below the viewport. Uses BBcode or plain text with `\n` spacing.
  `horizontal_alignment = CENTER`.

## Script: `src/ui/shell/credits_panel.gd` (modify existing)

- `_ready()`:
  1. Reads `res://src/data/credits.txt` via `FileAccess`.
  2. Builds a formatted string (title "Artists" + names with spacing).
  3. Sets the string on the RichTextLabel.
  4. Starts a looping Tween that animates `position.y` from below-screen
     to above-screen over ~15 seconds. When the tween ends, reset position
     and restart (loop).
- The Back button already emits `back_pressed` and works at any time.

## Integration

No changes needed to `app_shell.gd` — it already wires `goto_credits()` which
mounts the `CREDITS` scene. Navigating back returns to landing.

## Testing

- Load the credits panel and verify the artists list renders.
- Verify the text auto-scrolls upward and loops.
- Verify the Back button is clickable during scrolling and returns to landing.
