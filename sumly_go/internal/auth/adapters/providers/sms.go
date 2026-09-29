package providers

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
)

// SMS implements Alibaba Cloud RPC SendSms 2017-05-25 with HTTPS and signed requests.
type SMS struct {
	AccessKeyID, AccessKeySecret, SignName, TemplateCode string
	HTTP                                                 *http.Client
}

func (s SMS) Enabled() bool {
	return s.AccessKeyID != "" && s.AccessKeySecret != "" && s.SignName != "" && s.TemplateCode != ""
}
func escape(s string) string { return strings.ReplaceAll(url.QueryEscape(s), "+", "%20") }
func (s SMS) Send(ctx context.Context, phone, code, purpose string) error {
	if !s.Enabled() {
		return domain.ErrUnavailable
	}
	phone, e := domain.NormalizePhone(phone)
	if e != nil {
		return e
	}
	b := make([]byte, 24)
	if _, e = rand.Read(b); e != nil {
		return e
	}
	params, _ := json.Marshal(map[string]string{"code": code})
	form := url.Values{"AccessKeyId": {s.AccessKeyID}, "Action": {"SendSms"}, "Format": {"JSON"}, "RegionId": {"cn-hangzhou"}, "Version": {"2017-05-25"}, "SignatureMethod": {"HMAC-SHA1"}, "SignatureVersion": {"1.0"}, "SignatureNonce": {base64.RawURLEncoding.EncodeToString(b)}, "Timestamp": {time.Now().UTC().Format("2006-01-02T15:04:05Z")}, "PhoneNumbers": {strings.TrimPrefix(phone, "+86")}, "SignName": {s.SignName}, "TemplateCode": {s.TemplateCode}, "TemplateParam": {string(params)}}
	canonical := strings.ReplaceAll(form.Encode(), "+", "%20")
	mac := hmac.New(sha1.New, []byte(s.AccessKeySecret+"&"))
	mac.Write([]byte("POST&%2F&" + escape(canonical)))
	form.Set("Signature", base64.StdEncoding.EncodeToString(mac.Sum(nil)))
	req, e := http.NewRequestWithContext(ctx, "POST", "https://dysmsapi.aliyuncs.com/", strings.NewReader(form.Encode()))
	if e != nil {
		return e
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, e := boundedClient(s.HTTP).Do(req)
	if e != nil {
		return domain.ErrUnavailable
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return domain.ErrUnavailable
	}
	var out struct{ Code string }
	if e = decodeBounded(res.Body, &out); e != nil || out.Code != "OK" {
		return domain.ErrUnavailable
	}
	return nil
}
