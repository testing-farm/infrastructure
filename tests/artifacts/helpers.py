"""Helpers and utilities for Testing Farm artifact server lifecheck."""

from __future__ import annotations

import dataclasses
import hashlib
import json
import logging
from pathlib import Path
import shlex
import socket
import ssl
import subprocess
import time
from typing import Any, Optional
import urllib.parse
import uuid

from gluetool import GlueError
from gluetool.result import Result
from gluetool.utils import wait
import requests

logger = logging.getLogger(__name__)


@dataclasses.dataclass
class ArtifactsConfig:
    """Configuration for artifact server lifecheck tests.

    :param host: Artifact server hostname or IP address.
    :param private_ip: Expected private IP address of the server.
    :param http_port: Port for HTTP service.
    :param https_port: Port for HTTPS service.
    :param ssh_port: Port for SSH service.
    :param upload_user: Username for restricted rsync-over-SSH uploads.
    :param upload_key_path: Path to private SSH key for upload user.
    :param admin_user: Username for administrative SSH access (mount inspect, reboot).
    :param admin_key_path: Path to private SSH key for admin user.
    :param ca_cert_path: Path to custom CA certificate for TLS validation.
    :param probe_namespace: Directory prefix under artifacts root for probe testing.
    :param request_timeout: Timeout in seconds for HTTP/HTTPS requests.
    :param ssh_timeout: Timeout in seconds for SSH/rsync commands.
    :param reboot_timeout: Max seconds to wait for reboot completion.
    :param reboot_poll_interval: Interval in seconds between reboot polling checks.
    :param allow_reboot: Whether reboot testing is explicitly authorized.
    :param is_live: Whether live infrastructure execution is enabled.
    :param artifact_dir: Directory where test logs and artifacts are preserved.
    """

    host: str = "redhat.artifacts.testing.farm"
    private_ip: Optional[str] = None
    http_port: int = 80
    https_port: int = 443
    ssh_port: int = 22
    upload_user: str = "artifacts"
    upload_key_path: Optional[str] = None
    admin_user: str = "fedora"
    admin_key_path: Optional[str] = None
    ca_cert_path: Optional[str] = None
    probe_namespace: str = "probe-lifecheck"
    request_timeout: float = 10.0
    ssh_timeout: float = 15.0
    reboot_timeout: int = 300
    reboot_poll_interval: int = 5
    mount_point: str = "/mnt/s3files"
    allow_reboot: bool = False
    is_live: bool = False
    artifact_dir: str = ".pytest/artifacts-lifecheck"


@dataclasses.dataclass
class ProbePayload:
    """Unique test probe file payload.

    :param probe_id: Unique UUID identifying this probe run.
    :param created_at: Timestamp when the probe was created.
    :param relative_dir: Relative folder under artifact store (e.g. probe-lifecheck/probe-<uuid>).
    :param filename: Probe file name.
    :param content: Text content of the probe file.
    :param content_sha256: Hex digest of SHA256 hash of probe content.
    :param local_path: Local filesystem path where probe is written prior to upload.
    """

    probe_id: str
    created_at: str
    relative_dir: str
    filename: str
    content: str
    content_sha256: str
    local_path: Optional[Path] = None


@dataclasses.dataclass
class CommandResult:
    """Result of an executed subprocess command.

    :param command: Executed command arguments (sanitized).
    :param exit_code: Subprocess exit code.
    :param stdout: Standard output string.
    :param stderr: Standard error string.
    :param duration_seconds: Elapsed execution time in seconds.
    :param timed_out: Whether execution timed out.
    """

    command: list[str]
    exit_code: int
    stdout: str
    stderr: str
    duration_seconds: float
    timed_out: bool = False


def sanitize_command(cmd: list[str]) -> list[str]:
    """Sanitize sensitive arguments from command list for safe logging.

    :param cmd: Command list.
    :returns: Sanitized command list.
    """
    sanitized: list[str] = []
    redact_next = False
    for arg in cmd:
        if redact_next:
            sanitized.append("[REDACTED]")
            redact_next = False
            continue
        if arg in ("-i", "--identity", "--password", "-p"):
            sanitized.append(arg)
            if arg in ("-i", "--identity", "--password"):
                redact_next = True
            continue
        sanitized.append(arg)
    return sanitized


