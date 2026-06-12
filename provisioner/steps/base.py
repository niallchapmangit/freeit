"""Base class for all provisioning steps."""

from __future__ import annotations

import subprocess
from abc import ABC, abstractmethod
from typing import Any

from provisioner.ledger import Ledger
from provisioner.schema import CompanySpec


class StepError(Exception):
    pass


class Step(ABC):
    name: str  # unique step key used in the ledger

    def __init__(self, spec: CompanySpec, ledger: Ledger, config: dict[str, Any]) -> None:
        self.spec = spec
        self.ledger = ledger
        self.config = config

    def run(self, force: bool = False) -> dict[str, Any]:
        if self.ledger.is_done(self.name) and not force:
            print(f"  [skip] {self.name} — already done")
            return self.ledger.get_output(self.name)

        print(f"  [run]  {self.name}")
        try:
            output = self.execute()
            self.ledger.mark_done(self.name, output)
            print(f"  [done] {self.name}")
            return output
        except Exception as exc:
            self.ledger.mark_failed(self.name, str(exc))
            raise StepError(f"Step '{self.name}' failed: {exc}") from exc

    @abstractmethod
    def execute(self) -> dict[str, Any]:
        """Implement the step. Return a dict of outputs stored in the ledger."""

    def sh(self, cmd: list[str], check: bool = True, capture: bool = False) -> str:
        """Run a subprocess, streaming output unless capture=True."""
        result = subprocess.run(
            cmd,
            check=check,
            capture_output=capture,
            text=True,
        )
        return result.stdout.strip() if capture else ""
