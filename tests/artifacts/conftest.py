"""Pytest configuration and fixtures for Testing Farm artifact server lifecheck."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import tempfile
import time
from typing import Generator

import pytest

from tests.artifacts.helpers import (
    ArtifactsConfig,
    ProbePayload,
    cleanup_probe,
    create_probe,
)


def pytest_addoption(parser: pytest.Parser) -> None:
    """Register custom command-line options for artifact server lifecheck."""
    group = parser.getgroup("artifacts", "Testing Farm Artifact Server Lifecheck")
    group.addoption(
        "--live-artifacts",
        action="store_true",
        default=False,
        help="Execute live lifecheck tests against deployed infrastructure. "
             "When omitted, live infrastructure tests are skipped.",
    )
    group.addoption(
        "--artifacts-host",
        action="store",
        default=os.environ.get("ARTIFACTS_HOST", "redhat.artifacts.testing.farm"),
        help="Artifact server hostname or IP address (default: redhat.artifacts.testing.farm)",
    )
    group.addoption(
        "--artifacts-private-ip",
        action="store",
        default=os.environ.get("ARTIFACTS_PRIVATE_IP"),
        help="Expected private IP of the artifact server instance",
    )
    group.addoption(
        "--artifacts-http-port",
        action="store",
        type=int,
        default=int(os.environ.get("ARTIFACTS_HTTP_PORT", "80")),
        help="HTTP port (default: 80)",
    )
    group.addoption(
        "--artifacts-https-port",
        action="store",
        type=int,
        default=int(os.environ.get("ARTIFACTS_HTTPS_PORT", "443")),
        help="HTTPS port (default: 443)",
    )
    group.addoption(
        "--artifacts-ssh-port",
        action="store",
        type=int,
        default=int(os.environ.get("ARTIFACTS_SSH_PORT", "22")),
        help="SSH port (default: 22)",
    )
    group.addoption(
        "--artifacts-upload-user",
        action="store",
        default=os.environ.get("ARTIFACTS_UPLOAD_USER", "artifacts"),
        help="Restricted SSH upload user (default: artifacts)",
    )
    group.addoption(
        "--artifacts-upload-key",
        action="store",
        default=os.environ.get("ARTIFACTS_UPLOAD_KEY"),
        help="Path to private SSH key for upload user",
    )
    group.addoption(
        "--artifacts-admin-user",
        action="store",
        default=os.environ.get("ARTIFACTS_ADMIN_USER", "fedora"),
        help="Administrative SSH user (default: fedora)",
    )
    group.addoption(
        "--artifacts-admin-key",
        action="store",
        default=os.environ.get("ARTIFACTS_ADMIN_KEY"),
        help="Path to private SSH key for admin user",
    )
    group.addoption(
        "--artifacts-ca-cert",
        action="store",
        default=os.environ.get("ARTIFACTS_CA_CERT"),
        help="Path to custom CA certificate for TLS verification",
    )
    group.addoption(
        "--artifacts-mount-point",
        action="store",
        default=os.environ.get("ARTIFACTS_MOUNT_POINT", "/mnt/s3files"),
        help="Mount point of S3 Files on the artifact server (default: /mnt/s3files)",
    )
    group.addoption(
        "--artifacts-allow-reboot",
        action="store_true",
        default=os.environ.get("ARTIFACTS_ALLOW_REBOOT", "false").lower() in ("true", "1", "yes"),
        help="Explicitly opt in to reboot test. When false, reboot tests are skipped.",
    )
    group.addoption(
        "--artifacts-artifact-dir",
        action="store",
        default=os.environ.get("ARTIFACTS_ARTIFACT_DIR", f".pytest/artifacts-{int(time.time())}"),
        help="Directory to store diagnostic logs and test reports",
    )


@pytest.fixture(scope="session")
def artifacts_config(request: pytest.FixtureRequest) -> ArtifactsConfig:
    """Fixture providing initialized ArtifactsConfig from CLI arguments.

    :param request: Pytest request fixture.
    :returns: ArtifactsConfig object.
    """
    return ArtifactsConfig(
        host=request.config.getoption("--artifacts-host"),
        private_ip=request.config.getoption("--artifacts-private-ip"),
        http_port=request.config.getoption("--artifacts-http-port"),
        https_port=request.config.getoption("--artifacts-https-port"),
        ssh_port=request.config.getoption("--artifacts-ssh-port"),
        upload_user=request.config.getoption("--artifacts-upload-user"),
        upload_key_path=request.config.getoption("--artifacts-upload-key"),
        admin_user=request.config.getoption("--artifacts-admin-user"),
        admin_key_path=request.config.getoption("--artifacts-admin-key"),
        ca_cert_path=request.config.getoption("--artifacts-ca-cert"),
        mount_point=request.config.getoption("--artifacts-mount-point"),
        allow_reboot=request.config.getoption("--artifacts-allow-reboot"),
        is_live=request.config.getoption("--live-artifacts"),
        artifact_dir=request.config.getoption("--artifacts-artifact-dir"),
    )


@pytest.fixture(scope="session")
def artifact_dir(artifacts_config: ArtifactsConfig) -> Path:
    """Fixture providing a unique per-run directory for logs and artifacts.

    :param artifacts_config: ArtifactsConfig instance.
    :returns: Path to artifact directory.
    """
    path = Path(artifacts_config.artifact_dir)
    path.mkdir(parents=True, exist_ok=True)
    return path


@pytest.fixture
def probe_workspace(artifact_dir: Path) -> Generator[tuple[ProbePayload, Path], None, None]:
    """Fixture that generates a unique test probe in a local temporary workspace.

    :param artifact_dir: Artifact log directory.
    :returns: Tuple of (ProbePayload, temp_dir Path).
    """
    temp_dir = Path(tempfile.mkdtemp(prefix="tft-probe-", dir=artifact_dir))
    probe = create_probe(base_dir=temp_dir)
    try:
        yield probe, temp_dir
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
