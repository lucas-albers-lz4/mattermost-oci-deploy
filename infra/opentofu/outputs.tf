output "public_ip" {
  description = "Public IP assigned to the Mattermost VM."
  value       = oci_core_instance.mattermost.public_ip
}

output "instance_id" {
  description = "Mattermost VM instance OCID."
  value       = oci_core_instance.mattermost.id
}

output "backup_bucket_name" {
  description = "Object Storage bucket used for backups."
  value       = oci_objectstorage_bucket.backups.name
}

output "object_storage_namespace" {
  description = "Object Storage namespace."
  value       = data.oci_objectstorage_namespace.this.namespace
}

output "prod_hostname" {
  description = "Production hostname for manual DNS update."
  value       = var.prod_hostname
}

output "test_hostname" {
  description = "Test hostname for manual DNS update."
  value       = var.test_hostname
}

output "dns_manual_step" {
  description = "Manual DNS checkpoint."
  value       = "Point ${var.prod_hostname} and ${var.test_hostname} to ${oci_core_instance.mattermost.public_ip} in DNS."
}

output "ssh_command" {
  description = "SSH command for the new VM."
  value       = "ssh ubuntu@${oci_core_instance.mattermost.public_ip}"
}
