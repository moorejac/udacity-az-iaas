output "cluster_public_ip" {
    value = azurerm_public_ip.cluster.fqdn
}