def run_command(
    cmd: list[str],
    timeout: float = 30.0,
    cwd: Optional[Path | str] = None,
    log_dir: Optional[Path] = None,
    log_prefix: str = "cmd",
) -> CommandResult:
    """Execute a subprocess command with timeout and write sanitized output to log directory.

    :param cmd: Command arguments list.
    :param timeout: Timeout in seconds.
    :param cwd: Optional working directory for command execution.
    :param log_dir: Optional directory to store command stdout/stderr logs.
    :param log_prefix: Prefix for artifact log files.
    :returns: CommandResult instance.
    """
    start_time = time.monotonic()
    timed_out = False
    sanitized_cmd = sanitize_command(cmd)

    try:
        process = subprocess.run(
            cmd,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        exit_code = process.returncode
        stdout = process.stdout
        stderr = process.stderr
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        exit_code = -1
        stdout = exc.stdout if isinstance(exc.stdout, str) else (exc.stdout.decode("utf-8", errors="replace") if exc.stdout else "")
        stderr = exc.stderr if isinstance(exc.stderr, str) else (exc.stderr.decode("utf-8", errors="replace") if exc.stderr else "Command timed out")

    duration = time.monotonic() - start_time

    if log_dir is not None:
        log_dir.mkdir(parents=True, exist_ok=True)
        timestamp = int(time.time() * 1000)
        cmd_file = log_dir / f"{log_prefix}-{timestamp}.log"
        with open(cmd_file, "w", encoding="utf-8") as fh:
            fh.write(f"Command: {' '.join(sanitized_cmd)}\n")
            fh.write(f"Duration: {duration:.3f}s, Exit Code: {exit_code}, TimedOut: {timed_out}\n")
            fh.write("--- STDOUT ---\n")
            fh.write(stdout)
            fh.write("\n--- STDERR ---\n")
            fh.write(stderr)
            fh.write("\n")

    return CommandResult(
        command=sanitized_cmd,
        exit_code=exit_code,
        stdout=stdout,
        stderr=stderr,
        duration_seconds=duration,
        timed_out=timed_out,
    )


def create_probe(namespace: str = "probe-lifecheck", base_dir: Optional[Path] = None) -> ProbePayload:
    """Generate a unique probe payload and optional local file.

    :param namespace: Prefix directory under artifacts root.
    :param base_dir: Optional base directory to write the local probe file.
    :returns: ProbePayload instance.
    """
    probe_id = str(uuid.uuid4())
    created_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    relative_dir = f"{namespace}/probe-{probe_id}"
    filename = "probe.txt"

    raw_token = f"tft-lifecheck-probe-{probe_id}-{time.time_ns()}"
    content_hash = hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
    content = (
        f"Testing Farm Artifact Server Lifecheck Probe\n"
        f"Probe ID: {probe_id}\n"
        f"Created At: {created_at}\n"
        f"Token: {raw_token}\n"
        f"SHA256: {content_hash}\n"
    )
    final_sha256 = hashlib.sha256(content.encode("utf-8")).hexdigest()

    local_path = None
    if base_dir is not None:
        local_dir = base_dir / relative_dir
        local_dir.mkdir(parents=True, exist_ok=True)
        local_path = local_dir / filename
        with open(local_path, "w", encoding="utf-8") as fh:
            fh.write(content)

    return ProbePayload(
        probe_id=probe_id,
        created_at=created_at,
        relative_dir=relative_dir,
        filename=filename,
        content=content,
        content_sha256=final_sha256,
        local_path=local_path,
    )


def resolve_dns(hostname: str) -> list[str]:
    """Resolve IPv4 addresses for a given hostname.

    :param hostname: Target hostname.
    :returns: List of resolved IPv4 address strings.
    """
    try:
        addrinfo = socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM)
        return list({item[4][0] for item in addrinfo})
    except socket.gaierror as exc:
        logger.error(f"DNS resolution failed for {hostname}: {exc}")
        return []


