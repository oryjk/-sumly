// dbmigrate 对 DATABASE_URL 指定的 PostgreSQL 执行 db/migrations 下的 goose 前向迁移。
//
// 之所以不用 `go run github.com/pressly/goose/v3/cmd/goose@version`：CLI 入口会引入
// 全量数据库驱动依赖（ydb、mymysql 等），它们不在仓库 go.sum 里，go run 会直接报
// missing go.sum entry。这里只链接仓库已依赖的 goose 库与 pgx 驱动。
//
// 在 sumly_go 目录下运行：
//
//	DATABASE_URL=postgres://... go run ./cmd/dbmigrate
package main

import (
	"database/sql"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
)

func main() {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		slog.Error("需要设置 DATABASE_URL")
		os.Exit(1)
	}
	if err := run(databaseURL, "db/migrations"); err != nil {
		slog.Error("迁移失败", "error", err)
		os.Exit(1)
	}
}

func run(databaseURL, migrationDir string) error {
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return fmt.Errorf("打开数据库: %w", err)
	}
	defer database.Close()

	absDir, err := filepath.Abs(migrationDir)
	if err != nil {
		return fmt.Errorf("定位迁移目录: %w", err)
	}
	if info, err := os.Stat(absDir); err != nil || !info.IsDir() {
		return fmt.Errorf("迁移目录不存在: %s", absDir)
	}
	if err := goose.SetDialect("postgres"); err != nil {
		return fmt.Errorf("goose 方言: %w", err)
	}
	if err := goose.Up(database, absDir); err != nil {
		return fmt.Errorf("goose up: %w", err)
	}
	slog.Info("迁移完成", "dir", absDir)
	return nil
}
