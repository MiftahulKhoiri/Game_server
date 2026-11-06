package auth

import (
	"strings"
	"testing"
	"time"
)

func init() { Iterations = 1000 } // cepat untuk tes

func TestHashAndVerify(t *testing.T) {
	h, err := Hash("rahasia-banget")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(h, "rahasia") {
		t.Fatal("hash tidak boleh memuat kata sandi")
	}
	if !Verify("rahasia-banget", h) {
		t.Error("kata sandi benar harus lolos")
	}
	if Verify("Rahasia-banget", h) || Verify("", h) {
		t.Error("kata sandi salah harus ditolak")
	}
	h2, _ := Hash("rahasia-banget")
	if h == h2 {
		t.Error("garam harus acak: dua hash dari sandi sama tidak boleh identik")
	}
}

func TestVerifyRejectsGarbage(t *testing.T) {
	for _, bad := range []string{"", "x", "a$b$c$d", "pbkdf2-sha256$0$AAAA$AAAA", "pbkdf2-sha256$abc$AAAA$AAAA",
		"pbkdf2-sha256$99999999999$AAAA$AAAA", "pbkdf2-sha256$1000$!!$!!", "pbkdf2-sha256$1000$AAAA"} {
		if Verify("apa-saja", bad) {
			t.Errorf("hash rusak %q tidak boleh lolos", bad)
		}
	}
}

func TestVerifyUsesStoredIterations(t *testing.T) {
	old := Iterations
	Iterations = 2000
	h, _ := Hash("sandi-panjang")
	Iterations = old
	if !strings.HasPrefix(h, "pbkdf2-sha256$2000$") {
		t.Fatalf("iterasi harus ikut tersimpan: %s", h)
	}
	if !Verify("sandi-panjang", h) {
		t.Error("hash lama dengan iterasi berbeda harus tetap terverifikasi")
	}
}

func TestValidatePassword(t *testing.T) {
	for pw, ok := range map[string]bool{
		"1234567":                 false,
		"12345678":                true,
		"        ":                false,
		"kata sandi dengan spasi": true,
		"sandi😀😀😀😀😀😀😀😀":           true,
		strings.Repeat("a", 128):  true,
		strings.Repeat("a", 129):  false,
	} {
		if err := ValidatePassword(pw); (err == nil) != ok {
			t.Errorf("ValidatePassword(%q) = %v, harapan ok=%v", pw, err, ok)
		}
	}
}

func TestNormalizeEmail(t *testing.T) {
	good := map[string]string{
		"budi@contoh.id":          "budi@contoh.id",
		"  Budi.S@Contoh.CO.ID  ": "budi.s@contoh.co.id",
		"a+b@x.io":                "a+b@x.io",
	}
	for in, want := range good {
		got, err := NormalizeEmail(in)
		if err != nil || got != want {
			t.Errorf("NormalizeEmail(%q) = %q, %v; harapan %q", in, got, err, want)
		}
	}
	for _, bad := range []string{"", "budi", "budi@", "@x.id", "budi@x", "budi@.id", "budi@x.", "Budi <b@x.id>",
		"a b@x.id", "a@x.id, c@y.id", strings.Repeat("a", 250) + "@x.id"} {
		if got, err := NormalizeEmail(bad); err == nil {
			t.Errorf("NormalizeEmail(%q) harus ditolak, dapat %q", bad, got)
		}
	}
}

func TestLimiter(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	l := NewLimiter(3, time.Minute)
	l.SetClock(func() time.Time { return now })

	for i := 0; i < 3; i++ {
		if _, blocked := l.Blocked("a"); blocked {
			t.Fatalf("belum boleh diblokir pada kegagalan ke-%d", i)
		}
		l.Fail("a")
		now = now.Add(10 * time.Second)
	}
	wait, blocked := l.Blocked("a")
	if !blocked || wait <= 0 || wait > time.Minute {
		t.Fatalf("harus diblokir setelah 3 kegagalan: blocked=%v wait=%v", blocked, wait)
	}
	if _, blocked := l.Blocked("b"); blocked {
		t.Error("kunci lain tidak boleh ikut diblokir")
	}
	now = now.Add(time.Minute)
	if _, blocked := l.Blocked("a"); blocked {
		t.Error("harus terbuka lagi setelah window lewat")
	}
	l.Fail("a")
	l.Fail("a")
	l.Fail("a")
	l.Reset("a")
	if _, blocked := l.Blocked("a"); blocked {
		t.Error("Reset harus menghapus catatan kegagalan")
	}
}
