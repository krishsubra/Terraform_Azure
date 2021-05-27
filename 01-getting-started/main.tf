##############
# Terraform
##############

##########################################################################
# This will create the following
/* 
1. Create Resource Group
2. Create Vnet
3. Create a subnet
4. Create a Public IP
5. Create a NSG ( Network Security Group )
6. Create a NIC
7. Connect NSG and NIC
8. Use a plugin to generate random Text for unique storage account name
9. Create storage account for storing boot diagnostics of a VM.
10. Create a SSH key to inject to VM.
11. Create a VM.
12. Associate NIC and Storage + OS image + keys to use.
*/
##########################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

##################
# Define provider
##################
provider "azurerm" {
  features {}
}

###########################
# Create a resource group
###########################
resource "azurerm_resource_group" "myterraformgroup" {
  name     = "myResourceGroup-TF"
  location = "eastus"

  tags = {
    environment = "Terraform Demo"
  }
}

###########################
# Create a Virtual network
###########################
resource "azurerm_virtual_network" "myterraformnetwork" {
  name                = "myVnet-TF"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus"
  resource_group_name = azurerm_resource_group.myterraformgroup.name

  tags = {
    environment = "Terraform Demo"
  }
}

#################
# Create subnet
#################
resource "azurerm_subnet" "myterraformsubnet" {
  name                 = "mySubnet-TF"
  resource_group_name  = azurerm_resource_group.myterraformgroup.name
  virtual_network_name = azurerm_virtual_network.myterraformnetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

###################
# Create public IP
###################
resource "azurerm_public_ip" "myterraformpublicip" {
  name                = "myPublicIP-TF"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.myterraformgroup.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "Terraform Demo"
  }
}

################################
# Create network security Group
################################
resource "azurerm_network_security_group" "myterraformnsg" {
  name                = "myNetworkSecurityGroup-TF"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.myterraformgroup.name

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

  tags = {
    environment = "Terraform Demo"
  }

}

#############
# Create NIC
#############
resource "azurerm_network_interface" "myterraformnic" {
  name                = "myNIC-TF"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.myterraformgroup.name


  ip_configuration {
    name                          = "myNicConfiguration"
    subnet_id                     = azurerm_subnet.myterraformsubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.myterraformpublicip.id
  }

  tags = {
    environment = "Terraform Demo"
  }
}

################################
# Connect Security Group to NIC
################################
resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.myterraformnic.id
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id
}

#######################################################
# Generate random text for unique storage account name
#######################################################
resource "random_id" "randomId" {
  # This is a plugin => so need to run terraform init again while running this for first time.
  keepers = {
    resource_group = azurerm_resource_group.myterraformgroup.name
  }

  byte_length = 8
}

###############################################
# Create Storage account for boot diagnaostics
###############################################
resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = azurerm_resource_group.myterraformgroup.name
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "Terraform Demo"
  }
}

###################
# Create SSH Key
###################
resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

######################
# Register Output key
######################
output "tls_private_key" {
  value     = tls_private_key.example_ssh.private_key_pem
  sensitive = true
}

##########################
# Create virtual machine
##########################
resource "azurerm_linux_virtual_machine" "myterraformvm" {
  name                  = "myVM-TF"
  location              = "eastus"
  resource_group_name   = azurerm_resource_group.myterraformgroup.name
  network_interface_ids = [azurerm_network_interface.myterraformnic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "myvm-1-TF"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    # This file will be taken from the local user home directory.
    # if you run this from Azure shell, will be taken from there.
    # you can create a key pair before making the terraform apply run.
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }

  tags = {
    environment = "Terraform Demo"
  }

}
