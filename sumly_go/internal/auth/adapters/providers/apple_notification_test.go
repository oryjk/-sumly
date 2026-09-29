package providers

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	jwt "github.com/golang-jwt/jwt/v5"
)

func TestAppleNotificationVerifiesSignatureAudienceAndEvent(t *testing.T) {
	rsaKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	signer, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	crypto, _ := credentials.New(strings.Repeat("s", 32))
	jwks, _ := json.Marshal(map[string]any{"keys": []any{map[string]string{
		"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "notify-key",
		"n": base64.RawURLEncoding.EncodeToString(rsaKey.N.Bytes()),
		"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(rsaKey.E)).Bytes()),
	}}})
	client := &http.Client{Transport: roundTrip(func(r *http.Request) (*http.Response, error) {
		if r.URL.String() != "https://appleid.apple.com/auth/keys" {
			t.Fatalf("unexpected request %s", r.URL)
		}
		return response(200, string(jwks)), nil
	})}
	apple := NewApple(AppleConfig{ClientID: "com.oryjk.sumly", TeamID: "team", KeyID: "key", PrivateKey: signer}, client, crypto)
	sign := func(aud string, events any) string {
		claims := jwt.MapClaims{
			"iss": "https://appleid.apple.com", "aud": aud,
			"iat": time.Now().Unix(), "exp": time.Now().Add(time.Minute).Unix(),
			"jti": "event-id", "events": events,
		}
		token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
		token.Header["kid"] = "notify-key"
		raw, _ := token.SignedString(rsaKey)
		return raw
	}

	eventJSON := `{"type":"consent-revoked","sub":"apple-subject","event_time":1720000000000}`
	got, err := apple.VerifyNotification(context.Background(), sign("com.oryjk.sumly", eventJSON))
	if err != nil || got.ID != "event-id" || got.Type != "consent-revoked" || got.Subject != "apple-subject" || got.EventTime != 1720000000000 || got.IssuedAt.IsZero() {
		t.Fatalf("notification = %+v, err=%v", got, err)
	}
	if _, err = apple.VerifyNotification(context.Background(), sign("other.app", eventJSON)); err == nil {
		t.Fatal("wrong audience accepted")
	}
	if _, err = apple.VerifyNotification(context.Background(), sign("com.oryjk.sumly", `{"type":"consent-revoked","sub":""}`)); err == nil {
		t.Fatal("empty subject accepted")
	}
	if _, err = apple.VerifyNotification(context.Background(), sign("com.oryjk.sumly", `{"type":"unknown","sub":"apple-subject"}`)); err != nil && err != domain.ErrInvalid {
		t.Fatalf("unknown event should parse deterministically, got %v", err)
	}
}

func TestAppleNotificationAcceptsObjectEventsClaim(t *testing.T) {
	rsaKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	jwks, _ := json.Marshal(map[string]any{"keys": []any{map[string]string{
		"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "notify-key",
		"n": base64.RawURLEncoding.EncodeToString(rsaKey.N.Bytes()),
		"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(rsaKey.E)).Bytes()),
	}}})
	apple := NewApple(AppleConfig{ClientID: "com.oryjk.sumly"}, &http.Client{Transport: roundTrip(func(*http.Request) (*http.Response, error) { return response(200, string(jwks)), nil })}, nil)
	if apple.Enabled() {
		t.Fatal("login enabled without private key")
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": "https://appleid.apple.com", "aud": "com.oryjk.sumly", "iat": time.Now().Unix(), "exp": time.Now().Add(time.Minute).Unix(), "jti": "object-event",
		"events": map[string]any{"type": "email-disabled", "sub": "apple-subject", "event_time": 1720000000001, "email": "relay@privaterelay.appleid.com", "is_private_email": "true"},
	})
	token.Header["kid"] = "notify-key"
	raw, _ := token.SignedString(rsaKey)
	got, err := apple.VerifyNotification(context.Background(), raw)
	if err != nil || got.Type != "email-disabled" || got.Subject != "apple-subject" {
		t.Fatalf("%+v %v", got, err)
	}
}

func TestAppleNotificationAcceptsSingleElementEventArray(t *testing.T) {
	rsaKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	signer, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	crypto, _ := credentials.New(strings.Repeat("s", 32))
	jwks, _ := json.Marshal(map[string]any{"keys": []any{map[string]string{
		"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "notify-key",
		"n": base64.RawURLEncoding.EncodeToString(rsaKey.N.Bytes()),
		"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(rsaKey.E)).Bytes()),
	}}})
	apple := NewApple(AppleConfig{ClientID: "com.oryjk.sumly", TeamID: "team", KeyID: "key", PrivateKey: signer}, &http.Client{Transport: roundTrip(func(*http.Request) (*http.Response, error) { return response(200, string(jwks)), nil })}, crypto)
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": "https://appleid.apple.com", "aud": "com.oryjk.sumly", "iat": time.Now().Unix(), "exp": time.Now().Add(time.Minute).Unix(), "jti": "array-event",
		"events": []any{map[string]any{"type": "account-deleted", "sub": "apple-subject", "event_time": 1720000000002}},
	})
	token.Header["kid"] = "notify-key"
	raw, _ := token.SignedString(rsaKey)
	got, err := apple.VerifyNotification(context.Background(), raw)
	if err != nil || got.Type != "account-deleted" || got.Subject != "apple-subject" {
		t.Fatalf("%+v %v", got, err)
	}

	// Historical Apple examples have represented events as JSON encoded inside a string.
	// JSON whitespace inside that encoded value must not change the accepted shape.
	token = jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": "https://appleid.apple.com", "aud": "com.oryjk.sumly", "iat": time.Now().Unix(), "exp": time.Now().Add(time.Minute).Unix(), "jti": "string-array-event",
		"events": " \n [{\"type\":\"account-deleted\",\"sub\":\"apple-subject\",\"event_time\":1720000000002}] \t",
	})
	token.Header["kid"] = "notify-key"
	raw, _ = token.SignedString(rsaKey)
	got, err = apple.VerifyNotification(context.Background(), raw)
	if err != nil || got.Type != "account-deleted" || got.Subject != "apple-subject" {
		t.Fatalf("stringified array with whitespace: %+v %v", got, err)
	}
}

func TestAppleNotificationDoesNotRequireExpirationClaim(t *testing.T) {
	rsaKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	signer, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	crypto, _ := credentials.New(strings.Repeat("s", 32))
	jwks, _ := json.Marshal(map[string]any{"keys": []any{map[string]string{
		"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "notify-key",
		"n": base64.RawURLEncoding.EncodeToString(rsaKey.N.Bytes()),
		"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(rsaKey.E)).Bytes()),
	}}})
	apple := NewApple(AppleConfig{ClientID: "com.oryjk.sumly", TeamID: "team", KeyID: "key", PrivateKey: signer}, &http.Client{Transport: roundTrip(func(*http.Request) (*http.Response, error) { return response(200, string(jwks)), nil })}, crypto)
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": "https://appleid.apple.com", "aud": "com.oryjk.sumly", "iat": time.Now().Unix(), "jti": "event-id",
		"events": map[string]any{"type": "consent-revoked", "sub": "apple-subject", "event_time": 1720000000003},
	})
	token.Header["kid"] = "notify-key"
	raw, _ := token.SignedString(rsaKey)
	got, err := apple.VerifyNotification(context.Background(), raw)
	if err != nil || got.Type != "consent-revoked" || got.Subject != "apple-subject" {
		t.Fatalf("%+v %v", got, err)
	}
}
