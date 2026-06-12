"""
Step 3 — Create Keycloak users via the Admin REST API (E2.2).
One user per employee row in the CSV. Idempotent: checks by email before creating.
"""

from __future__ import annotations

import secrets
import string
from typing import Any

import requests

from provisioner.schema import CompanySpec, EmployeeRow, Role
from provisioner.steps.base import Step


class ProvisionUsers(Step):
    name = "provision_users"

    def execute(self) -> dict[str, Any]:
        company_domain = self.ledger.get_output("provision_node")["company_domain"]
        spec = self.spec.company
        keycloak_url = f"https://auth.{company_domain}"
        realm = spec.company_id
        admin_pass = self._get_secret("keycloak-admin-password")

        token = self._get_token(keycloak_url, admin_pass)
        created: list[str] = []
        skipped: list[str] = []

        for emp in self.spec.employees:
            uid = self._upsert_user(keycloak_url, realm, token, emp)
            if uid:
                self._assign_role(keycloak_url, realm, token, uid, emp.role)
                created.append(emp.email)
            else:
                skipped.append(emp.email)

        return {"created": created, "skipped": skipped}

    def _get_secret(self, name: str) -> str:
        import boto3
        company_id = self.spec.company.company_id
        region = self.config.get("state_region", "eu-west-1")
        client = boto3.client("secretsmanager", region_name=region)
        secret_id = f"freeit/{company_id}/{name}"
        return client.get_secret_value(SecretId=secret_id)["SecretString"]

    def _get_token(self, base_url: str, admin_pass: str) -> str:
        resp = requests.post(
            f"{base_url}/realms/master/protocol/openid-connect/token",
            data={
                "client_id": "admin-cli",
                "username": "admin",
                "password": admin_pass,
                "grant_type": "password",
            },
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["access_token"]

    def _upsert_user(
        self,
        base_url: str,
        realm: str,
        token: str,
        emp: EmployeeRow,
    ) -> str | None:
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        admin = f"{base_url}/admin/realms/{realm}"

        # Check if user already exists.
        existing = requests.get(
            f"{admin}/users",
            params={"email": emp.email, "exact": "true"},
            headers=headers,
            timeout=30,
        )
        existing.raise_for_status()
        found = existing.json()
        if found:
            print(f"    [skip] user already exists: {emp.email}")
            return None

        # Generate a temporary password the user must change on first login.
        temp_pass = _random_password()

        resp = requests.post(
            f"{admin}/users",
            json={
                "username": emp.email,
                "email": emp.email,
                "firstName": emp.first_name,
                "lastName": emp.last_name,
                "enabled": True,
                "emailVerified": True,
                "credentials": [{
                    "type": "password",
                    "value": temp_pass,
                    "temporary": True,
                }],
                "attributes": {
                    "department": [emp.department or ""],
                    "jobTitle": [emp.job_title or ""],
                },
            },
            headers=headers,
            timeout=30,
        )
        resp.raise_for_status()

        # Keycloak returns the new user ID in the Location header.
        location = resp.headers.get("Location", "")
        user_id = location.rstrip("/").split("/")[-1]
        print(f"    [ok]   created user: {emp.email} (id={user_id})")
        return user_id

    def _assign_role(
        self,
        base_url: str,
        realm: str,
        token: str,
        user_id: str,
        role: Role,
    ) -> None:
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        admin = f"{base_url}/admin/realms/{realm}"

        role_resp = requests.get(
            f"{admin}/roles/{role.value}",
            headers=headers,
            timeout=30,
        )
        role_resp.raise_for_status()
        role_rep = role_resp.json()

        requests.post(
            f"{admin}/users/{user_id}/role-mappings/realm",
            json=[role_rep],
            headers=headers,
            timeout=30,
        ).raise_for_status()


def _random_password(length: int = 20) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(secrets.choice(alphabet) for _ in range(length))
