# Pytest Test Cases for Library Management System

Based on the provided source code and functional requirements R1-R7, here are comprehensive pytest test cases:

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

These test cases comprehensively cover:

- **R1**: Input validation for all fields (title, author, ISBN, copies), duplicate detection, boundary conditions
- **R3**: Patron ID validation, book availability checks, borrowing limits, database updates
- **R4**: Return validation, patron/book verification, availability updates, late fee integration
- **R5**: Late fee calculation for various overdue durations, rate transitions, maximum cap
- **R6**: Search by title/author/ISBN, partial matching, case-insensitivity, empty/invalid inputs
- **R7**: Status reports with various loan states, late fee totals, patron validation, history tracking

Each test is focused, well-documented, and tests a specific aspect of the requirements.