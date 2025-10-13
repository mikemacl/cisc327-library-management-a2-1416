"""
Status Routes - Patron status reporting endpoints
"""

from flask import Blueprint, render_template, request, flash

from library_service import get_patron_status_report

status_bp = Blueprint("status", __name__)


@status_bp.route("/status", methods=["GET", "POST"])
def patron_status():
    """
    Display patron status report.
    Web interface for R7: Patron Status Report
    """
    patron_id = ""
    report = None

    if request.method == "POST":
        patron_id = request.form.get("patron_id", "").strip()
    else:
        patron_id = request.args.get("patron_id", "").strip()

    if patron_id:
        report = get_patron_status_report(patron_id)
        if report.get("status", "").startswith("Invalid patron ID"):
            flash(report["status"], "error")
            report = None
    return render_template("patron_status.html", patron_id=patron_id, report=report)
