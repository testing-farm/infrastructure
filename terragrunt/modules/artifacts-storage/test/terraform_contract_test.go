package test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Plan the real production inputs/provider tags against local read-only API stubs.
// No backend, real credentials, resource refresh or apply is used.
func TestTerraformMatchesDeploymentPolicies(t *testing.T) {
	terraform, err := exec.LookPath("terraform")
	if err != nil {
		t.Fatal("terraform is required for the production contract test")
	}
	terragrunt, err := exec.LookPath("terragrunt")
	if err != nil {
		t.Fatal("terragrunt is required for the production contract test")
	}
	work := t.TempDir()
	leaf, err := filepath.Abs(filepath.Dir(policyDirectory))
	if err != nil {
		t.Fatal(err)
	}
	rendered := filepath.Join(work, "terragrunt.json")
	runTerraformCommand(t, work, nil, terragrunt, "render-json", "--terragrunt-working-dir", leaf,
		"--terragrunt-json-out", rendered, "--terragrunt-non-interactive")
	var configuration struct {
		Inputs   map[string]any `json:"inputs"`
		Generate map[string]struct {
			Contents string `json:"contents"`
		} `json:"generate"`
	}
	readJSON(t, rendered, &configuration)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Error(err)
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "text/xml")
		switch r.Form.Get("Action") {
		case "GetUser":
			fmt.Fprint(w, `<GetUserResponse xmlns="https://iam.amazonaws.com/doc/2010-05-08/"><GetUserResult><User><Path>/</Path><UserName>offline-test</UserName><UserId>offline-test</UserId><Arn>arn:aws:iam::727920394381:user/offline-test</Arn></User></GetUserResult></GetUserResponse>`)
		case "GetCallerIdentity":
			fmt.Fprint(w, `<GetCallerIdentityResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/"><GetCallerIdentityResult><Arn>arn:aws:iam::727920394381:user/offline-test</Arn><UserId>offline-test</UserId><Account>727920394381</Account></GetCallerIdentityResult></GetCallerIdentityResponse>`)
		case "DescribeSubnets":
			fmt.Fprintf(w, `<DescribeSubnetsResponse xmlns="http://ec2.amazonaws.com/doc/2016-11-15/"><subnetSet><item><subnetId>%s</subnetId><vpcId>%s</vpcId><ownerId>727920394381</ownerId><state>available</state><cidrBlock>10.31.8.0/22</cidrBlock><availabilityZone>us-east-1a</availabilityZone><availabilityZoneId>use1-az1</availabilityZoneId><availableIpAddressCount>900</availableIpAddressCount><defaultForAz>false</defaultForAz><mapPublicIpOnLaunch>false</mapPublicIpOnLaunch></item></subnetSet></DescribeSubnetsResponse>`, configuration.Inputs["subnet_id"], configuration.Inputs["vpc_id"])
		default:
			t.Errorf("unexpected API operation: %s", r.Form.Get("Action"))
			http.Error(w, "unexpected API operation", http.StatusBadRequest)
		}
	}))
	defer server.Close()

	files, err := filepath.Glob("../*.tf")
	if err != nil {
		t.Fatal(err)
	}
	for _, source := range append(files, filepath.Join(leaf, ".terraform.lock.hcl")) {
		content, err := os.ReadFile(source)
		if err != nil {
			t.Fatal(err)
		}
		writeFile(t, filepath.Join(work, filepath.Base(source)), content)
	}
	provider := configuration.Generate["provider"].Contents
	if !strings.Contains(provider, `provider "aws" {`) {
		t.Fatal("production provider configuration is missing")
	}
	settings := fmt.Sprintf(`
  skip_credentials_validation = true
  skip_metadata_api_check = true
  skip_region_validation = true
  endpoints {
    ec2 = %[1]q
    sts = %[1]q
    iam = %[1]q
    s3 = %[1]q
    s3files = %[1]q
  }
`, server.URL)
	provider = strings.Replace(provider, `provider "aws" {`, `provider "aws" {`+settings, 1)
	writeFile(t, filepath.Join(work, "provider.tf"), []byte(provider))
	inputs := map[string]any{}
	for _, name := range []string{"bucket_name", "vpc_id", "subnet_id", "name_prefix", "permissions_boundary_arn"} {
		if value, ok := configuration.Inputs[name]; ok {
			inputs[name] = value
		}
	}
	variables, err := json.Marshal(inputs)
	if err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(work, "terraform.tfvars.json"), variables)
	credentials := filepath.Join(work, "credentials")
	writeFile(t, credentials, []byte("[redhat_us_east_1_storage]\naws_access_key_id = offline-test\naws_secret_access_key = offline-test\n"))
	config := filepath.Join(work, "aws-config")
	writeFile(t, config, nil)
	cliConfig := filepath.Join(work, "terraform.rc")
	writeFile(t, cliConfig, nil)
	environment := []string{}
	for _, value := range os.Environ() {
		if !strings.HasPrefix(value, "AWS_") && !strings.HasPrefix(value, "TF_VAR_") && !strings.HasPrefix(value, "TF_TOKEN_") && !strings.HasPrefix(value, "TF_CLI_") && !strings.HasPrefix(value, "TF_DATA_DIR=") {
			environment = append(environment, value)
		}
	}
	environment = append(environment, "AWS_CONFIG_FILE="+config, "AWS_SHARED_CREDENTIALS_FILE="+credentials,
		"AWS_EC2_METADATA_DISABLED=true", "AWS_MAX_ATTEMPTS=1", "TF_CLI_CONFIG_FILE="+cliConfig, "CHECKPOINT_DISABLE=1")
	runTerraformCommand(t, work, environment, terraform, "init", "-backend=false", "-input=false", "-lockfile=readonly", "-no-color")
	// Unexpected service endpoints fail at a local proxy rather than reaching AWS.
	environment = append(environment, "HTTPS_PROXY="+server.URL, "HTTP_PROXY="+server.URL, "NO_PROXY=127.0.0.1,localhost")
	runTerraformCommand(t, work, environment, terraform, "plan", "-refresh=false", "-input=false", "-no-color", "-out=plan")
	var plan struct {
		PlannedValues struct {
			RootModule struct {
				Resources []struct {
					Address string
					Values  map[string]any
				}
			} `json:"root_module"`
		} `json:"planned_values"`
	}
	output := runTerraformCommand(t, work, environment, terraform, "show", "-json", "plan")
	if err := json.Unmarshal(output, &plan); err != nil {
		t.Fatal(err)
	}
	resources := map[string]map[string]any{}
	for _, resource := range plan.PlannedValues.RootModule.Resources {
		resources[resource.Address] = resource.Values
	}
	for _, address := range []string{"aws_iam_role.s3files_service", "aws_iam_role.ec2_client"} {
		t.Run(address, func(t *testing.T) {
			if got := resources[address]["permissions_boundary"]; got != boundary {
				t.Errorf("planned permissions boundary = %v, want %s", got, boundary)
			}
		})
	}
	for _, address := range []string{"aws_s3files_file_system.artifacts", "aws_security_group.nfs_client", "aws_security_group.mount_target"} {
		t.Run(address, func(t *testing.T) {
			tags, _ := resources[address]["tags_all"].(map[string]any)
			if got := tags["StorageBackend"]; got != backend {
				t.Errorf("planned ownership tag = %v, want %s", got, backend)
			}
		})
	}
	t.Run("bucket_lifecycle_permissions", func(t *testing.T) {
		if resources["aws_s3_bucket_lifecycle_configuration.artifacts"] == nil {
			t.Fatal("expected the planned lifecycle configuration")
		}
		s := findStatement(t, loadPolicy(t, "deployment-storage"), "ManageBucketConfiguration")
		requireValues(t, s.Resource, bucket)
		for _, action := range values(t, s.Action) {
			if action == "s3:PutLifecycleConfiguration" {
				return
			}
		}
		t.Error("deployment policy cannot write the planned bucket lifecycle configuration")
	})
}

func writeFile(t *testing.T, path string, content []byte) {
	t.Helper()
	if err := os.WriteFile(path, content, 0600); err != nil {
		t.Fatal(err)
	}
}

func readJSON(t *testing.T, path string, value any) {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(content, value); err != nil {
		t.Fatal(err)
	}
}

func runTerraformCommand(t *testing.T, directory string, environment []string, command string, arguments ...string) []byte {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	process := exec.CommandContext(ctx, command, arguments...)
	process.Dir = directory
	process.Env = environment
	output, err := process.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %v failed: %v\n%s", command, arguments, err, output)
	}
	return output
}
