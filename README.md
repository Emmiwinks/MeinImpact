# MeinImpact

MeinImpact is a cross-platform civic action app. It helps politically
interested but passive people take one concrete, low-effort democratic action
per week and later understand what happened because of that action.

The repository is split into two product surfaces:

- `backend`: Python 3.14, FastAPI, PostgreSQL, Docker Compose, HTTPS streaming
  and Server-Sent Events (SSE).
- `app`: Flutter client prepared for Android, iOS, web, Windows, macOS, and
  Linux.

Core principles:

- Political neutrality and transparent recommendation scoring.
- Minimal viable data, privacy by design, and no data monetization.
- Stateless backend processes. Persistent state belongs in PostgreSQL or a
  managed infrastructure dependency.
- No AI provider secrets in the client. Mistral is called by the backend.
- Unit test coverage must stay at or above 95% for backend and app code.

Start here:

- `doc/product_concept.md` for the product concept.
- `doc/architecture.md` for the technical architecture.
- `doc/security.md` for API, mobile, and AI security requirements.
- `Agent.md` for coding and collaboration rules for future agents.
