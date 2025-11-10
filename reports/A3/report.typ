#set document(
  title: "Assignment 3: Mock and Stub Testing",
  author: "Mike MacLennan",
  date: datetime(year: 2025, month: 11, day: 09),
)

#set page(
  paper: "us-letter",
  margin: 1in,
  header: [
    #set text(9pt)
    #grid(
      columns: (1fr, 1fr),
      align: (left, right),
      [CMPE 327 - Assignment 3],
      [Mike MacLennan - 20121416]
    )
    #line(length: 100%, stroke: 0.5pt)
  ],
)

#set text(size: 11pt)
#set par(justify: true)

#align(center + horizon)[
  #set page(header: none)
  #text(size: 18pt, weight: "bold")[Assignment 3: Mock and Stub Testing]

  #text(size: 14pt)[CMPE 327 - Software Quality Assurance]

  #text(size: 12pt)[Mike MacLennan]

  #text(size: 12pt)[#context document.date.display()]

  #link("https://github.com/mikemacl/cisc327-library-management-a2-1416")
]

#pagebreak()

#outline(indent: auto)

#pagebreak()

#set heading(numbering: "1.")
= Student Information

*Name:* Mike MacLennan \
*Student ID:* 20121416 \
*Submission Date:* #context document.date.display()

= Stubbing vs. Mocking

*Stubs* are fake implementations that return hard-coded values without verification. They replace dependencies when only return values matter. I stubbed `get_book_by_id()` and `calculate_late_fee_for_book()` using `mocker.patch()`. These functions normally query SQLite but the tests only need their outputs. The stubs return dictionaries with test data, eliminating database calls and making tests fast and deterministic.

*Mocks* are test doubles that verify interactions occurred correctly. Unlike stubs, mocks track how they were called and assert proper parameters were passed. I mocked the `PaymentGateway` class using `Mock(spec=PaymentGateway)` because verifying the payment API is critical. Each test configures the mock's return value for `process_payment()` or `refund_payment()`, then uses `assert_called_once_with()`, `assert_not_called()`, or similar assertions to verify correct amounts and transaction IDs were sent.

*Strategy:* Database functions are stubbed because I only need their outputs. The payment gateway is mocked because I must verify the system calls it with correct parameters. Functions under test (`pay_late_fees` and `refund_late_fee_payment`) use real implementations to exercise actual business logic. This approach isolates external dependencies while testing real code paths, achieving 91% statement coverage and 81% branch coverage without database or network calls.

= Test Execution Instructions

== Environment Setup

```bash
# create venv (can do this without `uv` as well)
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

== Running Tests

```bash
# run all tests
pytest

# run only legacy tests (baseline coverage)
pytest tests/test_library_service.py

# run with coverage report
pytest --cov=services --cov-report=term-missing --cov-report=html tests

# include branch coverage
pytest --cov=services --cov-branch --cov-report=term-missing
coverage xml -i

