---
layout: guide
title: Contrast checks
description: Read AA and AAA results and use strict contrast checks in a script.
---

## Run a check

```sh
auva tokens.jsonc --check
```

Each output line names a foreground/background pair, its contrast ratio,
and its highest passing level. For example, the built-in light theme reports:

```text
text / background: 17.06:1 AAA
text_muted / background: 7.24:1 AAA
text / surface: 17.85:1 AAA
accent_text / accent: 6.70:1 AA
text_inverse / accent: 6.70:1 AA
text / surface_hover: 16.30:1 AAA
```

```sh
auva --builtin light --check
auva --themes dark,light,high_contrast --check
```

With multiple themes, results are printed in the order supplied to
`--themes`. Run themes separately if you want each report clearly named.

## Understand the thresholds

| Result | Contrast ratio |
| --- | --- |
| `AAA` | At least 7:1 |
| `AA` | At least 4.5:1, below 7:1 |
| `FAIL` | Below 4.5:1 |

Auva uses the normal-text thresholds for every checked pair. It does not
apply the lower thresholds for large text, test every UI state, or check
syntax-token colors. These reports cover selected colors, not full WCAG
compliance for an application.

The six default pairs are:

| Foreground | Background |
| --- | --- |
| `text` | `background` |
| `text_muted` | `background` |
| `text` | `surface` |
| `accent_text` | `accent` |
| `text_inverse` | `accent` |
| `text` | `surface_hover` |

A built-in theme can fail a checked pair. For example, the dark preset's
`text_inverse / accent` ratio is approximately 2.90:1. Check inherited colors
as well as your overrides, and choose foreground/background colors that fit
their intended use.

## Fail a script when AA is missed

```sh
auva tokens.jsonc --check --strict
```

`--strict` also prints the check results on its own. It returns exit status
`1` if any default pair fails AA and `0` when all pass. Missing files, parse
errors, and token validation errors also return `1`.

`--check` alone returns `0` for a valid theme even if a pair says `FAIL`.
A pair that passes AA but misses AAA does not fail `--strict`.

You can export sheets and check them in the same command:

```sh
auva tokens.jsonc --export theme-sheets --strict
```

Sheets are written before the final exit status is returned, including when
contrast fails. Check the status before treating an export as approved.

## Use the Ruby API

```ruby
require "auva"

theme = Auva.load("tokens.jsonc")
Auva.contrast(theme).each do |result|
  puts "#{result.pair}: #{result.ratio.round(2)} AA=#{result.aa} AAA=#{result.aaa}"
end
```

The API also accepts custom pairs of `colors` member names:

```ruby
Auva.contrast(theme, pairs: [["text", "surface_pressed"]])
```

## Transparent colors

The contrast calculation uses each color's RGB channels and ignores alpha.
It does not composite transparent foregrounds or backgrounds over another
surface. For example, opaque `#000000` and transparent `#00000000` produce
the same reported ratio against white.

Use opaque colors for these checks, or first calculate the final displayed
colors for the actual background. Inspect transparent overlays in the
[preview](preview.md) as well.
