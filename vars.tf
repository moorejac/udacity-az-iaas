variable "location" {
    description = "The location where resources are created"
    default = "West US"
}

variable "prefix" {
    description = "The prefix to be used for all resources"
    default = "udacity-devops"
}

variable "tags" {
    description = "The tags assigned to each resource"
    default = {project = "project_1"}
}

variable "application_port" {
    description = "The port that you want to expose to the external load balancer"
    default = 80
}

variable "vmss_capacity" {
    description = "The number of VMs to create in the scale set"
    default = 3
}

variable "admin_user" {
    description = "User name to use as the admin account on the VMs that will be part of the VM Scale Set"
    default = "vmssadminuser"
}

variable "admin_password" {
    description = "Default password for admin"
    default = "*****"
}