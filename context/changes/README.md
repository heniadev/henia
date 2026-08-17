# context/changes/

In-flight units of work — one folder per change at
`context/changes/<change-id>/`.

A change is identified by its `change.md` identity file and is opened with
`/101-new`. Everything change-scoped lives inside that folder: research,
framing, the implementation plan, and reviews. Nothing change-scoped
belongs in `context/foundation/`.

When a change is finished, `/101-archive` moves its whole folder under
`context/archive/`.
