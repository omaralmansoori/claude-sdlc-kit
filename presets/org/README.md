# Preset: ORG

This is an **optional overlay** for the claude-sdlc-kit. The core kit is deliberately
domain-agnostic — nothing in `toolkit/`, `skills/`, or `bootstrap.sh` knows about any
particular organization. This preset is the **one place** where organization-specific
conventions live, captured for **the organization (ORG)** and its statutory
case-management work.

If you are not building for ORG, **skip this folder entirely**. The methodology stands
on its own without it.

---

## What this preset adds

The core kit gives you the *machinery* (ingestion, the development contract, the four
append-only seams, waves, integration gates, heavy QA). This preset layers on the
*policy* that a regulated, bilingual, child-protection domain demands — the parts you must
**not** invent and must **not** dilute into "a typical internal tool."

| File | What it pins down |
|------|-------------------|
| `README.md` | This file — what the preset is, that it is optional, how to apply it. |
| `brand.md` | The ORG visual rules for any **exported or user-facing** artifact: surface/text/alert palette, the no-emoji rule, one icon set. |
| `auth-entra-adr.md.tmpl` | ADR template for **Entra ID (Azure AD) OIDC SSO** behind an `IAuthProvider` abstraction, with a mock provider for dev/test and a real provider for prod. |
| `i18n-rtl.md` | **Arabic / RTL-first** guidance — the single biggest divergence from a typical internal tool. i18n + RTL from commit 1, not a v2 retrofit. |
| `protected-core-checklist.md` | The statutory / child-protection **protected-core** checklist: guarded state machine, Authority Matrix as RBAC, append-only audit, data-driven forms/measures, SLA math, in-region data residency, and the external-LLM gate. |

---

## How to apply it

You have two equivalent options. Pick one; do not do both.

### Option A — at bootstrap (recommended for a new repo)

```bash
./bootstrap.sh --preset org
```

`bootstrap.sh` copies the preset's policy docs into the new project's `docs/presets/org/`
tree and appends a `> **Preset applied:** org. Read docs/presets/org/* ...` reference line
to the generated `CLAUDE.md` and `AGENTS.md`, so every agent session reads them as project
law. Move `docs/presets/org/auth-entra-adr.md.tmpl` to `docs/adr/000X-auth-entra.md` and
fill in real (sanitized) values.

### Option B — into an existing repo (manual)

```bash
mkdir -p docs/presets/org
cp presets/org/brand.md                    docs/presets/org/brand.md
cp presets/org/i18n-rtl.md                 docs/presets/org/i18n-rtl.md
cp presets/org/protected-core-checklist.md docs/presets/org/protected-core-checklist.md
cp presets/org/auth-entra-adr.md.tmpl      docs/adr/000X-auth-entra.md   # then fill in
```

Then add one line near the top of your project `CLAUDE.md` (Option A adds this for you):

```md
> **Preset applied:** org. Read `docs/presets/org/*` and the auth ADR before any feature work.
```

---

## Precedence rules

1. **The corpus wins on domain behavior.** If a `ORG-*` / `DC_*` requirement in your KB
   contradicts a default in this preset, the requirement governs — log the divergence and
   follow the corpus.
2. **This preset wins on policy defaults.** Where the core kit is intentionally silent
   (brand, auth, RTL, statutory audit posture), these files are the project default.
3. **Never bake preset content back into core.** Edits to brand colors, auth, RTL, or audit
   policy belong here under `presets/org/`, not in `toolkit/` or `skills/`. Keeping the core
   generic is what makes the kit shareable.

---

## Sanitization

This preset carries **no real tenant IDs, hostnames, secrets, or personal data**. The Entra
ADR uses placeholder env-var names and a worked shape, not live credentials. The one concrete
non-placeholder values are the **sample brand palette** in `brand.md` (a restrained
grey/sand/red product palette) — a preset needs real values to be a useful worked example, so
treat those hex codes as an illustrative sample to replace with your own brand, not as a
sanitization gap. Treat any value you fill in (tenant, client ID, redirect URI) as a secret
that lives in your secrets manager — never in this repo.
