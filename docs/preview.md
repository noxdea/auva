---
layout: guide
title: Preview and export
description: Compare built-in themes, render preview categories, and export eight PNG sheets.
---

## Open the color preview

Run a token file in an interactive terminal:

```sh
auva tokens.jsonc
```

The CLI opens the `colors` category in a native window. It selects the
macOS, Windows, or Linux backend from your platform. If a native window is
unavailable, Auva prints the reason and reports that the theme was loaded.

You can also inspect a built-in theme without a file:

```sh
auva --builtin light
```

## Compare built-in themes

```sh
auva --themes dark,light,high_contrast
```

Click a theme tab to switch the displayed theme. `--themes` selects built-in
themes instead of loading a token file. These tabs switch themes; they do
not switch preview categories.

## Export all sheets

```sh
auva tokens.jsonc --export theme-sheets
```

Auva creates the directory and writes these eight 800 × 480 PNG files:

| File | Contents |
| --- | --- |
| `colors.png` | Color swatches |
| `typography.png` | Samples across the font-size scale |
| `spacing.png` | Bars for the first eight entries in the sorted spacing scale |
| `radii.png` | Rounded rectangles for named radii |
| `shadows.png` | Samples for named shadows |
| `motion.png` | Duration, easing, and reduced-motion values |
| `buttons.png` | Primary, secondary, danger, and disabled buttons |
| `components.png` | The visible portion of a scrollable component gallery |

The files are static previews. Motion is disabled for rendering, and a sheet
shows only the content that fits its viewport; it is not a capture of an
entire scrollable view. Exporting again overwrites the same filenames.

Compare multiple built-ins with a subdirectory for each theme:

```sh
auva --themes dark,light,high_contrast --export theme-sheets
```

This writes `theme-sheets/dark/colors.png`,
`theme-sheets/light/colors.png`, and the other sheets under their respective
theme directories.

## Preview another category with Ruby

The CLI has no category-selection option. Save this as `preview.rb` to open
the component gallery:

```ruby
require "auva"

theme = Auva.load("tokens.jsonc")
Auva::Preview.show(theme, category: :components)
```

```sh
ruby preview.rb
```

Use `:colors`, `:typography`, `:spacing`, `:radii`, `:shadows`, `:motion`,
`:buttons`, or `:components`. Scroll longer category views to inspect more
samples.

To render a category without a desktop window:

```ruby
require "auva"

theme = Auva.load("tokens.jsonc")
png = Auva::Preview.render(theme, category: :typography, width: 1000, height: 700)
File.binwrite("typography.png", png)
Auva::Preview.render_all(theme, "theme-sheets")
```

`Preview.show` does not watch a file unless you pass a watcher:

```ruby
require "auva"

theme = Auva.load("tokens.jsonc")
watcher = Auva::Watcher.new("tokens.jsonc", theme: theme)
Auva::Preview.show(theme, category: :buttons, watcher: watcher)
```

## Watch a token file

The CLI's native file preview watches automatically. A valid save updates the
theme; an invalid save leaves the previous valid theme visible. Run a
separate `auva tokens.jsonc --check` to see a validation error.

For watching outside the native window:

```sh
auva tokens.jsonc --check --watch
```

The initial check runs once, then Auva waits for file changes and prints
`auva: updated` after valid reloads. Watching does not repeat contrast checks
or regenerate exports. Stop it with Ctrl+C and rerun the check or export
command after editing.

In the current CLI, `--no-watch` disables this explicit `--watch` loop;
the native file preview still watches automatically.

Next: [Contrast checks](contrast.md).
