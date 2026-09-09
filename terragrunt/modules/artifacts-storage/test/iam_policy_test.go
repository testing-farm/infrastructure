package test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

const (
	policyDirectory = "../../../environments/production/artifacts-redhat/storage/iam"
	serviceRole     = "arn:aws:iam::727920394381:role/testing-farm-artifacts-redhat-s3files-service-role"
	clientRole      = "arn:aws:iam::727920394381:role/testing-farm-artifacts-redhat-ec2-client-role"
	profile         = "arn:aws:iam::727920394381:instance-profile/testing-farm-artifacts-redhat-instance-profile"
	boundary        = "arn:aws:iam::727920394381:policy/arr-testing-farm.prod.role-boundary"
	clientPolicy    = "arn:aws:iam::aws:policy/AmazonS3FilesClientFullAccess"
	bucket          = "arn:aws:s3:::testing-farm-artifacts-redhat"
	backend         = "testing-farm-artifacts-redhat"
)

type statement struct {
	Sid       string
	Effect    string
	Action    json.RawMessage
	Resource  json.RawMessage
	Condition map[string]map[string]json.RawMessage
}

type policy struct {
	Version   string
	Statement []statement
}

func values(t *testing.T, raw json.RawMessage) []string {
	t.Helper()
	var one string
	if json.Unmarshal(raw, &one) == nil {
		return []string{one}
	}
	var many []string
	if err := json.Unmarshal(raw, &many); err != nil || len(many) == 0 {
		t.Fatalf("expected a non-empty string or string array: %s", raw)
	}
	return many
}

func requireValues(t *testing.T, raw json.RawMessage, expected ...string) {
	t.Helper()
	actual := values(t, raw)
	sort.Strings(actual)
	sort.Strings(expected)
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("got %v, want %v", actual, expected)
	}
}

func loadPolicy(t *testing.T, name string) policy {
	t.Helper()
	content, err := os.ReadFile(filepath.Join(policyDirectory, name+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var compact bytes.Buffer
	if err := json.Compact(&compact, content); err != nil {
		t.Fatal(err)
	}
	if compact.Len() > 6144 {
		t.Fatalf("%s exceeds IAM's managed-policy limit: %d characters", name, compact.Len())
	}
	var p policy
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&p); err != nil {
		t.Fatal(err)
	}
	if p.Version != "2012-10-17" || len(p.Statement) == 0 {
		t.Fatal("missing policy version or statements")
	}
	seen := map[string]bool{}
	for _, s := range p.Statement {
		if s.Sid == "" || seen[s.Sid] || (s.Effect != "Allow" && s.Effect != "Deny") {
			t.Fatalf("invalid or duplicate statement: %s", s.Sid)
		}
		seen[s.Sid] = true
		values(t, s.Action)
		values(t, s.Resource)
	}
	return p
}

func findStatement(t *testing.T, p policy, sid string) statement {
	t.Helper()
	for _, s := range p.Statement {
		if s.Sid == sid {
			return s
		}
	}
	t.Fatalf("missing statement %s", sid)
	return statement{}
}

// These tests check the checked-in authorization contract, not AWS's policy evaluator.
// Access Analyzer, IAM simulation and a real plan remain administrator acceptance steps.
func TestDeploymentPoliciesHaveNoBlanketActions(t *testing.T) {
	for _, name := range []string{"deployment-iam", "deployment-storage", "deployment-network"} {
		t.Run(name, func(t *testing.T) {
			for _, s := range loadPolicy(t, name).Statement {
				for _, action := range values(t, s.Action) {
					if strings.ContainsAny(action, "*?") || strings.HasPrefix(action, "elasticfilesystem:") {
						t.Errorf("%s contains a blanket action or EFS substitute: %s", s.Sid, action)
					}
				}
				for _, resource := range values(t, s.Resource) {
					if resource == "*" {
						requireValues(t, s.Condition["StringEquals"]["aws:RequestedRegion"], "us-east-1")
						if s.Sid != "ReadNetwork" && s.Sid != "CreateTaggedFileSystem" && s.Sid != "ListServiceEventRules" {
							t.Errorf("unexpected account-wide scope: %s", s.Sid)
						}
					}
				}
			}
		})
	}
}

func TestIAMDelegationIsBounded(t *testing.T) {
	p := loadPolicy(t, "deployment-iam")
	for _, s := range p.Statement {
		for _, resource := range values(t, s.Resource) {
			if resource != serviceRole && resource != clientRole && resource != profile && resource != boundary {
				t.Errorf("unexpected IAM resource: %s", resource)
			}
			if s.Effect == "Allow" && resource == boundary {
				t.Error("deployer must not manage the boundary policy")
			}
		}
	}
	for _, sid := range []string{"CreateBoundedRoles", "ManageBoundedRolePolicies"} {
		s := findStatement(t, p, sid)
		requireValues(t, s.Resource, serviceRole, clientRole)
		requireValues(t, s.Condition["StringEquals"]["iam:PermissionsBoundary"], boundary)
	}
	for _, sid := range []string{"DenyMissingOrDifferentBoundary", "DenyBoundaryRemoval", "DenyBoundaryPolicyMutation"} {
		if findStatement(t, p, sid).Effect != "Deny" {
			t.Errorf("%s must explicitly deny the operation", sid)
		}
	}
	s := findStatement(t, p, "DenyMissingOrDifferentBoundary")
	requireValues(t, s.Condition["StringNotEquals"]["iam:PermissionsBoundary"], boundary)
	requireValues(t, s.Action, "iam:CreateRole", "iam:PutRolePermissionsBoundary")
	requireValues(t, findStatement(t, p, "DenyBoundaryRemoval").Action, "iam:DeleteRolePermissionsBoundary")
	requireValues(t, findStatement(t, p, "DenyBoundaryPolicyMutation").Resource, boundary)
	s = findStatement(t, p, "AttachOnlyClientPolicy")
	requireValues(t, s.Resource, clientRole)
	requireValues(t, s.Condition["ArnEquals"]["iam:PolicyARN"], clientPolicy)
	for _, tc := range []struct{ sid, role, service string }{
		{"PassServiceRole", serviceRole, "elasticfilesystem.amazonaws.com"},
		{"PassClientRole", clientRole, "ec2.amazonaws.com"},
	} {
		s = findStatement(t, p, tc.sid)
		requireValues(t, s.Action, "iam:PassRole")
		requireValues(t, s.Resource, tc.role)
		requireValues(t, s.Condition["StringEquals"]["iam:PassedToService"], tc.service)
	}
}

func TestRuntimeBoundarySeparatesRoles(t *testing.T) {
	p := loadPolicy(t, "role-boundary")
	for _, s := range p.Statement {
		if s.Effect != "Allow" {
			t.Fatalf("unexpected runtime boundary effect: %s", s.Sid)
		}
		principal := values(t, s.Condition["ArnEquals"]["aws:PrincipalArn"])
		if len(principal) != 1 || (principal[0] != serviceRole && principal[0] != clientRole) {
			t.Fatalf("boundary must distinguish the runtime roles: %s", s.Sid)
		}
		for _, action := range values(t, s.Action) {
			if principal[0] == clientRole {
				if action != "s3:ListBucket" && action != "s3:GetObject*" && action != "s3files:ClientMount" && action != "s3files:ClientWrite" && action != "s3files:ClientRootAccess" {
					t.Errorf("unexpected client privilege: %s", action)
				}
			} else if !strings.HasPrefix(action, "s3:") && !strings.HasPrefix(action, "events:") {
				t.Errorf("unexpected service privilege: %s", action)
			}
		}
	}
	s := findStatement(t, p, "ClientMountAccess")
	requireValues(t, s.Resource, "arn:aws:s3files:us-east-1:727920394381:file-system/*")
	requireValues(t, s.Condition["StringEquals"]["aws:ResourceTag/StorageBackend"], backend)
	requireValues(t, findStatement(t, p, "ServiceObjectSync").Resource, bucket+"/*")
	requireValues(t, findStatement(t, p, "ClientObjectReads").Resource, bucket+"/*")
}

func TestOwnershipTagsCannotBeUsedToAdoptUnrelatedResources(t *testing.T) {
	for _, tc := range []struct{ name, create, tag, update, createKey, createValue, resourceKey string }{
		{"deployment-storage", "CreateTaggedFileSystem", "TagFileSystemOnCreation", "UpdateNonAuthorizationFileSystemTags", "s3files:CreateAction", "CreateFileSystem", "aws:ResourceTag/StorageBackend"},
		{"deployment-network", "CreateTaggedSecurityGroups", "TagSecurityGroupsOnCreation", "UpdateNonAuthorizationSecurityGroupTags", "ec2:CreateAction", "CreateSecurityGroup", "ec2:ResourceTag/StorageBackend"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := loadPolicy(t, tc.name)
			for _, sid := range []string{tc.create, tc.tag} {
				s := findStatement(t, p, sid)
				requireValues(t, s.Condition["StringEquals"]["aws:RequestTag/StorageBackend"], backend)
			}
			s := findStatement(t, p, tc.tag)
			requireValues(t, s.Condition["StringEquals"][tc.createKey], tc.createValue)
			s = findStatement(t, p, tc.update)
			requireValues(t, s.Condition["StringEquals"][tc.resourceKey], backend)
			// IAM tag condition-key names are case-insensitive. Protect spelling variants too.
			requireValues(t, s.Condition["ForAllValues:StringNotEqualsIgnoreCase"]["aws:TagKeys"], "StorageBackend")
		})
	}
}

