package authhttp

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"github.com/gin-gonic/gin"
)

func TestNativeContractDisabledAndBounded(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	h := NewNativeHandler(application.Accounts{}, application.Sessions{})
	h.RegisterRoutes(r.Group("/api/v1/app"))
	for _, tc := range []struct {
		method, path, body string
		status             int
	}{
		{"GET", "/capabilities", "", 200}, {"POST", "/phone/code", `{"phone_number":"13800138000"}`, 503},
		{"POST", "/email/register", `{"email":"a@example.com","password":"abcdefghijkl","code":"123456"}`, 503},
		{"POST", "/apple/challenge", `{}`, 503}, {"GET", "/me", "", 401}, {"DELETE", "/account", `{"confirmation":"DELETE"}`, 401},
		{"POST", "/phone/login", strings.Repeat("x", 40000), 422},
	} {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(tc.method, "/api/v1/app/auth"+tc.path, strings.NewReader(tc.body))
		req.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, req)
		if w.Code != tc.status {
			t.Fatalf("%s %s: %d %s", tc.method, tc.path, w.Code, w.Body.String())
		}
		if tc.path == "/capabilities" && w.Body.String() != `{"code":0,"message":"ok","data":{"apple":false,"phone":false,"email":false}}` {
			t.Fatal(w.Body.String())
		}
	}
	_ = http.MethodPost
}
