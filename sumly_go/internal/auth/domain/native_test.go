package domain

import (
	"strings"
	"testing"
)

func TestNormalizationAndPasswordPolicy(t *testing.T) {
	for _, s := range []string{"13800138000", "+8613800138000", " 13800138000 "} {
		v, e := NormalizePhone(s)
		if e != nil || v != "+8613800138000" {
			t.Fatalf("phone %q: %q %v", s, v, e)
		}
	}
	for _, s := range []string{"+12125551234", "12800138000", "138001380000"} {
		if _, e := NormalizePhone(s); e == nil {
			t.Fatalf("accepted %q", s)
		}
	}
	if v, e := NormalizeEmail(" A.B+tag@EXAMPLE.COM "); e != nil || v != "a.b+tag@example.com" {
		t.Fatal(v, e)
	}
	for _, s := range []string{"x", "x@y\r\nBcc:x@y.com", "Name <x@y.com>"} {
		if _, e := NormalizeEmail(s); e == nil {
			t.Fatal("invalid email accepted")
		}
	}
	for _, s := range []string{strings.Repeat("字", 12), strings.Repeat(" ", 12), strings.Repeat("a", 128)} {
		if e := ValidatePassword(s); e != nil {
			t.Fatal(e)
		}
	}
	for _, s := range []string{"short", strings.Repeat("a", 129)} {
		if ValidatePassword(s) == nil {
			t.Fatal("invalid password")
		}
	}
}
