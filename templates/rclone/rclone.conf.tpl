# Rendered on the VM by scripts/render-rclone-config.sh (or bootstrap).
# Uses OCI instance principal — no customer secret keys on disk for Object Storage.
[oci-files]
type = oracleobjectstorage
provider = instance_principal_auth
namespace = ${OBJECT_STORAGE_NAMESPACE}
compartment = ${COMPARTMENT_OCID}
region = ${MM_FILESETTINGS_AMAZONS3REGION}
