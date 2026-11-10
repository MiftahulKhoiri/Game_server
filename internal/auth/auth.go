// Package auth berisi hash kata sandi, pemeriksaan data akun, dan pembatas percobaan login.
//
// Hash memakai PBKDF2-HMAC-SHA256 dari pustaka standar Go (crypto/pbkdf2, Go 1.24+), jadi
// tidak ada dependensi baru. Format simpanan:
//
//	pbkdf2-sha256$<iterasi>$<garam base64>$<hash base64>
//
// Jumlah iterasi ikut tersimpan, sehingga bisa dinaikkan nanti tanpa merusak akun lama.
package auth

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"net/mail"
	"strconv"
	"strings"
	"sync"
	"unicode/utf8"
)

// Iterations adalah jumlah putaran PBKDF2 untuk hash baru (anjuran OWASP untuk
// HMAC-SHA256: 600 ribu). Variabel supaya tes bisa menurunkannya agar cepat.
var Iterations = 600_000

const (
	scheme  = "pbkdf2-sha256"
	saltLen = 16
	keyLen  = 32

	// MinPassword dan MaxPassword membatasi panjang kata sandi (dalam karakter / byte).
	MinPassword = 8
	MaxPassword = 128

	maxEmail      = 254
	maxIterations = 10_000_000 // batas waras saat membaca hash dari database
)

var b64 = base64.RawStdEncoding

// Hash membuat hash kata sandi dengan garam acak.
func Hash(password string) (string, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, Iterations, keyLen)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s$%d$%s$%s", scheme, Iterations, b64.EncodeToString(salt), b64.EncodeToString(key)), nil
}

// Verify memeriksa kata sandi terhadap hash tersimpan (waktu tetap). Hash rusak = false.
func Verify(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != scheme {
		return false
	}
	iter, err := strconv.Atoi(parts[1])
	if err != nil || iter < 1 || iter > maxIterations {
		return false
	}
	salt, err := b64.DecodeString(parts[2])
	if err != nil || len(salt) == 0 {
		return false
	}
	want, err := b64.DecodeString(parts[3])
	if err != nil || len(want) == 0 {
		return false
	}
	got, err := pbkdf2.Key(sha256.New, password, salt, iter, len(want))
	if err != nil {
		return false
	}
	return subtle.ConstantTimeCompare(got, want) == 1
}

// NeedsRehash: hash dibuat dengan putaran lebih sedikit dari Iterations sekarang (mis. akun lama),
// sehingga sebaiknya dibuat ulang saat pemain berhasil masuk (roadmap no. 221).
func NeedsRehash(encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != scheme {
		return true
	}
	iter, err := strconv.Atoi(parts[1])
	return err != nil || iter < Iterations
}

var (
	dummyOnce sync.Once
	dummyHash string
)

// BurnTime menghabiskan waktu sebesar satu pemeriksaan kata sandi. Dipanggil saat nama/email
// tidak ada, supaya lama jawaban tidak membocorkan apakah akun itu ada.
func BurnTime(password string) {
	dummyOnce.Do(func() { dummyHash, _ = Hash("tidak-dipakai") })
	Verify(password, dummyHash)
}

// ValidatePassword memeriksa aturan kata sandi. Spasi di tepi dipertahankan (bagian dari sandi).
func ValidatePassword(pw string) error {
	if utf8.RuneCountInString(pw) < MinPassword {
		return fmt.Errorf("kata sandi minimal %d karakter", MinPassword)
	}
	if len(pw) > MaxPassword {
		return fmt.Errorf("kata sandi maksimal %d byte", MaxPassword)
	}
	if strings.TrimSpace(pw) == "" {
		return errors.New("kata sandi tidak boleh hanya spasi")
	}
	return nil
}

// NormalizeEmail merapikan (huruf kecil, tanpa spasi tepi) dan memeriksa bentuk alamat email.
// Hanya alamat polos yang diterima, tanpa nama tampilan seperti "Budi <b@x.id>".
func NormalizeEmail(s string) (string, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	bad := errors.New("alamat email tidak valid")
	if s == "" || len(s) > maxEmail {
		return "", bad
	}
	addr, err := mail.ParseAddress(s)
	if err != nil || addr.Address != s {
		return "", bad
	}
	at := strings.LastIndex(s, "@")
	domain := s[at+1:]
	if at < 1 || !strings.Contains(domain, ".") || strings.HasPrefix(domain, ".") || strings.HasSuffix(domain, ".") {
		return "", bad
	}
	return s, nil
}
