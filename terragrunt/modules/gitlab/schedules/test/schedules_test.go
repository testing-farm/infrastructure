
package test

import (
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/google/uuid"
	"testing"
	"os"
)

func TestSchedulesModule(t *testing.T) {
	// The test first create a test project and then create a schedule for it.

	t.Parallel()

	// Root folder where terraform files should be (relative to the test folder)
	rootFolderSchedules := ".."
	rootFolderProject := "../../project"

	// Relative path to terraform module being tested from the root folder
	terraformFolderRelativeToRoot := "."

	// Copy the terraform folder to a temp folder
	tempTestFolderSchedules := test_structure.CopyTerraformFolderToTemp(t, rootFolderSchedules, terraformFolderRelativeToRoot)
	tempTestFolderProject := test_structure.CopyTerraformFolderToTemp(t, rootFolderProject, terraformFolderRelativeToRoot)

	//Generate uuid to use as project name
	uuid := uuid.New()

	// Define the Terraform options, using Terragrunt to execute
	terraformOptionsProject := &terraform.Options{
		// Set the path to the Terragrunt module you want to test
		TerraformDir: tempTestFolderProject,

		// Variables to pass to our Terraform code using VAR=value pairs
		Vars: map[string]interface{}{
			"project_name": "gitlab-module-test-project-" + uuid.String(),
			"description": "gitlab-module-test-project-" + uuid.String(),
			"namespace_id": 5515434,
			"gitlab_token": os.Getenv("TF_VAR_gitlab_testing_farm_bot"),
		},
	}

	// Clean up resources with "terraform destroy" at the end of the test
	defer terraform.Destroy(t, terraformOptionsProject)

	// First apply the project module and get id output
	terraform.InitAndApply(t, terraformOptionsProject)

	output := terraform.Output(t, terraformOptionsProject, "id")

	// Now we can use the output from the project module to pass to the schedules module
	terraformOptionsSchedules := &terraform.Options{
		TerraformDir: tempTestFolderSchedules,

		Vars: map[string]interface{}{
			"gitlab_token": os.Getenv("TF_VAR_gitlab_testing_farm_bot"),
			"project_id": output,
			"schedules": []map[string]interface{}{
				{
					"description": "Test schedule",
					"git_ref": "refs/heads/main",
					"cron_schedule": "0 0 * * sat",
					"variables": map[string]string{
						"SCHEDULED_JOB" : "test-job",
					},
				},
			},
		},
	}

	defer terraform.Destroy(t, terraformOptionsSchedules)

	terraform.InitAndApply(t, terraformOptionsSchedules)
}
