"""Detail readers: the full text behind thin list entries."""

import httpx

from meinimpact.infrastructure.listings.http import CrawlPolicy, PoliteHttpClient
from meinimpact.infrastructure.listings.sources.eu_have_your_say import (
    EuHaveYourSayDetailReader,
    parse_initiative_summary,
)
from meinimpact.infrastructure.listings.sources.openpetition import (
    OpenPetitionDetailReader,
    parse_petition_text,
)
from tests.listing_fakes import make_listing

_PETITION_PAGE = """
<html><body>
  <nav>Startseite Petitionen</nav>
  <div id="petition-main">
    <ul><li><button>Pro &amp; Contra</button></li></ul>
    <p>Petition richtet sich an: Stadtrat Dresden</p>
    <p>Die Kita GARTENKINDER soll   geschlossen werden.</p>
    <script>track()</script>
    <form><input name="email"></form>
  </div>
</body></html>
"""


def test_petition_text_is_the_main_block_without_noise() -> None:
    assert parse_petition_text(_PETITION_PAGE) == (
        "Petition richtet sich an: Stadtrat Dresden "
        "Die Kita GARTENKINDER soll geschlossen werden."
    )


def test_petition_page_without_main_block_has_no_text() -> None:
    assert parse_petition_text("<html><body><p>x</p></body></html>") is None


def test_eu_summary_prefers_german_and_strips_html() -> None:
    payload = {
        "dossierSummary": "English summary",
        "initiativeTranslations": [
            {"language": "EN", "field": "SUMMARY", "value": "<p>English</p>"},
            {
                "language": "DE",
                "field": "SUMMARY",
                "value": "<p>Mit den EU-Vorschriften wird CO<sub>2</sub> erfasst.</p>",
            },
        ],
    }

    assert parse_initiative_summary(payload) == (
        "Mit den EU-Vorschriften wird CO 2 erfasst."
    )


def test_eu_summary_falls_back_to_english_dossier_summary() -> None:
    assert parse_initiative_summary({"dossierSummary": " English  text "}) == (
        "English text"
    )
    assert parse_initiative_summary({}) is None


async def _no_sleep(_: float) -> None:
    return None


def _http(responses: dict[str, httpx.Response]) -> PoliteHttpClient:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        return responses[request.url.path]

    return PoliteHttpClient(
        policy=CrawlPolicy(default_delay_s=0),
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        sleep=_no_sleep,
    )


async def test_readers_fetch_the_listing_detail() -> None:
    http = _http(
        {
            "/x": httpx.Response(200, text=_PETITION_PAGE),
            "/info/law/better-regulation/brpapi/groupInitiatives/16240": (
                httpx.Response(200, json={"dossierSummary": "Summary"})
            ),
        }
    )

    petition = await OpenPetitionDetailReader(http).read(make_listing("x"))
    initiative = await EuHaveYourSayDetailReader(http).read(make_listing("16240"))

    assert petition is not None and petition.startswith("Petition richtet")
    assert initiative == "Summary"
