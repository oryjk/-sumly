package markethttp

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	sharedhttpapi "gitee.com/oryjk/sumly/sumly_go/internal/shared/adapters/httpapi"
	"github.com/gin-gonic/gin"
)

type GoldHistoryUseCase interface {
	GetGoldHistory(context.Context) ([]domain.GoldHistoryPoint, error)
}
type HistoryHandler struct{ history GoldHistoryUseCase }

func NewHistoryHandler(history GoldHistoryUseCase) *HistoryHandler {
	return &HistoryHandler{history: history}
}
func (h *HistoryHandler) RegisterPublicRoutes(group *gin.RouterGroup) {
	group.GET("/market/gold/history", func(c *gin.Context) {
		points, err := h.history.GetGoldHistory(c.Request.Context())
		if err != nil {
			sharedhttpapi.WriteError(c, err)
			return
		}
		type point struct {
			Date        string  `json:"date"`
			Price       float64 `json:"price"`
			Granularity string  `json:"granularity"`
			Source      string  `json:"source"`
		}
		result := struct {
			Unit   string  `json:"unit"`
			Points []point `json:"points"`
		}{Unit: "USD/troy_oz", Points: make([]point, 0, len(points))}
		for _, p := range points {
			result.Points = append(result.Points, point{p.Date.Format("2006-01-02"), p.Price, p.Granularity, p.Source})
		}
		sharedhttpapi.WriteSuccess(c, result)
	})
}
