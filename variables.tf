variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "location" {
  description = "Azure region for the resources."
  type        = string
  default     = "centralindia"
}

variable "project_name" {
  description = "Short project prefix. Use lowercase letters and numbers only."
  type        = string
  default     = "shop"
  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.project_name))
    error_message = "project_name must be 2-8 lowercase letters or numbers."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
  default     = "rg-ecommerce-dev"
}

variable "app_service_sku" {
  description = "Linux App Service Plan SKU."
  type        = string
  default     = "B1"
}

variable "sql_admin_username" {
  description = "SQL administrator login."
  type        = string
  default     = "shopadmin"
}

variable "sql_admin_password" {
  description = "SQL administrator password. Supply through TF_VAR_sql_admin_password; do not commit it."
  type        = string
  sensitive   = true
}

variable "sql_database_sku" {
  description = "Azure SQL database SKU."
  type        = string
  default     = "Basic"
}

variable "storage_replication_type" {
  description = "Storage replication type."
  type        = string
  default     = "LRS"
}

variable "domain_name" {
  description = "Existing domain already registered with a registrar and delegated to Azure DNS, e.g. example.com. Leave empty to use the Front Door default hostname."
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "Subdomain to serve the storefront, e.g. www."
  type        = string
  default     = "www"
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default = {
    application = "ecommerce"
    managed_by  = "terraform"
  }
}
