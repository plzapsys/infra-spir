resource "proxmox_vm_qemu" "k8s_controlplane" {
  for_each = local.k8s_controlplane

  name        = each.key
  target_node = each.value.target_node
  desc        = "Kubernetes control plane"
  clone       = local.k8s_common.clone_k8s
  vmid        = each.value.vmid

  cpu     = "kvm64"
  sockets = 1
  cores   = each.value.cores
  memory  = each.value.memory

  os_type = "cloud-init"
  qemu_os = "l26"
  agent   = 1
  scsihw  = "virtio-scsi-pci"
  onboot  = true

  ssh_forward_ip = each.value.ip
  ipconfig0      = "ip=${each.value.ip}/24,gw=${local.k8s_common.gw}"
  sshkeys        = var.ssh_pub_keys

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          storage    = each.value.storage_clone_to
          size       = each.value.disk
          discard    = true
          emulatessd = true
          replicate  = true
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = "vmbr1"
    tag    = 13
  }

  vga {
    memory = 0
    type   = "serial0"
  }

  serial {
    id   = 0
    type = "socket"
  }

  lifecycle {
    ignore_changes = [
      clone,
      pool,
      ciuser,
      disks[0].scsi[0].scsi0[0].disk[0].storage,
    ]
  }

  provisioner "remote-exec" {
    inline = ["while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done"]

    connection {
      host        = self.default_ipv4_address
      user        = local.vm_user
      timeout     = "120s"
      private_key = file("~/.ssh/id_rsa")
    }
  }

  # Move disks from shared to local storage
  provisioner "local-exec" {
    command = <<EOT
      for disk in ${local.k8s_common.ci_disk} ${local.k8s_common.boot_disk}; do
        curl --silent --insecure \
          ${var.proxmox_url}/nodes/${each.value.target_node}/qemu/${each.value.vmid}/move_disk \
          --header "Authorization: PVEAPIToken=${var.proxmox_username}=${var.proxmox_token}" \
          --data-urlencode disk="$disk" \
          --data-urlencode storage="${local.k8s_common.storage_move_to}" \
          --data-urlencode delete=1
      done
    EOT
  }
}
