package sina

import (
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

const quoteFixture = "var hq_str_hf_XAU=\"4288.66,4263.940,4288.66,4289.01,4318.02,4257.40,13:19:00,4263.94,4260.49,0,0,0,2026-09-17,伦敦金（现货黄金）\";\n" +
	"var hq_str_fx_susdcny=\"13:19:14,6.7079000000,6.7089000000,6.7121000000,148.0000000000,6.7078000000,6.7118000000,6.6970000000,6.7084000000,在岸人民币,-0.0551,-0.0037,0.0148,此行情由新浪财经计算得出,0.0000,0.0000,,2026-09-17\";"

func TestParseQuoteBody(t *testing.T) {
	quote, err := parseQuoteBody([]byte(quoteFixture))
	if err != nil {
		t.Fatalf("parseQuoteBody() error = %v", err)
	}
	if quote.Price != 4288.66 {
		t.Errorf("Price = %v, want 4288.66", quote.Price)
	}
	if quote.PrevClose != 4263.94 {
		t.Errorf("PrevClose = %v, want 4263.94", quote.PrevClose)
	}
	if quote.Open != 4260.49 || quote.High != 4318.02 || quote.Low != 4257.40 {
		t.Errorf("OHLC = (%v,%v,%v), want (4260.49,4318.02,4257.40)", quote.Open, quote.High, quote.Low)
	}
	want := time.Date(2026, 9, 17, 13, 19, 0, 0, beijingZone)
	if !quote.AsOf.Equal(want) {
		t.Errorf("AsOf = %v, want %v", quote.AsOf, want)
	}
	if quote.Symbol != "XAUUSD" {
		t.Errorf("Symbol = %q, want XAUUSD", quote.Symbol)
	}
}

func TestParseQuoteBodyUSDCNY(t *testing.T) {
	quote, err := parseQuoteBody([]byte(quoteFixture))
	if err != nil {
		t.Fatalf("parseQuoteBody() error = %v", err)
	}
	// 买/卖中间价 (6.7079 + 6.7089) / 2
	if quote.USDCNY != 6.7084 {
		t.Errorf("USDCNY = %v, want 6.7084", quote.USDCNY)
	}
	wantPerGram := 4288.66 / domain.GramsPerTroyOunce * 6.7084
	if got := quote.CNYPerGram(); got < wantPerGram-1e-6 || got > wantPerGram+1e-6 {
		t.Errorf("CNYPerGram() = %v, want ~%v", got, wantPerGram)
	}
}

func TestParseQuoteBodyWithoutRateStillParsesGold(t *testing.T) {
	goldOnly := "var hq_str_hf_XAU=\"4288.66,4263.940,4288.66,4289.01,4318.02,4257.40,13:19:00,4263.94,4260.49,0,0,0,2026-09-17,x\";"
	quote, err := parseQuoteBody([]byte(goldOnly))
	if err != nil {
		t.Fatalf("parseQuoteBody() error = %v", err)
	}
	if quote.USDCNY != 0 {
		t.Errorf("USDCNY = %v, want 0 when rate line missing", quote.USDCNY)
	}
	if quote.CNYPerGram() != 0 {
		t.Errorf("CNYPerGram() = %v, want 0 when rate unavailable", quote.CNYPerGram())
	}
}

func TestQuoteChangeComputed(t *testing.T) {
	quote, err := parseQuoteBody([]byte(quoteFixture))
	if err != nil {
		t.Fatalf("parseQuoteBody() error = %v", err)
	}
	if got := quote.Change(); got < 24.71 || got > 24.73 {
		t.Errorf("Change() = %v, want ~24.72", got)
	}
}

func TestParseQuoteBodyRejectsGarbage(t *testing.T) {
	if _, err := parseQuoteBody([]byte(`var hq_str_hf_XAU="";`)); err == nil {
		t.Error("empty fields: want error")
	}
	if _, err := parseQuoteBody([]byte(`var x=1;`)); err == nil {
		t.Error("no quoted payload: want error")
	}
}

const dailyFixture = `/*<script>location.href='//sina.com';</script>*/
var t=([{"date":"2026-09-16","open":"3860.800","high":"3882.400","low":"3855.100","close":"3875.250","volume":"0","position":"0","s":"0.000"},
{"date":"bad-date","open":"1","high":"1","low":"1","close":"1"},
{"date":"2026-09-15","open":"3850.100","high":"3871.200","low":"3841.500","close":"3860.800","volume":"0","position":"0","s":"0.000"}]);`

func TestParseDailyBodySkipsBadRowsAndSorts(t *testing.T) {
	bars, err := parseDailyBody([]byte(dailyFixture))
	if err != nil {
		t.Fatalf("parseDailyBody() error = %v", err)
	}
	if len(bars) != 2 {
		t.Fatalf("len(bars) = %d, want 2", len(bars))
	}
	if bars[0].Date.Format("2006-01-02") != "2026-09-15" || bars[1].Date.Format("2006-01-02") != "2026-09-16" {
		t.Errorf("dates = %v, %v; want ascending 09-15, 09-16", bars[0].Date, bars[1].Date)
	}
	if bars[1].Close != 3875.25 {
		t.Errorf("bars[1].Close = %v, want 3875.25", bars[1].Close)
	}
}

func TestParseDailyBodyRejectsGarbage(t *testing.T) {
	if _, err := parseDailyBody([]byte(`var t=(null);`)); err == nil {
		t.Error("no array: want error")
	}
	if _, err := parseDailyBody([]byte(`var t=([{"date":"nope"}]);`)); err == nil {
		t.Error("all rows invalid: want error")
	}
}
