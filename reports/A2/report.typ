#set document(
  title: "Assignment 2: System Completion & AI Testing",
  author: "Mike MacLennan",
  date: datetime(year: 2025, month: 10, day: 12),
)

#set page(
  paper: "us-letter",
  margin: 1in,
  header: [
    #set text(9pt)
    #grid(
      columns: (1fr, 1fr),
      align: (left, right),
      [CMPE 327 - Assignment 2],
      [Mike MacLennan - 20121416]
    )
    #line(length: 100%, stroke: 0.5pt)
  ],
)

#set text(size: 11pt)
#set par(justify: true)

#align(center + horizon)[
  #set page(header: none)
  #text(size: 18pt, weight: "bold")[Assignment 2: System Completion & AI Testing]

  #text(size: 14pt)[CMPE 327 - Software Quality Assurance]

  #text(size: 12pt)[Mike MacLennan]

  #text(size: 12pt)[#context document.date.display()]

  #link("https://github.com/mikemacl/cisc327-library-management-a2-1416")
]

#pagebreak()

#outline(indent: auto)

#pagebreak()

#heading(level: 1, numbering: none)[Student Information]
*Name* & Mike MacLennan \
*Student ID* & 20121416 \
*Repository* #link("https://github.com/mikemacl/cisc327-library-management-a2-1416")

= 1. Implementation Progress
- finished the remaining logic in `library_service.py` so r4–r7 now
  behave properly (returns update records, late fees cap at \$15, search
  respects mode, and patron status aggregates active/history loans)
- added database helpers (`database.py`) needed for returns, search, and
  status
- hooked new functionality into the flask app: return flow now surfaces
  real messages, the search page shows results, and a patron status page
  is available from the navbar
- all tests passing (`uv run pytest`)

= 2. Additional Test Cases
- improved `tests/test_library_service.py` so every requirement has at
  least one assertion set; return, late-fee, search, and status tests
  are now active instead of `xfail`
- added r2 coverage to prove `database.get_all_books` returns sorted
  output and reflects availability changes after a borrow
- updated existing fixtures to ensure seeded data matches the new logic
  (for example, replacing the sixth-book borrow check with an enforced
  limit test)

= 3. AI-Assisted Test Generation
== Prompt
- gathered python sources (tests excluded) via
  `files-to-prompt . -e py --ignore tests --ignore sample_test.py`, then
  paired the resulting bundle with `requirements_specification.md`
- final prompt (`reports/A2/prompt.txt`) is just the raw code listing
  followed by the requirements

```
the following listing contains the python source files for the library management system project (tests removed). after the code listing you will find the functional requirements r1-r7. based on these inputs, generate pytest test cases that exercise the specified behaviour.
```

== Responses
=== GPT-5-Codex
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

