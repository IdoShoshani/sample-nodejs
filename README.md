# DevOps Sample Node.js App

## Overview

A lightweight Node.js application. It features basic web endpoints, Prometheus metrics integration, and is designed for Kubernetes deployment and CI/CD pipeline demonstrations.

## Quick start

```bash
git clone https://github.com/IdoShoshani/sample-nodejs.git && cd sample-nodejs
npm ci && npm test                                         # lint + 4 route tests
docker build -t sample-nodejs:dev . && \
  docker run --rm -p 8080:8080 sample-nodejs:dev           # http://localhost:8080/my-app
```

## Features

- Express.js web server
- Prometheus metrics integration
- Readiness and liveness probe endpoints
- Customizable port via environment variable

## Prerequisites

- Node.js (v22.1.0)

---

## DevOps / DevSecOps (this fork)

Forked from `EladAviczer/sample-nodejs`. This fork adds: a multi-stage non-root Dockerfile, route tests, ESLint, and a full GitHub Actions CI/CD pipeline that publishes to Docker Hub and drives a GitOps deployment via ArgoCD.

### Architecture (one picture in words)

```
 dev push  ───►  GitHub Actions (this repo)
                   ├── test       (npm ci, lint, node --test)
                   ├── sast       (Semgrep, fail on ERROR)
                   ├── release    (compute version, build, Trivy gate,
                   │               docker push, git tag)            ──► Docker Hub  (idoshoshani123/sample-nodejs:<tag>)
                   └── promote    (yq edit values.yaml, git commit
                                   on GitOps repo)                  ──► GitOps repo (IdoShoshani/devops-challenge-gitops)
                                                                              │
                                                              ArgoCD watches  ▼
                                                              kubernetes (RKE2 home lab)
                                                                          │
                                                                          ▼
                                                              Deployment + Service + Ingress
                                                                          │
                                                                          ▼
                                                                  http://sample-nodejs.local
```

### Decisions

