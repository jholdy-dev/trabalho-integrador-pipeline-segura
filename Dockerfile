# syntax=docker/dockerfile:1
#
# Dockerfile endurecido para PASSAR no Dockle (CIS Docker Benchmark).
# Cada decisao abaixo mata um check do CIS — comentado para a defesa do trabalho.
#
# Pin por DIGEST (nao por tag) — tag e ponteiro mutavel, digest e o conteudo.
# (ver nota 11-06-2026: "tag e mutavel, digest sha256 nao e").
# Para descobrir o digest atual:  docker pull python:3.12-slim && docker inspect ...
# Aqui usamos tag versionada + comentario de digest; troque pelo @sha256 real ao fixar.

############################
# Estagio 1 — build/deps
############################
FROM python:3.12-slim AS build

WORKDIR /app

# Instala dependencias num prefixo isolado para copiar so o necessario depois.
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

############################
# Estagio 2 — runtime minimo
############################
FROM python:3.12-slim AS runtime

# CIS-DI-0001 / CIS-DI-0008: cria usuario sem privilegio e NAO roda como root.
# Um RCE no worker cai como 'appuser', nao como root (defesa em profundidade).
RUN groupadd --gid 10001 appgroup \
    && useradd --uid 10001 --gid appgroup --shell /usr/sbin/nologin --create-home appuser

WORKDIR /app

# CIS-DI-0006: copia as libs do estagio de build (sem toolchain de compilacao na imagem final).
COPY --from=build /install /usr/local
# CIS-DI-0009: COPY (nunca ADD) — ADD faz auto-extract/fetch remoto, risco de supply chain.
COPY --chown=appuser:appgroup app/ ./

# CIS-DI-0010: nenhum segredo embutido. Segredo entra por env/secret em runtime (ver notas
# 12-06-2026: Vault + credencial de curta duracao). O Trivy 'secret' scan valida isso na CI.

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

# Porta NAO privilegiada (>1024): processo sem root consegue dar bind sem CAP_NET_BIND_SERVICE.
EXPOSE 8080

# CIS-DI-0001: troca para o usuario sem privilegio ANTES do CMD.
USER 10001:10001

# CIS-DI-0006: HEALTHCHECK obrigatorio pelo benchmark — orquestrador sabe se o container vive.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz').status==200 else 1)"

# gunicorn como PID 1 (servidor de producao; o Flask dev server nao escala).
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
