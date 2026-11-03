locals {
  suffix = "${var.project_name}${var.environment}"
  common_tags = merge(var.tags, {
    environment = var.environment
    project     = "ecommerce"
  })
  custom_hostname = var.domain_name != "" ? "${var.app_subdomain}.${var.domain_name}" : ""
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# App Service Plan shared by the storefront and API.
resource "azurerm_service_plan" "main" {
  name                = "asp-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "frontend" {
  name                = "app-${local.suffix}-web"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  site_config {
    always_on = var.app_service_sku != "F1"
    application_stack {
      node_version = "20-lts"
    }
    minimum_tls_version = "1.2"
  }

  app_settings = {
    WEBSITES_PORT                = "8080"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    API_BASE_URL                 = "https://${azurerm_linux_web_app.backend.default_hostname}"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

resource "azurerm_linux_web_app" "backend" {
  name                = "app-${local.suffix}-api"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  site_config {
    always_on = var.app_service_sku != "F1"
    application_stack {
      node_version = "20-lts"
    }
    minimum_tls_version = "1.2"
  }

  app_settings = {
    WEBSITES_PORT = "8080"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    SQL_SERVER       = azurerm_mssql_server.main.fully_qualified_domain_name
    SQL_DATABASE     = azurerm_mssql_database.main.name
    SQL_USERNAME     = var.sql_admin_username
    SQL_PASSWORD     = var.sql_admin_password
    STORAGE_ACCOUNT  = azurerm_storage_account.main.name
    STORAGE_CONTAINER = azurerm_storage_container.product_media.name
    AZURE_STORAGE_CONNECTION_STRING = azurerm_storage_account.main.primary_connection_string
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Azure SQL
resource "azurerm_mssql_server" "main" {
  name                         = "sql-${local.suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  public_network_access_enabled = true
  tags                         = local.common_tags
}

resource "azurerm_mssql_database" "main" {
  name           = "ecommerce"
  server_id      = azurerm_mssql_server.main.id
  sku_name       = var.sql_database_sku
  max_size_gb    = 2
  zone_redundant = false
  tags           = local.common_tags
}

# Permit Azure-hosted services to reach SQL. For production, replace this
# broad rule with private networking / private endpoints and tighter access.
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Blob storage for product images, invoices and uploaded files.
resource "azurerm_storage_account" "main" {
  name                            = substr("st${local.suffix}data", 0, 24)
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  tags                            = local.common_tags
}

resource "azurerm_storage_container" "product_media" {
  name                  = "product-media"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# Azure Front Door Standard: public global entry point to the frontend app.
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "afd-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.common_tags
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "afd-${local.suffix}-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = local.common_tags
}

resource "azurerm_cdn_frontdoor_origin_group" "frontend" {
  name                     = "frontend-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  load_balancing {}
  health_probe {
    path                = "/"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 120
  }
}

resource "azurerm_cdn_frontdoor_origin" "frontend" {
  name                          = "frontend-app-service"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.frontend.id
  enabled                       = true
  host_name                     = azurerm_linux_web_app.frontend.default_hostname
  origin_host_header            = azurerm_linux_web_app.frontend.default_hostname
  certificate_name_check_enabled = true
  http_port                     = 80
  https_port                    = 443
  priority                      = 1
  weight                        = 1000
}

resource "azurerm_cdn_frontdoor_route" "frontend" {
  name                          = "frontend-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.frontend.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.frontend.id]
  enabled                       = true
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  link_to_default_domain        = var.domain_name == ""
  cdn_frontdoor_custom_domain_ids = var.domain_name != "" ? [azurerm_cdn_frontdoor_custom_domain.main[0].id] : []

  depends_on = [azurerm_cdn_frontdoor_origin.frontend]
}

# Optional: host an existing domain's DNS zone in Azure DNS and attach www.<domain>
# to Front Door. This does NOT purchase/register a domain name.
resource "azurerm_dns_zone" "main" {
  count               = var.domain_name != "" ? 1 : 0
  name                = var.domain_name
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_cdn_frontdoor_custom_domain" "main" {
  count                    = var.domain_name != "" ? 1 : 0
  name                     = "custom-${var.project_name}-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  dns_zone_id              = azurerm_dns_zone.main[0].id
  host_name                = local.custom_hostname

  tls {
    certificate_type    = "ManagedCertificate"
    minimum_tls_version = "TLS12"
  }
}

resource "azurerm_dns_txt_record" "frontdoor_validation" {
  count               = var.domain_name != "" ? 1 : 0
  name                = "_dnsauth.${var.app_subdomain}"
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 3600

  record {
    value = azurerm_cdn_frontdoor_custom_domain.main[0].validation_token
  }
}

resource "azurerm_dns_cname_record" "frontend" {
  count               = var.domain_name != "" ? 1 : 0
  name                = var.app_subdomain
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 3600
  record              = azurerm_cdn_frontdoor_endpoint.main.host_name
  depends_on          = [azurerm_cdn_frontdoor_route.frontend, azurerm_dns_txt_record.frontdoor_validation]
}

