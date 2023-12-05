package test

import (
	"testing"
    "github.com/stretchr/testify/assert"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/gruntwork-io/terratest/modules/azure"
	"fmt"
)

func TestTerraformVMSS(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../../examples",
		VarFiles: []string{"terratest.tfvars"},
		Upgrade: true,
	}

	// Defer the destroy to cleanup all created resources
	defer terraform.Destroy(t, terraformOptions)

	// This will init and apply the resources and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// // Assert inputs with outputs
	outputs_vm_name := terraform.Output(t, terraformOptions, "linux_virtual_machine_names")
	elem := outputs_vm_name[0]
	assert.Equal(t, "linux-vm", outputs_vm_name)
}
