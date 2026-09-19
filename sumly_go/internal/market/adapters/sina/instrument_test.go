package sina

import (
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"testing"
)

func TestDomesticQuoteUsesNativeCNYAndCorrectFields(t *testing.T) {
	body := []byte(`var hq_str_gds_AU9999="946.00,0,946.00,947.69,946.00,938.50,02:30:00,947.09,944.50,2174,3.00,1.00,2026-09-19,沪金99";`)
	q, err := parseInstrumentQuote(body, "gds_AU9999", "AU9999", "CNY")
	if err != nil || q.Price != 946 || q.Open != 944.5 || q.PrevClose != 947.09 || q.CNYPerGram() != 946 {
		t.Fatalf("quote=%+v err=%v", q, err)
	}
}
func TestNativeUSDQuoteDoesNotRequireFX(t *testing.T) {
	q, err := parseInstrumentQuote([]byte(quoteFixture), "hf_XAU", "XAUUSD", "USD")
	if err != nil || q.Open != 4260.49 || q.Currency != "USD" {
		t.Fatalf("quote=%+v err=%v", q, err)
	}
	if q.CNYPerGram() != q.Price/domain.GramsPerTroyOunce*q.USDCNY {
		t.Fatal("incorrect conversion")
	}
}
func TestInstrumentQuoteRejectsInvalidPrices(t *testing.T) {
	for _, p := range []string{"NaN", "+Inf", "0", "-5"} {
		_, err := parseInstrumentQuote([]byte(`var hq_str_gds_AU9999="`+p+`,0,1,1,2,1,02:30:00,1,1,0,0,0,2026-09-19,x";`), "gds_AU9999", "AU9999", "CNY")
		if err == nil {
			t.Fatalf("accepted %s", p)
		}
	}
}
