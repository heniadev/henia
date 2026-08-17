# Contract surfaces

Registry of **load-bearing names** — the identifiers that other code, tools,
or people depend on staying stable. Changing one is never a local edit.

## What belongs here

Data **structures**, **routes/endpoints**, file and message **formats**, and
**events**. One `##` heading per surface, named exactly as it appears in the
system, followed by a line or two on who depends on it and why it must stay
stable.

## How it is consumed

`/101-plan-review` pattern-scans plan text against this file's H2 headings
and flags any plan that touches a registered surface without acknowledging
it. When this file is absent, that check is **silently skipped** — which is
why an empty-but-present registry is already useful: it starts working the
day the first surface is added.

## Ownership

- **`/101-init`** owns the scaffold — this file's creation and this intro.
- **The user** owns the entries. Any skill may add one, but only when the
  user asks for it.
- **`/101-plan-review`** is a read-only consumer and never writes here.

---

<!-- Surfaces start below. One ## heading per surface. -->