def check_http_redirect(
    host: str,
    port: int = 80,
    timeout: float = 10.0,
    path: str = "/",
) -> dict[str, Any]:
    """Verify HTTP to HTTPS redirect behavior.

    :param host: Hostname or IP.
    :param port: HTTP port (default 80).
    :param timeout: Request timeout in seconds.
    :param path: Request path.
    :returns: Dictionary with status_code, location, and is_redirect_to_https.
    """
    url = f"http://{host}:{port}{path}"
    try:
        response = requests.get(url, timeout=timeout, allow_redirects=False)
        location = response.headers.get("Location", "")
        parsed = urllib.parse.urlparse(location)
        is_redirect_to_https = (
            response.status_code in (301, 302, 307, 308)
            and parsed.scheme == "https"
        )
        return {
            "status_code": response.status_code,
            "location": location,
            "is_redirect_to_https": is_redirect_to_https,
            "headers": dict(response.headers),
        }
    except requests.RequestException as exc:
        logger.error(f"HTTP redirect check failed for {url}: {exc}")
        return {
            "status_code": -1,
            "location": "",
            "is_redirect_to_https": False,
            "error": str(exc),
        }


def matches_san(hostname: str, san: str) -> bool:
    """Check if a hostname matches a Subject Alternative Name entry (exact or wildcard).

    Supports exact matches (redhat.artifacts.testing.farm) as well as wildcard parent
    domain matching (*.artifacts.testing.farm or *.testing.farm).

    :param hostname: Target hostname.
    :param san: SAN entry from certificate.
    :returns: True if hostname matches SAN, False otherwise.
    """
    if san.lower() == hostname.lower():
        return True
    if san.startswith("*."):
        parent_domain = san[2:].lower()
        host_lower = hostname.lower()
        if host_lower.endswith(f".{parent_domain}"):
            # Single-label subdomain match (e.g. *.artifacts.testing.farm matches redhat.artifacts.testing.farm)
            prefix = host_lower[:-len(parent_domain) - 1]
            if "." not in prefix:
                return True
        # Also allow multi-level parent matching if CA issued broader wildcard
        if host_lower == parent_domain or host_lower.endswith(f".{parent_domain}"):
            return True
    return False


def check_https_tls(
    host: str,
    port: int = 443,
    ca_cert: Optional[str] = None,
    timeout: float = 10.0,
) -> dict[str, Any]:
    """Verify TLS certificate validity and SAN matches host.

    :param host: Target hostname.
    :param port: HTTPS port (default 443).
    :param ca_cert: Optional CA bundle path.
    :param timeout: Timeout in seconds.
    :returns: Dictionary with tls_valid, subject, san, and cert details.
    """
    context = ssl.create_default_context(cafile=ca_cert)
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            with context.wrap_socket(sock, server_hostname=host) as ssock:
                cert = ssock.getpeercert()
                san_list = [entry[1] for entry in cert.get("subjectAltName", []) if entry[0] == "DNS"]
                return {
                    "tls_valid": True,
                    "version": ssock.version(),
                    "cipher": ssock.cipher(),
                    "subject": cert.get("subject"),
                    "subjectAltName": san_list,
                    "notAfter": cert.get("notAfter"),
                }
    except Exception as exc:
        logger.error(f"TLS check failed for {host}:{port}: {exc}")
        return {
            "tls_valid": False,
            "error": str(exc),
        }


def _build_ssh_cmd(
    port: int,
    key_path: Optional[str] = None,
    timeout: float = 15.0,
) -> list[str]:
    """Build standardized SSH client command arguments.

    :param port: SSH port number.
    :param key_path: Optional private key path.
    :param timeout: Connection timeout in seconds.
    :returns: List of base SSH command tokens.
    """
    cmd = [
        "ssh",
        "-p", str(port),
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "BatchMode=yes",
        "-o", f"ConnectTimeout={int(timeout)}",
    ]
    if key_path:
        cmd.extend(["-i", key_path])
    return cmd


