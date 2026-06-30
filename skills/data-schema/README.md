# data-schema (bundled skill)

A rigorous method for turning a knowledge base's data catalog into a proper, normalized,
constraint-backed data model — applied at the **design-spec → build-plan** stage, *before* a spec is
decomposed into build tickets, so the contract layer (Zod/OpenAPI) and every module are generated
against a sound schema.

- **[`SKILL.md`](./SKILL.md)** — the activation wrapper: when to use it, the order of operations, and the
  non-negotiables.
- **[`database-design-rules.md`](./database-design-rules.md)** — the canonical 16-section rule set
  (naming, types, constraints, relationships, ORM/migration safety, indexing, concurrency, audit, PII,
  JSON, partitioning, anti-patterns, testing, docs).

Syntax examples target SQL Server + a TypeORM-style ORM; the principles are stack-agnostic. This skill is
referenced from the development-contract pillar (`toolkit/contract/design-spec.md.tmpl`).
