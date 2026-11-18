environment = "staging"

# Cloud VPS 10 (4 vCPU / 8 GB) - enough for the app plus the monitoring stack.
# Product ids change over time, double check in the Contabo API docs.
product_id = "V91"
region     = "EU"

# Ubuntu 24.04 - confirm the id with: cntb get images --name ubuntu
image_id = "d64d5c6c-9dda-4e38-8174-0ee282474d8a"

ssh_public_key   = "ssh-ed25519 AAAA... deploy@devops-task"
allowed_ssh_cidr = "0.0.0.0/0"
app_port         = 80

repo_url = "https://github.com/arifuzzamanjoy/devops-task.git"
