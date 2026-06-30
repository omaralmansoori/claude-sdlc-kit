# Database Design Rules

A living reference for schema design, naming, and operational safety.
Applies to SQL Server with a TypeScript ORM (TypeORM-style) unless noted.

> Canonical rule set, supplied by the operator. This document is authoritative (see §16); the
> [`SKILL.md`](./SKILL.md) beside it is a short activation wrapper that points here.

---

## 1. Naming Conventions
- Tables: `TitleCase`, plural nouns (e.g. `VisitorBookings`, `SiteUsers`)
- Columns: `TitleCase` (e.g. `CreatedAt`, `EmiratesId`)
- Primary keys: always named `Id`
- Foreign keys: `{ReferencingTableSingular}{ReferencedTableSingular}Id` (e.g. `BookingSiteId`)
- Indexes: `Idx{Table}{Col1}{Col2}` (e.g. `IdxBookingsSiteId`)
- Unique constraints: `Uq{Table}{Col}` (e.g. `UqUsersEmail`)
- Check constraints: `Ck{Table}{Col}` (e.g. `CkBookingsStatus`)
- Default constraints: `Df{Table}{Col}` — name them explicitly so they can be dropped/altered cleanly (SQL Server auto-names are unstable)
- Foreign key constraints: `Fk{ChildTable}{ParentTable}` (e.g. `FkBookingsSites`)
- Junction/bridge tables: `{TableA}{TableB}` in alphabetical order (e.g. `RolesUsers`, not `UsersRoles`)
- Views: prefix `Vw` (e.g. `VwActiveBookings`)
- Stored procedures: `Usp{Verb}{Noun}` (e.g. `UspArchiveBookings`)
- Triggers: `Tr{Table}{Event}` (e.g. `TrBookingsAfterUpdate`) — but prefer app/ORM logic over triggers (see §9)
- Boolean columns: prefix with `Is`, `Has`, or `Can` (e.g. `IsActive`, `HasConsent`)
- Datetime columns: suffix with `At` (e.g. `ConfirmedAt`); date-only with `On` (e.g. `BookingOn`)
- Avoid abbreviations and reserved words; never use spaces or quoted identifiers

## 2. Schema Design Patterns
- Every table must have: `Id`, `CreatedAt`, `UpdatedAt`
- Soft-delete tables add `DeletedAt DATETIME NULL` and a filtered index on `WHERE DeletedAt IS NULL`
- Never hard-delete records that may be audited or referenced — use soft-delete
- Primary keys: UUID v4 (`VARCHAR(36)`) by default; use `INT IDENTITY` only when PKs are never exposed to clients
- Consider UUID v7 (time-ordered) over v4 for high-insert tables to reduce index fragmentation, if your stack supports it
- Nullable unique columns (e.g. `EmiratesId`) must use a **filtered index** (`WHERE Col IS NOT NULL`) — SQL Server allows only one NULL in a plain UNIQUE constraint
- Enum-like columns: store as `VARCHAR` with a CHECK constraint, not as a numeric code
- Never store PII (names, IDs, contact info) in audit/log tables — reference by opaque `Id` only
- One concept per table; do not overload a table with unrelated nullable columns ("wide sparse" tables are a smell)
- Prefer narrow tables with clear ownership; extract optional 1:1 detail into a satellite table when >30% of rows leave columns NULL
- No business logic encoded in PKs (no "smart keys" like `BK-2026-DXB-0001`); store such codes in a separate human-readable column with its own unique constraint
- Always define an explicit collation strategy for text columns (case/accent sensitivity); document the default and override per-column only with reason
- Money: never `FLOAT`/`REAL`. Use `DECIMAL(19,4)` and store the currency code (`CHAR(3)`, ISO 4217) alongside it
- Timestamps: store UTC in `DATETIME2(3)`; never store local time. Capture the originating timezone separately if it matters to the domain

## 3. Data Types & Precision
- Strings: size to the domain, not to the max. `VARCHAR(320)` for email, `VARCHAR(15)` for E.164 phone, `VARCHAR(36)` for UUID
- Use `NVARCHAR` only when Unicode is required; otherwise `VARCHAR` to halve storage. Be consistent across joined columns to avoid implicit conversions
- Avoid `MAX` types (`VARCHAR(MAX)`, `NVARCHAR(MAX)`) on hot tables; move large text/blobs to a dedicated table or object storage with a reference
- Booleans: `BIT NOT NULL` with an explicit default; never use a nullable `BIT` to mean three states — model the third state explicitly
- Dates without time: `DATE`. Time without date: `TIME`. Full timestamps: `DATETIME2(3)` (millisecond precision is usually enough)
- Numeric IDs from external systems: store as `VARCHAR`, not `INT` — leading zeros and length rules matter (Emirates ID, IBAN, etc.)
- JSON columns: use `NVARCHAR(MAX)` with `ISJSON()` check constraint; index extracted scalar properties via computed columns, not the blob itself
- Never use implicit type coercion across joins — mismatched types defeat index usage and force scans

