An appropriate set of test cases for the specified requirements, focusing on the business logic in `library_service.py`, is provided below. These tests rely on the `pytest` framework and fixtures defined in `conftest.py`.

Save the following code as `test_library_service.py` in the root directory of your project and run it using `pytest`.

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