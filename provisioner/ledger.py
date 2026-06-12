"""
Idempotency ledger — tracks step completion per company.
Stored as a JSON file at ~/.freeit/ledger/<company_id>.json.

On re-run, completed steps are skipped. A step can be forced to re-run
by passing --force-step <step_name> to the CLI.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _ledger_path(company_id: str, ledger_dir: Path) -> Path:
    ledger_dir.mkdir(parents=True, exist_ok=True)
    return ledger_dir / f"{company_id}.json"


class Ledger:
    def __init__(self, company_id: str, ledger_dir: Path) -> None:
        self.company_id = company_id
        self._path = _ledger_path(company_id, ledger_dir)
        self._data: dict[str, Any] = self._load()

    def _load(self) -> dict[str, Any]:
        if self._path.exists():
            return json.loads(self._path.read_text())
        return {"company_id": self.company_id, "steps": {}}

    def _save(self) -> None:
        self._path.write_text(json.dumps(self._data, indent=2))

    def is_done(self, step: str) -> bool:
        return self._data["steps"].get(step, {}).get("status") == "done"

    def mark_done(self, step: str, output: dict[str, Any] | None = None) -> None:
        self._data["steps"][step] = {
            "status": "done",
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "output": output or {},
        }
        self._save()

    def mark_failed(self, step: str, error: str) -> None:
        self._data["steps"][step] = {
            "status": "failed",
            "failed_at": datetime.now(timezone.utc).isoformat(),
            "error": error,
        }
        self._save()

    def get_output(self, step: str) -> dict[str, Any]:
        return self._data["steps"].get(step, {}).get("output", {})

    def reset_step(self, step: str) -> None:
        self._data["steps"].pop(step, None)
        self._save()

    def summary(self) -> dict[str, str]:
        return {k: v["status"] for k, v in self._data["steps"].items()}
