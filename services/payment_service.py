"""simulated external payment gateway."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Dict


class PaymentGatewayError(Exception):
    """raised when the gateway refuses to act."""


@dataclass
class PaymentResult:
    transaction_id: str
    status: str
    amount: float


class PaymentGateway:
    """small fake payment provider"""

    def process_payment(self, patron_id: str, book_id: int, amount: float) -> Dict[str, str | float]:
        if amount <= 0:
            raise PaymentGatewayError("amount must be positive")
        transaction_id = self._build_txn("pay", patron_id, book_id)
        return {"transaction_id": transaction_id, "status": "approved", "amount": round(amount, 2)}

    def refund_payment(self, transaction_id: str, amount: float) -> Dict[str, str | float]:
        if not transaction_id:
            raise PaymentGatewayError("transaction id required")
        if amount <= 0:
            raise PaymentGatewayError("amount must be positive")
        return {"transaction_id": transaction_id, "status": "refunded", "amount": round(amount, 2)}

    def _build_txn(self, prefix: str, patron_id: str, book_id: int) -> str:
        stamp = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
        return f"{prefix}_{patron_id}_{book_id}_{stamp}"


__all__ = ["PaymentGateway", "PaymentGatewayError", "PaymentResult"]
