"""Live on-demand lifecheck tests for Testing Farm artifact server."""

from __future__ import annotations

import logging
from pathlib import Path

import pytest

from tests.artifacts.helpers import (
    ArtifactsConfig,
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
    matches_san,
    reboot_and_wait,
    resolve_dns,
    upload_probe_rsync,
)

logger = logging.getLogger(__name__)


@pytest.fixture(autouse=True)
def require_live(artifacts_config: ArtifactsConfig) -> None:
    """Ensure live tests only run when --live-artifacts is explicitly passed.

    :param artifacts_config: ArtifactsConfig instance.
    """
    if not artifacts_config.is_live:
        pytest.skip("Live infrastructure execution disabled. Pass --live-artifacts to execute.")


@pytest.mark.artifacts
@pytest.mark.live
def test_dns_resolution(artifacts_config: ArtifactsConfig, artifact_dir: Path) -> None:
    """Verify that the artifact server hostname resolves to an expected private IP."""
    resolved_ips = resolve_dns(artifacts_config.host)
    assert resolved_ips, f"Failed to resolve DNS for host: {artifacts_config.host}"
    logger.info(f"Resolved {artifacts_config.host} -> {resolved_ips}")

    if artifacts_config.private_ip:
        assert artifacts_config.private_ip in resolved_ips, (
            f"Expected private IP {artifacts_config.private_ip} not found in resolved IPs: {resolved_ips}"
        )


@pytest.mark.artifacts
@pytest.mark.live
def test_http_redirect(artifacts_config: ArtifactsConfig, artifact_dir: Path) -> None:
    """Verify that plaintext HTTP port 80 requests are redirected to HTTPS port 443."""
    res = check_http_redirect(
        host=artifacts_config.host,
        port=artifacts_config.http_port,
        timeout=artifacts_config.request_timeout,
    )
    assert res["is_redirect_to_https"], (
        f"HTTP redirect failed: status={res.get('status_code')}, location={res.get('location')}"
    )


@pytest.mark.artifacts
@pytest.mark.live
def test_https_tls(artifacts_config: ArtifactsConfig, artifact_dir: Path) -> None:
    """Verify TLS certificate validity, valid chain, and Subject Alternative Name."""
    res = check_https_tls(
        host=artifacts_config.host,
        port=artifacts_config.https_port,
        ca_cert=artifacts_config.ca_cert_path,
        timeout=artifacts_config.request_timeout,
    )
    assert res["tls_valid"], f"TLS validation failed: {res.get('error')}"

    san_list = res.get("subjectAltName", [])
    assert any(
        matches_san(artifacts_config.host, san)
        for san in san_list
    ), f"Hostname {artifacts_config.host} not covered by certificate SANs: {san_list}"


@pytest.mark.artifacts
@pytest.mark.live
def test_autoindex_enabled(artifacts_config: ArtifactsConfig, artifact_dir: Path) -> None:
    """Verify nginx autoindex directory listing is enabled."""
    res = check_autoindex(config=artifacts_config, path="/")
    assert res["status_code"] == 200, f"Autoindex request returned status {res['status_code']}"
    assert res["autoindex_enabled"], "Autoindex HTML markers not detected in response body"


@pytest.mark.artifacts
@pytest.mark.live
def test_cors_headers(artifacts_config: ArtifactsConfig, artifact_dir: Path) -> None:
    """Verify CORS headers are returned for cross-origin web requests."""
    res = check_cors_headers(config=artifacts_config, path="/")
    assert res["cors_ok"], f"CORS headers missing or incorrect: {res.get('allow_origin')}"


@pytest.mark.artifacts
@pytest.mark.live
def test_restricted_ssh_rejected(artifacts_config: ArtifactsConfig, artifact_dir: Path) -> None:
    """Verify interactive shells and unauthorized commands are rejected by the restricted SSH user."""
    res = check_restricted_ssh_access(config=artifacts_config, log_dir=artifact_dir)
    assert res["shell_rejected"], (
        f"Shell restriction not verified (exit {res['shell_exit_code']}): {res['shell_stderr']}"
    )
    assert res["command_rejected"], (
        f"Command restriction not verified (exit {res['command_exit_code']}): {res['command_stderr']}"
    )


@pytest.mark.artifacts
@pytest.mark.live
def test_mount_status(artifacts_config: ArtifactsConfig, artifact_dir: Path) -> None:
    """Verify S3 Files NFS mount presence and writeability via admin SSH."""
    res = check_mount_status(config=artifacts_config, mount_point=artifacts_config.mount_point, log_dir=artifact_dir)
    assert res["mount_present"], f"S3 Files NFS mount not found at {artifacts_config.mount_point}: {res.get('stderr')}"
    assert res["is_writable"], f"{artifacts_config.mount_point} directory is not writable"


