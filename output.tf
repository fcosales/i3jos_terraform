output "vmss_public_ip" {
  value = azurerm_public_ip.vmss.fqdn
}

output "mysql_server" {
  value = azurerm_mysql_server.vmss.fqdn
}

output "mysql_database" {
  value = azurerm_mysql_database.vmss.name
}

// output "jumpbox_public_ip" {
//    value = azurerm_public_ip.jumpbox.fqdn
// }