package version

import "testing"

func TestCompare(t *testing.T) {
	tests := []struct {
		a, b string
		want int
	}{
		{"0.1.0", "0.1.0", 0},
		{"0.1.0", "0.2.0", -1},
		{"0.2.0", "0.1.9", 1},
		{"1.0.0", "0.99.99", 1},
		{"0.10.0", "0.9.0", 1}, // dibandingkan sebagai angka, bukan teks
		{"v0.2.0", "0.2.0", 0},
		{"0.0.9", "0.1.0", -1},
	}
	for _, tt := range tests {
		got, err := Compare(tt.a, tt.b)
		if err != nil || got != tt.want {
			t.Errorf("Compare(%q,%q) = %d, %v; mau %d", tt.a, tt.b, got, err, tt.want)
		}
	}
}

func TestParseRejects(t *testing.T) {
	for _, v := range []string{"", "1", "1.2", "1.2.3.4", "a.b.c", "1.2.x", "1..3", "-1.0.0", "+1.0.0", "1.0.0-beta"} {
		if Valid(v) {
			t.Errorf("%q seharusnya tidak valid", v)
		}
	}
	if _, err := Compare("1.0.0", "salah"); err == nil {
		t.Error("Compare dengan versi rusak harus error")
	}
}

func TestDefaultsAreValid(t *testing.T) {
	for _, v := range []string{Server, DefaultMinClient, DefaultLatestClient} {
		if !Valid(v) {
			t.Errorf("nilai bawaan %q tidak valid", v)
		}
	}
	if c, _ := Compare(DefaultMinClient, DefaultLatestClient); c > 0 {
		t.Error("min client tidak boleh lebih baru dari latest client")
	}
}
