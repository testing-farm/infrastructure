#!/bin/bash -e

#
# Cleanup leftover loadbalancers from Testing Farm older then today.
#

# Regions to clenup
profiles="fedora_us_east_1 fedora_us_east_2"
today=$(date +%Y-%m-%d)
tag_contains="testing-farm"

aws_elb() {
    local profile=$1
    shift
    aws --profile "$profile" elb "$@"
}
export -f aws_elb

# Terminate load balancers
for profile in $profiles; do
    aws_elb "$profile" describe-load-balancers | \
        jq -r ".LoadBalancerDescriptions[] | select((.Instances | length == 0) and .CreatedTime < \"$today\") | .LoadBalancerName" | \
        parallel -r aws_elb "$profile" describe-tags --load-balancer-names | \
        jq -r ".TagDescriptions[] | select(.Tags[].Key | contains(\"$tag_contains\")) | .LoadBalancerName" | \
        parallel -r -I{} "bash -c \"echo 'Terminating LB {} from $profile'; aws_elb $profile delete-load-balancer --load-balancer-name {}\""
done
