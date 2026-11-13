# Ohm-My-Usage-archy-Pi

Live OMP (Oh My Pi) provider usage in the Omarchy bar.

The bar shows your primary provider's usage — by default, whichever limit is highest (auto). The panel shows every provider's limits with a progress bar and a reset countdown, mirroring `omp usage`.

## Why this exists

The usual usage bar (`ai-usagebar`) is a big multi-provider tool that needs its own Rust binary plus per-vendor auth for every provider. OMP already does all of that: `omp usage --json` hands back clean, machine-readable limits for every authenticated account. This plugin is just a thin shell around that — no binary, no auth plumbing, nothing to go stale.

## Install

```bash
omarchy plugin add https://github.com/AventurineDream/Ohm-My-Usage-archy-Pi.git --enable
```

Requires `omp` on your PATH (Oh My Pi). The widget polls `omp usage --json` on a timer; the interval is configurable.

## Settings

- **Primary provider** — the provider id from `omp usage --json` shown in the bar (e.g. `anthropic`, `openai-codex`, `devin`). Blank falls back to whichever provider is most used.
- **Top bar usage window** — `auto` (highest percent), `5h`, or `7d`.
- **Show usage as** — `used` or `left`.
- **Show provider name** — prefix the bar value with the provider's short code.
- **Refresh interval** — seconds between `omp usage` polls (default 120).

Left-click opens the panel. Right-click refreshes now. A failed fetch keeps the last good numbers on screen, marked stale, instead of blanking the bar.

## Development

The model (`OmpUsageModel.js`) is pure functions over the `omp usage --json` shape, with a node harness:

```bash
node test/OmpUsageModel.test.js
```

## License

MIT