# view HTML coverage report
python -m webbrowser -t htmlcov/index.html
```

= Test Cases Summary

== Payment Processing Tests (`pay_late_fees`)

*`test_pay_late_fees_succeeds_with_valid_data`*

- purpose: successful payment processing
- stubs: `get_book_by_id`, `calculate_late_fee_for_book`
- mocks: `PaymentGateway.process_payment`
- verification: `assert_called_once_with` validates amount and IDs

*`test_pay_late_fees_reports_declined_payment`*

- purpose: handle declined payments
- stubs: `get_book_by_id`, `calculate_late_fee_for_book`
- mocks: `PaymentGateway.process_payment` (returns declined)
- verification: error message checked

*`test_pay_late_fees_rejects_invalid_patron_id`*

- purpose: reject invalid patron IDs
- stubs: none
- mocks: `PaymentGateway.process_payment`
- verification: `assert_not_called` on all dependencies

*`test_pay_late_fees_skips_when_no_fee_due`*

- purpose: skip payment when fee is \$0
- stubs: `get_book_by_id`, `calculate_late_fee_for_book` (returns 0)
- mocks: `PaymentGateway.process_payment`
- verification: `assert_not_called` on gateway

*`test_pay_late_fees_handles_gateway_errors`*

- purpose: handle network/gateway errors
- stubs: `get_book_by_id`, `calculate_late_fee_for_book`
- mocks: `PaymentGateway.process_payment` (raises exception)
- verification: exception caught and propagated

== Refund Processing Tests (`refund_late_fee_payment`)

*`test_refund_late_fee_payment_succeeds`*

- purpose: successful refund processing
- stubs: none
- mocks: `PaymentGateway.refund_payment`
- verification: `assert_called_once_with` validates transaction ID and amount

*`test_refund_late_fee_payment_requires_transaction_id`*

- purpose: reject missing transaction ID
- stubs: none
- mocks: `PaymentGateway.refund_payment`
- verification: `assert_not_called` on gateway

*`test_refund_late_fee_payment_blocks_non_positive_amount`*

- purpose: reject zero/negative amounts
- stubs: none
- mocks: `PaymentGateway.refund_payment`
- verification: `assert_not_called` for each invalid amount

*`test_refund_late_fee_payment_caps_amount`*

- purpose: enforce \$15 maximum refund
- stubs: none
- mocks: `PaymentGateway.refund_payment`
- verification: `assert_not_called` for amounts greater than \$15

*`test_refund_late_fee_payment_handles_gateway_error`*

- purpose: handle gateway errors during refund
- stubs: none
- mocks: `PaymentGateway.refund_payment` (raises exception)
- verification: error message verified

*`test_refund_late_fee_payment_reports_declined_status`*

- purpose: handle denied refunds
- stubs: none
- mocks: `PaymentGateway.refund_payment` (returns denied)
- verification: failure message checked

= Coverage Analysis

== Initial Coverage

Before adding mock/stub tests, running only the original test suite:

```bash
pytest --cov=services tests/test_library_service.py
```

*Results:*
- statement coverage: 66.7%
- all payment functions uncovered (shown in red in HTML report)

== Final Coverage

After adding 11 new tests for payment processing and refunds:

```bash
pytest --cov=services --cov-branch tests/
```

*Results:*
- statement coverage: *91.0%* (132/145 lines)
- branch coverage: *80.9%* (55/68 branches)

== Improvements Made

Payment function tests added coverage for:
- successful payment/refund paths
- error handling branches (declined, network errors)
- input validation branches (invalid IDs, zero amounts, negative amounts)
- edge cases (maximum refund limit, missing transaction IDs)

== Remaining Uncovered Lines

The remaining uncovered lines are in `payment_service.py`, an external library that shouldn't be modified or tested per assignment instructions.

= Challenges and Solutions

== Import Path Changes

*Problem:* moving `library_service.py` to `services/` broke imports in routes, tests, and app files.

*Solution:* updated all imports to `services.library_service` and added `services/__init__.py`. Modified `conftest.py`, route handlers, and sample scripts.

== Mock Configuration

*Problem:* Understanding when to use `mocker.patch()` vs `Mock(spec=)` and how to configure return values.

*Solution:* Used `mocker.patch()` for stubbing internal functions (database calls) and `Mock(spec=PaymentGateway)` for the external API. Configured mocks with `return_value` dictionaries or `side_effect` exceptions before passing to functions under test.

== Coverage Metrics

*Problem:* `payment_service.py` (external library) counted against coverage percentage.

*Solution:* Created `.coveragerc` to exclude `payment_service.py` from coverage calculations, focusing metrics on authored code.

= Screenshots

== Test Execution Results

#figure(
  image("media/pytest_screenshot.png", width: 100%),
  caption: [All tests passing]
)


== Test Coverage Report

#figure(
  image("media/pytest_cov_screenshot.png", width: 100%),
  caption: [Coverage terminal output showing 91% statement and 81% branch coverage]
)

#pagebreak()

== HTML Coverage Summary

#figure(
  image("media/html_screenshot.png", width: 100%),
  caption: [HTML coverage report showing detailed line-by-line metrics]
)
