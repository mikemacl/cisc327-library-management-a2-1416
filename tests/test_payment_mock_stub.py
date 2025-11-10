from __future__ import annotations

from unittest.mock import Mock

import pytest

from services.library_service import pay_late_fees, refund_late_fee_payment
from services.payment_service import PaymentGateway, PaymentGatewayError


@pytest.fixture
def payment_gateway_mock() -> Mock:
    return Mock(spec=PaymentGateway)


def test_pay_late_fees_succeeds_with_valid_data(mocker, payment_gateway_mock: Mock) -> None:
    mocker.patch(
        "services.library_service.get_book_by_id",
        return_value={"id": 9, "title": "clean code"},
    )
    mocker.patch(
        "services.library_service.calculate_late_fee_for_book",
        return_value={"fee_amount": 4.5},
    )
    payment_gateway_mock.process_payment.return_value = {
        "status": "approved",
        "transaction_id": "txn-ok",
    }

    result = pay_late_fees("123456", 9, payment_gateway_mock)

    assert result["success"] is True
    assert result["transaction_id"] == "txn-ok"
    payment_gateway_mock.process_payment.assert_called_once_with("123456", 9, 4.5)


def test_pay_late_fees_reports_declined_payment(mocker, payment_gateway_mock: Mock) -> None:
    mocker.patch(
        "services.library_service.get_book_by_id",
        return_value={"id": 4, "title": "refactoring"},
    )
    mocker.patch(
        "services.library_service.calculate_late_fee_for_book",
        return_value={"fee_amount": 6.0},
    )
    payment_gateway_mock.process_payment.return_value = {"status": "declined"}

    result = pay_late_fees("654321", 4, payment_gateway_mock)

    assert result["success"] is False
    assert "declined" in result["message"]
    payment_gateway_mock.process_payment.assert_called_once_with("654321", 4, 6.0)


def test_pay_late_fees_rejects_invalid_patron_id(mocker, payment_gateway_mock: Mock) -> None:
    book_stub = mocker.patch("services.library_service.get_book_by_id")
    fee_stub = mocker.patch("services.library_service.calculate_late_fee_for_book")

    result = pay_late_fees("abc123", 1, payment_gateway_mock)

    assert result["success"] is False
    book_stub.assert_not_called()
    fee_stub.assert_not_called()
    payment_gateway_mock.process_payment.assert_not_called()


def test_pay_late_fees_skips_when_no_fee_due(mocker, payment_gateway_mock: Mock) -> None:
    mocker.patch(
        "services.library_service.get_book_by_id",
        return_value={"id": 1, "title": "dry"},
    )
    mocker.patch(
        "services.library_service.calculate_late_fee_for_book",
        return_value={"fee_amount": 0.0},
    )

    result = pay_late_fees("123456", 1, payment_gateway_mock)

    assert result["success"] is False
    payment_gateway_mock.process_payment.assert_not_called()


def test_pay_late_fees_handles_gateway_errors(mocker, payment_gateway_mock: Mock) -> None:
    mocker.patch(
        "services.library_service.get_book_by_id",
        return_value={"id": 2, "title": "patterns"},
    )
    mocker.patch(
        "services.library_service.calculate_late_fee_for_book",
        return_value={"fee_amount": 3.25},
    )
    payment_gateway_mock.process_payment.side_effect = PaymentGatewayError("offline")

    result = pay_late_fees("999999", 2, payment_gateway_mock)

    assert result["success"] is False
    assert "error" in result["message"]
    payment_gateway_mock.process_payment.assert_called_once_with("999999", 2, 3.25)


def test_refund_late_fee_payment_succeeds(payment_gateway_mock: Mock) -> None:
    payment_gateway_mock.refund_payment.return_value = {
        "status": "refunded",
        "transaction_id": "txn-1",
    }

    result = refund_late_fee_payment("txn-1", 5.0, payment_gateway_mock)

    assert result["success"] is True
    assert result["transaction_id"] == "txn-1"
    payment_gateway_mock.refund_payment.assert_called_once_with("txn-1", 5.0)


def test_refund_late_fee_payment_requires_transaction_id(payment_gateway_mock: Mock) -> None:
    result = refund_late_fee_payment("", 5.0, payment_gateway_mock)

    assert result["success"] is False
    payment_gateway_mock.refund_payment.assert_not_called()


@pytest.mark.parametrize("amount", [-1.0, 0.0])
def test_refund_late_fee_payment_blocks_non_positive_amount(payment_gateway_mock: Mock, amount: float) -> None:
    result = refund_late_fee_payment("txn-2", amount, payment_gateway_mock)

    assert result["success"] is False
    payment_gateway_mock.refund_payment.assert_not_called()


def test_refund_late_fee_payment_caps_amount(payment_gateway_mock: Mock) -> None:
    result = refund_late_fee_payment("txn-3", 20.0, payment_gateway_mock)

    assert result["success"] is False
    payment_gateway_mock.refund_payment.assert_not_called()


def test_refund_late_fee_payment_handles_gateway_error(payment_gateway_mock: Mock) -> None:
    payment_gateway_mock.refund_payment.side_effect = PaymentGatewayError("timeout")

    result = refund_late_fee_payment("txn-4", 7.0, payment_gateway_mock)

    assert result["success"] is False
    assert "error" in result["message"]
    payment_gateway_mock.refund_payment.assert_called_once_with("txn-4", 7.0)


def test_refund_late_fee_payment_reports_declined_status(payment_gateway_mock: Mock) -> None:
    payment_gateway_mock.refund_payment.return_value = {"status": "denied"}

    result = refund_late_fee_payment("txn-5", 6.0, payment_gateway_mock)

    assert result["success"] is False
    payment_gateway_mock.refund_payment.assert_called_once_with("txn-5", 6.0)
