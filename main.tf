resource "random_pet" "name" {}

resource "azurerm_resource_provider_registration" "dashboard" {
  name = "Microsoft.Dashboard"
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = "${var.resource_group_name_prefix}-${random_pet.name.id}"
  tags = merge(
    var.tags,
    {
      autokillDays = var.autokill_days
    },
    {
      reason = var.autokill_reason
    },
    {
      project = var.project
    },
    {
      owner = var.owner
    },
    {
      env = var.env
    }
  )

  depends_on = [
    azurerm_resource_provider_registration.dashboard
  ]
}

# Create virtual network
resource "azurerm_virtual_network" "my_terraform_network" {
  name                = "myVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "my_terraform_subnet" {
  name                 = "mySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.my_terraform_network.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "my_terraform_public_ip" {
  name                = "myPublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "my_terraform_nsg" {
  name                = "myNetworkSecurityGroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "my_terraform_nic" {
  name                = "myNIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "my_nic_configuration"
    subnet_id                     = azurerm_subnet.my_terraform_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.my_terraform_public_ip.id
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.my_terraform_nic.id
  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "random_id" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "my_storage_account" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "my_terraform_vm" {
  name                  = "myVM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.my_terraform_nic.id]
  size                  = "Standard_B1ls"

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name  = "hostname"
  admin_username = var.username

  admin_ssh_key {
    username   = var.username
    public_key = jsondecode(azapi_resource_action.ssh_public_key_gen.output).publicKey
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
  }
}

resource "azurerm_dashboard_grafana" "grafana" {
  name                              = "${random_pet.name.id}-gd"
  resource_group_name               = azurerm_resource_group.rg.name
  location                          = azurerm_resource_group.rg.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_monitor_workspace" "monitor_workspace" {
  name                = "${random_pet.name.id}-mamw"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_log_analytics_workspace" "example" {
  name                = "${random_pet.name.id}-laws"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "${random_pet.name.id}-dcre"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_monitor_data_collection_rule" "dcr_vm" {
  name                        = "${azurerm_resource_group.rg.name}-${azurerm_linux_virtual_machine.my_terraform_vm.name}"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id
  kind                        = "Linux"

  destinations {
    azure_monitor_metrics {
      name               = "monitor-account"
    }

    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.example.id
      name                  = "example-destination-log"
    }
  }

  data_sources {
    performance_counter {
      streams                       = ["Microsoft-Perf", "Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["*"]
      name                          = "VMInsightsPerfCounters"
    }
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics"]
    destinations = ["monitor-account"]
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics", "Microsoft-Syslog", "Microsoft-Perf"]
    destinations = ["example-destination-log"]
  }
}

data "azuread_domains" "aad_domains" {
  only_default = true
}

data "azuread_client_config" "current" {}

resource "azuread_user" "grafana_admin" {
  display_name        = "Grafana Admin"
  password            = "notSecure123"
  user_principal_name = "grafana-admin@${data.azuread_domains.aad_domains.domains[0].domain_name}"
  force_password_change = false
}

resource "azuread_group" "grafana_admins" {
  display_name     = "Grafana Admins"
  owners           = [data.azuread_client_config.current.object_id]
  security_enabled = true
}

resource "azuread_group_member" "example" {
  group_object_id  = azuread_group.grafana_admins.id
  member_object_id = azuread_user.grafana_admin.id
}

resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Grafana Admin"
  principal_id         = azuread_group.grafana_admins.id
}

data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "grafana_reader" {
  //scope                = azurerm_resource_group.rg.id
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}
