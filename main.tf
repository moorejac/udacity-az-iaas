provider "azurerm" {
  version = "~>2.0"
  features {}
}

resource "random_string" "fqdn" {
  length = 6
  special = false
  upper = false
  number = false
}

resource "azurerm_resource_group" "vmss" {
  name = "${var.prefix}-rg"
  location = var.location
  tags = var.tags
}

resource "azurerm_network_security_group" "vmss" {
  name = "${var.prefix}-nsg"
  resource_group_name = azurerm_resource_group.vmss.name
  location = var.location
  tags = var.tags
}

resource "azurerm_network_security_rule" "vmss" {
  for_each = local.nsgrules
  name = each.key
  direction = each.value.direction
  access = each.value.access
  priority = each.value.priority
  protocol = each.value.protocol
  source_port_range = each.value.source_port_range
  destination_port_range = each.value.destination_port_range
  source_address_prefix = each.value.source_address_prefix
  destination_address_prefix = each.value.destination_address_prefix
  resource_group_name = azurerm_resource_group.vmss.name
  network_security_group_name = azurerm_network_security_group.vmss.name
}

resource "azurerm_virtual_network" "vmss" {
  name = "${var.prefix}-vmss-vnet"
  address_space = ["10.0.0.0/16"]
  location = var.location
  resource_group_name = azurerm_resource_group.vmss.name
  tags = var.tags
}

resource "azurerm_subnet" "vmss" {
  name = "${var.prefix}-vmss-subnet"
  resource_group_name = azurerm_resource_group.vmss.name
  virtual_network_name = azurerm_virtual_network.vmss.name
  address_prefixes = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "vmss" {
  name = "${var.prefix}-vmss-public-ip"
  location = var.location
  resource_group_name = azurerm_resource_group.vmss.name
  allocation_method = "Static"
  domain_name_label = random_string.fqdn.result
  tags = var.tags
}

resource "azurerm_lb" "vmss" {
  name = "${var.prefix}vmss-lb"
  location = var.location
  resource_group_name = azurerm_resource_group.vmss.name

  frontend_ip_configuration {
    name = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vmss.id
  }
  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = azurerm_resource_group.vmss.name
  loadbalancer_id = azurerm_lb.vmss.id
  name = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
  resource_group_name = azurerm_resource_group.vmss.name
  loadbalancer_id = azurerm_lb.vmss.id
  name = "${var.prefix}-ssh-running-probe"
  port = var.application_port
}

resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name = azurerm_resource_group.vmss.name
  loadbalancer_id = azurerm_lb.vmss.id
  name = "http"
  protocol = "Tcp"
  frontend_port = var.application_port
  backend_port = var.application_port
  backend_address_pool_id = azurerm_lb_backend_address_pool.bpepool.id
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id = azurerm_lb_probe.vmss.id
}

data "azurerm_resource_group" "image" {
  name = azurerm_resource_group.vmss.name
}

data "azurerm_image" "image" {
  name = "vmss-web-server-image"
  resource_group_name = data.azurerm_resource_group.image.name
}

resource "azurerm_virtual_machine_scale_set" "vmss" {
  name = "${var.prefix}-vmscaleset"
  location = var.location
  resource_group_name = azurerm_resource_group.vmss.name
  upgrade_policy_mode = "Manual"

  sku {
    name = "Standard_DS1_v2"
    tier = "Standard"
    capacity = var.vmss_capacity
  }

  storage_profile_image_reference {
    id=data.azurerm_image.image.id
  }

  storage_profile_os_disk {
    name = ""
    caching = "ReadWrite"
    create_option = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun = 0
    caching = "ReadWrite"
    create_option = "Empty"
    disk_size_gb = 10
  }

  os_profile {
    computer_name_prefix = "vmss-web-server"
    admin_username = var.admin_user
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  network_profile {
    name = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name = "IPConfiguration"
      subnet_id = azurerm_subnet.vmss.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
      primary = true
    }
  }
  tags = var.tags
}