#pagebreak()
=== Claude Sonnet 4.5
```python
# test_library_service.py
"""
Pytest test cases for Library Management System business logic.
Tests cover requirements R1-R7 with focus on input validation,
business rules, and edge cases.
"""

import pytest
from datetime import datetime, timedelta
from library_service import (
    add_book_to_catalog,
    borrow_book_by_patron,
    return_book_by_patron,
    calculate_late_fee_for_book,
    search_books_in_catalog,
    get_patron_status_report,
)
from database import (
    get_book_by_isbn,
    insert_book,
    insert_borrow_record,
    get_patron_borrow_count,
    update_book_availability,
    get_all_books,
)


# ============================================================================
# R1: Add Book To Catalog Tests
# ============================================================================

class TestAddBookToCatalog:
    """Tests for R1: Add Book To Catalog functionality."""

    def test_add_valid_book(self):
        """Test adding a valid book succeeds."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "1234567890123", 5
        )
        assert success is True
        assert "successfully added" in message

        # Verify book was added to database
        book = get_book_by_isbn("1234567890123")
        assert book is not None
        assert book['title'] == "Test Book"
        assert book['author'] == "Test Author"
        assert book['total_copies'] == 5
        assert book['available_copies'] == 5

    def test_add_book_empty_title(self):
        """Test adding book with empty title fails."""
        success, message = add_book_to_catalog(
            "", "Test Author", "1234567890123", 5
        )
        assert success is False
        assert "Title is required" in message

    def test_add_book_whitespace_title(self):
        """Test adding book with whitespace-only title fails."""
        success, message = add_book_to_catalog(
            "   ", "Test Author", "1234567890123", 5
        )
        assert success is False
        assert "Title is required" in message

    def test_add_book_title_too_long(self):
        """Test adding book with title exceeding 200 characters fails."""
        long_title = "A" * 201
        success, message = add_book_to_catalog(
            long_title, "Test Author", "1234567890123", 5
        )
        assert success is False
        assert "less than 200 characters" in message

    def test_add_book_title_exactly_200_chars(self):
        """Test adding book with exactly 200 character title succeeds."""
        title_200 = "A" * 200
        success, message = add_book_to_catalog(
            title_200, "Test Author", "1234567890123", 5
        )
        assert success is True

    def test_add_book_empty_author(self):
        """Test adding book with empty author fails."""
        success, message = add_book_to_catalog(
            "Test Book", "", "1234567890123", 5
        )
        assert success is False
        assert "Author is required" in message

    def test_add_book_whitespace_author(self):
        """Test adding book with whitespace-only author fails."""
        success, message = add_book_to_catalog(
            "Test Book", "   ", "1234567890123", 5
        )
        assert success is False
        assert "Author is required" in message

    def test_add_book_author_too_long(self):
        """Test adding book with author exceeding 100 characters fails."""
        long_author = "A" * 101
        success, message = add_book_to_catalog(
            "Test Book", long_author, "1234567890123", 5
        )
        assert success is False
        assert "less than 100 characters" in message

    def test_add_book_author_exactly_100_chars(self):
        """Test adding book with exactly 100 character author succeeds."""
        author_100 = "A" * 100
        success, message = add_book_to_catalog(
            "Test Book", author_100, "1234567890123", 5
        )
        assert success is True

    def test_add_book_isbn_too_short(self):
        """Test adding book with ISBN less than 13 digits fails."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "123456789012", 5
        )
        assert success is False
        assert "exactly 13 digits" in message

    def test_add_book_isbn_too_long(self):
        """Test adding book with ISBN more than 13 digits fails."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "12345678901234", 5
        )
        assert success is False
        assert "exactly 13 digits" in message

    def test_add_book_isbn_non_numeric(self):
        """Test adding book with non-numeric ISBN fails."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "123456789012A", 5
        )
        assert success is False
        assert "exactly 13 digits" in message

    def test_add_book_isbn_with_spaces(self):
        """Test adding book with ISBN containing spaces fails."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "1234 5678 9012", 5
        )
        assert success is False
        assert "exactly 13 digits" in message

    def test_add_book_duplicate_isbn(self):
        """Test adding book with duplicate ISBN fails."""
        # Add first book
        add_book_to_catalog("Book One", "Author One", "1234567890123", 3)

        # Try to add another book with same ISBN
        success, message = add_book_to_catalog(
            "Book Two", "Author Two", "1234567890123", 5
        )
        assert success is False
        assert "already exists" in message

    def test_add_book_zero_copies(self):
        """Test adding book with zero copies fails."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "1234567890123", 0
        )
        assert success is False
        assert "positive integer" in message

    def test_add_book_negative_copies(self):
        """Test adding book with negative copies fails."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "1234567890123", -1
        )
        assert success is False
        assert "positive integer" in message

    def test_add_book_float_copies(self):
        """Test adding book with float copies fails."""
        success, message = add_book_to_catalog(
            "Test Book", "Test Author", "1234567890123", 5.5
        )
        assert success is False
        assert "positive integer" in message

    def test_add_book_strips_whitespace(self):
        """Test that title and author whitespace is stripped."""
        success, message = add_book_to_catalog(
            "  Test Book  ", "  Test Author  ", "1234567890123", 5
        )
        assert success is True

        book = get_book_by_isbn("1234567890123")
        assert book['title'] == "Test Book"
        assert book['author'] == "Test Author"


# ============================================================================
# R3: Book Borrowing Interface Tests
# ============================================================================

class TestBorrowBook:
    """Tests for R3: Book Borrowing Interface."""

    def test_borrow_valid_book(self):
        """Test borrowing an available book succeeds."""
        # Add a book first
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = borrow_book_by_patron("123456", book['id'])
        assert success is True
        assert "Successfully borrowed" in message
        assert "Due date:" in message

        # Verify borrow count increased
        assert get_patron_borrow_count("123456") == 1

    def test_borrow_invalid_patron_id_non_numeric(self):
        """Test borrowing with non-numeric patron ID fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = borrow_book_by_patron("ABCDEF", book['id'])
        assert success is False
        assert "Invalid patron ID" in message

    def test_borrow_invalid_patron_id_too_short(self):
        """Test borrowing with patron ID less than 6 digits fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = borrow_book_by_patron("12345", book['id'])
        assert success is False
        assert "Invalid patron ID" in message

    def test_borrow_invalid_patron_id_too_long(self):
        """Test borrowing with patron ID more than 6 digits fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = borrow_book_by_patron("1234567", book['id'])
        assert success is False
        assert "Invalid patron ID" in message

    def test_borrow_invalid_patron_id_empty(self):
        """Test borrowing with empty patron ID fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = borrow_book_by_patron("", book['id'])
        assert success is False
        assert "Invalid patron ID" in message

    def test_borrow_nonexistent_book(self):
        """Test borrowing non-existent book fails."""
        success, message = borrow_book_by_patron("123456", 9999)
        assert success is False
        assert "Book not found" in message

    def test_borrow_unavailable_book(self):
        """Test borrowing unavailable book fails."""
        # Add book with 0 available copies
        insert_book("Test Book", "Test Author", "1234567890123", 3, 0)
        book = get_book_by_isbn("1234567890123")

        success, message = borrow_book_by_patron("123456", book['id'])
        assert success is False
        assert "not available" in message

    def test_borrow_at_max_limit(self):
        """Test borrowing when patron has 5 books fails."""
        # Add 5 books and borrow all
        for i in range(5):
            isbn = f"123456789012{i}"
            insert_book(f"Book {i}", "Author", isbn, 1, 1)
            book = get_book_by_isbn(isbn)
            borrow_book_by_patron("123456", book['id'])

        # Try to borrow 6th book
        insert_book("Book 6", "Author", "1234567890125", 1, 1)
        book = get_book_by_isbn("1234567890125")

        success, message = borrow_book_by_patron("123456", book['id'])
        assert success is False
        assert "maximum borrowing limit" in message
        assert "5 books" in message

    def test_borrow_just_below_max_limit(self):
        """Test borrowing when patron has 4 books succeeds."""
        # Add 4 books and borrow all
        for i in range(4):
            isbn = f"123456789012{i}"
            insert_book(f"Book {i}", "Author", isbn, 1, 1)
            book = get_book_by_isbn(isbn)
            borrow_book_by_patron("123456", book['id'])

        # Borrow 5th book should succeed
        insert_book("Book 5", "Author", "1234567890124", 1, 1)
        book = get_book_by_isbn("1234567890124")

        success, message = borrow_book_by_patron("123456", book['id'])
        assert success is True

    def test_borrow_updates_available_copies(self):
        """Test that borrowing decrements available copies."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        borrow_book_by_patron("123456", book['id'])

        updated_book = get_book_by_isbn("1234567890123")
        assert updated_book['available_copies'] == 2

    def test_borrow_sets_correct_due_date(self):
        """Test that due date is set 14 days from borrow."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        before_borrow = datetime.now()
        success, message = borrow_book_by_patron("123456", book['id'])
        after_borrow = datetime.now()

        assert success is True
        # Extract date from message
        import re
        match = re.search(r'Due date: (\d{4}-\d{2}-\d{2})', message)
        assert match is not None
        due_date_str = match.group(1)
        due_date = datetime.strptime(due_date_str, "%Y-%m-%d")

        # Due date should be approximately 14 days from now
        expected_min = before_borrow + timedelta(days=14)
        expected_max = after_borrow + timedelta(days=14)

        assert expected_min <= due_date <= expected_max


# ============================================================================
# R4: Book Return Processing Tests
# ============================================================================

class TestReturnBook:
    """Tests for R4: Book Return Processing."""

    def test_return_valid_book_on_time(self):
        """Test returning a book on time succeeds with no fee."""
        # Setup: add book and borrow it
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")
        borrow_book_by_patron("123456", book['id'])

        success, message = return_book_by_patron("123456", book['id'])
        assert success is True
        assert "successfully returned" in message
        assert "Late fee: $0.00" in message

    def test_return_invalid_patron_id(self):
        """Test returning with invalid patron ID fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = return_book_by_patron("ABCDEF", book['id'])
        assert success is False
        assert "Invalid patron ID" in message

    def test_return_patron_id_too_short(self):
        """Test returning with patron ID less than 6 digits fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = return_book_by_patron("12345", book['id'])
        assert success is False
        assert "Invalid patron ID" in message

    def test_return_patron_id_too_long(self):
        """Test returning with patron ID more than 6 digits fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = return_book_by_patron("1234567", book['id'])
        assert success is False
        assert "Invalid patron ID" in message

    def test_return_nonexistent_book(self):
        """Test returning non-existent book fails."""
        success, message = return_book_by_patron("123456", 9999)
        assert success is False
        assert "Book not found" in message

    def test_return_not_borrowed_book(self):
        """Test returning book not borrowed by patron fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        success, message = return_book_by_patron("123456", book['id'])
        assert success is False
        assert "No active borrow record" in message

    def test_return_borrowed_by_different_patron(self):
        """Test returning book borrowed by different patron fails."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")
        borrow_book_by_patron("111111", book['id'])

        success, message = return_book_by_patron("222222", book['id'])
        assert success is False
        assert "No active borrow record" in message

    def test_return_updates_available_copies(self):
        """Test that returning increments available copies."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")
        borrow_book_by_patron("123456", book['id'])

        # Available copies should be 2
        book_after_borrow = get_book_by_isbn("1234567890123")
        assert book_after_borrow['available_copies'] == 2

        return_book_by_patron("123456", book['id'])

        # Available copies should be back to 3
        book_after_return = get_book_by_isbn("1234567890123")
        assert book_after_return['available_copies'] == 3

    def test_return_overdue_book_calculates_fee(self):
        """Test returning overdue book calculates late fee."""
        # Setup: add book and create overdue borrow record
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # Create borrow record with past dates
        past_borrow = datetime.now() - timedelta(days=20)
        past_due = datetime.now() - timedelta(days=6)
        insert_borrow_record("123456", book['id'], past_borrow, past_due)
        update_book_availability(book['id'], -1)

        success, message = return_book_by_patron("123456", book['id'])
        assert success is True
        assert "Late fee:" in message
        # Should have fee greater than $0
        assert "$0.00" not in message or "overdue" in message.lower()


# ============================================================================
# R5: Late Fee Calculation Tests
# ============================================================================

class TestCalculateLateFee:
    """Tests for R5: Late Fee Calculation API."""

    def test_late_fee_on_time_return(self):
        """Test late fee is $0 for on-time return."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # Borrow with future due date
        borrow_date = datetime.now() - timedelta(days=5)
        due_date = datetime.now() + timedelta(days=9)
        insert_borrow_record("123456", book['id'], borrow_date, due_date)

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 0.0
        assert result['days_overdue'] == 0
        assert "on time" in result['status'].lower()

    def test_late_fee_1_day_overdue(self):
        """Test late fee for 1 day overdue is $0.50."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # Borrow with due date 1 day ago
        borrow_date = datetime.now() - timedelta(days=15)
        due_date = datetime.now() - timedelta(days=1)
        insert_borrow_record("123456", book['id'], borrow_date, due_date)

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 0.50
        assert result['days_overdue'] == 1
        assert "overdue" in result['status'].lower()

    def test_late_fee_7_days_overdue(self):
        """Test late fee for 7 days overdue is $3.50."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # Borrow with due date 7 days ago
        borrow_date = datetime.now() - timedelta(days=21)
        due_date = datetime.now() - timedelta(days=7)
        insert_borrow_record("123456", book['id'], borrow_date, due_date)

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 3.50
        assert result['days_overdue'] == 7

    def test_late_fee_8_days_overdue(self):
        """Test late fee for 8 days overdue is $4.50."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # 7 days @ $0.50 = $3.50, 1 day @ $1.00 = $1.00, total = $4.50
        borrow_date = datetime.now() - timedelta(days=22)
        due_date = datetime.now() - timedelta(days=8)
        insert_borrow_record("123456", book['id'], borrow_date, due_date)

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 4.50
        assert result['days_overdue'] == 8

    def test_late_fee_14_days_overdue(self):
        """Test late fee for 14 days overdue is $10.50."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # 7 days @ $0.50 = $3.50, 7 days @ $1.00 = $7.00, total = $10.50
        borrow_date = datetime.now() - timedelta(days=28)
        due_date = datetime.now() - timedelta(days=14)
        insert_borrow_record("123456", book['id'], borrow_date, due_date)

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 10.50
        assert result['days_overdue'] == 14

    def test_late_fee_maximum_cap(self):
        """Test late fee is capped at $15.00."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # 30 days overdue would be $26.50 without cap
        borrow_date = datetime.now() - timedelta(days=44)
        due_date = datetime.now() - timedelta(days=30)
        insert_borrow_record("123456", book['id'], borrow_date, due_date)

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 15.00
        assert result['days_overdue'] == 30

    def test_late_fee_no_active_borrow(self):
        """Test late fee calculation with no active borrow."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 0.0
        assert result['days_overdue'] == 0
        assert "No active borrow" in result['status']

    def test_late_fee_exactly_at_transition(self):
        """Test late fee at exactly 7 days (last day of $0.50 rate)."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        borrow_date = datetime.now() - timedelta(days=21)
        due_date = datetime.now() - timedelta(days=7)
        insert_borrow_record("123456", book['id'], borrow_date, due_date)

        result = calculate_late_fee_for_book("123456", book['id'])
        assert result['fee_amount'] == 3.50  # 7 * 0.50


# ============================================================================
# R6: Book Search Functionality Tests
# ============================================================================

class TestSearchBooks:
    """Tests for R6: Book Search Functionality."""

    def test_search_by_title_exact_match(self):
        """Test searching by exact title match."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("The Great Gatsby", "title")
        assert len(results) == 1
        assert results[0]['title'] == "The Great Gatsby"

    def test_search_by_title_partial_match(self):
        """Test searching by partial title match."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)
        insert_book("Great Expectations", "Charles Dickens", "1234567890124", 2, 2)

        results = search_books_in_catalog("Great", "title")
        assert len(results) == 2

    def test_search_by_title_case_insensitive(self):
        """Test title search is case-insensitive."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("great gatsby", "title")
        assert len(results) == 1
        assert results[0]['title'] == "The Great Gatsby"

    def test_search_by_title_no_results(self):
        """Test title search with no matches returns empty list."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("Nonexistent Book", "title")
        assert len(results) == 0

    def test_search_by_author_exact_match(self):
        """Test searching by exact author match."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("F. Scott Fitzgerald", "author")
        assert len(results) == 1
        assert results[0]['author'] == "F. Scott Fitzgerald"

    def test_search_by_author_partial_match(self):
        """Test searching by partial author match."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)
        insert_book("Tender is the Night", "F. Scott Fitzgerald", "1234567890124", 2, 2)

        results = search_books_in_catalog("Fitzgerald", "author")
        assert len(results) == 2

    def test_search_by_author_case_insensitive(self):
        """Test author search is case-insensitive."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("fitzgerald", "author")
        assert len(results) == 1

    def test_search_by_isbn_exact_match(self):
        """Test searching by ISBN (exact match only)."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("1234567890123", "isbn")
        assert len(results) == 1
        assert results[0]['isbn'] == "1234567890123"

    def test_search_by_isbn_partial_no_match(self):
        """Test ISBN search does not support partial matching."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("12345", "isbn")
        assert len(results) == 0

    def test_search_by_isbn_no_results(self):
        """Test ISBN search with no match returns empty list."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("9999999999999", "isbn")
        assert len(results) == 0

    def test_search_empty_term(self):
        """Test search with empty term returns empty list."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("", "title")
        assert len(results) == 0

    def test_search_whitespace_term(self):
        """Test search with whitespace-only term."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("   ", "title")
        assert len(results) == 0

    def test_search_invalid_type(self):
        """Test search with invalid type returns empty list."""
        insert_book("The Great Gatsby", "F. Scott Fitzgerald", "1234567890123", 3, 3)

        results = search_books_in_catalog("Gatsby", "invalid_type")
        assert len(results) == 0

    def test_search_none_term(self):
        """Test search with None term returns empty list."""
        results = search_books_in_catalog(None, "title")
        assert len(results) == 0

    def test_search_none_type(self):
        """Test search with None type returns empty list."""
        results = search_books_in_catalog("Gatsby", None)
        assert len(results) == 0


# ============================================================================
# R7: Patron Status Report Tests
# ============================================================================

class TestPatronStatusReport:
    """Tests for R7: Patron Status Report."""

    def test_status_valid_patron_no_borrows(self):
        """Test status report for patron with no borrows."""
        report = get_patron_status_report("123456")

        assert report['patron_id'] == "123456"
        assert report['current_loans'] == []
        assert report['history'] == []
        assert report['active_count'] == 0
        assert report['total_late_fees'] == 0.0
        assert "No borrow records" in report['status']

    def test_status_valid_patron_with_current_loans(self):
        """Test status report for patron with current loans."""
        # Add and borrow a book
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")
        borrow_book_by_patron("123456", book['id'])

        report = get_patron_status_report("123456")

        assert report['patron_id'] == "123456"
        assert len(report['current_loans']) == 1
        assert report['current_loans'][0]['title'] == "Test Book"
        assert report['active_count'] == 1
        assert report['total_late_fees'] == 0.0

    def test_status_with_returned_books(self):
        """Test status report includes returned books in history."""
        # Add, borrow, and return a book
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")
        borrow_book_by_patron("123456", book['id'])
        return_book_by_patron("123456", book['id'])

        report = get_patron_status_report("123456")

        assert len(report['current_loans']) == 0
        assert len(report['history']) == 1
        assert report['history'][0]['title'] == "Test Book"
        assert report['history'][0]['return_date'] is not None

    def test_status_with_overdue_books(self):
        """Test status report calculates late fees for overdue books."""
        insert_book("Test Book", "Test Author", "1234567890123", 3, 3)
        book = get_book_by_isbn("1234567890123")

        # Create overdue borrow
        past_borrow = datetime.now() - timedelta(days=20)
        past_due = datetime.now() - timedelta(days=6)
        insert_borrow_record("123456", book['id'], past_borrow, past_due)
        update_book_availability(book['id'], -1)

        report = get_patron_status_report("123456")

        assert len(report['current_loans']) == 1
        assert report['current_loans'][0]['is_overdue'] is True
        assert report['current_loans'][0]['late_fee'] > 0
        assert report['total_late_fees'] > 0

    def test_status_multiple_current_loans(self):
        """Test status report with multiple current loans."""
        # Borrow 3 books
        for i in range(3):
            isbn = f"123456789012{i}"
            insert_book(f"Book {i}", "Author", isbn, 1, 1)
            book = get_book_by_isbn(isbn)
            borrow_book_by_patron("123456", book['id'])

        report = get_patron_status_report("123456")

        assert len(report['current_loans']) == 3
        assert report['active_count'] == 3

    def test_status_invalid_patron_id_non_numeric(self):
        """Test status report with non-numeric patron ID."""
        report = get_patron_status_report("ABCDEF")

        assert "Invalid patron ID" in report['status']
        assert report['current_loans'] == []
        assert report['history'] == []

    def test_status_invalid_patron_id_too_short(self):
        """Test status report with patron ID less than 6 digits."""
        report = get_patron_status_report("12345")

        assert "Invalid patron ID" in report['status']

    def test_status_invalid_patron_id_too_long(self):
        """Test status report with patron ID more than 6 digits."""
        report = get_patron_status_report("1234567")

        assert "Invalid patron ID" in report['status']

    def test_status_total_late_fees_multiple_books(self):
        """Test total late fees across multiple overdue books."""
        # Create 2 overdue books
        for i in range(2):
            isbn = f"123456789012{i}"
            insert_book(f"Book {i}", "Author", isbn, 1, 1)
            book = get_book_by_isbn(isbn)

            past_borrow = datetime.now() - timedelta(days=20)
            past_due = datetime.now() - timedelta(days=5)
            insert_borrow_record("123456", book['id'], past_borrow, past_due)
            update_book_availability(book['id'], -1)

        report = get_patron_status_report("123456")

        # Each book: 5 days * $0.50 = $2.50, total = $5.00
        assert report['total_late_fees'] == 5.00
        assert len(report['current_loans']) == 2

    def test_status_mixed_on_time_and_overdue(self):
        """Test status report with mix of on-time and overdue books."""
        # On-time book
        insert_book("On Time Book", "Author", "1234567890120", 1, 1)
        book1 = get_book_by_isbn("1234567890120")
        borrow_book_by_patron("123456", book1['id'])

        # Overdue book
        insert_book("Overdue Book", "Author", "1234567890121", 1, 1)
        book2 = get_book_by_isbn("1234567890121")
        past_borrow = datetime.now() - timedelta(days=20)
        past_due = datetime.now() - timedelta(days=5)
        insert_borrow_record("123456", book2['id'], past_borrow, past_due)
        update_book_availability(book2['id'], -1)

        report = get_patron_status_report("123456")

        assert len(report['current_loans']) == 2
        assert report['total_late_fees'] > 0

        # Check one is overdue and one is not
        overdue_count = sum(1 for loan in report['current_loans'] if loan['is_overdue'])
        assert overdue_count == 1

    def test_status_empty_patron_id(self):
        """Test status report with empty patron ID."""
        report = get_patron_status_report("")

        assert "Invalid patron ID" in report['status']
```

