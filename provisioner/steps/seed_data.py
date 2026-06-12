"""
Step 5 — Seed data: populate Files, Mail, and Calendar so the company
feels alive when the recruiter first logs in.
"""

from __future__ import annotations

import boto3
from typing import Any

from provisioner.seed.seeders import CalendarSeeder, FilesSeeder, MailSeeder
from provisioner.seed.spec import build_seed_bundle
from provisioner.steps.base import Step


class SeedData(Step):
    name = "seed_data"

    def execute(self) -> dict[str, Any]:
        company_domain = self.ledger.get_output("provision_node")["company_domain"]
        spec = self.spec.company

        files_url = f"https://files.{company_domain}"
        imap_host = f"mail.{company_domain}"
        caldav_url = f"https://mail.{company_domain}/dav"

        bundle = build_seed_bundle(self.spec)

        print(f"    Seeding {len(bundle.files)} file(s), "
              f"{len(bundle.mails)} email(s), "
              f"{len(bundle.calendars)} calendar event(s)")

        # Files — real WebDAV
        files_seeder = FilesSeeder(
            base_url=files_url,
            app_password_fn=lambda email: self._get_nextcloud_password(email, spec.company_id),
        )
        file_results = files_seeder.seed(bundle.files)

        # Mail — stub until E3.2
        mail_seeder = MailSeeder(imap_host=imap_host)
        mail_results = mail_seeder.seed(bundle.mails)

        # Calendar — stub until E3.2
        cal_seeder = CalendarSeeder(caldav_base_url=caldav_url)
        cal_results = cal_seeder.seed(bundle.calendars)

        created_files = sum(1 for v in file_results.values() if v == "created")
        skipped_files = sum(1 for v in file_results.values() if v == "skipped")

        return {
            "files": {"created": created_files, "skipped": skipped_files},
            "mails": {"stub": len(mail_results)},
            "calendars": {"stub": len(cal_results)},
        }

    def _get_nextcloud_password(self, email: str, company_id: str) -> str:
        """Fetch per-user Nextcloud app password from AWS Secrets Manager."""
        region = self.config.get("state_region", "eu-west-1")
        client = boto3.client("secretsmanager", region_name=region)
        # App passwords are stored by bootstrap-realm.sh (E1.3) or provisioner step
        # under freeit/<company_id>/nextcloud-app-password-<email>.
        secret_id = f"freeit/{company_id}/nextcloud-app-password-{email}"
        return client.get_secret_value(SecretId=secret_id)["SecretString"]
