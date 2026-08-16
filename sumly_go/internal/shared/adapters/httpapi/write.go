package httpapi

import (
	"errors"
	"log/slog"
	"net/http"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

func WriteSuccess[T any](c *gin.Context, data T) {
	c.JSON(http.StatusOK, sharedhttp.Success(data))
}

func WriteError(c *gin.Context, err error) {
	status := http.StatusInternalServerError
	message := "internal error"
	var businessError *sharederror.Error
	if errors.As(err, &businessError) {
		message = businessError.Message
		switch businessError.Kind {
		case sharederror.KindUnauthorized:
			status = http.StatusUnauthorized
		case sharederror.KindForbidden:
			status = http.StatusForbidden
		case sharederror.KindNotFound:
			status = http.StatusNotFound
		case sharederror.KindConflict:
			status = http.StatusConflict
		case sharederror.KindValidation:
			status = http.StatusUnprocessableEntity
		case sharederror.KindInternal:
			message = "internal error"
		}
	}
	// 内部错误对客户端只回通用文案，但必须落日志，否则线上 500 无法定位。
	if status == http.StatusInternalServerError {
		slog.Error("internal error while handling request", "error", err, "path", c.Request.URL.Path, "method", c.Request.Method)
	}
	c.JSON(status, sharedhttp.Response[any]{Code: status, Message: message, Data: nil})
}
