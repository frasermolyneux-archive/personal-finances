resource "azurerm_key_vault_secret" "app_registration_client_secret" {
  for_each = toset(var.locations)

  name         = format("%s-clientsecret", local.app_registration_name)
  value        = azuread_application_password.app_password_primary.value
  key_vault_id = azurerm_key_vault.kv[each.value].id
}
