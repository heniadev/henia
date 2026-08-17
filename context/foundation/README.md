# context/foundation/

Living documents that span multiple changes. Each project picks the ones it
actually needs — requirements, tech stack, roadmap, lessons, test plan —
and each document is owned by the skills that read and write it.

## Conventions

**Edit-in-place (G-05a).** When a foundation document changes
incrementally, edit the existing file. Never create dated just-in-case
copies alongside it; the file's history lives in git, not in the filename.

**Archive only when superseded.** A document replaced by a new approach —
not merely refined — moves to `foundation/archive/YYYY-MM-DD-<doc>.md`, and
the replacement takes the original path. Nothing reads that archive
routinely; it exists so a superseded approach stays recoverable.

**Named anti-pattern — change-scoped doc in foundation.** Anything tied to
a single change (its plan, its research, its reviews) belongs under
`context/changes/<change-id>/`, never here. Foundation is for what outlives
any one change.
