"""Jinja2 template renderer for seed data artefacts."""

from __future__ import annotations

from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

_TEMPLATE_DIR = Path(__file__).parent / "templates"

_env = Environment(
    loader=FileSystemLoader(str(_TEMPLATE_DIR)),
    undefined=StrictUndefined,
    trim_blocks=True,
    lstrip_blocks=True,
    autoescape=False,   # Markdown output — HTML escaping would break it
)


def render(template_name: str, **context: object) -> str:
    """Render a template by name with the given context."""
    return _env.get_template(template_name).render(**context)
