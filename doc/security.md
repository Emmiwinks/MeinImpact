# Security Baseline

MeinImpact handles sensitive civic and political data. Security and privacy are
product requirements, not optional hardening tasks.

## Sources

This baseline follows guidance from OWASP REST Security, OWASP API Security Top
10 2023, OWASP Mobile Application Security, FastAPI streaming documentation,
MDN Server-Sent Events documentation, Mistral API documentation, and Flutter
deployment guidance.

## API Security Requirements

- Serve production APIs only over HTTPS.
- Require bearer access tokens for all non-public endpoints.
- Validate JWT issuer, audience, expiry, not-before, and signature.
- Do not accept unsigned JWTs or algorithm choices from token headers.
- Validate request content types and reject unexpected content types.
- Validate all input lengths, formats, enum values, and object ownership.
- Enforce authorization at every endpoint and every object lookup.
- Use semantic status codes such as `401`, `403`, `404`, `413`, `415`, and
  `429`.
- Add rate limiting and abuse controls before production AI usage.
- Do not leak stack traces or internal error details to clients.
- Add security headers to all responses.

## Mobile Security Requirements

- Do not trust client-side checks for authorization or workflow sequencing.
- Do not hardcode backend secrets or AI provider keys into the app.
- Store tokens in platform secure storage, not regular preferences.
- Use HTTPS for every backend call.
- Consider certificate pinning after the production certificate and release
  process are stable.
- Minimize permissions and request them only when needed.
- Disable verbose logging of sensitive data in release builds.
- Add Android Play Integrity and Apple App Attest verification before public
  production launch.

## Local Identity Data Requirements

- Keep real names, private addresses, and similar identity values on the device
  when the backend does not strictly need them.
- Encrypt locally stored identity values with platform security APIs.
- Use placeholders such as `{{USER_FULL_NAME}}` in prompts and drafts that flow
  through the backend or Mistral.
- Replace placeholders with real values only inside the app, immediately before
  the user sends a reviewed external email or letter.
- Do not persist placeholder-resolved drafts in backend logs, analytics, or
  databases.
- Any server-side identity processing must be justified by a documented feature,
  minimized to the fields required, and covered by deletion/export behavior.

## Stateless Backend Requirements

- Backend instances must be replaceable without losing durable state.
- Do not store sessions, rate counters, background job state, or user progress in
  process memory for production features.
- Use PostgreSQL or a managed external dependency for durable coordination.
- Design every endpoint to validate the current workflow state from persistent
  data.

## AI Safety Requirements

- Mistral calls must happen server-side.
- Prompts must include neutrality and non-manipulation constraints.
- Generated drafts must be editable by users before submission.
- Prompts must use local placeholders instead of real identity values whenever
  the real values are not required for model reasoning.
- Store only the minimum draft data needed for the user experience and audit
  requirements.
- Log AI metadata and failures without logging full sensitive prompts or drafts.
- Add content filters for anti-democratic, discriminatory, or unconstitutional
  content before production.

## SSE and Streaming Requirements

- SSE streams must use `text/event-stream`.
- Events must avoid secrets and unnecessary personal data.
- Streams must terminate cleanly and send an explicit completion event.
- Long-running streams must handle client disconnects without leaking tasks.
- Proxies must be configured to avoid buffering streaming responses.

## Initial Authentication Model

The initial scaffold uses anonymous installation sessions to protect API
endpoints from completely unauthenticated access while keeping the app publicly
available. This is not enough for production by itself.

Production authentication must add:

- Refresh token rotation with hashed token storage.
- Device or app integrity checks.
- Server-side rate limits per user, installation, IP range, and action type.
- Optional stronger identity verification for actions that require a real human.
- Account deletion, data export, and revocation flows.
