FROM mirror.vinnel.cloud/library/golang:1.27-alpine@sha256:fa3d596898d9f126af7c01d14ee7597bab3f39cccf392ef36b69fe77cd681f18 AS build
WORKDIR /app

ADD --checksum=sha256:1168849a67369e3c0264d4cc28eeb7135394ba563d2a750e825bea77f37274d7 \
    https://github.com/Vinnelle/chat/releases/download/v0.5.4/chat-linux-x86_64 /chat
RUN chmod 0755 /chat

COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
COPY internal/ ./internal/
RUN CGO_ENABLED=0 go build -trimpath -ldflags=-s -o /gemma .

FROM mirror.vinnel.cloud/library/alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

RUN apk add --no-cache tor curl \
    && adduser -D -u 10001 gemma

COPY --from=build /chat /usr/local/bin/chat
COPY --from=build /gemma /usr/local/bin/gemma

ENV TOR_PATH=/usr/bin/tor CHAT_PATH=/usr/local/bin/chat
USER 10001
ENTRYPOINT ["/usr/local/bin/gemma"]
