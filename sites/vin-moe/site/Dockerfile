FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS images
RUN apk add --no-cache imagemagick librsvg libwebp-tools
COPY src/images/favicon.png .
COPY src/images/avatar.jpg .
RUN cwebp -q 82 -resize 288 288 avatar.jpg -o avatar.webp
RUN magick favicon.png -gravity center -background none -extent 530x530 \
    -define icon:auto-resize=16,32,48,64 favicon.ico
RUN magick favicon.png -gravity center -background none -extent 530x530 \
    -resize 180x180 apple-touch-icon.png

FROM mirror.vinnel.cloud/library/nginx:1.31-alpine@sha256:72ba65eb42c10344912a84ff42408db7d34f2feb642204570ab8fc5ffd29f1d3 AS brotli-builder
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

FROM mirror.vinnel.cloud/library/node:26-alpine@sha256:ef24c5053d50fdc3e4e56eb4e7ddb7861874ab0fdc797046ba897581deb8e868 AS asset-build
RUN apk add --no-cache brotli gzip curl
RUN npm install -g clean-css-cli terser html-minifier-terser

WORKDIR /app
COPY scripts/ /build/
COPY html/ .
COPY src/images/favicon.png .
COPY --from=images /favicon.ico .
COPY --from=images /apple-touch-icon.png .
COPY --from=images /avatar.webp .

RUN sh /build/fetch-fonts.sh fonts && sh /build/build.sh
RUN cp css/style.*.css css/post.css && cp fonts/jetbrains-mono.*.css fonts/post.css

FROM mirror.vinnel.cloud/nginxinc/nginx-unprivileged:1.31-alpine@sha256:2ddec616f1cb58bcac057aa388f28cb81e35137641ef4226d321714499329bd1
USER root
RUN apk --no-cache upgrade && rm /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
USER nginx
COPY --from=brotli-builder /ngx_http_brotli_filter_module.so /etc/nginx/modules/
COPY --from=brotli-builder /ngx_http_brotli_static_module.so /etc/nginx/modules/
COPY conf/nginx-main.conf /etc/nginx/nginx.conf
COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY conf/blog-proxy.inc /etc/nginx/conf.d/blog-proxy.inc
COPY --from=asset-build /app/ /usr/share/nginx/html/
EXPOSE 8080
