"""e2e browser tests for library management system."""

import os
import subprocess
import sys
import time

import pytest

BASE_URL = "http://localhost:5000"


@pytest.fixture(scope="session")
def flask_server():
    """start Flask server"""
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    proc = subprocess.Popen(
        [sys.executable, "app.py"],
        cwd=project_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    time.sleep(2)

    if proc.poll() is not None:
        stdout, stderr = proc.communicate()
        raise RuntimeError(f"Flask server failed to start: {stderr.decode()}")

    yield BASE_URL

    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


# add book flow
class TestAddBookFlow:
    def test_add_book_and_verify_in_catalog(self, page, flask_server):
        base_url = flask_server
        test_book = {
            "title": "The Playwright Guide",
            "author": "Test Author",
            "isbn": "9781234567890",
            "copies": "5",
        }

        page.goto(f"{base_url}/add_book")
        assert "Add New Book" in page.locator("h2").inner_text()

        page.fill("#title", test_book["title"])
        page.fill("#author", test_book["author"])
        page.fill("#isbn", test_book["isbn"])
        page.fill("#total_copies", test_book["copies"])
        page.click("button:has-text('Add Book to Catalog')")

        page.wait_for_url(f"{base_url}/catalog")
        flash_message = page.locator(".flash-success")
        assert flash_message.is_visible()
        assert "successfully" in flash_message.inner_text().lower()

        book_row = page.locator(f"table tbody tr:has-text('{test_book['title']}')")
        assert book_row.is_visible()
        assert test_book["author"] in book_row.inner_text()
        assert test_book["isbn"] in book_row.inner_text()

    def test_add_book_validation_duplicate_isbn(self, page, flask_server):
        base_url = flask_server
        existing_isbn = "9780743273565"  # The Great Gatsby

        page.goto(f"{base_url}/add_book")
        page.fill("#title", "Duplicate Test Book")
        page.fill("#author", "Test Author")
        page.fill("#isbn", existing_isbn)
        page.fill("#total_copies", "1")
        page.click("button:has-text('Add Book to Catalog')")

        flash_message = page.locator(".flash-error")
        assert flash_message.is_visible()
        assert (
            "isbn" in flash_message.inner_text().lower()
            or "exists" in flash_message.inner_text().lower()
        )


# search book flow
class TestSearchBookFlow:
    def test_search_book_by_title(self, page, flask_server):
        base_url = flask_server
        search_term = "Great Gatsby"

        page.goto(f"{base_url}/search")
        assert "Search Books" in page.locator("h2").inner_text()

        page.fill("#q", search_term)
        page.select_option("#type", "title")
        page.click("button:has-text('Search')")

        page.wait_for_selector("table tbody tr")
        results_heading = page.locator("h3:has-text('Search Results')")
        assert results_heading.is_visible()
        assert search_term in results_heading.inner_text()

        result_row = page.locator("table tbody tr:has-text('The Great Gatsby')")
        assert result_row.is_visible()
        assert "F. Scott Fitzgerald" in result_row.inner_text()

    def test_search_book_by_author(self, page, flask_server):
        base_url = flask_server
        search_term = "Harper Lee"

        page.goto(f"{base_url}/search")
        page.fill("#q", search_term)
        page.select_option("#type", "author")
        page.click("button:has-text('Search')")

        page.wait_for_selector("table tbody tr")
        result_row = page.locator("table tbody tr:has-text('To Kill a Mockingbird')")
        assert result_row.is_visible()

    def test_search_no_results(self, page, flask_server):
        base_url = flask_server
        search_term = "NonExistentBookTitle12345"

        page.goto(f"{base_url}/search")
        page.fill("#q", search_term)
        page.click("button:has-text('Search')")

        no_results = page.locator("text=No results found")
        assert no_results.is_visible()


# catalog navigation
class TestCatalogNavigation:
    def test_catalog_displays_books(self, page, flask_server):
        base_url = flask_server

        page.goto(f"{base_url}/catalog")
        assert "Book Catalog" in page.locator("h2").inner_text()

        gatsby_row = page.locator("table tbody tr:has-text('The Great Gatsby')")
        assert gatsby_row.is_visible()

        availability = gatsby_row.locator(".status-available, .status-unavailable")
        assert availability.is_visible()

    def test_navigate_to_add_book_from_catalog(self, page, flask_server):
        base_url = flask_server

        page.goto(f"{base_url}/catalog")
        page.click("a:has-text('Add New Book')")

        page.wait_for_url(f"{base_url}/add_book")
        assert "Add New Book" in page.locator("h2").inner_text()
