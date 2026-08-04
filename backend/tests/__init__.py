"""Test suite package root.

Needed so mypy resolves `tests/support/httpx_mock.py` consistently as
`tests.support.httpx_mock` — without this file, mypy treats `tests/` as an
implicit namespace root and also finds the same file as `support.httpx_mock`
(since `tests/support/__init__.py` exists), reporting it as "found twice
under different module names".
"""
