"""Resolve deployed storage/EC2 outputs and independently verified administrator SSH inputs."""

from __future__ import annotations

import base64
import dataclasses
import json
from pathlib import Path
import re
import tempfile
from typing import Any, Optional

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from gluetool import GlueError

from tests.artifacts.helpers import ArtifactsConfig, run_command


def _output(deployment: Path, unit: str, log_dir: Path) -> dict[str, Any]:
    """Read applied outputs, retaining complete Terragrunt diagnostics.

    :param deployment: Terragrunt stack directory.
    :param unit: Unit within the stack.
    :param log_dir: Protected diagnostic directory.
    :returns: Terraform output envelopes, not planned/mock values.
    """
    result = run_command(
        ["terragrunt", "output", "-json", "--terragrunt-working-dir", str(deployment / unit)],
        timeout=60, log_dir=log_dir, log_prefix=f"deployment-{unit}",
    )
    if result.exit_code or result.timed_out:
        raise GlueError(f"Cannot read deployed {unit} outputs; check the completed apply and Terraform credentials. "
                        f"Inspect diagnostics in {log_dir}")
    try:
        outputs = json.loads(result.stdout)
    except ValueError as exc:
        raise GlueError(f"Invalid {unit} output JSON; inspect diagnostics in {log_dir}") from exc
    if not isinstance(outputs, dict):
        raise GlueError(f"Invalid {unit} outputs; expected a Terraform output mapping")
    return outputs


def _value(outputs: dict[str, Any], name: str) -> str:
    """Require a nonempty applied string output before discovering SSH credentials."""
    output = outputs.get(name)
    value = output.get("value") if isinstance(output, dict) else None
    if not isinstance(value, str) or not value:
        raise GlueError(f"Deployment output {name!r} is missing; finish applying the storage and EC2 units first")
    return value


def _administrator_key(public_key: str, identities: list[str]) -> str:
    """Match public files to the EC2 key pair without reading or copying private contents."""
    expected = public_key.split()[:2]
    if len(expected) != 2:
        raise GlueError("EC2 did not return an administrator public key; set ARTIFACTS_ADMIN_KEY explicitly")
    candidates = [Path(name).expanduser() for name in identities]
    candidates.extend(path.with_suffix("") for path in sorted((Path.home() / ".ssh").glob("*.pub")))
    for candidate in candidates:
        public = Path(str(candidate) + ".pub")
        try:
            if candidate.is_file() and public.read_text().split()[:2] == expected:
                return str(candidate)
        except (OSError, UnicodeError):
            continue
    raise GlueError("Cannot find a local administrator identity matching the deployed EC2 key pair. "
                    "Set ARTIFACTS_ADMIN_KEY to its private-key path; no private key is copied to the server")


def _known_hosts(console: str, hosts: list[str], port: int, log_dir: Path, alias: Optional[str]) -> str:
    """Use only public host keys from the authenticated instance-console block, never keyscan."""
    if "-----BEGIN SSH HOST KEY KEYS-----" not in console:
        try:
            console = base64.b64decode(console, validate=True).decode("utf-8")
        except (ValueError, UnicodeError):
            raise GlueError("Cannot decode EC2 host-key evidence; supply independently verified ARTIFACTS_KNOWN_HOSTS") from None
    block = re.search(r"-----BEGIN SSH HOST KEY KEYS-----(.*?)-----END SSH HOST KEY KEYS-----", console, re.DOTALL)
    keys = re.findall(r"(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^\s]+)\s+([A-Za-z0-9+/=]+)", block.group(1)) if block else []
    if not keys:
        raise GlueError("EC2 console has no public host-key block; supply independently verified ARTIFACTS_KNOWN_HOSTS. "
                        "Unverified ssh-keyscan output is not accepted")
    names = {f"[{host}]:{port}" if port != 22 else host for host in hosts}
    if alias and alias != "none":
        names.add(alias)
    path = log_dir / "verified-known-hosts"
    path.write_text("".join(f"{','.join(sorted(names))} {kind} {key}\n" for kind, key in keys))
    path.chmod(0o600)
    return str(path)


