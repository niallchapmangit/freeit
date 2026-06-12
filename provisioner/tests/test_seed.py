"""Tests for the seed data generator."""

from __future__ import annotations

from datetime import date

from provisioner.schema import load_csv
from provisioner.seed.spec import build_seed_bundle, _next_monday, _next_tuesday
from provisioner.seed.renderer import render

import textwrap
from pathlib import Path


def _load_example() -> object:
    example = Path(__file__).parents[2] / "docs" / "csv" / "example.csv"
    return load_csv(example)


def test_bundle_has_files():
    spec = _load_example()
    bundle = build_seed_bundle(spec, today=date(2026, 6, 12))
    assert len(bundle.files) > 0


def test_onboarding_files_per_target():
    spec = _load_example()
    onboarding_targets = [e for e in spec.employees if e.is_onboarding_target]
    bundle = build_seed_bundle(spec, today=date(2026, 6, 12))
    # Each target gets Welcome.md + Team_Directory.md; plus one shared handbook
    assert len(bundle.files) == len(onboarding_targets) * 2 + 1


def test_welcome_doc_renders_name():
    spec = _load_example()
    bundle = build_seed_bundle(spec, today=date(2026, 6, 12))
    welcome_files = [f for f in bundle.files if "Welcome.md" in f.webdav_path]
    assert len(welcome_files) == 1
    assert "Bob" in welcome_files[0].content


def test_team_directory_lists_all_employees():
    spec = _load_example()
    bundle = build_seed_bundle(spec, today=date(2026, 6, 12))
    dir_files = [f for f in bundle.files if "Team_Directory" in f.webdav_path]
    assert len(dir_files) == 1
    content = dir_files[0].content
    for emp in spec.employees:
        assert emp.first_name in content


def test_handbook_mentions_company_name():
    spec = _load_example()
    bundle = build_seed_bundle(spec, today=date(2026, 6, 12))
    handbook = next(f for f in bundle.files if "Handbook" in f.webdav_path)
    assert spec.company.company_name in handbook.content


def test_mail_artefacts_per_onboarding_target():
    spec = _load_example()
    bundle = build_seed_bundle(spec, today=date(2026, 6, 12))
    targets = [e for e in spec.employees if e.is_onboarding_target]
    assert len(bundle.mails) == len(targets)


def test_calendar_has_all_hands():
    spec = _load_example()
    bundle = build_seed_bundle(spec, today=date(2026, 6, 12))
    all_hands = [c for c in bundle.calendars if "All-Hands" in c.summary]
    assert len(all_hands) >= 1


def test_next_monday_is_monday():
    d = _next_monday(date(2026, 6, 12))  # Friday
    assert d.weekday() == 0  # Monday


def test_next_tuesday_is_tuesday():
    d = _next_tuesday(date(2026, 6, 12))  # Friday
    assert d.weekday() == 1  # Tuesday


def test_welcome_email_text_renders():
    spec = _load_example()
    emp = next(e for e in spec.employees if e.is_onboarding_target)
    content = render(
        "welcome_email.txt.j2",
        company=spec.company,
        employee=emp,
        manager=None,
        today=date(2026, 6, 12),
    )
    assert spec.company.company_name in content
    assert emp.first_name in content


def test_welcome_email_html_renders():
    spec = _load_example()
    emp = next(e for e in spec.employees if e.is_onboarding_target)
    content = render(
        "welcome_email.html.j2",
        company=spec.company,
        employee=emp,
        manager=None,
        today=date(2026, 6, 12),
    )
    assert "<!DOCTYPE html>" in content
    assert emp.first_name in content
