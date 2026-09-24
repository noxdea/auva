<h1 align="center">Auva</h1>

<p align="center">
  <strong>JSONC design-token loader and deterministic theme sheets for Zaniah.</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/auva"><img src="https://img.shields.io/gem/v/auva?style=flat-square" alt="Gem version"></a>
  <a href="https://rubygems.org/gems/auva"><img src="https://img.shields.io/gem/dt/auva?style=flat-square" alt="Gem downloads"></a>
  <a href="https://github.com/noxdea/auva/actions/workflows/main.yml"><img src="https://github.com/noxdea/auva/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.2-CC342D?style=flat-square" alt="Ruby 3.2 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#token-format">Token format</a> ·
  <a href="#cli">CLI</a> ·
  <a href="#ruby-api">Ruby API</a>
</p>

---

Auva is a JSONC design-token loader and deterministic theme-sheet generator
for [Zaniah](https://github.com/noxdea/zaniah). It validates tokens against
Zaniah's own theme members, reports source locations, and checks WCAG contrast.

## Features

- **JSONC tokens** — comments and trailing commas are accepted.
- **Built-in inheritance** — extend `dark`, `light`, or `high_contrast`.
- **Strict validation** — unknown categories, tokens, and values fail with a source line and path.
- **WCAG checks** — report AA and AAA contrast for essential color pairs.
- **Native preview** — inspect colors, typography, spacing, radii, shadows, motion, buttons, and components.
- **Live reload** — update the preview as a token file changes.
- **Deterministic sheets** — export all eight preview categories as PNG files.

## Installation

```bash
gem install auva
```

Auva requires Ruby 3.2 or newer.

## Quick start

Create `tokens.jsonc`:

```jsonc
{
  // Start from a complete Zaniah theme.
  "extends": "light",
  "colors": {
    "accent": "#245b9b"
  },
  "syntax": {
    "keyword": "#7c3aed",
    "string": "#15803d"
  },
  "motion": {
    "reduced": true
  }
}
```

Open the native preview:

```bash
auva tokens.jsonc
```

Check contrast and fail when any required pair misses WCAG AA:

```bash
auva tokens.jsonc --check --strict
```

## Token format

| Category | Description |
|---|---|
| `extends` | Base theme: `dark`, `light`, `high_contrast`, or `none` |
| `colors` | Zaniah color members such as `accent` and `background` |
| `syntax` | Code-editor colors: `keyword`, `string`, `comment`, `number`, `function`, `type`, `constant`, `punctuation`, `operator`, `variable`, `text` |
| `typography` | Font families, sizes, and related type tokens |
| `spacing` | Numeric spacing scale entries |
| `radii` | Named border radii |
| `shadows` | Named shadows with validated members |
| `motion` | Durations, easing values, and reduced-motion preference |

Unspecified values remain inherited from the selected base theme.
`syntax` requires a Zaniah theme with `Theme::Syntax` support; token files
without it remain compatible with older Zaniah versions.

## CLI

Export every preview sheet:

```bash
auva tokens.jsonc --export public/theme
```

The directory contains `colors.png`, `typography.png`, `spacing.png`,
`radii.png`, `shadows.png`, `motion.png`, `buttons.png`, and `components.png`.

| Option | Description |
|---|---|
| `--builtin NAME` | Use `dark`, `light`, or `high_contrast` without a token file |
| `--themes NAMES` | Preview or export comma-separated built-in themes |
| `--check` | Print contrast ratios |
| `--strict` | Exit with failure when WCAG AA is not met |
| `--export DIR` | Write deterministic PNG sheets |
| `--watch` | Watch a token file outside the native preview |
| `--no-watch` | Disable watching |

## Ruby API

```ruby
require "auva"

theme = Auva.load("tokens.jsonc")
results = Auva.contrast(theme)
Auva::Preview.render_all(theme, "public/theme")
```

## Development

```bash
bundle install
bundle exec rake
bundle exec rbs -I sig validate
gem build --strict auva.gemspec
```

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/noxdea/auva).

## License

Auva is available under the [MIT License](LICENSE.txt).
