"""Unit and offline tests for artifact server lifecheck helpers."""

from __future__ import annotations

import itertools
import json
from pathlib import Path
import shutil
import ssl
import subprocess
import time
from unittest.mock import MagicMock, patch

import pytest
import requests

from tests.artifacts.helpers import (
    ArtifactsConfig,
    CommandResult,
    ProbePayload,
    check_autoindex,
    check_cors_headers,
    check_http_redirect,
    check_https_tls,
    check_mount_status,
    check_restricted_ssh_access,
    check_rsync_write_only,
    cleanup_probe,
    create_probe,
    fetch_probe_https,
    get_boot_id,
    reboot_and_wait,
    resolve_dns,
    run_admin_ssh_command,
    run_command,
    sanitize_command,
    upload_probe_rsync,
)


def test_sanitize_command() -> None:
    """Test that sensitive arguments like SSH keys and passwords are redacted."""
    cmd = ["ssh", "-i", "/secret/id_rsa", "-p", "22", "user@host", "echo", "hi"]
    sanitized = sanitize_command(cmd)
    assert sanitized == ["ssh", "-i", "[REDACTED]", "-p", "22", "user@host", "echo", "hi"]


def test_probe_creation(tmp_path: Path) -> None:
    """Test unique probe payload generation and local file creation."""
    probe = create_probe(namespace="probe-test", base_dir=tmp_path)
    assert probe.probe_id
    assert probe.relative_dir.startswith("probe-test/probe-")
    assert probe.filename == "probe.txt"
    assert "Testing Farm Artifact Server Lifecheck Probe" in probe.content
    assert probe.local_path is not None
    assert probe.local_path.exists()
    assert probe.local_path.read_text(encoding="utf-8") == probe.content


def test_run_command_success(tmp_path: Path) -> None:
    """Test running a command successfully with cwd and log artifact capture."""
    log_dir = tmp_path / "logs"
    sub_dir = tmp_path / "sub"
    sub_dir.mkdir()
    res = run_command(["pwd"], timeout=5.0, cwd=sub_dir, log_dir=log_dir, log_prefix="test-pwd")
    assert res.exit_code == 0
    assert str(sub_dir) in res.stdout
    assert not res.timed_out
    assert res.duration_seconds >= 0.0

    # Verify log artifact written
    log_files = list(log_dir.glob("test-pwd-*.log"))
    assert len(log_files) == 1
    content = log_files[0].read_text(encoding="utf-8")
    assert str(sub_dir) in content


def test_run_command_timeout(tmp_path: Path) -> None:
    """Test command timeout handling."""
    log_dir = tmp_path / "logs"
    with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd=["sleep", "10"], timeout=0.1, stderr=b"timeout")):
        res = run_command(["sleep", "10"], timeout=0.1, log_dir=log_dir, log_prefix="test-timeout")
        assert res.timed_out
        assert res.exit_code == -1
        assert "timeout" in res.stderr


def test_resolve_dns_mocked() -> None:
    """Test DNS resolution helper with mocked socket."""
    fake_addrinfo = [(2, 1, 6, "", ("10.0.1.50", 0))]
    with patch("socket.getaddrinfo", return_value=fake_addrinfo):
        ips = resolve_dns("redhat.artifacts.testing.farm")
        assert ips == ["10.0.1.50"]


def test_check_http_redirect_success() -> None:
    """Test HTTP to HTTPS redirect helper when redirect is valid."""
    mock_resp = MagicMock()
    mock_resp.status_code = 301
    mock_resp.headers = {"Location": "https://redhat.artifacts.testing.farm/"}

    with patch("requests.get", return_value=mock_resp):
        res = check_http_redirect("redhat.artifacts.testing.farm", port=80)
        assert res["status_code"] == 301
        assert res["is_redirect_to_https"] is True


