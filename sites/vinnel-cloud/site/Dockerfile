FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools fontconfig
COPY shared/images/ .
COPY site/src/images/ .
COPY site/src/fonts/ /usr/share/fonts/truetype/vinnel-cloud/
RUN fc-cache -f
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp \
 && rsvg-convert -w 1200 -h 630 vinnel-cloud-social.svg | magick png:- vinnel-cloud-social.webp

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

FROM mirror.vinnel.cloud/library/node:26-alpine@sha256:8996bb5821d62a8fd9bb27c1cb07462f3fdce6e47d640c6a881ead0b064ce216 AS asset-build
RUN apk add --no-cache brotli gzip curl
RUN npm install -g clean-css-cli terser html-minifier-terser

WORKDIR /app
COPY shared/scripts/ /build/
COPY shared/html/ .
COPY site/html/ .
COPY --from=images /*.webp assets/images/

RUN sh /build/fetch-fonts.sh assets/fonts && sh /build/build.sh

FROM mirror.vinnel.cloud/nginxinc/nginx-unprivileged:1.31-alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e
USER root
RUN apk --no-cache upgrade && rm /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
USER nginx
COPY --from=brotli-builder /ngx_http_brotli_filter_module.so /etc/nginx/modules/
COPY --from=brotli-builder /ngx_http_brotli_static_module.so /etc/nginx/modules/
COPY shared/conf/nginx-main.conf /etc/nginx/nginx.conf
COPY site/conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=asset-build /app/ /usr/share/nginx/html/
EXPOSE 8080
