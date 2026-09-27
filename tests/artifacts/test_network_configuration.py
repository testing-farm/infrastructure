"""Keep artifact frontend access aligned with the existing RH private-network model."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
DEPLOYMENT = ROOT / "terragrunt/environments/production/artifacts-redhat"


def test_frontend_allows_direct_private_network_access() -> None:
    """Admit routed administrators/readers as well as workers, on only the frontend ports."""
    source = (DEPLOYMENT / "security-group/terragrunt.hcl").read_text()
    rules = re.search(r"^\s*ingress_rules\s*=\s*\[([^]]*)\]", source, re.MULTILINE)
    assert rules is not None, "Use direct frontend ingress rather than worker-only source-group membership"
    assert set(re.findall(r'"([^"]+)"', rules.group(1))) == {"ssh-tcp", "http-80-tcp", "https-443-tcp"}
    cidrs = re.search(r"^\s*ingress_cidr_blocks\s*=\s*\[([^]]*)\]", source, re.MULTILINE)
    assert cidrs is not None
    assert re.findall(r'"([^"]+)"', cidrs.group(1)) == ["0.0.0.0/0"]
    assert "ingress_with_source_security_group_id" not in source
    assert "ingress_ipv6_cidr_blocks" not in source


def test_frontend_instance_remains_private() -> None:
    """The broad IPv4 source rule relies on private routing, not an Internet-facing instance."""
    source = (DEPLOYMENT / "ec2/terragrunt.hcl").read_text()
    assert re.search(r"^\s*associate_public_ip_address\s*=\s*false\s*$", source, re.MULTILINE)


def test_runbook_does_not_require_a_worker_jump() -> None:
    """The runbook describes the intended direct access, not an administrative workaround."""
    source = (DEPLOYMENT / "README.adoc").read_text()
    assert "ProxyJump" not in source
    assert "jump worker" not in source
    assert "current frontend SG permits worker-SG sources only" not in source
    assert "0.0.0.0/0" in source