def test_check_http_redirect_invalid() -> None:
    """Test HTTP to HTTPS redirect helper when response is not redirecting to HTTPS."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.headers = {}

    with patch("requests.get", return_value=mock_resp):
        res = check_http_redirect("redhat.artifacts.testing.farm", port=80)
        assert res["status_code"] == 200
        assert res["is_redirect_to_https"] is False


def test_check_https_tls_mocked() -> None:
    """Test TLS certificate check with mocked socket and SSL context."""
    mock_cert = {
        "subject": ((("commonName", "redhat.artifacts.testing.farm"),),),
        "subjectAltName": (("DNS", "redhat.artifacts.testing.farm"),),
        "notAfter": "Sep 14 12:00:00 2027 GMT",
    }
    mock_ssock = MagicMock()
    mock_ssock.getpeercert.return_value = mock_cert
    mock_ssock.version.return_value = "TLSv1.3"
    mock_ssock.cipher.return_value = ("TLS_AES_256_GCM_SHA384", "TLSv1.3", 256)

    with patch("socket.create_connection"), patch("ssl.create_default_context") as mock_ssl_ctx:
        mock_ctx_inst = MagicMock()
        mock_ctx_inst.wrap_socket.return_value.__enter__.return_value = mock_ssock
        mock_ssl_ctx.return_value = mock_ctx_inst

        res = check_https_tls("redhat.artifacts.testing.farm", port=443)
        assert res["tls_valid"] is True
        assert "redhat.artifacts.testing.farm" in res["subjectAltName"]


def test_admin_ssh_requires_verified_host_and_selected_identity() -> None:
    """Administrative commands use RHEL's cloud-user and fail closed on unknown hosts."""
    config = ArtifactsConfig(admin_key_path="/keys/admin", known_hosts_path="/keys/known_hosts")
    with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0, stdout="", stderr="")) as run:
        run_admin_ssh_command(config, "id")

    command = run.call_args.args[0]
    assert "cloud-user@redhat.artifacts.testing.farm" in command
    assert "StrictHostKeyChecking=yes" in command
    assert "UserKnownHostsFile=/keys/known_hosts" in command
    assert "IdentitiesOnly=yes" in command
    assert "ForwardAgent=no" in command


def test_upload_probe_rsync_command_construction(tmp_path: Path) -> None:
    """Test rsync upload helper builds the proper command with cwd and SSH options."""
    config = ArtifactsConfig(
        host="10.0.1.50",
        ssh_port=2222,
        upload_user="custom-user",
        upload_key_path="/path/to/key",
    )
    probe = create_probe(base_dir=tmp_path)

    with patch("tests.artifacts.helpers.run_command") as mock_run_cmd:
        mock_run_cmd.return_value = CommandResult(command=[], exit_code=0, stdout="", stderr="", duration_seconds=0.1)
        res = upload_probe_rsync(config, probe, temp_dir=tmp_path, log_dir=tmp_path)
        assert res.exit_code == 0

        called_cmd = mock_run_cmd.call_args[0][0]
        called_kwargs = mock_run_cmd.call_args[1]
        assert "rsync" in called_cmd[0]
        assert called_cmd[-1] == "custom-user@10.0.1.50:"
        assert "--chmod=D755,F644" in called_cmd
        ssh_command = called_cmd[called_cmd.index("-e") + 1]
        assert "-p 2222" in ssh_command
        assert "-i /path/to/key" in ssh_command
        assert called_kwargs["cwd"] == tmp_path


@pytest.mark.skipif(shutil.which("rsync") is None, reason="rsync is required for transfer-mode regression")
def test_upload_probe_public_modes_preserve_private_workspace(tmp_path: Path) -> None:
    """Real rsync makes only the transferred probe public, irrespective of source umask."""
    source = tmp_path / "private-workspace"
    source.mkdir(mode=0o700)
    destination = tmp_path / "receiver"
    destination.mkdir(mode=0o700)
    probe = create_probe(base_dir=source)
    assert probe.local_path is not None
    namespace = source / "probe-lifecheck"
    namespace.chmod(0o700)
    probe.local_path.parent.chmod(0o700)
    probe.local_path.chmod(0o600)
    secret = source / "unrelated-private-file"
    secret.write_text("not an artifact")
    secret.chmod(0o600)

    result = CommandResult(command=[], exit_code=0, stdout="", stderr="", duration_seconds=0)
    with patch("tests.artifacts.helpers.run_command", return_value=result) as command:
        upload_probe_rsync(ArtifactsConfig(), probe, source)
    arguments = command.call_args.args[0]
    # Exercise the exact upload options with a local receiver, without SSH or live infrastructure.
    options = arguments[1:arguments.index("-e")]
    transfer = run_command(["rsync", *options, arguments[-2], str(destination)], cwd=source)
    assert transfer.exit_code == 0, transfer.stderr

    remote_file = destination / probe.relative_dir / probe.filename
    assert remote_file.read_text() == probe.content
    assert remote_file.stat().st_mode & 0o777 == 0o644
    assert remote_file.parent.stat().st_mode & 0o777 == 0o755
    assert (destination / "probe-lifecheck").stat().st_mode & 0o777 == 0o755
    assert source.stat().st_mode & 0o777 == 0o700
    assert destination.stat().st_mode & 0o777 == 0o700
    assert namespace.stat().st_mode & 0o777 == 0o700
    assert probe.local_path.parent.stat().st_mode & 0o777 == 0o700
    assert probe.local_path.stat().st_mode & 0o777 == 0o600
    assert secret.stat().st_mode & 0o777 == 0o600
    assert not (destination / secret.name).exists()


