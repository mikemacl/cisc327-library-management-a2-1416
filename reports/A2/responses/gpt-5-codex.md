Proposed addition: `tests/test_library_service.py`
```python
from datetime import datetime, timedelta

import pytest

import database
from library_service import (
    add_book_to_catalog,
    borrow_book_by_patron,
    calculate_late_fee_for_book,
    get_patron_status_report,
    return_book_by_patron,
    search_books_in_catalog,
)


def create_book(title: str, author: str, isbn: str, total_copies: int, available_copies: int | None = None) -> int:
    """Insert a book and return its generated id."""
    if available_copies is None:
        available_copies = total_copies
    conn = database.get_db_connection()
    cursor = conn.execute(
        """
        INSERT INTO books (title, author, isbn, total_copies, available_copies)
        VALUES (?, ?, ?, ?, ?)
        """,
        (title, author, isbn, total_copies, available_copies),
    )
    conn.commit()
    book_id = cursor.lastrowid
    conn.close()
    return book_id


def create_borrow_record(
    patron_id: str,
    book_id: int,
    borrow_date: datetime,
    due_date: datetime,
    return_date: datetime | None = None,
) -> None:
    """Insert a borrow record (optionally with a return date)."""
    conn = database.get_db_connection()
    conn.execute(
        """
        INSERT INTO borrow_records (patron_id, book_id, borrow_date, due_date, return_date)
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            patron_id,
            book_id,
            borrow_date.isoformat(),
            due_date.isoformat(),
            return_date.isoformat() if return_date else None,
        ),
    )
    conn.commit()
    conn.close()


def fetch_book(book_id: int):
    conn = database.get_db_connection()
    row = conn.execute("SELECT * FROM books WHERE id = ?", (book_id,)).fetchone()
    conn.close()
    return row


def fetch_borrow_record(patron_id: str, book_id: int):
    conn = database.get_db_connection()
    row = conn.execute(
        "SELECT * FROM borrow_records WHERE patron_id = ? AND book_id = ?",
        (patron_id, book_id),
    ).fetchone()
    conn.close()
    return row


# R1: add_book_to_catalog ----------------------------------------------------------------------


def test_add_book_to_catalog_success():
    success, message = add_book_to_catalog("New Book", "Jane Doe", "1234567890123", 3)

    assert success is True
    assert message == 'Book "New Book" has been successfully added to the catalog.'

    book = fetch_book(1)
    assert book is not None
    assert book["title"] == "New Book"
    assert book["available_copies"] == 3
    assert book["total_copies"] == 3


def test_add_book_to_catalog_rejects_duplicate_isbn():
    add_book_to_catalog("Original", "Author A", "1234567890123", 2)

    success, message = add_book_to_catalog("Duplicate", "Author B", "1234567890123", 1)

    assert success is False
    assert message == "A book with this ISBN already exists."

    conn = database.get_db_connection()
    count = conn.execute(
        "SELECT COUNT(*) AS c FROM books WHERE isbn = ?", ("1234567890123",)
    ).fetchone()["c"]
    conn.close()
    assert count == 1


def test_add_book_to_catalog_requires_exactly_13_digit_isbn():
    success, message = add_book_to_catalog("Invalid ISBN", "Author", "123", 1)

    assert success is False
    assert message == "ISBN must be exactly 13 digits."

    conn = database.get_db_connection()
    count = conn.execute("SELECT COUNT(*) AS c FROM books").fetchone()["c"]
    conn.close()
    assert count == 0


def test_add_book_to_catalog_requires_numeric_isbn():
    success, message = add_book_to_catalog("Non Numeric ISBN", "Author", "123456789012X", 1)

    assert success is False
    assert message == "ISBN must be exactly 13 digits."


def test_add_book_to_catalog_requires_positive_total_copies():
    success, message = add_book_to_catalog("Zero Copies", "Author", "9999999999999", 0)

    assert success is False
    assert message == "Total copies must be a positive integer."


# R3: borrow_book_by_patron --------------------------------------------------------------------


def test_borrow_book_by_patron_success():
    book_id = create_book("Borrowable Book", "Author", "1111111111111", 2)

    success, message = borrow_book_by_patron("123456", book_id)

    assert success is True
    assert message.startswith('Successfully borrowed "Borrowable Book". Due date:')

    book = fetch_book(book_id)
    assert book["available_copies"] == 1

    record = fetch_borrow_record("123456", book_id)
    assert record is not None
    borrow_date = datetime.fromisoformat(record["borrow_date"])
    due_date = datetime.fromisoformat(record["due_date"])
    assert due_date - borrow_date == timedelta(days=14)
    assert record["return_date"] is None


def test_borrow_book_by_patron_rejects_invalid_patron_id():
    book_id = create_book("Borrowable Book", "Author", "2222222222222", 1)

    success, message = borrow_book_by_patron("12A456", book_id)

    assert success is False
    assert message == "Invalid patron ID. Must be exactly 6 digits."


def test_borrow_book_by_patron_rejects_missing_book():
    success, message = borrow_book_by_patron("123456", 999)

    assert success is False
    assert message == "Book not found."


def test_borrow_book_by_patron_requires_availability():
    book_id = create_book("Unavailable Book", "Author", "3333333333333", 1, available_copies=0)

    success, message = borrow_book_by_patron("123456", book_id)

    assert success is False
    assert message == "This book is currently not available."


def test_borrow_book_by_patron_enforces_borrow_limit():
    patron_id = "123456"
    for i in range(5):
        isbn = f"44444444444{i:02d}"
        book_id = create_book(f"Book {i}", "Author", isbn, 1)
        create_borrow_record(
            patron_id,
            book_id,
            datetime.now() - timedelta(days=3),
            datetime.now() + timedelta(days=11),
        )
        database.update_book_availability(book_id, -1)

    new_book_id = create_book("Sixth Book", "Author", "5555555555555", 1)
    success, message = borrow_book_by_patron(patron_id, new_book_id)

    assert success is False
    assert message == "You have reached the maximum borrowing limit of 5 books."


# R4: return_book_by_patron --------------------------------------------------------------------


def test_return_book_by_patron_success():
    patron_id = "123456"
    book_id = create_book("Returnable Book", "Author", "6666666666666", 1, available_copies=0)
    borrow_date = datetime.now() - timedelta(days=5)
    due_date = datetime.now() + timedelta(days=9)
    create_borrow_record(patron_id, book_id, borrow_date, due_date)

    success, message = return_book_by_patron(patron_id, book_id)

    assert success is True
    assert message == 'Book "Returnable Book" successfully returned. Late fee: $0.00. Book returned on time.'

    record = fetch_borrow_record(patron_id, book_id)
    assert record["return_date"] is not None

    book = fetch_book(book_id)
    assert book["available_copies"] == 1


def test_return_book_by_patron_requires_active_record():
    patron_id = "123456"
    book_id = create_book("Never Borrowed", "Author", "7777777777777", 1)

    success, message = return_book_by_patron(patron_id, book_id)

    assert success is False
    assert message == "No active borrow record found for this patron and book."


def test_return_book_by_patron_validates_patron_id():
    book_id = create_book("Returnable Book", "Author", "8888888888888", 1)

    success, message = return_book_by_patron("ABCDEF", book_id)

    assert success is False
    assert message == "Invalid patron ID. Must be exactly 6 digits."


# R5: calculate_late_fee_for_book --------------------------------------------------------------


def test_calculate_late_fee_for_book_no_active_record():
    book_id = create_book("Available Book", "Author", "8900000000001", 1)

    result = calculate_late_fee_for_book("123456", book_id)

    assert result["fee_amount"] == 0.0
    assert result["status"] == "No active borrow found for this patron and book."


def test_calculate_late_fee_for_book_on_time():
    patron_id = "123456"
    book_id = create_book("On Time Book", "Author", "8900000000002", 1, available_copies=0)
    borrow_date = datetime.now() - timedelta(days=3)
    due_date = datetime.now() + timedelta(days=2)
    create_borrow_record(patron_id, book_id, borrow_date, due_date)

    result = calculate_late_fee_for_book(patron_id, book_id)

    assert result["fee_amount"] == 0.0
    assert result["days_overdue"] == 0
    assert result["status"] == "Book returned on time."


def test_calculate_late_fee_for_book_overdue_cap_applied():
    patron_id = "123456"
    book_id = create_book("Very Overdue Book", "Author", "8900000000003", 1, available_copies=0)
    borrow_date = datetime.now() - timedelta(days=60)
    due_date = datetime.now() - timedelta(days=40)
    create_borrow_record(patron_id, book_id, borrow_date, due_date)

    result = calculate_late_fee_for_book(patron_id, book_id)

    assert result["fee_amount"] == 15.0
    assert result["days_overdue"] >= 40
    assert result["status"] == "Book is overdue."


# R6: search_books_in_catalog ------------------------------------------------------------------


def test_search_books_in_catalog_title_partial_case_insensitive():
    create_book("The Great Gatsby", "F. Scott Fitzgerald", "9780743273565", 3)
    create_book("Great Expectations", "Charles Dickens", "9780141439563", 2)
    create_book("Moby Dick", "Herman Melville", "9781503280786", 1)

    results = search_books_in_catalog("great", "title")

    titles = [book["title"] for book in results]
    assert titles == ["Great Expectations", "The Great Gatsby"]


def test_search_books_in_catalog_isbn_exact_match():
    create_book("Moby Dick", "Herman Melville", "9781503280786", 1)

    results = search_books_in_catalog("9781503280786", "isbn")

    assert len(results) == 1
    assert results[0]["title"] == "Moby Dick"


def test_search_books_in_catalog_invalid_type_returns_empty():
    create_book("Any Book", "Any Author", "9012345678901", 1)

    results = search_books_in_catalog("Anything", "genre")

    assert results == []


# R7: get_patron_status_report -----------------------------------------------------------------


def test_get_patron_status_report_invalid_patron_id():
    report = get_patron_status_report("12A456")

    assert report["status"] == "Invalid patron ID. Must be exactly 6 digits."
    assert report["current_loans"] == []
    assert report["history"] == []
    assert report["total_late_fees"] == 0.0


def test_get_patron_status_report_includes_current_loans_history_and_fees():
    patron_id = "123456"

    overdue_book_id = create_book("Current Loan", "Author One", "9900000000001", 1, available_copies=0)
    borrow_date_active = datetime.now() - timedelta(days=20)
    due_date_active = datetime.now() - timedelta(days=3)
    create_borrow_record(patron_id, overdue_book_id, borrow_date_active, due_date_active)

    returned_book_id = create_book("Returned Book", "Author Two", "9900000000002", 1, available_copies=1)
    borrow_date_returned = datetime.now() - timedelta(days=40)
    due_date_returned = datetime.now() - timedelta(days=26)
    return_date = datetime.now() - timedelta(days=10)
    create_borrow_record(
        patron_id,
        returned_book_id,
        borrow_date_returned,
        due_date_returned,
        return_date,
    )

    expected_fee = calculate_late_fee_for_book(patron_id, overdue_book_id)["fee_amount"]

    report = get_patron_status_report(patron_id)

    assert report["patron_id"] == patron_id
    assert report["status"] == "OK"
    assert report["active_count"] == 1
    assert len(report["current_loans"]) == 1
    assert len(report["history"]) == 1
    assert report["total_late_fees"] == expected_fee

    current = report["current_loans"][0]
    assert current["book_id"] == overdue_book_id
    assert current["is_overdue"] is True
    assert current["late_fee"] == expected_fee
    assert isinstance(current["borrow_date"], datetime)
    assert isinstance(current["due_date"], datetime)
    assert current["return_date"] is None

    history_entry = report["history"][0]
    assert history_entry["book_id"] == returned_book_id
    assert isinstance(history_entry["borrow_date"], datetime)
    assert isinstance(history_entry["due_date"], datetime)
    assert isinstance(history_entry["return_date"], datetime)
```