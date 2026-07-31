FROM alpine:3.22

ARG KUBECTL_VERSION=v1.31.2

RUN apk add --no-cache ttyd bash curl ca-certificates \
    && curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl \
    && rm -rf /var/cache/apk/*

RUN adduser -D -u 10001 shell
USER 10001

EXPOSE 7681
