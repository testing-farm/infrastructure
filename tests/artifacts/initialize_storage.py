"""Explicit operator entry point for mounted artifact-storage root ownership."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Optional

from gluetool import GlueError

from tests.artifacts.helpers import ArtifactsConfig, initialize_storage_root


def main(argv: Optional[list[str]] = None) -> None:
    """Initialize the mounted root using approved deployment inputs.

    :param argv: Command-line arguments; defaults to the process arguments.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", required=True,
        help="Authorize nonrecursive ownership initialization of the verified mounted root",
    )
    parser.parse_args(argv)
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
        result = initialize_storage_root(config, log_dir=Path(config.artifact_dir))
    except (GlueError, ValueError, OSError) as exc:
        parser.exit(1, f"Cannot initialize artifact storage: {exc}\n")
    print(result.stdout, end="")


if __name__ == "__main__":
    main()
