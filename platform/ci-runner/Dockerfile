FROM debian:trixie-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.36.4
# renovate: datasource=github-releases depName=terraform-linters/tflint
ARG TFLINT_VERSION=v0.64.0
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.98.0

ARG CACHEBUST=0
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      rsync \
      build-essential \
      shellcheck \
      yamllint \
      unzip \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.asc \
    && chmod a+r /etc/apt/keyrings/nodesource.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/nodesource.asc] https://deb.nodesource.com/node_26.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* /usr/lib/node_modules/npm /usr/bin/npm /usr/bin/npx

RUN groupadd -g 1001 runner \
    && useradd -u 1001 -g runner -m -d /home/runner -s /bin/bash runner

RUN curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl

RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip" -o /tmp/tflint.zip \
    && unzip -q /tmp/tflint.zip -d /usr/local/bin \
    && chmod 0755 /usr/local/bin/tflint \
    && rm /tmp/tflint.zip

RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64"

USER runner
WORKDIR /home/runner
