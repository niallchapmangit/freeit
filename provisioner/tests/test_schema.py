"""Tests for CSV schema parsing and validation."""

import textwrap
from pathlib import Path

import pytest

from provisioner.schema import load_csv, CompanySpec


def write_csv(tmp_path: Path, content: str) -> Path:
    p = tmp_path / "test.csv"
    p.write_text(textwrap.dedent(content).lstrip())
    return p


VALID_CSV = """\
    record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role,department,job_title,apps,is_onboarding_target
    company,acme-demo,Acme Corp,yourdemo.com,medium,alice@recruiter.com,,,,,,,,
    employee,acme-demo,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,admin,Engineering,Engineer,nextcloud;mail,true
    employee,acme-demo,,,,,carol@acme-demo.yourdemo.com,Carol,Jones,employee,HR,HR Lead,nextcloud;mail,false
"""


def test_valid_csv_parses(tmp_path: Path) -> None:
    spec = load_csv(write_csv(tmp_path, VALID_CSV))
    assert isinstance(spec, CompanySpec)
    assert spec.company.company_id == "acme-demo"
    assert len(spec.employees) == 2
    assert spec.company_domain == "acme-demo.yourdemo.com"


def test_employee_apps_parsed(tmp_path: Path) -> None:
    spec = load_csv(write_csv(tmp_path, VALID_CSV))
    assert spec.employees[0].apps == ["nextcloud", "mail"]


def test_missing_company_row(tmp_path: Path) -> None:
    csv = """\
        record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role
        employee,acme-demo,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,admin
    """
    with pytest.raises(ValueError, match="company row"):
        load_csv(write_csv(tmp_path, csv))


def test_duplicate_company_row(tmp_path: Path) -> None:
    csv = """\
        record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role
        company,acme-demo,Acme Corp,yourdemo.com,medium,alice@recruiter.com,,,,
        company,acme-demo,Acme Corp,yourdemo.com,medium,alice@recruiter.com,,,,
        employee,acme-demo,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,admin
    """
    with pytest.raises(ValueError, match="duplicate company row"):
        load_csv(write_csv(tmp_path, csv))


def test_invalid_company_id(tmp_path: Path) -> None:
    csv = """\
        record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role
        company,ACME CORP,Acme Corp,yourdemo.com,medium,alice@recruiter.com,,,,
        employee,ACME CORP,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,admin
    """
    with pytest.raises(ValueError, match="company_id"):
        load_csv(write_csv(tmp_path, csv))


def test_non_eu_region_rejected(tmp_path: Path) -> None:
    csv = """\
        record_type,company_id,company_name,root_domain,node_size,aws_region,recruiter_email,email,first_name,last_name,role
        company,acme-demo,Acme Corp,yourdemo.com,medium,us-east-1,alice@recruiter.com,,,,
        employee,acme-demo,,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,admin
    """
    with pytest.raises(ValueError, match="EU region"):
        load_csv(write_csv(tmp_path, csv))


def test_recruiter_on_company_domain_rejected(tmp_path: Path) -> None:
    csv = """\
        record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role
        company,acme-demo,Acme Corp,yourdemo.com,medium,alice@acme-demo.yourdemo.com,,,,
        employee,acme-demo,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,admin
    """
    with pytest.raises(ValueError, match="external"):
        load_csv(write_csv(tmp_path, csv))


def test_no_admin_rejected(tmp_path: Path) -> None:
    csv = """\
        record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role
        company,acme-demo,Acme Corp,yourdemo.com,medium,alice@recruiter.com,,,,
        employee,acme-demo,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,employee
    """
    with pytest.raises(ValueError, match="admin"):
        load_csv(write_csv(tmp_path, csv))


def test_company_id_mismatch_rejected(tmp_path: Path) -> None:
    csv = """\
        record_type,company_id,company_name,root_domain,node_size,recruiter_email,email,first_name,last_name,role
        company,acme-demo,Acme Corp,yourdemo.com,medium,alice@recruiter.com,,,,
        employee,other-company,,,,,bob@acme-demo.yourdemo.com,Bob,Smith,admin
    """
    with pytest.raises(ValueError, match="company_id"):
        load_csv(write_csv(tmp_path, csv))


def test_example_csv_valid() -> None:
    """The committed example CSV must always be valid."""
    example = Path(__file__).parents[2] / "docs" / "csv" / "example.csv"
    spec = load_csv(example)
    assert spec.company.company_id == "acme-demo"
    assert len(spec.employees) == 3
