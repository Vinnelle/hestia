FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools
COPY shared/images/ .
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp

FROM mirror.vinnel.cloud/nginxinc/nginx-unprivileged:1.31-alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e AS brotli-builder
USER root
RUN apk add --no-cache git gcc musl-dev make pcre2-dev zlib-dev linux-headers openssl-dev brotli-dev
RUN git clone --recurse-submodules https://github.com/google/ngx_brotli /tmp/ngx_brotli \
 && NGINX_VERSION=$(nginx -v 2>&1 | sed 's/.*\///') \
 && wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O /tmp/nginx.tar.gz \
 && tar -C /tmp -xzf /tmp/nginx.tar.gz \
 && cd /tmp/nginx-${NGINX_VERSION} \
 && ./configure --with-compat --add-dynamic-module=/tmp/ngx_brotli \
 && make modules \
 && cp objs/ngx_http_brotli_filter_module.so /ngx_http_brotli_filter_module.so \
 && cp objs/ngx_http_brotli_static_module.so /ngx_http_brotli_static_module.so

FROM mirror.vinnel.cloud/library/node:26-alpine@sha256:40cd011b55415bc894e45b02fdd5a5dfde056921b7d23a64c74f80497af48797 AS asset-build
RUN apk add --no-cache brotli gzip curl
RUN npm install -g clean-css-cli terser html-minifier-terser

WORKDIR /app
COPY shared/scripts/ /build/
COPY shared/html/ .
COPY auth/html/ .
COPY --from=images /favicon.webp assets/images/

RUN sh /build/fetch-fonts.sh assets/fonts && sh /build/build.sh

FROM mirror.vinnel.cloud/nginxinc/nginx-unprivileged:1.31-alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e
USER root
RUN apk --no-cache upgrade && rm /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
USER nginx
COPY --from=brotli-builder /ngx_http_brotli_filter_module.so /etc/nginx/modules/
COPY --from=brotli-builder /ngx_http_brotli_static_module.so /etc/nginx/modules/
COPY shared/conf/nginx-main.conf /etc/nginx/nginx.conf
COPY auth/conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=asset-build /app/ /usr/share/nginx/html/
EXPOSE 8080
