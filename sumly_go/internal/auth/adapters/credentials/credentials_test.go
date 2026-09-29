package credentials

import (
	"strings"
	"testing"
)

func TestPasswordAndSealing(t *testing.T) {
	c, err := New(strings.Repeat("s", 32))
	if err != nil {
		t.Fatal(err)
	}
	hash, err := c.HashPassword(" password长字符123 ")
	if err != nil {
		t.Fatal(err)
	}
	if !c.CheckPassword(hash, " password长字符123 ") || c.CheckPassword(hash, "password长字符123") {
		t.Fatal("password not exact")
	}
	if c.CheckPassword("$argon2id$v=19$m=999999999,t=2,p=1$bad$bad", "password") {
		t.Fatal("unbounded PHC accepted")
	}
	encrypted, err := c.Seal("apple-refresh")
	if err != nil {
		t.Fatal(err)
	}
	plain, err := c.Open(encrypted)
	if err != nil || plain != "apple-refresh" {
		t.Fatal("roundtrip", err)
	}
	encrypted[0] ^= 1
	if _, err = c.Open(encrypted); err == nil {
		t.Fatal("tampering accepted")
	}
	if c.Digest("otp", "123456") == c.Digest("refresh", "123456") {
		t.Fatal("purposes not separated")
	}
}
