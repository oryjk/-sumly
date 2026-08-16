package bootstrap

import "testing"

func TestLoadConfigParsesDevLoginEnabled(t *testing.T) {
	for _, test := range []struct {
		name     string
		value    string
		expected bool
	}{
		{name: "true 开启", value: "true", expected: true},
		{name: "false 关闭", value: "false", expected: false},
		{name: "缺省关闭", value: "", expected: false},
		{name: "其他值关闭", value: "1", expected: false},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("DATABASE_URL", "postgres://example")
			t.Setenv("JWT_SECRET", "secret")
			t.Setenv("WECHAT_APP_ID", "appid")
			t.Setenv("WECHAT_APP_SECRET", "appsecret")
			t.Setenv("DEV_LOGIN_ENABLED", test.value)

			config, err := LoadConfig()
			if err != nil {
				t.Fatalf("load config: %v", err)
			}
			if config.DevLoginEnabled != test.expected {
				t.Fatalf("expected DevLoginEnabled=%v, got %v", test.expected, config.DevLoginEnabled)
			}
		})
	}
}
