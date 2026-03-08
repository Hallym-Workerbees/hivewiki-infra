# HiveWiki Infra

HiveWiki Infra는 HiveWiki 프로젝트의 인프라를 코드로 관리하는 레포지토리입니다.  
OpenTofu를 사용해 클라우드 리소스와 환경 구성을 정의하고 관리합니다.

---

## 개발 환경

이 프로젝트는 다음 도구들을 사용합니다.

- OpenTofu
- pre-commit
- gitleaks
- commitizen

---

## 시작하기

### 1. 필수 도구 설치

`pre-commit`은 Python 기반 도구이므로 먼저 설치합니다.

```bash
pip install pre-commit
```

### 2. Repository Clone

```bash
git clone <repository-url>
cd hivewiki-infra
```

### 3. pre-commit hook 설치

```bash
pre-commit install --hook-type pre-commit --hook-type commit-msg
```

이 프로젝트는 pre-commit hooks를 사용합니다.  
코드가 자동으로 수정되면 커밋이 중단될 수 있으며, 수정된 파일을 확인한 뒤 다시 add하고 커밋하면 됩니다.

Commit message는 **영어로 작성해야 하며**, Conventional Commits 규칙을 따릅니다.  
자세한 규칙은 이 [문서](https://commitizen-tools.github.io/commitizen/tutorials/writing_commits/)를 참고하세요.
