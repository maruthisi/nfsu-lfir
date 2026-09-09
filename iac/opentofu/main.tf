# Config is split: config.yaml (shared), source.yaml (senders), mirror.yaml (receivers).
# Shared secrets (keys/, .env) live at the REPO ROOT, two levels up from this module.
locals {
  cfg = yamldecode(file("${path.module}/config.yaml"))
  src = yamldecode(file("${path.module}/source.yaml")) # senders
  mir = yamldecode(file("${path.module}/mirror.yaml")) # receivers

  keys_dir = "${path.module}/../../keys" # keys live at the repo root

  sim_pubkey  = trimspace(file("${local.keys_dir}/sim_key.pub"))
  mgmt_pubkey = trimspace(var.mgmt_ssh_pubkey)

  # Root logins on every VM: your management key plus anyone in keys/admins.txt.
  admin_keys = concat(
    [local.mgmt_pubkey],
    [for line in split("\n", file("${local.keys_dir}/admins.txt")) :
    trimspace(line) if trimspace(line) != "" && !startswith(trimspace(line), "#")],
  )
}

# Root password the Linode API requires; we log in with keys, so it's random.
resource "random_password" "root" {
  length  = 32
  special = true
}

# ---- MIRROR machines (receivers; students investigate these) ----------------
resource "linode_instance" "mirror" {
  count           = local.mir.count
  label           = format("mirror-%02d", count.index + 1)
  region          = local.mir.region
  type            = local.cfg.simulation.instance_type
  image           = local.cfg.simulation.image
  root_pass       = random_password.root.result
  authorized_keys = local.admin_keys

  metadata {
    user_data = base64encode(templatefile("${path.module}/templates/mirror-init.yaml.tftpl", {
      sim_pubkey     = local.sim_pubkey
      student_pubkey = trimspace(file("${local.keys_dir}/students/${format("mirror-%02d", count.index + 1)}.pub"))
    }))
  }
}

# ---- SOURCE machines (senders) ----------------------------------------------
# Bare VMs on purpose: the file copy + timing is done by the Ansible playbook,
# NOT baked into the image. Root access comes from admin_keys.
resource "linode_instance" "source" {
  count           = local.src.count
  label           = format("source-%02d", count.index + 1)
  region          = element(local.src.regions, count.index % length(local.src.regions))
  type            = local.cfg.simulation.instance_type
  image           = local.cfg.simulation.image
  root_pass       = random_password.root.result
  authorized_keys = local.admin_keys

  metadata {
    user_data = base64encode(file("${path.module}/templates/source-init.yaml"))
  }
}

# ---- Ansible inventory: regenerated on every apply, from the real IPs --------
resource "local_file" "ansible_hosts" {
  filename = "${path.module}/../ansible/inventory/hosts.yml"
  content = yamlencode({
    all = {
      vars = {
        ansible_user                 = "root"
        ansible_ssh_private_key_file = "~/.ssh/id_ed25519"
        ansible_ssh_common_args      = "-o StrictHostKeyChecking=no"
      }
      children = {
        sources = {
          hosts = { for s in linode_instance.source : s.label => {
            ansible_host = one(s.ipv4)
            region       = s.region
          } }
        }
        mirrors = {
          hosts = { for m in linode_instance.mirror : m.label => {
            ansible_host = one(m.ipv4)
            region       = local.mir.region
          } }
        }
      }
    }
  })
}

# ---- Hand-out inventory (label / role / region / public IP) -----------------
resource "local_file" "inventory" {
  filename = "${path.module}/inventory.csv"
  content = join("\n", concat(
    ["label,role,region,public_ip"],
    formatlist("%s,source,%s,%s",
      linode_instance.source[*].label,
      linode_instance.source[*].region,
    [for s in linode_instance.source : one(s.ipv4)]),
    formatlist("%s,mirror,%s,%s",
      linode_instance.mirror[*].label,
      local.mir.region,
    [for m in linode_instance.mirror : one(m.ipv4)]),
  ))
}

# ---- Student hand-out: which mirror, its IP, and the key file to email --------
resource "local_file" "handout" {
  filename = "${path.module}/handout.csv"
  content = join("\n", concat(
    ["mirror,public_ip,private_key_file,login_command"],
    [for m in linode_instance.mirror :
      format("%s,%s,keys/students/%s,ssh -i keys/students/%s analyst@%s",
    m.label, one(m.ipv4), m.label, m.label, one(m.ipv4))],
  ))
}
