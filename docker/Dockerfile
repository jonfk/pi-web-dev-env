FROM ubuntu:24.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG ASSISTANT_USER=ubuntu
ARG PYTHON_VERSION=3.12
ARG FZF_VERSION=0.72.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
  && install -d -m 0755 /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    stow \
    bat \
    build-essential \
    fd-find \
    git \
    git-delta \
    gh \
    golang-go \
    jq \
    less \
    nodejs \
    openssh-client \
    pkg-config \
    ripgrep \
    rsync \
    sudo \
    unzip \
    vim \
    xz-utils \
    zip \
  && case "$(uname -m)" in \
    x86_64) fzf_arch=amd64; fzf_sha256=0e58e4bd0b3c5d68c56b54c460a6863d0de79633ed18d388575a960ab447b006 ;; \
    aarch64) fzf_arch=arm64; fzf_sha256=a0a5b50730f568c5f08b8dbba1e6e598db253e1856d371290086786b889b996b ;; \
    *) echo "Unsupported fzf architecture: $(uname -m)" >&2; exit 1 ;; \
  esac \
  && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${fzf_arch}.tar.gz" -o /tmp/fzf.tar.gz \
  && echo "${fzf_sha256}  /tmp/fzf.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/fzf.tar.gz -C /usr/local/bin fzf \
  && chmod 0755 /usr/local/bin/fzf \
  && rm /tmp/fzf.tar.gz \
  && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
  && UV_PYTHON_INSTALL_DIR=/opt/uv-python uv python install "${PYTHON_VERSION}" \
  && ln -s /usr/bin/batcat /usr/local/bin/bat \
  && ln -s /usr/bin/fdfind /usr/local/bin/fd \
  && ln -s "$(UV_PYTHON_INSTALL_DIR=/opt/uv-python uv python find "${PYTHON_VERSION}")" /usr/local/bin/python3 \
  && ln -s /usr/local/bin/python3 /usr/local/bin/python \
  && npm install -g pnpm@10.14.0 @mariozechner/pi-coding-agent \
  && getent passwd "${ASSISTANT_USER}" >/dev/null \
  && mkdir -p /workspace "/home/${ASSISTANT_USER}/.pi/agent" "/home/${ASSISTANT_USER}/.config/wede" "/home/${ASSISTANT_USER}/.ssh" \
  && chown -R "${ASSISTANT_USER}:${ASSISTANT_USER}" /workspace "/home/${ASSISTANT_USER}/.pi" "/home/${ASSISTANT_USER}/.config" "/home/${ASSISTANT_USER}/.ssh" \
  && chmod 0700 "/home/${ASSISTANT_USER}/.ssh" \
  && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | su "${ASSISTANT_USER}" -c "sh -s -- -y --profile minimal --default-toolchain stable" \
  && echo "${ASSISTANT_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${ASSISTANT_USER}" \
  && chmod 0440 "/etc/sudoers.d/${ASSISTANT_USER}" \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ENV PATH="/home/${ASSISTANT_USER}/.cargo/bin:${PATH}"

FROM base AS pipane-builder

WORKDIR /build/pipane
COPY pipane/package.json pipane/package-lock.json ./
COPY pipane/patches ./patches
RUN npm ci
COPY pipane/ ./
RUN npm run build

FROM base AS wede-builder

WORKDIR /build/wede
COPY wede/package.json wede/package-lock.json ./
RUN npm ci
COPY wede/ ./
RUN npm run build:all

FROM base AS pi-webui-builder

WORKDIR /build/pi-webui
COPY pi-webui/package.json pi-webui/package-lock.json ./
RUN npm ci
COPY pi-webui/ ./
RUN npm run build

FROM base AS runtime

ARG ASSISTANT_USER=ubuntu

COPY --from=pipane-builder --chown=${ASSISTANT_USER}:${ASSISTANT_USER} /build/pipane /opt/pipane
COPY --from=wede-builder /build/wede/wede /usr/local/bin/wede
COPY --from=pi-webui-builder --chown=${ASSISTANT_USER}:${ASSISTANT_USER} /build/pi-webui /opt/pi-webui
COPY docker/entrypoint.sh /usr/local/bin/pi-web-dev-env-entrypoint
COPY docker/bootstrap.sh /usr/local/bin/pi-web-dev-env-bootstrap

RUN chmod 0755 /usr/local/bin/wede /usr/local/bin/pi-web-dev-env-entrypoint /usr/local/bin/pi-web-dev-env-bootstrap \
  && ln -s /opt/pipane/bin/pipane.js /usr/local/bin/pipane \
  && ln -s /opt/pi-webui/dist/server/index.js /usr/local/bin/pi-webui

USER ${ASSISTANT_USER}
WORKDIR /workspace

ENV NODE_ENV=production \
    PI_CWD=/workspace \
    PORT=8222 \
    PIPANE_AUTH_DISABLED=0 \
    WEDE_PORT=9090 \
    WEDE_PASSWORD=admin \
    WEDE_AUTH_DISABLED=0 \
    PI_WEBUI_HOST=0.0.0.0 \
    PI_WEBUI_PORT=4096 \
    PI_PROJECT_CWD=/workspace \
    PI_WEBUI_CWD_ALLOW_ANY=1

EXPOSE 8222 9090 4096

ENTRYPOINT ["pi-web-dev-env-entrypoint"]
CMD ["pipane"]
