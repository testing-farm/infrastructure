"""Offline tests for explicit mounted-storage ownership initialization."""

from __future__ import annotations

import dataclasses
import os
from pathlib import Path
import shlex
import subprocess
from unittest.mock import patch

from gluetool import GlueError
import pytest

from tests.artifacts.helpers import ArtifactsConfig, CommandResult, initialize_storage_root
from tests.artifacts.initialize_storage import main


@pytest.fixture
def storage_config() -> ArtifactsConfig:
    """Supply approved backend identifiers and a separate administrator identity."""
    return ArtifactsConfig(
        admin_key_path="/keys/admin", known_hosts_path="/keys/verified-hosts",
        filesystem_id="fs-0963344dcd0f605ed", mount_target_ip="10.31.10.250",
    )


@pytest.mark.parametrize("field", ["admin_key_path", "known_hosts_path", "filesystem_id", "mount_target_ip"])
def test_initialization_requires_approved_inputs(storage_config: ArtifactsConfig, field: str) -> None:
    """Missing identity/backend inputs fail before contacting any server."""
    config = dataclasses.replace(storage_config, **{field: None})
    with patch("tests.artifacts.helpers.check_mount_status") as inspect, \
            patch("tests.artifacts.helpers.run_admin_ssh_command") as admin:
        with pytest.raises(GlueError, match="requires the admin key"):
            initialize_storage_root(config)
    inspect.assert_not_called()
    admin.assert_not_called()


@pytest.mark.parametrize(("present", "backend"), [(False, False), (True, False)])
def test_initialization_rejects_unverified_mount(
    storage_config: ArtifactsConfig, present: bool, backend: bool,
) -> None:
    """An absent mount or wrong/stale native backend cannot reach chown."""
    mount = {"mount_present": present, "expected_backend": backend, "stderr": "wrong backend"}
    with patch("tests.artifacts.helpers.check_mount_status", return_value=mount), \
            patch("tests.artifacts.helpers.run_admin_ssh_command") as admin:
        with pytest.raises(GlueError, match="expected persistent NFS backend"):
            initialize_storage_root(storage_config)
    admin.assert_not_called()


@pytest.mark.parametrize("canonical", ["", "/", "relative/path"])
def test_initialization_rejects_invalid_data_root(storage_config: ArtifactsConfig, canonical: str) -> None:
    """Never initialize the operating-system root or an unresolved path."""
    mount = {"mount_present": True, "expected_backend": True, "canonical_mount_point": canonical}
    with patch("tests.artifacts.helpers.check_mount_status", return_value=mount), \
            patch("tests.artifacts.helpers.run_admin_ssh_command") as admin:
        with pytest.raises(GlueError, match="invalid data mount"):
            initialize_storage_root(storage_config)
    admin.assert_not_called()


@pytest.mark.parametrize(
    ("guard_status", "chown_status", "uid", "denied_user", "mount_changed", "succeeds", "chown_called"),
    [(0, 0, "1234", "", False, True, True), (1, 0, "1234", "", False, False, False),
     (0, 42, "1234", "", False, False, True), (0, 0, "0", "", False, False, False),
     (0, 0, "1234", "artifacts", False, False, True), (0, 0, "1234", "nginx", False, False, True),
     (0, 0, "1234", "", True, False, False)],
)
def test_initialization_shell_contract(
    tmp_path: Path, storage_config: ArtifactsConfig, guard_status: int, chown_status: int,
    uid: str, denied_user: str, mount_changed: bool, succeeds: bool, chown_called: bool,
) -> None:
    """Run the exact remote shell with fake privilege/mount boundaries, never real sudo/chown."""
    mounted_root = tmp_path / "canonical mount's root"
    mounted_root.mkdir()
    child = mounted_root / "existing-artifact"
    child.write_text("retain existing contents and permissions")
    child.chmod(0o640)
    child_metadata = child.stat()
    tools = tmp_path / "tools"
    tools.mkdir()
    calls = tmp_path / "chown-calls"
    scripts = {
        "guard": '[ "$PWD" = "$1" ] || exit 99\nexit "$GUARD_STATUS"\n',
        "id": 'case "$1" in -u) echo "$UPLOAD_UID";; -g) echo 5678;; *) exit 98;; esac\n',
        "sudo": ('[ "$1" = -n ] || exit 97\nshift\n'
                 'if [ "$1" = -u ]; then [ "$2" != "$DENIED_USER" ] || exit 53; shift 2; fi\n'
                 'exec "$@"\n'),
        "chown": 'printf "%s\\n" "$PWD" "$@" > "$CHOWN_CALLS"\nexit "$CHOWN_STATUS"\n',
        "stat": ('if [ "$2" = %d:%i ] && [ "$3" != . ] && [ "$MOUNT_CHANGED" = 1 ]; then\n'
                 '    echo 0:0\nelse\n    exec /usr/bin/stat "$@"\nfi\n'),
    }
    for name, body in scripts.items():
        path = tools / name
        path.write_text("#!/bin/sh\nset -eu\n" + body)
        path.chmod(0o755)
    environment = {
        **os.environ, "PATH": f"{tools}:{os.environ['PATH']}", "CHOWN_CALLS": str(calls),
        "GUARD_STATUS": str(guard_status), "CHOWN_STATUS": str(chown_status), "UPLOAD_UID": uid,
        "DENIED_USER": denied_user, "MOUNT_CHANGED": str(int(mount_changed)),
    }

    def run_shell(config: ArtifactsConfig, command: str, **kwargs: object) -> CommandResult:
        command = command.replace("/usr/local/libexec/check-artifacts-mount", shlex.quote(str(tools / "guard")))
        result = subprocess.run(["bash", "-c", command], capture_output=True, text=True, env=environment, timeout=10)
        return CommandResult(command=[], exit_code=result.returncode, stdout=result.stdout,
                             stderr=result.stderr, duration_seconds=0)

    mount = {"mount_present": True, "expected_backend": True, "canonical_mount_point": str(mounted_root)}
    with patch("tests.artifacts.helpers.check_mount_status", return_value=mount), \
            patch("tests.artifacts.helpers.run_admin_ssh_command", side_effect=run_shell):
        if succeeds:
            result = initialize_storage_root(storage_config, log_dir=tmp_path)
            assert "Before:" in result.stdout and "After:" in result.stdout
        else:
            with pytest.raises(GlueError, match="Storage initialization failed"):
                initialize_storage_root(storage_config, log_dir=tmp_path)
    assert calls.exists() is chown_called
    if chown_called:
        assert calls.read_text().splitlines() == [str(mounted_root), "--no-dereference", "--", "1234:5678", "."]
    assert child.read_text() == "retain existing contents and permissions"
    assert child.stat().st_mode == child_metadata.st_mode
    assert child.stat().st_uid == child_metadata.st_uid
    assert child.stat().st_gid == child_metadata.st_gid


