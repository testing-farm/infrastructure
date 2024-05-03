package test

import (
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestVaultModule(t *testing.T) {
	t.Parallel()

	// Root folder where terraform files should be (relative to the test folder)
	rootFolder := ".."

	// Relative path to terraform module being tested from the root folder
	terraformFolderRelativeToRoot := "."

	// Copy the terraform folder to a temp folder
	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	// Define the Terraform options, using Terragrunt to execute
	terraformOptions := &terraform.Options{
		// Set the path to the Terragrunt module you want to test
		TerraformDir: tempTestFolder,

		// Variables to pass to our Terraform code using VAR=value pairs
		Vars: map[string]interface{}{
			"vault_file":          "test/secrets.yaml",
			"vault_password_file": "test/vault_pass",  // pragma: allowlist secret
		},
	}

	// Clean up resources with "terraform destroy" at the end of the test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform code
	terraform.InitAndApply(t, terraformOptions)

	// Run terraform output to get the value of an output variable
	output := terraform.Output(t, terraformOptions, "secrets")
	expectedOutput := "map[one:map[subone:map[list:[a b c]]] two:map[subtwo:map[var:value]]]"

	// Verify that the output meets expected value
	assert.Equal(t, expectedOutput, output)
}