def configuration_from_deployment(
    config: ArtifactsConfig, deployment: Path, aws_profile: Optional[str], *,
    host: Optional[str] = None, ssh_port: Optional[int] = None,
) -> ArtifactsConfig:
    """Resolve applied outputs, local admin identity and console-attested host keys without SSH access.

    :param config: Operator overrides and existing initializer defaults.
    :param deployment: Applied Terragrunt stack directory.
    :param aws_profile: Approved profile for read-only EC2 identity discovery.
    :param host: Optional existing SSH alias or forwarded endpoint, otherwise the deployed private IP.
    :param ssh_port: Explicit port override, otherwise use the SSH client's configured port.
    :returns: Complete initializer configuration with protected per-run diagnostics.
    :raises GlueError: If outputs, account/instance identity or SSH trust cannot be established.
    """
    parent = Path(config.artifact_dir).expanduser()
    parent.mkdir(parents=True, exist_ok=True)
    log_dir = Path(tempfile.mkdtemp(prefix="initialize-storage-", dir=parent))
    deployment = deployment.expanduser().resolve()
    storage = _output(deployment, "storage", log_dir)
    ec2 = _output(deployment, "ec2", log_dir)
    filesystem = _value(storage, "file_system_id")
    mount_ip = _value(storage, "mount_target_ipv4_address")
    for label, supplied, deployed in (("ARTIFACTS_FILESYSTEM_ID", config.filesystem_id, filesystem),
                                     ("ARTIFACTS_MOUNT_TARGET_IP", config.mount_target_ip, mount_ip)):
        if supplied and supplied != deployed:
            raise GlueError(f"{label} disagrees with deployed outputs; remove the stale override before initialization")
    instance_id, private_ip, arn = (_value(ec2, name) for name in ("id", "private_ip", "arn"))
    parts = arn.split(":")
    if len(parts) != 6 or parts[2] != "ec2" or parts[5] != f"instance/{instance_id}":
        raise GlueError("Deployed EC2 ARN and instance ID disagree; refresh the deployment outputs")
    config = dataclasses.replace(config, host=host or private_ip, private_ip=private_ip,
                                 filesystem_id=filesystem, mount_target_ip=mount_ip, artifact_dir=str(log_dir))
    ssh = run_command(["ssh", "-G", "-l", config.admin_user, config.host], timeout=10)
    if ssh.exit_code or ssh.timed_out:
        raise GlueError("Cannot read local SSH configuration; check ssh -G for ARTIFACTS_HOST")
    settings: dict[str, str] = {}
    identities = []
    for line in ssh.stdout.splitlines():
        name, separator, value = line.partition(" ")
        if separator:
            if name == "identityfile":
                identities.append(value)
            else:
                settings[name] = value
    config = dataclasses.replace(config, ssh_port=ssh_port if ssh_port is not None else int(settings.get("port", "22")))
    key, known = config.admin_key_path, config.known_hosts_path
    try:
        if not key or not known:
            session = boto3.Session(profile_name=aws_profile, region_name=parts[3])
            options = Config(connect_timeout=5, read_timeout=20, retries={"total_max_attempts": 1})
            if session.client("sts", config=options).get_caller_identity()["Account"] != parts[4]:
                raise GlueError("AWS profile account differs from the deployed EC2 account; select ARTIFACTS_AWS_PROFILE")
            client = session.client("ec2", config=options)
            reservations = client.describe_instances(InstanceIds=[instance_id])["Reservations"]
            instances = [instance for reservation in reservations for instance in reservation["Instances"]]
            if len(instances) != 1 or instances[0].get("PrivateIpAddress") != private_ip:
                raise GlueError("Deployed instance identity/private IP changed; refresh the deployment outputs")
            if not key:
                pair = client.describe_key_pairs(KeyNames=[instances[0]["KeyName"]], IncludePublicKey=True)["KeyPairs"][0]
                key = _administrator_key(pair["PublicKey"], identities)
            if not known:
                console = client.get_console_output(InstanceId=instance_id).get("Output", "")
                hosts = [config.host, private_ip, settings.get("hostname", config.host)]
                known = _known_hosts(console, hosts, config.ssh_port, log_dir, settings.get("hostkeyalias"))
    except ClientError as exc:
        raise GlueError(f"AWS SSH input discovery failed ({exc.operation_name}: {exc.response['Error']['Code']}). "
                        "Check ARTIFACTS_AWS_PROFILE and EC2 read permissions, or supply verified admin/known-hosts paths") from None
    except BotoCoreError as exc:
        raise GlueError(f"AWS SSH input discovery failed ({type(exc).__name__}); check ARTIFACTS_AWS_PROFILE and credentials") from None
    except (KeyError, IndexError) as exc:
        raise GlueError(f"EC2 identity response is incomplete ({type(exc).__name__}); supply verified admin/known-hosts paths") from None
    assert key and known
    for variable, path in (("ARTIFACTS_ADMIN_KEY", key), ("ARTIFACTS_KNOWN_HOSTS", known)):
        if not Path(path).expanduser().is_file():
            raise GlueError(f"{variable} file does not exist: {path}")
    return dataclasses.replace(config, admin_key_path=str(Path(key).expanduser()),
                               known_hosts_path=str(Path(known).expanduser()))
