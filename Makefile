ENV ?= dev
REGION ?= us-east-1

up:
	@echo "🚀 Starting EKS lab deployment..."
	cd infra && terraform init
	@echo "🏗️  Deploying infrastructure (this takes ~15 minutes)..."
	cd infra && terraform apply -auto-approve
	@echo "⚙️  Configuring kubectl..."
	aws eks update-kubeconfig --name $(ENV)-eks --region $(REGION)
	@echo "✅ Verifying cluster nodes..."
	kubectl get nodes
	@echo "🎯 Deploying Argo CD applications..."
	cd infra && terraform apply -var="enable_argocd_apps=true" -auto-approve
	@echo "🎉 Deployment complete!"

down:
	@echo "🧹 Cleaning up AWS resources..."
	@$(MAKE) cleanup-check
	@echo "💥 Destroying Terraform infrastructure..."
	cd infra && terraform destroy -auto-approve
	@echo "✅ Cleanup complete!"

plan:
	cd infra && terraform plan

kube:
	aws eks update-kubeconfig --name $(ENV)-eks --region $(REGION)

# Verify security baseline services using AWS CLI
security:
	@echo "🔍 Verifying Security Baseline Services..."
	@echo "📡 Checking GuardDuty..."
	@aws guardduty list-detectors --query 'DetectorIds[0]' --output text --region $(REGION) | grep -v None || echo "❌ GuardDuty not enabled"
	@echo "📋 Checking Config..."
	@aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[0].name' --output text --region $(REGION) 2>/dev/null | grep -v None || echo "❌ Config not enabled"
	@echo "🛡️  Checking Security Hub..."
	@aws securityhub describe-hub --region $(REGION) --query 'HubArn' --output text 2>/dev/null | grep -v None || echo "❌ Security Hub not enabled"

# Check for leaked AWS resources by project tags
cleanup-check:
	@echo "🔍 Checking for leaked resources with project tag..."
	@echo "Load Balancers:"
	@aws elbv2 describe-load-balancers --region $(REGION) --query "LoadBalancers[?contains(keys(Tags), 'project') && Tags.project=='eks-ephemeral-lab'].[LoadBalancerName,State.Code]" --output table 2>/dev/null || echo "None found"
	@echo "Security Groups:"
	@aws ec2 describe-security-groups --region $(REGION) --query "SecurityGroups[?contains(keys(Tags), 'project') && Tags.project=='eks-ephemeral-lab'].[GroupName,GroupId]" --output table 2>/dev/null || echo "None found"

checkov:
	@echo "🔍 Running Checkov security scan..."
	cd infra && checkov -d . --framework terraform --compact

checkov-detailed:
	@echo "🔍 Running detailed Checkov security scan..."
	cd infra && checkov -d . --framework terraform

# Refresh AWS credentials for MCP server (after aws login)
creds:
	@./scripts/refresh-aws-creds.sh

.PHONY: up down plan kube security cleanup-check checkov checkov-detailed creds
