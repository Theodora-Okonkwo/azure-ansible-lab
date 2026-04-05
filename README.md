# Azure Ansible Lab — Static Web Deployment with Nginx

**Author:** Theodora Okonkwo
**Assignment:** Multi-Play Ansible Playbook — Install Nginx, Deploy Static Site, Verify Deployment
**Tools:** Terraform · Ansible · Azure · WSL Ubuntu

---

## Overview

This project provisions 2 Azure Linux VMs using Terraform, deploys a static
website using a multi-play Ansible playbook, and verifies the deployment
returns HTTP 200 — all from a local WSL controller without logging into
any VM manually.

---

## Project Structure

```
azure-ansible-lab/
├── main.tf              # All Azure resources
├── variables.tf         # Variable declarations
├── terraform.tfvars     # Variable values (not committed — see .gitignore)
├── outputs.tf           # Output definitions
└── static-web/
    ├── inventory.ini    # Ansible host list
    ├── site.yml         # Multi-play Ansible playbook
    ├── README.md        # This file
    └── files/
        └── index.html   # Static site content (staged on controller)
```

---

## Prerequisites

| Tool      | Notes                                         |
|-----------|-----------------------------------------------|
| Terraform | Via HashiCorp apt repo                        |
| Ansible   | Via Python venv                               |
| Azure CLI | Linux version required (not Windows)          |
| WSL       | Ubuntu 22.04 set as default distro            |
| SSH Key   | RSA 4096-bit — Azure does NOT support ED25519 |

---

## VM Details

| Role | Hostname | Public IP        |
|------|----------|------------------|
| web1 | vm-web1  | <web1_public_ip> |
| web2 | vm-web2  | <web2_public_ip> |

> **Note:** IPs change after terraform destroy and re-apply.
> Run terraform output vm_roles_with_ips to get the current IPs.

---

## 1. Terraform — Infrastructure

### Resources Created (20 total)

- 1 Resource Group
- 1 Virtual Network
- 1 Subnet
- 1 Network Security Group (SSH port 22 + HTTP port 80)
- 4 Public IPs (Standard SKU)
- 4 Network Interface Cards
- 4 NSG Associations
- 4 Ubuntu 22.04 VMs

### Variables

| Variable            | Value                        | Description          |
|---------------------|------------------------------|----------------------|
| vm_roles            | ["web1","web2","app1","db1"] | VM role names        |
| location            | East US                      | Azure region         |
| resource_group_name | rg-ansible-lab               | Resource group name  |
| admin_username      | azureuser                    | VM admin user        |
| vm_size             | Standard_B2ms                | 2 vCPU, 8GB RAM      |
| ssh_public_key_path | ~/.ssh/id_rsa_azure.pub      | RSA public key path  |
| vnet_address_space  | 10.0.0.0/16                  | Virtual network CIDR |
| subnet_prefix       | 10.0.1.0/24                  | Subnet CIDR          |

### main.tf

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  ssh_public_key = file(var.ssh_public_key_path)
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-ansible-lab"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "subnet-ansible-lab"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefix]
}