func TestProvisioningScopes(t *testing.T) {
	p := loadPolicy(t, "deployment-storage")
	for _, sid := range []string{"CreateAndTagBucket", "ManageBucketConfiguration"} {
		requireValues(t, findStatement(t, p, sid).Resource, bucket)
	}
	s := findStatement(t, p, "ManageOwnedFileSystem")
	requireValues(t, s.Resource, "arn:aws:s3files:us-east-1:727920394381:file-system/*")
	requireValues(t, s.Condition["StringEquals"]["aws:ResourceTag/StorageBackend"], backend)
	p = loadPolicy(t, "deployment-network")
	for _, sid := range []string{"ManageOwnedSecurityGroups", "UseOwnedInterfaceSecurityGroups"} {
		s = findStatement(t, p, sid)
		requireValues(t, s.Resource, "arn:aws:ec2:us-east-1:727920394381:security-group/*")
		requireValues(t, s.Condition["StringEquals"]["ec2:ResourceTag/StorageBackend"], backend)
		requireValues(t, s.Condition["ArnEquals"]["ec2:Vpc"], "arn:aws:ec2:us-east-1:727920394381:vpc/vpc-008152fcfb0333f30")
	}
	requireValues(t, findStatement(t, p, "CreateSecurityGroupsInApprovedVpc").Resource, "arn:aws:ec2:us-east-1:727920394381:vpc/vpc-008152fcfb0333f30")
	requireValues(t, findStatement(t, p, "UseApprovedSubnet").Resource, "arn:aws:ec2:us-east-1:727920394381:subnet/subnet-036ad213c3fb0eb7e")
	s = findStatement(t, p, "ManageInterfacesInApprovedSubnet")
	requireValues(t, s.Condition["ArnEquals"]["ec2:Subnet"], "arn:aws:ec2:us-east-1:727920394381:subnet/subnet-036ad213c3fb0eb7e")
}
