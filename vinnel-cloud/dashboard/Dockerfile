FROM golang:1.26-alpine AS build
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

# chart.js is vendored at web/assets/js/chart.js (see the header comment in
# that file) — no unverified CDN fetch at build time
COPY . .
RUN CGO_ENABLED=0 go build -o /dashboard .

FROM alpine:3.24
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
COPY --from=build /dashboard /usr/local/bin/dashboard
# numeric so kubelet can verify runAsNonRoot
USER 10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/dashboard"]
