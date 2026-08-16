package db_test

import (
	"math"
	"testing"

	"github.com/pressly/goose/v3"
)

func TestMigrationsHaveUniqueVersions(t *testing.T) {
	if _, err := goose.CollectMigrations("migrations", 0, math.MaxInt64); err != nil {
		t.Fatalf("collect migrations: %v", err)
	}
}
