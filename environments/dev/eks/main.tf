############################
# Remote State from shared #
############################
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "hivewiki-infra-state-bucket"
    key    = "shared/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

###################################
# Remote State from AWS Dev Infra #
###################################
data "terraform_remote_state" "dev_infra" {
  backend = "s3"
  config = {
    bucket = "hivewiki-infra-state-bucket"
    key    = "dev/infra/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

###########
# Kubectl #
###########
provider "kubectl" {
  host                   = data.terraform_remote_state.dev_infra.outputs.eks_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.dev_infra.outputs.eks_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name,
      "--region",
      var.aws_region,
      "--role-arn",
      data.terraform_remote_state.shared.outputs.eks_fullaccess_role_arn
    ]
    command = "aws"
  }
}

########
# Helm #
########
provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.dev_infra.outputs.eks_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.dev_infra.outputs.eks_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name,
        "--region",
        var.aws_region,
        "--role-arn",
        data.terraform_remote_state.shared.outputs.eks_fullaccess_role_arn
      ]
      command = "aws"
    }
  }
}

#############################
# Kubectl - Gateway API CRD #
#############################
data "kubectl_file_documents" "gateway_api_docs" {
  content = file("${path.module}/../../../third-party/gateway-api/standard-install.yaml")
}
resource "kubectl_manifest" "gateway_api" {
  for_each  = data.kubectl_file_documents.gateway_api_docs.manifests
  yaml_body = each.value
}

#################
# Helm - Cilium #
#################
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.19.2"
  namespace  = "kube-system"

  wait    = true
  atomic  = true
  timeout = 900

  values = [
    yamlencode({
      image = {
        repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/quay/cilium/cilium"
      }

      cni = {
        chainingMode = "aws-cni"
        exclusive    = false
      }

      routingMode          = "native"
      enableIPv4Masquerade = false
      enableIPv6Masquerade = false

      prometheus = {
        enabled = true
        port    = 9962
        metrics = [
          "cilium_bpf_map_pressure",
          "cilium_drop_total",
          "cilium_forward_total",
        ]
      }

      operator = {
        replicas = 1
        image = {
          repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/quay/cilium/operator"
        }
        prometheus = {
          enabled = true
          port    = 9963
        }
      }

      hubble = {
        enabled = true

        relay = {
          enabled = true
          image = {
            repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/quay/cilium/hubble-relay"
          }
          prometheus = {
            enabled = true
            port    = 9966
          }
        }

        ui = {
          enabled = true
          frontend = {
            image = {
              repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/quay/cilium/hubble-ui"
            }
          }
          backend = {
            image = {
              repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/quay/cilium/hubble-ui-backend"
            }
          }
        }

        metrics = {
          enabledOpenMetrics = true
          port               = 9965
          enabled = [
            "dns",
            "drop:sourceContext=pod;destinationContext=pod",
            "tcp",
            "flow",
            "port-distribution",
            "httpV2",
            "policy",
          ]
        }
      }
    })
  ]
}

#########################
# Helm - Metrics-Server #
#########################
resource "helm_release" "metrics-server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.13.0"
  namespace  = "metrics-server"

  values = [
    yamlencode({
      image = {
        repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/k8s/metrics-server/metrics-server"
      }
    })
  ]
}

#################
# Helm - ArgoCD #
#################
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "3.9.0"
  namespace        = "argocd"
  create_namespace = true

  values = [
    yamlencode({
      global = {
        image = {
          repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/quay/argoproj/argocd"
        }
      }
      dex = {
        image = {
          repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/ghcr/dexidp/dex"
        }
      }
      redis = {
        image = {
          repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/docker-hub/library/redis"
        }
      }
    })
  ]
}

####################
# Helm - Karpenter #
####################
resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.11.1"
  namespace        = "karpenter"
  create_namespace = true

  values = [
    yamlencode({
      replicas = 1

      settings = {
        clusterName       = var.cluster_name
        interruptionQueue = data.terraform_remote_state.dev_infra.outputs.sqs_name
      }

      controller = {
        env = [
          {
            name  = "AWS_REGION"
            value = var.aws_region
          },
          {
            name  = "AWS_DEFAULT_REGION"
            value = var.aws_region
          }
        ]
        image = {
          repository = "647502392199.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/karpenter/controller"
        }

        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
    })
  ]
}