def test_fetch_probe_https_immediate_success(tmp_path: Path) -> None:
    """Test immediate HTTPS fetch returns matching content and calculates latency."""
    config = ArtifactsConfig(host="10.0.1.50", https_port=443)
    probe = create_probe(base_dir=tmp_path)

    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.text = probe.content

    with patch("requests.get", return_value=mock_resp):
        status, body, latency_ms, matches = fetch_probe_https(config, probe, log_dir=tmp_path)
        assert status == 200
        assert matches is True
        assert body == probe.content
        assert latency_ms >= 0.0


def test_fetch_probe_https_failure_no_retries(tmp_path: Path) -> None:
    """Test immediate HTTPS fetch failure does not attempt silent retries."""
    config = ArtifactsConfig(host="10.0.1.50", https_port=443)
    probe = create_probe(base_dir=tmp_path)

    with patch("requests.get", side_effect=requests.ConnectionError("Connection refused")) as mock_get:
        status, body, _, matches = fetch_probe_https(config, probe, log_dir=tmp_path)
        assert status == -1
        assert matches is False
        assert "Connection refused" in body
        assert mock_get.call_count == 1


@pytest.mark.parametrize(
    ("status", "body", "enabled"),
    [
        (200, "<html><title>Index of /</title><pre><a href='../'>../</a></pre></html>", True),
        (200, "<html><title>Home</title><a href='/help'>Help</a></html>", False),
        (200, "<html><pre>Service unavailable</pre></html>", False),
        (503, "<html><title>Index of /</title></html>", False),
    ],
)
def test_check_autoindex(status: int, body: str, enabled: bool) -> None:
    """Only a successful nginx directory listing passes, not an arbitrary HTML page."""
    config = ArtifactsConfig(host="10.0.1.50")
    mock_resp = MagicMock(status_code=status, text=body, headers={"Content-Type": "text/html"})

    with patch("requests.get", return_value=mock_resp):
        res = check_autoindex(config, path="/")
        assert res["status_code"] == status
        assert res["autoindex_enabled"] is enabled


@pytest.mark.parametrize(
    ("status", "origin", "allowed"),
    [
        (200, "*", True),
        (204, "https://dashboard.testing-farm.io", True),
        (200, "", False),
        (200, "https://other.example.com", False),
        (301, "*", False),
        (403, "*", False),
        (405, "*", False),
        (500, "*", False),
    ],
)
def test_check_cors_headers(status: int, origin: str, allowed: bool) -> None:
    """The viewer's cross-origin GET must succeed; headers on an error response do not pass."""
    config = ArtifactsConfig(host="10.0.1.50")
    mock_resp = MagicMock(status_code=status, headers={"Access-Control-Allow-Origin": origin})

    with patch("requests.get", return_value=mock_resp) as get, patch(
        "requests.options", side_effect=AssertionError("CORS lifecheck must use the viewer's GET path")
    ):
        res = check_cors_headers(config, path="/")
        assert res["status_code"] == status
        assert res["cors_ok"] is allowed
        assert res["allow_origin"] == origin
        get.assert_called_once_with(
            "https://10.0.1.50:443/",
            headers={"Origin": "https://dashboard.testing-farm.io"},
            timeout=config.request_timeout,
            verify=True,
        )


