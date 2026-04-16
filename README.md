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

- `modules/vnet/` — reusable VNet module with subnets, NSGs, optional DDoS plan, and outputs
- `environments/dev/` — root Terraform for development
- `environments/prod/` — root Terraform for production
- `.github/workflows/terraform.yml` — CI/CD workflow for lint, validate, plan, and apply
- `scripts/bootstrap-dev.sh` / `scripts/bootstrap-prod.sh` — create or reuse per-environment remote state resources and backend config files
- `scripts/setup-github-oidc.sh` — create or reuse the GitHub OIDC identity, federated credentials, and all required role assignments

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

Terraform remote state is stored in Azure Blob Storage with one storage account per environment.

| Environment | Resource group | Storage account |
|-------------|----------------|-----------------|
| dev | `tfstate-dev-rg` | derived from subscription ID |
| prod | `tfstate-prod-rg` | derived from subscription ID |

Both backends use `use_azuread_auth = true` — the AzureRM backend authenticates to the storage data plane via Azure AD tokens, not storage account keys. The GitHub Actions identity therefore needs `Storage Blob Data Contributor` on each backend storage account (assigned by `setup-github-oidc.sh`).

Do not rotate the backend storage account name after bootstrap.

## Bootstrap model

This repository uses two layers of bootstrap scripts.

### Layer 1 — per-environment state storage

Run once per environment to create or reuse the remote state prerequisites:

```bash
# dev
SUBSCRIPTION_ID=<sub-id> ./scripts/bootstrap-dev.sh

# prod
SUBSCRIPTION_ID=<sub-id> ./scripts/bootstrap-prod.sh
```

Each script:

- creates or reuses the backend resource group, storage account, and container
- writes `environments/<env>/backend.tfbackend`
- optionally runs `terraform init`

### Layer 2 — GitHub OIDC identity

Run once to create or update the Microsoft Entra app, service principal, federated credentials, and all required role assignments:

```bash
DEV_TFSTATE_RG=tfstate-dev-rg   DEV_TFSTATE_SA=<dev-sa-name>  \
PROD_TFSTATE_RG=tfstate-prod-rg PROD_TFSTATE_SA=<prod-sa-name> \
OWNER=<github-owner> REPO=<github-repo>                        \
./scripts/setup-github-oidc.sh
```

The script assigns:

| Role | Scope | Purpose |
|------|-------|---------|
| `Contributor` | subscription | create and manage all workload resources |
| `Storage Blob Data Contributor` | subscription | data-plane access to dynamically-created storage accounts |
| `Storage Blob Data Contributor` | dev tfstate storage account | Terraform backend access for dev |
| `Storage Blob Data Contributor` | prod tfstate storage account | Terraform backend access for prod |

The subscription-scope `Storage Blob Data Contributor` is required because the prod environment creates a storage account with `shared_access_key_enabled = false`. The `azurerm` provider polls the storage data plane after creation to verify availability. Without AAD data-plane access that poll fails with `403 KeyBasedAuthenticationNotPermitted`. The management-plane `Contributor` role does not cover data-plane operations. Because the account is created by Terraform it cannot be pre-scoped, so subscription scope is the minimum viable target.

## Provider configuration — `storage_use_azuread`

`environments/prod/providers.tf` includes:

```hcl
provider "azurerm" {
  storage_use_azuread = true
  ...
}
```

This is required for any environment where a storage account has `shared_access_key_enabled = false`. Without it the `azurerm` provider falls back to key-based data-plane calls and fails with `KeyBasedAuthenticationNotPermitted`. The dev environment does not set this because dev storage uses `shared_access_key_enabled = true`.

## Branching and release model

This repository uses a simple promotion flow:

- `develop` -> deploys to `dev`
- `main` -> deploys to `prod`

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

### Triggers

| Event | Branch | Effect |
|-------|--------|--------|
| `pull_request` | `develop` | lint + plan dev |
| `pull_request` | `main` | lint + plan prod |
| `push` | `develop` | lint + apply dev |
| `push` | `main` | lint + apply prod (requires manual approval) |
| `workflow_dispatch` | any | lint + plan for selected environment |

The `workflow_dispatch` trigger lets you run a plan at any time from the GitHub Actions UI without needing to push a commit. Select the target environment (`dev` or `prod`) from the dropdown. Dispatch runs execute plan only — no apply.

