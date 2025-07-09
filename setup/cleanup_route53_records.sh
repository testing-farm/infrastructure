#!/bin/bash -e

#
# Cleanup Route53 records that match staging-\d+ or gitlab-ci patterns
# from the testing-farm.io hosted zone
#
# Usage: ./cleanup_route53_records.sh [--dry-run]
#

# Default profile to use
profile=${AWS_PROFILE:-fedora_us_east_1}

# Check for dry run mode
DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
    echo "[+] Running in DRY RUN mode - no changes will be made"
fi

# Specific hosted zone for testing-farm.io
zone_id="Z0711647188EWQGM661TT"
zone_name="testing-farm.io"

# Pattern to match records for cleanup
staging_pattern="staging-[0-9]+"
gitlab_ci_pattern="gitlab-ci"

# Batch size for pagination
BATCH_SIZE=100

# Function to process a single record
process_record() {
    local record_name=$1
    local records=$2

    echo "    [+] Processing record: $record_name"

    # Get all records with this name (there might be multiple types)
    echo "$records" | jq -c ".ResourceRecordSets[] | select(.Name == \"$record_name\")" | while read -r record_details; do
        record_type=$(echo "$record_details" | jq -r ".Type")

        if [ "$record_type" != "A" ] && [ "$record_type" != "CNAME" ] && [ "$record_type" != "TXT" ]; then
            echo "    [!] Skipping $record_name (unsupported record type: $record_type)"
            continue
        fi

        # Create change batch for deletion
        change_batch=$(echo "$record_details" | jq '{
            Changes: [{
                Action: "DELETE",
                ResourceRecordSet: .
            }]
        }')

        if [ "$DRY_RUN" = true ]; then
            echo "    [DRY RUN] Would delete $record_type record: $record_name"
        else
            echo "    [+] Deleting $record_type record: $record_name"

            # Execute the deletion
            change_id=$(aws --profile "$profile" route53 change-resource-record-sets \
                --hosted-zone-id "$zone_id" \
                --change-batch "$change_batch" \
                --query "ChangeInfo.Id" --output text)

            if [ $? -eq 0 ]; then
                echo "    [+] Successfully submitted deletion for $record_name (Change ID: $change_id)"
            else
                echo "    [!] Failed to delete $record_name"
            fi
        fi
    done
}

echo "[+] Processing hosted zone: $zone_name (batch size: $BATCH_SIZE)"

# Initialize variables for pagination
next_token=""
batch_count=0

# Loop through all pages of records
while true; do
    batch_count=$((batch_count + 1))
    echo "  [+] Processing batch $batch_count..."

    # Build command with or without pagination token
    if [ -n "$next_token" ]; then
        records=$(aws --profile "$profile" route53 list-resource-record-sets --hosted-zone-id "$zone_id" --max-items $BATCH_SIZE --starting-token "$next_token" --output json)
    else
        records=$(aws --profile "$profile" route53 list-resource-record-sets --hosted-zone-id "$zone_id" --max-items $BATCH_SIZE --output json)
    fi

    # Find records matching our patterns in this batch
    staging_records=$(echo "$records" | jq -r ".ResourceRecordSets[]? | select(.Name | test(\"$staging_pattern\")) | .Name")
    gitlab_ci_records=$(echo "$records" | jq -r ".ResourceRecordSets[]? | select(.Name | test(\"$gitlab_ci_pattern\")) | .Name")

    # Combine records from this batch
    batch_records=$(echo -e "$staging_records\n$gitlab_ci_records" | grep -v "^$" | sort -u)

    if [ -z "$batch_records" ]; then
        echo "  [+] No matching records found in batch $batch_count"
        # Check if there are more pages
        next_token=$(echo "$records" | jq -r ".NextToken // empty")
        if [ -z "$next_token" ]; then
            break
        fi
        continue
    fi

    echo "  [+] Found $(echo "$batch_records" | wc -l) records to process in batch $batch_count"

    # Process each matching record in this batch
    echo "$batch_records" | while read -r record_name; do
        if [ -n "$record_name" ]; then
            process_record "$record_name" "$records"
        fi
    done

    # Check if there are more pages
    next_token=$(echo "$records" | jq -r ".NextToken // empty")
    if [ -z "$next_token" ]; then
        break
    fi
done

echo "[+] Route53 cleanup completed"
