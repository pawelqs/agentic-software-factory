# Design principles

Factory default; a project's own `docs/design-principles.md` replaces it.

- **Deep modules**: simple interface, substantial functionality behind it. No shallow pass-through layers or wrappers.
- **Information hiding**: a design decision lives in one module; callers don't depend on internals.
- **Pull complexity down**: modules handle their own edge cases instead of pushing them to callers.
- **Follow the codebase**: existing patterns, naming and libraries over new ones.
- **YAGNI**: build what the spec needs. No speculative options, config or abstractions.
- **Duplication**: remove it when the cases are truly the same; tolerate it over a premature abstraction.
- **Errors**: fail loudly at boundaries; no silent catch-alls.
- **Names** say what a thing is or does; a needed comment explains why, not what.
