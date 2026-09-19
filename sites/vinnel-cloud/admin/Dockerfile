FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS images
RUN apk add --no-cache imagemagick librsvg rsvg-convert libwebp-tools
COPY shared/images/ .
RUN rsvg-convert -w 64 -h 64 favicon.svg | magick png:- favicon.webp

FROM mirror.vinnel.cloud/library/node:26-alpine@sha256:dbaa92e5758cbbcf85d65d5403fdb530fe3442cbe8c6dbfb7ef23365450d5070 AS asset-build
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

FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:4cb7ac979db5fcc41cae44b2227ba5ab8a51e8807f40d9ba4dee20a0ad960b5b AS build
WORKDIR /app

COPY admin/go.mod admin/go.sum ./
RUN go mod download

COPY admin/*.go ./
COPY admin/internal/ ./internal/
COPY --from=asset-build /app/ ./html/
RUN CGO_ENABLED=0 go build -o /admin .

FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=build /admin /usr/local/bin/admin
USER 10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/admin"]
