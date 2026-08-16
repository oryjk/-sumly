FROM golang:1.26.5-bookworm AS builder

# 内网构建环境无法直连 proxy.golang.org，默认走国内代理，可被 --build-arg 覆盖。
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG TARGETOS=linux
ARG TARGETARCH=arm64
RUN CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    go build -trimpath -ldflags="-s -w" -o /out/sumly-go-api ./cmd/api

FROM debian:bookworm-slim AS runtime

# 运行时只需要 CA 证书与 zoneinfo，从 builder 拷贝即可，避免 apt 依赖外网。
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

RUN useradd --system --uid 10001 --create-home app

WORKDIR /app
COPY --from=builder /out/sumly-go-api /app/sumly-go-api

USER app
EXPOSE 18090

ENTRYPOINT ["/app/sumly-go-api"]
