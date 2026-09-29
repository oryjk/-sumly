package providers

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"io"
	"math/big"
	"net/http"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	jwt "github.com/golang-jwt/jwt/v5"
)

type roundTrip func(*http.Request) (*http.Response, error)

func (f roundTrip) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func response(status int, s string) *http.Response {
	return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(s)), Header: make(http.Header)}
}
func TestAppleVerifiesBothTokensAndNonce(t *testing.T) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	signer, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	crypto, _ := credentials.New(strings.Repeat("s", 32))
	sign := func(changes jwt.MapClaims) string {
		claims := jwt.MapClaims{"iss": "https://appleid.apple.com", "aud": "app.id", "sub": "subject", "nonce": "nonce", "iat": time.Now().Unix(), "exp": time.Now().Add(time.Minute).Unix()}
		for k, v := range changes {
			claims[k] = v
		}
		tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
		tok.Header["kid"] = "key"
		v, _ := tok.SignedString(key)
		return v
	}
	jwks, _ := json.Marshal(map[string]any{"keys": []any{map[string]string{"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "key", "n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()), "e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes())}}})
	exchanged := sign(nil)
	calls := 0
	client := &http.Client{Transport: roundTrip(func(r *http.Request) (*http.Response, error) {
		if r.URL.Scheme != "https" {
			t.Fatal("insecure request")
		}
		if r.URL.Path == "/auth/keys" {
			return response(200, string(jwks)), nil
		}
		calls++
		if e := r.ParseForm(); e != nil || r.Form.Get("code") != "auth-code" || r.Form.Get("client_secret") == "" {
			t.Fatal("bad exchange")
		}
		v, _ := json.Marshal(map[string]string{"id_token": exchanged, "refresh_token": "apple-refresh"})
		return response(200, string(v)), nil
	})}
	a := NewApple(AppleConfig{ClientID: "app.id", TeamID: "team", KeyID: "key", PrivateKey: signer}, client, crypto)
	got, e := a.Verify(context.Background(), sign(nil), "auth-code", crypto.Digest("apple-nonce", "nonce"))
	if e != nil || got.Subject != "subject" || got.RefreshToken != "apple-refresh" {
		t.Fatal(got, e)
	}
	for _, bad := range []jwt.MapClaims{{"iss": "evil"}, {"aud": "other"}, {"nonce": "wrong"}, {"exp": time.Now().Add(-time.Minute).Unix()}, {"iat": time.Now().Add(time.Hour).Unix()}, {"sub": ""}} {
		before := calls
		if _, e = a.Verify(context.Background(), sign(bad), "auth-code", crypto.Digest("apple-nonce", "nonce")); e == nil || calls != before {
			t.Fatal("invalid token reached exchange", bad, e)
		}
	}
	exchanged = sign(jwt.MapClaims{"sub": "other"})
	if _, e = a.Verify(context.Background(), sign(nil), "auth-code", crypto.Digest("apple-nonce", "nonce")); e == nil {
		t.Fatal("different exchange subject accepted")
	}
	raw := sign(nil)
	raw = raw[:len(raw)-10] + "AAAAAAAAAA"
	if _, e = a.Verify(context.Background(), raw, "auth-code", crypto.Digest("apple-nonce", "nonce")); e == nil {
		t.Fatal("invalid signature accepted")
	}
}
func TestProviderMissingConfiguration(t *testing.T) {
	if NewApple(AppleConfig{}, nil, nil).Enabled() {
		t.Fatal("apple enabled")
	}
	if (SMS{}).Enabled() {
		t.Fatal("SMS enabled")
	}
	if (SMTP{}).Enabled() {
		t.Fatal("SMTP enabled")
	}
}

func TestSMSFailClosedAndSigned(t *testing.T) {
	for _, tc := range []struct {
		status int
		body   string
		ok     bool
	}{{200, `{"Code":"OK"}`, true}, {200, `{"Code":"isv.BUSINESS_LIMIT_CONTROL"}`, false}, {500, `{}`, false}, {200, strings.Repeat("x", 65537), false}} {
		s := SMS{AccessKeyID: "id", AccessKeySecret: "secret", SignName: "Sumly", TemplateCode: "SMS_1", HTTP: &http.Client{Transport: roundTrip(func(r *http.Request) (*http.Response, error) {
			if r.URL.String() != "https://dysmsapi.aliyuncs.com/" {
				t.Fatal("endpoint")
			}
			_ = r.ParseForm()
			if r.Form.Get("PhoneNumbers") != "13800138000" || r.Form.Get("Signature") == "" || r.Form.Get("TemplateParam") != `{"code":"123456"}` {
				t.Fatal("SMS request")
			}
			return response(tc.status, tc.body), nil
		})}}
		if e := s.Send(context.Background(), "+8613800138000", "123456", "login"); (e == nil) != tc.ok {
			t.Fatal("unexpected SMS result", e)
		}
	}
}
