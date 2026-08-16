package sharederror

import "errors"

type Kind string

const (
	KindUnauthorized Kind = "unauthorized"
	KindForbidden    Kind = "forbidden"
	KindNotFound     Kind = "not_found"
	KindConflict     Kind = "conflict"
	KindValidation   Kind = "validation"
	KindInternal     Kind = "internal"
)

var (
	ErrUnauthorized = &Error{Kind: KindUnauthorized, Message: "unauthorized"}
	ErrForbidden    = &Error{Kind: KindForbidden, Message: "forbidden"}
	ErrNotFound     = &Error{Kind: KindNotFound, Message: "not found"}
	ErrConflict     = &Error{Kind: KindConflict, Message: "conflict"}
	ErrValidation   = &Error{Kind: KindValidation, Message: "validation failed"}
	ErrInternal     = &Error{Kind: KindInternal, Message: "internal error"}
)

type Error struct {
	Kind    Kind
	Message string
	Cause   error
}

func (e *Error) Error() string {
	return e.Message
}

func (e *Error) Unwrap() error {
	return e.Cause
}

func (e *Error) Is(target error) bool {
	var other *Error
	return errors.As(target, &other) && e.Kind == other.Kind
}

func New(kind Kind, message string) error {
	return &Error{Kind: kind, Message: message}
}

func Wrap(kind Kind, message string, cause error) error {
	return &Error{Kind: kind, Message: message, Cause: cause}
}
