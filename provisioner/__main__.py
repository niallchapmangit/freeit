"""
freeit — Company-in-a-CSV provisioning CLI.

Usage:
  freeit provision <csv_file> [options]
  freeit status    <company_id>
  freeit retry     <csv_file> --step <step_name>

Examples:
  freeit provision docs/csv/example.csv
  freeit provision docs/csv/example.csv --dry-run
  freeit status acme-demo
  freeit retry docs/csv/example.csv --step provision_users
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import click

from provisioner.engine import PIPELINE, Engine
from provisioner.ledger import Ledger
from provisioner.schema import load_csv


def _config_from_env() -> dict:
    """Load required configuration from environment variables."""
    missing = []
    cfg: dict = {}

    required = {
        "FREEIT_REPO_ROOT": "repo_root",
        "FREEIT_STATE_BUCKET": "state_bucket",
        "FREEIT_STATE_PASSPHRASE": "state_passphrase",
        "FREEIT_SSH_KEY": "ssh_key",
        "FREEIT_SSH_PUBLIC_KEY": "ssh_public_key",
        "FREEIT_REPO_URL": "repo_url",
        "FREEIT_DEPLOY_KEY": "deploy_key",
        "FREEIT_CLOUDFLARE_API_TOKEN": "cloudflare_api_token",
        "FREEIT_CLOUDFLARE_ZONE_ID": "cloudflare_zone_id",
        "FREEIT_SES_FROM_ADDRESS": "ses_from_address",
    }

    for env_var, key in required.items():
        val = os.environ.get(env_var, "")
        if not val:
            missing.append(env_var)
        cfg[key] = val

    if missing:
        click.echo(f"Missing required environment variables:\n  " + "\n  ".join(missing), err=True)
        sys.exit(1)

    cfg.setdefault("state_region", os.environ.get("FREEIT_STATE_REGION", "eu-west-1"))
    cfg.setdefault("ssh_user", os.environ.get("FREEIT_SSH_USER", "ubuntu"))
    cfg["ssh_cidrs"] = os.environ.get("FREEIT_SSH_CIDRS", "").split(",")
    cfg["api_cidrs"] = os.environ.get("FREEIT_API_CIDRS", "").split(",")

    return cfg


def _ledger_dir() -> Path:
    return Path.home() / ".freeit" / "ledger"


@click.group()
def cli() -> None:
    """freeit — provision a company from a CSV file."""


@cli.command()
@click.argument("csv_file", type=click.Path(exists=True, path_type=Path))
@click.option("--dry-run", is_flag=True, help="Validate CSV and print plan without running.")
@click.option(
    "--force-step",
    multiple=True,
    help="Force a specific step to re-run even if already done. Can be repeated.",
)
def provision(csv_file: Path, dry_run: bool, force_step: tuple[str, ...]) -> None:
    """Provision a company from CSV_FILE."""
    click.echo(f"Loading CSV: {csv_file}")
    try:
        spec = load_csv(csv_file)
    except (ValueError, Exception) as exc:
        click.echo(f"[error] CSV validation failed: {exc}", err=True)
        sys.exit(1)

    company = spec.company
    click.echo(f"Company    : {company.company_id} ({company.company_name})")
    click.echo(f"Domain     : {company.company_id}.{company.root_domain}")
    click.echo(f"Employees  : {len(spec.employees)}")
    click.echo(f"Recruiter  : {company.recruiter_email}")
    click.echo(f"Node size  : {company.node_size}")
    click.echo(f"Region     : {company.aws_region}")
    click.echo(f"Steps      : {[s.name for s in PIPELINE]}")

    if dry_run:
        click.echo("\n[dry-run] Validation passed. No infrastructure changes made.")
        return

    config = _config_from_env()
    engine = Engine(spec, config, _ledger_dir(), force_steps=list(force_step))
    engine.run()


@cli.command()
@click.argument("company_id")
def status(company_id: str) -> None:
    """Show provisioning status for COMPANY_ID."""
    ledger = Ledger(company_id, _ledger_dir())
    summary = ledger.summary()
    if not summary:
        click.echo(f"No ledger found for company: {company_id}")
        return

    click.echo(f"\nStatus for: {company_id}")
    for step, state in summary.items():
        icon = "✓" if state == "done" else "✗"
        click.echo(f"  {icon} {step}: {state}")
    click.echo()


@cli.command()
@click.argument("csv_file", type=click.Path(exists=True, path_type=Path))
@click.option("--step", required=True, help="Step name to force re-run.")
def retry(csv_file: Path, step: str) -> None:
    """Re-run a specific step for a company, skipping all others."""
    try:
        spec = load_csv(csv_file)
    except Exception as exc:
        click.echo(f"[error] {exc}", err=True)
        sys.exit(1)

    config = _config_from_env()
    engine = Engine(spec, config, _ledger_dir(), force_steps=[step])
    engine.run()


def main() -> None:
    cli()


if __name__ == "__main__":
    main()
