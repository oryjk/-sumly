package wechat

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestExchangeCodeAcceptsWechatErrcodeZeroResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Query().Get("js_code") != "wx-code" {
			t.Errorf("expected wx-code query")
		}
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"errcode":0,"errmsg":"ok","openid":"openid-1","session_key":"session-1"}`))
	}))
	t.Cleanup(server.Close)
	client := NewClient(server.Client(), server.URL, "app-id", "app-secret")

	identity, err := client.ExchangeCode(context.Background(), "wx-code")
	if err != nil {
		t.Fatalf("exchange code: %v", err)
	}
	if identity.OpenID != "openid-1" || identity.SessionKey != "session-1" {
		t.Fatalf("unexpected identity: %+v", identity)
	}
}

func TestExchangeCodeRejectsWechatError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"errcode":40029,"errmsg":"invalid code"}`))
	}))
	t.Cleanup(server.Close)
	client := NewClient(server.Client(), server.URL, "app-id", "app-secret")

	if _, err := client.ExchangeCode(context.Background(), "bad-code"); err == nil {
		t.Fatal("expected WeChat error")
	}
}

func TestExchangeCodeRejectsMissingOpenID(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"errcode":0,"errmsg":"ok"}`))
	}))
	t.Cleanup(server.Close)
	client := NewClient(server.Client(), server.URL, "app-id", "app-secret")

	if _, err := client.ExchangeCode(context.Background(), "wx-code"); err == nil {
		t.Fatal("expected missing openid error")
	}
}

func TestExchangeCodeRejectsHTTPErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.WriteHeader(http.StatusInternalServerError)
	}))
	t.Cleanup(server.Close)
	client := NewClient(server.Client(), server.URL, "app-id", "app-secret")

	if _, err := client.ExchangeCode(context.Background(), "wx-code"); err == nil {
		t.Fatal("expected HTTP error")
	}
}
