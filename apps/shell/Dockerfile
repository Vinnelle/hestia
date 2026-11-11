FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.37.2

RUN apk add --no-cache ttyd bash curl ca-certificates \
    && curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl \
    && rm -rf /var/cache/apk/*

RUN adduser -D -u 10001 shell
USER 10001

EXPOSE 7681
