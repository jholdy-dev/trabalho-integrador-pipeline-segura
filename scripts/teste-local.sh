#!/usr/bin/env bash
#
# Roda os MESMOS gates da CI na sua maquina, antes de dar push.
# Assim voce nao "queima" execucoes do GitHub Actions descobrindo erro bobo.
#
# Pre-requisitos: docker
set -euo pipefail

IMG="pipeline-segura:local"
cd "$(dirname "$0")/.."

echo "==> [0/4] Build da imagem"
docker build -t "$IMG" .

echo "==> [1/4] Dockle (CIS Docker Benchmark) — falha em FATAL"
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.dockleignore:/.dockleignore:ro" \
  goodwithtech/dockle:latest \
  --exit-code 1 --exit-level fatal --format list "$IMG"

echo "==> [2/4] Trivy — CVE CRITICAL + secrets (falha bloqueia)"
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --scanners vuln,secret \
  --severity CRITICAL \
  --ignore-unfixed \
  --exit-code 1 "$IMG"

echo "==> [3/4] SBOM CycloneDX -> sbom.cyclonedx.json"
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:/out" \
  aquasec/trivy:latest image \
  --format cyclonedx --output /out/sbom.cyclonedx.json "$IMG"

echo "==> [4/4] OK. Assinatura (cosign keyless) so roda na CI com OIDC do GitHub."
echo "Tudo verde. Pode dar push com seguranca."
