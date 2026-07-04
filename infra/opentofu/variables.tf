variable "oci_profile" {
  description = "OCI CLI profile to use from ~/.oci/config."
  type        = string
  default     = "DEFAULT"
}

variable "tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment OCID for Mattermost resources."
  type        = string
}

variable "region" {
  description = "OCI region, for example us-phoenix-1."
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key installed for the ubuntu user."
  type        = string
}

variable "admin_allowed_cidr" {
  description = "Admin public IP/CIDR allowed to SSH."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for OCI resource display names."
  type        = string
  default     = "mattermost"
}

variable "availability_domain_index" {
  description = "Zero-based availability domain index for the compute instance."
  type        = number
  default     = 0
}

variable "vcn_cidr" {
  description = "VCN CIDR block."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "Public subnet CIDR block."
  type        = string
  default     = "10.20.1.0/24"
}

variable "instance_shape" {
  description = "OCI compute shape."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "OCPUs for the A1 Flex instance."
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memory in GB for the A1 Flex instance."
  type        = number
  default     = 12
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB."
  type        = number
  default     = 50
}

variable "backup_bucket_name" {
  description = "Object Storage bucket for backups."
  type        = string
  default     = "mattermost-backups"
}

variable "backup_retention_days" {
  description = "Object Storage daily/ backup retention."
  type        = number
  default     = 60
}

variable "prod_hostname" {
  description = "Production DNS hostname. DNS update remains manual."
  type        = string
}

variable "test_hostname" {
  description = "Test DNS hostname. DNS update remains manual."
  type        = string
}