@pytest.mark.parametrize("reason", ["hostname mismatch", "certificate has expired", "unknown issuer"])
def test_tls_verification_failure(reason: str) -> None:
    """The standard TLS context verifies the target hostname and rejects invalid certificates."""
    context = ssl.create_default_context()
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED
    with patch("socket.create_connection") as connection, patch(
        "ssl.create_default_context", return_value=context
    ), patch.object(context, "wrap_socket", side_effect=ssl.SSLCertVerificationError(reason)) as wrap:
        res = check_https_tls("redhat.artifacts.testing.farm")
        assert res["tls_valid"] is False
        assert reason in res["error"]
        wrap.assert_called_once_with(
            connection.return_value.__enter__.return_value,
            server_hostname="redhat.artifacts.testing.farm",
        )


def test_check_restricted_ssh_access_mocked(tmp_path: Path) -> None:
    """Accept actual rrsync forced-command rejections for shell and exec requests."""
    with patch("subprocess.run", side_effect=[
        subprocess.CompletedProcess([], 1, stdout="", stderr="/usr/bin/rrsync error: Not invoked via sshd\n"),
        subprocess.CompletedProcess([], 1, stdout="", stderr="/usr/bin/rrsync error: SSH_ORIGINAL_COMMAND does not run rsync\n"),
    ]):
        res = check_restricted_ssh_access(ArtifactsConfig(), log_dir=tmp_path)

    assert res["shell_rejected"] is True
    assert res["command_rejected"] is True


@pytest.mark.parametrize(
    ("exit_code", "stderr"),
    [
        (0, ""),
        (255, "ssh: connect to host port 22: Connection refused"),
        (255, "Permission denied (publickey)."),
        (1, "not allowed"),
        (1, "rrsync error: could not chdir to restricted directory"),
        (255, "rrsync error: Not invoked via sshd\nrrsync error: SSH_ORIGINAL_COMMAND does not run rsync"),
    ],
)
def test_ssh_restrictions_require_specific_rejection(exit_code: int, stderr: str) -> None:
    """Success, transport/authentication errors and unrelated failures do not prove a restriction."""
    with patch("subprocess.run", return_value=subprocess.CompletedProcess([], exit_code, stdout="", stderr=stderr)):
        res = check_restricted_ssh_access(ArtifactsConfig())

    assert res["shell_rejected"] is False
    assert res["command_rejected"] is False


def test_ssh_restrictions_reject_timeouts() -> None:
    """A timed-out SSH process provides no evidence of a forced-command restriction."""
    with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("ssh", 1)):
        res = check_restricted_ssh_access(ArtifactsConfig())

    assert res["shell_rejected"] is False
    assert res["command_rejected"] is False


def test_ssh_check_requests_a_shell_without_consuming_runner_input() -> None:
    """Send an SSH shell request without a command or PTY, and close its stdin."""
    config = ArtifactsConfig()
    with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0, stdout="", stderr="")) as run:
        check_restricted_ssh_access(config)

    shell_call = run.call_args_list[0]
    shell_cmd = shell_call.args[0]
    assert shell_cmd[-1] == f"{config.upload_user}@{config.host}"
    assert "-T" in shell_cmd
    assert shell_call.kwargs["stdin"] == subprocess.DEVNULL


@pytest.mark.parametrize(
    ("exit_code", "stderr", "rejected"),
    [
        (12, "/usr/bin/rrsync error: reading from write-only server is not allowed\n", True),
        (0, "", False),
        (23, "rsync: link_stat failed: No such file or directory", False),
        (255, "Permission denied (publickey).", False),
        (255, "ssh: connect to host port 22: Connection refused", False),
        (1, "rrsync error: could not chdir to restricted directory", False),
    ],
)
def test_rsync_write_only_requires_sender_rejection(
    tmp_path: Path, exit_code: int, stderr: str, rejected: bool,
) -> None:
    """Only an explicit write-only rejection proves the upload key cannot download artifacts."""
    config = ArtifactsConfig()
    probe = create_probe(base_dir=tmp_path)
    with patch("subprocess.run", return_value=subprocess.CompletedProcess([], exit_code, stdout="", stderr=stderr)) as run:
        res = check_rsync_write_only(config, probe, tmp_path, log_dir=tmp_path)

    assert res["download_rejected"] is rejected
    command = run.call_args.args[0]
    assert command[-2] == f"{config.upload_user}@{config.host}:{probe.relative_dir}/{probe.filename}"
    assert run.call_args.kwargs["cwd"] == tmp_path
    assert res["stderr"] == stderr


