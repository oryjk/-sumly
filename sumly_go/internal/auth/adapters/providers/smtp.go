package providers

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/mail"
	"net/smtp"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
)

type SMTP struct{ Host, Port, Username, Password, From, Mode string }

func (s SMTP) Enabled() bool {
	a, e := mail.ParseAddress(s.From)
	return e == nil && a.Address == s.From && !strings.ContainsAny(s.From, "\r\n") && s.Host != "" && s.Port != "" && s.Username != "" && s.Password != "" && (s.Mode == "tls" || s.Mode == "starttls")
}
func (s SMTP) Send(ctx context.Context, to, code, purpose string) error {
	if !s.Enabled() {
		return domain.ErrUnavailable
	}
	to, e := domain.NormalizeEmail(to)
	if e != nil {
		return e
	}
	if len(code) != 6 || strings.ContainsAny(code, "\r\n") {
		return domain.ErrInvalid
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	dial := &net.Dialer{Timeout: 10 * time.Second}
	address := net.JoinHostPort(s.Host, s.Port)
	tlsConfig := &tls.Config{ServerName: s.Host, MinVersion: tls.VersionTLS12}
	var conn net.Conn
	if s.Mode == "tls" {
		conn, e = (&tls.Dialer{NetDialer: dial, Config: tlsConfig}).DialContext(ctx, "tcp", address)
	} else {
		conn, e = dial.DialContext(ctx, "tcp", address)
	}
	if e != nil {
		return domain.ErrUnavailable
	}
	defer conn.Close()
	deadline, _ := ctx.Deadline()
	conn.SetDeadline(deadline)
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	defer stop()
	client, e := smtp.NewClient(conn, s.Host)
	if e != nil {
		return domain.ErrUnavailable
	}
	defer client.Close()
	if s.Mode == "starttls" {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return domain.ErrUnavailable
		}
		if e = client.StartTLS(tlsConfig); e != nil {
			return domain.ErrUnavailable
		}
	}
	if e = client.Auth(smtp.PlainAuth("", s.Username, s.Password, s.Host)); e != nil {
		return domain.ErrUnavailable
	}
	if e = client.Mail(s.From); e != nil {
		return domain.ErrUnavailable
	}
	if e = client.Rcpt(to); e != nil {
		return domain.ErrUnavailable
	}
	w, e := client.Data()
	if e != nil {
		return domain.ErrUnavailable
	}
	_, e = fmt.Fprintf(w, "From: %s\r\nTo: %s\r\nSubject: Sumly verification code\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nYour Sumly verification code is %s. It expires in 5 minutes. If you did not request this, ignore this email.\r\n", s.From, to, code)
	if e != nil {
		return domain.ErrUnavailable
	}
	if e = w.Close(); e != nil {
		return domain.ErrUnavailable
	}
	if e = client.Quit(); e != nil {
		return domain.ErrUnavailable
	}
	return nil
}