## 4. Constraints & Data Integrity
- Push integrity into the database; the ORM is not the only writer (migrations, scripts, and DBAs touch the DB too)
- Every foreign key column has an actual `FOREIGN KEY` constraint, not just an ORM relation
- Default `ON DELETE` behavior is `NO ACTION`. Use `CASCADE` only for true ownership (child cannot exist without parent) and never across soft-deleted relationships
- Avoid multiple cascade paths to the same table — SQL Server rejects them; resolve with `NO ACTION` + application logic
- `NOT NULL` is the default mindset; justify every nullable column. NULL means "unknown/not applicable," never "empty" or "zero"
- Use CHECK constraints for invariants: ranges (`CkBookingsGuests` `Guests BETWEEN 1 AND 20`), state machines, and cross-column rules (`EndAt > StartAt`)
- Enforce uniqueness at the DB level for any field the app treats as unique — application-level checks race under concurrency
- Composite natural keys belong in a `UNIQUE` constraint, even when a surrogate `Id` is the PK

## 5. Relationships & Cardinality
- 1:N — FK on the "many" side, indexed (§7)
- N:M — explicit junction table with its own `Id`, `CreatedAt`, `UpdatedAt`, plus a composite `UNIQUE` on the two FKs
- 1:1 — share the PK or put a `UNIQUE` FK on the dependent table; only split out when columns are large, rarely accessed, or have different security needs
- Polymorphic associations: avoid `(EntityType, EntityId)` pairs — they cannot be FK-enforced. Prefer separate nullable FKs with a CHECK ensuring exactly one is set, or separate junction tables
- Self-referencing hierarchies: store `ParentId` (adjacency list) for shallow trees; consider a closure table or `HIERARCHYID` for deep/queried trees
- Document the cardinality and ownership of every relationship in the entity comment

## 6. ORM / Migration Rules
- ORM entities (`domain/*/entity.ts` or equivalent) are the **source of truth**; DB schema is derived from them
- Schema changes require: (1) edit `@Column()` decorator, (2) update init/migration scripts to match byte-for-byte
- Never alter the database schema directly outside of the ORM + init scripts
- New NOT NULL columns must supply a DEFAULT value or be added nullable first, then backfilled
- When removing a column: deprecate in ORM first (mark nullable), then drop in a follow-up migration after verifying no code references it
- Keep init scripts and migration scripts identical in column definitions (type, length, nullability, defaults)
- **Every migration must be reversible** — provide a working `down()` or an explicit, reviewed reason it is irreversible
- Migrations are **forward-only in production** but must be tested both ways in CI
- One logical change per migration; never bundle unrelated schema edits
- **Expand/contract pattern** for breaking changes: (1) add new structure, (2) backfill + dual-write, (3) switch reads, (4) remove old structure in a later release — never break running app instances mid-deploy
- Backfills on large tables must be **batched** (e.g. 5k rows/transaction) with a delay, not a single `UPDATE` that locks the table
- Never run data migrations and schema migrations in the same transaction on large tables
- Migration filenames are timestamp-prefixed and immutable once merged; fix mistakes with a new migration, never by editing a shipped one
- Seed/reference data lives in versioned, idempotent migrations (use `MERGE` or "insert if not exists"), separate from test fixtures

## 7. Indexing & Performance
- Index every foreign key column (SQL Server does not auto-index FKs)
- Index any column appearing in frequent `WHERE`, `ORDER BY`, or `JOIN` clauses
- Composite index column order: highest-selectivity column first; match the order to actual query predicates (equality columns before range columns)
- Filtered indexes for nullable unique constraints (see §2)
- Avoid indexing columns with very low cardinality (boolean flags, status enums with <5 values) unless combined with a high-selectivity column
- Covering indexes: `INCLUDE` frequently SELECTed columns to avoid key lookups on hot read paths
- Never add an index without a documented reason in a comment on the `@Index()` decorator or migration
- The clustered index (usually the PK) should be narrow, static, and ideally ever-increasing; random UUID v4 clustering causes page splits — see UUID v7 note in §2
- Audit and remove **unused and duplicate indexes** quarterly (`sys.dm_db_index_usage_stats`) — every index taxes writes
- Watch index fragmentation; reorganize/rebuild on a schedule appropriate to churn
- Prefer set-based operations over row-by-row (RBAR); no cursors in application paths
- Always paginate large result sets with keyset (seek) pagination over `OFFSET` for deep pages
- Treat any query plan with a scan on a large table or a key-lookup loop as a review item, not a default

## 8. Transactions & Concurrency
- Keep transactions short and narrow; never hold a transaction open across a network/user round-trip
- Default isolation is `READ COMMITTED`; enable `READ COMMITTED SNAPSHOT` (RCSI) to reduce reader/writer blocking unless a specific case forbids it
- Use **optimistic concurrency** for user-editable records: a `RowVersion`/`@VersionColumn()` checked on update; reject and re-read on conflict rather than last-write-wins
- Acquire locks in a consistent order across the codebase to avoid deadlocks; expect and retry deadlocks (error 1205) with backoff
- Idempotency: side-effectful writes (bookings, payments) carry an `IdempotencyKey` with a unique constraint so retries don't double-insert
- Never do "check-then-insert" in application code for uniqueness — rely on the DB constraint and handle the duplicate-key error
- Long-running reports run against a replica or with `SNAPSHOT` isolation, never blocking OLTP tables

