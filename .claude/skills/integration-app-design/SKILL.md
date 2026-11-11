---
name: integration-app-design
description: Rules for designing the integration apps (apps/*, docs/integration-apps.md) in FigCraft. Use when creating or editing any screen, layout or element for an integration app design.
---

# Designing integration apps

Two rules apply to every design change.

## 1. Always use design tokens

- The app's tokens live in a W3C DTCG file next to its design (`apps/<app>/design/tokens.json`).
  That file is the source of truth. Add or change a token there first, then sync it into
  FigCraft with the `spec-compare` skill.
- Each app has a variable collection named after it (the mail client uses `Mail`). Bind every
  fill, stroke and text colour to a variable with `variable.bind`. Bind spacing and radius to
  the `space/*` and `radius/*` number variables.
- Bind fixed sizes too: shared scales to `size/*` (icons, avatar, control heights), and
  one component's own dimensions to component tokens (`sidebar/width/expanded`). Hug and fill
  sizes and icon glyph geometry stay unbound.
- Every interactive element is at least 44×44. This is a rule, not a token.
- Shared effects are styles. Apply them with `style.apply`, for example `Surface/Paper`.
- When a value has no token, add the token first with `variable.create`, then bind it.
- Token names are design-side only, such as `surface/nav` and `text/muted`. Don't set
  `codeSyntax`.
- Check your work: walk `inspect_document` and confirm that every solid paint has an entry in
  `boundVariables`.

## 2. Prefer components, and reuse them

- Before you build an element, run `component.list`. If a component already covers it, place
  an instance with `instance.create`. Change only its text and properties.
- When an element appears a second time, make it a component. Don't copy layers.
- Main components live on the page's **Components** board. Screens hold instances only.
- Express differences with variants (`State=Selected|Default`) or boolean properties
  (`Show count`, `Unread`). Don't use detached copies.
- To change the look of an element, edit the main component. Never detach an instance.