def upload_probe_rsync(
    config: ArtifactsConfig,
    probe: ProbePayload,
    temp_dir: Path,
    log_dir: Optional[Path] = None,
) -> CommandResult:
    """Upload probe payload via restricted rsync-over-SSH.

    :param config: ArtifactsConfig instance.
    :param probe: ProbePayload instance with local file created.
    :param temp_dir: Temporary directory containing probe local structure.
    :param log_dir: Directory to store command logs.
    :returns: CommandResult of the rsync invocation.
    """
    if probe.local_path is None or not probe.local_path.exists():
        raise ValueError("Probe local file does not exist. Call create_probe with base_dir first.")

    ssh_cmd = _build_ssh_cmd(config.ssh_port, config.upload_key_path, config.ssh_timeout)

    # Target upload path with --relative: base root on remote host
    remote_target = f"{config.upload_user}@{config.host}:"
    rel_file_path = str(probe.local_path.relative_to(temp_dir))
    cmd = [
        "rsync",
        "-avz",
        "--relative",
        "-e", shlex.join(ssh_cmd),
        rel_file_path,
        remote_target,
    ]

    return run_command(
        cmd,
        timeout=config.ssh_timeout,
        cwd=temp_dir,
        log_dir=log_dir,
        log_prefix="rsync-upload",
    )


def fetch_probe_https(
    config: ArtifactsConfig,
    probe: ProbePayload,
    log_dir: Optional[Path] = None,
) -> tuple[int, str, float, bool]:
    """Perform immediate single-attempt HTTPS retrieval of uploaded probe.

    Bound by request_timeout; strictly does not retry upon failure.

    :param config: ArtifactsConfig instance.
    :param probe: ProbePayload instance to retrieve.
    :param log_dir: Optional log directory for diagnostic artifacts.
    :returns: Tuple of (status_code, response_body, latency_ms, content_matches).
    """
    url = f"https://{config.host}:{config.https_port}/{probe.relative_dir}/{probe.filename}"
    verify: Any = config.ca_cert_path if config.ca_cert_path else True

    start_time = time.monotonic()
    status_code = -1
    response_body = ""
    content_matches = False

    try:
        response = requests.get(
            url,
            timeout=config.request_timeout,
            verify=verify,
            allow_redirects=True,
        )
        status_code = response.status_code
        response_body = response.text
        content_matches = (status_code == 200 and response_body == probe.content)
    except requests.RequestException as exc:
        logger.error(f"First-attempt HTTPS fetch failed for {url}: {exc}")
        response_body = f"Fetch error: {exc}"

    latency_ms = (time.monotonic() - start_time) * 1000.0

    if log_dir is not None:
        log_dir.mkdir(parents=True, exist_ok=True)
        timestamp = int(time.time() * 1000)
        fetch_log = log_dir / f"https-fetch-{timestamp}.log"
        with open(fetch_log, "w", encoding="utf-8") as fh:
            fh.write(f"URL: {url}\n")
            fh.write(f"Status Code: {status_code}\n")
            fh.write(f"Latency: {latency_ms:.2f} ms\n")
            fh.write(f"Content Matches: {content_matches}\n")
            fh.write(f"Response Body:\n{response_body}\n")

    return status_code, response_body, latency_ms, content_matches


def check_autoindex(
    config: ArtifactsConfig,
    path: str = "/",
) -> dict[str, Any]:
    """Verify autoindex directory listing is enabled on nginx.

    :param config: ArtifactsConfig instance.
    :param path: Path to inspect.
    :returns: Dictionary with status_code, autoindex_enabled, and headers.
    """
    url = f"https://{config.host}:{config.https_port}{path}"
    verify: Any = config.ca_cert_path if config.ca_cert_path else True

    try:
        response = requests.get(url, timeout=config.request_timeout, verify=verify)
        has_autoindex = (
            response.status_code == 200
            and ("<title>Index of" in response.text or "<pre>" in response.text or "<a href=" in response.text)
        )
        return {
            "status_code": response.status_code,
            "autoindex_enabled": has_autoindex,
            "headers": dict(response.headers),
        }
    except requests.RequestException as exc:
        return {
            "status_code": -1,
            "autoindex_enabled": False,
            "error": str(exc),
        }