def test_rsync_write_only_rejects_timeout(tmp_path: Path) -> None:
    """A timeout must fail the write-only check even if partial stderr contains a rejection."""
    with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(
        "rsync", 1, stderr=b"rrsync error: reading from write-only server is not allowed",
    )):
        res = check_rsync_write_only(ArtifactsConfig(), create_probe(), tmp_path)

    assert res["download_rejected"] is False


def _mount_command_result(command: list[str], descriptor: str) -> subprocess.CompletedProcess[str]:
    """Model the native-unit image: NFS is mounted but the active fstab has no storage entry."""
    remote = command[-1]
    if "readlink" in remote:
        stdout = "/var/mnt/s3files\n"
    elif "findmnt --json" in remote:
        stdout = json.dumps({"filesystems": [{
            "target": "/var/mnt/s3files", "fstype": "nfs4", "source": "127.0.0.1:/",
        }]})
    elif "findmnt --fstab" in remote:
        return subprocess.CompletedProcess(command, 1, stdout="", stderr="No storage entry in fstab")
    elif "systemctl show" in remote and "systemctl cat" in remote:
        stdout = descriptor
    else:
        raise AssertionError(f"Unexpected mount inspection: {remote}")
    return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")


@pytest.mark.parametrize(
    ("before", "after", "expected"),
    [
        ("", "", True),
        ("What=fs-0963344dcd0f605ed:/", "What=fs-00000000000000000:/", False),
        ("Type=s3files", "Type=nfs4", False),
        ("Where=/var/mnt/s3files", "Where=/var/mnt/other", False),
        ("mounttargetip=10.31.10.250", "mounttargetip=10.31.10.251", False),
        ("mounttargetip=10.31.10.250", "mounttargetip=10.31.10.250,mounttargetip=10.31.10.251", False),
        ("mounttargetip=10.31.10.250", "mounttargetip=10.31.10.251,mounttargetip=10.31.10.250", True),
        ("_netdev,", "", False),
        (",nofail", "", False),
        ("LoadState=loaded", "LoadState=masked", False),
        ("ActiveState=active", "ActiveState=inactive", False),
        ("UnitFileState=enabled", "UnitFileState=disabled", False),
        ("UnitFileState=enabled", "UnitFileState=enabled-runtime", False),
        ("NeedDaemonReload=no", "NeedDaemonReload=yes", False),
        ("--- unit configuration ---", "missing unit configuration", False),
    ],
)
def test_mount_verifies_native_backend(
    native_mount_descriptor: str, before: str, after: str, expected: bool,
) -> None:
    """A healthy native mount needs no fstab/automount; wrong backend or unit state fails."""
    config = ArtifactsConfig(filesystem_id="fs-0963344dcd0f605ed", mount_target_ip="10.31.10.250")
    descriptor = native_mount_descriptor.replace(before, after) if before else native_mount_descriptor
    with patch("subprocess.run", side_effect=lambda command, **kwargs: _mount_command_result(command, descriptor)) as run:
        result = check_mount_status(config)

    assert result["mount_present"] is True
    assert result["expected_backend"] is expected
    commands = [call.args[0][-1] for call in run.call_args_list]
    assert all("findmnt --fstab" not in command for command in commands)
    assert "systemd-escape --path --suffix=mount -- /var/mnt/s3files" in commands[-1]
    assert "systemctl show" in commands[-1] and "systemctl cat" in commands[-1]


@pytest.mark.parametrize(
    ("override", "expected"),
    [
        ("[Mount]\nWhat=fs-00000000000000000:/\n", False),
        ("[Mount]\nOptions=_netdev,nofail,mounttargetip=10.31.10.251\n", False),
        ("[Mount]\nWhat=fs-0963344dcd0f605ed:/\n", True),
        ("[Unit]\nAfter=network-online.target time-sync.target\n", True),
        ("[Mount\nWhat=fs-0963344dcd0f605ed:/\n", False),
    ],
)
def test_mount_checks_effective_native_drop_ins(native_mount_descriptor: str, override: str, expected: bool) -> None:
    """Use the effective fragment plus ordered drop-ins, not just the image's original file."""
    config = ArtifactsConfig(filesystem_id="fs-0963344dcd0f605ed", mount_target_ip="10.31.10.250")
    descriptor = native_mount_descriptor + "\n# /etc/systemd/system/var-mnt-s3files.mount.d/override.conf\n" + override
    with patch("subprocess.run", side_effect=lambda command, **kwargs: _mount_command_result(command, descriptor)):
        result = check_mount_status(config)

    assert result["expected_backend"] is expected


