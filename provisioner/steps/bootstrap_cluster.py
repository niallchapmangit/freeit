"""
Step 2 — Bootstrap Flux + Keycloak on the provisioned node.
Delegates to scripts/bootstrap-cluster.sh.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from provisioner.steps.base import Step


class BootstrapCluster(Step):
    name = "bootstrap_cluster"

    def execute(self) -> dict[str, Any]:
        node_ip = self.ledger.get_output("provision_node")["node_ip"]
        company_domain = self.ledger.get_output("provision_node")["company_domain"]
        spec = self.spec.company
        cfg = self.config
        repo_root = Path(cfg["repo_root"])
        script = repo_root / "scripts" / "bootstrap-cluster.sh"

        self.sh([
            "bash", str(script),
            "--company-id",   spec.company_id,
            "--node-ip",      node_ip,
            "--ssh-user",     cfg.get("ssh_user", "ubuntu"),
            "--ssh-key",      cfg["ssh_key"],
            "--repo-url",     cfg["repo_url"],
            "--domain",       company_domain,
            "--deploy-key",   cfg["deploy_key"],
            "--state-bucket", cfg["state_bucket"],
            "--aws-region",   cfg.get("state_region", "eu-west-1"),
        ])

        return {"company_domain": company_domain, "node_ip": node_ip}
