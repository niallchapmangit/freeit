"""
Step 1 — Provision the VM via OpenTofu (infra/stacks/company).
Outputs: node_ip, company_domain.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from provisioner.steps.base import Step


class ProvisionNode(Step):
    name = "provision_node"

    def execute(self) -> dict[str, Any]:
        spec = self.spec.company
        repo_root = Path(self.config["repo_root"])
        stack_dir = repo_root / "infra" / "stacks" / "company"
        tfvars_path = stack_dir / "env" / f"{spec.company_id}.tfvars"

        self._write_tfvars(tfvars_path)
        self._tofu_init(stack_dir, spec.company_id)
        self._tofu_apply(stack_dir, tfvars_path)
        return self._tofu_outputs(stack_dir)

    def _write_tfvars(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        spec = self.spec.company
        cfg = self.config
        content = (
            f'company_id     = "{spec.company_id}"\n'
            f'substrate      = "{spec.substrate}"\n'
            f'node_size      = "{spec.node_size}"\n'
            f'region         = "{spec.aws_region}"\n'
            f'root_domain    = "{spec.root_domain}"\n'
            f'ssh_public_key = "{cfg["ssh_public_key"]}"\n'
            f'ssh_cidrs      = {json.dumps(cfg["ssh_cidrs"])}\n'
            f'api_cidrs      = {json.dumps(cfg["api_cidrs"])}\n'
        )
        path.write_text(content)

    def _tofu_init(self, stack_dir: Path, company_id: str) -> None:
        cfg = self.config
        self.sh([
            "tofu", f"-chdir={stack_dir}", "init", "-reconfigure",
            f'-backend-config=bucket={cfg["state_bucket"]}',
            f'-backend-config=key=companies/{company_id}/terraform.tfstate',
            f'-backend-config=region={cfg["state_region"]}',
        ])

    def _tofu_apply(self, stack_dir: Path, tfvars_path: Path) -> None:
        env = os.environ.copy()
        env["TF_VAR_state_passphrase"] = self.config["state_passphrase"]
        env["TF_VAR_cloudflare_api_token"] = self.config["cloudflare_api_token"]
        env["TF_VAR_cloudflare_zone_id"] = self.config["cloudflare_zone_id"]
        subprocess_env = env

        import subprocess
        subprocess.run(
            ["tofu", f"-chdir={stack_dir}", "apply", "-auto-approve",
             f"-var-file={tfvars_path}"],
            check=True,
            env=subprocess_env,
        )

    def _tofu_outputs(self, stack_dir: Path) -> dict[str, Any]:
        raw = self.sh(
            ["tofu", f"-chdir={stack_dir}", "output", "-json"],
            capture=True,
        )
        outputs = json.loads(raw)
        return {
            "node_ip": outputs["node_public_ip"]["value"],
            "company_domain": outputs["company_domain"]["value"],
        }