@pytest.mark.parametrize("timed_out", [False, True])
def test_native_unit_inspection_failure_cannot_pass(native_mount_descriptor: str, timed_out: bool) -> None:
    """Partial valid unit output cannot hide an SSH error or timeout."""
    config = ArtifactsConfig(filesystem_id="fs-0963344dcd0f605ed", mount_target_ip="10.31.10.250")
    failure = (
        subprocess.TimeoutExpired("ssh", 1, output=native_mount_descriptor)
        if timed_out else subprocess.CompletedProcess([], 1, stdout=native_mount_descriptor, stderr="Inspection failed")
    )
    with patch("subprocess.run", side_effect=[
        _mount_command_result(["readlink"], native_mount_descriptor),
        _mount_command_result(["findmnt --json"], native_mount_descriptor),
        failure,
    ]):
        result = check_mount_status(config)

    assert result["mount_present"] is True
    assert result["expected_backend"] is False


def test_mount_accepts_remote_canonical_path_without_admin_write_access() -> None:
    """A valid uploader mount is not rejected because /mnt is an alias or admin is read-only."""
    mount_info = json.dumps({"filesystems": [{"target": "/var/mnt/s3files", "fstype": "nfs4"}]})
    with patch("subprocess.run", side_effect=[
        subprocess.CompletedProcess([], 0, stdout="/var/mnt/s3files\n", stderr=""),
        subprocess.CompletedProcess([], 0, stdout=mount_info, stderr=""),
    ]):
        result = check_mount_status(ArtifactsConfig())

    assert result["mount_present"] is True
    assert result["canonical_mount_point"] == "/var/mnt/s3files"
    assert "is_writable" not in result


def test_check_mount_status_mocked(tmp_path: Path) -> None:
    """Test S3 Files mount status verification on default /mnt/s3files."""
    config = ArtifactsConfig(host="10.0.1.50", mount_point="/mnt/s3files")

    mock_findmnt = CommandResult(
        command=["ssh"],
        exit_code=0,
        stdout='{"filesystems": [{"target": "/mnt/s3files", "fstype": "nfs4"}]}',
        stderr="",
        duration_seconds=0.1,
    )
    resolved = CommandResult(command=["ssh"], exit_code=0, stdout="/mnt/s3files\n", stderr="", duration_seconds=0.1)

    with patch("tests.artifacts.helpers.run_admin_ssh_command", side_effect=[resolved, mock_findmnt]):
        res = check_mount_status(config, log_dir=tmp_path)
        assert res["mount_present"] is True
        assert res["fstype"] == "nfs4"
        assert res["canonical_mount_point"] == "/mnt/s3files"
        assert res["mount_point"] == "/mnt/s3files"


@pytest.mark.parametrize(
    ("fstype", "target", "expected"),
    [
        ("nfs", "/mnt/s3files", False),
        ("nfs4", "/mnt/s3files", True),
        ("xfs", "/mnt/s3files", False),
        ("ext4", "/mnt/s3files", False),
        ("autofs", "/mnt/s3files", False),
        ("nfs4", "/mnt/another-store", False),
    ],
)
def test_mount_requires_nfs_at_configured_target(fstype: str, target: str, expected: bool) -> None:
    """Only an NFSv4 filesystem at the resolved mount point is accepted."""
    mount_info = json.dumps({"filesystems": [{"target": target, "fstype": fstype}]})
    with patch("subprocess.run", side_effect=[
        subprocess.CompletedProcess([], 0, stdout="/mnt/s3files\n", stderr=""),
        subprocess.CompletedProcess([], 0, stdout=mount_info, stderr=""),
    ]):
        res = check_mount_status(ArtifactsConfig())

    assert res["mount_present"] is expected


@pytest.mark.parametrize("stdout", ["not JSON", "[]", "{}", '{"filesystems": []}'])
def test_mount_rejects_invalid_or_missing_filesystem_data(stdout: str) -> None:
    """Malformed or empty findmnt output cannot be accepted as a mount."""
    with patch("subprocess.run", side_effect=[
        subprocess.CompletedProcess([], 0, stdout="/mnt/s3files\n", stderr=""),
        subprocess.CompletedProcess([], 0, stdout=stdout, stderr=""),
    ]):
        res = check_mount_status(ArtifactsConfig())

    assert res["mount_present"] is False


