data "azurerm_client_config" "current" {}

data "azurerm_key_vault" "cert_key_vault" {
  name                = var.cert_keyvault
  resource_group_name = var.cert_keyvault_rg
}

data "azurerm_key_vault_secret" "runas_cert_secret" {
  name         = azurerm_key_vault_certificate.automation_account.name
  key_vault_id = data.azurerm_key_vault.cert_key_vault.id
}

resource "azurerm_resource_group" "rg_github_membership" {
  name     = "github-membership-management"
  location = "Uk South"
}

resource "azurerm_automation_account" "github_membership_automation" {
  name                = var.automation_account_name
  location            = azurerm_resource_group.rg_github_membership.location
  resource_group_name = azurerm_resource_group.rg_github_membership.name

  sku_name = "Basic"
}

resource "azurerm_automation_runbook" "github_membership_runbook" {
  name                    = var.runbook_name
  location                = azurerm_resource_group.rg_github_membership.location
  resource_group_name     = azurerm_resource_group.rg_github_membership.name
  automation_account_name = azurerm_automation_account.github_membership_automation.name
  log_verbose             = "true"
  log_progress            = "true"
  description             = "Runbook to recieve notifications when accounts are disabled in AAD"
  runbook_type            = "PowerShell"

  publish_content_link {
    uri = "https://raw.githubusercontent.com/hmcts/azure-automation-runbooks/DTSPO-440-create-offboarding-runbook/runbooks/Remove-UserGitHubAccess.ps1"
  }
}

resource "azurerm_automation_module" "az_accounts_module" {
  name                    = "Az.Accounts"
  resource_group_name     = azurerm_resource_group.rg_github_membership.name
  automation_account_name = azurerm_automation_account.github_membership_automation.name

  module_link {
    uri = "https://devopsgallerystorage.blob.core.windows.net/packages/az.accounts.2.2.5.nupkg"
  }
}

resource "azurerm_automation_module" "az_keyvault_module" {
  name                    = "Az.KeyVault"
  resource_group_name     = azurerm_resource_group.rg_github_membership.name
  automation_account_name = azurerm_automation_account.github_membership_automation.name

  module_link {
    uri = "https://devopsgallerystorage.blob.core.windows.net/packages/az.keyvault.3.3.1.nupkg"
  }
  # This module cannot be imported unless the Accounts Module has been imported first
  depends_on = [azurerm_automation_module.az_accounts_module]
}

resource "azurerm_automation_certificate" "github_membership_runas_cert" {
  name                    = "AzureRunAsCertificate"
  resource_group_name     = azurerm_automation_account.github_membership_automation.resource_group_name
  automation_account_name = azurerm_automation_account.github_membership_automation.name
  base64                  = data.azurerm_key_vault_secret.runas_cert_secret.value

}

resource "azurerm_automation_connection_service_principal" "github_membership_runas_connection" {
  name                    = "AzureRunAsConnection"
  resource_group_name     = azurerm_automation_account.github_membership_automation.resource_group_name
  automation_account_name = azurerm_automation_account.github_membership_automation.name
  application_id          = azuread_service_principal.automation_account.application_id
  tenant_id               = data.azurerm_client_config.current.tenant_id
  subscription_id         = data.azurerm_client_config.current.subscription_id
  certificate_thumbprint  = azurerm_automation_certificate.github_membership_runas_cert.thumbprint

}
