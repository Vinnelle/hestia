FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools
COPY shared/images/ .
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp

FROM mirror.vinnel.cloud/library/node:26-alpine@sha256:40cd011b55415bc894e45b02fdd5a5dfde056921b7d23a64c74f80497af48797 AS asset-build
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

FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS build
WORKDIR /app

COPY admin/go.mod admin/go.sum ./
RUN go mod download

COPY admin/*.go ./
COPY admin/internal/ ./internal/
COPY --from=asset-build /app/ ./html/
RUN CGO_ENABLED=0 go build -o /admin .

FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=build /admin /usr/local/bin/admin
USER 10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/admin"]
