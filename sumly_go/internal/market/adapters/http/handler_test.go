package markethttp

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/gin-gonic/gin"
)

type marketStub struct{}

func (marketStub) GetGoldRealtime(context.Context) ([]domain.RealtimePoint, int, error) {
	return nil, 5, nil
}

func (marketStub) GetGoldQuote(context.Context) (domain.GoldQuote, error) {
	return domain.GoldQuote{}, nil
}
func (marketStub) GetGoldDailyKLines(context.Context) ([]domain.DailyBar, error) { return nil, nil }
func (marketStub) GetGoldIntraday(context.Context) ([]domain.IntradayPoint, error) {
	return []domain.IntradayPoint{{Time: time.Date(2026, 9, 18, 6, 0, 0, 0, time.FixedZone("CST", 8*3600)), Price: 4343.97}}, nil
}
func TestIntradayPublicRouteEnvelope(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	NewHandler(marketStub{}).RegisterPublicRoutes(router.Group("/api/v1/app"))
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest("GET", "/api/v1/app/market/gold/intraday", nil))
	if response.Code != 200 {
		t.Fatalf("status=%d body=%s", response.Code, response.Body)
	}
	var payload struct {
		Code int `json:"code"`
		Data struct {
			Symbol string `json:"symbol"`
			Points []struct {
				Time  string  `json:"time"`
				Price float64 `json:"price"`
			} `json:"points"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Code != 0 || payload.Data.Symbol != "XAUUSD" || len(payload.Data.Points) != 1 {
		t.Fatalf("bad response: %s", response.Body)
	}
	if payload.Data.Points[0].Time != "2026-09-18T06:00:00+08:00" || payload.Data.Points[0].Price != 4343.97 {
		t.Fatalf("wrong units/timestamp: %s", response.Body)
	}
}

func TestRealtimeColdStartReturnsEmptyArrayAndExplicitUnits(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	NewHandler(marketStub{}).RegisterPublicRoutes(router.Group("/api/v1/app"))
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest("GET", "/api/v1/app/market/gold/realtime", nil))
	var body struct {
		Data struct {
			Unit     string `json:"unit"`
			Interval int    `json:"interval_seconds"`
			Window   int    `json:"window_seconds"`
			Points   []any  `json:"points"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if response.Code != 200 || body.Data.Unit != "CNY/g" || body.Data.Interval != 5 || body.Data.Window != 1200 || body.Data.Points == nil || len(body.Data.Points) != 0 {
		t.Fatalf("response: %s", response.Body)
	}
}