## 9. Triggers, Computed Columns & Server Logic
- Prefer application/ORM logic to triggers; triggers are invisible side effects that complicate debugging and migrations
- If a trigger is unavoidable (e.g. cross-table audit that must not be bypassable), keep it minimal, set-based, and documented
- Use **computed columns** (persisted where indexed) for derived values that must stay consistent (e.g. normalized search keys), rather than maintaining them in app code
- Business rules that span tables and must hold for all writers belong in constraints or, failing that, a single well-tested stored procedure — not duplicated across services

## 10. Auditing & Change Tracking
- Separate the audit concern from the operational table; do not bloat hot tables with history
- Audit tables record: `Id`, `OccurredAt`, `Action` (`Insert`/`Update`/`Delete`), `EntityName`, `EntityId`, `ChangedByUserId`, and a JSON `Changes` diff
- **Never store PII in audit payloads** — store opaque `Id`s and reference the source table (restated from §2 because it is the most-violated rule)
- For full point-in-time history, prefer SQL Server **temporal tables** (`SYSTEM_VERSIONING`) over hand-rolled triggers
- Audit records are append-only and never updated; restrict write access at the DB-role level
- Capture the actor and request context (`CorrelationId`) so audit entries are traceable to a request

## 11. Security, PII & Compliance
- Classify every column: Public, Internal, PII, or Sensitive — record the classification in the entity comment
- Encrypt sensitive data at rest (TDE for the database; Always Encrypted / column encryption for high-sensitivity fields like national IDs)
- Apply **dynamic data masking** for support/read-only roles so PII is not exposed casually
- Principle of least privilege: application accounts get DML only, never DDL; migrations run under a separate elevated identity
- Never store secrets, raw passwords, or tokens — store password **hashes** (Argon2/bcrypt) and treat the column as Sensitive
- Support data-subject rights: design for **deletion/anonymization** of PII (overwrite with tombstone values) while preserving referential and audit integrity via opaque IDs
- Define and enforce **retention periods** per table; PII beyond its retention window is purged or anonymized on schedule
- All access to Sensitive tables is logged (§10)
- Connection strings and credentials live in a secrets manager, never in source or config files

## 12. JSON & Semi-Structured Data
- Use JSON columns for genuinely schema-less, low-query attributes (flexible metadata, third-party payloads) — not as an escape hatch from modeling
- Validate with `ISJSON(Col) = 1` as a CHECK constraint
- Anything you filter, sort, or join on must be promoted to a real (optionally computed) column and indexed — never query inside the blob on hot paths
- Document the expected JSON shape in the entity comment and version it if it evolves
- Do not store relational data (lists of FKs, parent/child links) as JSON — use proper tables

## 13. Partitioning, Archiving & Growth
- Plan for table growth at design time; estimate row counts and growth rate in the entity comment for any high-volume table
- Large append-only/time-series tables (bookings, events, logs) are candidates for **partitioning** by date range
- Move cold data to archive tables/storage on a schedule; keep the OLTP footprint small
- Soft-deleted rows are eventually hard-purged from operational tables only after retention and audit requirements are met (and only via a reviewed job, never ad hoc)
- Never run unbounded `DELETE`/`UPDATE` on large tables — batch with a `TOP (n)` loop and throttle

## 14. Query & Access Patterns (Anti-Patterns)
- No `SELECT *` in application code — name columns explicitly so schema changes don't silently break callers and so covering indexes apply
- Avoid N+1 queries; use the ORM's eager/explicit join loading and assert query counts in tests
- No functions on indexed columns in `WHERE` (`WHERE YEAR(CreatedAt) = 2026` defeats the index) — use range predicates instead
- Parameterize all queries; never string-concatenate user input (SQL injection + plan-cache bloat)
- Avoid `OR` across different columns where it forces scans; rewrite as `UNION` of indexable predicates when needed
- Keep transactions and the queries inside them as small as the correctness requirement allows (§8)

## 15. Testing, Environments & Seed Data
- Every migration runs in CI against a fresh database and against a production-like snapshot (data shape matters for performance regressions)
- Test both `up()` and `down()`; a migration that can't roll back in CI doesn't merge without sign-off
- Maintain idempotent **seed data** for reference tables (countries, statuses, roles) as versioned migrations
- Keep **test fixtures** separate from seed data; fixtures never ship to production
- Lower environments use **anonymized/synthetic** data — never a raw copy of production PII
- Add a performance smoke test (explain-plan or timing) for new indexes on hot tables

## 16. Documentation & Conventions
- Every table and non-obvious column has a comment explaining purpose, units, and constraints (PII classification per §11, growth estimate per §13)
- Keep an up-to-date ER diagram generated from the schema, not drawn by hand
- A `CHANGELOG`/ADR entry accompanies any non-trivial schema decision (why this shape, what was rejected)
- This document is the canonical rule set; deviations require a written, reviewed exception noting the reason and scope
