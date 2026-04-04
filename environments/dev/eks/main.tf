###############################
# Remote state: AWS Dev Infra #
###############################
data "terraform_remote_state" "dev_infra" {
  backend = "s3"
  config = {
    bucket = "hivewiki-infra-state-bucket"
    key    = "dev/infra/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

##############
# Kubernetes #
##############
provider "kubernetes" {
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
      var.aws_region
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
        var.aws_region
      ]
      command = "aws"
    }
  }
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
        prometheus = {
          enabled = true
          port    = 9963
        }
      }

      hubble = {
        enabled = true

        relay = {
          enabled = true
          prometheus = {
            enabled = true
            port    = 9966
          }
        }

        ui = {
          enabled = true
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

##################
# Metrics-Server #
##################
