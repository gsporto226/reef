---
status: accepted
---

# The link adapter uses Flutter's route information API, no third-party router

Windowing draws every page through the app's buffer builder
(`packages/reef/docs/specs/2026-09-02-windowing-design.md` §5). What reef
needs from the URL is narrow: report the focused buffer's path, and hand the
initial route and browser back and forward to `openLink` (spec §9). The
`reef_router` package does this with one widget over a
`RouteInformationProvider`, the platform one by default. It uses no `Router`
widget, no route parser and no page stack, and it depends on Flutter and reef
only. It replaces the empty `reef_auto_route` package.

## Considered options

- **Rebuild the adapter on auto_route.** Rejected: the router's page stack
  and guards would go unused, because windowing already decides what is on
  screen. The app would carry a router dependency only to read and write the
  URL.
- **Flutter's `Router` widget with a parser and delegate.** Rejected: the
  delegate would have to build pages, which windowing already does, and the
  history mapping (push or replace from the doc) fits a provider report
  directly.

## Consequences

- Apps are not tied to a router. An app that also uses one keeps it.
- Tests drive URL behaviour with a fake `RouteInformationProvider`; no
  browser is needed.
- Browser history traversal on app-initiated back is not built: it needs a
  web-only API outside the route information seam.
