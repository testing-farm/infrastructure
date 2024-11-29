
package test

import (
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/google/uuid"
	"testing"
	"os"
)

func TestProjectModule(t *testing.T) {
	t.Parallel()

	// Root folder where terraform files should be (relative to the test folder)
	rootFolder := ".."

	// Relative path to terraform module being tested from the root folder
	terraformFolderRelativeToRoot := "."

	// Copy the terraform folder to a temp folder
	tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	//Generate uuid to use as project name
	uuid := uuid.New()

	// Define the Terraform options, using Terragrunt to execute
	terraformOptions := &terraform.Options{
		// Set the path to the Terragrunt module you want to test
		TerraformDir: tempTestFolder,

		// Variables to pass to our Terraform code using VAR=value pairs
		Vars: map[string]interface{}{
			"project_name": "gitlab-module-test-project-" + uuid.String(),
			"description": "gitlab-module-test-project-" + uuid.String(),
			"namespace_id": 5515434,
			"gitlab_token": os.Getenv("TF_VAR_gitlab_testing_farm_bot"),
		},
	}

	// Clean up resources with "terraform destroy" at the end of the test
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform code
	terraform.InitAndApply(t, terraformOptions)

	// Run terraform output to get the value of an output variable
	output := terraform.Output(t, terraformOptions, "id")

	// Verify that the output is not empty
	assert.NotEmpty(t, output)
}
