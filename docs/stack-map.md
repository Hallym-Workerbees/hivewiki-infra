# Stack Map

이 문서는 `live` 계층이 어떤 스택으로 나뉘고, 각 스택이 무엇을 소유하는지 빠르게 파악하기 위한 지도입니다.

## Layer Overview

![HiveWiki Cloud Architecture](./images/cloud_architecture.png)

### `live/shared`

계정 공용 리소스를 만듭니다.

- Terraform state S3 bucket
- Route53/ACM 같은 공용 DNS, 인증서 계층
- 애플리케이션 및 pull-through cache용 ECR
- 클러스터와 앱이 참조하는 공용 IAM 리소스

소스: `modules/stacks/shared`

### `live/cluster/vpc`

클러스터 네트워크의 기초 계층입니다.

- VPC, 서브넷
- NAT Gateway
- VPC Endpoint

소스: `modules/stacks/cluster-vpc`

### `live/cluster/observability`

![HiveWiki Logging Architecture](./images/logging_diagram.png)

관측성 저장소를 준비합니다.

- 로그/메트릭 관련 S3 아카이브 버킷
- Loki 등 상위 스택이 의존하는 저장 리소스
- EKS 내부 로그용 Loki backend 버킷

로그 보관 전략은 다음과 같습니다.

- AWS 리소스 로그는 `CloudWatch Logs -> Amazon Data Firehose -> S3 -> S3 Glacier` 경로를 사용합니다.
- ALB/WAF 로그는 S3에 직접 저장한 뒤 Glacier로 아카이빙합니다.
- EKS 내부 로그는 `Grafana Alloy -> Grafana Loki -> S3` 경로를 사용하며, `dev`는 retention 기반으로만 운영하고 `prod`는 Glacier 아카이빙을 적용합니다.

소스: `modules/stacks/cluster-observability`

### `live/cluster/infra`

플랫폼 핵심 계층입니다.

- EKS control plane
- 기본 managed addon
- infra 전용 node group
- pod identity association
- Karpenter prerequisite
- private mode용 bastion

소스: `modules/stacks/cluster-infra`

주요 의존성:

- `../vpc`
- `../../shared`
- `../observability`

### `live/cluster/edge`

퍼블릭 트래픽과 엣지 보호 계층입니다.

- WAF
- CloudFront 및 관련 엣지 리소스

소스: `modules/stacks/cluster-edge`

### `live/cluster/eks-addons`

클러스터 안에 설치되는 운영 소프트웨어를 관리합니다.

- Gateway API CRD
- Cilium
- Metrics Server
- ArgoCD
- Karpenter nodepool
- 기타 Helm/Kubectl 기반 애드온

이 계층은 멀티테넌시 격리 전략의 핵심이기도 합니다.

- Karpenter NodePool을 `system`, `dev`, `prod`로 나눕니다.
- 각 NodePool에는 환경별 label과 taint를 적용합니다.
- 워크로드는 `nodeSelector`와 toleration으로 자신이 배치될 노드를 제한합니다.
- Pod 간 네트워크 권한 경계는 `CiliumNetworkPolicy`를 기준으로 설계합니다.

소스: `modules/stacks/cluster-eks-addons`

주요 의존성:

- `../infra`
- `../vpc`

### `live/cluster/logging`

AWS 리소스 로그 아카이빙 경로를 담당합니다.

- EKS control plane log group
- dev RDS log group
- 선택적으로 prod RDS log group
- CloudWatch Logs에서 Amazon Data Firehose를 거쳐 S3 아카이브 버킷으로 전달
- 장기 보관 시 S3 Glacier 계층으로 아카이빙

소스: `modules/stacks/cluster-logging`

주요 의존성:

- `../infra`
- `../observability`
- `../tenants/dev/rds`
- `../tenants/prod/rds` (`TG_ENABLE_PROD_RDS_LOGGING=true`일 때만)

### `live/cluster/tenants/dev`

개발 테넌트 리소스입니다.

- `app`: 정적 자산 버킷, CloudFront 연결, 웹 워크로드용 IAM
- `cache`: ElastiCache Serverless
- `rds`: 개발용 PostgreSQL
- `ops`: 비용 절감용 hibernate/reboot automation, Lambda, Step Functions, CodeBuild

`ops`는 이번 저장소의 서브프로젝트처럼 볼 수 있는 운영 자동화 계층입니다.

- `hibernate` Step Function은 RDS 중지, EKS node group scale-down, ElastiCache flush, 네트워크 축소를 순차/병렬로 조합합니다.
- `reboot` Step Function은 네트워크 복구, RDS 기동, EKS node group scale-up, 완료 알림까지 이어지는 아침 복구 워크플로우입니다.
- 두 워크플로우 모두 EventBridge Scheduler로 예약 실행되고, Lambda와 CodeBuild를 함께 사용합니다.

상세 흐름은 아래와 같습니다.

#### Hibernate

![Hibernate Step Function](./images/sfn_hibernate.png)

