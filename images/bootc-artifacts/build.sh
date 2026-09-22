#!/bin/bash
# Import the artifact-server qcow2 into an AWS AMI.
#
# The container image and the qcow2 are built on Testing Farm via the tmt plans
# in this directory (container.fmf, qcow2.fmf) - see README.adoc. This script
# performs the one step Testing Farm does not cover: importing the built qcow2
# into an AMI for the deploy (TFT-4797), which consumes it as ARTIFACTS_SERVER_AMI.
#
# Usage:
#   ./build.sh <disk.qcow2>
#
# Env:
#   AWS_BUCKET   S3 bucket used to stage the disk image for import   (required)
#   AWS_REGION   AMI region                                          (default us-east-1)
#   AMI_NAME     name for the registered AMI                (default artifacts-bootc-<ts>)
#   AWS_PROFILE  AWS profile with EC2/S3 VM import permissions       (as usual)
#
# Prereqs:
#   - qemu-img (qcow2 -> raw conversion; EC2 import does not accept qcow2)
#   - AWS credentials with the "vmimport" service role configured, see
#     https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html
set -euo pipefail

cd "$(dirname "$0")"

QCOW2="${1:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AMI_NAME="${AMI_NAME:-artifacts-bootc-$(date +%Y%m%d-%H%M%S)}"

if [ -z "$QCOW2" ] || [ ! -f "$QCOW2" ]; then
    echo "Usage: $0 <disk.qcow2>" >&2
    echo "Error: qcow2 file '$QCOW2' not found. Build it first with 'make image/artifacts-bootc/qcow2'." >&2
    exit 1
fi

if [ -z "${AWS_BUCKET:-}" ]; then
    echo "Error: AWS_BUCKET must be set to stage the disk image for import." >&2
    exit 1
fi

work="$(mktemp -d)"
raw="$work/artifacts-bootc.raw"
s3_key="artifacts-bootc-import/$(basename "$AMI_NAME").raw"
trap 'rm -rf "$work"; aws s3 rm "s3://$AWS_BUCKET/$s3_key" --region "$AWS_REGION" >/dev/null 2>&1 || true' EXIT

echo "🔧 converting $QCOW2 to raw (EC2 import does not accept qcow2)"
qemu-img convert -f qcow2 -O raw "$QCOW2" "$raw"

echo "⬆️  uploading disk image to s3://$AWS_BUCKET/$s3_key"
aws s3 cp "$raw" "s3://$AWS_BUCKET/$s3_key" --region "$AWS_REGION"

echo "💿 importing snapshot in $AWS_REGION"
import_task=$(aws ec2 import-snapshot \
    --region "$AWS_REGION" \
    --description "$AMI_NAME" \
    --disk-container "Format=raw,UserBucket={S3Bucket=$AWS_BUCKET,S3Key=$s3_key}" \
    --query 'ImportTaskId' --output text)
echo "   import task: $import_task"

echo "⏳ waiting for snapshot import to complete"
while :; do
    read -r status progress message <<<"$(aws ec2 describe-import-snapshot-tasks \
        --region "$AWS_REGION" --import-task-ids "$import_task" \
        --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.[Status,Progress,StatusMessage]' \
        --output text)"
    case "$status" in
        completed) echo "   snapshot import completed"; break ;;
        deleted|deleting|error) echo "Error: snapshot import $status: $message" >&2; exit 1 ;;
        *) echo "   status=$status progress=${progress}% ${message}"; sleep 30 ;;
    esac
done

snapshot_id=$(aws ec2 describe-import-snapshot-tasks \
    --region "$AWS_REGION" --import-task-ids "$import_task" \
    --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)
echo "   snapshot: $snapshot_id"

echo "🏷️  registering AMI $AMI_NAME"
# bootc RHEL images boot via UEFI; ENA + NVMe are standard on modern instance types.
ami_id=$(aws ec2 register-image \
    --region "$AWS_REGION" \
    --name "$AMI_NAME" \
    --description "RHEL 10 bootc artifact storage server (TFT-4795)" \
    --architecture x86_64 \
    --root-device-name /dev/xvda \
    --boot-mode uefi \
    --ena-support \
    --virtualization-type hvm \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={SnapshotId=$snapshot_id,VolumeType=gp3,DeleteOnTermination=true}" \
    --query 'ImageId' --output text)

echo "✅ AMI build finished: $ami_id"
echo "   Pass it to TFT-4797 as ARTIFACTS_SERVER_AMI (consumed by"
echo "   terragrunt/environments/production/artifacts-redhat/ec2/terragrunt.hcl)."
