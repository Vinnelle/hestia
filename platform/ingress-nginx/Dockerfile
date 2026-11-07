FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:fa3d596898d9f126af7c01d14ee7597bab3f39cccf392ef36b69fe77cd681f18 AS build
RUN apk add --no-cache bash
WORKDIR /src
COPY . .
ARG TAG
ARG COMMIT_SHA
ENV GOFLAGS=-buildvcs=false GOTOOLCHAIN=local
RUN PKG=k8s.io/ingress-nginx ARCH=amd64 REPO_INFO=https://github.com/chainguard-forks/ingress-nginx TAG="$TAG" COMMIT_SHA="$COMMIT_SHA" build/build.sh

FROM scratch
COPY --from=build /src/rootfs/bin/amd64/ /
