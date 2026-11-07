FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:fa3d596898d9f126af7c01d14ee7597bab3f39cccf392ef36b69fe77cd681f18 AS gosu
RUN apk add --no-cache git
RUN git clone --quiet --depth 1 --branch 1.19 https://github.com/tianon/gosu /src
WORKDIR /src
RUN CGO_ENABLED=0 GOTOOLCHAIN=local go build -trimpath -ldflags='-s -w' -o /gosu .

FROM mirror.vinnel.cloud/library/postgres:18-alpine@sha256:123b17998ccaf47e53b502e8c6a1e79afd8f579c6f3eec83c563da026f957395
RUN apk upgrade --no-cache
COPY --from=gosu /gosu /usr/local/bin/gosu
