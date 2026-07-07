# ============================================================
# Imagem única: Debian + Node 22 + n8n + Flutter + Claude Code + rtk
# ============================================================
FROM node:22-bookworm-slim

ARG N8N_VERSION=2.25.6
ARG CLAUDE_CODE_VERSION=2.1.202
ARG FLUTTER_VERSION=3.41.9
ARG RTK_VERSION=v0.40.0

ENV DEBIAN_FRONTEND=noninteractive
ENV FVM_CACHE_PATH=/opt/fvm
# Força módulos nativos a usarem prebuilt binaries quando disponível,
# evitando recompilação que pode quebrar com versões novas de Node
ENV npm_config_build_from_source=false

# ------------------------------------------------------------
# Dependências de sistema
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        git curl unzip xz-utils \
        ca-certificates \
        chromium \
        fonts-liberation fonts-noto-color-emoji \
        libstdc++6 \
        python3 make g++ pkg-config \
        tini \
        jq \
        procps \
        which file \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Diretórios pro user 'node'
# ------------------------------------------------------------
RUN mkdir -p \
        /home/node/.n8n \
        /home/node/.claude \
        /home/node/.context-mode \
        /home/node/scripts \
        /home/node/prompts \
        /home/node/node_modules/@anthropic-ai \
        /workspace \
    && chown -R node:node /home/node /workspace

# ------------------------------------------------------------
# rtk (binário oficial)
# ------------------------------------------------------------
RUN ARCH="$(uname -m)" \
    && case "$ARCH" in \
        x86_64)  TARGET="x86_64-unknown-linux-musl" ;; \
        aarch64) TARGET="aarch64-unknown-linux-gnu" ;; \
        *) echo "Arquitetura não suportada: $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/rtk-${TARGET}.tar.gz" \
        -o /tmp/rtk.tar.gz \
    && tar -xzf /tmp/rtk.tar.gz -C /tmp \
    && mv /tmp/rtk /usr/local/bin/rtk \
    && chmod +x /usr/local/bin/rtk \
    && rm /tmp/rtk.tar.gz \
    && rtk --version

# ------------------------------------------------------------
# n8n + Claude Code + context-mode
# Instalações separadas pra que erros sejam fáceis de isolar
# ------------------------------------------------------------
RUN npm install -g --omit=dev n8n@${N8N_VERSION} \
    && n8n --version

RUN npm install -g --omit=dev @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && claude --version

RUN npm install -g --omit=dev context-mode \
    && context-mode --version \
    && npm cache clean --force

RUN NPM_PREFIX="$(npm config get prefix)" \
    && ln -sf "${NPM_PREFIX}/lib/node_modules/@anthropic-ai/claude-code" \
              /home/node/node_modules/@anthropic-ai/claude-code \
    && chown -R node:node /home/node/node_modules

# ------------------------------------------------------------
# Flutter SDK
# ------------------------------------------------------------
ENV FLUTTER_HOME=/opt/flutter
ENV PUB_CACHE=/opt/pub-cache
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"
ENV CHROME_EXECUTABLE=/usr/bin/chromium

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
        https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && git config --system --add safe.directory ${FLUTTER_HOME} \
    && mkdir -p ${PUB_CACHE} \
    && ${FLUTTER_HOME}/bin/flutter config --no-analytics \
    && ${FLUTTER_HOME}/bin/flutter config --enable-web \
    && ${FLUTTER_HOME}/bin/flutter precache --web \
        --no-android --no-ios --no-linux --no-macos --no-windows \
    && ${FLUTTER_HOME}/bin/flutter doctor -v || true \
    && ${FLUTTER_HOME}/bin/cache/dart-sdk/bin/dart --version \
    && ${FLUTTER_HOME}/bin/flutter --version \
    && chown -R node:node ${FLUTTER_HOME} ${PUB_CACHE}

# === FVM + versões pré-aquecidas pro eval pipeline ===
USER root

# PUB_CACHE em /opt pra ser shared (não fica em ~ do user node, sobrevive reset de home)
ENV PUB_CACHE=/opt/pub-cache
ENV PATH="/opt/pub-cache/bin:${PATH}"

# Instala FVM CLI globalmente
RUN /opt/flutter/bin/cache/dart-sdk/bin/dart pub global activate fvm \
    && chmod -R a+rx /opt/pub-cache

# Cache do FVM em /opt (mesma lógica — sobrevive)
ENV FVM_CACHE_PATH=/opt/fvm
RUN mkdir -p /opt/fvm \
    && chown -R node:node /opt/fvm

USER node

# Pre-warm das versões usadas pelos bugs históricos (sequencial pra evitar race)
RUN fvm install 3.32.8 \
    && fvm install 3.35.7 \
    && fvm install 3.41.9

# ------------------------------------------------------------
# Configuração final
# ------------------------------------------------------------
ENV SHELL=/bin/bash
ENV N8N_USER_FOLDER=/home/node/.n8n
ENV NODE_ENV=production

EXPOSE 5678

USER node
WORKDIR /home/node

RUN flutter --version \
    && dart --version \
    && n8n --version \
    && claude --version \
    && rtk --version

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["n8n", "start"]