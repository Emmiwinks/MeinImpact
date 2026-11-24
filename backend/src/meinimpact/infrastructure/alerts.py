"""Problems someone should look at without having to open /admin.

Always logged; also sent to Sentry when MEINIMPACT_SENTRY_DSN is set, which
mails them. Messages name sources and counts only, never user data.
"""

import logging

import sentry_sdk

logger = logging.getLogger(__name__)


def init_sentry(dsn: str | None, environment: str) -> None:
    """No-op without a DSN. Sends no personal data: no IPs, cookies,
    headers or request bodies (a location request carries a PLZ)."""
    if not dsn:
        return
    sentry_sdk.init(
        dsn=dsn,
        environment=environment,
        send_default_pii=False,
        max_request_body_size="never",
        traces_sample_rate=0.0,
    )


def alert(message: str) -> None:
    logger.warning("ALERT: %s", message)
    if sentry_sdk.is_initialized():
        sentry_sdk.capture_message(message, level="warning")
