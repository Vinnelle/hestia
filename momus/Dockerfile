# syntax=docker/dockerfile:1.7

ARG DEBIAN_IMAGE=debian:13-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd
ARG KUBECTL_VERSION=v1.31.4
ARG KUBECTL_SHA256=298e19e9c6c17199011404278f0ff8168a7eca4217edad9097af577023a5620f
ARG STARSHIP_VERSION=v1.26.0
ARG STARSHIP_SHA256=321f0dd7af8340a5f2e6a8fec6538a04f617486f9ec70d878f91c09cd8deef22
# VS Code CLI 1.127.0 stable
ARG VSCODE_CLI_COMMIT=4fe60c8b1cdac1c4c174f2fb180d0d758272d713
ARG VSCODE_CLI_SHA256=6f076b0ddecb89bbdefc8baeed0fcd0b1d81029976ad26fba2623c58200510c0

FROM ${DEBIAN_IMAGE} AS builder

ARG KUBECTL_VERSION
ARG KUBECTL_SHA256
ARG STARSHIP_VERSION
ARG STARSHIP_SHA256
ARG VSCODE_CLI_COMMIT
ARG VSCODE_CLI_SHA256

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gcc \
      libc6-dev; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY love/love.c /build/love.c

RUN set -eux; \
    curl -fsSLo /build/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    echo "${KUBECTL_SHA256}  /build/kubectl" | sha256sum -c -; \
    chmod 0755 /build/kubectl; \
    curl -fsSLo /build/starship.tar.gz "https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz"; \
    echo "${STARSHIP_SHA256}  /build/starship.tar.gz" | sha256sum -c -; \
    tar -xzf /build/starship.tar.gz -C /build starship; \
    chmod 0755 /build/starship; \
    curl -fsSLo /build/vscode-cli.tar.gz "https://vscode.download.prss.microsoft.com/dbazure/download/stable/${VSCODE_CLI_COMMIT}/vscode_cli_linux_x64_cli.tar.gz"; \
    echo "${VSCODE_CLI_SHA256}  /build/vscode-cli.tar.gz" | sha256sum -c -; \
    tar -xzf /build/vscode-cli.tar.gz -C /build code; \
    chmod 0755 /build/code; \
    /build/kubectl version --client=true >/dev/null; \
    /build/starship --version >/dev/null; \
    /build/code --version >/dev/null; \
    cc -O3 -D_FORTIFY_SOURCE=3 -fstack-protector-strong -fPIE -pie -Wl,-z,relro,-z,now \
      -o /build/love /build/love.c

FROM ${DEBIAN_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      git \
      jq \
      openssh-server \
      sudo \
      tmux \
      zsh; \
    rm -rf /var/lib/apt/lists/*; \
    useradd --create-home --home-dir /home/ida --shell /usr/bin/zsh --password '*' --groups sudo ida

COPY --from=builder /build/code /usr/local/bin/code
COPY --from=builder /build/kubectl /usr/local/bin/kubectl
COPY --from=builder /build/love /usr/local/bin/love
COPY --from=builder /build/starship /usr/local/bin/starship
COPY hestia/momus/entrypoint.sh /usr/local/bin/momus-entrypoint

RUN set -eux; \
    chmod 0755 \
      /usr/local/bin/code \
      /usr/local/bin/kubectl \
      /usr/local/bin/love \
      /usr/local/bin/momus-entrypoint \
      /usr/local/bin/starship; \
    install -d -m 0755 -o ida -g ida /home/ida; \
    install -d -m 0700 -o ida -g ida /home/ida/.kube /home/ida/.ssh; \
    install -d -m 0755 -o ida -g ida /home/ida/.config /home/ida/.vscode-cli /home/ida/Projects

EXPOSE 2222

ENTRYPOINT ["/usr/local/bin/momus-entrypoint"]