def test_mount_inspection_does_not_require_admin_write_access() -> None:
    """Inspect the mounted directory, but leave write verification to the upload identity."""
    config = ArtifactsConfig(mount_point="/mnt/artifacts store")
    mount_info = json.dumps({"filesystems": [{"target": config.mount_point, "fstype": "nfs4"}]})
    with patch("subprocess.run", side_effect=[
        subprocess.CompletedProcess([], 0, stdout=f"{config.mount_point}\n", stderr=""),
        subprocess.CompletedProcess([], 0, stdout=mount_info, stderr=""),
    ]) as run:
        res = check_mount_status(config)

    assert res["mount_present"] is True
    inspection = run.call_args_list[1].args[0][-1]
    assert "stat -- '/mnt/artifacts store/.'" in inspection
    assert inspection.index("stat ") < inspection.index("findmnt ")
    assert "--mountpoint '/mnt/artifacts store'" in inspection
    assert all("test -w" not in call.args[0][-1] for call in run.call_args_list)


@pytest.mark.parametrize("timed_out", [False, True])
def test_mount_rejects_failed_inspection(timed_out: bool) -> None:
    """A failed or timed-out SSH command cannot prove an NFS mount, even with partial JSON."""
    mount_info = '{"filesystems": [{"target": "/mnt/s3files", "fstype": "nfs4"}]}'
    with patch("subprocess.run") as run:
        failure = (
            subprocess.TimeoutExpired("ssh", 1, output=mount_info)
            if timed_out else subprocess.CompletedProcess([], 255, stdout=mount_info, stderr="Connection closed")
        )
        run.side_effect = [subprocess.CompletedProcess([], 0, stdout="/mnt/s3files\n", stderr=""), failure]
        res = check_mount_status(ArtifactsConfig())

    assert res["mount_present"] is False


def test_get_boot_id_and_reboot_and_wait_mocked(tmp_path: Path) -> None:
    """Wait through an unchanged boot ID and SSH downtime, then verify NFS recovery."""
    config = ArtifactsConfig(allow_reboot=True, reboot_timeout=30, reboot_poll_interval=1)
    old_boot_id = "11111111-1111-1111-1111-111111111111"
    new_boot_id = "22222222-2222-2222-2222-222222222222"

    with patch("subprocess.run", side_effect=[
        subprocess.CompletedProcess([], 0, stdout="", stderr=""),
        subprocess.CompletedProcess([], 0, stdout=old_boot_id, stderr=""),
        subprocess.CompletedProcess([], 255, stdout="", stderr="Connection refused"),
        subprocess.CompletedProcess([], 0, stdout=new_boot_id, stderr=""),
        subprocess.CompletedProcess([], 0, stdout="/mnt/s3files\n", stderr=""),
        subprocess.CompletedProcess([], 0, stdout='{"filesystems": [{"target": "/mnt/s3files", "fstype": "nfs4"}]}', stderr=""),
    ]), patch("time.sleep"):
        ok, boot_id = reboot_and_wait(config, old_boot_id, log_dir=tmp_path)

    assert ok is True
    assert boot_id == new_boot_id


