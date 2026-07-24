# Pre-bakes the tools every gaia workflow currently installs on every run
# (docker.io, gh, jq, rsync, nodejs, build-essential, kubectl, tflint,
# shellcheck, yamllint, actionlint). Each workflow already guards its
# install step with `type -p <tool> || apt-get install -y <tool>`, so
# nothing else needs to change: once this image is wired in, those guards
# just become no-ops.
#
# Terraform itself stays on hashicorp/setup-terraform (handles version
# selection); not baked in here.
FROM ghcr.io/actions/actions-runner:latest

ARG KUBECTL_VERSION=v1.31.2
ARG TFLINT_VERSION=v0.53.0
ARG ACTIONLINT_VERSION=1.7.7

USER root

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
      docker.io \
      gh \
      jq \
      rsync \
      nodejs \
      build-essential \
      shellcheck \
      yamllint \
      curl \
      unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl

RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip" -o /tmp/tflint.zip \
    && unzip -q /tmp/tflint.zip -d /usr/local/bin \
    && chmod 0755 /usr/local/bin/tflint \
    && rm /tmp/tflint.zip

RUN curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" -o /tmp/actionlint.tar.gz \
    && tar -xzf /tmp/actionlint.tar.gz -C /usr/local/bin actionlint \
    && chmod 0755 /usr/local/bin/actionlint \
    && rm /tmp/actionlint.tar.gz

USER runner