@pytest.mark.artifacts
@pytest.mark.live
def test_probe_upload_and_readback(
    artifacts_config: ArtifactsConfig,
    probe_workspace: tuple[ProbePayload, Path],
    artifact_dir: Path,
) -> None:
    """Upload a unique probe via restricted rsync-over-SSH and verify immediate first-attempt HTTPS read-back."""
    probe, temp_dir = probe_workspace

    # Upload probe via restricted rsync-over-SSH
    upload_res = upload_probe_rsync(
        config=artifacts_config,
        probe=probe,
        temp_dir=temp_dir,
        log_dir=artifact_dir,
    )
    assert upload_res.exit_code == 0, f"rsync upload failed (exit {upload_res.exit_code}): {upload_res.stderr}"

    try:
        # Immediate single-attempt HTTPS retrieval without retry
        status, body, latency_ms, matches = fetch_probe_https(
            config=artifacts_config,
            probe=probe,
            log_dir=artifact_dir,
        )
        logger.info(f"Probe read-back completed in {latency_ms:.2f} ms (status {status})")

        assert status == 200, f"HTTPS fetch returned status {status}: {body}"
        assert matches, f"Retrieved probe body did not match uploaded payload. Got:\n{body}"

        # The same key must be able to upload but not download the verified probe.
        restriction = check_rsync_write_only(artifacts_config, probe, temp_dir, artifact_dir)
        assert restriction["download_rejected"], (
            f"Write-only rsync restriction not verified (exit {restriction['exit_code']}): "
            f"{restriction['stderr']}"
        )
    finally:
        # Confined cleanup of probe directory
        cleanup_success = cleanup_probe(config=artifacts_config, probe=probe, log_dir=artifact_dir)
        if not cleanup_success:
            logger.warning(f"Probe cleanup could not remove {probe.relative_dir}")


@pytest.mark.artifacts
@pytest.mark.live
@pytest.mark.reboot
def test_reboot_and_persistence(
    artifacts_config: ArtifactsConfig,
    probe_workspace: tuple[ProbePayload, Path],
    artifact_dir: Path,
) -> None:
    """Opt-in reboot test verifying persistence of pre-reboot probe and post-reboot upload capability."""
    if not artifacts_config.allow_reboot:
        pytest.skip("Reboot validation is opt-in. Pass --artifacts-allow-reboot to execute.")

    probe1, temp_dir = probe_workspace

    # 1. Upload pre-reboot probe and verify immediate read-back
    upload_res = upload_probe_rsync(artifacts_config, probe1, temp_dir, artifact_dir)
    assert upload_res.exit_code == 0, f"Pre-reboot upload failed: {upload_res.stderr}"

    status, _, _, matches = fetch_probe_https(artifacts_config, probe1, artifact_dir)
    assert status == 200 and matches, "Pre-reboot HTTPS fetch failed"

    # 2. Record initial boot ID
    old_boot_id = get_boot_id(artifacts_config, artifact_dir)
    assert old_boot_id, "Failed to retrieve initial kernel boot ID"

    try:
        # 3. Trigger reboot and wait for recovery with new boot ID
        reboot_ok, new_boot_id = reboot_and_wait(artifacts_config, old_boot_id, artifact_dir)
        assert reboot_ok, f"Reboot failed or timed out. New boot ID: '{new_boot_id}'"
        assert new_boot_id != old_boot_id, f"Boot ID unchanged after reboot: {new_boot_id}"

        # 4. Verify pre-reboot probe is still accessible over HTTPS after reboot
        post_status, _, _, post_matches = fetch_probe_https(artifacts_config, probe1, artifact_dir)
        assert post_status == 200 and post_matches, "Pre-reboot probe is inaccessible after reboot"

        # 5. Create and upload post-reboot probe to verify new writes succeed
        probe2 = create_probe(base_dir=temp_dir)
        upload2_res = upload_probe_rsync(artifacts_config, probe2, temp_dir, artifact_dir)
        assert upload2_res.exit_code == 0, f"Post-reboot upload failed: {upload2_res.stderr}"

        status2, _, _, matches2 = fetch_probe_https(artifacts_config, probe2, artifact_dir)
        assert status2 == 200 and matches2, "Post-reboot probe HTTPS fetch failed"
    finally:
        cleanup_probe(artifacts_config, probe1, artifact_dir)
        if "probe2" in locals():
            cleanup_probe(artifacts_config, probe2, artifact_dir)
