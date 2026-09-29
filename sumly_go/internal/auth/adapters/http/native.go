package authhttp

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

type NativeHandler struct {
	accounts application.Accounts
	sessions application.Sessions
}

func NewNativeHandler(a application.Accounts, s application.Sessions) *NativeHandler {
	return &NativeHandler{a, s}
}

type nativeRequest struct {
	Email         string `json:"email"`
	Password      string `json:"password"`
	NewPassword   string `json:"new_password"`
	Phone         string `json:"phone_number"`
	Code          string `json:"code"`
	Purpose       string `json:"purpose"`
	Refresh       string `json:"refresh_token"`
	Challenge     string `json:"challenge_id"`
	Identity      string `json:"identity_token"`
	Authorization string `json:"authorization_code"`
	Nickname      string `json:"nickname"`
	Confirmation  string `json:"confirmation"`
}

type appleNotificationRequest struct {
	Payload string `json:"payload"`
}

func nativeError(c *gin.Context, e error) {
	status := 503
	message := "authentication temporarily unavailable"
	switch {
	case errors.Is(e, domain.ErrInvalid):
		status = 422
		message = e.Error()
	case errors.Is(e, domain.ErrCredentials):
		status = 401
		message = e.Error()
	case errors.Is(e, domain.ErrReauthenticate):
		status = 403
		message = e.Error()
	case errors.Is(e, domain.ErrConflict):
		status = 409
		message = e.Error()
	case errors.Is(e, domain.ErrLimited):
		status = 429
		message = e.Error()
		c.Header("Retry-After", "60")
	}
	c.JSON(status, sharedhttp.Response[any]{Code: status, Message: message})
}
func (h *NativeHandler) RegisterRoutes(g *gin.RouterGroup) {
	g.GET("/auth/capabilities", func(c *gin.Context) { c.JSON(200, sharedhttp.Success(h.accounts.Capabilities())) })
	g.POST("/auth/apple/notifications", h.appleNotification)
	for _, path := range []string{"apple/challenge", "apple/login", "phone/code", "phone/login", "email/code", "email/register", "email/login", "email/reset-password", "refresh", "logout"} {
		g.POST("/auth/"+path, h.endpoint(path))
	}
	g.GET("/auth/me", h.endpoint("me"))
	g.DELETE("/auth/account", h.endpoint("account"))
}
func (h *NativeHandler) endpoint(path string) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 20*time.Second)
		defer cancel()
		var req nativeRequest
		token, hasToken := bearerToken(c.GetHeader("Authorization"))
		if (path == "me" || path == "account") && !hasToken {
			nativeError(c, domain.ErrCredentials)
			return
		}
		if c.Request.Method != "GET" {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 32768)
			d := json.NewDecoder(c.Request.Body)
			d.DisallowUnknownFields()
			if e := d.Decode(&req); e != nil {
				nativeError(c, domain.ErrInvalid)
				return
			}
			if e := d.Decode(new(any)); e != io.EOF {
				nativeError(c, domain.ErrInvalid)
				return
			}
		}
		var data any = struct{}{}
		var e error
		ip := c.ClientIP()
		switch path {
		case "apple/challenge":
			data, e = h.accounts.Challenge(ctx, ip)
		case "apple/login":
			data, e = h.accounts.AppleLogin(ctx, req.Challenge, req.Identity, req.Authorization, req.Nickname, ip)
		case "phone/code":
			e = h.accounts.Codes.Send(ctx, "phone", req.Phone, "login", ip)
			data = gin.H{"retry_after": 60, "expires_in": 300}
		case "email/code":
			e = h.accounts.Codes.Send(ctx, "email", req.Email, req.Purpose, ip)
			data = gin.H{"retry_after": 60, "expires_in": 300}
		case "phone/login":
			data, e = h.accounts.PhoneLogin(ctx, req.Phone, req.Code, ip)
		case "email/register":
			data, e = h.accounts.Register(ctx, req.Email, req.Password, req.Code, ip)
		case "email/login":
			data, e = h.accounts.EmailLogin(ctx, req.Email, req.Password, ip)
		case "email/reset-password":
			e = h.accounts.Reset(ctx, req.Email, req.NewPassword, req.Code, ip)
		case "refresh":
			if h.sessions.Store == nil {
				e = domain.ErrUnavailable
			} else {
				data, e = h.sessions.Refresh(ctx, req.Refresh)
			}
		case "logout":
			if h.sessions.Store == nil {
				e = domain.ErrUnavailable
			} else {
				e = h.sessions.Logout(ctx, req.Refresh)
			}
		case "me":
			if h.sessions.Store == nil {
				e = domain.ErrCredentials
			} else {
				data, e = h.sessions.Me(ctx, token)
			}
		case "account":
			if h.sessions.Store == nil {
				e = domain.ErrCredentials
			} else {
				e = h.sessions.Delete(ctx, token, req.Confirmation)
			}
		}
		if e != nil {
			nativeError(c, e)
			return
		}
		c.JSON(200, sharedhttp.Success(data))
	}
}

func (h *NativeHandler) appleNotification(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 20*time.Second)
	defer cancel()
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 32768)
	decoder := json.NewDecoder(c.Request.Body)
	decoder.DisallowUnknownFields()
	var req appleNotificationRequest
	if err := decoder.Decode(&req); err != nil {
		nativeError(c, domain.ErrInvalid)
		return
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		nativeError(c, domain.ErrInvalid)
		return
	}
	if req.Payload == "" || len(req.Payload) > 16384 {
		nativeError(c, domain.ErrInvalid)
		return
	}
	if err := h.accounts.HandleAppleNotification(ctx, req.Payload); err != nil {
		nativeError(c, err)
		return
	}
	c.Status(http.StatusOK)
}
