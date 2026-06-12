"""
freeit — Company-in-a-CSV provisioning CLI.

Usage:
  freeit provision <csv_file> [options]
  freeit status    <company_id>
  freeit retry     <csv_file> --step <step_name>

Examples:
  freeit provision docs/csv/niall-demo.csv
  freeit provision docs/csv/niall-demo.csv --dry-run
  freeit status niall-demo
  freeit retry docs/csv/niall-demo.csv --step provision_users

Configuration is loaded from freeit.yaml in the repo root (non-secret values)
and a .env file alongside it (secrets — never committed).
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import click

from provisioner.engine import PIPELINE, Engine
from provisioner.ledger import Ledger
from provisioner.schema import load_csv


def _find_config_file() -> Path | None:
    """Walk up from cwd looking for freeit.yaml."""
    for directory in [Path.cwd(), *Path.cwd().parents]:
        candidate = directory / "freeit.yaml"
        if candidate.exists():
            return candidate
    return None


def _load_config(config_path: Path | None) -> dict:
    """
    Build runtime config by merging (lowest → highest priority):
      1. freeit.yaml  — operator defaults committed to the repo
      2. .env file    — secrets that must never be committed
      3. FREEIT_*     — environment variable overrides (CI / shell)
    """
    try:
        import yaml
    except ImportError:
        click.echo("[error] PyYAML is required: pip install pyyaml", err=True)
        sys.exit(1)

    # Layer 1: freeit.yaml
    file_cfg: dict = {}
    if config_path and config_path.exists():
        with config_path.open() as fh:
            file_cfg = yaml.safe_load(fh) or {}
        click.echo(f"Config     : {config_path}")
    else:
        click.echo("Config     : (no freeit.yaml found — using environment only)")

    # Layer 2: .env file alongside freeit.yaml (secrets — never committed)
    env_file = (config_path.parent / ".env") if config_path else (Path.cwd() / ".env")
    if env_file.exists():
        with env_file.open() as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    os.environ.setdefault(k.strip(), v.strip())

    # Layer 3: FREEIT_* env vars override everything
    env_map = {
        "FREEIT_ROOT_DOMAIN":           "root_domain",
        "FREEIT_CLOUDFLARE_ZONE_ID":    "cloudflare_zone_id",
        "FREEIT_CLOUDFLARE_API_TOKEN":  "cloudflare_api_token",
        "FREEIT_STATE_BUCKET":          "state_bucket",
        "FREEIT_AWS_REGION":            "aws_region",
        "FREEIT_SSH_KEY":               "ssh_key",
        "FREEIT_SSH_PUBLIC_KEY":        "ssh_public_key",
        "FREEIT_SSH_CIDRS":             "ssh_cidrs",
        "FREEIT_API_CIDRS":             "api_cidrs",
        "FREEIT_SSH_USER":              "ssh_user",
        "FREEIT_REPO_URL":              "repo_url",
        "FREEIT_DEPLOY_KEY":            "deploy_key",
        "FREEIT_SES_FROM_ADDRESS":      "ses_from_address",
        "FREEIT_STATE_PASSPHRASE":      "state_passphrase",
    }
    cfg = dict(file_cfg)
    for env_var, key in env_map.items():
        val = os.environ.get(env_var)
        if val:
            cfg[key] = val

    # Normalise list fields (may arrive as comma-string from env or list from yaml)
    for field in ("ssh_cidrs", "api_cidrs"):
        raw = cfg.get(field, "")
        if isinstance(raw, str):
            cfg[field] = [c.strip() for c in raw.split(",") if c.strip()]

    # Expand ~ in path fields
    for field in ("ssh_key", "ssh_public_key", "deploy_key"):
        if cfg.get(field):
            cfg[field] = str(Path(cfg[field]).expanduser())

    # Validate secrets (must come from .env or env — never freeit.yaml)
    missing_secrets = []
    for key, hint in {
        "state_passphrase":     "FREEIT_STATE_PASSPHRASE (or .env: FREEIT_STATE_PASSPHRASE=...)",
        "cloudflare_api_token": "FREEIT_CLOUDFLARE_API_TOKEN (or .env: FREEIT_CLOUDFLARE_API_TOKEN=...)",
    }.items():
        if not cfg.get(key):
            missing_secrets.append(hint)

    # Validate non-secret required fields
    missing_fields = []
    for key, hint in {
        "root_domain":        "root_domain in freeit.yaml",
        "cloudflare_zone_id": "cloudflare_zone_id in freeit.yaml",
        "state_bucket":       "state_bucket in freeit.yaml",
        "ssh_key":            "ssh_key in freeit.yaml",
        "ssh_public_key":     "ssh_public_key in freeit.yaml",
        "repo_url":           "repo_url in freeit.yaml",
        "deploy_key":         "deploy_key in freeit.yaml",
        "ses_from_address":   "ses_from_address in freeit.yaml",
    }.items():
        if not cfg.get(key):
            missing_fields.append(hint)

    missing = missing_secrets + missing_fields
    if missing:
        click.echo("[error] Missing configuration:\n  " + "\n  ".join(missing), err=True)
        click.echo(
            "\nNon-secret values → freeit.yaml\n"
            "Secrets           → .env file (same directory as freeit.yaml)\n",
            err=True,
        )
        sys.exit(1)

    cfg.setdefault("aws_region", "eu-west-1")
    cfg.setdefault("ssh_user", "ubuntu")
    return cfg


def _ledger_dir() -> Path:
    return Path.home() / ".freeit" / "ledger"


@click.group()
def cli() -> None:
    """freeit — provision a company from a CSV file."""


@cli.command()
@click.argument("csv_file", type=click.Path(exists=True, path_type=Path))
@click.option("--dry-run", is_flag=True, help="Validate CSV and config without making changes.")
@click.option(
    "--force-step",
    multiple=True,
    help="Force a specific step to re-run even if already done. Can be repeated.",
)
@click.option(
    "--config",
    "config_file",
    type=click.Path(path_type=Path),
    default=None,
    help="Path to freeit.yaml (defaults to auto-discovery from cwd upward).",
)
def provision(
    csv_file: Path,
    dry_run: bool,
    force_step: tuple[str, ...],
    config_file: Path | None,
) -> None:
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
        config_path = config_file or _find_config_file()
        _load_config(config_path)  # validate config is complete
        click.echo("\n[dry-run] Config and CSV valid. No infrastructure changes made.")
        return

    config_path = config_file or _find_config_file()
    config = _load_config(config_path)
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
@click.option(
    "--config",
    "config_file",
    type=click.Path(path_type=Path),
    default=None,
    help="Path to freeit.yaml (defaults to auto-discovery from cwd upward).",
)
def retry(csv_file: Path, step: str, config_file: Path | None) -> None:
    """Re-run a specific step for a company, skipping all others."""
    try:
        spec = load_csv(csv_file)
    except Exception as exc:
        click.echo(f"[error] {exc}", err=True)
        sys.exit(1)

    config_path = config_file or _find_config_file()
    config = _load_config(config_path)
    engine = Engine(spec, config, _ledger_dir(), force_steps=[step])
    engine.run()


def main() -> None:
    cli()


if __name__ == "__main__":
    main()
