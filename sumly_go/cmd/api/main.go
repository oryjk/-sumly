package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/bootstrap"
)

func main() {
	config, err := bootstrap.LoadConfig()
	if err != nil {
		slog.Error("load configuration", "error", err)
		os.Exit(1)
	}
	dependencies, closeDependencies, err := bootstrap.BuildDependencies(context.Background(), config)
	if err != nil {
		slog.Error("build dependencies", "error", err)
		os.Exit(1)
	}
	defer closeDependencies()

	server := &http.Server{
		Addr:              config.HTTPAddr,
		Handler:           bootstrap.NewRouter(dependencies),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	slog.Info("starting HTTP server", "address", config.HTTPAddr, "environment", config.AppEnvironment)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("HTTP server stopped", "error", err)
		os.Exit(1)
	}
}
