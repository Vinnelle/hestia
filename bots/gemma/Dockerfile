FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS build
WORKDIR /app

ADD --checksum=sha256:db62d78016be36bd81c895d5f8688d8d286e19fe672af8f2acf4e8efac25ffd6 \
    https://github.com/Vinnelle/chat/releases/download/v0.5.2/chat-linux-x86_64 /chat
RUN chmod 0755 /chat

COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
COPY internal/ ./internal/
RUN CGO_ENABLED=0 go build -trimpath -ldflags=-s -o /gemma .

FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

RUN apk add --no-cache tor \
    && adduser -D -u 10001 gemma

COPY --from=build /chat /usr/local/bin/chat
COPY --from=build /gemma /usr/local/bin/gemma

ENV TOR_PATH=/usr/bin/tor CHAT_PATH=/usr/local/bin/chat
USER 10001
ENTRYPOINT ["/usr/local/bin/gemma"]
