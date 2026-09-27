"""Offline regressions for the self-contained storage initialization Make/CLI workflow."""

from __future__ import annotations

import base64
import dataclasses
import json
import os
from pathlib import Path
import shlex
import subprocess
from typing import Any, Generator
from unittest.mock import MagicMock, patch

from botocore.exceptions import ClientError
from gluetool import GlueError
import pytest

from tests.artifacts.helpers import ArtifactsConfig, CommandResult, _build_ssh_cmd
from tests.artifacts.initialize_storage import main
from tests.artifacts.initialization_config import configuration_from_deployment


ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def discovered_config(tmp_path: Path) -> ArtifactsConfig:
    """Represent verified inputs returned by deployment discovery, never a live host."""
    return ArtifactsConfig(host="10.0.0.2", admin_key_path="/keys/admin", known_hosts_path="/keys/verified",
                           filesystem_id="fs-test", mount_target_ip="10.0.0.8", artifact_dir=str(tmp_path))


def test_cli_discovers_inputs_before_initialization(discovered_config: ArtifactsConfig, tmp_path: Path) -> None:
    """The production entry point supplies all mandatory inputs without a sourced env file."""
    result = CommandResult([], 0, "initialized\n", "", 0)
    with patch.dict(os.environ, {}, clear=True), \
            patch("tests.artifacts.initialize_storage.configuration_from_deployment", return_value=discovered_config, create=True) as discover, \
            patch("tests.artifacts.initialize_storage.run_admin_ssh_command", return_value=result, create=True) as connect, \
            patch("tests.artifacts.initialize_storage.initialize_storage_root", return_value=result) as initialize:
        main(["--deployment", str(tmp_path), "--aws-profile", "approved", "--apply"])
    assert discover.call_args.args[1] == tmp_path
    assert discover.call_args.args[2] == "approved"
    assert connect.call_args.args[1] == "true"
    assert initialize.call_args.args[0] == discovered_config


def test_check_cannot_connect_or_change_ownership(discovered_config: ArtifactsConfig, tmp_path: Path) -> None:
    """A diagnostic target resolves deployment inputs but cannot issue remote commands."""
    with patch.dict(os.environ, {}, clear=True), \
            patch("tests.artifacts.initialize_storage.configuration_from_deployment", return_value=discovered_config, create=True), \
            patch("tests.artifacts.initialize_storage.run_admin_ssh_command", create=True) as connect, \
            patch("tests.artifacts.initialize_storage.initialize_storage_root") as initialize:
        main(["--deployment", str(tmp_path), "--check"])
    connect.assert_not_called()
    initialize.assert_not_called()


def test_connection_failure_is_not_a_missing_input_error(
    discovered_config: ArtifactsConfig, tmp_path: Path, capsys: pytest.CaptureFixture[str],
) -> None:
    """Network/authentication failure stops before ownership setup, with useful next steps."""
    result = CommandResult([], 255, "", "Connection timed out", 1)
    with patch.dict(os.environ, {}, clear=True), \
            patch("tests.artifacts.initialize_storage.configuration_from_deployment", return_value=discovered_config, create=True), \
            patch("tests.artifacts.initialize_storage.run_admin_ssh_command", return_value=result, create=True), \
            patch("tests.artifacts.initialize_storage.initialize_storage_root") as initialize:
        with pytest.raises(SystemExit) as error:
            main(["--deployment", str(tmp_path), "--apply"])
    assert error.value.code == 1
    message = capsys.readouterr().err
    assert "SSH" in message
    assert "VPN" in message and "ingress" in message
    assert "ProxyJump" not in message
    initialize.assert_not_called()


@pytest.mark.parametrize("mode", ["apply", "check"])
def test_make_target_passes_deployment_and_mode(mode: str) -> None:
    """Both targets use the deployed stack; neither relies on an external env script."""
    target = "artifacts/storage/initialize" + ("/check" if mode == "check" else "")
    result = subprocess.run(["make", "-n", "IS_MAINTAINER=1", "ARTIFACTS_AWS_PROFILE=approved", target],
                            cwd=ROOT, capture_output=True, text=True, timeout=15, check=False)
    assert result.returncode == 0, result.stderr
    arguments = shlex.split(result.stdout.strip())
    assert "--deployment" in arguments
    assert Path(arguments[arguments.index("--deployment") + 1]) == ROOT / "terragrunt/environments/production/artifacts-redhat"
    assert arguments[arguments.index("--aws-profile") + 1] == "approved"
    assert arguments[-1] == f"--{mode}"


def test_verified_host_keys_cannot_be_bypassed_by_connection_sharing() -> None:
    """Every pinned SSH command authenticates the peer, even with a configured ControlMaster."""
    command = _build_ssh_cmd(22, known_hosts_path="/verified-hosts")
    assert "ControlMaster=no" in command
    assert "ControlPath=none" in command
    assert "StrictHostKeyChecking=yes" in command


