package credentials

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"golang.org/x/crypto/argon2"
)

type Credentials struct {
	key  []byte
	aead cipher.AEAD
}

func New(secret string) (*Credentials, error) {
	if len(secret) < 32 {
		return nil, domain.ErrUnavailable
	}
	c := &Credentials{key: []byte(secret)}
	key := c.mac("apple-encryption", "")
	b, e := aes.NewCipher(key)
	if e != nil {
		return nil, e
	}
	c.aead, e = cipher.NewGCM(b)
	return c, e
}
func (c *Credentials) mac(p, s string) []byte {
	h := hmac.New(sha256.New, c.key)
	h.Write([]byte(p + "\x00" + s))
	return h.Sum(nil)
}
func (c *Credentials) Digest(p, s string) string {
	return base64.RawURLEncoding.EncodeToString(c.mac(p, s))
}
func (c *Credentials) Random() string {
	b := make([]byte, 32)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}
func (c *Credentials) Seal(s string) ([]byte, error) {
	n := make([]byte, c.aead.NonceSize())
	if _, e := rand.Read(n); e != nil {
		return nil, e
	}
	return c.aead.Seal(n, n, []byte(s), []byte("apple-refresh-v1")), nil
}
func (c *Credentials) Open(b []byte) (string, error) {
	n := c.aead.NonceSize()
	if len(b) < n {
		return "", domain.ErrCredentials
	}
	p, e := c.aead.Open(nil, b[:n], b[n:], []byte("apple-refresh-v1"))
	return string(p), e
}
func (c *Credentials) HashPassword(s string) (string, error) {
	if e := domain.ValidatePassword(s); e != nil {
		return "", e
	}
	salt := make([]byte, 16)
	if _, e := rand.Read(salt); e != nil {
		return "", e
	}
	hash := argon2.IDKey([]byte(s), salt, 2, 19456, 1, 32)
	return fmt.Sprintf("$argon2id$v=19$m=19456,t=2,p=1$%s$%s", base64.RawStdEncoding.EncodeToString(salt), base64.RawStdEncoding.EncodeToString(hash)), nil
}
func (c *Credentials) CheckPassword(phc, s string) bool {
	if len(s) > 512 || len(phc) > 200 {
		return false
	}
	p := strings.Split(phc, "$")
	if len(p) != 6 || p[1] != "argon2id" || p[2] != "v=19" || p[3] != "m=19456,t=2,p=1" {
		return false
	}
	salt, e := base64.RawStdEncoding.DecodeString(p[4])
	if e != nil || len(salt) != 16 {
		return false
	}
	expected, e := base64.RawStdEncoding.DecodeString(p[5])
	if e != nil || len(expected) != 32 {
		return false
	}
	actual := argon2.IDKey([]byte(s), salt, 2, 19456, 1, 32)
	return subtle.ConstantTimeCompare(actual, expected) == 1
}
