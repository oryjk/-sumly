package sge

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestDailyTradingDateAndOHLC(t *testing.T) {
	b, e := parseDaily([]byte(`{"time":[["2026-09-18",937,947.09,935.5,948.9],["bad",1,2,1,2]]}`))
	if e != nil || len(b) != 1 || b[0].Open != 937 || b[0].Close != 947.09 || b[0].Low != 935.5 || b[0].High != 948.9 || b[0].Date.Format("2006-01-02") != "2026-09-18" {
		t.Fatalf("%+v %v", b, e)
	}
}

type transportFunc func(*http.Request) (*http.Response, error)

func (f transportFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestDailyRequestIncludesRequiredHeaders(t *testing.T) {
	client := &Client{HTTP: &http.Client{Transport: transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.Method != "POST" || r.Header.Get("User-Agent") != "Mozilla/5.0" || r.Header.Get("Content-Type") != "application/x-www-form-urlencoded" {
			t.Fatal("missing provider request headers")
		}
		body, _ := io.ReadAll(r.Body)
		if string(body) != "instid=Au99.99" {
			t.Fatal("wrong instrument")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"time":[["2026-09-18",937,947.09,935.5,948.9]]}`)), Header: make(http.Header)}, nil
	})}}
	if b, e := client.FetchGoldDailyKLines(context.Background()); e != nil || len(b) != 1 {
		t.Fatalf("%+v %v", b, e)
	}
}
