package apidocs_test

import (
	"context"
	"testing"

	apidocs "gitee.com/oryjk/sumly/sumly_go/docs"
	"github.com/getkin/kin-openapi/openapi3"
)

func TestEmbeddedOpenAPISpecIsValid(t *testing.T) {
	loader := openapi3.NewLoader()
	document, err := loader.LoadFromData(apidocs.OpenAPI)
	if err != nil {
		t.Fatalf("load embedded OpenAPI spec: %v", err)
	}
	if err := document.Validate(context.Background()); err != nil {
		t.Fatalf("validate OpenAPI spec: %v", err)
	}
	for _, path := range []string{
		"/health",
		"/api/v1/app/auth/wechat/login",
		"/api/v1/app/users/me",
	} {
		if document.Paths.Find(path) == nil {
			t.Fatalf("OpenAPI spec is missing path %s", path)
		}
	}
}
