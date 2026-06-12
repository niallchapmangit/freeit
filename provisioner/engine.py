"""
Provisioning engine — runs the step pipeline for one CompanySpec.

Pipeline (in order):
  1. provision_node      — OpenTofu: VM + DNS → node IP + company domain
  2. bootstrap_cluster   — Flux + Keycloak on the node
  3. provision_users     — Keycloak Admin API: create users from employee rows
  4. send_invite         — AWS SES: email the recruiter

Each step is idempotent via the Ledger. Re-running the engine skips completed
steps and picks up from the first incomplete one.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from provisioner.ledger import Ledger
from provisioner.schema import CompanySpec
from provisioner.steps.base import Step, StepError
from provisioner.steps.bootstrap_cluster import BootstrapCluster
from provisioner.steps.provision_node import ProvisionNode
from provisioner.steps.provision_users import ProvisionUsers
from provisioner.steps.seed_data import SeedData
from provisioner.steps.send_invite import SendInvite

PIPELINE: list[type[Step]] = [
    ProvisionNode,       # 1. VM + DNS via OpenTofu
    BootstrapCluster,    # 2. Flux + Keycloak on node
    ProvisionUsers,      # 3. Keycloak users from CSV
    SeedData,            # 4. Files / Mail / Calendar artefacts
    SendInvite,          # 5. Recruiter invite email
]


class Engine:
    def __init__(
        self,
        spec: CompanySpec,
        config: dict[str, Any],
        ledger_dir: Path,
        force_steps: list[str] | None = None,
    ) -> None:
        self.spec = spec
        self.config = config
        self.ledger = Ledger(spec.company.company_id, ledger_dir)
        self.force_steps = set(force_steps or [])

    def run(self) -> None:
        company_id = self.spec.company.company_id
        print(f"\nProvisioning company: {company_id}")
        print(f"Steps: {[s.name for s in PIPELINE]}\n")

        for step_cls in PIPELINE:
            step = step_cls(self.spec, self.ledger, self.config)
            force = step_cls.name in self.force_steps
            try:
                step.run(force=force)
            except StepError as exc:
                print(f"\n[FAILED] {exc}")
                print(f"Fix the issue and re-run — completed steps will be skipped.")
                raise SystemExit(1) from exc

        company_domain = self.ledger.get_output("provision_node").get("company_domain", "")
        print(f"\n{'─' * 50}")
        print(f"  Company ready: {company_id}")
        print(f"  URL:   https://{company_domain}")
        print(f"  Auth:  https://auth.{company_domain}")
        print(f"  Files: https://files.{company_domain}")
        print(f"  Mail:  https://mail.{company_domain}")
        print(f"{'─' * 50}\n")
