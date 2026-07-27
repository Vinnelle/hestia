FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools fontconfig
COPY src/images/ .
# librsvg in this image doesn't load embedded @font-face data URIs, so the
# wordmark fonts are installed as real system fonts instead
COPY src/fonts/ /usr/share/fonts/truetype/vinnel-cloud/
RUN fc-cache -f
# magick's own SVG rasterizer flattens transparency to opaque white despite
# -background none; rsvg-convert renders real alpha, so it does the SVG->PNG
# step and magick only handles the PNG->WebP encode
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp \
 && rsvg-convert -w 400 -h 100 vinnel-cloud-dark.svg | magick png:- vinnel-cloud-dark-1x.webp \
 && rsvg-convert -w 800 -h 200 vinnel-cloud-dark.svg | magick png:- vinnel-cloud-dark-2x.webp \
 && rsvg-convert -w 400 -h 100 vinnel-cloud-light.svg | magick png:- vinnel-cloud-light-1x.webp \
 && rsvg-convert -w 800 -h 200 vinnel-cloud-light.svg | magick png:- vinnel-cloud-light-2x.webp \
 && rsvg-convert -w 800 -h 200 vinnel-cloud-gradient.svg | magick png:- vinnel-cloud-gradient.webp

FROM nginx:1.31-alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752 AS brotli-builder
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

FROM node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS asset-build
RUN apk add --no-cache brotli gzip
RUN npm install -g clean-css-cli terser

WORKDIR /app
COPY build.sh .
COPY html/ .
COPY --from=images /*.webp assets/images/

RUN sh build.sh

FROM nginxinc/nginx-unprivileged:1.31-alpine@sha256:59ccf0943b0b8e8d9e6ea9039a39555730f544701a655c596f7df7d096c593f5
USER root
RUN apk --no-cache upgrade
USER nginx
COPY --from=brotli-builder /ngx_http_brotli_filter_module.so /etc/nginx/modules/
COPY --from=brotli-builder /ngx_http_brotli_static_module.so /etc/nginx/modules/
COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=asset-build /app/ /usr/share/nginx/html/
EXPOSE 8080
