#!/bin/sh
set -eu

image=artifacts.vinnel.cloud/vinnel-cloud/gaia/ingress-nginx
version=${INGRESS_NGINX_VERSION#controller-}
src=$(mktemp -d)

git clone --quiet --depth 1 --branch "$INGRESS_NGINX_VERSION" https://github.com/chainguard-forks/ingress-nginx.git "$src"
head=$(git -C "$src" rev-parse HEAD)
if [ "$head" != "$INGRESS_NGINX_COMMIT" ]; then
  echo "$INGRESS_NGINX_VERSION is $head, expected $INGRESS_NGINX_COMMIT" >&2
  exit 1
fi

nginx_build="$src/images/nginx/rootfs/build.sh"
sed -i \
  -e "s|^CORES=.*|CORES=$INGRESS_NGINX_BUILD_JOBS|" \
  -e "s|^export MAKEFLAGS=-j\${CORES}\$|export MAKEFLAGS=-j\${CORES} CMAKE_BUILD_PARALLEL_LEVEL=\${CORES}|" \
  "$nginx_build"
if ! grep -qx "CORES=$INGRESS_NGINX_BUILD_JOBS" "$nginx_build" || ! grep -q "CMAKE_BUILD_PARALLEL_LEVEL=\${CORES}\$" "$nginx_build"; then
  echo "could not cap the nginx build at $INGRESS_NGINX_BUILD_JOBS jobs; build.sh changed upstream" >&2
  exit 1
fi

buildctl-daemonless.sh build \
  --frontend dockerfile.v0 \
  --local context="$src/images/nginx/rootfs" \
  --local dockerfile="$src/images/nginx/rootfs" \
  --metadata-file /tmp/nginx.json \
  --output "type=image,name=$image/nginx:$version,push=true"
nginx="$image/nginx@$(jq -r '.["containerimage.digest"]' /tmp/nginx.json)"

buildctl-daemonless.sh build \
  --frontend dockerfile.v0 \
  --local context="$src" \
  --local dockerfile=hestia/platform/ingress-nginx \
  --opt build-arg:TAG="$version" \
  --opt build-arg:COMMIT_SHA="$INGRESS_NGINX_COMMIT" \
  --output "type=local,dest=$src/rootfs/bin/amd64"

buildctl-daemonless.sh build \
  --frontend dockerfile.v0 \
  --local context="$src/rootfs" \
  --local dockerfile="$src/rootfs" \
  --no-cache \
  --opt build-arg:BASE_IMAGE="$nginx" \
  --opt build-arg:VERSION="$version" \
  --opt build-arg:COMMIT_SHA="$INGRESS_NGINX_COMMIT" \
  --opt build-arg:BUILD_ID="$CI_PIPELINE_ID" \
  --metadata-file /tmp/controller.json \
  --output "type=image,name=$image/controller:$version,push=true"

sh .gitlab-ci/scripts/record-image-digest.sh ingress-nginx-controller \
  "$image/controller:$version@$(jq -r '.["containerimage.digest"]' /tmp/controller.json)"
