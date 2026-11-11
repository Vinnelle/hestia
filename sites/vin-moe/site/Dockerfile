FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS images
RUN apk add --no-cache imagemagick librsvg libwebp-tools
COPY src/images/favicon.png .
COPY src/images/avatar.jpg .
RUN cwebp -q 82 -resize 288 288 avatar.jpg -o avatar.webp
RUN magick favicon.png -gravity center -background none -extent 530x530 \
    -define icon:auto-resize=16,32,48,64 favicon.ico
RUN magick favicon.png -gravity center -background none -extent 530x530 \
    -resize 180x180 apple-touch-icon.png

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
COPY scripts/ /build/
COPY html/ .
COPY src/images/favicon.png .
COPY --from=images /favicon.ico .
COPY --from=images /apple-touch-icon.png .
COPY --from=images /avatar.webp .

RUN sh /build/fetch-fonts.sh fonts && sh /build/embed-runner.sh && sh /build/build.sh
RUN cp css/style.*.css css/post.css && cp fonts/jetbrains-mono.*.css fonts/post.css
RUN chmod -R a+rX /app

FROM mirror.vinnel.cloud/nginxinc/nginx-unprivileged:1.31-alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e
USER root
RUN apk --no-cache upgrade && rm /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh \
 && install -d -m 0755 /etc/nginx/njs
USER nginx
COPY --from=brotli-builder /ngx_http_brotli_filter_module.so /etc/nginx/modules/
COPY --from=brotli-builder /ngx_http_brotli_static_module.so /etc/nginx/modules/
COPY --chmod=0644 conf/nginx-main.conf /etc/nginx/nginx.conf
COPY --chmod=0644 conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=0644 conf/blog-proxy.inc /etc/nginx/conf.d/blog-proxy.inc
COPY --chmod=0644 conf/invite.js /etc/nginx/njs/invite.js
COPY --from=asset-build /app/ /usr/share/nginx/html/
EXPOSE 8080
