# Config is split: config.yaml (shared), source.yaml (malicious senders),
# mirror.yaml (receivers under attack). Scale each independently.
locals {
  cfg = yamldecode(file("${path.module}/config.yaml"))
  src = yamldecode(file("${path.module}/source.yaml")) # senders
  mir = yamldecode(file("${path.module}/mirror.yaml")) # receivers

  sim_pubkey  = trimspace(file("${path.module}/keys/sim_key.pub"))
  mgmt_pubkey = trimspace(var.mgmt_ssh_pubkey)

  # Root logins on every VM: your management key plus anyone in keys/admins.txt.
  admin_keys = concat(
    [local.mgmt_pubkey],
    [for line in split("\n", file("${path.module}/keys/admins.txt")) :
    trimspace(line) if trimspace(line) != "" && !startswith(trimspace(line), "#")],
  )
}

# Root password the Linode API requires; we log in with keys, so it's random.
resource "random_password" "root" {
  length  = 32
  special = true
}

# ---- MIRROR machines (under attack; students investigate these) -------------
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
      student_pubkey = trimspace(file("${path.module}/keys/students/${format("mirror-%02d", count.index + 1)}.pub"))
    }))
  }
}

# ---- SOURCE machines (malicious senders, spread across non-India regions) ----
resource "linode_instance" "source" {
  count           = local.src.count
  label           = format("source-%02d", count.index + 1)
  region          = element(local.src.regions, count.index % length(local.src.regions))
  type            = local.cfg.simulation.instance_type
  image           = local.cfg.simulation.image
  root_pass       = random_password.root.result
  authorized_keys = local.admin_keys

  metadata {
    user_data = base64encode(templatefile("${path.module}/templates/source-init.yaml.tftpl", {
      filename        = local.cfg.file_transfer.filename
      duration        = local.cfg.simulation.duration_seconds
      min             = local.cfg.file_transfer.min_interval_seconds
      max             = local.cfg.file_transfer.max_interval_seconds
      dest_dir        = local.cfg.file_transfer.dest_dir
      private_key_b64 = base64encode(file("${path.module}/keys/sim_key"))
      drop_sh_b64     = base64encode(file("${path.module}/scripts/drop.sh"))
      setup_once_b64  = base64encode(file("${path.module}/scripts/setup_once.sh"))
      payload_b64     = base64encode(file("${path.module}/malicious_test.txt"))
      # receiver (mirror) PUBLIC IPs, one per line -> /etc/simulation/targets.txt
      targets_b64 = base64encode(join("\n", [for m in linode_instance.mirror : one(m.ipv4)]))
    }))
  }
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
