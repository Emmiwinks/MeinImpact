---
name: MeinImpact
description: Civic actions dealt as a hand of cards on a card table.
colors:
  table-ink: "#101820"
  table-peach: "#FFF1E3"
  card-stock: "#F4F1EA"
  card-stock-light: "#FFFCF8"
  ink: "#101820"
  ink-muted: "#4A5560"
  stock-muted: "#B9C0C8"
  keyline-on-ink: "#F4F1EA1F"
  keyline-on-stone: "#10182026"
  topic-coral: "#FF5A5F"
  topic-teal: "#2EC4B6"
  topic-amber: "#FFBF3C"
  topic-violet: "#8C84FF"
typography:
  headline:
    fontFamily: "Unbounded, sans-serif"
    fontSize: "28px"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  card-title:
    fontFamily: "Unbounded, sans-serif"
    fontSize: "21px"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Albert Sans, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.25
  body-strong:
    fontFamily: "Albert Sans, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.35
  body:
    fontFamily: "Albert Sans, sans-serif"
    fontSize: "15px"
    fontWeight: 500
    lineHeight: 1.4
  label-button:
    fontFamily: "Albert Sans, sans-serif"
    fontSize: "16px"
    fontWeight: 800
  label-text-button:
    fontFamily: "Albert Sans, sans-serif"
    fontSize: "15px"
    fontWeight: 800
  label:
    fontFamily: "Albert Sans, sans-serif"
    fontSize: "13px"
    fontWeight: 700
    lineHeight: 1.3
  nav-label:
    fontFamily: "Albert Sans, sans-serif"
    fontSize: "12px"
    fontWeight: 700
rounded:
  card: "26px"
  card-art: "18px"
  tile: "14px"
  tile-art: "11px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  base: "16px"
  card-inset: "20px"
  lg: "24px"
  xl: "32px"
components:
  action-card:
    backgroundColor: "{colors.card-stock}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "20px"
    width: "340px"
    height: "520px"
  button-play:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.card-stock}"
    typography: "{typography.label-button}"
    rounded: "{rounded.pill}"
    padding: "12px 24px"
    height: "52px"
  button-on-table:
    backgroundColor: "{colors.card-stock}"
    textColor: "{colors.table-ink}"
    typography: "{typography.label-button}"
    rounded: "{rounded.pill}"
    padding: "12px 24px"
    height: "52px"
  button-text:
    textColor: "{colors.card-stock}"
    typography: "{typography.label-text-button}"
    rounded: "{rounded.pill}"
    height: "48px"
  fact-chip:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
  list-row:
    backgroundColor: "{colors.table-ink}"
    textColor: "{colors.card-stock}"
    padding: "16px 24px"
  list-row-thumbnail:
    backgroundColor: "{colors.card-stock}"
    rounded: "{rounded.tile}"
    padding: "3px"
    size: "56px"
  nav-bar:
    backgroundColor: "{colors.table-ink}"
    textColor: "{colors.stock-muted}"
    typography: "{typography.nav-label}"
    height: "72px"
  nav-indicator:
    backgroundColor: "{colors.topic-amber}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
---

# Design System: MeinImpact

## Overview

**Creative North Star: "The Card Table"**

MeinImpact deals the user's civic actions as a hand of playing cards on a table, not as a feed. The table is the screen: deep ink in dark mode, warm peach in light mode, always following the phone's setting. On it lie cards of warm, light card stock, each carrying a flat geometric picture of its topic on one of four bright topic colours. A big, chunky display face sets the questions; a friendly grotesque carries everything else. The feel is a tabletop game for a few minutes on the phone: tactile, bright, a little playful, and plain about the facts.

Density is low and deliberate. One card is read at a time, upright and large; the next ones peek out behind it, rotated and dimmed, so the hand reads as a hand. Detail is on the card's back, one tap away, never in front. Depth comes from cards lying on the table with soft shadows; everything that is not a card (rows, chips, buttons, the navigation bar) stays flat.

Material is the building kit underneath (navigation bar, back gesture, ripples, 48dp targets), not the visual language. Android ships first; iOS gets the same custom look.