#pagebreak()

=== Gemini-2.5-Pro
```python
# ./test_library_service.py

import pytest
from datetime import datetime, timedelta
import sqlite3

# Import functions to test from the business logic layer
from library_service import (
    add_book_to_catalog,
    borrow_book_by_patron,
    return_book_by_patron,
    calculate_late_fee_for_book,
    search_books_in_catalog,
    get_patron_status_report,
)

# Import database functions for test setup and verification
from database import (
    get_book_by_isbn,
    get_book_by_id,
    get_active_borrow_record,
    get_patron_borrow_count,
    get_patron_borrow_records,
)

# --- Helper Functions for Test Setup ---

def setup_borrow_record(
    conn: sqlite3.Connection,
    patron_id: str,
    book_id: int,
    borrow_date: datetime,
    due_date: datetime,
    return_date: datetime = None,
):
    """Inserts a borrow record directly into the database for testing."""
    return_date_iso = return_date.isoformat() if return_date else None
    conn.execute(
        """
        INSERT INTO borrow_records (patron_id, book_id, borrow_date, due_date, return_date)
        VALUES (?, ?, ?, ?, ?)
        """,
        (patron_id, book_id, borrow_date.isoformat(), due_date.isoformat(), return_date_iso),
    )
    conn.commit()


# --- Test Cases for Functional Requirements ---

class TestR1AddBook:
    """Tests for R1: Add Book To Catalog"""

    def test_add_book_success(self):
        """R1: Test successfully adding a new book."""
        title = "New Book for Testing"
        author = "Test Author"
        isbn = "1234567890123"
        copies = 5

        success, message = add_book_to_catalog(title, author, isbn, copies)

        assert success is True
        assert "successfully added" in message

        # Verify in database
        book = get_book_by_isbn(isbn)
        assert book is not None
        assert book["title"] == title
        assert book["total_copies"] == copies
        assert book["available_copies"] == copies

    def test_add_book_duplicate_isbn(self):
        """R1: Test adding a book with an existing ISBN."""
        # This ISBN exists in the sample data
        isbn = "9780743273565"
        success, message = add_book_to_catalog("Another Book", "Some Author", isbn, 1)

        assert success is False
        assert "ISBN already exists" in message

    @pytest.mark.parametrize("title, author, isbn, copies, expected_msg", [
        ("", "Author", "1112223334445", 1, "Title is required"),
        ("Title", "", "1112223334445", 1, "Author is required"),
        ("T"*201, "Author", "1112223334445", 1, "Title must be less than 200 characters"),
        ("Title", "A"*101, "1112223334445", 1, "Author must be less than 100 characters"),
        ("Title", "Author", "123", 1, "ISBN must be exactly 13 digits"),
        ("Title", "Author", "123456789012a", 1, "ISBN must be exactly 13 digits"),
        ("Title", "Author", "1112223334445", 0, "Total copies must be a positive integer"),
        ("Title", "Author", "1112223334445", -1, "Total copies must be a positive integer"),
    ])
    def test_add_book_validation(self, title, author, isbn, copies, expected_msg):
        """R1: Test various input validation rules for adding a book."""
        success, message = add_book_to_catalog(title, author, isbn, copies)
        assert success is False
        assert expected_msg in message


class TestR3BorrowBook:
    """Tests for R3: Book Borrowing Interface"""

    def test_borrow_book_success(self):
        """R3: Test a successful book borrow."""
        patron_id = "111111"
        book_id = 1  # 'The Great Gatsby' from sample data, should be available

        book_before = get_book_by_id(book_id)
        assert book_before["available_copies"] > 0

        success, message = borrow_book_by_patron(patron_id, book_id)

        assert success is True
        assert "Successfully borrowed" in message

        # Verify DB changes
        book_after = get_book_by_id(book_id)
        assert book_after["available_copies"] == book_before["available_copies"] - 1
        assert get_patron_borrow_count(patron_id) == 1

    def test_borrow_book_unavailable(self):
        """R3: Test borrowing a book with no available copies."""
        patron_id = "222222"
        book_id = 3  # '1984' from sample data is not available

        success, message = borrow_book_by_patron(patron_id, book_id)

        assert success is False
        assert "not available" in message
        assert get_patron_borrow_count(patron_id) == 0

    def test_borrow_book_limit_reached(self, raw_connection):
        """R3: Test borrowing when the patron has reached the 5-book limit."""
        patron_id = "333333"
        # Manually create 5 borrow records for this patron
        for i in range(5):
            book_id = add_book_to_catalog(f"Book {i}", "Author", f"99988877766{i}", 1)[0]
            borrow_book_by_patron(patron_id, i + 4) # book_ids are 4, 5, 6, 7, 8

        assert get_patron_borrow_count(patron_id) == 5

        # Attempt to borrow a 6th book
        success, message = borrow_book_by_patron(patron_id, 1) # 'The Great Gatsby'

        assert success is False
        assert "maximum borrowing limit" in message

    @pytest.mark.parametrize("patron_id, book_id, expected_msg", [
        ("123", 1, "Invalid patron ID"),
        ("abcdef", 1, "Invalid patron ID"),
        ("123456", 999, "Book not found"),
    ])
    def test_borrow_book_invalid_inputs(self, patron_id, book_id, expected_msg):
        """R3: Test invalid inputs for patron ID and book ID."""
        success, message = borrow_book_by_patron(patron_id, book_id)
        assert success is False
        assert expected_msg in message


class TestR4ReturnBook:
    """Tests for R4: Book Return Processing"""

    def test_return_book_success(self):
        """R4: Test a successful, on-time book return."""
        patron_id = "444444"
        book_id = 2  # 'To Kill a Mockingbird'

        borrow_success, _ = borrow_book_by_patron(patron_id, book_id)
        assert borrow_success is True

        book_before = get_book_by_id(book_id)

        return_success, message = return_book_by_patron(patron_id, book_id)

        assert return_success is True
        assert "successfully returned" in message
        assert "Late fee: $0.00" in message

        # Verify DB changes
        book_after = get_book_by_id(book_id)
        assert book_after["available_copies"] == book_before["available_copies"] + 1
        assert get_active_borrow_record(patron_id, book_id) is None

    def test_return_book_with_late_fee(self, raw_connection, mocker):
        """R4 & R5: Test returning an overdue book and ensure fee is in the message."""
        patron_id = "555555"
        book_id = 1

        # Manually create a borrow record that is overdue
        now = datetime.now()
        borrow_date = now - timedelta(days=20)
        due_date = borrow_date + timedelta(days=14) # Due 6 days ago

        setup_borrow_record(raw_connection, patron_id, book_id, borrow_date, due_date)
        raw_connection.execute("UPDATE books SET available_copies = available_copies - 1 WHERE id = 1")
        raw_connection.commit()

        # Mock datetime.now() in library_service to control the overdue calculation
        mocker.patch("library_service.datetime")
        mocker.patch("database.datetime")
        library_service.datetime.now.return_value = now
        database.datetime.now.return_value = now

        success, message = return_book_by_patron(patron_id, book_id)

        assert success is True
        assert "Late fee: $3.00" in message # 6 days @ $0.50/day

    def test_return_book_not_borrowed(self):
        """R4: Test returning a book that the patron does not have."""
        patron_id = "666666"
        book_id = 1
        success, message = return_book_by_patron(patron_id, book_id)

        assert success is False
        assert "No active borrow record found" in message


class TestR5LateFeeCalculation:
    """Tests for R5: Late Fee Calculation API"""

    @pytest.fixture
    def setup_overdue_book(self, raw_connection):
        patron_id = "777777"
        book_id = 1 # 'The Great Gatsby'
        now = datetime(2023, 1, 30) # A fixed point in time for consistency
        borrow_date = now - timedelta(days=30) # Borrowed 30 days ago
        due_date = borrow_date + timedelta(days=14) # Due 16 days ago

        setup_borrow_record(raw_connection, patron_id, book_id, borrow_date, due_date)
        return patron_id, book_id, due_date

    @pytest.mark.parametrize("days_after_due, expected_fee", [
        (0, 0.0),       # On time
        (1, 0.50),      # 1 day overdue
        (7, 3.50),      # 7 days overdue (7 * 0.50)
        (8, 4.50),      # 8 days overdue (3.50 + 1.00)
        (18, 14.50),    # 18 days overdue (3.50 + 11*1.00)
        (19, 15.00),    # 19 days overdue (3.50 + 12*1.00 = 15.50, capped at 15.00)
        (30, 15.00),    # Well over max fee
    ])
    def test_late_fee_scenarios(self, setup_overdue_book, mocker, days_after_due, expected_fee):
        """R5: Test various overdue scenarios and their corresponding fees."""
        patron_id, book_id, due_date = setup_overdue_book

        # Mock datetime.now() inside the library_service module
        mocked_now = due_date + timedelta(days=days_after_due)
        mocker.patch("library_service.datetime")
        library_service.datetime.now.return_value = mocked_now

        result = calculate_late_fee_for_book(patron_id, book_id)

        assert result["fee_amount"] == expected_fee
        assert result["days_overdue"] == days_after_due

    def test_late_fee_no_record(self):
        """R5: Test that fee is 0 if no active borrow record exists."""
        result = calculate_late_fee_for_book("123456", 99)
        assert result["fee_amount"] == 0.0
        assert "No active borrow found" in result["status"]


class TestR6BookSearch:
    """Tests for R6: Book Search Functionality"""

    @pytest.mark.parametrize("term, type, expected_count", [
        ("Gatsby", "title", 1),
        ("gatsby", "title", 1), # Case-insensitive
        ("Lee", "author", 1),
        ("F. Scott Fitzgerald", "author", 1),
        ("9780451524935", "isbn", 1), # 1984
        ("NonExistent", "title", 0),
        ("9780743273565", "author", 0), # Correct ISBN, wrong type
        ("", "title", 0), # Empty search term
    ])
    def test_search_scenarios(self, term, type, expected_count):
        """R6: Test search by title, author, and ISBN with various inputs."""
        results = search_books_in_catalog(term, type)
        assert len(results) == expected_count
        if expected_count > 0:
            # For ISBN, verify it's an exact match
            if type == "isbn":
                assert results[0]["isbn"] == term
            # For others, verify partial match
            else:
                field = results[0][type]
                assert term.lower() in field.lower()

    def test_search_invalid_type(self):
        """R6: Test that an invalid search type returns no results."""
        results = search_books_in_catalog("test", "publication_year")
        assert results == []


class TestR7PatronStatus:
    """Tests for R7: Patron Status Report"""

    @pytest.fixture
    def setup_patron_records(self, raw_connection):
        """Creates a complex record history for a single patron."""
        patron_id = "888888"
        base_time = datetime(2023, 5, 15)

        # 1. Returned book
        returned_borrow_date = base_time - timedelta(days=60)
        returned_due_date = returned_borrow_date + timedelta(days=14)
        return_date = returned_due_date - timedelta(days=2) # Returned on time
        setup_borrow_record(raw_connection, patron_id, 1, returned_borrow_date, returned_due_date, return_date)

        # 2. On-time current loan
        ontime_borrow_date = base_time - timedelta(days=10)
        ontime_due_date = ontime_borrow_date + timedelta(days=14) # Due in 4 days
        setup_borrow_record(raw_connection, patron_id, 2, ontime_borrow_date, ontime_due_date)

        # 3. Overdue current loan (will be 8 days overdue)
        overdue_borrow_date = base_time - timedelta(days=22)
        overdue_due_date = overdue_borrow_date + timedelta(days=14) # Due 8 days ago
        setup_borrow_record(raw_connection, patron_id, 3, overdue_borrow_date, overdue_due_date)

        return patron_id, base_time

    def test_patron_status_comprehensive_report(self, setup_patron_records, mocker):
        """R7: Test a full report with history, current loans, and late fees."""
        patron_id, base_time = setup_patron_records

        # Mock datetime.now() in the service to get predictable fee calculations
        mocker.patch("library_service.datetime")
        library_service.datetime.now.return_value = base_time

        report = get_patron_status_report(patron_id)

        assert report["status"] == "OK"
        assert report["patron_id"] == patron_id

        # Verify counts
        assert report["active_count"] == 2
        assert len(report["current_loans"]) == 2
        assert len(report["history"]) == 1

        # Verify total late fees (8 days overdue = 7*0.5 + 1*1.0 = $4.50)
        assert report["total_late_fees"] == 4.50

        # Verify history item
        assert report["history"][0]["book_id"] == 1

        # Verify current loan details
        current_book_ids = {loan["book_id"] for loan in report["current_loans"]}
        assert current_book_ids == {2, 3}

        for loan in report["current_loans"]:
            if loan["book_id"] == 2: # On-time book
                assert loan["is_overdue"] is False
                assert loan["late_fee"] == 0.0
            if loan["book_id"] == 3: # Overdue book
                assert loan["is_overdue"] is True
                assert loan["late_fee"] == 4.50

    def test_patron_status_no_records(self):
        """R7: Test report for a patron with no borrowing history."""
        patron_id = "999999"
        report = get_patron_status_report(patron_id)

        assert report["status"] == "No borrow records found."
        assert report["active_count"] == 0
        assert report["total_late_fees"] == 0.0
        assert report["current_loans"] == []
        assert report["history"] == []

    def test_patron_status_invalid_id(self):
        """R7: Test report for an invalid patron ID format."""
        patron_id = "invalid"
        report = get_patron_status_report(patron_id)
        assert "Invalid patron ID" in report["status"]
```