PUBLIC_KEY = "ssh-ed25519 " + base64.b64encode(
    (11).to_bytes(4, "big") + b"ssh-ed25519" + (32).to_bytes(4, "big") + bytes(range(32)),
).decode()
CONSOLE = f"-----BEGIN SSH HOST KEY KEYS-----\n{PUBLIC_KEY} host\n-----END SSH HOST KEY KEYS-----\n"


@dataclasses.dataclass
class Deployment:
    """Read-only command/API fakes plus an unreadable-by-the-test private identity."""

    config: ArtifactsConfig
    api: MagicMock
    command: MagicMock
    identity: Path


@pytest.fixture
def deployment(tmp_path: Path) -> Generator[Deployment, None, None]:
    """Model applied outputs and authenticated EC2 evidence without remote operations."""
    ssh_dir = tmp_path / ".ssh"
    ssh_dir.mkdir()
    identity = ssh_dir / "approved-admin"
    identity.write_text("Private identity contents must not be read")
    Path(str(identity) + ".pub").write_text(PUBLIC_KEY)
    outputs = {
        "storage": {"file_system_id": "fs-test", "mount_target_ipv4_address": "10.0.0.8"},
        "ec2": {"id": "i-test", "private_ip": "10.0.0.2",
                "arn": "arn:aws:ec2:us-east-1:123456789012:instance/i-test"},
    }

    def command_result(arguments: list[str], **kwargs: Any) -> CommandResult:
        if arguments[:3] == ["terragrunt", "output", "-json"]:
            unit = Path(arguments[-1]).name
            text = json.dumps({name: {"value": value} for name, value in outputs[unit].items()})
        else:
            assert arguments[:2] == ["ssh", "-G"], "Discovery must never connect to a guest"
            text = "hostname 10.0.0.2\nport 22\nidentityfile /missing/identity\n"
        return CommandResult(arguments, 0, text, "", 0)

    api = MagicMock(spec=["get_caller_identity", "describe_instances", "describe_key_pairs", "get_console_output"])
    api.get_caller_identity.return_value = {"Account": "123456789012"}
    api.describe_instances.return_value = {"Reservations": [{"Instances": [{"PrivateIpAddress": "10.0.0.2", "KeyName": "approved"}]}]}
    api.describe_key_pairs.return_value = {"KeyPairs": [{"PublicKey": PUBLIC_KEY}]}
    api.get_console_output.return_value = {"Output": CONSOLE}
    original_read = Path.read_text

    def read_public_only(path: Path, *args: Any, **kwargs: Any) -> str:
        assert path != identity, "Private key bytes must never enter discovery/logs"
        return original_read(path, *args, **kwargs)

    with patch("tests.artifacts.initialization_config.run_command", side_effect=command_result) as command, \
            patch("tests.artifacts.initialization_config.boto3.Session") as session, \
            patch.object(Path, "home", return_value=tmp_path), \
            patch.object(Path, "read_text", new=read_public_only):
        session.return_value.client.return_value = api
        yield Deployment(ArtifactsConfig(artifact_dir=str(tmp_path / "diagnostics")), api, command, identity)


@pytest.mark.parametrize("encoded_console", [False, True])
def test_deployment_supplies_all_required_inputs(deployment: Deployment, tmp_path: Path, encoded_console: bool) -> None:
    """Plain and base64 EC2 evidence produce private per-run, instance-bound known hosts."""
    if encoded_console:
        deployment.api.get_console_output.return_value = {"Output": base64.b64encode(CONSOLE.encode()).decode()}
    config = configuration_from_deployment(deployment.config, tmp_path, "approved")
    assert config.host == "10.0.0.2" and config.ssh_port == 22
    assert config.filesystem_id == "fs-test" and config.mount_target_ip == "10.0.0.8"
    assert config.admin_key_path == str(deployment.identity)
    known = Path(str(config.known_hosts_path))
    assert known.read_text() == f"10.0.0.2 {PUBLIC_KEY}\n"
    assert known.stat().st_mode & 0o777 == 0o600
    assert known.parent.stat().st_mode & 0o777 == 0o700
    deployment.api.describe_key_pairs.assert_called_once_with(KeyNames=["approved"], IncludePublicKey=True)
    deployment.api.get_console_output.assert_called_once_with(InstanceId="i-test")


def test_ssh_alias_port_and_hostkeyalias_are_retained(deployment: Deployment, tmp_path: Path) -> None:
    """An approved configured route is reused, not replaced by a new jump-host workflow."""
    old_command = deployment.command.side_effect

    def configured(arguments: list[str], **kwargs: Any) -> CommandResult:
        if arguments[:2] == ["ssh", "-G"]:
            return CommandResult(arguments, 0, "hostname 127.0.0.1\nport 2222\nhostkeyalias approved-host\n", "", 0)
        return old_command(arguments, **kwargs)

    deployment.command.side_effect = configured
    config = configuration_from_deployment(deployment.config, tmp_path, "approved", host="my-alias")
    assert config.host == "my-alias" and config.ssh_port == 2222
    hosts = Path(str(config.known_hosts_path)).read_text().split()[0].split(",")
    assert {"[127.0.0.1]:2222", "[10.0.0.2]:2222", "[my-alias]:2222", "approved-host"} == set(hosts)


