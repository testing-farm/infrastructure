#!/bin/bash

set -x -e

gitlab_api_call() {
    curl -X ${2:-GET} -s --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" --url "https://gitlab.com/api/v4/projects/${CI_PROJECT_ID}${1}" ${3}
}

find_commit_mrs() {
	gitlab_api_call "/repository/commits/${CI_COMMIT_SHA}/merge_requests" | jq '[.[] | select(.state == "merged" and (.labels[] | contains("Backport to release")))] | first | .iid'
}

find_mr_commits() {
	gitlab_api_call "/merge_requests/${1}/commits" | jq -r '.[].id'
}

create_mr() {
	gitlab_api_call "/merge_requests" "POST" "--data \"source_branch=${3}\" \"--data target_branch=${4}\" --data \"title=${1}\" --data \"description=${2}\""
}

MR_IID="$(find_commit_mrs)"

[ -z "${MR_IID}" ] && echo "No MR to backport found" && exit 0

COMMITS="$(find_mr_commits ${MR_IID})"

[ -z "${COMMITS}" ] && echo "Parsing commits for !${MR_IID} failed" && exit 1

RELEASE_BRANCH="$(git branch --list --format='%(refname:short)' test-release/* | sort -r | head -n1)"
BACKPORT_BRANCH="cherry-pick-${MR_IID}-${RELEASE_BRANCH}"

[ -z "${RELEASE_BRANCH}" ] && echo "Could not find a valid release branch" && exit 1

git config --global user.name "testing-farm-bot"

git switch -c "${BACKPORT_BRANCH}" ${RELEASE_BRANCH}
git cherry-pick ${COMMITS}

git push -u origin "${BACKPORT_BRANCH}"

create_mr "" "" "${BACKPORT_BRANCH}" "${RELEASE_BRANCH}"
