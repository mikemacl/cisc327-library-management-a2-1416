#set document(
  title: "Assignment 1: Baseline Implementation Report",
  author: "Mike MacLennan",
  date: datetime(year: 2025, month: 9, day: 21),
)

#set page(
  paper: "us-letter",
  margin: 1in,
  header: [
    #set text(9pt)
    #grid(
      columns: (1fr, 1fr),
      align: (left, right),
      [CMPE 327 - Assignment 1],
      [Mike MacLennan - 20121416]
    )
    #line(length: 100%, stroke: 0.5pt)
  ],
)

#set text(size: 11pt)
#set par(justify: true)

#align(center + horizon)[
  #set page(header: none)
  #text(size: 18pt, weight: "bold")[Assignment 1: Baseline Implementation Report]

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

#set heading(numbering: "1.")
= Implementation Status
#table(
  columns: (auto, auto, auto),
  table.header([Function], [Status], [Notes]),
  `add_book_to_catalog`, [partial], [accepts any 13-character ISBN even if it has non-digits],
  `borrow_book_by_patron`, [partial], [borrow limit check uses "> 5" allowing a sixth book],
  `return_book_by_patron`, [not implemented], [placeholder response only],
  `calculate_late_fee_for_book`, [not implemented], [returns static dict with no logic],
  `search_books_in_catalog`, [not implemented], [always returns an empty list],
  `get_patron_status_report`, [not implemented], [returns an empty dict]
)

= Test Summary

- `tests/test_library_service.py` uses an isolated SQLite database per test run for deterministic state.
- Add-book tests cover happy path, blank title, overlong author, duplicate ISBN, and the non-digit ISBN bug.
- Borrow-flow tests assert invalid patron IDs, unavailable inventory, the borrow-limit bug, and a successful checkout.
- Return, late-fee, search, and status tests remain marked `xfail` until their implementations exist.