**Key Characteristics:**
- Ink or stone table, light card stock, four rotating topic colours.
- Unbounded ExtraBold for headings and card questions; Albert Sans for all other text.
- Generous 26px card corners, pill buttons and chips, soft downward shadows on cards only.
- Ink text on every light surface and every topic colour.
- Motion is physical (fan, flip, flight) and cuts to instant when the system disables animations.

## Colors

A neutral ink-and-stock base with four saturated topic colours that rotate by topic, so no single colour (and no party colour) owns the screen.

### Primary
- **Card Stock** (card-stock, dark mode; card-stock-light, light mode): the face of every card, the fill of the play button's label, the rim around list thumbnails, and the on-table text colour in dark mode. Warm off-white; a shade lighter on the light table so cards still lift off it.
- **Table Ink** (table-ink / ink): the dark-mode table and navigation bar, and in both themes the colour of all text on cards and topic faces, the play button fill, and the ink shapes inside topic art.

### Secondary
- **Topic Coral** (topic-coral), **Topic Teal** (topic-teal), **Topic Amber** (topic-amber), **Topic Violet** (topic-violet): card art backgrounds, the card back's header strip, the face-down deck, and the one accent shape inside each topic picture (the next colour in the rotation). A card's colour comes from its main topic's position in the topic list, modulo four, so the same topic always looks the same and the colours spread evenly. The violet ships lighter than the direction contract's #6C63FF; the build value keeps 13px ink labels legible on the card back's violet strip (about 5.8:1 instead of about 4.1:1).

### Tertiary
- **Amber as chrome accent**: beyond its topic role, Topic Amber is the single interface accent: the navigation bar's selected indicator, the text cursor, selection handles, and text selection (at 40% alpha).

