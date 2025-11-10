"""tests for library_service rules."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Dict, List

import pytest

import database
from services import library_service


# helpers

def _add_book(
    title: str,
    author: str,
    isbn: str,
    *,
    total: int = 1,
    available: int | None = None,
) -> Dict:
    """add a seed book and return it."""
    available_copies = total if available is None else available
    inserted = database.insert_book(title, author, isbn, total, available_copies)
    assert inserted, "seed book insert failed"
    book = database.get_book_by_isbn(isbn)
    assert book is not None, "seed book lookup failed"
    return book


def _seed_borrow_record(
    patron_id: str,
    book_id: int,
    *,
    borrow_days_ago: int = 0,
) -> None:
    """add a seed borrow record."""
    borrow_date = datetime.now() - timedelta(days=borrow_days_ago)
    due_date = borrow_date + timedelta(days=14)
    ok = database.insert_borrow_record(patron_id, book_id, borrow_date, due_date)
    assert ok, "seed borrow record failed"
    database.update_book_availability(book_id, -1)


# r1 add_book_to_catalog


def test_add_book_accepts_valid_payload() -> None:
    success, message = library_service.add_book_to_catalog(
        "book alpha", "author one", "1000000000001", 4
    )
    assert success is True
    assert "successfully" in message.lower()
    stored = database.get_book_by_isbn("1000000000001")
    assert stored is not None
    assert stored["total_copies"] == 4
    assert stored["available_copies"] == 4


def test_add_book_rejects_blank_title() -> None:
    success, message = library_service.add_book_to_catalog(
        "   ", "author two", "1000000000002", 1
    )
    assert success is False
    assert "Title is required" in message


def test_add_book_rejects_long_author() -> None:
    long_name = "A" * 101
    success, message = library_service.add_book_to_catalog(
        "book beta", long_name, "1000000000003", 2
    )
    assert success is False
    assert "Author must be less than 100 characters" in message


def test_add_book_requires_numeric_isbn() -> None:
    success, message = library_service.add_book_to_catalog(
        "book gamma", "author three", "1234567890ABC", 3
    )
    assert success is False
    assert "digits" in message


def test_add_book_rejects_duplicate_isbn() -> None:
    first = library_service.add_book_to_catalog(
        "book delta", "author four", "1000000000004", 2
    )
    assert first[0] is True
    duplicate = library_service.add_book_to_catalog(
        "book delta copy", "author five", "1000000000004", 1
    )
    assert duplicate[0] is False
    assert "already exists" in duplicate[1]

# r2 get_all_books


def test_get_all_books_returns_sorted_catalog() -> None:
    titles = [
        ("zeta volume", "author sort", "1000000000033"),
        ("alpha manual", "author sort", "1000000000034"),
        ("middle text", "author sort", "1000000000035"),
    ]
    for title, author, isbn in titles:
        _add_book(title, author, isbn, total=2)

    catalog = database.get_all_books()
    assert [entry["title"] for entry in catalog] == sorted(entry["title"] for entry in catalog)


def test_get_all_books_reflects_current_availability() -> None:
    book = _add_book("availability check", "author stock", "1000000000036", total=3)
    _seed_borrow_record("112233", book["id"])
    refreshed = database.get_all_books()
    target = next(entry for entry in refreshed if entry["id"] == book["id"])
    assert target["available_copies"] == 2
    assert target["total_copies"] == 3

# r3 borrow_book_by_patron


def test_borrow_book_requires_valid_patron_id() -> None:
    book = _add_book("book epsilon", "author six", "1000000000005", total=1)
    success, message = library_service.borrow_book_by_patron("12345", book["id"])
    assert success is False
    assert "6 digits" in message


def test_borrow_book_reports_missing_book() -> None:
    success, message = library_service.borrow_book_by_patron("123456", 999)
    assert success is False
    assert "Book not found" in message


def test_borrow_book_blocks_when_unavailable() -> None:
    book = _add_book("book zeta", "author seven", "1000000000006", total=1, available=0)
    success, message = library_service.borrow_book_by_patron("123456", book["id"])
    assert success is False
    assert "not available" in message


def test_borrow_book_enforces_patron_limit() -> None:
    patron = "654321"
    # seed five active borrows
    for i in range(5):
        book = _add_book(f"book {i}", "author pool", f"100000000001{i}")
        _seed_borrow_record(patron, book["id"])
    next_book = _add_book("book extra", "author pool", "1000000000019", total=2)
    success, message = library_service.borrow_book_by_patron(patron, next_book["id"])
    assert success is False
    assert "maximum borrowing limit" in message


def test_borrow_book_successfully_creates_record() -> None:
    patron = "555555"
    book = _add_book("book eta", "author eight", "1000000000020", total=2)
    success, message = library_service.borrow_book_by_patron(patron, book["id"])
    assert success is True
    reloaded = database.get_book_by_id(book["id"])
    assert reloaded["available_copies"] == 1
    records = database.get_patron_borrow_count(patron)
    assert records == 1
    assert "Due date" in message


# r4 return_book_by_patron

def test_return_book_updates_inventory_and_record() -> None:
    patron = "777777"
    book = _add_book("book theta", "author nine", "1000000000021", total=1)
    _seed_borrow_record(patron, book["id"], borrow_days_ago=1)
    success, message = library_service.return_book_by_patron(patron, book["id"])
    assert success is True
    reloaded = database.get_book_by_id(book["id"])
    assert reloaded["available_copies"] == 1
    assert "return" in message.lower()


def test_return_book_rejects_when_not_borrowed() -> None:
    patron = "888888"
    book = _add_book("book iota", "author ten", "1000000000022", total=1)
    success, message = library_service.return_book_by_patron(patron, book["id"])
    assert success is False
    assert "no active borrow record" in message.lower()


def test_return_book_sets_return_date() -> None:
    patron = "999999"
    book = _add_book("book kappa", "author eleven", "1000000000023", total=1)
    _seed_borrow_record(patron, book["id"], borrow_days_ago=3)
    success, _ = library_service.return_book_by_patron(patron, book["id"])
    assert success is True
    conn = database.get_db_connection()
    row = conn.execute(
        "SELECT return_date FROM borrow_records WHERE patron_id = ? AND book_id = ?",
        (patron, book["id"]),
    ).fetchone()
    conn.close()
    assert row["return_date"] is not None


def test_return_book_handles_invalid_book_id() -> None:
    success, message = library_service.return_book_by_patron("123456", 42)
    assert success is False
    assert "Book not found" in message


# r5 calculate_late_fee_for_book


def _seed_overdue_record(patron: str, book: Dict, *, days_overdue: int) -> None:
    borrow_date = datetime.now() - timedelta(days=14 + days_overdue)
    due_date = borrow_date + timedelta(days=14)
    ok = database.insert_borrow_record(patron, book["id"], borrow_date, due_date)
    assert ok, "seed overdue record failed"
    database.update_book_availability(book["id"], -1)


def test_late_fee_zero_when_returned_on_time() -> None:
    patron = "101010"
    book = _add_book("book lambda", "author twelve", "1000000000024", total=1)
    _seed_borrow_record(patron, book["id"], borrow_days_ago=1)
    result = library_service.calculate_late_fee_for_book(patron, book["id"])
    assert result["fee_amount"] == 0.0
    assert result["days_overdue"] == 0


def test_late_fee_half_dollar_for_each_day_first_week() -> None:
    patron = "202020"
    book = _add_book("book mu", "author thirteen", "1000000000025", total=1)
    _seed_overdue_record(patron, book, days_overdue=3)
    result = library_service.calculate_late_fee_for_book(patron, book["id"])
    assert result["fee_amount"] == pytest.approx(1.5)
    assert result["days_overdue"] == 3


def test_late_fee_switches_to_one_dollar_after_seven_days() -> None:
    patron = "303030"
    book = _add_book("book nu", "author fourteen", "1000000000026", total=1)
    _seed_overdue_record(patron, book, days_overdue=10)
    result = library_service.calculate_late_fee_for_book(patron, book["id"])
    expected = (7 * 0.5) + (3 * 1.0)
    assert result["fee_amount"] == pytest.approx(expected)
    assert result["days_overdue"] == 10


def test_late_fee_caps_at_fifteen_dollars() -> None:
    patron = "404040"
    book = _add_book("book xi", "author fifteen", "1000000000027", total=1)
    _seed_overdue_record(patron, book, days_overdue=60)
    result = library_service.calculate_late_fee_for_book(patron, book["id"])
    assert result["fee_amount"] == 15.0
    assert result["days_overdue"] == 60


# r6 search_books_in_catalog


def _seed_catalog() -> List[Dict]:
    books = [
        _add_book("alpha code", "writer one", "1000000000028", total=2),
        _add_book("alpha guide", "writer one", "1000000000029", total=1),
        _add_book("gamma notes", "scribe two", "1000000000030", total=3),
    ]
    return books


def test_search_title_partial_case_insensitive() -> None:
    _seed_catalog()
    results = library_service.search_books_in_catalog("alpha", "title")
    titles = {book["title"] for book in results}
    assert titles == {"alpha code", "alpha guide"}


def test_search_author_partial_case_insensitive() -> None:
    _seed_catalog()
    results = library_service.search_books_in_catalog("writer", "author")
    assert all("writer" in book["author"] for book in results)
    assert len(results) == 2


def test_search_isbn_exact_match() -> None:
    books = _seed_catalog()
    target = books[2]
    results = library_service.search_books_in_catalog(target["isbn"], "isbn")
    assert len(results) == 1
    assert results[0]["id"] == target["id"]


def test_search_invalid_type_returns_empty() -> None:
    _seed_catalog()
    results = library_service.search_books_in_catalog("alpha", "unknown")
    assert results == []


# r7 get_patron_status_report


def _seed_patron_activity(patron: str) -> Dict:
    active_book = _add_book("loan active", "writer three", "1000000000031", total=1)
    _seed_borrow_record(patron, active_book["id"], borrow_days_ago=5)
    history_book = _add_book("loan done", "writer three", "1000000000032", total=1)
    _seed_borrow_record(patron, history_book["id"], borrow_days_ago=20)
    database.update_borrow_record_return_date(patron, history_book["id"], datetime.now())
    return {"active": active_book, "history": history_book}


def test_patron_status_lists_active_loans() -> None:
    patron = "505050"
    books = _seed_patron_activity(patron)
    report = library_service.get_patron_status_report(patron)
    assert any(item["book_id"] == books["active"]["id"] for item in report["current_loans"])


def test_patron_status_counts_active_loans() -> None:
    patron = "606060"
    _seed_patron_activity(patron)
    report = library_service.get_patron_status_report(patron)
    assert report["active_count"] == 1


def test_patron_status_sums_late_fees() -> None:
    patron = "707070"
    books = _seed_patron_activity(patron)
    # make the active loan overdue by 10 days
    conn = database.get_db_connection()
    conn.execute(
        "UPDATE borrow_records SET borrow_date = ?, due_date = ? WHERE patron_id = ? AND book_id = ?",
        (
            (datetime.now() - timedelta(days=24)).isoformat(),
            (datetime.now() - timedelta(days=10)).isoformat(),
            patron,
            books["active"]["id"],
        ),
    )
    conn.commit()
    conn.close()
    report = library_service.get_patron_status_report(patron)
    assert report["total_late_fees"] > 0


def test_patron_status_includes_history() -> None:
    patron = "808080"
    books = _seed_patron_activity(patron)
    report = library_service.get_patron_status_report(patron)
    assert any(entry["book_id"] == books["history"]["id"] for entry in report["history"])
