package authhttp

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	"github.com/gin-gonic/gin"
)

type WechatLoginUseCase interface {
	Execute(context.Context, string) (application.WechatLoginResult, error)
}

type DevLoginUseCase interface {
	Execute(context.Context, string) (application.DevLoginResult, error)
}

type Handler struct {
	wechatLogin WechatLoginUseCase
	devLogin    DevLoginUseCase
}

type WechatLoginRequest struct {
	JSCode string `json:"js_code" binding:"required"`
}

type DevLoginRequest struct {
	Identifier string `json:"identifier" binding:"required"`
}

type WechatLoginResponse struct {
	Token string       `json:"token"`
	User  UserResponse `json:"user"`
}

type UserResponse struct {
	ID          int64   `json:"id"`
	Nickname    string  `json:"nickname"`
	AvatarURL   *string `json:"avatar_url"`
	RealName    *string `json:"real_name"`
	PhoneNumber *string `json:"phone_number"`
	Status      string  `json:"status"`
}

func NewHandler(wechatLogin WechatLoginUseCase, devLogin DevLoginUseCase) *Handler {
	return &Handler{wechatLogin: wechatLogin, devLogin: devLogin}
}

func (h *Handler) WechatLogin(c *gin.Context) {
	var request WechatLoginRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "微信登录 code 不能为空"))
		return
	}
	result, err := h.wechatLogin.Execute(c.Request.Context(), request.JSCode)
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, WechatLoginResponse{
		Token: result.Token,
		User:  mapUserResponse(result.User),
	})
}

func mapUserResponse(user userdomain.User) UserResponse {
	return UserResponse{
		ID: user.ID, Nickname: user.Nickname, AvatarURL: user.AvatarURL,
		RealName: user.RealName, PhoneNumber: user.PhoneNumber, Status: string(user.Status),
	}
}

func (h *Handler) DevLogin(c *gin.Context) {
	var request DevLoginRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "开发登录标识不能为空"))
		return
	}
	result, err := h.devLogin.Execute(c.Request.Context(), request.Identifier)
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, WechatLoginResponse{
		Token: result.Token,
		User:  mapUserResponse(result.User),
	})
}

func (h *Handler) RegisterPublicRoutes(group *gin.RouterGroup) {
	group.POST("/auth/wechat/login", h.WechatLogin)
	if h.devLogin != nil {
		group.POST("/auth/dev/login", h.DevLogin)
	}
}
