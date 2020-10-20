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

resource "azurerm_resource_group" "cluster" {
  name = "${var.prefix}-rg"
  location = var.location
  tags = var.tags
}

resource "azurerm_network_security_group" "cluster" {
  name = "${var.prefix}-nsg"
  resource_group_name = azurerm_resource_group.cluster.name
  location = var.location
  tags = var.tags
}

resource "azurerm_network_security_rule" "cluster" {
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
  resource_group_name = azurerm_resource_group.cluster.name
  network_security_group_name = azurerm_network_security_group.cluster.name
}

resource "azurerm_virtual_network" "cluster" {
  name = "${var.prefix}-cluster-vnet"
  address_space = ["10.0.0.0/16"]
  location = var.location
  resource_group_name = azurerm_resource_group.cluster.name
  tags = var.tags
}

resource "azurerm_subnet" "cluster" {
  name = "${var.prefix}-cluster-subnet"
  resource_group_name = azurerm_resource_group.cluster.name
  virtual_network_name = azurerm_virtual_network.cluster.name
  address_prefixes = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "cluster" {
  name = "${var.prefix}-cluster-public-ip"
  location = var.location
  resource_group_name = azurerm_resource_group.cluster.name
  allocation_method = "Static"
  domain_name_label = random_string.fqdn.result
  tags = var.tags
}

resource "azurerm_lb" "cluster" {
  name = "${var.prefix}cluster-lb"
  location = var.location
  resource_group_name = azurerm_resource_group.cluster.name

  frontend_ip_configuration {
    name = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.cluster.id
  }
  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = azurerm_resource_group.cluster.name
  loadbalancer_id = azurerm_lb.cluster.id
  name = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "cluster" {
  resource_group_name = azurerm_resource_group.cluster.name
  loadbalancer_id = azurerm_lb.cluster.id
  name = "${var.prefix}-ssh-running-probe"
  port = var.application_port
}

resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name = azurerm_resource_group.cluster.name
  loadbalancer_id = azurerm_lb.cluster.id
  name = "http"
  protocol = "Tcp"
  frontend_port = var.application_port
  backend_port = var.application_port
  backend_address_pool_id = azurerm_lb_backend_address_pool.bpepool.id
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id = azurerm_lb_probe.cluster.id
}

resource "azurerm_network_interface" "cluster" {
 count = var.vm_count
 name = "acctni${count.index}"
 location = azurerm_resource_group.cluster.location
 resource_group_name = azurerm_resource_group.cluster.name

  ip_configuration {
    name = "vmNICConfig"
    subnet_id = azurerm_subnet.cluster.id
    private_ip_address_allocation = "dynamic"
  }
}

data "azurerm_resource_group" "image" {
  name = azurerm_resource_group.cluster.name
}

data "azurerm_image" "image" {
  name = "vmss-web-server-image"
  resource_group_name = data.azurerm_resource_group.image.name
}

resource "azurerm_virtual_machine" "cluster" {
  count = var.vm_count
  name = "acctvm${count.index}"
  location = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  network_interface_ids = [element(azurerm_network_interface.cluster.*.id, count.index)]
  vm_size = "Standard_DS1_v2"
  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    id=data.azurerm_image.image.id
  }

  storage_os_disk {
    name = ""
    caching = "ReadWrite"
    create_option = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name = "cluster-web-server"
    admin_username = var.admin_user
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = var.tags
}

