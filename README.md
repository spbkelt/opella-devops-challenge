# Opella Terraform Infrastructure

Terraform-based Azure infrastructure for two environments in one Azure subscription:

- `dev`
- `prod`

This repository includes:

- a reusable Azure VNet module
- one root Terraform configuration per environment
- a Linux VM
- a workload storage account with a private blob container
- remote Terraform state in Azure Blob Storage
- a GitHub Actions CI/CD pipeline using OIDC with Azure

## Deliverables

This repository contains:

- `modules/vnet/` — reusable VNet module with subnets, NSGs, optional DDoS plan, and outputs
- `environments/dev/` — root Terraform for development
- `environments/prod/` — root Terraform for production
- `.github/workflows/terraform.yml` — CI/CD workflow for lint, validate, plan, and apply
- `scripts/bootstrap.sh` or equivalent bootstrap script — creates or reuses remote state resources, GitHub OIDC identity, role assignments, and backend config files

## Design choices

### Why resource groups instead of separate subscriptions?

For this challenge, `dev` and `prod` live in the same Azure subscription and are separated with dedicated resource groups. That gives:

- clear lifecycle boundaries
- separate Terraform state keys per environment
- clean naming and tagging
- simpler bootstrap and GitHub Actions setup

Use separate subscriptions when you need stronger isolation for billing, policy, quotas, or production blast-radius control.

## What gets deployed?

Each environment deploys:

- a resource group
- a virtual network with subnets
- network security groups
- a Linux virtual machine
- a workload storage account
- a private blob container
- optional DDoS protection resources

### Why a VM and a storage account?

The original challenge asks for a virtual machine and one additional useful resource.

The VM is useful for:

- connectivity testing
- validating network rules
- basic administration

The storage account is useful for:

- application data
- artifacts
- backups
- simple development workflows

## Naming and tagging

Resources are named to make the project, environment, and region obvious.

Examples:

- `rg-opella-dev-eastus-001`
- `vnet-opella-prod-eastus-001`
- `vm-opella-dev-eastus-001`

Common tags:

- `environment`
- `project`
- `region`
- `owner`
- `managed_by=terraform`

Best practice:

- define repeated values once in `locals.tf`
- pass shared inputs through variables
- merge common tags into every resource

## Useful outputs

Useful Terraform outputs include:

- resource group name
- VNet ID and name
- subnet IDs
- VM name
- VM private IP
- VM public IP when enabled
- storage account ID and name
- storage container name

These outputs are useful for validation, integration, and troubleshooting.

## Remote state

Terraform remote state is stored in Azure Blob Storage.

Recommended pattern:

- one stable backend storage account
- one state container
- separate state keys per environment

Example keys:

- `environments/dev/terraform.tfstate`
- `environments/prod/terraform.tfstate`

Do not rotate the backend storage account name after bootstrap.

## Bootstrap model

This repository uses a bootstrap script instead of a separate Terraform bootstrap stack.

The bootstrap script should create or reuse only the pre-Terraform dependencies:

- backend resource group
- backend storage account
- backend container
- Microsoft Entra app / service principal for GitHub Actions
- federated credentials for GitHub OIDC
- role assignments needed for Terraform backend access and infrastructure apply
- generated `backend.tfbackend` files for `environments/dev` and `environments/prod`

That avoids the backend chicken-and-egg problem because Azure Storage must already exist before Terraform can use it as a backend.

## Branching and release model

This repository uses a simple promotion flow:

- `develop` -> deploys to `dev`
- `main` -> deploys to `production`

Recommended flow:

1. create a feature branch
2. open a PR into `develop`
3. after merge, GitHub Actions deploys `dev` automatically
4. when ready to release, open a PR from `develop` into `main`
5. the PR into `main` runs the `prod` plan
6. after merge to `main`, GitHub Actions waits for manual approval on the `production` GitHub Environment
7. once approved, GitHub Actions deploys `prod`

## GitHub Actions CI/CD

The release lifecycle is defined in `.github/workflows/terraform.yml`.

### Pull request lifecycle

On every PR to `develop` or `main`:

1. `terraform fmt -check`
2. `terraform init -backend=false`
3. `terraform validate`
4. `tflint`
5. `checkov`
6. `terraform plan`
7. plan output is posted back to the PR as a comment

