
terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.1-rc3"
    }
  }
}


provider "proxmox" {
  # Configuration options
  pm_api_url = var.proxmox_api_url
  pm_api_token_id = file(var.proxmox_api_token_id)
  pm_api_token_secret = file(var.proxmox_api_token_secret)
  pm_tls_insecure = true #karena ssl nya masi blm sedcure (http)
}



resource "proxmox_vm_qemu" "k8s-master" {
  name        = "k8s-master"
  target_node = "prk1"
  vmid       = 300
  clone      = "template"
  full_clone = true

  ciuser    = var.ci_user
  cipassword = var.ci_password
  sshkeys   = file(var.ci_ssh_public_key)

  agent     = 1
  cores     = 2
  memory    = 4096
  os_type   = "cloud-init"
  bootdisk  = "scsi0"
  scsihw    = "virtio-scsi-pci"

  disks {
    ide {
      ide0 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = 20
          storage = "local-lvm"
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  boot     = "order=scsi0"
  ipconfig0 = "ip=192.168.2.201/24,gw=192.168.2.69" #gatewaynya ip proxmox
  # ipconfig0 = "ip=dhcp"
  
  lifecycle {
    ignore_changes = [ 
      network
    ]
  }
}

resource "proxmox_vm_qemu" "k8s-workers" {
  count       = var.vm_count
  name        = "k8s-worker-${count.index + 1}"
  target_node = "prk2"
  vmid        = 301 + count.index
  clone       = "template"
  full_clone  = true

  ciuser    = var.ci_user
  cipassword = var.ci_password
  sshkeys   = file(var.ci_ssh_public_key)

  agent     = 1
  cores     = 2
  memory    = 4096
  os_type   = "cloud-init"
  bootdisk  = "scsi0"
  scsihw    = "virtio-scsi-pci"

  disks {
    ide {
      ide0 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = 10
          storage = "local-lvm"
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  boot     = "order=scsi0"
  ipconfig0 = "ip=192.168.3.${count.index + 201}/24,gw=192.168.3.69"
  # ipconfig0 = "ip=dhcp"
  
  lifecycle {
    ignore_changes = [ 
      network
    ]
  }
}

output "vm_info" {
  value = {
    master = {
      hostname = proxmox_vm_qemu.k8s-master.name
      ip_addr  = proxmox_vm_qemu.k8s-master.default_ipv4_address
    },
    workers = [
      for vm in proxmox_vm_qemu.k8s-workers : {
        hostname = vm.name
        ip_addr  = vm.default_ipv4_address
      }
    ]
  }
}

# setelah kelar provisioning, simpen ip addressnya di dlm inventory
resource "local_file" "create_ansible_inventory" {
  depends_on = [
    proxmox_vm_qemu.k8s-master,
    proxmox_vm_qemu.k8s-workers
  ]

  content = <<EOT
[master-node]
${proxmox_vm_qemu.k8s-master.default_ipv4_address}
[worker-node]
${join("\n", [for worker in proxmox_vm_qemu.k8s-workers : worker.default_ipv4_address])}

EOT

  filename = "./inventory.ini"
}

resource "null_resource" "testing_ansible" {
  depends_on = [ local_file.create_ansible_inventory ]
  provisioner "local-exec" {
    command = "sleep 180;ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./inventory.ini init.yml -u ${var.ci_user} --private-key=${var.ci_ssh_private_key}"
  }
}

# resource "null_resource" "install_software" {
#   depends_on = [ local_file.create_ansible_inventory ]
#   provisioner "local-exec" {
#     command = "sleep 180;ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./inventory.ini playbook-install-software.yml -u ${var.ci_user} --private-key=${var.ci_ssh_private_key}"
#   }
# }


# resource "null_resource" "ansible_playbook" {
#     depends_on = [null_resource.testing_ansible]
#     provisioner "local-exec" {
#         command = "sleep 180;ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./inventory.ini playbook-create-k8s-cluster.yml -u ${var.ci_user} --private-key=${var.ci_ssh_private_key}"
#     }
# }



