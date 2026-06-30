# Arabic / RTL-first (preset)

This is the **single biggest divergence** from a typical internal tool. The corpus is
bilingual (English BRDs/FRDs; Arabic clinical instruments and forms), the operational users
work in Arabic, and the UI must render right-to-left correctly. Treat i18n + RTL as a
**commit-1 foundation, not a v2 retrofit.** Retrofitting bidi onto an LTR-assuming codebase
is an expensive, defect-prone rewrite — bake it in before the first feature slice.

---

## Decide these on day one (record in an ADR if you like)

| Decision | Default to adopt | Why now |
|----------|------------------|---------|
| i18n library / framework | Your framework's first-class i18n (e.g. locale-routed messages) | Wiring it later means touching every string. |
| Locale routing | `/{en\|ar}/...` (or equivalent) with a default + persisted user preference | The URL carries locale; SSR and links stay correct. |
| Direction source of truth | `dir` derived from locale, set on `<html>` | One switch flips the whole document. |
| CSS strategy | **Logical properties** everywhere | The only sane way to be direction-agnostic. |
| Arabic-capable font | Ship an Arabic-capable webfont with proper shaping | System fallbacks render Arabic poorly/inconsistently. |
| Message storage | Keyed catalogs `en.json` / `ar.json`, no hard-coded strings | Translation + review become tractable. |

---

## RTL is logical, not a mirror hack

- **Use CSS logical properties, not physical ones.** `margin-inline-start` not `margin-left`;
  `padding-inline-end` not `padding-right`; `inset-inline-start` not `left`; `text-align: start`
  not `left`. The same stylesheet then renders correctly in both directions with no per-locale
  overrides.
- **Set `dir` once, high up.** `dir="rtl"` on `<html>` (driven by locale) flips the inline
  axis for the whole tree. Avoid sprinkling `dir` on leaf nodes except for genuinely
  direction-fixed content.
- **Bidi-aware components.** Anything with an implied direction — icon+label rows, breadcrumbs,
  progress steppers, chevrons/back-arrows, sliders, number/date/currency formatting, charts
  with axes, tables with a leading column — must be **mirrored by logic**, not assumed LTR.
  Directional icons (back, next, indent) flip; non-directional icons (search, user) do not.
- **Mixed-direction content is normal.** Arabic text containing Latin tokens (codes, IDs,
  phone numbers, file names) needs correct bidi isolation (`<bdi>` / `unicode-bidi: isolate`)
  so embedded LTR runs don't reorder the surrounding Arabic.
- **Numerals & dates:** decide Eastern-Arabic vs Western-Arabic numerals explicitly per the
  corpus, and format dates/times through the locale formatter — never string-concatenate.

---

## Bilingual fields live in the contract layer

Bilingual labels and bilingual **data** are a schema concern, not an afterthought sprinkled in
components. Model them in the contracts package so backend and frontend share one source of
truth and validation runs at every edge.

```ts
// contracts: a label/value carried in both languages
const Bilingual = z.object({ en: z.string(), ar: z.string() });

// reference/config data (lookups, form labels, measure items) is bilingual at rest:
const ServiceType = z.object({
  code: z.string(),
  label: Bilingual,      // not a single string
});
```

- **Reference/config data** (lookups, statuses, form/questionnaire labels, measure items) is
  bilingual **at rest** — store both languages, return both, let the UI pick by locale.
- **UI chrome strings** (buttons, nav, validation messages) live in the i18n message catalogs
  (`en.json`/`ar.json`), not in the database.
- A field is **not "done"** until both `en` and `ar` are present and it renders correctly in
  both directions on the brand surfaces (see `brand.md`).

---

## OCR caveat — verify Arabic clinical content before trusting scoring

Some Arabic in the corpus was **OCR'd from degraded scans**. Per the KB conventions, every
such file carries a quality caveat in its area `_manifest.md`. For clinical instruments this is
a **correctness hazard, not a cosmetic one**:

- **Never trust OCR'd Arabic scoring as gospel.** Item wording, option ordering, reverse-scored
  items, and cut-off thresholds can all be corrupted by OCR.
- Before implementing any score, **verify the instrument against the canonical published
  source** — treat the OCR'd text as "verify against canonical," not as authoritative.
- Encode **scoring as versioned data** (see `protected-core-checklist.md`, forms/measures
  engine) so a corrected instrument is a new version, with the provenance recorded and the
  prior version preserved. A silently wrong clinical score is a statutory-grade defect.

---

## Definition of done (i18n/RTL)

A screen or export is RTL-complete only when:

1. It renders correctly with `dir="rtl"` **and** `dir="ltr"` — no clipped text, no mirrored
   icons that shouldn't mirror, no un-mirrored layout that should.
2. Every visible string comes from the i18n layer (no hard-coded English).
3. Bilingual data shows the locale-correct language and bidi-isolates embedded LTR runs.
4. Numbers, dates, and currency are locale-formatted.
5. Any clinical/measure content sourced from OCR has been verified against the canonical
   instrument before its scoring is wired up.
