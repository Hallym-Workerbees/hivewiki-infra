# Contributing Guide

이 문서는 새 기여자가 이 저장소를 안전하게 읽고, 변경하고, 검증하는 최소 절차를 정리합니다.

## Before You Change Anything

먼저 확인할 것:

- 현재 AWS 계정이 맞는지
- 변경 대상이 `shared`, `cluster`, `tenant` 중 어디인지
- 해당 스택이 다른 스택 출력값을 소비하는지
- 변경이 `dev` 전용인지, `prod`까지 전파되는지

추천 확인 명령:

```bash
aws sts get-caller-identity
git status --short
pre-commit run --all-files
```

## Working Rules

### 1. `live`에서 시작해서 `modules`로 내려간다

실제 배포 단위는 `live/**/terragrunt.hcl`입니다. 먼저 여기서 변경 범위를 잡고, 그다음 `terraform.source`가 가리키는 `modules/stacks/**`를 수정하는 흐름이 가장 안전합니다.

### 2. 작은 범위로 `plan`한다

가능하면 전체 apply 전에 영향을 받는 스택만 먼저 `plan`합니다.

```bash
cd live/cluster/infra
terragrunt plan
```

테넌트 DB를 바꿨다면:

```bash
cd live/cluster/tenants/dev/rds
terragrunt plan
```

### 3. dev 전용 자동화는 스크립트를 재사용한다

개발 계열 스택 전체 검증/적용은 직접 `run --all`을 조합하기보다 스크립트를 우선 사용합니다.

```bash
bash scripts/run-dev-only.sh plan
bash scripts/run-dev-only.sh apply
```

이 스크립트는 Lambda 번들 생성과 `logging` 분리 실행까지 포함합니다.

## Validation Checklist

PR 전에 최소한 아래는 확인합니다.

- `pre-commit run --all-files`
- 변경 스택에서 `terragrunt plan`
- Lambda 관련 변경이면 `bash scripts/build-tenant-dev-ops-lambdas.sh`
- `prod` 영향 변경이면 영향받는 `prod` 스택도 별도 `plan`

예시:

```bash
pre-commit run --all-files
cd live/cluster/tenants/dev/cache && terragrunt plan
cd ../prod/cache && terragrunt plan
```

## Secrets And Sensitive Inputs

이 저장소는 인프라 코드 저장소이지 비밀 저장소가 아닙니다.

- 토큰, 비밀번호, webhook URL을 문서 예시에 넣지 않습니다.
- `TF_VAR_*` 환경 변수 또는 안전한 배포 파이프라인 입력을 우선 고려합니다.
- 계정별 `tfvars`를 편집했다면 커밋 전 diff를 다시 읽고 민감정보가 없는지 확인합니다.
- `gitleaks` 경고는 우회하지 말고 원인을 제거합니다.

## Common Change Scenarios

### EKS나 IAM 정책을 바꾸는 경우

영향 범위:

- `live/cluster/infra`
- 경우에 따라 `live/cluster/eks-addons`

확인 포인트:

- pod identity association이 깨지지 않는지
- Karpenter 관련 role/policy가 유지되는지
- private mode 여부에 따라 bastion 경로가 필요한지

### 앱용 정적 배포나 CDN 구성을 바꾸는 경우

영향 범위:

- `live/cluster/tenants/*/app`
- 경우에 따라 `live/shared`
- 경우에 따라 `live/cluster/edge`

확인 포인트:

- Route53 zone / ACM certificate 의존성
- 환경별 custom domain 차이
- S3 allowed origins

### 데이터 계층을 바꾸는 경우

영향 범위:

- `live/cluster/tenants/*/rds`
- `live/cluster/tenants/*/cache`
- 경우에 따라 `live/cluster/logging`

확인 포인트:

- 보안 그룹 의존성
- 서브넷과 VPC dependency
- prod의 로그 보존 기간과 Multi-AZ 설정

## Commit And PR Notes

- 커밋 메시지는 영어 Conventional Commits 형식을 따릅니다.

예시 템플릿:

```text
Summary
- Update dev cache capacity
- Keep prod unchanged

Stacks
- live/cluster/tenants/dev/cache

Validation
- pre-commit run --all-files
- terragrunt plan in live/cluster/tenants/dev/cache
```
