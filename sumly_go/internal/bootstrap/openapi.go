package bootstrap

import (
	"net/http"

	apidocs "gitee.com/oryjk/sumly/sumly_go/docs"
	"github.com/gin-gonic/gin"
	"github.com/swaggest/swgui/v5emb"
)

const (
	openAPIBasePath = "/api/docs"
	openAPISpecPath = openAPIBasePath + "/openapi.yaml"
)

func registerOpenAPI(router *gin.Engine) {
	ui := v5emb.New("Sumly Go API", openAPISpecPath, openAPIBasePath)
	handler := http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path == openAPISpecPath {
			writer.Header().Set("Content-Type", "application/yaml; charset=utf-8")
			_, _ = writer.Write(apidocs.OpenAPI)
			return
		}
		ui.ServeHTTP(writer, request)
	})
	router.GET(openAPIBasePath+"/*path", gin.WrapH(handler))
}
