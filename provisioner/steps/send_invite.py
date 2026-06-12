"""
Step 4 — Send the recruiter invite to their real external email.
This is the only email in the whole flow that needs real deliverability.
Uses AWS SES (simple, EU region, no MX record required for outbound).
"""

from __future__ import annotations

from typing import Any

import boto3

from provisioner.steps.base import Step


INVITE_SUBJECT = "Your demo company is ready"

INVITE_BODY_TEXT = """\
Hi,

Your demo company '{company_name}' is ready.

Log in here: https://{company_domain}

What's inside:
  - Email & calendar: https://mail.{company_domain}
  - Files: https://files.{company_domain}
  - User management: https://auth.{company_domain}

Your team is already set up and onboarding packs are pre-seeded.

This environment is isolated and single-tenant — nothing shared.

Enjoy the demo.
"""

INVITE_BODY_HTML = """\
<p>Hi,</p>
<p>Your demo company <strong>{company_name}</strong> is ready.</p>
<p><a href="https://{company_domain}">Log in here</a></p>
<ul>
  <li><a href="https://mail.{company_domain}">Email &amp; Calendar</a></li>
  <li><a href="https://files.{company_domain}">Files</a></li>
  <li><a href="https://auth.{company_domain}">User Management</a></li>
</ul>
<p>Your team is already set up and onboarding packs are pre-seeded.</p>
<p>This environment is isolated and single-tenant — nothing shared.</p>
"""


class SendInvite(Step):
    name = "send_invite"

    def execute(self) -> dict[str, Any]:
        spec = self.spec.company
        company_domain = self.ledger.get_output("provision_node")["company_domain"]
        region = self.config.get("ses_region", self.config.get("state_region", "eu-west-1"))
        from_addr = self.config["ses_from_address"]

        body_text = INVITE_BODY_TEXT.format(
            company_name=spec.company_name,
            company_domain=company_domain,
        )
        body_html = INVITE_BODY_HTML.format(
            company_name=spec.company_name,
            company_domain=company_domain,
        )

        ses = boto3.client("ses", region_name=region)
        resp = ses.send_email(
            Source=from_addr,
            Destination={"ToAddresses": [spec.recruiter_email]},
            Message={
                "Subject": {"Data": INVITE_SUBJECT},
                "Body": {
                    "Text": {"Data": body_text},
                    "Html": {"Data": body_html},
                },
            },
        )

        message_id = resp["MessageId"]
        print(f"    [ok] invite sent to {spec.recruiter_email} (MessageId={message_id})")
        return {"message_id": message_id, "to": spec.recruiter_email}
