"""Offline checks of live lifecheck outcomes at the transport boundary."""

from io import BytesIO
from pathlib import Path
import shlex
import subprocess
from types import SimpleNamespace
from unittest.mock import patch

import boto3
from botocore.response import StreamingBody
from botocore.stub import Stubber
from gluetool import GlueError
import pytest

from tests.artifacts.helpers import ArtifactsConfig, create_probe
from tests.artifacts.test_lifecheck import (
    test_probe_upload_and_readback as run_upload_lifecheck,
    test_reboot_and_persistence as run_reboot_lifecheck,
)


@pytest.mark.parametrize("reboot", [False, True])
def test_partial_upload_is_cleaned_up(tmp_path: Path, reboot: bool) -> None:
    """An interrupted transfer still cleans the owned remote probe prefix."""
    config = ArtifactsConfig(
        allow_reboot=reboot,
        s3_bucket="artifact-test-bucket",
        filesystem_id="fs-0963344dcd0f605ed",
        mount_target_ip="10.31.10.250",
    )
    probe = create_probe(base_dir=tmp_path)
    remote_files: set[str] = set()

    def transport(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if command[0] == "rsync":
            remote_files.add(probe.relative_dir)
            return subprocess.CompletedProcess(command, 23, stdout="", stderr="partial transfer")
        if "rm -rf" in command[-1]:
            remote_files.discard(probe.relative_dir)
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
        raise AssertionError(f"Unexpected transport operation: {command[0]}")

    lifecheck = run_reboot_lifecheck if reboot else run_upload_lifecheck
    with patch("subprocess.run", side_effect=transport):
        with pytest.raises(AssertionError, match="upload failed"):
            lifecheck(config, (probe, tmp_path), tmp_path)

    assert not remote_files


def test_post_reboot_partial_upload_cleans_both_probes(tmp_path: Path) -> None:
    """Both probe prefixes are removed when the second, post-reboot transfer fails."""
    config = ArtifactsConfig(
        allow_reboot=True,
        s3_bucket="artifact-test-bucket",
        filesystem_id="fs-0963344dcd0f605ed",
        mount_target_ip="10.31.10.250",
    )
    probe = create_probe(base_dir=tmp_path)
    remote_files: set[str] = set()
    boot_reads = 0
    uploads = 0

    def transport(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        nonlocal boot_reads, uploads
        stdout = ""
        if command[0] == "rsync":
            remote_files.add(str(Path(command[-2]).parent))
            uploads += 1
            return subprocess.CompletedProcess(command, 0 if uploads == 1 else 23, stdout="", stderr="partial transfer")
        remote = command[-1]
        if "rm -rf" in remote:
            relative = Path(shlex.split(remote)[-1]).relative_to(config.mount_point)
            remote_files.discard(str(relative))
        elif "boot_id" in remote:
            boot_reads += 1
            stdout = "old-boot\n" if boot_reads == 1 else "new-boot\n"
        elif "systemctl reboot" in remote:
            pass
        elif "readlink" in remote:
            stdout = "/var/mnt/s3files\n"
        elif "findmnt --json" in remote:
            stdout = '{"filesystems": [{"target": "/var/mnt/s3files", "fstype": "nfs4"}]}'
        elif "findmnt --fstab" in remote:
            stdout = "fs-0963344dcd0f605ed:/ s3files _netdev,nofail,x-systemd.automount,mounttargetip=10.31.10.250\n"
        else:
            raise AssertionError(f"Unexpected transport operation: {command[0]}")
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    client = boto3.client("s3", region_name="us-east-1", aws_access_key_id="offline", aws_secret_access_key="offline")
    content = probe.content.encode()
    with Stubber(client) as stubber, patch("subprocess.run", side_effect=transport), patch("boto3.Session") as session:
        session.return_value.client.return_value = client
        stubber.add_response("get_object", {"Body": StreamingBody(BytesIO(content), len(content))})
        with patch("requests.get", return_value=SimpleNamespace(status_code=200, text=probe.content)):
            with pytest.raises(AssertionError, match="Post-reboot upload failed"):
                run_reboot_lifecheck(config, (probe, tmp_path), tmp_path)
        stubber.assert_no_pending_responses()

    assert uploads == 2
    assert not remote_files


def test_cleanup_failure_cannot_pass_silently(tmp_path: Path) -> None:
    """A failed remote removal is an explicit failure, even after a partial upload."""
    config = ArtifactsConfig(s3_bucket="artifact-test-bucket")
    probe = create_probe(base_dir=tmp_path)
    with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 23, stdout="", stderr="denied")):
        with pytest.raises(GlueError, match="Cannot clean owned probe"):
            run_upload_lifecheck(config, (probe, tmp_path), tmp_path)
