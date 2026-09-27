"""Explicit operator entry point for mounted artifact-storage root ownership."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from typing import Optional

from gluetool import GlueError

from tests.artifacts.helpers import ArtifactsConfig, initialize_storage_root, run_admin_ssh_command
from tests.artifacts.initialization_config import configuration_from_deployment


def main(argv: Optional[list[str]] = None) -> None:
    """Initialize the mounted root using approved deployment inputs.

    :param argv: Command-line arguments; defaults to the process arguments.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--apply", action="store_true",
        help="Authorize nonrecursive ownership initialization of the verified mounted root",
    )
    mode.add_argument("--check", action="store_true", help="Resolve inputs only; no SSH connection or ownership change")
    parser.add_argument("--deployment", type=Path, help="Applied Terragrunt stack supplying storage and EC2 outputs")
    parser.add_argument("--aws-profile", default=os.environ.get("ARTIFACTS_AWS_PROFILE"),
                        help="Approved AWS profile for read-only EC2 host-key/identity discovery")
    args = parser.parse_args(argv)
    defaults = ArtifactsConfig()
    try:
        config = ArtifactsConfig(
            host=os.environ.get("ARTIFACTS_HOST", defaults.host),
            ssh_port=int(os.environ.get("ARTIFACTS_SSH_PORT", str(defaults.ssh_port))),
            admin_user=os.environ.get("ARTIFACTS_ADMIN_USER", defaults.admin_user),
            admin_key_path=os.environ.get("ARTIFACTS_ADMIN_KEY"),
            known_hosts_path=os.environ.get("ARTIFACTS_KNOWN_HOSTS"),
            upload_user=os.environ.get("ARTIFACTS_UPLOAD_USER", defaults.upload_user),
            mount_point=os.environ.get("ARTIFACTS_MOUNT_POINT", defaults.mount_point),
            filesystem_id=os.environ.get("ARTIFACTS_FILESYSTEM_ID"),
            mount_target_ip=os.environ.get("ARTIFACTS_MOUNT_TARGET_IP"),
            artifact_dir=os.environ.get("ARTIFACTS_ARTIFACT_DIR", defaults.artifact_dir),
        )
        if args.deployment:
            config = configuration_from_deployment(
                config, args.deployment, args.aws_profile, host=os.environ.get("ARTIFACTS_HOST"),
                ssh_port=int(os.environ["ARTIFACTS_SSH_PORT"]) if "ARTIFACTS_SSH_PORT" in os.environ else None,
            )
        if args.check:
            if not all((config.admin_key_path, config.known_hosts_path, config.filesystem_id, config.mount_target_ip)):
                raise GlueError("Check requires --deployment or explicit administrator, verified host-key and backend inputs")
            print(json.dumps({"host": config.host, "ssh_port": config.ssh_port, "admin_user": config.admin_user,
                              "admin_key": config.admin_key_path, "known_hosts": config.known_hosts_path,
                              "filesystem_id": config.filesystem_id, "mount_target_ip": config.mount_target_ip,
                              "diagnostics": config.artifact_dir, "ownership_changed": False}, indent=2))
            return
        if args.deployment:
            print(f"Initialization diagnostics: {config.artifact_dir}", file=sys.stderr)
            connection = run_admin_ssh_command(config, "true", log_dir=Path(config.artifact_dir), log_prefix="initialize-connect")
            if connection.exit_code or connection.timed_out:
                raise GlueError(f"Administrator SSH failed for {config.admin_user}@{config.host}:{config.ssh_port}: "
                                f"{connection.stderr.strip()}. Check direct RH VPN access, frontend TCP 22 ingress "
                                f"and the administrator identity. No ownership change was attempted; "
                                f"inspect diagnostics in {config.artifact_dir}")
        result = initialize_storage_root(config, log_dir=Path(config.artifact_dir))
    except (GlueError, ValueError, OSError) as exc:
        parser.exit(1, f"Cannot initialize artifact storage: {exc}\n")
    print(result.stdout, end="")


if __name__ == "__main__":
    main()