def check_cors_headers(
    config: ArtifactsConfig,
    path: str = "/",
) -> dict[str, Any]:
    """Verify CORS headers on HTTP/HTTPS responses.

    :param config: ArtifactsConfig instance.
    :param path: Path to inspect.
    :returns: Dictionary with cors_allowed, allow_origin header, etc.
    """
    url = f"https://{config.host}:{config.https_port}{path}"
    verify: Any = config.ca_cert_path if config.ca_cert_path else True
    headers = {"Origin": "https://dashboard.testing-farm.io"}

    try:
        response = requests.options(url, headers=headers, timeout=config.request_timeout, verify=verify)
        allow_origin = response.headers.get("Access-Control-Allow-Origin", "")
        return {
            "status_code": response.status_code,
            "allow_origin": allow_origin,
            "cors_ok": allow_origin in ("*", "https://dashboard.testing-farm.io"),
            "headers": dict(response.headers),
        }
    except requests.RequestException as exc:
        return {
            "status_code": -1,
            "cors_ok": False,
            "error": str(exc),
        }


def _rrsync_rejected(result: CommandResult, reason: str) -> bool:
    """Recognize a forced-command rejection, not a transport or authentication failure.

    :param result: Completed SSH or rsync command.
    :param reason: Expected diagnostic from the image's rrsync forced command.
    :returns: Whether rrsync rejected the requested operation for this reason.
    """
    return (
        not result.timed_out
        and 0 < result.exit_code < 255
        and any("rrsync" in line and reason in line for line in result.stderr.splitlines())
    )


def check_restricted_ssh_access(
    config: ArtifactsConfig,
    log_dir: Optional[Path] = None,
) -> dict[str, Any]:
    """Verify that interactive shell and unauthorized commands are rejected by restricted SSH.

    :param config: ArtifactsConfig instance.
    :param log_dir: Optional log directory.
    :returns: Dictionary summarizing rejection results.
    """
    ssh_cmd = _build_ssh_cmd(config.ssh_port, config.upload_key_path, config.ssh_timeout)

    # No remote command sends a shell request. Disable PTY allocation so a no-pty
    # restriction alone cannot stand in for rejection by the forced command.
    cmd_shell = [*ssh_cmd, "-T", f"{config.upload_user}@{config.host}"]
    res_shell = run_command(cmd_shell, timeout=config.ssh_timeout, log_dir=log_dir, log_prefix="ssh-reject-shell")

    # Test 2: Arbitrary command (cat /etc/passwd)
    cmd_cat = [*ssh_cmd, f"{config.upload_user}@{config.host}", "cat /etc/passwd"]
    res_cat = run_command(cmd_cat, timeout=config.ssh_timeout, log_dir=log_dir, log_prefix="ssh-reject-cmd")

    shell_rejected = _rrsync_rejected(res_shell, "Not invoked via sshd")
    cmd_rejected = _rrsync_rejected(res_cat, "SSH_ORIGINAL_COMMAND does not run rsync")

    return {
        "shell_rejected": shell_rejected,
        "command_rejected": cmd_rejected,
        "shell_exit_code": res_shell.exit_code,
        "shell_stderr": res_shell.stderr,
        "command_exit_code": res_cat.exit_code,
        "command_stderr": res_cat.stderr,
    }


