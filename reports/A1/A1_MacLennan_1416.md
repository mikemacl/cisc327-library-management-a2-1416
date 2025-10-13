# Assignment 1 Report

> **Name:** MacLennan
> **Student ID:** 20121416
> **Group:** None

## Implementation Status

| Function | Status | Notes |
|----------|--------|-------|
| add_book_to_catalog | partial | accepts any 13-character ISBN even if it has non-digits |
| borrow_book_by_patron | partial | borrow limit check uses `> 5`; customers can take a sixth book |
| return_book_by_patron | not implemented | returns stub message |
| calculate_late_fee_for_book | not implemented | placeholder dict, no logic |
| search_books_in_catalog | not implemented | always returns empty list |
| get_patron_status_report | not implemented | returns empty dict |

## Test Summary

- `tests/test_library_service.py` runs on a temp sqlite db with fresh state each test
- add-book cases cover happy path, blank title, long author, duplicate isbn, and the buggy non-digit isbn
- borrow flow checks invalid ids, unavailable books, limit bug, and a successful checkout
- returns, late fees, search, and status still unimplemented so they stay marked xfail
