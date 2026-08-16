package sharedhttp

type Response[T any] struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    T      `json:"data"`
}

func Success[T any](data T) Response[T] {
	return Response[T]{
		Code:    0,
		Message: "ok",
		Data:    data,
	}
}
