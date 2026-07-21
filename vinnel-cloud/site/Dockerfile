FROM alpine:3.24 AS images
RUN apk add --no-cache imagemagick
COPY src/images/ .
RUN magick favicon.svg -background none -resize 64x64 favicon.webp \
 && magick vinnel-cloud-dark.svg -background none -resize 400x100 vinnel-cloud-dark-1x.webp \
 && magick vinnel-cloud-dark.svg -background none -resize 800x200 vinnel-cloud-dark-2x.webp \
 && magick vinnel-cloud-light.svg -background none -resize 400x100 vinnel-cloud-light-1x.webp \
 && magick vinnel-cloud-light.svg -background none -resize 800x200 vinnel-cloud-light-2x.webp \
 && magick vinnel-cloud-gradient.svg -background none -resize 800x200 vinnel-cloud-gradient.webp

FROM nginx:1.31-alpine AS brotli-builder
RUN apk add --no-cache git gcc musl-dev make pcre2-dev zlib-dev linux-headers openssl-dev brotli-dev
# ngx_brotli publishes no versioned releases compatible with current nginx, so
# master is cloned at build time; the module is compiled against the exact
# nginx version of the base image above
RUN git clone --recurse-submodules https://github.com/google/ngx_brotli /tmp/ngx_brotli \
 && NGINX_VERSION=$(nginx -v 2>&1 | sed 's/.*\///') \
 && wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O /tmp/nginx.tar.gz \
 && tar -C /tmp -xzf /tmp/nginx.tar.gz \
 && cd /tmp/nginx-${NGINX_VERSION} \
 && ./configure --with-compat --add-dynamic-module=/tmp/ngx_brotli \
 && make modules \
 && cp objs/ngx_http_brotli_filter_module.so /ngx_http_brotli_filter_module.so \
 && cp objs/ngx_http_brotli_static_module.so /ngx_http_brotli_static_module.so

FROM node:24-alpine AS build
RUN apk add --no-cache brotli gzip
RUN npm install -g clean-css-cli

WORKDIR /app
COPY build.sh .
COPY html/ .
COPY --from=images /*.webp assets/images/

RUN sh build.sh

FROM nginxinc/nginx-unprivileged:1.31-alpine
USER root
RUN apk --no-cache upgrade
USER nginx
COPY --from=brotli-builder /ngx_http_brotli_filter_module.so /etc/nginx/modules/
COPY --from=brotli-builder /ngx_http_brotli_static_module.so /etc/nginx/modules/
COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/ /usr/share/nginx/html/
EXPOSE 8080
