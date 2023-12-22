package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestTerraformVM(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../../examples",
		VarFiles:     []string{"terratest.tfvars"},
		Upgrade:      true,
	}

	// Defer the destroy to cleanup all created resources
	defer terraform.Destroy(t, terraformOptions)

	// This will init and apply the resources and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// // Assert inputs with outputs
	outputs_vm_name := terraform.Output(t, terraformOptions, "linux_virtual_machine_name")
	assert.Equal(t, "VMLINUX01.test", outputs_vm_name)
}
