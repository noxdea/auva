---
layout: guide
title: Design tokens
description: Choose a base theme and override Zaniah's color, typography, spacing, and motion tokens.
---

A token file is a JSONC object. Auva accepts comments and trailing commas,
then validates the category names, member names, and value types against
the installed Zaniah theme.

## Choose a base theme

Set `extends` to `dark`, `light`, or `high_contrast`. The spelling
`high-contrast` is also accepted. If you omit `extends`, Auva starts from
`dark`.

```jsonc
{
  "extends": "light",
  "colors": {
    "accent": "#245b9b",
  },
}
```

Only the supplied tokens change. `extends: "none"` is accepted, but currently
also starts from the dark theme; it does not create an empty theme. Inheritance
selects a built-in theme, not another token file.

## Colors and syntax

Use hex colors in the forms `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA`.
In eight-digit colors, the last two digits are alpha: `#00000080` is
approximately half-transparent black.

The `colors` members are:

| Purpose | Members |
| --- | --- |
| Surfaces | `background`, `surface`, `surface_hover`, `surface_pressed` |
| Borders and focus | `border`, `border_focus`, `ring` |
| Text | `text`, `text_muted`, `text_inverse` |
| Accent | `accent`, `accent_hover`, `accent_text` |
| Status | `success`, `warning`, `danger`, `info` |
| Overlays and selection | `overlay_scrim`, `selection` |

Code-editor colors belong in `syntax`:

```jsonc
{
  "extends": "light",
  "syntax": {
    "keyword": "#7c3aed",
    "string": "#15803d",
    "comment": "#475569"
  }
}
```

The available syntax members are `keyword`, `string`, `comment`, `number`,
`function`, `type`, `constant`, `punctuation`, `operator`, `variable`, and
`text`. They require an installed Zaniah theme with `Theme::Syntax` support.

## Typography

`font_sans` and `font_mono` take strings. All other typography members take
numbers:

| Group | Members |
| --- | --- |
| Size | `size_xs`, `size_sm`, `size_md`, `size_lg`, `size_xl`, `size_2xl` |
| Weight | `weight_normal`, `weight_medium`, `weight_semibold`, `weight_bold` |
| Line height | `line_height_tight`, `line_height_normal`, `line_height_relaxed` |

```jsonc
{
  "typography": {
    "font_sans": "sans-serif",
    "font_mono": "monospace",
    "size_md": 16,
    "line_height_normal": 1.5
  }
}
```

## Spacing, radii, and shadows

`spacing` maps integer keys, written as JSON strings, to numeric values.
Existing entries are overridden; additional integer keys are allowed.
The built-in scale has keys `0`, `1`, `2`, `3`, `4`, `5`, `6`, `8`, `10`,
`12`, and `16`.

`radii` accepts the names `none`, `sm`, `md`, `lg`, and `full`, with numeric
values. Shadows accept `sm`, `md`, and `lg`. Each shadow can override
numeric `x`, `y`, `blur`, and `spread`; a `color`; and boolean `inset`.

```jsonc
{
  "spacing": {
    "4": 18,
    "7": 28
  },
  "radii": {
    "md": 10
  },
  "shadows": {
    "md": {
      "y": 4,
      "blur": 12,
      "color": "#00000040",
      "inset": false
    }
  }
}
```

Unspecified shadow members remain inherited.

## Motion

Durations are numbers in seconds. Use `linear`, `ease_in`, `ease_out`, or
`ease_in_out` for easing, and a JSON boolean for `reduced`:

```jsonc
{
  "motion": {
    "duration_fast": 0.1,
    "duration_base": 0.2,
    "duration_slow": 0.3,
    "easing_standard": "ease_in_out",
    "easing_decelerate": "ease_out",
    "easing_accelerate": "ease_in",
    "reduced": true
  }
}
```

Auva checks easing value types when loading, but does not check that an easing
name exists. Use the supported names above. Numeric tokens are type-checked;
Auva does not enforce sensible size or duration ranges.

## Read validation errors

Every category other than `extends` must be an object. Unknown categories,
unknown members, and incompatible values fail loading. For example:

```jsonc
{
  "colors": { "accnet": "#245b9b" }
}
```

```text
auva: unknown token: accnet (line 2: colors.accnet)
```

Correct the named token and run `auva tokens.jsonc --check` again.

Next: [Preview and export](preview.md).
