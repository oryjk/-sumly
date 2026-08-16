.PHONY: generate migrate-up migrate-down migrate-status fmt test vet build run verify

export GOPROXY := https://goproxy.cn,direct
export GOSUMDB := sum.golang.google.cn
export GOTOOLCHAIN := go1.26.5

SQLC_VERSION := v1.31.1
ENV_FILE ?= ./.env

define with_env
	@test -f "$(ENV_FILE)" || { echo "missing $(ENV_FILE); copy .env.example to .env first"; exit 1; }; set -a; . "$(ENV_FILE)"; set +a; $(1)
endef

generate:
	go run github.com/sqlc-dev/sqlc/cmd/sqlc@$(SQLC_VERSION) generate

migrate-up:
	$(call with_env,go run ./cmd/dbmigrate)

migrate-down:
	$(call with_env,go run github.com/pressly/goose/v3/cmd/goose@v3.27.2 -dir db/migrations postgres "$$DATABASE_URL" down)

migrate-status:
	$(call with_env,go run github.com/pressly/goose/v3/cmd/goose@v3.27.2 -dir db/migrations postgres "$$DATABASE_URL" status)

fmt:
	gofmt -w .

test:
	go test ./...

vet:
	go vet ./...

build:
	go build -o /tmp/sumly-go-api ./cmd/api

run:
	$(call with_env,go run ./cmd/api)

verify: generate fmt test vet build
