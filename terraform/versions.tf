terraform {
  # 1.10+ for S3 native locking (use_lockfile)
  required_version = ">= 1.10"

  required_providers {
    contabo = {
      source  = "contabo/contabo"
      version = "~> 0.1"
    }
  }
}
