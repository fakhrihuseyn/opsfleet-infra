# Makefile for staging and deploying infra and karpenter
.PHONY: help init-validate-dev plan-dev deploy-dev karpenter-dev destroy-dev deploy-prod karpenter-prod destroy-prod validate-dev validate-prod

help:
	@printf "\nUsage: make <target>\n\nAvailable targets:\n"
	@printf "  init-validate           Initialize and validate Terraform\n"
	@printf "  plan-dev           	   Show full plan for dev (no -target)\n"
	@printf "  plan-staging       	   Show plan for staging with -target options\n"
	@printf "  plan-prod          	   Show full plan for prod (no -target)\n"
	@printf "  deploy-dev              Deploy dev infrastructure (Stage A)\n"
	@printf "  karpenter-dev           Install Karpenter for dev (Stage B)\n"
	@printf "  validate-dev            Init and validate Terraform for dev\n"
	@printf "  destroy-dev             Destroy dev infrastructure\n"
	@printf "  destroy-karpenter-dev   Destroy only Karpenter in dev\n"
	@printf "  destroy-eks-dev         Destroy only EKS module in dev\n"
	@printf "  deploy-prod             Deploy prod infrastructure (Stage A)\n"
	@printf "  karpenter-prod          Install Karpenter for prod (Stage B)\n"
	@printf "  validate-prod           Init and validate Terraform for prod\n"
	@printf "  destroy-prod            Destroy prod infrastructure\n\n"

init-validate:
	terraform init -upgrade
	terraform validate

plan-dev:
	@printf "###### Planning full dev environment ######.\n ###### This may take a few minutes...######\n"
	terraform init -upgrade
	terraform plan -var-file=env/dev/dev.tfvars

plan-staging:
	@printf "###### Planning full staging environment ######.\n ###### This may take a few minutes...######\n"
	terraform init -upgrade
	terraform plan -var-file=env/stage/stage.tfvars

plan-prod:
	@printf "###### Planning full prod environment ######.\n ###### This may take a few minutes...######\n"
	terraform init -upgrade
	terraform plan -var-file=env/prod/prod.tfvars


deploy-dev:
	terraform init -upgrade
	terraform apply -var-file=env/dev/dev.tfvars \
		-target=aws_vpc.netw \
		-target=aws_eks_cluster.core \
		-target=aws_iam_role.eks_cluster \
		-target=aws_iam_role.node_group \
		-target=aws_iam_instance_profile.node \
		-target=aws_eks_node_group.amd64 \
		-target=aws_eks_node_group.arm64 -auto-approve

karpenter-dev:
	# Stage B: configure kubernetes provider and install Karpenter
	terraform init -upgrade
	terraform apply -var-file=env/dev/dev.tfvars \
		-target=kubernetes_namespace.karpenter \
		-target=kubernetes_service_account.karpenter \
		-target=aws_iam_role.karpenter_controller \
		-target=helm_release.karpenter -auto-approve


# Destroy dev environment
destroy-dev:
	terraform destroy -var-file=env/dev/dev.tfvars -auto-approve

# Destraction of specific modules can be done by targeting them individually
# Example: destroy only karpenter module

# Destraction of specific modules can be done by targeting them individually
# Example: destroy only karpenter module
destroy-karpenter-dev:
	terraform destroy -var-file=env/dev/dev.tfvars -target=module.karpenter -auto-approve
# Example: destroy only EKS module

destroy-eks-dev:
	terraform destroy -var-file=env/dev/dev.tfvars -target=module.eks -auto-approve

# Makefile for production staging and deploying infra and karpenter
.PHONY: deploy-prod karpenter-prod destroy-prod

validate-prod:
	terraform init -upgrade
	terraform validate

plan-prod-full:
	terraform init -upgrade
	terraform plan -var-file=env/prod/prod.tfvars

deploy-prod:
	terraform init -upgrade
	terraform apply -var-file=env/prod/prod.tfvars -target=module.vpc -target=module.eks -target=module.iam_eks -target=module.iam_karpenter -auto-approve

karpenter-prod:
	terraform init -upgrade
	terraform apply -var-file=env/prod/prod.tfvars -target=module.karpenter -auto-approve

destroy-prod:
	terraform destroy -var-file=env/prod/prod.tfvars -auto-approve

# Destraction of specific modules can be done by targeting them individually
# Example: destroy only karpenter module
# Destraction of specific modules can be done by targeting them individually
# Example: destroy only karpenter module
destroy-karpenter-prod:
	terraform destroy -var-file=env/prod/prod.tfvars -target=module.karpenter -auto-approve
# Example: destroy only EKS module
destroy-eks-prod:
	terraform destroy -var-file=env/prod/prod.tfvars -target=module.eks -auto-approve
