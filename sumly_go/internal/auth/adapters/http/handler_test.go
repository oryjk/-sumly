package authhttp

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	"github.com/gin-gonic/gin"
)

func TestWechatLoginHandlerReturnsTokenAndUser(t *testing.T) {
	gin.SetMode(gin.TestMode)
	realName, phoneNumber := "王小明", "13800138000"
	handler := NewHandler(&fakeWechatLogin{result: application.WechatLoginResult{
		Token: "jwt-1",
		User: userdomain.User{
			ID: 42, OpenID: "openid-1", RealName: &realName, PhoneNumber: &phoneNumber, Status: userdomain.StatusActive,
		},
	}})
	router := gin.New()
	router.POST("/login", handler.WechatLogin)
	request := httptest.NewRequest(http.MethodPost, "/login", bytes.NewBufferString(`{"js_code":"wx-code"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, response.Code, response.Body.String())
	}
	if !bytes.Contains(response.Body.Bytes(), []byte(`"token":"jwt-1"`)) {
		t.Fatalf("expected token in response: %s", response.Body.String())
	}
	if !bytes.Contains(response.Body.Bytes(), []byte(`"real_name":"王小明"`)) || !bytes.Contains(response.Body.Bytes(), []byte(`"phone_number":"13800138000"`)) {
		t.Fatalf("expected player profile in response: %s", response.Body.String())
	}
}

func TestWechatLoginHandlerRejectsEmptyBody(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := NewHandler(&fakeWechatLogin{})
	router := gin.New()
	router.POST("/login", handler.WechatLogin)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/login", nil))

	if response.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected status %d, got %d: %s", http.StatusUnprocessableEntity, response.Code, response.Body.String())
	}
}

type fakeWechatLogin struct {
	result application.WechatLoginResult
	err    error
}

func (f *fakeWechatLogin) Execute(context.Context, string) (application.WechatLoginResult, error) {
	return f.result, f.err
}
