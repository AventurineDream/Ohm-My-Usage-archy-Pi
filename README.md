# Ohm-My-Usage-archy-Pi

OMP provider usage in the Omarchy bar. See a chosen provider's current limit at a glance, then open the panel for every provider's usage windows and reset countdowns. Current version: 0.4.1.

![Ohm-My-Usage-archy-Pi bar widget with example usage](screenshots/bar-widget.png)

## Highlights

- Reads the JSON output from `omp usage --json`.
- Select a provider or use Auto to show the most-used limit.
- Choose the `5h` or `7d` usage window and display either usage or remaining capacity.
- Show the provider label, percentage, both, or neither in the bar.
- Browse provider details in a compact, collapsible panel with optional progress bars.
- Reorder providers by dragging; collapse state and order persist locally.
- Refresh on demand or on a configurable interval; a failed refresh keeps the last good values and marks them stale.
- The bar's tone follows the number: the theme accent normally, dim red once a limit reaches 90%, and full red when a limit is exhausted.

## Requirements

- Omarchy Quattro
- The `omp` command from [Oh My Pi](https://github.com/can1357/oh-my-pi) on `PATH`, with at least one authenticated provider. The plugin reads `omp usage --json` and nothing else; it has no provider-authentication flow of its own.

## Install

```bash
omarchy plugin add https://github.com/AventurineDream/Ohm-My-Usage-archy-Pi.git --enable
```

## Use

The bar shows the configured provider's usage. In Auto mode, it chooses the available limit with the highest usage. Left-click opens the provider panel; right-click requests an immediate refresh.

The panel starts with the first two providers expanded and the remaining providers collapsed. Click a provider heading to expand or collapse it. Drag the grip to change the order; newly appearing providers are added at the end. These choices are saved in `~/.config/omarchy/omp-usage-state.json` and do not change which provider is shown in the bar.

![Provider panel with usage windows, reset countdowns, and detail controls](screenshots/providers-panel.png)

*Screenshots use deterministic sample provider data; displayed values are illustrative.*

## Settings

The panel's Settings section and Omarchy plugin settings expose the following options:

| Option | Values and purpose |
|---|---|
| `provider` | OMP provider ID shown in the bar (e.g. `anthropic`, `openai-codex`, `devin`). Defaults to `anthropic`; choose Auto (an empty value) to follow whichever provider is most used. |
| `barWindow` | Which limit window the bar shows: `auto` (the default; the most-used available limit), `5h`, or `7d`. |
| `showAs` | `used` or `left`. |
| `showProvider` | Include the provider's short name in the bar. |
| `showBarValue` | Include the numeric usage value. |
| `showPanelBars` | Show/hide progress bars in the panel. |
| `refreshIntervalSec` | Seconds between `omp usage` polls while the panel is open; default 300. With the panel closed it polls at half that rate (every 10 minutes by default). |

If a refresh fails, the widget retains the last successful values and marks them stale instead of replacing them with empty data. Each consecutive failure doubles the poll interval (capped at 30 minutes); the next success restores the normal cadence.

## Uninstall

```bash
omarchy plugin remove aven.omp-usage
```

Your provider order and expand/collapse choices live in `~/.config/omarchy/omp-usage-state.json`; delete it by hand if you want them gone.

## Changelog

### 0.4.1

- The bar readout uses the theme accent colour normally, dim red at 90% or more, and full red when a limit is exhausted.
- Panel fix: a drag that ended while a poll landed no longer throws a `ReferenceError` and loses the pending report.
- Panel hardening: correct reset timing and remaining-use display, and report when saved layout state can't be read or written.

### 0.4.0

- Drag to sort: reorder providers by the ⠿ grip; the order is saved and survives refetches.

### 0.3.0

- Settings section in the panel (provider, bar window, show-as, bar value, panel bars).
- Collapsible providers (first two expanded); expand/collapse state persists across panel opens.

### 0.2.0

- Default poll interval 5 minutes, halved while the panel is closed, with exponential back-off on failures; fetches immediately on panel open when the data is stale.

## Development

Run the model tests with Node.js:

```bash
node test/OmpUsageModel.test.js
```

## License

MIT. See [LICENSE](LICENSE).
