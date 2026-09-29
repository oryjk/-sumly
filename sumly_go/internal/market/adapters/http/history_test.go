package markethttp

import (
	"context"
	"encoding/json"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/gin-gonic/gin"
	"net/http/httptest"
	"testing"
	"time"
)

type historyStub struct{}

func (historyStub) GetGoldHistory(context.Context) ([]domain.GoldHistoryPoint, error) {
	return []domain.GoldHistoryPoint{{Date: time.Date(1900, 7, 1, 12, 0, 0, 0, time.UTC), Price: 18.94, Granularity: "annual", Source: "usgs-ds140"}}, nil
}
func TestHistoryRoutePreservesUnitsAndAnnualMeaning(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	NewHistoryHandler(historyStub{}).RegisterPublicRoutes(r.Group("/api/v1/app"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/history", nil))
	var result struct {
		Code int
		Data struct {
			Unit   string
			Points []struct {
				Date, Granularity, Source string
				Price                     float64
			}
		}
	}
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if w.Code != 200 || result.Code != 0 || result.Data.Unit != "USD/troy_oz" || len(result.Data.Points) != 1 || result.Data.Points[0].Date != "1900-07-01" || result.Data.Points[0].Granularity != "annual" {
		t.Fatal(w.Body.String())
	}
}