클러스터 내부:

1. `kube-green`이 먼저 대상 워크로드의 replica를 `0`으로 줄입니다.

Step Function:

1. `EventBridge Scheduler`가 예약된 시각에 `hibernate` Step Function 실행을 시작합니다.
2. 시작 Lambda를 호출해 Slack 알림을 보냅니다.
3. 아래 작업을 병렬로 실행합니다.
   - MNG zero-scale:\
     infra 전용 Managed Node Group의 desired size를 `0`으로 내리는 작업을 시작합니다. \
     EC2/EKS 상태를 polling하면서 실제로 node group 인스턴스가 사라질 때까지 기다립니다.
   - RDS stop: \
     dev RDS stop을 시작합니다. \
     RDS 상태를 polling하면서 `stopped`가 될 때까지 기다립니다.
   - ElastiCache Serverless: \
     cache flush를 수행해 불필요한 저장 비용을 줄입니다.
4. 병렬 작업이 끝나면 CodeBuild가 이 저장소 코드를 가져와 `live/cluster/vpc`를 다시 apply합니다.
5. 이때 `hibernate.auto.tfvars.json`을 주입해 `natgw_azs = []`, `enable_full_vpce = false`로 덮어써서 NAT Gateway, 연결된 EIP, 불필요한 VPC endpoint 계층을 제거합니다.
6. 종료 Lambda를 호출해 Slack 알림을 보냅니다.

#### Reboot

![Reboot Step Function](./images/sfn_reboot.png)

Step Function:

1. `EventBridge Scheduler`가 예약된 시각에 `reboot` Step Function 실행을 시작합니다.
2. 별도 임시 변수 주입 없이 `live/cluster/vpc`를 다시 apply합니다.
3. 그 결과 기본 설정값 기준으로 NAT Gateway, 라우팅, 연결된 EIP, 필요한 네트워크 구성이 복구됩니다.
4. 아래 작업을 병렬로 실행합니다.
   - MNG restore: \
     infra 전용 Managed Node Group desired size를 원래 운영 값으로 되돌립니다. \
     EKS 상태를 polling하면서 scale-up 완료까지 기다립니다.
   - RDS start: \
     dev RDS를 다시 기동합니다.
     RDS 상태를 polling하면서 `available`이 될 때까지 기다립니다.
5. 종료 Lambda를 호출해 Slack 알림을 보냅니다.

클러스터 내부:

1. `kube-green`이 Pod들을 다시 복구합니다.

#### 운영 상의 비고

- `kube-green`과 Step Function 시작/종료 사이에는 약 30분 텀이 있습니다.
- 더 정교하게 만들 수도 있었습니다. 예를 들어 hibernate 시점에 `kube-green`이 실제로 모든 워크로드를 `0`으로 만든 것을 확인한 뒤 다음 단계로 진행하거나, reboot 시점에 Kubernetes node readiness를 직접 조회하는 방식도 가능합니다.
- 다만 프로젝트 기한, 구현 난이도, 운영 복잡성을 고려해 이번 구현에서는 러프하지만 예측 가능한 방식으로 설계했습니다.

### `live/cluster/tenants/prod`

운영 테넌트 리소스입니다.

- `app`
- `cache`
- `rds`

## Recommended Apply Order

새 환경을 처음 올릴 때는 아래 순서가 안전합니다.

1. `live/shared`
2. `live/cluster/vpc`
3. `live/cluster/observability`
4. `live/cluster/infra`
5. `live/cluster/edge`
6. `live/cluster/eks-addons`
7. `live/cluster/tenants/dev/rds`
8. `live/cluster/tenants/dev/cache`
9. `live/cluster/tenants/dev/app`
10. `live/cluster/tenants/dev/ops`
11. `live/cluster/tenants/prod/rds`
12. `live/cluster/tenants/prod/cache`
13. `live/cluster/tenants/prod/app`
14. `live/cluster/logging`

`terragrunt run --all`이 의존관계를 어느 정도 계산해주지만, 초기 부트스트랩이나 장애 복구 때는 위 순서를 알고 있는 편이 안전합니다.

## Key Configuration Files

- `root.hcl`: remote state, provider, 기본 태그
- `live/cluster/cluster.hcl`: 클러스터 공통값, 네트워크 토글
- `live/cluster/tenants/dev/tenant.hcl`: dev 테넌트 prefix
- `live/cluster/tenants/prod/tenant.hcl`: prod 테넌트 prefix

## Change Impact Guide

- DNS/인증서/ECR 변경: `shared`
- 서브넷/NAT/VPCE 변경: `vpc`
- EKS 버전, node group, IAM, bastion 변경: `infra`
- 인그레스/WAF/CloudFront 변경: `edge`, `tenant app`
- 애드온, Helm 배포, Karpenter, Cilium 기반 격리 정책 변경: `eks-addons`
- DB/캐시 스펙 변경: 각 tenant의 `rds`, `cache`
- 개발 환경 절전 자동화 변경: `tenants/dev/ops`
