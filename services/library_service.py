"""
Library Service Module - Business Logic Functions
Contains all the core business logic for the Library Management System
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Dict, List, Tuple
from database import (
    get_book_by_id,
    get_book_by_isbn,
    get_patron_borrow_count,
    get_active_borrow_record,
    get_patron_borrow_records,
    insert_book,
    insert_borrow_record,
    update_book_availability,
    update_borrow_record_return_date,
    get_all_books,
    search_books,
)
from services.payment_service import PaymentGateway, PaymentGatewayError

def add_book_to_catalog(title: str, author: str, isbn: str, total_copies: int) -> Tuple[bool, str]:
    """
    Add a new book to the catalog.
    Implements R1: Book Catalog Management
    
    Args:
        title: Book title (max 200 chars)
        author: Book author (max 100 chars)
        isbn: 13-digit ISBN
        total_copies: Number of copies (positive integer)
        
    Returns:
        tuple: (success: bool, message: str)
    """
    # Input validation
    if not title or not title.strip():
        return False, "Title is required."
    
    if len(title.strip()) > 200:
        return False, "Title must be less than 200 characters."
    
    if not author or not author.strip():
        return False, "Author is required."
    
    if len(author.strip()) > 100:
        return False, "Author must be less than 100 characters."
    
    if len(isbn) != 13:
        return False, "ISBN must be exactly 13 digits."

    if not isbn.isdigit():
        return False, "ISBN must be exactly 13 digits."
    
    if not isinstance(total_copies, int) or total_copies <= 0:
        return False, "Total copies must be a positive integer."
    
    # Check for duplicate ISBN
    existing = get_book_by_isbn(isbn)
    if existing:
        return False, "A book with this ISBN already exists."
    
    # Insert new book
    success = insert_book(title.strip(), author.strip(), isbn, total_copies, total_copies)
    if success:
        return True, f'Book "{title.strip()}" has been successfully added to the catalog.'
    else:
        return False, "Database error occurred while adding the book."

def borrow_book_by_patron(patron_id: str, book_id: int) -> Tuple[bool, str]:
    """
    Allow a patron to borrow a book.
    Implements R3 as per requirements  
    
    Args:
        patron_id: 6-digit library card ID
        book_id: ID of the book to borrow
        
    Returns:
        tuple: (success: bool, message: str)
    """
    # Validate patron ID
    if not patron_id or not patron_id.isdigit() or len(patron_id) != 6:
        return False, "Invalid patron ID. Must be exactly 6 digits."
    
    # Check if book exists and is available
    book = get_book_by_id(book_id)
    if not book:
        return False, "Book not found."
    
    if book['available_copies'] <= 0:
        return False, "This book is currently not available."
    
    # Check patron's current borrowed books count
    current_borrowed = get_patron_borrow_count(patron_id)
    
    if current_borrowed >= 5:
        return False, "You have reached the maximum borrowing limit of 5 books."
    
    # Create borrow record
    borrow_date = datetime.now()
    due_date = borrow_date + timedelta(days=14)
    
    # Insert borrow record and update availability
    borrow_success = insert_borrow_record(patron_id, book_id, borrow_date, due_date)
    if not borrow_success:
        return False, "Database error occurred while creating borrow record."
    
    availability_success = update_book_availability(book_id, -1)
    if not availability_success:
        return False, "Database error occurred while updating book availability."
    
    return True, f'Successfully borrowed "{book["title"]}". Due date: {due_date.strftime("%Y-%m-%d")}.'

def return_book_by_patron(patron_id: str, book_id: int) -> Tuple[bool, str]:
    """
    Process book return by a patron.
    
    Implements R4 as per requirements
    """
    if not patron_id or not patron_id.isdigit() or len(patron_id) != 6:
        return False, "Invalid patron ID. Must be exactly 6 digits."

    book = get_book_by_id(book_id)
    if not book:
        return False, "Book not found."

    active_record = get_active_borrow_record(patron_id, book_id)
    if not active_record:
        return False, "No active borrow record found for this patron and book."

    fee_info = calculate_late_fee_for_book(patron_id, book_id)

    now = datetime.now()
    updated = update_borrow_record_return_date(patron_id, book_id, now)
    if not updated:
        return False, "Database error occurred while updating borrow record."

    availability_success = update_book_availability(book_id, 1)
    if not availability_success:
        return False, "Database error occurred while updating book availability."

    fee_amount = fee_info.get("fee_amount", 0.0)
    status = fee_info.get("status", "Return processed.")
    return True, (
        f'Book "{book["title"]}" successfully returned. '
        f'Late fee: ${fee_amount:.2f}. {status}'
    )

def calculate_late_fee_for_book(patron_id: str, book_id: int) -> Dict:
    """
    Calculate late fees for a specific book.
    
    Implements R5 as per requirements 
    """
    record = get_active_borrow_record(patron_id, book_id)
    if not record:
        return {
            "fee_amount": 0.0,
            "days_overdue": 0,
            "status": "No active borrow found for this patron and book.",
        }

    due_date = datetime.fromisoformat(record["due_date"])
    now = datetime.now()
    days_overdue = max(0, (now - due_date).days)

    if days_overdue <= 0:
        return {
            "fee_amount": 0.0,
            "days_overdue": 0,
            "status": "Book returned on time.",
        }

    first_week_days = min(days_overdue, 7)
    remaining_days = max(0, days_overdue - 7)
    fee_amount = (first_week_days * 0.50) + (remaining_days * 1.00)
    fee_amount = min(fee_amount, 15.0)

    return {
        "fee_amount": round(fee_amount, 2),
        "days_overdue": days_overdue,
        "status": "Book is overdue.",
    }

def search_books_in_catalog(search_term: str, search_type: str) -> List[Dict]:
    """
    Search for books in the catalog.
    
    Implements R6 as per requirements
    """
    if not search_term or not search_type:
        return []

    return search_books(search_term, search_type)

def get_patron_status_report(patron_id: str) -> Dict:
    """
    Get status report for a patron.
    
    Implements R7 as per requirements
    """
    if not patron_id or not patron_id.isdigit() or len(patron_id) != 6:
        return {
            "patron_id": patron_id,
            "current_loans": [],
            "history": [],
            "active_count": 0,
            "total_late_fees": 0.0,
            "status": "Invalid patron ID. Must be exactly 6 digits.",
        }

    records = get_patron_borrow_records(patron_id)
    current_loans: List[Dict] = []
    history: List[Dict] = []
    total_late_fees = 0.0

    for record in records:
        due_date = datetime.fromisoformat(record["due_date"])
        entry = {
            "book_id": record["book_id"],
            "title": record["title"],
            "author": record["author"],
            "borrow_date": datetime.fromisoformat(record["borrow_date"]),
            "due_date": due_date,
            "return_date": (
                datetime.fromisoformat(record["return_date"])
                if record["return_date"]
                else None
            ),
        }
        if record["return_date"] is None:
            fee = calculate_late_fee_for_book(patron_id, record["book_id"])
            total_late_fees += fee.get("fee_amount", 0.0)
            entry["is_overdue"] = fee.get("days_overdue", 0) > 0
            entry["late_fee"] = fee.get("fee_amount", 0.0)
            current_loans.append(entry)
        else:
            history.append(entry)

    return {
        "patron_id": patron_id,
        "current_loans": current_loans,
        "history": history,
        "active_count": len(current_loans),
        "total_late_fees": round(total_late_fees, 2),
        "status": "OK" if records else "No borrow records found.",
    }

def _payment_response(
    success: bool,
    message: str,
    *,
    transaction_id: str | None = None,
    amount: float = 0.0,
) -> Dict:
    return {
        "success": success,
        "message": message,
        "transaction_id": transaction_id,
        "amount": round(amount, 2),
    }

def _is_valid_patron_id(patron_id: str) -> bool:
    return bool(patron_id and patron_id.isdigit() and len(patron_id) == 6)

def pay_late_fees(
    patron_id: str,
    book_id: int,
    payment_gateway: PaymentGateway,
) -> Dict:
    if not _is_valid_patron_id(patron_id):
        return _payment_response(False, "invalid patron id; must be 6 digits.")

    book = get_book_by_id(book_id)
    if not book:
        return _payment_response(False, "book not found.")

    fee_info = calculate_late_fee_for_book(patron_id, book_id)
    fee_amount = round(float(fee_info.get("fee_amount", 0.0)), 2)
    if fee_amount <= 0:
        return _payment_response(False, "no late fees due for this book.")

    try:
        response = payment_gateway.process_payment(patron_id, book_id, fee_amount)
    except PaymentGatewayError as exc:
        return _payment_response(False, f"payment gateway error: {exc}", amount=fee_amount)
    except Exception as exc:  # pragma: no cover - defensive
        return _payment_response(False, f"payment failed: {exc}", amount=fee_amount)

    status = str(response.get("status", "")).lower()
    transaction_id = response.get("transaction_id")
    if status not in {"approved", "success", "ok"}:
        return _payment_response(
            False,
            "payment declined by gateway.",
            transaction_id=transaction_id,
            amount=fee_amount,
        )

    return _payment_response(
        True,
        f'late fee payment recorded for "{book["title"]}".',
        transaction_id=transaction_id,
        amount=fee_amount,
    )

def refund_late_fee_payment(
    transaction_id: str,
    amount: float,
    payment_gateway: PaymentGateway,
) -> Dict:
    if not transaction_id or not transaction_id.strip():
        return _payment_response(False, "transaction id is required.")

    normalized_amount = round(float(amount or 0.0), 2)
    if normalized_amount <= 0:
        return _payment_response(False, "refund amount must be positive.")
    if normalized_amount > 15.0:
        return _payment_response(False, "refund amount cannot exceed $15.00.")

    try:
        response = payment_gateway.refund_payment(transaction_id.strip(), normalized_amount)
    except PaymentGatewayError as exc:
        return _payment_response(False, f"payment gateway error: {exc}", amount=normalized_amount)
    except Exception as exc:  # pragma: no cover - defensive
        return _payment_response(False, f"refund failed: {exc}", amount=normalized_amount)

    status = str(response.get("status", "")).lower()
    if status not in {"refunded", "success", "ok"}:
        return _payment_response(
            False,
            "refund declined by gateway.",
            transaction_id=response.get("transaction_id", transaction_id),
            amount=normalized_amount,
        )

    return _payment_response(
        True,
        f"refund issued for ${normalized_amount:.2f}.",
        transaction_id=response.get("transaction_id", transaction_id),
        amount=normalized_amount,
    )
