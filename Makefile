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
	./scripts/cleanup-aws-resources.sh
	cd infra && TF_VAR_enable_argocd=false terraform destroy -auto-approve

plan:
	cd infra && terraform plan

kube:
	aws eks update-kubeconfig --name $(ENV)-eks --region $(REGION)

security:
	./scripts/verify-security.sh

cleanup:
	./scripts/cleanup-aws-resources.sh

.PHONY: up down plan kube security cleanup
