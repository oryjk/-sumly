package domain

import (
	"strings"
	"time"
	"unicode/utf8"

	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

type Status string

const (
	StatusActive Status = "active"
	StatusFrozen Status = "frozen"
)

type User struct {
	ID          int64
	OpenID      string
	Nickname    string
	AvatarURL   *string
	RealName    *string
	PhoneNumber *string
	Status      Status
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func NewUser(openID string) (User, error) {
	openID = strings.TrimSpace(openID)
	if openID == "" {
		return User{}, sharederror.New(sharederror.KindValidation, "微信 openid 不能为空")
	}
	return User{OpenID: openID, Status: StatusActive}, nil
}

func (u User) IsActive() bool {
	return u.Status == StatusActive
}

func (u User) UpdateAppProfile(nickname, realName *string) (User, error) {
	if nickname != nil {
		value := strings.TrimSpace(*nickname)
		if utf8.RuneCountInString(value) > 120 {
			return User{}, sharederror.New(sharederror.KindValidation, "昵称不能超过 120 个字符")
		}
		u.Nickname = value
	}
	if realName != nil {
		value := strings.TrimSpace(*realName)
		if utf8.RuneCountInString(value) > 120 {
			return User{}, sharederror.New(sharederror.KindValidation, "真实姓名不能超过 120 个字符")
		}
		u.RealName = optionalString(value)
	}
	return u, nil
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}
