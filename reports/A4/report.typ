#set document(
  title: "Assignment 4: E2E Testing and Application Containerization",
  author: "Mike MacLennan",
  date: datetime(year: 2025, month: 11, day: 30),
)

#set page(
  paper: "us-letter",
  margin: 1in,
  header: [
    #set text(9pt)
    #grid(
      columns: (1fr, 1fr),
      align: (left, right),
      [CMPE 327 - Assignment 4],
      [Mike MacLennan - 20121416]
    )
    #line(length: 100%, stroke: 0.5pt)
  ],
)

#set text(size: 11pt)
#set par(justify: true)

#align(center + horizon)[
  #set page(header: none)
  #text(size: 16pt, weight: "bold")[Assignment 4: E2E Testing and Application Containerization]

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

= E2E Testing Approach

*Tool:* playwright for Python with pytest-playwright integration.

*Tested Features:*
- *Add Book Flow:* navigate to add book page, fill form fields (title, author, ISBN, copies), submit, verify success message and catalog entry
- *Search Book Flow:* search by title, author, and verify results; test no-results case
- *Catalog Navigation:* verify catalog displays books with availability status, test navigation links

*Assertion Strategy:*
- UI element presence via `page.locator()` and `is_visible()`
- text content verification using `inner_text()` checks
- flash message validation for success/error feedback
- table row content verification for data accuracy

= Execution Instructions

== Environment Setup

```bash
# create virtual environment
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt

# install playwright browsers
uv run playwright install chromium
```

== Running E2E Tests

```bash
# run all e2e tests
pytest tests/test_e2e.py

# run with verbose output
pytest tests/test_e2e.py -v
```

== Running Docker Container

```bash
# build the image
docker build -t library-app .

# run the container
docker run -p 5000:5000 library-app

# access at http://localhost:5000
```

= Test Case Summary

#table(
  columns: (auto, 1fr, 1fr),
  inset: 8pt,
  align: left,
  table.header(
    [*Test Name*], [*Actions*], [*Expected Result*]
  ),
  [test_add_book_and_verify_in_catalog],
  [navigate to `/add_book`, fill form with test book data, submit],
  [redirect to catalog, success flash message, book appears in table],

  [test_add_book_validation_duplicate_isbn],
  [attempt to add book with existing ISBN (Great Gatsby)],
  [error flash message about duplicate ISBN],

  [test_search_book_by_title],
  [navigate to `/search`, search "Great Gatsby" by title],
  [results table shows The Great Gatsby with F. Scott Fitzgerald],

  [test_search_book_by_author],
  [search "Harper Lee" by author],
  [results table shows To Kill a Mockingbird],

  [test_search_no_results],
  [search for non-existent book title],
  ["No results found" message displayed],

  [test_catalog_displays_books],
  [navigate to `/catalog`],
  [table displays books with availability status indicators],

  [test_navigate_to_add_book_from_catalog],
  [click "Add New Book" link from catalog],
  [navigates to `/add_book` page with correct heading],
)

= Dockerization Process

== Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY database.py .
COPY routes/ ./routes/
COPY services/ ./services/
COPY templates/ ./templates/

ENV FLASK_APP=app.py

EXPOSE 5000

CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
```

== Design Decisions

- *Base Image:* `python:3.11-slim` is small and has the Python runtime
- *Dependency Installation:* `--no-cache-dir` reduces image size by not caching pip packages
- *Selective COPY:* only copy useful files (no tests, reports, or dev files)
- *Host Binding:* `--host=0.0.0.0` allows container to accept external connections
- *Image Size:* ~140MB (\<500MB limit)

== Build and Run

```bash
docker build -t library-app .
docker run -p 5000:5000 library-app
```

= Docker Hub Deployment

== Commands Executed

```bash
# tag the image
docker tag library-app mikemacl/library-app:v1

# push to Docker Hub
docker push mikemacl/library-app:v1

# delete local image
docker rmi mikemacl/library-app:v1

# pull from Docker Hub
docker pull mikemacl/library-app:v1

# run from pulled image
docker run -p 5000:5000 mikemacl/library-app:v1
```

== Screenshots

#figure(
  image("media/docker_screenshots.png", width: 100%),
  caption: [Docker Hub push, delete, pull, and run verification]
)

= Challenges and Reflections

*Python Version Compatibility:* my system Python was initially using 3.114 (free-threaded) and playwright failed to install so I pinned the Python version to 3.12 using a `.python-version` file.

*Playwright Browser Installation:* unlike Selenium, Playwright requires explicit browser installation via `playwright install chromium`.