def test_explicit_ssh_paths_need_no_cloud_discovery(deployment: Deployment, tmp_path: Path) -> None:
    """Explicit independently verified handoffs remain supported without EC2 console access."""
    known = tmp_path / "verified"
    known.write_text(PUBLIC_KEY)
    config = dataclasses.replace(deployment.config, admin_key_path=str(deployment.identity), known_hosts_path=str(known))
    actual = configuration_from_deployment(config, tmp_path, None, host="approved-alias", ssh_port=2022)
    assert actual.admin_key_path == str(deployment.identity) and actual.known_hosts_path == str(known)
    assert actual.host == "approved-alias" and actual.ssh_port == 2022
    deployment.api.get_caller_identity.assert_not_called()
    deployment.api.get_console_output.assert_not_called()


def test_wrong_aws_account_stops_discovery(deployment: Deployment, tmp_path: Path) -> None:
    """Credentials for another account cannot attest the deployed instance's host keys."""
    deployment.api.get_caller_identity.return_value = {"Account": "999999999999"}
    with pytest.raises(GlueError, match="account differs"):
        configuration_from_deployment(deployment.config, tmp_path, "wrong")
    deployment.api.describe_instances.assert_not_called()


def test_stale_instance_ip_stops_discovery(deployment: Deployment, tmp_path: Path) -> None:
    """A stale Terraform target cannot silently inherit another instance's trust material."""
    deployment.api.describe_instances.return_value = {"Reservations": [{"Instances": [{"PrivateIpAddress": "10.0.0.99"}]}]}
    with pytest.raises(GlueError, match="identity/private IP changed"):
        configuration_from_deployment(deployment.config, tmp_path, "approved")
    deployment.api.get_console_output.assert_not_called()


@pytest.mark.parametrize("console", ["not-base64!", "", f"authorized user: {PUBLIC_KEY}\n"])
def test_unattested_host_keys_are_rejected(deployment: Deployment, tmp_path: Path, console: str) -> None:
    """Missing host evidence never falls back to keyscan or unrelated console public keys."""
    deployment.api.get_console_output.return_value = {"Output": console}
    with pytest.raises(GlueError, match="verified ARTIFACTS_KNOWN_HOSTS"):
        configuration_from_deployment(deployment.config, tmp_path, "approved")


def test_missing_matching_admin_key_is_actionable(deployment: Deployment, tmp_path: Path) -> None:
    """Key-pair names are not mistaken for local private-key paths."""
    deployment.api.describe_key_pairs.return_value = {"KeyPairs": [{"PublicKey": "ssh-rsa other-public-key"}]}
    with pytest.raises(GlueError, match="Set ARTIFACTS_ADMIN_KEY"):
        configuration_from_deployment(deployment.config, tmp_path, "approved")
    deployment.api.get_console_output.assert_not_called()


@pytest.mark.parametrize("field", ["filesystem_id", "mount_target_ip"])
def test_stale_backend_override_is_rejected(deployment: Deployment, tmp_path: Path, field: str) -> None:
    """Old shell exports must not redirect the production target to a different filesystem."""
    config = dataclasses.replace(deployment.config, **{field: "stale"})
    with pytest.raises(GlueError, match="stale override"):
        configuration_from_deployment(config, tmp_path, "approved")
    deployment.api.get_caller_identity.assert_not_called()


@pytest.mark.parametrize("stdout", ["{}", "not-json", "[]"])
def test_missing_or_invalid_outputs_fail_closed(deployment: Deployment, tmp_path: Path, stdout: str) -> None:
    """Unapplied/malformed deployment outputs cannot fall through to SSH initialization."""
    deployment.command.side_effect = None
    deployment.command.return_value = CommandResult([], 0, stdout, "", 0)
    with pytest.raises(GlueError):
        configuration_from_deployment(deployment.config, tmp_path, "approved")
    deployment.api.get_caller_identity.assert_not_called()


def test_output_timeout_is_actionable(deployment: Deployment, tmp_path: Path) -> None:
    """A stuck Terraform/HCP read ends with diagnostic guidance, not remote commands."""
    deployment.command.side_effect = None
    deployment.command.return_value = CommandResult([], 0, "", "", 60, timed_out=True)
    with pytest.raises(GlueError, match="Cannot read deployed storage outputs"):
        configuration_from_deployment(deployment.config, tmp_path, "approved")


def test_aws_failure_does_not_expose_response_payload(deployment: Deployment, tmp_path: Path) -> None:
    """Report the failing operation/code, not potentially sensitive AWS error payloads."""
    deployment.api.describe_instances.side_effect = ClientError({"Error": {"Code": "AccessDenied", "Message": "opaque-payload"}}, "DescribeInstances")
    with pytest.raises(GlueError, match="DescribeInstances: AccessDenied") as error:
        configuration_from_deployment(deployment.config, tmp_path, "approved")
    assert "opaque-payload" not in str(error.value)