def test_reboot_recovers_with_native_mount_without_fstab(native_mount_descriptor: str) -> None:
    """A changed boot ID and healthy enabled native backend complete reboot recovery."""
    config = ArtifactsConfig(
        allow_reboot=True, reboot_timeout=60, reboot_poll_interval=1,
        filesystem_id="fs-0963344dcd0f605ed", mount_target_ip="10.31.10.250",
    )
    unit_checks = 0

    def transport(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        nonlocal unit_checks
        remote = command[-1]
        if "systemctl reboot" in remote:
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
        if "boot_id" in remote:
            return subprocess.CompletedProcess(command, 0, stdout="new-boot\n", stderr="")
        descriptor = native_mount_descriptor
        if "systemctl show" in remote:
            unit_checks += 1
            if unit_checks == 1:
                descriptor = descriptor.replace("ActiveState=active", "ActiveState=inactive")
        return _mount_command_result(command, descriptor)

    with patch("subprocess.run", side_effect=transport), patch("time.sleep"), patch(
        "time.time", side_effect=itertools.count(),
    ), patch("time.monotonic", side_effect=itertools.count()):
        assert reboot_and_wait(config, "old-boot") == (True, "new-boot")

    assert unit_checks == 2


def test_run_command_propagates_local_errors() -> None:
    """A missing or unusable local executable is not a remote command failure."""
    with patch("subprocess.run", side_effect=FileNotFoundError("ssh executable missing")):
        with pytest.raises(FileNotFoundError, match="ssh executable missing"):
            run_command(["ssh", "example"])


def test_reboot_propagates_permanent_local_errors() -> None:
    """Local failures while polling must not be misreported as a server reboot timeout."""
    config = ArtifactsConfig(allow_reboot=True, reboot_timeout=10, reboot_poll_interval=1)
    with patch("subprocess.run", side_effect=[
        subprocess.CompletedProcess([], 0, stdout="", stderr=""),
        PermissionError("cannot execute ssh"),
    ]), patch("time.sleep"), patch("time.time", side_effect=itertools.count()), patch(
        "time.monotonic", side_effect=itertools.count(),
    ):
        with pytest.raises(PermissionError, match="cannot execute ssh"):
            reboot_and_wait(config, "old-boot-id")


@pytest.mark.parametrize("fstype", ["xfs", "autofs"])
def test_reboot_requires_nfs_recovery(fstype: str) -> None:
    """A changed boot ID alone is insufficient when the backing NFS mount is absent."""
    config = ArtifactsConfig(allow_reboot=True, reboot_timeout=20, reboot_poll_interval=1)

    def remote_response(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if "boot_id" in command[-1]:
            stdout = "new-boot-id\n"
        elif "readlink" in command[-1]:
            stdout = f"{config.mount_point}\n"
        elif "findmnt" in command[-1]:
            stdout = json.dumps({"filesystems": [{"target": config.mount_point, "fstype": fstype}]})
        else:
            stdout = ""
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    with patch("subprocess.run", side_effect=remote_response), patch("time.sleep"), patch(
        "time.time", side_effect=itertools.count(),
    ), patch("time.monotonic", side_effect=itertools.count()):
        ok, boot_id = reboot_and_wait(config, "old-boot-id")

    assert ok is False
    assert boot_id == "new-boot-id"


def test_reboot_timeout_preserves_last_failure(caplog: pytest.LogCaptureFixture) -> None:
    """Timeout diagnostics distinguish an unchanged boot ID from an unreachable host."""
    config = ArtifactsConfig(allow_reboot=True, reboot_timeout=10, reboot_poll_interval=1)
    with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0, stdout="old-boot-id\n", stderr="")), patch(
        "time.sleep",
    ), patch("time.time", side_effect=itertools.count()), patch("time.monotonic", side_effect=itertools.count()):
        assert reboot_and_wait(config, "old-boot-id") == (False, "")

    assert "boot ID is unchanged" in caplog.text


def test_reboot_refused_without_allow_reboot() -> None:
    """Test that reboot_and_wait throws when allow_reboot is False."""
    config = ArtifactsConfig(allow_reboot=False)
    with pytest.raises(RuntimeError, match="Reboot testing is not enabled"):
        reboot_and_wait(config, "old-id")


def test_cleanup_probe_confined_path_safety(tmp_path: Path) -> None:
    """Test that cleanup refuses unsafe or traversal paths outside the probe namespace."""
    config = ArtifactsConfig(probe_namespace="probe-lifecheck")

    # Unsafe traversal path
    unsafe_probe = ProbePayload(
        probe_id="bad",
        created_at="now",
        relative_dir="../etc",
        filename="passwd",
        content="",
        content_sha256="",
    )
    assert cleanup_probe(config, unsafe_probe, log_dir=tmp_path) is False

    # Valid probe path
    valid_probe = create_probe(namespace="probe-lifecheck")
    with patch("tests.artifacts.helpers.run_admin_ssh_command") as mock_admin:
        mock_admin.return_value = CommandResult(command=[], exit_code=0, stdout="", stderr="", duration_seconds=0.1)
        assert cleanup_probe(config, valid_probe, log_dir=tmp_path) is True
        assert "/mnt/s3files/probe-lifecheck/probe-" in mock_admin.call_args[0][1]
