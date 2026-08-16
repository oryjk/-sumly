package bootstrap

import (
	"fmt"
	"os"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/shared/configenv"
)

type AppEnvironment string

const (
	EnvironmentDevelopment AppEnvironment = "development"
	EnvironmentTest        AppEnvironment = "test"
	EnvironmentProduction  AppEnvironment = "production"
)

type Config struct {
	HTTPAddr        string
	DatabaseURL     string
	JWTSecret       string
	WechatAppID     string
	WechatAppSecret string
	AppEnvironment  AppEnvironment
}

func LoadConfig() (Config, error) {
	configenv.Load()
	config := Config{
		HTTPAddr:        envOrDefault("HTTP_ADDR", ":18090"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		JWTSecret:       os.Getenv("JWT_SECRET"),
		WechatAppID:     os.Getenv("WECHAT_APP_ID"),
		WechatAppSecret: os.Getenv("WECHAT_APP_SECRET"),
		AppEnvironment:  parseAppEnvironment(os.Getenv("APP_ENV")),
	}

	for name, value := range map[string]string{
		"DATABASE_URL":      config.DatabaseURL,
		"JWT_SECRET":        config.JWTSecret,
		"WECHAT_APP_ID":     config.WechatAppID,
		"WECHAT_APP_SECRET": config.WechatAppSecret,
	} {
		if value == "" {
			return Config{}, fmt.Errorf("%s is required", name)
		}
	}
	return config, nil
}

func parseAppEnvironment(value string) AppEnvironment {
	switch AppEnvironment(strings.TrimSpace(value)) {
	case EnvironmentDevelopment:
		return EnvironmentDevelopment
	case EnvironmentTest:
		return EnvironmentTest
	case EnvironmentProduction:
		return EnvironmentProduction
	default:
		return EnvironmentProduction
	}
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
