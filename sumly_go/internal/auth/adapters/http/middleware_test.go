package authhttp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"github.com/gin-gonic/gin"
)

const middlewareTestSecret = "01234567890123456789012345678901"

func newMiddlewareTestRouter(t *testing.T, middleware Middleware) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	router := gin.New()
	protected := router.Group("/me")
	protected.Use(middleware.RequireUser())
	protected.GET("", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})
	return router
}

func TestRequireUserAcceptsValidUserToken(t *testing.T) {
	tokens, err := jwt.NewService(middlewareTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	router := newMiddlewareTestRouter(t, NewMiddleware(tokens))
	token, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	request := httptest.NewRequest(http.MethodGet, "/me", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, response.Code, response.Body.String())
	}
}

func TestRequireUserRejectsMissingToken(t *testing.T) {
	tokens, err := jwt.NewService(middlewareTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	router := newMiddlewareTestRouter(t, NewMiddleware(tokens))

	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/me", nil))

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected status %d, got %d", http.StatusUnauthorized, response.Code)
	}
}

func TestRequireUserRejectsAdminToken(t *testing.T) {
	tokens, err := jwt.NewService(middlewareTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	router := newMiddlewareTestRouter(t, NewMiddleware(tokens))
	token, err := tokens.IssueAdmin(context.Background(), 7, false)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	request := httptest.NewRequest(http.MethodGet, "/me", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("expected status %d, got %d", http.StatusForbidden, response.Code)
	}
}

func TestRequireActiveUserRejectsFrozenUsers(t *testing.T) {
	tokens, err := jwt.NewService(middlewareTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	gin.SetMode(gin.TestMode)
	router := gin.New()
	group := router.Group("/me")
	group.Use(NewMiddleware(tokens).RequireUser())
	group.Use(NewMiddleware(tokens).RequireActiveUser(&fakeActiveUserChecker{err: sharederror.ErrUnauthorized}))
	group.GET("", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})
	token, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	request := httptest.NewRequest(http.MethodGet, "/me", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected status %d, got %d", http.StatusUnauthorized, response.Code)
	}
}

type fakeActiveUserChecker struct {
	err error
}

func (f *fakeActiveUserChecker) EnsureActive(context.Context, int64) error {
	return f.err
}
