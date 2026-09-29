package authhttp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	"github.com/gin-gonic/gin"
)

type httpNotificationApple struct{ ports.AppleGateway }

func (httpNotificationApple) Enabled() bool { return true }
func (httpNotificationApple) VerifyNotification(context.Context, string) (domain.AppleNotification, error) {
	return domain.AppleNotification{Type: "email-enabled", Subject: "subject"}, nil
}

type httpNotificationStore struct{ ports.NativeStore }

func (*httpNotificationStore) ApplyAppleEvent(context.Context, domain.AppleNotification) error {
	return nil
}

func TestAppleNotificationEndpointAcceptsPayloadAndBoundsBody(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	h := NewNativeHandler(application.Accounts{Store: &httpNotificationStore{}, Apple: httpNotificationApple{}}, application.Sessions{})
	h.RegisterRoutes(r.Group("/api/v1/app"))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/apple/notifications", strings.NewReader(`{"payload":"signed-jws"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}

	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/apple/notifications", strings.NewReader(`{"payload":"signed-jws","email":"should-not-be-accepted@example.com"}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("recognized extra field status=%d body=%s", w.Code, w.Body.String())
	}

	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/apple/notifications", strings.NewReader(`{"payload":"","extra":true}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("unknown field status=%d body=%s", w.Code, w.Body.String())
	}

	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/apple/notifications", strings.NewReader(strings.Repeat("x", 40000)))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("oversize status=%d body=%s", w.Code, w.Body.String())
	}
}
