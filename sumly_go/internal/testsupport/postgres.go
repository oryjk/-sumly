package testsupport

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
)

// OpenTestPostgres uses only an explicitly configured isolated test database.
// It never falls back to DATABASE_URL and never starts a container.
//
// TEST_DATABASE_URL 指向的库被多个测试 package 并行共享（go test ./... 时
// package 间并行），因此这里为每个测试创建独立的随机 schema 并在该 schema
// 内跑迁移；测试结束自动 DROP。用例之间、package 之间互不可见，任何测试都
// 不允许 TRUNCATE 共享业务表。
func OpenTestPostgres(t *testing.T) *pgxpool.Pool {
	t.Helper()
	databaseURL := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not configured; skipping PostgreSQL integration test")
	}

	admin, err := pgxpool.New(context.Background(), databaseURL)
	if err != nil {
		t.Fatalf("open TEST_DATABASE_URL: %v", err)
	}
	t.Cleanup(admin.Close)

	schema := randomTestSchemaName()
	if _, err := admin.Exec(context.Background(),
		fmt.Sprintf("CREATE SCHEMA %s", pgx.Identifier{schema}.Sanitize())); err != nil {
		t.Fatalf("create isolated test schema: %v", err)
	}
	t.Cleanup(func() {
		if _, err := admin.Exec(context.Background(),
			fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", pgx.Identifier{schema}.Sanitize())); err != nil {
			t.Logf("drop isolated test schema %s: %v", schema, err)
		}
	})

	runMigrations(t, databaseURL, schema)

	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		t.Fatalf("parse TEST_DATABASE_URL: %v", err)
	}
	poolConfig.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		t.Fatalf("open isolated schema pool: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("ping isolated schema pool: %v", err)
	}
	return pool
}

func randomTestSchemaName() string {
	var raw [8]byte
	if _, err := rand.Read(raw[:]); err != nil {
		panic("generate isolated test schema name: " + err.Error())
	}
	return "test_" + hex.EncodeToString(raw[:])
}

func runMigrations(t *testing.T, databaseURL string, schema string) {
	t.Helper()
	connConfig, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		t.Fatalf("parse TEST_DATABASE_URL: %v", err)
	}
	connConfig.RuntimeParams["search_path"] = schema
	migrationDSN := stdlib.RegisterConnConfig(connConfig)

	database, err := sql.Open("pgx", migrationDSN)
	if err != nil {
		t.Fatalf("open migration database: %v", err)
	}
	defer database.Close()

	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve test support source path")
	}
	migrationDir := filepath.Clean(filepath.Join(filepath.Dir(currentFile), "..", "..", "db", "migrations"))
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatalf("set goose dialect: %v", err)
	}
	if err := goose.Up(database, migrationDir); err != nil {
		t.Fatalf("run migrations from %s: %v", migrationDir, err)
	}
}
