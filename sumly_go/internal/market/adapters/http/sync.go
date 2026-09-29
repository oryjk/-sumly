package markethttp

import (
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	shared "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	"github.com/gin-gonic/gin"
)

type SyncHandler struct{ store ports.HistorySyncStore }

func NewSyncHandler(store ports.HistorySyncStore) *SyncHandler { return &SyncHandler{store: store} }
func (h *SyncHandler) RegisterPublicRoutes(group *gin.RouterGroup) {
	group.GET("/market/gold/sync", func(c *gin.Context) {
		series := c.DefaultQuery("series", "xauusd")
		cursor := c.Query("cursor")
		if (series != "xauusd" && series != "au9999" && series != "comex-gold") || len(cursor) > 160 {
			c.JSON(400, gin.H{"code": 400, "message": "invalid market sync query", "data": nil})
			return
		}
		result, err := h.store.SyncHistory(c.Request.Context(), series, cursor)
		if err != nil {
			shared.WriteError(c, err)
			return
		}
		c.Header("Cache-Control", "no-store")
		shared.WriteSuccess(c, result)
	})
}
