resource "azurerm_resource_group" "web" {
  for_each = toset(var.locations)

  name     = format("rg-personal-finances-%s-web-%s-%s", var.environment, each.value, var.instance)
  location = each.value

  tags = var.tags
}

resource "azurerm_service_plan" "app" {
  for_each = toset(var.locations)

  name = format("plan-personal-finances-%s-web-%s-%s", var.environment, each.value, var.instance)

  resource_group_name = azurerm_resource_group.web[each.value].name
  location            = azurerm_resource_group.web[each.value].location

  os_type  = "Linux"
  sku_name = "F1"

  tags = var.tags
}

resource "azurerm_linux_web_app" "app" {
  for_each = toset(var.locations)

  name = format("app-personal-finances-%s-%s-%s-%s", var.environment, each.value, var.instance, random_id.environment_id.hex)

  resource_group_name = azurerm_resource_group.web[each.value].name
  location            = azurerm_resource_group.web[each.value].location

  service_plan_id = azurerm_service_plan.app[each.value].id

  https_only = true

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.ai[each.value].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.ai[each.value].connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    "minTlsVersion"                              = "1.2" // Setting as app setting as setting on resource doesn't seem to work.
    "AzureAd__Instance"                          = "https://login.microsoftonline.com/"
    "AzureAd__Domain"                            = "molyneux.io"
    "AzureAd__TenantId"                          = data.azurerm_client_config.current.tenant_id
    "AzureAd__ClientId"                          = azuread_application.finances_api.application_id
    "AzureAd__ClientSecret"                      = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", azurerm_key_vault.kv[each.value].name, azurerm_key_vault_secret.app_registration_client_secret[each.value].name)

    // App Data Storage Account
    "appdata_connectionstring" = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", azurerm_key_vault.kv[each.value].name, azurerm_key_vault_secret.appdata_connectionstring[each.value].name)

    // Client Settings that are exposed via API to the Blazor Web Assembly
    "ClientAzureAd__ClientId"  = azuread_application.finances_api_client.application_id
    "ClientAzureAd__Authority" = "https://login.microsoftonline.com/molyneux.io"
    "ClientServerApi__BaseUrl" = format("api://%s", local.app_registration_name)
    "ClientServerApi__Scopes"  = format("api://%s/access_as_user", local.app_registration_name)
  }

  site_config {
    always_on = false // This is required as the app service plan is set to 'F1' which is not always on.

    ftps_state = "Disabled"

    application_stack {
      dotnet_version = "7.0"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

// This is required as when the app service is created 'basic auth' is set as disabled which is required for the SCM deploy.
resource "azapi_update_resource" "app" {
  for_each = toset(var.locations)

  type        = "Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-09-01"
  resource_id = format("%s/basicPublishingCredentialsPolicies/scm", azurerm_linux_web_app.app[each.value].id)

  body = jsonencode({
    properties = {
      allow = true
    }
  })

  depends_on = [
    azurerm_linux_web_app.app,
  ]
}
