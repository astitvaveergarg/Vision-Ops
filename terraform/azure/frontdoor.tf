# Private DNS Zone for Private Cluster
resource "azurerm_private_dns_zone" "aks" {
  count               = var.environment == "prod" ? 1 : 0
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.aks.name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.environment == "prod" ? 1 : 0
  name                  = "${var.cluster_name}-dns-link"
  resource_group_name   = azurerm_resource_group.aks.name
  private_dns_zone_name = azurerm_private_dns_zone.aks[0].name
  virtual_network_id    = azurerm_virtual_network.aks.id

  tags = var.tags
}

# Azure Front Door for Production
resource "azurerm_cdn_frontdoor_profile" "api" {
  count               = var.enable_frontdoor ? 1 : 0
  name                = "${var.cluster_name}-frontdoor"
  resource_group_name = azurerm_resource_group.aks.name
  sku_name            = var.environment == "prod" ? "Premium_AzureFrontDoor" : "Standard_AzureFrontDoor"

  tags = var.tags
}

# Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "api" {
  count                    = var.enable_frontdoor ? 1 : 0
  name                     = "${var.cluster_name}-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.api[0].id

  tags = var.tags
}

# Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "api" {
  count                    = var.enable_frontdoor ? 1 : 0
  name                     = "vision-api-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.api[0].id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/health"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

# Origin - Internal Load Balancer
resource "azurerm_cdn_frontdoor_origin" "api" {
  count                         = var.enable_frontdoor ? 1 : 0
  name                          = "vision-api-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api[0].id

  enabled                        = true
  host_name                      = "vision-api.${var.cluster_name}.internal" # Replace with actual internal LB
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = "vision-api.${var.cluster_name}.internal"
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = false

  private_link {
    request_message        = "VisionOps Private Link Request"
    target_type            = "sites" # Change based on actual backend
    location               = azurerm_resource_group.aks.location
    private_link_target_id = azurerm_kubernetes_cluster.aks.id
  }
}

# Front Door Route
resource "azurerm_cdn_frontdoor_route" "api" {
  count                         = var.enable_frontdoor ? 1 : 0
  name                          = "vision-api-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.api[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api[0].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.api[0].id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}

# WAF Policy for Front Door (Production)
resource "azurerm_cdn_frontdoor_firewall_policy" "api" {
  count               = var.environment == "prod" && var.enable_frontdoor ? 1 : 0
  name                = replace("${var.cluster_name}wafpolicy", "-", "")
  resource_group_name = azurerm_resource_group.aks.name
  sku_name            = "Premium_AzureFrontDoor"
  enabled             = true
  mode                = "Prevention"

  # Rate limiting rule
  custom_rule {
    name                           = "RateLimitRule"
    enabled                        = true
    priority                       = 1
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100
    type                           = "RateLimitRule"
    action                         = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0", "::/0"]
    }
  }

  # Managed rule set - Default
  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"
  }

  # Managed rule set - Bot Protection
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  tags = var.tags
}

# Security Policy
resource "azurerm_cdn_frontdoor_security_policy" "api" {
  count                    = var.environment == "prod" && var.enable_frontdoor ? 1 : 0
  name                     = "${var.cluster_name}-security-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.api[0].id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.api[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.api[0].id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

# Outputs
output "frontdoor_endpoint_hostname" {
  description = "Azure Front Door endpoint hostname"
  value       = var.enable_frontdoor ? azurerm_cdn_frontdoor_endpoint.api[0].host_name : null
}

output "frontdoor_profile_id" {
  description = "Azure Front Door profile ID"
  value       = var.enable_frontdoor ? azurerm_cdn_frontdoor_profile.api[0].id : null
}
