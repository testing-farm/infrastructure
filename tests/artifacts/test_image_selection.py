"""Configuration contract for selecting released artifact-server AMIs, never MR uploads."""

import json
from pathlib import Path
import re

import pytest


ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def release_name_regex() -> str:
    """Read the reviewed production release selector from its Terragrunt configuration."""
    leaf = ROOT / "terragrunt/environments/production/artifacts-redhat/ec2/terragrunt.hcl"
    match = re.search(r'^\s*ami_name_regex\s*=\s*("[^"]+")\s*$', leaf.read_text(), re.MULTILINE)
    assert match is not None, "Production must configure an explicit release-only AMI selector"
    return str(json.loads(match.group(1)))


@pytest.mark.parametrize(
    ("name", "released"),
    [
        ("artifacts-bootc-x86_64-624c430c", True),
        ("artifacts-bootc-x86_64-abcdef01", True),
        ("artifacts-bootc-x86_64-mr-1608-12345678", False),
        ("artifacts-bootc-x86_64-mr-1608-abcdef01", False),
        ("artifacts-bootc-x86_64-diagnostic-624c430c", False),
        ("artifacts-bootc-x86_64-624c430", False),
        ("artifacts-bootc-x86_64-zzzzzzzz", False),
        ("artifacts-bootc-x86_64-624c430c-extra", False),
        ("artifacts-bootc-aarch64-624c430c", False),
    ],
)
def test_production_name_matches_only_ci_releases(release_name_regex: str, name: str, released: bool) -> None:
    """Default-branch short-SHA names pass; MR and diagnostic names never do."""
    assert bool(re.search(release_name_regex, name)) is released


def test_ami_lookup_applies_the_release_selector() -> None:
    """Keep the release-only configuration connected to the actual aws_ami lookup."""
    module = ROOT / "terragrunt/modules/artifacts-server/main.tf"
    assert re.search(r'^\s*name_regex\s*=\s*var\.ami_name_regex\s*$', module.read_text(), re.MULTILINE)
