package userhttp

import (
	"context"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/user/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	"github.com/gin-gonic/gin"
)

type AppUsers interface {
	GetMe(context.Context, sharedauth.Actor) (domain.User, error)
	UpdateMe(context.Context, sharedauth.Actor, application.UpdateMeCommand) (domain.User, error)
}

type AppHandler struct {
	users AppUsers
}

type UpdateMeRequest struct {
	Nickname *string `json:"nickname"`
	RealName *string `json:"real_name"`
}

type ProfileResponse struct {
	ID          int64   `json:"id"`
	Nickname    string  `json:"nickname"`
	AvatarURL   *string `json:"avatar_url"`
	RealName    *string `json:"real_name"`
	PhoneNumber *string `json:"phone_number"`
	Status      string  `json:"status"`
}

func NewAppHandler(users AppUsers) *AppHandler {
	return &AppHandler{users: users}
}

func (h *AppHandler) GetMe(c *gin.Context) {
	actor, ok := authhttp.ActorFromContext(c)
	if !ok {
		sharedhttpapi.WriteError(c, sharederror.ErrUnauthorized)
		return
	}
	user, err := h.users.GetMe(c.Request.Context(), actor)
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, mapProfileResponse(user))
}

func (h *AppHandler) UpdateMe(c *gin.Context) {
	actor, ok := authhttp.ActorFromContext(c)
	if !ok {
		sharedhttpapi.WriteError(c, sharederror.ErrUnauthorized)
		return
	}
	var request UpdateMeRequest
	if err := c.ShouldBindJSON(&request); err != nil || request.Nickname == nil && request.RealName == nil {
		sharedhttpapi.WriteError(c, sharederror.New(sharederror.KindValidation, "用户资料无效"))
		return
	}
	user, err := h.users.UpdateMe(c.Request.Context(), actor, application.UpdateMeCommand{
		Nickname: request.Nickname,
		RealName: request.RealName,
	})
	if err != nil {
		sharedhttpapi.WriteError(c, err)
		return
	}
	sharedhttpapi.WriteSuccess(c, mapProfileResponse(user))
}

func (h *AppHandler) RegisterAppRoutes(group *gin.RouterGroup) {
	group.GET("/users/me", h.GetMe)
	group.PATCH("/users/me", h.UpdateMe)
}

func mapProfileResponse(user domain.User) ProfileResponse {
	return ProfileResponse{
		ID: user.ID, Nickname: user.Nickname, AvatarURL: user.AvatarURL,
		RealName: user.RealName, PhoneNumber: user.PhoneNumber, Status: string(user.Status),
	}
}
