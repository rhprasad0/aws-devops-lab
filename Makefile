ENV ?= dev
REGION ?= us-east-1

up:
	cd infra && terraform init
	cd infra && terraform apply -target=module.vpc -auto-approve
	cd infra && terraform apply -target=module.eks.aws_eks_cluster.this -auto-approve
	cd infra && terraform apply -auto-approve
	aws eks update-kubeconfig --name $(ENV)-eks --region $(REGION)
	kubectl get nodes

down:
	cd infra && terraform destroy -auto-approve

plan:
	cd infra && terraform plan

kube:
	aws eks update-kubeconfig --name $(ENV)-eks --region $(REGION)

.PHONY: up down plan kube
