# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

People in Dresden who care about politics but rarely act on it. They open the app on their phone for a few minutes, once or twice a week, to do one easy civic action that fits their life situation and values, and later want to see what came of it. They are average users, not policy experts: if a card isn't interesting within about 5 seconds, they close the app.

## Product Purpose

MeinImpact turns passive political interest into one concrete, low-effort democratic action per week, and then shows what happened because of it. Actions are real opportunities from official registries and calendars: petitions, consultations, plan displays, surveys, and upcoming Dresden city council decisions, at EU, Bund, Sachsen and Dresden level. Success means a user does an action, comes back, and sees its effect (the "Wirkung" tab).

## Positioning

- Actions come directly from official registries and Dresden's council system (OParl), not from campaigns or a single organisation's agenda.
- Matching to the user's life situation (Lebenslagen) and values happens on the device. Political profiles never leave the phone.
- Actions are done inside the app: an in-app browser with a "Fertig" button, or an AI-drafted letter to the council groups handling an upcoming decision.
- Follow-up: news found about the actions a user has done.

## Operating Context

- Short mobile sessions, German only, du-form.
- Main surfaces: onboarding (life situations, values), the Aktionen feed, action detail, in-app action browser with "Fertig", letter pop-up for council decisions, and the Wirkung tab with news about done actions.
- Released through Google Play internal testing first, to beta testers.

## Capabilities and Constraints

- Flutter app. Android ships first; iOS follows after the Android release with the same look. The web build is only a teaser that points to the app.
- One custom MeinImpact visual identity on both Android and iOS. Material is the building kit underneath, not the design language.
- Political neutrality: no ranking or wording that favours a party or position. Question-style titles stay neutral, and should not keep repeating "Soll".
- Privacy by design: value profile and topics stay on the device; no accounts in the MVP.
- Feed ranks rather than filters; only expert-only items are hidden.
- Gamification is planned but not designed yet.

## Brand Commitments

- Name: MeinImpact. Voice: German, du-form, friendly.
- No binding colours, typeface or logo yet. The landing page (dark/gold) and the app (light/green) are both placeholders; the app's design work may set the brand, and the landing page follows later.

## Evidence on Hand

- Real action data from the live backend (registries, OParl decisions, news about tracked actions).
- No testimonials, user numbers, press or impact statistics yet. Do not invent any.

## Product Principles

1. Would an average person enjoy this card in 5 seconds? That is the bar for every screen.
2. Fun and engaging, like Duolingo, never like a government form.
3. Neutral on content, warm in tone.
4. One action, low effort: every screen leads toward doing something, not reading more.
5. Show the effect: an action should feel like it went somewhere.