PR target determines which environment is planned:

- PR into `develop` -> `dev` plan
- PR into `main` -> `prod` plan

### Push lifecycle

On push to `develop`:

- deploy `dev` automatically

On push to `main`:

- deploy `prod`
- deployment is gated by the GitHub `production` environment approval rule

## Authentication model for GitHub Actions

This repository uses GitHub OIDC with Azure.

That means:

- no Azure client secret is needed in GitHub Actions
- GitHub exchanges a short-lived OIDC token directly with Azure
- Azure trusts the workflow based on federated credentials attached to the same Microsoft Entra app or service principal

The workflow exports these environment variables to Terraform jobs:

- `ARM_CLIENT_ID`
- `ARM_TENANT_ID`
- `ARM_SUBSCRIPTION_ID`
- `ARM_USE_OIDC=true`
- `ARM_USE_AZUREAD=true`
- `TF_VAR_admin_ssh_public_key`
- `TF_IN_AUTOMATION=true`
- `TF_INPUT=0`

### Why the workflow keeps `ARM_USE_OIDC` and `ARM_USE_AZUREAD`

Keep both in the workflow unless you hardcode the same backend settings in `backend.tfbackend`.

- `ARM_USE_OIDC=true` enables OIDC / workload identity federation for the AzureRM backend and provider.
- `ARM_USE_AZUREAD=true` enables Microsoft Entra ID authentication to the Azure Storage data plane used by the AzureRM backend.

## GitHub secret layout

Use repository secrets for this workflow:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Reason: the `plan` job does not reference a GitHub Environment, so it cannot use environment secrets. Environment secrets are only available to jobs that reference the environment, and if approval is required they are only available after approval.

Keep GitHub Environments for:

- deployment protection rules
- branch restrictions
- production approval gate
- environment-based OIDC subject claims on apply jobs

### Environment names

Create these GitHub Environments:

- `dev`
- `production`

Recommended configuration:

#### `dev`
- no required reviewers
- deployment branches restricted to `develop`

#### `production`
- required reviewers enabled
- deployment branches restricted to `main`

## Required Azure OIDC subjects

Because the current workflow has:

- PR plan jobs without a GitHub Environment
- apply jobs with `environment: dev`
- apply jobs with `environment: production`

the Microsoft Entra app must trust these three subject claims:

- `repo:spbkelt/opella-devops-challenge:pull_request`
- `repo:spbkelt/opella-devops-challenge:environment:dev`
- `repo:spbkelt/opella-devops-challenge:environment:production`

## Required Azure role assignments

The GitHub Actions identity needs at least:

- `Storage Blob Data Contributor` on the Terraform backend storage account
- permission to create and manage workload resources

If your Terraform stacks create the environment resource groups themselves, the simplest bootstrap is subscription-scope `Contributor`. If you later precreate the environment resource groups, you can tighten that to RG-scoped `Contributor`.

## Fork PR note

GitHub does not pass repository secrets to workflows triggered by pull requests from forks. Azure-backed plan jobs may therefore fail or be skipped for forked PRs unless you add special handling for them.

## Why `set -o pipefail` is in the plan step

The `plan` step writes output through `tee`:

```bash
terraform plan -no-color -out=tfplan 2>&1 | tee plan.txt
```

Without `set -o pipefail`, the shell can report success because `tee` succeeded even when `terraform plan` failed. Keeping `set -o pipefail` makes the step return the actual Terraform result.

## Initial setup checklist

1. Run the bootstrap script to create or reuse:
   - tfstate resource group
   - tfstate storage account
   - tfstate container
   - GitHub OIDC identity
   - federated credentials
   - role assignments
   - generated backend config files

2. Add repository secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`

3. Create GitHub Environments:
   - `dev`
   - `production`

4. Configure protection rules:
   - `dev` -> no reviewers, branch `develop`
   - `production` -> reviewers required, branch `main`

5. Initialize Terraform locally when needed:
   - `terraform init -backend-config=backend.tfbackend`

## Local workflow examples

Development:

```bash
cd environments/dev
terraform init -backend-config=backend.tfbackend
terraform plan
```

Production:

```bash
cd environments/prod
terraform init -backend-config=backend.tfbackend
terraform plan
```
