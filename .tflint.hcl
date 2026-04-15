# TFLint configuration
# Run: tflint --init && tflint --recursive
# Docs: https://github.com/terraform-linters/tflint

plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Terraform core rules
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

# Naming convention is enforced manually via locals; disable the built-in rule
# to avoid conflicts with our {abbrev}-{project}-{env}-{region}-{index} pattern.
rule "terraform_naming_convention" {
  enabled = false
}