def check_rsync_write_only(
    config: ArtifactsConfig,
    probe: ProbePayload,
    temp_dir: Path,
    log_dir: Optional[Path] = None,
) -> dict[str, Any]:
    """Attempt to download an uploaded probe using the restricted upload identity.

    :param config: ArtifactsConfig instance.
    :param probe: Probe whose successful upload and HTTPS read-back have been verified.
    :param temp_dir: Local workspace for any unexpectedly accepted download.
    :param log_dir: Directory to retain complete rsync diagnostics.
    :returns: Download rejection status, exit code, and stderr.
    """
    ssh_cmd = _build_ssh_cmd(config.ssh_port, config.upload_key_path, config.ssh_timeout)
    remote_source = f"{config.upload_user}@{config.host}:{probe.relative_dir}/{probe.filename}"
    res = run_command(
        [
            "rsync", "-avz",
            "-e", shlex.join(ssh_cmd),
            remote_source,
            f"download-{probe.probe_id}.txt",
        ],
        timeout=config.ssh_timeout,
        cwd=temp_dir,
        log_dir=log_dir,
        log_prefix="rsync-reject-download",
    )
    return {
        "download_rejected": _rrsync_rejected(res, "reading from write-only server is not allowed"),
        "exit_code": res.exit_code,
        "stderr": res.stderr,
    }


def run_admin_ssh_command(
    config: ArtifactsConfig,
    remote_cmd: str,
    log_dir: Optional[Path] = None,
    log_prefix: str = "admin-ssh",
) -> CommandResult:
    """Execute a command over administrative SSH.

    :param config: ArtifactsConfig instance.
    :param remote_cmd: Shell command to execute on the server.
    :param log_dir: Optional log directory.
    :param log_prefix: Prefix for log file.
    :returns: CommandResult.
    """
    ssh_cmd = _build_ssh_cmd(config.ssh_port, config.admin_key_path, config.ssh_timeout)
    cmd = [*ssh_cmd, f"{config.admin_user}@{config.host}", remote_cmd]
    return run_command(cmd, timeout=config.ssh_timeout, log_dir=log_dir, log_prefix=log_prefix)


def check_mount_status(
    config: ArtifactsConfig,
    mount_point: Optional[str] = None,
    log_dir: Optional[Path] = None,
) -> dict[str, Any]:
    """Verify S3 Files NFS mount status, filesystem type, and options via admin SSH.

    :param config: ArtifactsConfig instance.
    :param mount_point: Target mount point path (defaults to config.mount_point).
    :param log_dir: Optional log directory.
    :returns: Dictionary with mount_present, fstype, options, and writeable status.
    """
    target_mount = mount_point or config.mount_point
    # Access a child path to trigger systemd automount before inspecting the backing filesystem.
    res = run_admin_ssh_command(
        config,
        f"stat -- {shlex.quote(target_mount + '/.')} >/dev/null && "
        f"findmnt --json --list --mountpoint {shlex.quote(target_mount)} "
        "--types nfs,nfs4 --output TARGET,FSTYPE",
        log_dir=log_dir,
        log_prefix="mount-findmnt",
    )

    filesystems: list[dict[str, Any]] = []
    error = res.stderr
    if res.exit_code == 0 and not res.timed_out:
        try:
            mount_info = json.loads(res.stdout)
        except json.JSONDecodeError as exc:
            error = f"Invalid findmnt JSON for {target_mount}: {exc}"
        else:
            if isinstance(mount_info, dict) and isinstance(mount_info.get("filesystems"), list):
                filesystems = mount_info["filesystems"]
            else:
                error = f"Missing filesystem list in findmnt output for {target_mount}"

    filesystem = next((
        entry for entry in filesystems
        if isinstance(entry, dict)
        and entry.get("target") == target_mount
        and entry.get("fstype") in ("nfs", "nfs4")
    ), {})
    mount_present = bool(filesystem)
    is_writable = False
    if mount_present:
        res_touch = run_admin_ssh_command(
            config,
            f"test -w {shlex.quote(target_mount)}",
            log_dir=log_dir,
            log_prefix="mount-writable",
        )
        is_writable = res_touch.exit_code == 0 and not res_touch.timed_out

    return {
        "mount_present": mount_present,
        "fstype": filesystem.get("fstype", "unknown"),
        "is_writable": is_writable,
        "mount_point": target_mount,
        "stdout": res.stdout,
        "stderr": error,
    }


