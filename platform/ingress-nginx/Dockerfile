FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS build
RUN apk add --no-cache bash
WORKDIR /src
COPY . .
ARG TAG
ARG COMMIT_SHA
ENV GOFLAGS=-buildvcs=false GOTOOLCHAIN=local
RUN PKG=k8s.io/ingress-nginx ARCH=amd64 REPO_INFO=https://github.com/chainguard-forks/ingress-nginx TAG="$TAG" COMMIT_SHA="$COMMIT_SHA" build/build.sh

FROM scratch
COPY --from=build /src/rootfs/bin/amd64/ /
