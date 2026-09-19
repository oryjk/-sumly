package markethttp

import (
	"context"
	"encoding/json"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/gin-gonic/gin"
	"net/http/httptest"
	"testing"
	"time"
)

type domesticFixture struct{}

func (domesticFixture) FetchGoldQuote(context.Context) (domain.GoldQuote, error) {
	return domain.GoldQuote{Currency: "CNY", Symbol: "AU9999", Price: 946, PrevClose: 947.09, Open: 944.5, High: 946, Low: 938.5, AsOf: time.Now()}, nil
}
func (domesticFixture) FetchGoldDailyKLines(context.Context) ([]domain.DailyBar, error) {
	return []domain.DailyBar{}, nil
}
func TestInstrumentRoutesUseNativeUnitAndRejectUnknown(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	s := application.NewInstruments([]application.InstrumentMarket{{Instrument: domain.Instrument{ID: "au9999", Symbol: "AU9999", Kind: "spot", Currency: "CNY", Unit: "CNY/g", QuoteSource: "sina"}, Service: application.NewNativeGoldMarketService(domesticFixture{}, nil)}})
	NewInstrumentsHandler(s).RegisterPublicRoutes(r.Group("/api/v1/app"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/instruments/au9999/quote", nil))
	var body struct {
		Data struct {
			Price      float64       `json:"price"`
			CNY        float64       `json:"cny_per_gram"`
			Instrument InstrumentDTO `json:"instrument"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if w.Code != 200 || body.Data.Price != 946 || body.Data.CNY != 946 || body.Data.Instrument.Unit != "CNY/g" {
		t.Fatalf("%d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/app/market/gold/instruments/unknown/quote", nil))
	if w.Code != 404 {
		t.Fatalf("unknown=%d", w.Code)
	}
}
