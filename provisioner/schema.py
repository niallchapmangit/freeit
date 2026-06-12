"""
CSV schema models and validation.
CompanySpec is the internal representation of one parsed CSV file.
"""

from __future__ import annotations

import csv
import re
from enum import Enum
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, EmailStr, field_validator, model_validator


class NodeSize(str, Enum):
    small = "small"
    medium = "medium"
    large = "large"


class Substrate(str, Enum):
    aws = "aws"


class Role(str, Enum):
    employee = "employee"
    manager = "manager"
    admin = "admin"


_COMPANY_ID_RE = re.compile(r"^[a-z0-9-]{3,32}$")
_EU_REGION_RE = re.compile(r"^eu-")


class CompanyRow(BaseModel):
    company_id: str
    company_name: str
    root_domain: str
    recruiter_email: EmailStr
    node_size: NodeSize = NodeSize.medium
    aws_region: str = "eu-west-1"
    substrate: Substrate = Substrate.aws

    @field_validator("company_id")
    @classmethod
    def validate_company_id(cls, v: str) -> str:
        if not _COMPANY_ID_RE.match(v):
            raise ValueError(
                f"company_id '{v}' must be 3-32 lowercase alphanumeric characters or hyphens"
            )
        return v

    @field_validator("aws_region")
    @classmethod
    def validate_eu_region(cls, v: str) -> str:
        if not _EU_REGION_RE.match(v):
            raise ValueError(f"aws_region '{v}' must be an EU region (eu-*) — GDPR requirement")
        return v

    @model_validator(mode="after")
    def recruiter_not_on_company_domain(self) -> CompanyRow:
        company_domain = f"{self.company_id}.{self.root_domain}"
        if self.recruiter_email.endswith(f"@{company_domain}"):
            raise ValueError(
                f"recruiter_email must be an external address, not on {company_domain}"
            )
        return self


class EmployeeRow(BaseModel):
    company_id: str
    email: EmailStr
    first_name: str
    last_name: str
    role: Role
    department: Optional[str] = None
    job_title: Optional[str] = None
    apps: list[str] = ["nextcloud", "mail"]
    is_onboarding_target: bool = False

    @field_validator("apps", mode="before")
    @classmethod
    def parse_apps(cls, v: object) -> list[str]:
        if isinstance(v, str):
            return [a.strip() for a in v.replace(",", ";").split(";") if a.strip()]
        return v  # type: ignore[return-value]

    @field_validator("is_onboarding_target", mode="before")
    @classmethod
    def parse_bool(cls, v: object) -> bool:
        if isinstance(v, str):
            return v.strip().lower() in ("true", "1", "yes")
        return bool(v)


class CompanySpec(BaseModel):
    """Fully validated, parsed representation of one CSV file."""

    company: CompanyRow
    employees: list[EmployeeRow]

    @property
    def company_domain(self) -> str:
        return f"{self.company.company_id}.{self.company.root_domain}"

    @model_validator(mode="after")
    def validate_employees(self) -> CompanySpec:
        if not self.employees:
            raise ValueError("CSV must contain at least one employee row")

        for emp in self.employees:
            if emp.company_id != self.company.company_id:
                raise ValueError(
                    f"Employee {emp.email} has company_id '{emp.company_id}' "
                    f"but company row has '{self.company.company_id}'"
                )

        admins = [e for e in self.employees if e.role == Role.admin]
        if not admins:
            raise ValueError("At least one employee must have role=admin")

        return self


def load_csv(path: Path) -> CompanySpec:
    """Parse and validate a CSV file into a CompanySpec. Raises ValueError on any error."""
    company_row: Optional[CompanyRow] = None
    employee_rows: list[EmployeeRow] = []

    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for lineno, row in enumerate(reader, start=2):
            record_type = row.get("record_type", "").strip().lower()
            if record_type == "company":
                if company_row is not None:
                    raise ValueError(f"Line {lineno}: duplicate company row")
                company_row = CompanyRow(**_clean(row))
            elif record_type == "employee":
                employee_rows.append(EmployeeRow(**_clean(row)))
            elif record_type:
                raise ValueError(f"Line {lineno}: unknown record_type '{record_type}'")

    if company_row is None:
        raise ValueError("CSV must contain exactly one company row")

    return CompanySpec(company=company_row, employees=employee_rows)


def _clean(row: dict[str, str]) -> dict[str, str]:
    """Strip whitespace and drop empty values so Pydantic uses defaults."""
    return {k.strip(): v.strip() for k, v in row.items() if v and v.strip()}
