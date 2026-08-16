package bootstrap

import (
	"net/http"

	sharedhttp "gitee.com/oryjk/sumly/sumly_go/internal/shared/http"
	"github.com/gin-gonic/gin"
)

func NewRouter(dependencies Dependencies) *gin.Engine {
	router := gin.New()
	router.Use(gin.Logger(), gin.Recovery())
	router.Use(localDevelopmentCORS())
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, sharedhttp.Success(gin.H{"status": "ok"}))
	})
	registerOpenAPI(router)

	v1 := router.Group("/api/v1")
	app := v1.Group("/app")
	if dependencies.UserAuth != nil {
		dependencies.UserAuth.RegisterPublicRoutes(app)
	}
	if dependencies.AuthMiddleware != nil {
		userRoutes := app.Group("")
		userRoutes.Use(dependencies.AuthMiddleware.RequireUser())
		if dependencies.ActiveUsers != nil {
			userRoutes.Use(dependencies.AuthMiddleware.RequireActiveUser(dependencies.ActiveUsers))
		}
		if dependencies.AppUsers != nil {
			dependencies.AppUsers.RegisterAppRoutes(userRoutes)
		}
	}
	return router
}
