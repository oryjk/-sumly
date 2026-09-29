package application

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

type Codes struct {
	Store        ports.NativeStore
	Crypto       ports.Cryptography
	Phone, Email ports.CodeSender
}

func (c Codes) Send(ctx context.Context, provider, destination, purpose, ip string) error {
	var sender ports.CodeSender
	var e error
	switch provider {
	case "phone":
		destination, e = domain.NormalizePhone(destination)
		purpose = "login"
		sender = c.Phone
	case "email":
		destination, e = domain.NormalizeEmail(destination)
		sender = c.Email
		if purpose != "register" && purpose != "reset_password" {
			return domain.ErrInvalid
		}
	default:
		return domain.ErrInvalid
	}
	if e != nil {
		return e
	}
	if sender == nil || !sender.Enabled() {
		return domain.ErrUnavailable
	}
	dest := c.Crypto.Digest("quota-destination", provider+":"+destination)
	ip = c.Crypto.Digest("quota-ip", ip)
	if e = c.Store.TakeQuota(ctx, []domain.Quota{{Key: "send:cool:" + dest, Limit: 1, Window: time.Minute}, {Key: "send:hour:" + dest, Limit: 5, Window: time.Hour}, {Key: "send:day:" + dest, Limit: 20, Window: 24 * time.Hour}, {Key: "send:ip:" + ip, Limit: 30, Window: time.Hour}, {Key: "send:global", Limit: 1000, Window: time.Hour}}); e != nil {
		return e
	}
	n, e := rand.Int(rand.Reader, big.NewInt(1000000))
	if e != nil {
		return e
	}
	code := fmt.Sprintf("%06d", n.Int64())
	key := provider + ":" + purpose + ":" + destination
	hash := c.Crypto.Digest("otp", key+":"+code)
	if e = c.Store.PutCode(ctx, key, hash, time.Now().Add(5*time.Minute)); e != nil {
		return e
	}
	// Both email purposes always send the same neutral message, regardless of account existence.
	if e = sender.Send(ctx, destination, code, purpose); e != nil {
		return domain.ErrUnavailable
	}
	return c.Store.ActivateCode(ctx, key, hash)
}
func (c Codes) CodeHash(key, code string) (string, error) {
	if len(code) != 6 {
		return "", domain.ErrCredentials
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			return "", domain.ErrCredentials
		}
	}
	return c.Crypto.Digest("otp", key+":"+code), nil
}
