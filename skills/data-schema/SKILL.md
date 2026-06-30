---
name: data-schema
description: Use when designing or reviewing a database schema / data model - turning a knowledge base's data catalog (entities, fields, relationships) into a proper, normalized, constraint-backed schema before decomposing a spec into build tickets. Covers naming, data types, constraints, relationships, ORM/migration safety (expand/contract), indexing, transactions/concurrency, auditing, PII/compliance, JSON, partitioning, and anti-patterns. Syntax examples assume SQL Server + a TypeORM-style ORM; the principles are stack-agnostic.
---

# Data Schema Design

You design the data model **before** you decompose a spec into build tickets. The schema is the
foundation the contract layer (Zod/OpenAPI) and every module are generated against - get it wrong and
every downstream ticket inherits the mistake.

## When to use
- Designing a new domain's tables from a knowledge base's data catalog (the `DC_*`-style entities).
- Reviewing a proposed schema or migration before it lands.
- Resolving a data-modeling decision (polymorphic association, temporal history, soft-delete, money, PII).

## How to use
1. Read the full canonical rule set: [`database-design-rules.md`](./database-design-rules.md) (16 sections).
   It is the canonical reference - deviations require a written, reviewed exception (§16).
2. Apply it in this order for a new domain:
   - **Model** the entities (one concept per table; §2), name them (§1), type the columns (§3).
   - **Constrain** them (FKs, CHECKs, uniqueness, NOT NULL by default; §4) - push integrity into the DB.
   - **Relate** them (1:N / N:M junctions / 1:1 / avoid `(EntityType, EntityId)` polymorphism; §5).
   - **Index** for the real query predicates (every FK; selectivity order; filtered/covering; §7).
   - **Plan migrations** with expand/contract + a reversible `down()` + batched backfills (§6).
   - **Design audit** as a separate, append-only, **PII-free** concern (§10), and classify every column
     Public/Internal/PII/Sensitive (§11).
3. Make the contract package's Zod schemas agree with this data model (same field names, nullability,
   enums-as-CHECK). The DB is the source of truth for *shape and integrity*; the ORM entity is the source
   of truth the schema is *derived from* (§6).

## The non-negotiables (the most-violated rules)
- Every table has `Id`, `CreatedAt`, `UpdatedAt`; soft-delete via `DeletedAt` + a filtered index (§2).
- Money is `DECIMAL(19,4)` + an ISO-4217 currency code - never `FLOAT` (§2).
- Timestamps are UTC `DATETIME2(3)` - never local time (§2).
- Enum-like columns are `VARCHAR` + CHECK, not numeric codes (§2).
- Every FK has a real `FOREIGN KEY` constraint and is indexed (§4, §7).
- Uniqueness is enforced at the DB level; never check-then-insert in app code (§4, §8).
- Audit tables never store PII - opaque `Id`s only (§10, restated because it is the most-violated rule).
- Breaking schema changes use expand/contract; migrations are reversible and tested both ways in CI (§6).
- Optimistic concurrency (`RowVersion`) for user-editable records; idempotency keys for side-effectful writes (§8).

> Stack note: examples are SQL Server + TypeORM-style, but the principles (integrity in the DB, an
> append-only PII-free audit, expand/contract migrations, keyset pagination, least privilege) transfer to
> any relational stack. When the kit's core targets a different DB, keep the principles and translate the syntax.
