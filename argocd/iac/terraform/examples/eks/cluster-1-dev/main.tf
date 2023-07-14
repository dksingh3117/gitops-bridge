provider "aws" {
  region = local.region
}

locals {
  name = "cluster-2-dev"
  region = "us-west-2"
  environment = "dev"
  addons = {
    #enable_prometheus_adapter                    = true # doesn't required aws resources (ie IAM)
    #enable_gpu_operator                          = true # doesn't required aws resources (ie IAM)
    #enable_kyverno                               = true # doesn't required aws resources (ie IAM)
    #enable_argo_rollouts                         = true # doesn't required aws resources (ie IAM)
    #enable_argo_workflows                        = true # doesn't required aws resources (ie IAM)
    #enable_secrets_store_csi_driver              = true # doesn't required aws resources (ie IAM)
    #enable_secrets_store_csi_driver_provider_aws = true # doesn't required aws resources (ie IAM)
    #enable_kube_prometheus_stack                 = true # doesn't required aws resources (ie IAM)
    #enable_gatekeeper                            = true # doesn't required aws resources (ie IAM)
    #enable_ingress_nginx                         = true # doesn't required aws resources (ie IAM)
    enable_metrics_server                        = true # doesn't required aws resources (ie IAM)
    #enable_vpa                                   = true # doesn't required aws resources (ie IAM)
    #aws_enable_ebs_csi_resources                 = true # generate gp2 and gp3 storage classes for ebs-csi
    #enable_prometheus_adapter                    = true # doesn't required aws resources (ie IAM)
    #enable_gpu_operator                          = true # doesn't required aws resources (ie IAM)
    enable_foo                                   = true # you can add any addon here, make sure to update the gitops repo with the corresponding application set
  }
  argocd_bootstrap_control_plane = "https://raw.githubusercontent.com/csantanapr/gitops-control-plane/main/bootstrap/control-plane/exclude/bootstrap.yaml"
  argocd_bootstrap_workloads = "https://raw.githubusercontent.com/csantanapr/gitops-control-plane/main/bootstrap/workloads/exclude/bootstrap.yaml"
}

################################################################################
# GitOps Bridge
################################################################################

module "gitops_bridge_metadata" {
  source = "../../../modules/gitops-bridge-metadata"

  cluster_name = module.eks.cluster_name
  environment = local.environment
  metadata = module.eks_blueprints_addons.gitops_metadata
  addons = local.addons
  #argocd_remote = true
}

################################################################################
# GitOps Bootstrap: Install ArgoCD, Cluster(s), and App of Apps
################################################################################
data "http" "argocd_bootstrap_control_plane" {
  url = local.argocd_bootstrap_control_plane
}
data "http" "argocd_bootstrap_workloads" {
  url = local.argocd_bootstrap_workloads
}
locals {
  manifests = {
      "cluster.yaml" = yamlencode(module.gitops_bridge_metadata.argocd)
      "app_of_apps_control_plane.yaml" = data.http.argocd_bootstrap_control_plane.response_body
      "app_of_apps_workloads.yaml" = data.http.argocd_bootstrap_workloads.response_body
  }
  manifests_path = "${path.module}/manifests"
}
resource "local_file" "argocd_values_yaml" {
  for_each = local.manifests
  content  = each.value
  filename = "${local.manifests_path}/${each.key}"
}

locals {
  kubeconfig = "/tmp/${module.eks.cluster_name}"
  kubeconfig_command = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}
locals {
  argocd_helm_repository = "https://argoproj.github.io/argo-helm"
  argocd_version = "5.38.0"
  argocd_namespace = "argocd"
  argocd_install = true
  argocd_install_script = <<-EOF
    KUBECONFIG=${local.kubeconfig}
    ${local.kubeconfig_command}
    helm repo add argo "${local.argocd_helm_repository}"
    helm repo update
    helm upgrade --install argo-cd argo/argo-cd --version "${local.argocd_version}" --namespace "${local.argocd_namespace}" --create-namespace --wait
    kubectl apply -f ${local.manifests_path}
    echo "{\"NAMESPACE\": \"${local.argocd_namespace}\"}"
  EOF
}
resource "shell_script" "argocd" {
  count = local.argocd_install ? 1 : 0
  lifecycle_commands {
    create = local.argocd_install_script
    update = local.argocd_install_script
    delete = "echo gitops ftw!"
  }
}


################################################################################
# Blueprints Addons
################################################################################

module "eks_blueprints_addons" {
  source = "../../../../../../terraform-aws-eks-blueprints-addons/gitops"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  vpc_id            = module.vpc.vpc_id


  #enable_argo_rollouts                         = true # doesn't required aws resources (ie IAM)
  #enable_argo_workflows                        = true # doesn't required aws resources (ie IAM)
  #enable_secrets_store_csi_driver              = true # doesn't required aws resources (ie IAM)
  #enable_secrets_store_csi_driver_provider_aws = true # doesn't required aws resources (ie IAM)
  #enable_kube_prometheus_stack                 = true # doesn't required aws resources (ie IAM)
  #enable_gatekeeper                            = true # doesn't required aws resources (ie IAM)
  #enable_ingress_nginx                         = true # doesn't required aws resources (ie IAM)
  #enable_metrics_server                         = true # doesn't required aws resources (ie IAM)
  #enable_vpa                                   = true # doesn't required aws resources (ie IAM)

  #enable_aws_efs_csi_driver                    = true
  #enable_aws_fsx_csi_driver                    = true
  #enable_aws_cloudwatch_metrics = true
  #enable_aws_privateca_issuer                  = true
  enable_cert_manager       = true
  #enable_cluster_autoscaler = true
  #enable_external_dns                          = true
  #external_dns_route53_zone_arns = ["arn:aws:route53:::hostedzone/Z123456789"]
  #enable_external_secrets                      = true
  #enable_aws_load_balancer_controller = true
  #enable_aws_for_fluentbit            = true
  #enable_fargate_fluentbit            = true
  #enable_aws_node_termination_handler   = true
  #aws_node_termination_handler_asg_arns = [for asg in module.eks.self_managed_node_groups : asg.autoscaling_group_arn]
  #enable_karpenter = true
  #enable_velero = true
  ## An S3 Bucket ARN is required. This can be declared with or without a Suffix.
  #velero = {
  #  s3_backup_location = "${module.velero_backup_s3_bucket.s3_bucket_arn}/backups"
  #}
  #enable_aws_gateway_api_controller = true

  tags = local.tags
}

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.14"

  role_name_prefix = "${local.name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}


################################################################################
# Cluster
################################################################################
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/csantanapr/terraform-gitops-bridge"
  }
}

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.13"

  cluster_name                   = local.name
  cluster_version                = "1.27"
  cluster_endpoint_public_access = true


  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["t3.medium"]

      min_size     = 3
      max_size     = 10
      desired_size = 3
    }
  }
  # EKS Addons
  cluster_addons = {
    vpc-cni = {
      # Specify the VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      before_compute = true
      most_recent    = true # To ensure access to the latest settings provided
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

/*
locals {
  fluxcd_cluster_manifest = "${path.module}/fluxcd.yaml"
}
resource "local_file" "fluxcd_yaml" {
  content  = yamlencode(module.gitops_bridge_metadata.fluxcd)
  filename = local.fluxcd_cluster_manifest
}
*/