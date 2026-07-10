data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_ocid
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  ubuntu_image_id     = data.oci_core_images.ubuntu.images[0].id
  cloud_init          = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {})
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_block     = var.vcn_cidr
  display_name   = "${var.name_prefix}-vcn"
  dns_label      = "mattermost"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-public-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.subnet_cidr
  display_name               = "${var.name_prefix}-public-subnet"
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
}

resource "oci_core_network_security_group" "mattermost" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nsg"
}

resource "oci_core_network_security_group_security_rule" "ssh" {
  network_security_group_id = oci_core_network_security_group.mattermost.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.admin_allowed_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Admin SSH"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "http" {
  network_security_group_id = oci_core_network_security_group.mattermost.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "HTTP redirect and ACME"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "https" {
  network_security_group_id = oci_core_network_security_group.mattermost.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "HTTPS"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# Mattermost Calls WebRTC media (UDP); must match MM_CALLS_UDP_SERVER_PORT in compose.
resource "oci_core_network_security_group_security_rule" "calls_udp" {
  network_security_group_id = oci_core_network_security_group.mattermost.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Mattermost Calls media UDP"

  udp_options {
    destination_port_range {
      min = 8443
      max = 8443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "egress" {
  network_security_group_id = oci_core_network_security_group.mattermost.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Outbound package, image, STUN, and Object Storage access"
}

resource "oci_core_instance" "mattermost" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "${var.name_prefix}-free-01"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.mattermost.id]
    display_name     = "${var.name_prefix}-vnic"
  }

  source_details {
    source_type             = "image"
    source_id               = local.ubuntu_image_id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init)
  }
}

resource "oci_objectstorage_bucket" "backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.backup_bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

resource "oci_objectstorage_bucket" "files" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.file_bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

resource "oci_objectstorage_object_lifecycle_policy" "backups" {
  namespace = data.oci_objectstorage_namespace.this.namespace
  bucket    = oci_objectstorage_bucket.backups.name

  depends_on = [oci_identity_policy.object_lifecycle_service]

  rules {
    name        = "expire-daily-backups"
    action      = "DELETE"
    target      = "objects"
    is_enabled  = true
    time_amount = var.backup_retention_days
    time_unit   = "DAYS"

    object_name_filter {
      inclusion_prefixes = ["daily/"]
    }
  }
}

resource "oci_identity_policy" "object_lifecycle_service" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-object-lifecycle"
  description    = "Allow Object Storage lifecycle jobs to expire backup objects"

  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_ocid}"
  ]
}

resource "oci_identity_dynamic_group" "backup_writers" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-backup-writers"
  description    = "Mattermost VM instance principal for backup and filestore Object Storage access"
  matching_rule  = "instance.id = '${oci_core_instance.mattermost.id}'"
}

resource "oci_identity_policy" "backup_writers" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-backup-writers"
  description    = "Allow Mattermost instance to manage backup bucket objects only"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.backup_writers.name} to read buckets in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.backups.name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.backup_writers.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.backups.name}'",
  ]
}

resource "oci_identity_policy" "filestore_writers" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-filestore-writers"
  description    = "Allow Mattermost instance principal to manage filestore bucket via local S3 proxy (rclone)"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.backup_writers.name} to inspect buckets in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.backup_writers.name} to read buckets in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.files.name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.backup_writers.name} to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name='${oci_objectstorage_bucket.files.name}', any {request.permission='OBJECT_INSPECT', request.permission='OBJECT_READ', request.permission='OBJECT_CREATE', request.permission='OBJECT_OVERWRITE', request.permission='OBJECT_DELETE'}}",
  ]
}
