terraform {
  required_version = ">= 1.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0"
    }
  }
}

# Credentials come from ~/.oci/config ([DEFAULT] profile) unless the tenancy/user/fingerprint
# variables are set. The region always comes from var.region.
provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid != "" ? var.tenancy_ocid : null
  user_ocid        = var.user_ocid != "" ? var.user_ocid : null
  fingerprint      = var.fingerprint != "" ? var.fingerprint : null
  private_key_path = var.fingerprint != "" ? var.private_key_path : null
}