| Decision | Choice | Why |
|---|---|---|
| Workload kind | **Deployment** | Stateless HTTP service — no per-pod identity, no persistent volumes, no ordered startup. Free rolling updates + horizontal scaling. |
| CI/CD tool | **GitHub Actions** | Tight integration with the source repo; one config file in `.github/workflows/ci.yml`. |
| Git workflow | **Trunk-based** | Short-lived branches → PR (test + SAST) → merge to `main` → release pipeline. |
| Version scheme | `<pkg.version>-<run>` | Deterministic from `package.json#version` + `GITHUB_RUN_NUMBER`. Each merge to `main` produces a new image tag + matching git tag `v<tag>`. |
| Container registry | **Docker Hub** (public — see Deviations) | Free, simple. |
| SAST | **Semgrep** | `--config=auto`, blocks on ERROR-severity findings. |
| Image scan | **Trivy** | Blocks HIGH/CRITICAL; `ignore-unfixed: true`. Runs **on the local image after build**, so push only happens after the scan passes. |
| Probes | App's existing `/ready` (readiness) and `/live` (liveness) | No code changes needed beyond exporting `app`. |
| Metrics | Pod annotations enable Prometheus scraping of `/metrics` | Bonus. |
| GitOps layout | **Separate GitOps repo** ([devops-challenge-gitops](https://github.com/IdoShoshani/devops-challenge-gitops)) | Decouples app source from desired cluster state. Git history of the GitOps repo = audit log of every deploy. CI promotes a release by committing `image.tag`; ArgoCD reconciles. No `kubectl` in CI, no cluster credentials in CI. |

### Pipeline (`.github/workflows/ci.yml`)

Jobs (in dependency order):

1. **`test`** — `npm ci`, ESLint (flat config), `node --test` with `supertest` against 4 route tests.
2. **`sast`** — Semgrep `--config=auto --error --severity=ERROR` inside the `semgrep/semgrep` container.
3. **`release`** *(only on `main`)* — needs `test` + `sast`:
   - Compute `TAG=<pkg.version>-<run>`
   - Build the image with Buildx, load locally
   - Trivy scan on the loaded image, block HIGH/CRITICAL
   - Log in to Docker Hub with secrets, push
   - Create and push git tag `v<TAG>`
4. **`promote`** *(only on `main`)* — needs `release`:
   - Checkout the GitOps repo using `GITOPS_PAT`
   - `yq -i '.image.tag = strenv(TAG)' apps/sample-nodejs/values.yaml`
   - Commit and push as `ci-bot`

Required repo secrets:
- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` — push the image.
- `GITOPS_PAT` — fine-grained PAT scoped to `devops-challenge-gitops`, Contents: Read & write. Used by `promote` to commit the image-tag bump.

### Versioning

Each image tag is `<package.json#version>-<GITHUB_RUN_NUMBER>`, e.g. `1.0.0-12`. A matching git tag `v<image-tag>` is pushed on every successful `release`. **For a minor/major release, bump `version` in `package.json`** in a PR; the run number resets nothing and continues incrementing, so tags stay monotonically ordered.

### Deviations from the original challenge spec / plan

- **ESLint flat config (`eslint.config.js`) instead of `.eslintrc.json`.** ESLint `^9.9.0` (which the plan pins) does **not** read legacy `.eslintrc.json` by default. Using flat config is the supported path for ESLint 9+.
- **`aquasecurity/trivy-action@v0.36.0`.** The plan's `@0.24.0` is not a published tag.
- **`path-to-regexp` overridden to `0.1.13`** via npm `overrides` in `package.json`. Closes CVE-2026-4867 (HIGH ReDoS) surfaced by Trivy on the original Express transitive.
- **`npm` removed from the runtime image** in the second Dockerfile stage. The app runs with `node`, never `npm`. This eliminates a HIGH CVE in the base image's bundled npm (`picomatch` CVE-2026-33671) and trims attack surface.
- **Public Docker Hub repo** (`idoshoshani123/sample-nodejs`). The challenge asks for a private registry; this was a conscious cost/visibility choice for the homelab demo. To re-enable private:
  1. Set the Docker Hub repo to Private.
  2. Re-add `imagePullSecrets` in `values.yaml` and create a `dockerhub-pull-secret` in the cluster namespace.
- **Cluster: RKE2 home lab** instead of `kind`. RKE2's `ingress-nginx` (in hostNetwork mode) was already present, so the Helm chart's `ingress.className: nginx` works unchanged.
- **`.local` mDNS quirk on macOS.** `curl http://sample-nodejs.local/` hangs on resolution even with `/etc/hosts` because macOS routes `.local` to Bonjour. Workaround: `curl --resolve sample-nodejs.local:80:<node-ip> ...`. A clean fix would be to rename the ingress host to `sample-nodejs.test` (RFC-reserved testing TLD, not on mDNS) — one-line change in `values.yaml`.

### Local development

```bash
npm ci
npm run lint
npm test
npm start             # serves on :8080

docker build -t sample-nodejs:dev .
docker run -d --rm -p 8080:8080 --name sn sample-nodejs:dev
curl localhost:8080/my-app    # -> Hello, World!
docker stop sn
```

### Pre-commit gate checks the same things CI does

```bash
docker run --rm -v "$PWD:/src" semgrep/semgrep semgrep scan --config=auto --error --severity=ERROR /src
docker build -t sample-nodejs:ci .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image \
  --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 sample-nodejs:ci
```

### Links

- App repo: https://github.com/IdoShoshani/sample-nodejs
- GitOps repo: https://github.com/IdoShoshani/devops-challenge-gitops *(private)*
- Image: https://hub.docker.com/r/idoshoshani123/sample-nodejs
- Deployment: live on the RKE2 home lab — `http://sample-nodejs.local/my-app` (see "macOS mDNS" deviation above).