def test_initialization_timeout_cannot_pass(storage_config: ArtifactsConfig) -> None:
    """A timed-out remote initialization is surfaced even if an exit code looks successful."""
    mount = {"mount_present": True, "expected_backend": True, "canonical_mount_point": "/var/mnt/s3files"}
    result = CommandResult(command=[], exit_code=0, stdout="", stderr="timeout", duration_seconds=1, timed_out=True)
    with patch("tests.artifacts.helpers.check_mount_status", return_value=mount), \
            patch("tests.artifacts.helpers.run_admin_ssh_command", return_value=result):
        with pytest.raises(GlueError, match="timed out: True"):
            initialize_storage_root(storage_config)


def test_initialization_cli_requires_explicit_apply() -> None:
    """Importing/invoking the operator CLI without --apply cannot mutate storage."""
    with patch("tests.artifacts.initialize_storage.initialize_storage_root") as initialize:
        with pytest.raises(SystemExit) as error:
            main([])
    assert error.value.code == 2
    initialize.assert_not_called()


def test_initialization_cli_uses_deployment_inputs(tmp_path: Path) -> None:
    """Use existing ARTIFACTS_* handoff variables and retain complete diagnostics."""
    environment = {
        "ARTIFACTS_HOST": "approved-host", "ARTIFACTS_SSH_PORT": "2222",
        "ARTIFACTS_ADMIN_USER": "cloud-user", "ARTIFACTS_ADMIN_KEY": "/keys/admin",
        "ARTIFACTS_KNOWN_HOSTS": "/keys/verified", "ARTIFACTS_UPLOAD_USER": "uploader",
        "ARTIFACTS_MOUNT_POINT": "/mnt/s3files", "ARTIFACTS_FILESYSTEM_ID": "fs-12345678",
        "ARTIFACTS_MOUNT_TARGET_IP": "10.0.0.8", "ARTIFACTS_ARTIFACT_DIR": str(tmp_path),
    }
    result = CommandResult(command=[], exit_code=0, stdout="initialized\n", stderr="", duration_seconds=0)
    with patch.dict(os.environ, environment, clear=True), \
            patch("tests.artifacts.initialize_storage.initialize_storage_root", return_value=result) as initialize:
        main(["--apply"])
    config = initialize.call_args.args[0]
    assert config.host == "approved-host" and config.ssh_port == 2222
    assert config.admin_key_path == "/keys/admin" and config.known_hosts_path == "/keys/verified"
    assert config.upload_user == "uploader" and config.mount_point == "/mnt/s3files"
    assert config.filesystem_id == "fs-12345678" and config.mount_target_ip == "10.0.0.8"
    assert initialize.call_args.kwargs["log_dir"] == tmp_path


def test_initialization_cli_reports_failures() -> None:
    """The operator command exits unsuccessfully on a rejected backend or failed operation."""
    with patch("tests.artifacts.initialize_storage.initialize_storage_root", side_effect=GlueError("wrong backend")):
        with pytest.raises(SystemExit) as error:
            main(["--apply"])
    assert error.value.code == 1
