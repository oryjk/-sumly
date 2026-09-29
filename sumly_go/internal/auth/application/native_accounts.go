package application

import (
	"context"
	"errors"
	"time"
	"unicode/utf8"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

type Accounts struct {
	Store     ports.NativeStore
	Crypto    ports.Cryptography
	Codes     Codes
	Sessions  Sessions
	Apple     ports.AppleGateway
	DummyHash string
}

func (a Accounts) Capabilities() domain.Capabilities {
	return domain.Capabilities{Apple: a.Apple != nil && a.Apple.Enabled(), Phone: a.Codes.Phone != nil && a.Codes.Phone.Enabled(), Email: a.Codes.Email != nil && a.Codes.Email.Enabled()}
}
func (a Accounts) throttle(ctx context.Context, subject, ip string) error {
	return a.Store.TakeQuota(ctx, []domain.Quota{{Key: "login:ip:" + a.Crypto.Digest("ip", ip), Limit: 60, Window: time.Hour}, {Key: "login:subject:" + a.Crypto.Digest("subject", subject), Limit: 20, Window: time.Hour}})
}
func (a Accounts) login(ctx context.Context, m ports.LoginMutation) (domain.LoginResult, error) {
	ss, r := a.Sessions.New()
	m.Session = ss
	m.OpenID = "native-" + a.Crypto.Random()
	u, e := a.Store.Login(ctx, m)
	if e != nil {
		return domain.LoginResult{}, e
	}
	return a.Sessions.Result(ctx, ss, r, u)
}
func (a Accounts) PhoneLogin(ctx context.Context, phone, code, ip string) (domain.LoginResult, error) {
	if !a.Capabilities().Phone {
		return domain.LoginResult{}, domain.ErrUnavailable
	}
	phone, e := domain.NormalizePhone(phone)
	if e != nil {
		return domain.LoginResult{}, e
	}
	if e = a.throttle(ctx, phone, ip); e != nil {
		return domain.LoginResult{}, e
	}
	key := "phone:login:" + phone
	hash, e := a.Codes.CodeHash(key, code)
	if e != nil {
		return domain.LoginResult{}, e
	}
	return a.login(ctx, ports.LoginMutation{Provider: "phone", Subject: phone, CodeKey: key, CodeHash: hash})
}
func (a Accounts) Register(ctx context.Context, email, password, code, ip string) (domain.LoginResult, error) {
	if !a.Capabilities().Email {
		return domain.LoginResult{}, domain.ErrUnavailable
	}
	email, e := domain.NormalizeEmail(email)
	if e != nil {
		return domain.LoginResult{}, e
	}
	if e = domain.ValidatePassword(password); e != nil {
		return domain.LoginResult{}, e
	}
	if e = a.throttle(ctx, email, ip); e != nil {
		return domain.LoginResult{}, e
	}
	key := "email:register:" + email
	hash, e := a.Codes.CodeHash(key, code)
	if e != nil {
		return domain.LoginResult{}, e
	}
	phc, e := a.Crypto.HashPassword(password)
	if e != nil {
		return domain.LoginResult{}, e
	}
	return a.login(ctx, ports.LoginMutation{Provider: "email", Subject: email, PasswordHash: phc, CodeKey: key, CodeHash: hash, Register: true})
}
func (a Accounts) EmailLogin(ctx context.Context, email, password, ip string) (domain.LoginResult, error) {
	if !a.Capabilities().Email {
		return domain.LoginResult{}, domain.ErrUnavailable
	}
	email, e := domain.NormalizeEmail(email)
	if e != nil || len(password) > 512 {
		return domain.LoginResult{}, domain.ErrCredentials
	}
	if e = a.throttle(ctx, email, ip); e != nil {
		return domain.LoginResult{}, e
	}
	i, e := a.Store.FindIdentity(ctx, "email", email)
	if e != nil && !errors.Is(e, domain.ErrCredentials) {
		return domain.LoginResult{}, e
	}
	hash := i.PasswordHash
	if e != nil {
		hash = a.DummyHash
	}
	valid := a.Crypto.CheckPassword(hash, password)
	if !valid || e != nil || i.User.Status != "active" {
		return domain.LoginResult{}, domain.ErrCredentials
	}
	return a.login(ctx, ports.LoginMutation{Provider: "email", Subject: email, ExpectedPassword: hash})
}
func (a Accounts) Reset(ctx context.Context, email, password, code, ip string) error {
	if !a.Capabilities().Email {
		return domain.ErrUnavailable
	}
	email, e := domain.NormalizeEmail(email)
	if e != nil {
		return e
	}
	if e = domain.ValidatePassword(password); e != nil {
		return e
	}
	if e = a.throttle(ctx, email, ip); e != nil {
		return e
	}
	hash, e := a.Codes.CodeHash("email:reset_password:"+email, code)
	if e != nil {
		return e
	}
	phc, e := a.Crypto.HashPassword(password)
	if e != nil {
		return e
	}
	return a.Store.ResetPassword(ctx, email, hash, phc)
}
func (a Accounts) Challenge(ctx context.Context, ip string) (domain.Challenge, error) {
	if !a.Capabilities().Apple {
		return domain.Challenge{}, domain.ErrUnavailable
	}
	if e := a.appleThrottle(ctx, "challenge", ip); e != nil {
		return domain.Challenge{}, e
	}
	ch := domain.Challenge{ID: a.Crypto.Random(), Nonce: a.Crypto.Random(), ExpiresIn: 300}
	e := a.Store.NewChallenge(ctx, ch.ID, a.Crypto.Digest("apple-nonce", ch.Nonce), time.Now().Add(5*time.Minute))
	return ch, e
}
func (a Accounts) AppleLogin(ctx context.Context, id, token, code, nickname, ip string) (domain.LoginResult, error) {
	if !a.Capabilities().Apple {
		return domain.LoginResult{}, domain.ErrUnavailable
	}
	if len(id) > 128 || len(token) > 16384 || len(code) > 4096 || utf8.RuneCountInString(nickname) > 120 {
		return domain.LoginResult{}, domain.ErrInvalid
	}
	if e := a.appleThrottle(ctx, "login", ip); e != nil {
		return domain.LoginResult{}, e
	}
	nonce, e := a.Store.ConsumeChallenge(ctx, id)
	if e != nil {
		return domain.LoginResult{}, e
	}
	i, e := a.Apple.Verify(ctx, token, code, nonce)
	if errors.Is(e, domain.ErrUnavailable) {
		return domain.LoginResult{}, domain.ErrUnavailable
	}
	if e != nil {
		return domain.LoginResult{}, domain.ErrCredentials
	}
	if i.Subject == "" || i.RefreshToken == "" {
		return domain.LoginResult{}, domain.ErrCredentials
	}
	encrypted, e := a.Crypto.Seal(i.RefreshToken)
	if e != nil {
		return domain.LoginResult{}, e
	}
	return a.login(ctx, ports.LoginMutation{Provider: "apple", Subject: i.Subject, Nickname: nickname, AppleRefresh: encrypted})
}

func (a Accounts) appleThrottle(ctx context.Context, operation, ip string) error {
	return a.Store.TakeQuota(ctx, []domain.Quota{{Key: "apple:" + operation + ":ip:" + a.Crypto.Digest("ip", ip), Limit: 20, Window: time.Hour}, {Key: "apple:" + operation + ":global", Limit: 1000, Window: time.Hour}})
}
