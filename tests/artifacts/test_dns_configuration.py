"""Plan the actual artifact DNS module offline, including first-deployment mock inputs."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[2]
DNS = ROOT / "terragrunt/environments/production/artifacts-redhat/dns"


def dns_module() -> Path:
    """Resolve the local module selected by the production DNS leaf."""
    match = re.search(r'^\s*source\s*=\s*"([^"]+)"', (DNS / "terragrunt.hcl").read_text(), re.MULTILINE)
    assert match is not None
    assert match.group(1).startswith("."), "DNS must use the local lookup-free record module"
    module = (DNS / match.group(1)).resolve()
    assert module.is_dir()
    return module


def test_dns_uses_lookup_free_module() -> None:
    """Keep the production leaf connected to a module without live zone lookups."""
    module = dns_module()
    source = "\n".join(path.read_text() for path in module.glob("*.tf"))
    assert not re.search(r'^\s*data\s+"aws_route53_zone"', source, re.MULTILINE)
    assert re.search(r'^\s*zone_id\s*=\s*var\.zone_id\s*$', source, re.MULTILINE)
    assert re.search(r'^\s*zone_name\s*=\s*"artifacts\.testing\.farm"\s*$',
                     (DNS / "terragrunt.hcl").read_text(), re.MULTILINE)


@pytest.fixture(scope="session")
def terraform_runtime() -> tuple[str, Path]:
    """Reuse installed tooling without downloading providers or contacting AWS."""
    executable = shutil.which("terraform")
    if executable is None:
        pytest.skip("Terraform is not installed")
    providers = sorted((ROOT / "terragrunt/environments/production/artifacts-redhat").rglob("terraform-provider-aws_*"))
    if not providers:
        pytest.skip("No cached AWS provider; initialize an artifacts Terragrunt unit first")
    return executable, providers[0].parents[5]


@pytest.mark.parametrize(
    ("zone_id", "private_ip"),
    [("Z0123456789ABCDEF", "10.0.0.1"), ("Z0234567890ABCDEFG", "10.31.11.42")],
)
def test_dns_plan_without_existing_zone(
    tmp_path: Path, terraform_runtime: tuple[str, Path], zone_id: str, private_ip: str,
) -> None:
    """A fresh local state must plan the record even when AWS cannot be queried."""
    module = dns_module()
    executable, provider_cache = terraform_runtime
    for source in module.glob("*.tf"):
        shutil.copyfile(source, tmp_path / source.name)
    (tmp_path / "provider.tf").write_text('''
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "offline-test"
  secret_key                  = "offline-test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  max_retries                 = 0
  endpoints {
    route53 = "http://127.0.0.1:1"
    sts     = "http://127.0.0.1:1"
    iam     = "http://127.0.0.1:1"
  }
}
''')
    (tmp_path / "terraform.tfvars.json").write_text(json.dumps({
        "zone_id": zone_id,
        "zone_name": "artifacts.testing.farm",
        "records_jsonencoded": json.dumps([{"name": "redhat", "type": "A", "ttl": 60, "records": [private_ip]}]),
    }))
    (tmp_path / "terraform.rc").write_text('disable_checkpoint = true\n')
    environment = {key: value for key, value in os.environ.items() if not key.startswith(("AWS_", "TF_"))}
    environment.update({
        "AWS_CONFIG_FILE": str(tmp_path / "no-aws-config"),
        "AWS_SHARED_CREDENTIALS_FILE": str(tmp_path / "no-aws-credentials"),
        "AWS_EC2_METADATA_DISABLED": "true",
        "TF_CLI_CONFIG_FILE": str(tmp_path / "terraform.rc"),
    })
    commands = [
        ["init", "-backend=false", "-input=false", f"-plugin-dir={provider_cache}"],
        ["plan", "-input=false", "-lock=false", "-refresh=false", "-out=plan.tfplan"],
        ["show", "-json", "plan.tfplan"],
    ]
    for arguments in commands:
        result = subprocess.run(
            [executable, f"-chdir={tmp_path}", *arguments], env=environment,
            capture_output=True, text=True, timeout=60, check=False,
        )
        (tmp_path / f"{arguments[0]}.stdout.log").write_text(result.stdout)
        (tmp_path / f"{arguments[0]}.stderr.log").write_text(result.stderr)
        assert result.returncode == 0, f"Inspect {tmp_path}:\n{result.stdout}\n{result.stderr}"
    plan = json.loads(result.stdout)
    assert all(resource["mode"] == "managed" for resource in plan["configuration"]["root_module"]["resources"])
    assert len(plan["resource_changes"]) == 1
    record = plan["resource_changes"][0]
    assert record["address"] == 'aws_route53_record.this["redhat A"]'
    assert record["change"]["actions"] == ["create"]
    values = record["change"]["after"]
    assert values["zone_id"] == zone_id
    assert values["name"] == "redhat.artifacts.testing.farm"
    assert values["type"] == "A"
    assert values["ttl"] == 60
    assert values["records"] == [private_ip]
    assert values["allow_overwrite"] is False
    assert set(plan["planned_values"]["outputs"]) == {"route53_record_name", "route53_record_fqdn"}
