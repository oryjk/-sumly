package authhttp

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

const actorContextKey = "authenticated_actor"

type Middleware struct {
	tokens ports.TokenService
}

type ActiveUserChecker interface {
	EnsureActive(context.Context, int64) error
}

func NewMiddleware(tokens ports.TokenService) Middleware {
	return Middleware{tokens: tokens}
}

func (m Middleware) RequireUser() gin.HandlerFunc {
	return m.require(sharedauth.ActorUser)
}

func (m Middleware) RequireAdmin() gin.HandlerFunc {
	return m.require(sharedauth.ActorAdmin)
}

func (m Middleware) RequireActiveUser(checker ActiveUserChecker) gin.HandlerFunc {
	return func(c *gin.Context) {
		actor, ok := ActorFromContext(c)
		if !ok || !actor.IsUser() {
			abort(c, http.StatusUnauthorized, "unauthorized")
			return
		}
		if err := checker.EnsureActive(c.Request.Context(), actor.ID); err != nil {
			if errors.Is(err, sharederror.ErrUnauthorized) {
				c.Abort()
				sharedhttpapi.WriteError(c, sharederror.ErrUnauthorized)
				return
			}
			c.Abort()
			sharedhttpapi.WriteError(c, sharederror.Wrap(sharederror.KindInternal, "校验用户状态失败", err))
			return
		}
		c.Next()
	}
}

func ActorFromContext(c *gin.Context) (sharedauth.Actor, bool) {
	value, exists := c.Get(actorContextKey)
	if !exists {
		return sharedauth.Actor{}, false
	}
	actor, ok := value.(sharedauth.Actor)
	return actor, ok
}

func (m Middleware) require(kind sharedauth.ActorKind) gin.HandlerFunc {
	return func(c *gin.Context) {
		token, ok := bearerToken(c.GetHeader("Authorization"))
		if !ok {
			abort(c, http.StatusUnauthorized, "unauthorized")
			return
		}
		actor, err := m.tokens.Parse(c.Request.Context(), token)
		if err != nil {
			abort(c, http.StatusUnauthorized, "unauthorized")
			return
		}
		if actor.Kind != kind {
			abort(c, http.StatusForbidden, "forbidden")
			return
		}
		c.Set(actorContextKey, actor)
		c.Next()
	}
}

func bearerToken(header string) (string, bool) {
	prefix, token, ok := strings.Cut(header, " ")
	if !ok || !strings.EqualFold(prefix, "Bearer") || strings.TrimSpace(token) == "" {
		return "", false
	}
	return strings.TrimSpace(token), true
}

func abort(c *gin.Context, status int, message string) {
	c.AbortWithStatusJSON(status, sharedhttp.Response[any]{
		Code:    status,
		Message: message,
		Data:    nil,
	})
}
