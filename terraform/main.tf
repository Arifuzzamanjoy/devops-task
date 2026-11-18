provider "contabo" {
  oauth2_client_id     = var.contabo_client_id
  oauth2_client_secret = var.contabo_client_secret
  oauth2_user          = var.contabo_api_user
  oauth2_pass          = var.contabo_api_password
}

locals {
  name = "devops-task-${var.environment}"

  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    deploy_user      = var.deploy_user
    ssh_public_key   = trimspace(var.ssh_public_key)
    allowed_ssh_cidr = var.allowed_ssh_cidr
    app_port         = var.app_port
    environment      = var.environment
    repo_url         = var.repo_url
    app_dir          = var.app_dir
  })
}

# SSH key stored in the Contabo secret store and injected at install time
resource "contabo_secret" "ssh_key" {
  name  = "${local.name}-ssh"
  type  = "ssh"
  value = trimspace(var.ssh_public_key)
}

# Contabo has no security groups or instance roles, so firewall, SSH
# hardening and Docker are set up by cloud-init. Changing user_data
# reinstalls the server, so it is bootstrap only; later changes go through CD.
resource "contabo_instance" "app" {
  display_name = local.name
  product_id   = var.product_id
  region       = var.region
  image_id     = var.image_id
  period       = var.period
  ssh_keys     = [contabo_secret.ssh_key.id]
  user_data    = local.cloud_init
}
