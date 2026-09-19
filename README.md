# Auva

JSONC design-token loading and deterministic theme sheets for Zaniah. Auva
validates token names from Zaniah's own `members`, reports source lines, and
checks WCAG contrast ratios.

## Installation

```sh
gem install auva
```

## Usage

```sh
auva tokens.jsonc --check --strict
auva --builtin dark --export public/theme
```

The export directory contains deterministic `colors.png`, `typography.png`,
`spacing.png`, `radii.png`, `shadows.png`, `motion.png`, `buttons.png`, and
`components.png` sheets. Library
consumers can load a theme with `Auva.load("tokens.jsonc")`.

Supported token categories are `extends`, `colors`, `typography`, `spacing`,
`radii`, `shadows`, and `motion`; unknown names fail with a line number.

## Development

Run `rake spec` and `gem build --strict auva.gemspec`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/noxdea/auva.

## License

MIT.
