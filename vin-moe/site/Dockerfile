FROM alpine:3.24 AS images
RUN apk add --no-cache imagemagick librsvg libwebp-tools
COPY src/images/favicon.png .
RUN magick favicon.png -gravity center -background none -extent 530x530 \
    -define icon:auto-resize=16,32,48,64 favicon.ico

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

FROM node:24-alpine AS asset-build
RUN apk add --no-cache brotli gzip
RUN npm install -g clean-css-cli terser

WORKDIR /app
COPY build.sh .
COPY html/ .
COPY --from=images /favicon.ico .

RUN sh build.sh

FROM nginxinc/nginx-unprivileged:1.31-alpine
USER root
RUN apk --no-cache upgrade
USER nginx
COPY --from=brotli-builder /ngx_http_brotli_filter_module.so /etc/nginx/modules/
COPY --from=brotli-builder /ngx_http_brotli_static_module.so /etc/nginx/modules/
COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=asset-build /app/ /usr/share/nginx/html/
EXPOSE 8080