#v(2em)
*Full model outputs are archived in `reports/A2/responses/`.*

#pagebreak()

= 4. Comparison & Analysis
== Existing Tests
- service-layer focus with light helpers and fresh sqlite per test
- assertions are on behaviour we care about

== GPT-5-Codex
- swaps our fixtures for manual SQL inserts and hard-coded ids which
  dodges the validation logic and feels a bit fragile
- coverage overlaps ours; not a lot of new angles yet

== Claude Sonnet 4.5
- lots of edge cases and combos, but the volume makes it tough to manage
  and it doesn’t play nicely with our fixture setup
- still a decent idea bank if cherry-picked

== Gemini-2.5-Pro
- brings nicer parametrized examples, but it leans on seed data and
  fixture scopes that clash with the per-test reset
- probably workable with edits, just not plug-and-play right now

== Summary
- lots of nuggets we could port over (extra r1 validation, late-fee
  variations), but would need a careful review before we trust them

= 5. CI/CD Pipeline Setup
<cicd-pipeline-setup>
- GitHub actions workflow at `.github/workflows/tests.yml` and runs
  Pytest with coverage across Ubuntu, Macos, and Windows for Python
  3.10–3.12
- coverage uploads through codecov (token stored as `CODECOV_TOKEN`),
  and the README badges mirrors latest run