resource "azurerm_network_security_group" "main" {
  name                = "nsg-ansible-lab"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "main" {
  count               = length(var.vm_roles)
  name                = "pip-${var.vm_roles[count.index]}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "main" {
  count               = length(var.vm_roles)
  name                = "nic-${var.vm_roles[count.index]}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  count                     = length(var.vm_roles)
  network_interface_id      = azurerm_network_interface.main[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_linux_virtual_machine" "main" {
  count               = length(var.vm_roles)
  name                = "vm-${var.vm_roles[count.index]}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.main[count.index].id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
```

### variables.tf

```hcl
variable "vm_roles" {
  type    = list(string)
  default = ["web1", "web2", "app1", "db1"]
}
variable "location"            { default = "East US" }
variable "resource_group_name" { default = "rg-ansible-lab" }
variable "admin_username"      { default = "azureuser" }
variable "vm_size"             { default = "Standard_B2ms" }
variable "ssh_public_key_path" { default = "~/.ssh/id_ed25519.pub" }
variable "vnet_address_space"  { default = "10.0.0.0/16" }
variable "subnet_prefix"       { default = "10.0.1.0/24" }
```

### outputs.tf

```hcl
output "public_ips" {
  value = [for vm in azurerm_linux_virtual_machine.main : vm.public_ip_address]
}

output "vm_roles_with_ips" {
  value = {
    for i, vm in azurerm_linux_virtual_machine.main :
    var.vm_roles[i] => vm.public_ip_address
  }
}

output "ssh_command_examples" {
  value = [
    for vm in azurerm_linux_virtual_machine.main :
    "ssh ${var.admin_username}@${vm.public_ip_address}"
  ]
}
```

### terraform.tfvars

> ⚠️ This file is excluded from git via .gitignore — never commit it.
> Create your own locally using the template below.

```hcl
vm_roles            = ["web1", "web2", "app1", "db1"]
location            = "<your-azure-region>"
resource_group_name = "<your-resource-group-name>"
admin_username      = "<your-admin-username>"
vm_size             = "<your-vm-size>"
ssh_public_key_path = "<path-to-your-public-key>"
vnet_address_space  = "<your-vnet-cidr>"
subnet_prefix       = "<your-subnet-cidr>"
```

### Deploy Commands

```bash
# Initialise Terraform
terraform init

# Preview resources
terraform plan

# Deploy — type yes when prompted
terraform apply

# Get VM IPs after apply
terraform output vm_roles_with_ips

# Destroy all resources when done
terraform destroy
```

### Reading the Output

```bash
terraform output vm_roles_with_ips

# Example:
# {
#   "web1" = "<web1_public_ip>"
#   "web2" = "<web2_public_ip>"
#   "app1" = "<app1_public_ip>"
#   "db1"  = "<db1_public_ip>"
# }
```

> Only web1 and web2 are used in inventory.ini for this assignment.

---

## 2. Ansible Setup

### Activate venv first

```bash
source ~/ansible-onboarding/.venv/bin/activate
```

### Create folder structure

```bash
mkdir -p ~/ansible-onboarding/azure-ansible-lab/static-web/files
cd ~/ansible-onboarding/azure-ansible-lab/static-web
```

### inventory.ini

```ini
[web]
web1 ansible_host=<web1_public_ip>
web2 ansible_host=<web2_public_ip>

[web:vars]
ansible_user=azureuser
ansible_ssh_private_key_file=~/.ssh/id_rsa_azure
ansible_python_interpreter=/usr/bin/python3
```

> Always use named hosts (web1 ansible_host=IP) — bare IPs alone cause
> Ansible to fail with a parse warning.

### Download index.html

```bash
curl -o files/index.html \
  https://raw.githubusercontent.com/pravinmishraaws/Azure-Static-Website/main/index.html
```

### Edit your name in the footer

```bash
nano files/index.html
# Ctrl+W → search "Your Full Name" → replace with your name
# Ctrl+O → Enter → Ctrl+X to save
```

---

## 3. The Playbook — site.yml

### Playbook Structure

| Play | Target    | Responsibility              | Modules Used   |
|------|-----------|-----------------------------|----------------|
| 1    | web group | Install and configure Nginx | apt, service   |
| 2    | web group | Deploy static content       | copy + handler |
| 3    | localhost | Verify HTTP 200 response    | uri, loop      |

### Full site.yml

```yaml
---
- name: "Play 1 | Install Nginx"
  hosts: web
  become: true
  tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true
    - name: Install Nginx
      ansible.builtin.apt:
        name: nginx
        state: present
    - name: Start and enable Nginx
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true
- name: "Play 2 | Deploy Static Content"
  hosts: web
  become: true
  handlers:
    - name: Reload Nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
  tasks:
    - name: Copy index.html to web servers
      ansible.builtin.copy:
        src: files/index.html
        dest: /var/www/html/index.html
        owner: www-data
        group: www-data
        mode: "0644"
      notify: Reload Nginx
- name: "Play 3 | Verify Deployment"
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Check HTTP 200 from each web server
      ansible.builtin.uri:
        url: "http://{{ hostvars[item]['ansible_host'] }}"
        status_code: 200
      loop: "{{ groups['web'] }}"
```

---

## 4. Running the Deployment

### Step 1 — Test SSH connectivity

```bash
ansible web -i inventory.ini -m ping
```

Expected output:

```
web1 | SUCCESS => { "changed": false, "ping": "pong" }
web2 | SUCCESS => { "changed": false, "ping": "pong" }
```

### Step 2 — Run the playbook

```bash
ansible-playbook -i inventory.ini site.yml
```

### Step 3 — Verify in browser

```
http://<web1_public_ip>
http://<web2_public_ip>
```

### Step 4 — Re-deploy after content changes

```bash
nano files/index.html
ansible-playbook -i inventory.ini site.yml
```

---

## 5. Expected Playbook Output

```
PLAY [Play 1 | Install Nginx] **************************************************
TASK [Gathering Facts] *********************************************************
ok: [web1]
ok: [web2]
TASK [Update apt cache] ********************************************************
changed: [web1]
changed: [web2]
TASK [Install Nginx] ***********************************************************
changed: [web1]
changed: [web2]
TASK [Start and enable Nginx] **************************************************
ok: [web1]
ok: [web2]

PLAY [Play 2 | Deploy Static Content] ******************************************
TASK [Gathering Facts] *********************************************************
ok: [web1]
ok: [web2]
TASK [Copy index.html to web servers] ******************************************
changed: [web1]
changed: [web2]
RUNNING HANDLER [Reload Nginx] *************************************************
changed: [web1]
changed: [web2]

PLAY [Play 3 | Verify Deployment] **********************************************
TASK [Check HTTP 200 from each web server] *************************************
ok: [localhost] => (item=web1)
ok: [localhost] => (item=web2)

PLAY RECAP *********************************************************************
localhost : ok=1  changed=0  unreachable=0  failed=0
web1      : ok=7  changed=4  unreachable=0  failed=0
web2      : ok=7  changed=4  unreachable=0  failed=0
```

> failed=0 on all hosts = clean run. On a second run with no changes,
> changed=0 everywhere — idempotency working correctly.

---

## 6. Troubleshooting

| Problem                          | Cause                         | Fix                                              |
|----------------------------------|-------------------------------|--------------------------------------------------|
| site.yml could not be found      | Wrong directory               | cd into static-web/ first                        |
| Unable to parse inventory.ini    | Bare IPs with no host names   | Use web1 ansible_host=IP format                  |
| SSH connection timeout           | Port 22 blocked               | NSG allow-ssh rule is already in main.tf         |
| Browser shows default Nginx page | index.html not copied yet     | Run the playbook — Play 2 copies the file        |
| uri returns non-200              | Port 80 blocked or Nginx down | Check NSG allow-http rule, rerun playbook        |
| terraform destroy shows 0        | Wrong directory               | Run from azure-ansible-lab/ not static-web/      |
| Ansible not found                | Not in venv                   | source ~/ansible-onboarding/.venv/bin/activate   |

---

## 7. Key Learnings

- **Multi-play playbooks** separate concerns cleanly — install, deploy, and verify are independent plays
- **Handlers** are efficient — Nginx only reloads when index.html actually changes, not on every run
- **copy module** is better than git clone for static content — no Git needed on remote VMs, works offline
- **Play 3 on localhost** — Ansible can target your own machine to verify remote services over HTTP
- **Idempotency** — running the playbook twice gives the same result; changed=0 on second run confirms this
- **Terraform state** lives in the directory where you run Terraform — always run from azure-ansible-lab/
- **Named hosts in inventory** are required — bare IPs cause parse warnings and break hostvars lookups

---

## 8. Cleanup

```bash
cd ~/ansible-onboarding/azure-ansible-lab
terraform destroy
```

> Always run from azure-ansible-lab/ not from static-web/

---

## Resources

- [Terraform AzureRM Provider Docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Ansible Copy Module Docs](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Ansible URI Module Docs](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
- [Ansible Handlers Docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
- [Azure VM Sizes](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes)