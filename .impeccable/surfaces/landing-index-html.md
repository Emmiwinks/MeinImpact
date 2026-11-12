---
version: 1
slug: "landing-index-html"
primary_target: "landing/index.html"
related_targets: []
---

# Landing page (meinimpact.de)

Mode: Persuade. Static single HTML file at landing/index.html, German, du-form.

Audience: people in Dresden (mostly on phones) who hear about MeinImpact and want to know what it is. Job: understand the app in seconds, see that it is real and in the making, join the Android beta by email (hallo@meinimpact.de, mailing list as today).

Proof: live open questions from the backend (public preview endpoint), live counts by level. No testimonials, numbers or claims beyond that.

Constraints: claim is "Die einfachste Art, politisch aktiv zu werden." (user). No hand-of-cards metaphor (user). Card-table world from DESIGN.md, light peach table (user prefers light). Short "Über mich" text by the user plus GitHub link in the footer. Impressum and Datenschutz links.

Unresolved: the user's own Über-mich text (placeholder until supplied); Impressum/Datenschutz pages do not exist yet.

## Direction contract

THESIS: The page is the game's rulebook, opened at its first page: a moving board of real open questions, the claim, then numbered chapters that are the app's flow. Refuses the app-landing default of phone mockup beside headline over a feature-card row.

OWN-WORLD: Peach table #FFF1E3, card stock #FFFCF8, ink #101820 text, four topic colours (coral, teal, amber, violet) rotating by topic, Unbounded 800 for claim, questions and chapter numbers, Albert Sans for everything else, pill buttons in ink, soft straight-down shadows only on card-stock objects, keylines elsewhere.

STORY: Visitor sees real questions people can act on right now, reads the claim, scans six chapters (Dein Bild, Aktionen für dich, Mitmachen, Brief an den Stadtrat, Mein Impact, Bleibt bei dir), sees where the questions come from and what is still being built, reads who builds it, writes an email to join the beta.

FIRST VIEWPORT: Top bar: wordmark left, "Version 0.1 · Beta" pill right. A wide card-stock board spanning the content width: level and days-left line, then one live question in Unbounded at large size, flipping to the next every few seconds split-flap style, with a topic-colour band. Below it the claim in Unbounded (largest type on the page) left, the ink "Beta testen" pill and "Android jetzt, iPhone später" right. The chapter index starts at the fold.

FORM: Spielanleitung (game manual) with the live question flipper as opener, own list position 1 after user steer over two re-rolls (rounds 1 and 2 rerolled; user chose round-2 card "Spielanleitung" plus flipper). seed:b70fa00fcbcc74e6

Signature interaction: the split-flap flip of the question board (top half folds down, rows of letters settle), paused on hover and focus, instant swap under reduced motion; tapping the board shows the next question.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
