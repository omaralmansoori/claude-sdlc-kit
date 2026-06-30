# ORG Brand Rules (preset)

These rules apply to **any exported or user-facing artifact** the app or an agent produces:
the running UI, PDF/Word exports, generated reports, emails, dashboards, and decks. They are
a deliberately small, enforceable subset of the full ORG brand system — enough to keep
everything on-brand without turning every agent into a designer.

> Scope note: this is the **product** palette for an operational case-management tool —
> calm surfaces, high legibility, alerts reserved for genuine alerts. It is intentionally
> more restrained than the ORG marketing palette. When in doubt for marketing/collateral,
> defer to the full ORG brand guidelines; for the application, follow this file.

---

## Palette

| Token | Hex | Use |
|-------|-----|-----|
| Surface (off-white / light-grey) | `#F4F5F5` / `#FFFFFF` | Page and card backgrounds. Prefer light, low-saturation surfaces. |
| Dark Grey | `#4D5456` | Primary structural color: app chrome, headers, primary buttons, dividers. |
| Sand | `#DAC198` | Accent only — selected states, subtle highlights, secondary emphasis. Never for large fills or body text. |
| Black | `#000000` | Body text and high-contrast labels. |
| Red (critical) | `#EC1A39` | **Critical alerts only** — destructive actions, validation errors, statutory warnings. Never decorative. |

### Hard palette rules

- **Red is reserved.** `#EC1A39` may appear only on genuine alerts: errors, destructive
  confirmations, overdue-SLA / breach states, and statutory warnings. If it is on the screen,
  something needs attention. Do not use it for branding flourishes, links, or charts-by-default.
- **Sand is an accent, not a surface.** Use it sparingly for selection and emphasis. Large
  Sand fills read as marketing, not as an operational tool.
- **Text is Black on light surfaces.** Maintain a contrast ratio of at least 4.5:1 for body
  text and 3:1 for large text (WCAG AA). Dark Grey text is acceptable for secondary/muted
  copy but check contrast on the surface it sits on.
- **Max three colors in view.** Structural Dark Grey + Black text + at most one accent
  (Sand) or one alert (Red) at a time. Restraint is the brand.

### Suggested CSS custom properties

```css
:root {
  --color-surface:        #F4F5F5; /* page background */
  --color-surface-raised: #FFFFFF; /* cards, panels   */
  --color-structural:     #4D5456; /* Dark Grey       */
  --color-accent:         #DAC198; /* Sand            */
  --color-text:           #000000; /* body text       */
  --color-critical:       #EC1A39; /* alerts only     */
}
```

Define these once at the theme boundary and reference the tokens everywhere. No hard-coded
hex values scattered through components — changing the brand must be a one-file edit.

---

## No emojis. Ever.

No emojis in the UI, in exports, in emails, in error/toast/label strings, in commit-facing
user copy, or in generated reports. This is a statutory-facing government tool; emojis are
off-brand and inappropriate for the domain. Use the icon set below for any glyph need.

---

## One icon set: Lucide

Use **Lucide** (or your framework's Lucide binding) as the **single** icon set across the
entire product. Do not mix icon libraries — one set keeps stroke weight, grid, and metaphor
consistent.

- One library, imported per-icon (tree-shakeable), never a full-font dump.
- Consistent size scale (e.g. 16 / 20 / 24 px) and a single stroke weight.
- Icons support, never replace, a text label on actionable controls (accessibility).
- If Lucide lacks a needed glyph, request a substitute from within Lucide — do not pull in a
  second library.

---

## Strings: no internal spec references in user-facing copy

Requirement IDs (`ORG-*`, `DC_*`, `FCS-*`) are for code comments, commits, and PRs — **never**
for a string a user sees. A toast, error, label, tooltip, or export caption must read in plain
bilingual language, with the spec citation living only in the code comment beside it. (This was
a real defect class on the sibling project; the kit treats it as a brand rule here.)

---

## Bilingual by default

Every user-facing label has an English and an Arabic form, sourced from the i18n layer (see
`i18n-rtl.md`). Brand restraint and RTL correctness are the same job: a label is not "done"
until it renders correctly in both directions on the brand surfaces above.