Path filters restrict automatic triggers to changes under `environments/**`, `modules/**`, or `.github/workflows/terraform.yml`. Changes to scripts or documentation do not trigger the pipeline.

### Pull request lifecycle

On every PR to `develop` or `main`:

1. `terraform fmt -check`
2. `terraform init -backend=false`
3. `terraform validate`
4. `tflint`
5. `checkov`
6. `terraform plan`
7. plan output is posted back to the PR as a comment (upserted on re-runs)

PR target determines which environment is planned:

- PR into `develop` -> `dev` plan
- PR into `main` -> `prod` plan

### Push lifecycle

On push to `develop`:

- deploy `dev` automatically

On push to `main`:

- deploy `prod`
- deployment is gated by the GitHub `production` environment approval rule

### Job structure

The `detect` job runs first and sets three outputs — `target`, `run_plan`, `run_apply` — that all downstream jobs consume. This centralises environment detection and avoids duplicating branch-matching logic across jobs.

The `plan` job has a static name (`Plan`) rather than a dynamic one referencing `needs` outputs. GitHub Actions only evaluates job name expressions when a job executes; skipped jobs display the raw template string.

## Authentication model for GitHub Actions

This repository uses GitHub OIDC with Azure — no stored client secrets.

GitHub exchanges a short-lived OIDC token directly with Azure. Azure trusts the workflow based on federated credentials attached to the Microsoft Entra app.

The workflow sets these environment variables on Terraform jobs:

```yaml
ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
ARM_USE_OIDC: 'true'
```

`ARM_USE_OIDC=true` enables OIDC / workload identity federation for both the AzureRM provider and the AzureRM backend. The backend additionally requires `use_azuread_auth = true` in `backend.tfbackend` to use AAD tokens for blob data-plane access.

## GitHub secret layout

Use repository secrets:

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

The Microsoft Entra app must trust these three subject claims:

- `repo:<owner>/<repo>:pull_request`
- `repo:<owner>/<repo>:environment:dev`
- `repo:<owner>/<repo>:environment:production`

`setup-github-oidc.sh` creates and keeps these up to date automatically.

## Required Azure role assignments

| Role | Scope | Why |
|------|-------|-----|
| `Contributor` | subscription | create and manage all workload resources across both environments |
| `Storage Blob Data Contributor` | subscription | data-plane access for storage accounts created by Terraform with `shared_access_key_enabled=false` |
| `Storage Blob Data Contributor` | dev tfstate storage account | Terraform backend init / state read-write for dev |
| `Storage Blob Data Contributor` | prod tfstate storage account | Terraform backend init / state read-write for prod |

All four assignments are applied by `setup-github-oidc.sh`.

## Fork PR note

GitHub does not pass repository secrets to workflows triggered by pull requests from forks. Azure-backed plan jobs may therefore fail or be skipped for forked PRs unless you add special handling for them.

## Why `set -o pipefail` is in the plan step

The `plan` step writes output through `tee`:

```bash
terraform plan -no-color -out=tfplan 2>&1 | tee plan.txt
```

Without `set -o pipefail`, the shell can report success because `tee` succeeded even when `terraform plan` failed. Keeping `set -o pipefail` makes the step return the actual Terraform result.

## Initial setup checklist

1. Bootstrap per-environment state storage:
   ```bash
   SUBSCRIPTION_ID=<sub-id> ./scripts/bootstrap-dev.sh
   SUBSCRIPTION_ID=<sub-id> ./scripts/bootstrap-prod.sh
   ```

2. Set up GitHub OIDC identity and all role assignments:
   ```bash
   DEV_TFSTATE_RG=tfstate-dev-rg   DEV_TFSTATE_SA=<dev-sa>  \
   PROD_TFSTATE_RG=tfstate-prod-rg PROD_TFSTATE_SA=<prod-sa> \
   OWNER=<owner> REPO=<repo>                                 \
   ./scripts/setup-github-oidc.sh
   ```

3. Add repository secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`

4. Create GitHub Environments:
   - `dev`
   - `production`

5. Configure protection rules:
   - `dev` — no reviewers, branch `develop`
   - `production` — reviewers required, branch `main`

6. Initialize Terraform locally when needed:
   ```bash
   terraform init -backend-config=backend.tfbackend
   ```

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
