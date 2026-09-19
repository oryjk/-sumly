package yahoo

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

const fixture = `{"chart":{"result":[{"meta":{"symbol":"GCZ26.CMX","currency":"USD","exchangeName":"CMX","instrumentType":"FUTURE","regularMarketTime":1789765199,"regularMarketPrice":4424.9,"regularMarketDayHigh":4439.8,"regularMarketDayLow":4372.2,"previousClose":4399.7},"timestamp":[1789704000,1789765140,1789790280],"indicators":{"quote":[{"open":[4381.6,4424,null],"close":[4382,4424.9,null],"high":[4383,4425,null],"low":[4380,4423,null]}]}}],"error":null}}`

func TestContractIdentityAndNullBars(t *testing.T) {
	p, e := parseChart([]byte(fixture), "GCZ26.CMX")
	if e != nil {
		t.Fatal(e)
	}
	p.sessionOpen = 4381.6
	q, e := p.quote()
	if e != nil || q.Price != 4424.9 || q.PrevClose != 4399.7 || q.Open != 4381.6 || q.SourceDelaySeconds != 1800 {
		t.Fatalf("%+v %v", q, e)
	}
	if _, e := parseChart([]byte(fixture), "GCZ27.CMX"); e == nil {
		t.Fatal("accepted different contract")
	}
	if len(p.minutes()) != 2 {
		t.Fatal("null candle accepted")
	}
}

type transportFunc func(*http.Request) (*http.Response, error)

func (f transportFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestQuoteOpenComesFromMatchingDailySession(t *testing.T) {
	client := &Client{Symbol: "GCZ26.CMX", HTTP: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		body := fixture
		if r.URL.Query().Get("interval") == "1d" {
			var payload map[string]any
			_ = json.Unmarshal([]byte(fixture), &payload)
			result := payload["chart"].(map[string]any)["result"].([]any)[0].(map[string]any)
			result["timestamp"] = []int64{1789765140}
			result["indicators"] = map[string]any{"quote": []any{map[string]any{"open": []float64{4380.2}, "high": []float64{4440}, "low": []float64{4370}, "close": []float64{4424.9}}}}
			encoded, _ := json.Marshal(payload)
			body = string(encoded)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}, nil
	})}}
	q, e := client.FetchGoldQuote(context.Background())
	if e != nil || q.Open != 4380.2 {
		t.Fatalf("minute open mistaken for session open: %+v %v", q, e)
	}
}
