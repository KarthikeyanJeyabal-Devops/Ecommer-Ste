output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "frontdoor_endpoint_hostname" {
  description = "Default Azure Front Door hostname."
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "storefront_url" {
  value = var.domain_name != "" ? "https://${local.custom_hostname}" : "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}

output "frontend_app_url" {
  value = "https://${azurerm_linux_web_app.frontend.default_hostname}"
}

output "backend_app_url" {
  value = "https://${azurerm_linux_web_app.backend.default_hostname}"
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  value = azurerm_mssql_database.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "storage_container_name" {
  value = azurerm_storage_container.product_media.name
}

output "azure_dns_nameservers" {
  description = "Set these nameservers at your domain registrar when using Azure DNS."
  value       = var.domain_name != "" ? azurerm_dns_zone.main[0].name_servers : []
}