### Neutral
- **Peach Cream** (table-peach): the light-mode table and navigation bar (the user's pick: warm, not grey).
- **Ink Muted** (ink-muted): secondary text on card stock in both themes (the kind and deadline line), and secondary text on the peach table in light mode.
- **Stock Muted** (stock-muted): secondary text on the ink table in dark mode (list reasons, unselected navigation labels and icons).
- **Keyline on Ink** (keyline-on-ink) and **Keyline on Peach** (keyline-on-stone token): the hairline around cards and between list rows. On the light table it helps carry the card edge.

### Named Rules
**The Rotating Suit Rule.** Topic colours are assigned by topic index, never by meaning. No colour stands for a party, a position, urgency or success, and no screen adds a fifth.

**The Ink-On-Everything Rule.** Text on card stock and on any topic colour is always ink. Never set white or stock text on a topic colour, and never use a topic colour as a text colour.

**The One Amber Rule.** Interface chrome has one accent, amber, and it always means "selected": the navigation indicator, a starred action in Wirkung, a picked Lebenslage, a topic set to "mehr", and text selection. Buttons are ink or stock, never coloured.

## Typography

**Display Font:** Unbounded (bundled, OFL; ExtraBold 800)
**Body Font:** Albert Sans (bundled, OFL; Medium 500 to ExtraBold 800)

**Character:** Unbounded is wide, round and loud, a game-box face that makes a neutral civic question feel like a card worth picking up. Albert Sans is a warm, open grotesque that stays readable at 13 to 17px and holds its weight next to Unbounded.

### Hierarchy
- **Headline** (Unbounded 800, 28px, line-height 1.1, -0.02em): reserved for screen headings; the Für-dich screen deliberately has none (the tab names it).
- **Card Title** (Unbounded 800, 21px, line-height 1.1, -0.02em): the question on the card front, message titles on the table, and the "Alle Aktionen" app bar title. On cards it steps down to 18px, then 16px, to fit the whole question into five lines.
- **Title** (Albert Sans 700, 17px, line-height 1.25): list-row titles in "Alle Aktionen" and the "Dafür spricht" / "Dagegen spricht" headings on the card back.
- **Body Strong** (Albert Sans 600, 16px, line-height 1.35): the reason line on the card front.
- **Body** (Albert Sans 500, 15px, line-height 1.4): summaries, arguments, counts and explanations.
- **Label** (Albert Sans 700, 13px, line-height 1.3): the kind and deadline line, fact chips, the card back's header strip.
- **Button labels** (Albert Sans 800, 16px filled, 15px text buttons) and **navigation labels** (Albert Sans 700, 12px).

### Named Rules
**The Fit-Don't-Cut Rule.** A card question is never truncated mid-thought at normal sizes: it is set at the largest of 21, 18 or 16px that fits five lines, honouring the system text scale. Ellipsis is the last resort.

**The One Loud Voice Rule.** Unbounded is reserved for headings and card questions. Body, labels, buttons and navigation are always Albert Sans.

## Layout

A single-column phone layout on a 4px grid, with steps of 4, 8, 12, 16, 24 and 32px. Screen content is inset 24px from the edges; card content is inset 20px, and the card art sits in a 10px margin of card stock, like the picture on a playing card.

The Für-dich screen ("Meine Aktionen" tab) has no header: the tab names it and the dots count the cards, so the space goes to the cards (user decision). It has two bands: the fan filling the height, and a footer row with page dots on the left and the "Alle … ansehen" text button on the right. The front card is at most 340px wide (screen width minus 88px) and as tall as the table allows, up to playing-card proportions (height 1.75 × width). On the card front the art takes whatever height the words leave, never less than a 72px band; the words never push it out.

The fan ends: after the last action card comes a closing card (card stock, the face-down deck, "Das war deine N.", then "Alle … ansehen" as the filled button and "Zurück zur ersten Karte"). While it is in front, the footer's "Alle … ansehen" steps back. With nothing beyond the hand it says "Mehr gibt es gerade nicht" instead. The dots count it as one more position. No extra copy on it (user: no filler text).

"Alle Aktionen" is a plain list on the table: an explanatory body line, then full-width rows separated by keylines, each with a 56px thumbnail card, the title, up to two lines of reason and the kind and deadline line.

"Mein Impact" (the Wirkung tab) is the pile the played cards land on. No headline (the tab names it): the header is the played pile (the last three played cards face up, 50 by 68px with a 3px stock rim, newest upright on top, the ones below fanned out) beside the count in Card Title ("4 Aktionen erledigt") and a muted Body Strong line ("1 davon mit Berichten" or "Noch keine Berichte dazu"). No explanatory line (user: not necessary). Below it, one keyline-separated row per played action, newest first, with 24px above and below so each action reads as its own block, laid out like an "Alle Aktionen" row (thumbnail, Title, the kind, source and done-date line) with the star at the right, level with the title. Under each row sit its reports as flat news tiles, up to two, then a text button for the rest. While loading, the row shows a thin muted progress line. When nothing is found yet, or the search has not run, it shows a muted note with an icon. (Tried and rejected: each action as a face-up card with reports inside. User: too much like the hand's cards, and the action was hard to tell apart from its reports.)

"Mein Profil" is three sections on the table, divided by keylines like the Wirkung rows, each under a Card Title heading and with no brand header (the tab names it). **Deine Werte** is the signature of the profile: each of the four axes is its own block in a topic colour, in the rotation order (Wirtschaft coral, Diplomatie teal, Freiheit amber, Wandel violet). The colour belongs to the axis, never to a side. Each block (18px corners, 18px 16px padding, ink on the face) has the axis name in Unbounded 16px, then a continuous track with only the centre marked, an 8px ink bar from the centre to the marker that shows how far the user leans, and a 28px stock marker with a 4px ink ring. Under the track, both poles in Label 800, worded like the questionnaire's answers: Umverteilung ↔ Freier Markt, National ↔ International, Bürgerrechte ↔ Sicherheit, Bewahren ↔ Verändern (-2 is the left answer). The marker slides out from the centre on first show (520ms, ease-out quart, instant under reduced motion). Screen readers hear a reading ("Wirtschaft: eher Umverteilung, zwischen …"). Without answers the section reads "Noch nicht ausgefüllt." Below the blocks is an outlined pill button, "Fragebogen ausfüllen" (or "… erneut ausfüllen").

**Dir wichtig** lists only the picked public Lebenslagen as read-only outlined pills; "Bearbeiten" opens the picker in a sheet. **Deine Themen** shows only the topics that steer the feed (set to mehr or weniger, or learned), mehr first, and they can be tapped there; "Anpassen" opens all topics in a sheet. Full lists never sit on the profile itself (user: too many chips were overwhelming).

**Sheets** (picker, all topics): a modal bottom sheet in the table colour with a drag handle, opening at 90% height, content inset 24px. They follow changes at once.

The **Lebenslagen picker** (shared with onboarding) has the Card Title "Was ist dir wichtig?", muted explanations, a pill search field on the raised table fill, and area headings in Title type. Its chips are pills of their own (not Material chips) so long labels wrap: outlined when not picked, amber with ink text and a check (or the lock for private groups) when picked, 48dp minimum height. **Topic chips** are compact outlined pills with a 48dp tap target: "mehr" fills amber with ink text, "weniger" mutes text and outline, and the level is spelled out after the topic. Learned topics carry a sparkle icon (not a text glyph).

The **star** follows an action: the user wants to hear when something new turns up (push comes later; for now the star is only kept on the device, encrypted). Unstarred it is a muted outline star; starred it is marked like the selected navigation destination, a 40dp amber disc with a filled ink star, inside a 48dp target. A selection haptic accompanies it, and the star pops in with a short scale (instant under reduced motion). Stars go on actions only, never on single reports (user decision). With no played cards the tab shows the face-down deck message instead.

**Onboarding** is two screens on the table, following the system setting like the rest. **The values questionnaire ("Dein Bild")**: a progress row of eight dots (the current one 22px wide, past ones full, future ones at 30%) with a muted "Überspringen" text button. Below it **Dein Bild** (`WerteBild`), an abstract picture on a #F4F1EA sheet with 18px corners (a keyline edge while unframed): one flat shape per axis in its colour (circle Wirtschaft, half disc Diplomatie, rounded bar Freiheit, triangle Wandel), overprinting each other with multiply, plus an ink stroke once four questions are answered and eight ink dots, one per answer. Answers move, turn and scale the shapes and glide there (280ms); unanswered shapes are dashed ink outlines, faded unless their axis is being asked. Nothing in the picture reads as a side. Under it the fixed prompt "Was passt eher zu dir?" (Card Title, centred) and a muted line, then one question per card: both statements side by side (Body 600, ink, both left-aligned) split by a vertical "oder" rule, and below them, inset 10px, a block in the axis colour with the slider. No axis name and no pole labels while answering; those belong to the profile. The slider is **continuous** (-2.0 to +2.0): tap, drag, or tap a statement (leans to ±1). It catches softly in the centre ("Beides gleich") with a selection haptic. Unanswered, an empty ring waits in the centre and the block reads "Zieh oder tippe auf eine Seite"; then "Eher das" or "Genau das" with an arrow to the side, so the answer never rests on position alone. The statement leaned away from fades back. Screen readers get a slider ("Eher die erste Aussage"). Moving on deals the next card (460ms): the answered card is laid aside to the left, tipping up to 9° round its bottom edge, shrinking slightly and fading, while the next comes in at a slant from the right and straightens (ease-out cubic in, ease-in cubic out). System Back steps back a question and deals the other way; instant under reduced motion. After "Fertig" the **reveal** (1.4s, instant under reduced motion): the question fades down, the picture grows to the middle and an ink frame (10px) with a light mat (14px, #FFFCF8) grows around it, lying on the table with the card shadow, with a light haptic as it closes; then "Dein Bild" (Headline), "Aus deinen Antworten. Kein anderes sieht genau so aus." and a muted "Nr. 77 822 · 12.11.2026" (a number that cannot be read back into answers). "Weiter" (table button) and "Antworten ändern" (outlined). With nothing answered there is no reveal. Next step (planned): the framed picture is packed into the Rucksack on the Dir-wichtig page. **"Über dich"**: Headline, muted line, then "Dein Abgeordneter" (Card Title) with a pill PLZ field on the raised table fill and a "Suchen" table button; the result is a flat slip of card stock (ink disc with the ballot icon, name in Title, party and Wahlkreis in Label). Several Wahlkreise are offered as choice pills (amber with a check when chosen), not a dropdown. Below a keyline sits the Lebenslagen picker, and "Fertig" is pinned at the bottom.

The **letter screen** ("Brief schreiben", a full-screen dialog) is a form on the table under the standard app bar: the decision as an "Alle Aktionen" row (thumbnail, Title, the body and meeting date in Label, "Vorlage ansehen"), then keyline-separated sections. **An**: the Fraktion offices as checkbox rows (ticked is amber with an ink check; an office without an address is muted and cannot be ticked), and the members in an expandable row. **Was ist dir wichtig?**: the notes field, then "Brief erstellen" as the table button; once a letter exists it steps back to an outlined "Neu erstellen", because sending is now the main step. The drafted letter is **a sheet of card stock lying on the table** (26px corners, keyline, card shadow; the one non-action object allowed a shadow, because it is the thing the user sends): a "Dein Brief" label with "Zum Ändern hineintippen", a faint rule, and the letter in Albert Sans 16 at line-height 1.5, ink, editable in place. Under it a muted signing hint, "Kopieren" (outlined) beside "Mail-App" (table button), and "Adressen kopieren (für Webmail)".

The **in-app browser** keeps the site itself untouched; only its chrome is on the table: the app bar with close, a muted lock and the host in Title type (not the display face: it is an address, not a heading), the overflow menu on the raised table fill, and a 2px ink progress line that settles into a keyline.

The **"Fertig" bar** (letter and browser) is flat on the table with a keyline above: a muted hint on the left ("Mitgemacht? Dann tippe auf Fertig.") and "Fertig" with a check as the table button on the right. A bar, not a floating button, so it never covers a site's own submit button.

**Form fields** on the table: raised table fill, keyline border, 14px corners (pills for one-line search and PLZ fields), a 1.5px muted outline on focus, muted labels and hints. **Snackbars** float and invert the table like its buttons. **Checkboxes** are amber with an ink check when ticked (the One Amber Rule).

## Elevation & Depth

Depth is reserved for things lying on the table. Cards and the face-down deck cast soft, blurred shadows straight down; their stacking in the fan (offset, rotation, slight scale-down, dimmed content) does the rest. Everything that is not a card is flat: no shadow on rows, chips, buttons, app bars or the navigation bar, and no Material surface tint.

### Shadow Vocabulary
- **Card on table** (0 14px 30px, shadow colour #00000099 dark, #10182033 light): every action card, including the card in flight, the questionnaire's question card, and the drafted letter.
- **Deck card** (0 8px 16px, same shadow colour): the small face-down cards on loading and message states.

### Named Rules
**The Lying-On-The-Table Rule.** Only cards cast shadows, and shadows are always soft and straight down. A hard, offset or coloured shadow does not belong to this world.

## Shapes

Generously rounded, never sharp. Cards use 26px corners; the art band inside a card uses 18px, so the stock margin around it stays even. Small cards (list thumbnails, face-down deck) use 14px, with 11px on the art inside the 3px stock rim. Buttons, chips, the navigation indicator and the active page dot are pills. Topic art is built from a few flat geometric shapes (circles, rectangles, triangles, round-capped strokes) in ink, stock and one accent colour on the topic face; it never uses outlines for decoration, gradients or photography.

## Components

### Buttons
Big, solid and named after the act.
- **Shape:** full pill (999px), 52px minimum height, 12px 24px padding so a label can wrap at large text sizes.
- **Play button (on a card):** ink fill, card-stock label, Albert Sans 800 16px, full card width. The same button sits on both faces of the card.
- **Button on the table** (message states such as "Nochmal versuchen", onboarding's "Weiter" and "Fertig", "Brief erstellen", the "Fertig" bar; `MiColors.tableButton`): inverts the table, on-table colour as fill and table colour as label (stock on ink in dark mode, ink on stone in light), 200px minimum width.
- **Text button:** on-table colour, Albert Sans 800 15px, 48px minimum target ("Alle 7 ansehen").
- **Labels:** always the concrete action for the opportunity's kind ("Petition unterschreiben"), never a generic "Mitmachen" or "Los".

### Chips
- **Fact chip (card back):** transparent fill, 1px ink outline, pill, 6px 12px padding, Label type in ink. Registry facts only (dates, supporter count, place, districts); support counts are information, never a ranking claim.
- **Kind chip (news tile):** the same pill on the table, 1px on-table-muted outline, Label type in the on-table colour: "Stellungnahme" or "Hintergrund". Plain news carries no chip. No colour coding by kind.

### News tile
A report about a played action, flat on the table (not a card, so no shadow): raised table fill (#243242 dark, light enough to separate clearly from the ink table; #FFF8F0 light) with a keyline border, 14px corners, 16px 12px padding. It holds the optional kind chip, the title (Body Strong, up to three lines), the snippet (Body, muted, up to two lines) and a muted Label line with source host, date and an open-in-new icon. Tapping it opens the article in the in-app browser.

### Cards / Containers
- **Action card:** card stock with a keyline border and the card shadow, 26px corners, 20px inner inset. **Front:** topic art band on top, then the question (Card Title), one reason line (Body Strong), the kind and deadline line (Label, ink muted), the play button. **Back:** a topic-colour header strip with kind and source plus a close button ("Karte umdrehen"), the summary, fact chips, "Dafür spricht" and "Dagegen spricht" with small ink dot bullets, content fading out above the play button.
- **Reason line:** the personal sentence when one exists; otherwise the Lebenslage label quoted as the user picked it ("Weil du „…“ angegeben hast"), a neutral sentence for private Lebenslagen, or the learned interest.

### Navigation
- **Bottom navigation bar:** 72px, table colour, no tint. Three destinations: Mein Profil, Meine Aktionen, Mein Impact. Selected: amber pill indicator with an ink icon and an on-table label; unselected: muted icon and label. Wirkung carries a count badge for played cards not yet seen there.
- **App bar (pushed screens):** table colour, on-table foreground, Card Title type, no tint, system back.

### The Hand (signature component)
The top five actions by match, best first, as a fan: the front card upright, the next cards offset 22px right and 6px down per step, rotated about 4 degrees per step around their bottom edge, scaled down 3.5% per step, their words fading out so only colour and art show. Up to three cards are visible behind the front. A horizontal swipe moves through the hand and snaps (280ms, ease-out quart); a fling advances one card. Page dots show position (active dot 22px wide, others 8px, inactive at 30% on-table colour).

There is no weekly dealing: the hand is always the current top five and refills as cards are played. A card picked in "Alle Aktionen" moves to the front of the hand; the list itself marks nothing as already in the hand.

- **Flip:** tapping the front card turns it over on the Y axis (300ms, ease-out quart, with perspective).
- **Play:** when the action is done, the card shrinks, turns and flies to the Wirkung destination (520ms, ease-in cubic, fading over the last quarter), with a medium haptic on launch and a light one on landing; the fan closes up and a screen-reader announcement confirms it.
- **Empty, loading and error states:** three face-down deck cards (92 by 132px, topic colour inside a 4px stock border, slightly fanned) above a Card Title message and a muted body line. Loading reads "Deine Karten werden gemischt …".
- **Reduced motion:** when the system disables animations, every swipe, flip and flight becomes an instant cut.

## Do's and Don'ts

### Do:
- **Do** take every colour from the card-table tokens: table, card stock, ink, the two muted text colours, keylines and the four topic colours.
- **Do** derive a card's colour and art from its main topic via the rotation, so the same topic always looks the same.
- **Do** set all text on card stock and topic colours in ink.
- **Do** set card questions in Unbounded and fit them by stepping 21, 18, 16px over five lines before truncating.
- **Do** name the concrete action on every play button.
- **Do** give every motion an instant-cut path for reduced motion, and keep targets at 48dp or more.
- **Do** follow the system light or dark setting on every card-table screen.

### Don't:
- **Don't** put an eyebrow or kicker line above a heading.
- **Don't** let one colour dominate a screen or attach a topic colour to a party, position or verdict.
- **Don't** give shadows to anything but cards, and never use hard or offset shadows.
- **Don't** set body text, labels or buttons in Unbounded.
- **Don't** show a card's facts or arguments on its front; they live on the back.
- **Don't** mark cards in "Alle Aktionen" as already in the hand, with an icon or a label.

## Migration note

Every screen is on the card table: the app's MaterialApp theme is `miTheme` in light and dark, following the system, so pushed routes inherit it. The old look (`legacyTheme()`, `AppColors`, the green seed) is gone. The web teaser's "Mitmachen geht in der App" sheet is on the table too.
