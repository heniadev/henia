# Lessons Learned

> Append-only register of recurring rules and patterns. Re-read at start
> by /101-frame, /101-research, /101-plan, /101-plan-review,
> /101-implement, /101-impl-review.

## Name branches with conventional git prefixes

- **Context**: git branch creation and workflow, in repos using the 101 change lifecycle
- **Problem**: branch names get improvised per run — `change/devserver-setup` borrowed the toolkit's own noun instead of git convention, matching no PR template, tooling default or CI branch filter. `/101-new` explicitly does not create branches and no other skill owns the decision, so every change re-invents the name.
- **Rule**: Name branches with a conventional git prefix — `feature/`, `bugfix/`, `hotfix/`, `docs/`, `chore/`, `release/` — followed by a kebab-case description; never invent a prefix from project vocabulary. Branch per change, merged via pull request rather than committed to the default branch.
- **Applies to**: implement, impl-review
