FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS gosu
RUN apk add --no-cache git
RUN git clone --quiet --depth 1 --branch 1.19 https://github.com/tianon/gosu /src
WORKDIR /src
RUN CGO_ENABLED=0 GOTOOLCHAIN=local go build -trimpath -ldflags='-s -w' -o /gosu .

FROM mirror.vinnel.cloud/library/postgres:18-alpine@sha256:10a5c69a83035ab5239f5620d708520e8b28f5aa1f2b20143e6024532edadfb5
RUN apk upgrade --no-cache
COPY --from=gosu /gosu /usr/local/bin/gosu
