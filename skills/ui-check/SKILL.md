---
name: ui-check
description: Use when a change touches anything a person sees in a web UI, before calling it done.
visibility: public
scope: personal
layer: engineering
last-verified: 2026-11-26
---
# ui-check

Look at the real page, not the code, and catch what a person would trip over.

1. **Screenshot every page the change touches**, from the running app, with a headless browser script or the app's screenshot tool. Include the full page when it scrolls. Verify: no console errors were reported while it loaded.
2. **Check the states that matter:** empty, loading, one item, many items, an error, and a long name or value, at desktop and phone width (about 375 px).
   **Look by eye at the default theme only.** Add the high-contrast theme only when the change touches colours or focus. Check every other theme with scripts (contrast, overflow, hard-coded colours), without opening their pictures. Look at every theme by eye only when a theme itself changes, and once before a big release. (The operator, 2026-11-26: keep usage minimal; fix the other looks later rather than pay more on every change.)
3. **Look for the usual problems:**
   - the same action shown twice on one screen;
   - buttons or boxes stretched full width when they shouldn't be;
   - text overflowing, cut off, or wrapping awkwardly;
   - a long list burying what matters (fold the noise behind a "show" link);
   - a dead end: a problem with no next step.
4. **Read every word** with the `plain-words` skill in mind.
5. **Fix, re-shoot, compare.** Repeat until clean, then report what you looked at.

## gotchas
- A passing test suite says nothing about layout. Only looking does.
- Formatting and CSS changes can move things on pages you didn't edit; shoot the neighbours too.
- Real data is messier than test data: use the product's busiest demo data (Core: the busy-day demo). Never copy or open a live database to get real data.
- Anything the person must type or paste somewhere else (a sign-in code, a one-time code, a value for another site) gets its own panel, set apart from the rest. It shows the value large, has one button that copies it and opens where it goes, and gives short steps that say what it is and what it isn't ("not your authenticator code"). Buried in a card's text, people type the wrong code.

## never
- Never call UI work done without having looked at it.
- Never test against production data in a way that changes it; use read-only views or a test account.
