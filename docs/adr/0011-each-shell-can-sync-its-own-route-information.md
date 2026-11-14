---
status: accepted
---

# Each shell can sync its own route information

Extends ADR 0003. `WindowingLinkSync` reports the focused shell's focused
buffer to one `RouteInformationProvider`. An app with an address bar per
platform window needs one URL per shell.

## Decision

- `WindowingLinkSync` takes an optional `shell`. With it, the sync reports
  that shell's active window, and a route notification from its provider
  opens the link in that shell. Without it, it follows the focused shell, as
  today, so the web platform keeps one sync over the browser URL.
- Push or replace reporting (spec §9) is decided per shell, from that shell's
  active window's history.
- Browser entry state (ADR 0004 D2) stays web-only and only on the
  shell-less sync.

## Considered options

- **The app reads the doc and draws the bar itself.** Rejected: the app
  would rewrite reef's URL sync, which is what the integration app tests.
- **One sync that reports a URL per shell.** Rejected: a
  `RouteInformationProvider` holds one URL; a map of them is not that API.

## Consequences

- A shell's sync must be removed when the shell closes; it is placed inside
  the shell's widget subtree, so it goes with it.
- Tests use one fake provider per shell.
