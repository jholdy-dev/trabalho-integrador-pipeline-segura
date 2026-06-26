# Trabalho Integrador • Parte 1 — Pipeline Segura

Ecossistema de defesa 360°, **fase de build**: a imagem que chega no registry é
**construída de forma endurecida (CIS)**, **limpa (sem CVE CRITICAL nem segredo)**,
**assinada (proveniência)** e **auditável (SBOM)**.

> Fundamento nas notas da disciplina: a imagem é um *artefato que viaja* — build → push →
> store → pull → run. A defesa garante que **o que roda em produção é exatamente o que foi
> construído e revisado**. Ver `../11-06-2026.md` (supply chain) e `../22-05-2026.md` (hardening).

## Os 4 requisitos → onde estão resolvidos

| # | Requisito | Ferramenta | Onde | Gate |
|---|-----------|-----------|------|------|
| 1 | CIS Docker Benchmark; FATAL derruba a CI | **Dockle** `--exit-code 1 --exit-level fatal` | `pipeline-segura.yml` → *Gate 1* | ✅ falha CI |
| 2 | CVEs + secrets; bloqueia se CRITICAL | **Trivy** `scanners: vuln,secret severity: CRITICAL exit-code 1` | *Gate 2* | ✅ bloqueia |
| 3 | Assinar com Cosign (**keyless via OIDC**) | **Cosign** + `id-token: write` (Fulcio/Rekor) | *passo 4* | assina o **digest** |
| 4 | Publicar SBOM **CycloneDX** como artefato | **Trivy** `format: cyclonedx` + `upload-artifact` | *passo 3* | artefato 90d |

A **ordem** segue a nota 11-06-2026: `build → scan (gate) → sign → push`. Imagem só é
publicada e assinada **depois** que Dockle e Trivy passam. Cosign assina **pelo digest
(sha256)**, nunca pela tag — fecha o ciclo sobre o conteúdo imutável.

## Estrutura

```
trabalho-integrador-pipeline-segura/
├── app/                       # app Flask de exemplo (alvo da pipeline)
│   ├── app.py
│   └── requirements.txt
├── Dockerfile                 # endurecido p/ passar no Dockle (cada check comentado)
├── .dockerignore              # imagem mínima + não vaza segredo p/ o build context
├── scripts/teste-local.sh     # roda os mesmos gates localmente antes do push
└── .github/workflows/
    └── pipeline-segura.yml     # a pipeline (Dockle → Trivy → SBOM → Cosign)
```

## Como subir no GitHub (passo a passo)

A pipeline usa **GHCR** (`ghcr.io`) e **cosign keyless** porque é onde o OIDC do GitHub
torna o requisito "keyless via OIDC" possível **sem guardar nenhuma chave**.

1. **Crie o repositório** no GitHub (pode ser público; para privado o keyless também funciona).

2. **Suba o conteúdo desta pasta** como raiz do repositório:
   ```bash
   cd trabalho-integrador-pipeline-segura
   git init -b main
   git add .
   git commit -m "Pipeline segura: Dockle + Trivy + Cosign keyless + SBOM CycloneDX"
   git remote add origin git@github.com:<SEU_USUARIO>/<SEU_REPO>.git
   git push -u origin main
   ```
   > Importante: o `.github/workflows/` precisa ficar na **raiz** do repositório.

3. **Permissões** — o workflow já declara o mínimo necessário:
   `contents: read`, `packages: write` (push no GHCR), `id-token: write` (OIDC keyless).
   Confira em *Settings → Actions → General → Workflow permissions* se Actions pode escrever.

4. **Rode**: o push para `main` já dispara. Acompanhe em *Actions → Pipeline Segura*.
   - Falhou no **Gate 1/2**? A imagem tinha inconformidade CIS ou CVE CRITICAL/secret — é o
     comportamento esperado (o gate funcionou). Corrija e faça novo push.
   - Passou? A imagem vai assinada para `ghcr.io/<seu_usuario>/<seu_repo>` e o **SBOM**
     aparece como artefato na aba *Actions* (download em "Artifacts").

## Verificar a assinatura (prova do requisito 3)

```bash
cosign verify ghcr.io/<seu_usuario>/<seu_repo>@<digest> \
  --certificate-identity-regexp "https://github.com/<seu_usuario>/<seu_repo>/.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

A verificação confirma que a imagem foi assinada **por aquele repositório, naquele workflow**,
e a assinatura está registrada no log público de transparência (**Rekor**).

## Testar localmente antes (recomendado)

```bash
./scripts/teste-local.sh
```

Roda Dockle + Trivy + SBOM via container (só precisa de Docker). A assinatura cosign keyless
**não** roda local porque depende do token OIDC que só existe dentro do GitHub Actions.

## Como provar que os gates funcionam (para a defesa do trabalho)

- **Gate Dockle**: remova a linha `USER 10001:10001` do `Dockerfile` → o Dockle acusa
  `CIS-DI-0001` (roda como root) e a CI falha.
- **Gate Trivy/secret**: coloque uma chave fake (`AWS_SECRET=AKIA...`) num arquivo copiado para
  a imagem → o scanner de secrets do Trivy bloqueia.
- **Gate Trivy/CVE**: fixe uma base antiga conhecidamente vulnerável → Trivy falha em CRITICAL.

Cada falha demonstra um elo da defesa 360° impedindo que um artefato inseguro chegue ao registry.
