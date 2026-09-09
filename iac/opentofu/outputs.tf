output "sources" {
  description = "The malicious source machines and their public IPs (the answer key)."
  value = [for s in linode_instance.source : {
    label     = s.label
    region    = s.region
    public_ip = one(s.ipv4)
  }]
}

output "mirrors" {
  description = "The machines under attack that students investigate."
  value = [for m in linode_instance.mirror : {
    label     = m.label
    public_ip = one(m.ipv4)
  }]
}

output "inventory_csv" {
  description = "Path to the generated hand-out inventory."
  value       = local_file.inventory.filename
}

output "root_password" {
  description = "The shared root password on every VM (for console/Lish; SSH uses keys)."
  value       = var.root_password
  sensitive   = true
}