def get_boot_id(
    config: ArtifactsConfig,
    log_dir: Optional[Path] = None,
) -> str:
    """Retrieve kernel boot ID via admin SSH.

    :param config: ArtifactsConfig instance.
    :param log_dir: Optional log directory.
    :returns: Boot ID string or empty string on failure.
    """
    res = run_admin_ssh_command(
        config,
        "cat /proc/sys/kernel/random/boot_id",
        log_dir=log_dir,
        log_prefix="get-boot-id",
    )
    if res.exit_code == 0:
        return res.stdout.strip()
    logger.warning(f"Cannot read boot ID from {config.host} (exit {res.exit_code}): {res.stderr}")
    return ""


def reboot_and_wait(
    config: ArtifactsConfig,
    old_boot_id: str,
    log_dir: Optional[Path] = None,
) -> tuple[bool, str]:
    """Reboot over admin SSH and wait for a new boot ID and writable NFS mount.

    :param config: ArtifactsConfig instance.
    :param old_boot_id: Previous boot ID before reboot.
    :param log_dir: Optional log directory.
    :returns: Tuple of (reboot_success, new_boot_id).
    """
    if not config.allow_reboot:
        raise RuntimeError("Reboot testing is not enabled. Pass --artifacts-allow-reboot explicitly.")

    logger.info(f"Triggering reboot on {config.host} with initial boot ID: {old_boot_id}")
    run_admin_ssh_command(
        config,
        "sudo systemctl reboot || sudo reboot",
        log_dir=log_dir,
        log_prefix="trigger-reboot",
    )

    new_boot_id = ""

    def check_recovery() -> Result[str, str]:
        nonlocal new_boot_id
        boot_id = get_boot_id(config, log_dir=log_dir)
        if not boot_id:
            return Result.Error(f"Cannot read boot ID from {config.host}; see get-boot-id diagnostics")
        if boot_id == old_boot_id:
            return Result.Error(f"Host {config.host} boot ID is unchanged")

        new_boot_id = boot_id
        mount = check_mount_status(config, log_dir=log_dir)
        if not mount["mount_present"] or not mount["is_writable"]:
            return Result.Error(
                f"NFS mount {config.mount_point} has not recovered on {config.host} "
                f"(type {mount['fstype']}, writable {mount['is_writable']}): {mount['stderr']}"
            )
        return Result.Ok(boot_id)

    try:
        wait(
            f"{config.host} reboot and NFS recovery",
            check_recovery,
            timeout=config.reboot_timeout,
            tick=config.reboot_poll_interval,
        )
    except GlueError as exc:
        logger.error(f"Reboot verification failed for {config.host}: {exc}")
        return False, new_boot_id

    logger.info(f"Host {config.host} rebooted with writable NFS and new boot ID: {new_boot_id}")
    return True, new_boot_id


def cleanup_probe(
    config: ArtifactsConfig,
    probe: ProbePayload,
    log_dir: Optional[Path] = None,
) -> bool:
    """Targeted cleanup of the run's unique probe directory only.

    Confined strictly to `probe.relative_dir` under `probe_namespace`.

    :param config: ArtifactsConfig instance.
    :param probe: ProbePayload instance to delete.
    :param log_dir: Optional log directory.
    :returns: True if cleanup succeeded, False otherwise.
    """
    # Strict path check: relative_dir must start with configured probe_namespace and not contain traversal
    if not probe.relative_dir.startswith(config.probe_namespace) or ".." in probe.relative_dir:
        logger.error(f"Refusing to cleanup invalid probe path: {probe.relative_dir}")
        return False

    remote_cmd = f"rm -rf {config.mount_point}/{probe.relative_dir}"
    res = run_admin_ssh_command(
        config,
        remote_cmd,
        log_dir=log_dir,
        log_prefix="cleanup-probe",
    )

    if res.exit_code != 0:
        logger.warning(f"Probe cleanup failed for {probe.relative_dir}: {res.stderr}")
        return False
    return True
