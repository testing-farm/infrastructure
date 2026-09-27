"""Offline S3 synchronization checks using the SDK's external API stubber."""

from io import BytesIO
from pathlib import Path
from unittest.mock import patch

import boto3
from botocore.exceptions import ClientError
from botocore.response import StreamingBody
from botocore.stub import Stubber
import pytest

from tests.artifacts.helpers import ArtifactsConfig, create_probe, verify_probe_s3


def test_s3_readback_waits_for_expected_bytes(tmp_path: Path) -> None:
    """HTTPS visibility is supplemented by eventual bytes in the expected S3 bucket."""
    config = ArtifactsConfig(s3_bucket="artifact-test-bucket")
    probe = create_probe(base_dir=tmp_path)
    client = boto3.client("s3", region_name="us-east-1", aws_access_key_id="offline", aws_secret_access_key="offline")
    key = f"{probe.relative_dir}/{probe.filename}"
    expected = {"Bucket": "artifact-test-bucket", "Key": key}
    content = probe.content.encode()
    with Stubber(client) as stubber:
        stubber.add_client_error("get_object", service_error_code="NoSuchKey", http_status_code=404, expected_params=expected)
        stubber.add_response("get_object", {"Body": StreamingBody(BytesIO(b"stale"), 5)}, expected)
        stubber.add_response("get_object", {"Body": StreamingBody(BytesIO(content), len(content))}, expected)
        with patch("time.sleep"):
            assert verify_probe_s3(config, probe, tmp_path, client=client) is True
        stubber.assert_no_pending_responses()


def test_s3_readback_fails_at_deadline(tmp_path: Path) -> None:
    """A stale object must not pass or extend synchronization polling indefinitely."""
    config = ArtifactsConfig(s3_bucket="artifact-test-bucket", s3_sync_timeout=1)
    probe = create_probe(base_dir=tmp_path)
    client = boto3.client("s3", region_name="us-east-1", aws_access_key_id="offline", aws_secret_access_key="offline")
    clock = [0.0]

    def advance(seconds: float) -> None:
        clock[0] += seconds

    with Stubber(client) as stubber:
        stubber.add_response("get_object", {"Body": StreamingBody(BytesIO(b"stale"), 5)})
        with patch("time.time", side_effect=lambda: clock[0]), patch("time.sleep", side_effect=advance):
            assert verify_probe_s3(config, probe, tmp_path, client=client) is False
        stubber.assert_no_pending_responses()
    assert "S3 probe bytes differ" in (tmp_path / f"s3-sync-{probe.probe_id}.log").read_text()


def test_s3_permission_failure_is_not_retried(tmp_path: Path) -> None:
    """An authorization failure is not disguised as delayed synchronization."""
    config = ArtifactsConfig(s3_bucket="artifact-test-bucket")
    probe = create_probe(base_dir=tmp_path)
    client = boto3.client("s3", region_name="us-east-1", aws_access_key_id="offline", aws_secret_access_key="offline")
    with Stubber(client) as stubber:
        stubber.add_client_error("get_object", service_error_code="AccessDenied", http_status_code=403)
        with pytest.raises(ClientError, match="AccessDenied"):
            verify_probe_s3(config, probe, tmp_path, client=client)
        stubber.assert_no_pending_responses()
