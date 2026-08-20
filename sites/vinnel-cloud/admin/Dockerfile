FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools
COPY shared/images/ .
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp

FROM mirror.vinnel.cloud/library/node:24-alpine@sha256:d32cdf619f63fe0471182d08996dd516c6275bb5fd31ae06e55a570bd9e1ad43 AS asset-build
RUN apk add --no-cache brotli gzip curl
RUN npm install -g clean-css-cli terser html-minifier-terser

WORKDIR /app
COPY shared/scripts/ /build/
COPY shared/html/ .
COPY admin/html/ .
COPY --from=images /favicon.webp assets/images/

RUN sh /build/fetch-fonts.sh assets/fonts && sh /build/fetch-service-icons.sh assets/images/services && sh /build/build.sh \
 && find . \( -name '*.gz' -o -name '*.br' \) -delete

FROM mirror.vinnel.cloud/library/golang:1.26-alpine@sha256:28d89ee9cc0ff9fec75c82ca201e6bf7fdf9a679d4b7b24dfa04f2bb766bb468 AS build
WORKDIR /app

COPY admin/go.mod admin/go.sum ./
RUN go mod download

COPY admin/*.go ./
COPY admin/internal/ ./internal/
COPY --from=asset-build /app/ ./html/
RUN CGO_ENABLED=0 go build -o /admin .

FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=build /admin /usr/local/bin/admin
USER 10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/admin"]
