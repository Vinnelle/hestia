FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools
COPY src/images/ .
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp

FROM node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS asset-build
RUN apk add --no-cache brotli gzip curl
RUN npm install -g clean-css-cli terser

WORKDIR /app
COPY scripts/ /build/
COPY html/ .
COPY --from=images /favicon.webp assets/images/

RUN sh /build/fetch-fonts.sh assets/fonts && sh /build/build.sh \
 && find . \( -name '*.gz' -o -name '*.br' \) -delete

FROM golang:1.26-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS build
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
COPY --from=asset-build /app/ ./html/
RUN CGO_ENABLED=0 go build -o /admin .

FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=build /admin /usr/local/bin/admin
USER 10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/admin"]
