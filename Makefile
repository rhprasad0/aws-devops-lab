ENV ?= dev
REGION ?= us-east-1

up:
	cd infra && terraform init && terraform apply

down:
	cd infra && terraform destroy

plan:
	cd infra && terraform plan

.PHONY: up down plan
