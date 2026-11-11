---
version: 1
slug: "tures-feed-presentation-aktionen-tab-dart-1f249f96"
primary_target: "app/lib/src/features/feed/presentation/aktionen_tab.dart"
related_targets: ["app/lib/src/features/feed/presentation/widgets/opportunity_detail_dialog.dart","app/lib/src/app/main_tab_screen.dart"]
---

#Meine Aktionen  (action loop)

Scope: the Für-dich tab (hand of cards + "Alle ansehen"), the card's detail side, and the done moment. Visitor mode: Operate. Platform: Flutter, Android first, dark and light themes following the system.

Audience and job: people in Dresden, a few minutes on the phone; "show me what fits me, let me do one thing". Actions are ranked on-device by match, best first, each with the reason it fits this user. Little text first; detail on demand.

Constraints: neutrality (topic colours rotate, no party colour dominates), Material navigation/back gesture, 48dp targets, German du-form, real registry facts only. Question titles as they are (median 46 chars, up to ~110): card titles must hold four lines. No weekly dealing (roadmap): the hand is the top 5 by match and refills as cards are played.

Reason fallback quotes the Lebenslage label ('Weil du „<label>“ angegeben hast'); a du-clause per Lebenslage is a later content task (user: "Keep the quote for now"). No in-hand marker in "Alle Aktionen" (user: "no icon or label. not necessary.").

Open: other tabs (Profil, Wirkung, onboarding, letter) migrate in later passes.

## Direction contract

THESIS: Your actions are a hand of cards dealt to you, not a feed. Five cards, best match in front, each saying why it is yours; you play one and it goes onto your Wirkung pile. Refuses the category's scrolling list of same-size white cards.

OWN-WORLD: A card table. Dark: ink #101820 table, card stock #F4F1EA. Light: pale stone table, same card stock with an ink keyline. Card faces in rotating topic colours (coral #FF5A5F, teal #2EC4B6, amber #FFBF3C, violet #6C63FF) carrying flat geometric topic art of a few shapes. Unbounded for card titles, Albert Sans for everything else. Rounded 26 corners on cards, pill buttons, soft offset shadows on the table.

STORY: The visitor sees their hand, reads the front card's question and why it fits them, flips it for the facts and both sides, plays it, and watches it fly onto the Wirkung pile while the next card moves up. Everything else is one tap away in "Alle ansehen".

FIRST VIEWPORT: Header "Deine Hand" with the card count. (Stadtteil dropped 2026-11-11, user: "Drop it for now" — needs a postcode→Stadtteil table; on the maybe roadmap.) A fan of five cards fills the middle: the front card upright and large (art band on top, kind and deadline line, question in Unbounded up to four lines, one reason line, "Karte spielen" pill at the bottom), two or more cards peeking behind it, rotated right. Under the fan: page dots and "Alle ansehen". Bottom navigation bar: Profil, Für dich, Wirkung.

FORM: Brief-led direction "Deine Hand" (own grounded candidate from the user's brief, chosen over five rolled hands). seed:1c6bdf6dfb8d2330. Signature interaction: card play, the card scales and flies into the Wirkung destination with a haptic, and the fan closes up. Motion grammar: horizontal swipe with snap through the fan, a 300ms Y-axis flip for detail, emphasised ease-out; all motion cuts instantly when the system disables animations.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
