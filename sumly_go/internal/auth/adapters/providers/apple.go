package providers

import (
	"context"
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	jwt "github.com/golang-jwt/jwt/v5"
)

const appleIssuer = "https://appleid.apple.com"

type AppleConfig struct {
	ClientID, TeamID, KeyID string
	PrivateKey              *ecdsa.PrivateKey
}
type Apple struct {
	config             AppleConfig
	http               *http.Client
	crypto             ports.Cryptography
	mu                 sync.Mutex
	keys               map[string]*rsa.PublicKey
	fetched, attempted time.Time
}

func boundedClient(c *http.Client) *http.Client {
	if c == nil {
		c = &http.Client{}
	}
	copy := *c
	copy.Timeout = 10 * time.Second
	copy.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	return &copy
}
func NewApple(c AppleConfig, h *http.Client, crypto ports.Cryptography) *Apple {
	return &Apple{config: c, http: boundedClient(h), crypto: crypto}
}
func (a *Apple) Enabled() bool {
	return a != nil && a.config.ClientID != "" && a.config.TeamID != "" && a.config.KeyID != "" && a.config.PrivateKey != nil && a.config.PrivateKey.Curve.Params().Name == "P-256" && a.crypto != nil
}
func (a *Apple) key(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if k := a.keys[kid]; k != nil && time.Since(a.fetched) < time.Hour {
		return k, nil
	}
	if time.Since(a.attempted) < time.Minute {
		return nil, domain.ErrCredentials
	}
	a.attempted = time.Now()
	req, e := http.NewRequestWithContext(ctx, http.MethodGet, appleIssuer+"/auth/keys", nil)
	if e != nil {
		return nil, e
	}
	res, e := a.http.Do(req)
	if e != nil {
		return nil, domain.ErrUnavailable
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return nil, domain.ErrUnavailable
	}
	var document struct {
		Keys []struct{ Kty, Alg, Use, Kid, N, E string }
	}
	if e = decodeBounded(res.Body, &document); e != nil {
		return nil, e
	}
	if len(document.Keys) > 20 {
		return nil, domain.ErrCredentials
	}
	keys := map[string]*rsa.PublicKey{}
	for _, j := range document.Keys {
		if j.Kty != "RSA" || j.Alg != "RS256" || j.Use != "sig" || len(j.Kid) > 128 {
			continue
		}
		n, e := base64.RawURLEncoding.DecodeString(j.N)
		if e != nil || len(n) < 256 || len(n) > 512 {
			continue
		}
		ex, e := base64.RawURLEncoding.DecodeString(j.E)
		if e != nil || len(ex) > 4 || len(ex) == 0 {
			continue
		}
		v := new(big.Int).SetBytes(ex).Int64()
		if v < 3 || v > 2147483647 || v%2 == 0 {
			continue
		}
		keys[j.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(v)}
	}
	a.keys = keys
	a.fetched = time.Now()
	if keys[kid] == nil {
		return nil, domain.ErrCredentials
	}
	return keys[kid], nil
}

type appleClaims struct {
	Nonce string `json:"nonce"`
	jwt.RegisteredClaims
}

func (a *Apple) verifyToken(ctx context.Context, raw, nonceHash string) (*appleClaims, error) {
	if len(raw) == 0 || len(raw) > 16384 {
		return nil, domain.ErrCredentials
	}
	c := &appleClaims{}
	t, e := jwt.ParseWithClaims(raw, c, func(t *jwt.Token) (any, error) {
		kid, ok := t.Header["kid"].(string)
		if !ok || len(kid) > 128 {
			return nil, domain.ErrCredentials
		}
		return a.key(ctx, kid)
	}, jwt.WithValidMethods([]string{"RS256"}), jwt.WithIssuer(appleIssuer), jwt.WithAudience(a.config.ClientID), jwt.WithExpirationRequired(), jwt.WithIssuedAt())
	if e != nil || !t.Valid || c.IssuedAt == nil || c.Subject == "" || len(c.Subject) > 255 || len(c.Audience) != 1 || c.Nonce == "" || subtle.ConstantTimeCompare([]byte(a.crypto.Digest("apple-nonce", c.Nonce)), []byte(nonceHash)) != 1 {
		return nil, domain.ErrCredentials
	}
	return c, nil
}
func (a *Apple) clientSecret() (string, error) {
	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.RegisteredClaims{Issuer: a.config.TeamID, Subject: a.config.ClientID, Audience: jwt.ClaimStrings{appleIssuer}, IssuedAt: jwt.NewNumericDate(now), ExpiresAt: jwt.NewNumericDate(now.Add(5 * time.Minute))})
	token.Header["kid"] = a.config.KeyID
	return token.SignedString(a.config.PrivateKey)
}
func decodeBounded(r io.Reader, v any) error {
	b, e := io.ReadAll(io.LimitReader(r, 65537))
	if e != nil || len(b) > 65536 {
		return domain.ErrUnavailable
	}
	if e = json.Unmarshal(b, v); e != nil {
		return domain.ErrUnavailable
	}
	return nil
}
func (a *Apple) post(ctx context.Context, path string, form url.Values) (*http.Response, error) {
	secret, e := a.clientSecret()
	if e != nil {
		return nil, e
	}
	form.Set("client_id", a.config.ClientID)
	form.Set("client_secret", secret)
	req, e := http.NewRequestWithContext(ctx, "POST", appleIssuer+path, strings.NewReader(form.Encode()))
	if e != nil {
		return nil, e
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, e := a.http.Do(req)
	if e != nil {
		return nil, domain.ErrUnavailable
	}
	if res.StatusCode != 200 {
		res.Body.Close()
		return nil, domain.ErrUnavailable
	}
	return res, nil
}
func (a *Apple) Verify(ctx context.Context, raw, code, nonceHash string) (ports.AppleIdentity, error) {
	if !a.Enabled() {
		return ports.AppleIdentity{}, domain.ErrUnavailable
	}
	if code == "" || len(code) > 4096 {
		return ports.AppleIdentity{}, domain.ErrCredentials
	}
	first, e := a.verifyToken(ctx, raw, nonceHash)
	if e != nil {
		return ports.AppleIdentity{}, e
	}
	res, e := a.post(ctx, "/auth/token", url.Values{"grant_type": {"authorization_code"}, "code": {code}})
	if e != nil {
		return ports.AppleIdentity{}, e
	}
	defer res.Body.Close()
	var tokens struct {
		Identity string `json:"id_token"`
		Refresh  string `json:"refresh_token"`
	}
	if e = decodeBounded(res.Body, &tokens); e != nil {
		return ports.AppleIdentity{}, e
	}
	second, e := a.verifyToken(ctx, tokens.Identity, nonceHash)
	if e != nil || second.Subject != first.Subject || tokens.Refresh == "" || len(tokens.Refresh) > 8192 {
		return ports.AppleIdentity{}, domain.ErrCredentials
	}
	return ports.AppleIdentity{Subject: first.Subject, RefreshToken: tokens.Refresh}, nil
}
func (a *Apple) Revoke(ctx context.Context, token string) error {
	if !a.Enabled() || token == "" {
		return domain.ErrUnavailable
	}
	res, e := a.post(ctx, "/auth/revoke", url.Values{"token": {token}, "token_type_hint": {"refresh_token"}})
	if e != nil {
		return e
	}
	defer res.Body.Close()
	_, e = io.Copy(io.Discard, io.LimitReader(res.Body, 65536))
	return e
}
