FROM alpine:3.24 AS favicon
RUN apk add --no-cache imagemagick
COPY src/ico.png .
RUN magick ico.png -gravity center -background none -extent 530x530 \
    -define icon:auto-resize=16,32,48,64 favicon.ico

FROM nginxinc/nginx-unprivileged:1.31-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY html /usr/share/nginx/html
COPY --from=favicon /favicon.ico /usr/share/nginx/html/favicon.ico