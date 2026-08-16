package auth

type ActorKind string

const (
	ActorUser  ActorKind = "user"
	ActorAdmin ActorKind = "admin"
)

type Actor struct {
	Kind         ActorKind
	ID           int64
	IsSuperAdmin bool
}

func (a Actor) IsUser() bool {
	return a.Kind == ActorUser
}

func (a Actor) IsAdmin() bool {
	return a.Kind == ActorAdmin
}
