package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
)

func TestUrlWaitModule(t *testing.T) {
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
		Vars: map[string]interface{}{
			"urls": []string{"https://www.google.com"},
		},
	}

	// Clean up resources with "terraform destroy" at the end of the test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform code
	output := terraform.InitAndApply(t, terraformOptions)

	// Assert output contains URL available
	assert.Contains(t, output, "The URL 'https://www.google.com' is available.")
}

func TestUrlWaitModuleFailure(t *testing.T) {
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
		Vars: map[string]interface{}{
			"urls": []string{"https://notexistingurl"},
			"timeout": 1,
		},
	}

	// Clean up resources with "terraform destroy" at the end of the test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform code
	output, err := terraform.InitAndApplyE(t, terraformOptions)

	if assert.Error(t, err) {
		assert.Contains(t, output, "Timeout reached while waiting for URL 'https://notexistingurl' to be available.")
	}
}
