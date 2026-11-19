.PHONY: help install run test lint up down tf-init tf-plan tf-apply k8s-deploy k8s-status

COMPOSE_ALL := docker compose -f docker-compose.yml -f docker-compose.monitoring.yml
ENV ?= staging
TF := terraform -chdir=terraform

help: ## Show targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

install: ## Install app and dev dependencies
	pip install -r requirements-dev.txt

run: ## Run the app with reload on :8080
	uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload

test: ## Tests with coverage
	pytest --cov=app --cov-report=term

lint: ## flake8 + shellcheck
	flake8 app tests --max-line-length=120 --max-complexity=10
	shellcheck scripts/*.sh

up: ## App + monitoring stack
	$(COMPOSE_ALL) up -d --build

down: ## Stop everything
	$(COMPOSE_ALL) down

tf-init: ## terraform init (ENV=staging|production)
	$(TF) init -reconfigure -backend-config=envs/$(ENV).s3.tfbackend

tf-plan: ## terraform plan for ENV
	$(TF) plan -var-file=envs/$(ENV).tfvars -out=$(ENV).tfplan

tf-apply: ## Apply the saved plan for ENV
	$(TF) apply $(ENV).tfplan

k8s-deploy: ## Apply the manifests (needs k8s/secret.env)
	kubectl apply -k k8s/

k8s-status: ## Show what is running
	kubectl get pods,svc,hpa -n devops-task
