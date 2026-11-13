package game

import (
	"encoding/json"
	"strings"
	"testing"
)

// Bunga bank (no. 181, v0.79.0).

func atDay(t *testing.T, day int64) {
	t.Helper()
	old := Now
	Now = func() int64 { return day*realDaySeconds + 3600 }
	t.Cleanup(func() { Now = old })
}

func banker(bank int) State {
	st := NewState()
	st.Map = SpawnMap
	st.Bank = bank
	return st
}

func TestBankInterestFirstTouchOnlyStartsClock(t *testing.T) {
	atDay(t, 100)
	st := banker(10_000)
	if got := st.AccrueInterest(); got != 0 || st.Bank != 10_000 || st.BankDay != 100 {
		t.Fatalf("sentuhan pertama: bunga %d, bank %d, hari %d", got, st.Bank, st.BankDay)
	}
}

func TestBankInterestDaily(t *testing.T) {
	atDay(t, 100)
	st := banker(10_000)
	st.BankDay = 97
	if due := st.BankInterestDue(); due != 300 {
		t.Fatalf("3 hari x 1%% x 10.000 = 300, dapat %d", due)
	}
	if got := st.AccrueInterest(); got != 300 || st.Bank != 10_300 || st.BankDay != 100 {
		t.Fatalf("bunga %d, bank %d, hari %d", got, st.Bank, st.BankDay)
	}
	if again := st.AccrueInterest(); again != 0 {
		t.Fatalf("hari yang sama dihitung dua kali: %d", again)
	}
	if !strings.Contains(st.Ledger[len(st.Ledger)-1].Note, "Bunga") {
		t.Fatalf("bunga tidak tercatat: %+v", st.Ledger)
	}
}

func TestBankInterestCapped(t *testing.T) {
	atDay(t, 500)
	st := banker(5_000_000)
	st.BankDay = 1 // lama sekali tidak ke bank
	want := BankInterestMaxDays * BankInterestCap * BankInterestPermil / 1000
	if got := st.AccrueInterest(); got != want {
		t.Fatalf("bunga harus dibatasi %d, dapat %d", want, got)
	}
	full := banker(MaxBank)
	full.BankDay = 499
	if got := full.AccrueInterest(); got != 0 || full.Bank != MaxBank {
		t.Fatalf("tabungan penuh meluap: %d", full.Bank)
	}
}

// Celah: emas yang baru disimpan tidak berbunga untuk hari-hari yang sudah lewat.
func TestBankInterestDepositDoesNotEarnBackdated(t *testing.T) {
	atDay(t, 100)
	st := banker(1)
	st.Gold = 20_000
	st.BankDay = 93
	if err := st.BankDeposit(19_999); err != nil {
		t.Fatal(err)
	}
	if st.Bank != 1+19_999 {
		t.Fatalf("simpan memberi bunga untuk emas baru: bank %d", st.Bank)
	}
	if st.BankInterestDue() != 0 {
		t.Fatal("bunga hari ini sudah dihitung, tidak boleh ada sisa")
	}
}

func TestBankInterestWithdrawCreditsFirst(t *testing.T) {
	atDay(t, 100)
	st := banker(10_000)
	st.BankDay = 99
	if err := st.BankWithdraw(10_100); err != nil {
		t.Fatalf("bunga harus masuk sebelum mengambil: %v", err)
	}
	if st.Bank != 0 || st.Gold != NewState().Gold+10_100 {
		t.Fatalf("bank %d, emas %d", st.Bank, st.Gold)
	}
}

func TestBankClaimOnlyInVillage(t *testing.T) {
	atDay(t, 100)
	st := banker(100)
	st.Map = MapPerbatasan
	if err := st.BankClaim(); err != ErrBankFar {
		t.Fatalf("klaim di luar desa: %v", err)
	}
}

func TestBankDayCompatAndValidate(t *testing.T) {
	atDay(t, 100)
	raw, _ := json.Marshal(NewState())
	if strings.Contains(string(raw), "bank_day") {
		t.Fatal("state baru menulis bank_day")
	}
	st := NewState()
	st.BankDay = 105
	if st.Validate() == nil {
		t.Fatal("hari bunga di masa depan dianggap sah")
	}
	st.BankDay = 100
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
}
