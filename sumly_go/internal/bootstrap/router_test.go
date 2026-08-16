package bootstrap

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	authapplication "gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	userhttp "gitee.com/oryjk/sumly/sumly_go/internal/user/adapters/http"
	userapplication "gitee.com/oryjk/sumly/sumly_go/internal/user/application"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	"github.com/gin-gonic/gin"
)

const routerTestSecret = "01234567890123456789012345678901"

func TestHealthRoute(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{})
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}
	const expected = `{"code":0,"message":"ok","data":{"status":"ok"}}`
	if response.Body.String() != expected {
		t.Fatalf("expected body %s, got %s", expected, response.Body.String())
	}
}

func TestWechatLoginRouteIsPublicAndVersioned(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{UserAuth: authhttp.NewHandler(routerWechatLogin{}, nil)})

	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/wechat/login", nil))
	if unauthorized.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected validation status %d, got %d", http.StatusUnprocessableEntity, unauthorized.Code)
	}

	unversioned := httptest.NewRecorder()
	router.ServeHTTP(unversioned, httptest.NewRequest(http.MethodPost, "/api/app/auth/wechat/login", nil))
	if unversioned.Code != http.StatusNotFound {
		t.Fatalf("unversioned route status=%d", unversioned.Code)
	}
}

func TestAppUserRoutesAreProtected(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tokens, err := jwt.NewService(routerTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	middleware := authhttp.NewMiddleware(tokens)
	router := NewRouter(Dependencies{
		AuthMiddleware: &middleware,
		AppUsers:       userhttp.NewAppHandler(routerAppUsers{}),
	})

	unauthorized := httptest.NewRecorder()
	router.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/app/users/me", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status=%d body=%s", unauthorized.Code, unauthorized.Body.String())
	}

	token, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	request := httptest.NewRequest(http.MethodGet, "/api/v1/app/users/me", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("authorized status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestAppUserRoutesRejectFrozenUsers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tokens, err := jwt.NewService(routerTestSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	middleware := authhttp.NewMiddleware(tokens)
	router := NewRouter(Dependencies{
		AuthMiddleware: &middleware,
		ActiveUsers:    routerActiveUsers{err: sharederror.ErrUnauthorized},
		AppUsers:       userhttp.NewAppHandler(routerAppUsers{}),
	})
	token, err := tokens.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v1/app/users/me", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("frozen user status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestLocalH5PreflightIsAllowed(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{})
	request := httptest.NewRequest(http.MethodOptions, "/api/v1/app/auth/wechat/login", nil)
	request.Header.Set("Origin", "http://localhost:5173")
	request.Header.Set("Access-Control-Request-Method", http.MethodPost)
	request.Header.Set("Access-Control-Request-Headers", "authorization,content-type")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("expected preflight status %d, got %d", http.StatusNoContent, response.Code)
	}
	if response.Header().Get("Access-Control-Allow-Origin") != "http://localhost:5173" {
		t.Fatalf("unexpected allow origin %q", response.Header().Get("Access-Control-Allow-Origin"))
	}
}

func TestSwaggerRoutesServeEmbeddedOpenAPI(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Dependencies{})

	redirect := httptest.NewRecorder()
	router.ServeHTTP(redirect, httptest.NewRequest(http.MethodGet, "/api/docs", nil))
	if redirect.Code < 300 || redirect.Code >= 400 || redirect.Header().Get("Location") != "/api/docs/" {
		t.Fatalf("docs redirect status=%d location=%q", redirect.Code, redirect.Header().Get("Location"))
	}

	for _, test := range []struct {
		path        string
		contentType string
		contains    string
	}{
		{path: "/api/docs/", contentType: "text/html", contains: "Swagger UI"},
		{path: "/api/docs/openapi.yaml", contentType: "application/yaml", contains: "openapi: 3.0.3"},
		{path: "/api/docs/swagger-ui.css", contentType: "text/css"},
	} {
		response := httptest.NewRecorder()
		router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, test.path, nil))
		if response.Code != http.StatusOK || !strings.Contains(response.Header().Get("Content-Type"), test.contentType) {
			t.Fatalf("GET %s status=%d content-type=%q", test.path, response.Code, response.Header().Get("Content-Type"))
		}
		if test.contains != "" && !strings.Contains(response.Body.String(), test.contains) {
			t.Fatalf("GET %s body does not contain %q", test.path, test.contains)
		}
	}
}

type routerWechatLogin struct{}

func (routerWechatLogin) Execute(context.Context, string) (authapplication.WechatLoginResult, error) {
	return authapplication.WechatLoginResult{}, nil
}

type routerAppUsers struct{}

func (routerAppUsers) GetMe(context.Context, sharedauth.Actor) (userdomain.User, error) {
	return userdomain.User{}, nil
}

func (routerAppUsers) UpdateMe(context.Context, sharedauth.Actor, userapplication.UpdateMeCommand) (userdomain.User, error) {
	return userdomain.User{}, nil
}

type routerActiveUsers struct {
	err error
}

func (r routerActiveUsers) EnsureActive(context.Context, int64) error {
	return r.err
}

func TestDevLoginRouteRegisteredOnlyWhenEnabled(t *testing.T) {
	gin.SetMode(gin.TestMode)
	enabled := NewRouter(Dependencies{UserAuth: authhttp.NewHandler(routerWechatLogin{}, routerDevLogin{})})
	enabledResp := httptest.NewRecorder()
	enabled.ServeHTTP(enabledResp, httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/dev/login", nil))
	if enabledResp.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected dev login route to exist with validation status %d, got %d", http.StatusUnprocessableEntity, enabledResp.Code)
	}

	disabled := NewRouter(Dependencies{UserAuth: authhttp.NewHandler(routerWechatLogin{}, nil)})
	disabledResp := httptest.NewRecorder()
	disabled.ServeHTTP(disabledResp, httptest.NewRequest(http.MethodPost, "/api/v1/app/auth/dev/login", nil))
	if disabledResp.Code != http.StatusNotFound {
		t.Fatalf("expected dev login route to be absent (404), got %d", disabledResp.Code)
	}
}

type routerDevLogin struct{}

func (routerDevLogin) Execute(context.Context, string) (authapplication.DevLoginResult, error) {
	return authapplication.DevLoginResult{}, nil
}
