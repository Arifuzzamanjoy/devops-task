# --- Contabo API credentials (pass via TF_VAR_* env vars, never in tfvars) ---

variable "contabo_client_id" {
  description = "Contabo API OAuth2 client id"
  type        = string
  sensitive   = true
}

variable "contabo_client_secret" {
  description = "Contabo API OAuth2 client secret"
  type        = string
  sensitive   = true
}

variable "contabo_api_user" {
  description = "Contabo API user (account email)"
  type        = string
  sensitive   = true
}

variable "contabo_api_password" {
  description = "Contabo API password"
  type        = string
  sensitive   = true
}

# --- Environment ---

variable "environment" {
  description = "Deployment environment"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

# --- Server ---

variable "product_id" {
  description = "Contabo product id (VPS size). Check the product list in the Contabo API docs."
  type        = string
}

variable "region" {
  description = "Contabo region (EU, US-central, US-east, US-west, UK, SIN, JPN, AUS)"
  type        = string
  default     = "EU"
}

variable "image_id" {
  description = "OS image id (Ubuntu 24.04). List with: cntb get images --name ubuntu"
  type        = string
}

variable "period" {
  description = "Contract period in months"
  type        = number
  default     = 1
}

# --- Access ---

variable "ssh_public_key" {
  description = "Public key installed for the deploy user and root"
  type        = string
}

variable "deploy_user" {
  description = "Non-root user used by CI to deploy"
  type        = string
  default     = "deploy"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to reach SSH. GitHub-hosted runners need 0.0.0.0/0 (key-only auth + fail2ban)."
  type        = string
  default     = "0.0.0.0/0"
}

# --- App ---

variable "app_port" {
  description = "Public port the app is published on"
  type        = number
  default     = 80
}

variable "repo_url" {
  description = "Public git repo cloned onto the server at bootstrap"
  type        = string
}

variable "app_dir" {
  description = "Where the repo lives on the server"
  type        = string
  default     = "/opt/devops-task"
}
