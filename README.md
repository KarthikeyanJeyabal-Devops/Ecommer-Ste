# Azure E-commerce Infrastructure — Terraform + GitHub Actions

This starter deploys:
- Azure Front Door Standard as the public storefront entry point
- Two Linux App Services (frontend and backend/API) on a shared App Service Plan
- Azure SQL Server and database
- Azure Storage Account and private `product-media` blob container
- Optional Azure DNS zone, Front Door custom domain, DNS validation TXT record, and CNAME

> **Important:** Terraform deploys infrastructure, not your e-commerce application source code.
> The App Services are provisioned with Node.js 20 runtime settings. Add your frontend/API
> application code and a separate build/deploy workflow (or extend this workflow) to publish it.

## 1. Prerequisites

- Azure subscription with permission to create Resource Groups, App Services, SQL, Storage,
  Front Door and DNS resources.
- GitHub repository.
- Azure CLI and Terraform 1.6+ for local runs.
- An existing registered domain if you want a custom hostname.

## 2. Bootstrap remote Terraform state (one time)

The GitHub runner needs persistent remote state. Create a separate state resource group,
storage account and private container before running the workflow. Example (choose a globally
unique storage account name of 3–24 lowercase letters/numbers):

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"

az group create -n "rg-terraform-state" -l "centralindia"

az storage account create \
  --name "<UNIQUESTATEACCOUNT>" \
  --resource-group "rg-terraform-state" \
  --location "centralindia" \
  --sku "Standard_LRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false

az storage container create \
  --name "tfstate" \
  --account-name "<UNIQUESTATEACCOUNT>" \
  --auth-mode login
```

The identity used by GitHub Actions needs appropriate Azure RBAC on the state storage account
(e.g. Storage Blob Data Contributor) and permission to deploy the target resources.

## 3. Configure GitHub OIDC

Create an Entra ID app registration/service principal and federated credential for your repository.
Use the exact GitHub subject for your repository and environment, for example:

`repo:OWNER/REPOSITORY:environment:dev`

Grant the service principal the required Azure deployment permissions at the appropriate scope.
For a lab, Contributor on the target subscription/resource group plus the required state-storage
data role may be convenient; use least privilege in production.

In GitHub → Settings → Secrets and variables → Actions, add:

### Repository secrets
- `AZURE_CLIENT_ID` — Entra application/client ID
- `AZURE_TENANT_ID` — Entra tenant ID
- `TF_VAR_SQL_ADMIN_PASSWORD` — strong SQL administrator password

### Repository variables
- `AZURE_SUBSCRIPTION_ID` — Azure subscription ID
- `TF_STATE_RESOURCE_GROUP` — state resource group, e.g. `rg-terraform-state`
- `TF_STATE_STORAGE_ACCOUNT` — state storage account name
- `TF_STATE_CONTAINER` — state container, e.g. `tfstate`

Do not store credentials in `terraform.tfvars` or commit secrets.

## 4. Configure the project

Edit `terraform.tfvars`:
- Set `subscription_id` (the workflow overrides it using the GitHub variable).
- Set `location` and naming values if required.
- Keep `domain_name = ""` to use the Azure-generated Front Door hostname (`*.azurefd.net`) without a custom domain.

The storage account name is derived from `project_name` and `environment`; it must be globally unique.
If Azure reports a name conflict, change `project_name` or `environment`.

## 5. Deploy from GitHub

1. Push this folder's contents to the root of your GitHub repository.
2. Configure the GitHub OIDC secrets and variables above.
3. Open Actions → **Deploy E-commerce Infrastructure (Dev)** → Run workflow.
4. Review the workflow logs and Terraform outputs.

Pushes to `main` that modify Terraform files or `terraform.tfvars` also trigger the workflow.
The workflow applies changes automatically on `main`; protect the `main` branch and configure
GitHub environment approval rules if you want a manual approval gate.

## 6. Custom domain and DNS

Azure DNS does **not** buy/register a domain. You must already own the domain at a registrar.
When `domain_name = "example.com"`:
- Terraform creates an Azure DNS zone for `example.com`.
- Terraform creates the Front Door custom domain `www.example.com`.
- Terraform creates the Front Door validation TXT record and `www` CNAME.
- After deployment, copy the `azure_dns_nameservers` output into the domain registrar's
  nameserver settings to delegate the domain to Azure DNS.

DNS delegation can take time to propagate. Front Door managed certificate issuance and domain
validation are asynchronous; check the custom domain provisioning/validation state in Azure
before expecting HTTPS to work. Do not point a production domain until you are ready to cut over.

## 7. Local deployment (optional)

```bash
cp terraform.tfvars.example terraform.tfvars   # if using the example file
export TF_VAR_sql_admin_password='<STRONG_PASSWORD>'
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

For local runs, either configure the remote backend as described above or temporarily remove the
`backend "azurerm" {}` block and use local state. Do not use local state for shared team deployments.

## 8. Important production hardening

This is a development starter, not a production-ready commerce platform:
- SQL currently has public network access and an Azure-services firewall exception. Prefer Private
  Endpoint + VNet integration, disable public access, and restrict all network paths.
- App settings receive SQL/storage connection secrets for simplicity. Prefer managed identity,
  Key Vault references, and narrowly scoped RBAC; remove connection-string secrets from app config.
- Add a Front Door WAF policy, rate limiting, bot protection, monitoring, alerts and diagnostics.
- Add backups, SQL point-in-time restore configuration, deployment slots, autoscaling and disaster
  recovery appropriate to your requirements.
- Use private blob containers and short-lived user-delegation SAS or backend-mediated uploads.
- Add application-level authentication, payment-provider integration, input validation and secure
  handling of customer data. Do not store payment card data directly unless your compliance design
  explicitly supports it.

## 9. Resource naming notes

Azure resource names have global uniqueness and character restrictions. If deployment fails due to
a name collision, change `project_name` and rerun. Review `terraform plan` before applying.
