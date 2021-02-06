# Configure Providers
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.40"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "vmss" {
  name     = var.resource_group_name
  location = var.location
  tags = var.tags
}

# Create MySQL Server
resource "azurerm_mysql_server" "vmss" {
  resource_group_name = azurerm_resource_group.vmss.name
  name = "vmss-mysql-server"
  location = azurerm_resource_group.vmss.location
  version = "5.7"

  
  administrator_login = var.mysql_server_login
  administrator_login_password = var.mysql_server_pwd

  sku_name = "B_Gen5_2"
  storage_mb = "5120"
  auto_grow_enabled = false
  backup_retention_days = 7
  geo_redundant_backup_enabled = false

  infrastructure_encryption_enabled = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled = false
  #ssl_minimal_tls_version_enforced = "TLS1_2"
}

# Config MySQL Server Firewall Rule
resource "azurerm_mysql_firewall_rule" "vmss" {
  name                = "vmss-mysql-firewall-rule"
  resource_group_name = azurerm_resource_group.vmss.name
  server_name         = azurerm_mysql_server.vmss.name
  start_ip_address    = azurerm_public_ip.vmss.ip_address
  end_ip_address      = azurerm_public_ip.vmss.ip_address
}

# Create MySql DataBase
resource "azurerm_mysql_database" "vmss" {
  name                = "vmss-mysql-db"
  resource_group_name = azurerm_resource_group.vmss.name
  server_name         = azurerm_mysql_server.vmss.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

# Create a virtual network
resource "azurerm_virtual_network" "vmss" {
  name                = "vmss-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name
  tags = var.tags
}

# Create a subnet
resource "azurerm_subnet" "vmss" {
  name                 = "vmss-snet"
  resource_group_name  = azurerm_resource_group.vmss.name
  virtual_network_name = azurerm_virtual_network.vmss.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create a random domain name
resource "random_string" "fqdn" {
 length  = 6
 special = false
 upper   = false
 number  = false
}

# Create public IP
resource "azurerm_public_ip" "vmss" {
  name                = "vmss-public-ip"
  location            = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name
  allocation_method   = "Static"
  domain_name_label   = random_string.fqdn.result
  tags                = var.tags
}

# Create a load balancer
resource "azurerm_lb" "vmss" {
 name                = "vmss-lb"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name

 frontend_ip_configuration {
   name                 = "PublicIPAddress"
   public_ip_address_id = azurerm_public_ip.vmss.id
 }

 tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
 loadbalancer_id     = azurerm_lb.vmss.id
 name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
 resource_group_name = azurerm_resource_group.vmss.name
 loadbalancer_id     = azurerm_lb.vmss.id
 name                = "http-running-probe"
 port                = 80
}

resource "azurerm_lb_rule" "lbnatrule" {
   resource_group_name            = azurerm_resource_group.vmss.name
   loadbalancer_id                = azurerm_lb.vmss.id
   name                           = "http"
   protocol                       = "Tcp"
   frontend_port                  = 80
   backend_port                   = 80
   backend_address_pool_id        = azurerm_lb_backend_address_pool.bpepool.id
   frontend_ip_configuration_name = "PublicIPAddress"
   probe_id                       = azurerm_lb_probe.vmss.id
}

data "template_file" "script" {
  template = file("cloud-init.conf")
}

data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "cloud-init.conf"
    content_type = "text/cloud-config"
    content      = data.template_file.script.rendered
  }
  depends_on = [azurerm_mysql_server.vmss]
}

resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                            = "vmss"
  resource_group_name             = azurerm_resource_group.vmss.name
  location                        = azurerm_resource_group.vmss.location
  sku                             = "Standard_F2"
  instances                       = 2
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  custom_data                     = data.template_cloudinit_config.config.rendered

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name                      = "networkinterface"
    primary                   = true

    ip_configuration {
      name                                   = "IPConfiguration"
      primary                                = true
      subnet_id                              = azurerm_subnet.vmss.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
    }
  }
}