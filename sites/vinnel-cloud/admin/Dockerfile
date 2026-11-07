FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:3f4d6b32e26703c6082839234f43769d5046b3ac7c910033911d1e71d8cd630a AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools
COPY shared/images/ .
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp

FROM mirror.vinnel.cloud/library/node:26-alpine@sha256:8996bb5821d62a8fd9bb27c1cb07462f3fdce6e47d640c6a881ead0b064ce216 AS asset-build
RUN apk add --no-cache brotli gzip curl
RUN npm install -g clean-css-cli terser html-minifier-terser

WORKDIR /app
COPY shared/scripts/ /build/
COPY shared/html/ .
COPY admin/html/ .
COPY --from=images /favicon.webp assets/images/

COPY admin/editor/package.json admin/editor/package-lock.json /editor/
RUN cd /editor && npm ci --no-audit --no-fund
COPY admin/editor/ /editor/
RUN cd /editor && node test.mjs && node build.mjs /app/assets/js/editor.js

RUN sh /build/fetch-fonts.sh assets/fonts && sh /build/build.sh \
 && find . \( -name '*.gz' -o -name '*.br' \) -delete

FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:fa3d596898d9f126af7c01d14ee7597bab3f39cccf392ef36b69fe77cd681f18 AS build
WORKDIR /app

COPY admin/go.mod admin/go.sum ./
RUN go mod download

COPY admin/*.go ./
COPY admin/internal/ ./internal/
COPY --from=asset-build /app/ ./html/
RUN CGO_ENABLED=0 go build -o /admin .

FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:3f4d6b32e26703c6082839234f43769d5046b3ac7c910033911d1e71d8cd630a
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=build /admin /usr/local/bin/admin
USER 10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/admin"]
