package game

import (
	"errors"
	"slices"
	"testing"
)

func TestCosmeticCatalogValid(t *testing.T) {
	seen := map[string]bool{}
	for _, c := range Cosmetics {
		switch {
		case seen[c.ID]:
			t.Fatalf("id kosmetik ganda %s", c.ID)
		case !slices.Contains(CosmeticCats, c.Category):
			t.Fatalf("%s: kategori %q tidak dikenal", c.ID, c.Category)
		case !validTier(c.Tier):
			t.Fatalf("%s: kelangkaan %q tidak dikenal", c.ID, c.Tier)
		case c.Price < 0 || c.Name == "" || c.Desc == "":
			t.Fatalf("%s: data toko tidak lengkap", c.ID)
		case c.Color != "" && !hexColor.MatchString(c.Color):
			t.Fatalf("%s: warna %q", c.ID, c.Color)
		}
		seen[c.ID] = true
	}
	for _, tier := range Tiers { // semua enam kelangkaan terpakai di toko
		if !slices.ContainsFunc(Cosmetics, func(c Cosmetic) bool { return c.Tier == tier }) {
			t.Fatalf("tidak ada kosmetik %s", tier)
		}
	}
	for _, cat := range []string{CatHair, CatClothes, CatPants} { // tiap bagian punya pilihan gratis
		if !slices.ContainsFunc(Cosmetics, func(c Cosmetic) bool { return c.Category == cat && c.Price == 0 }) {
			t.Fatalf("kategori %s tanpa pilihan gratis", cat)
		}
	}
	for _, list := range [][]string{HairColors, SkinColors, EyeColors} {
		for _, c := range list {
			if !hexColor.MatchString(c) {
				t.Fatalf("palet %q", c)
			}
		}
	}
}

func TestGearCatalog(t *testing.T) {
	for _, it := range gearItems {
		def, ok := ItemByID(it.ID)
		if !ok || def.Kind != KindEquipment || def.BuyPrice <= 0 || !validTier(def.Tier) || def.Desc == "" {
			t.Fatalf("perlengkapan %s tidak lengkap: %+v", it.ID, def)
		}
		if def.Slot == SlotWeapon && def.Style != "" {
			if _, ok := WeaponStyles[def.Style]; !ok {
				t.Fatalf("%s: gaya %q", it.ID, def.Style)
			}
		}
	}
	// Kelangkaan lama tetap sama untuk barang lama.
	if d, _ := ItemByID("pedang_rune"); d.Rarity != "epik" || d.Tier != TierEpic {
		t.Fatalf("pedang rune: %+v", d)
	}
	if d, _ := ItemByID("pedang_legenda"); d.Rarity != "epik" || d.Tier != TierLegendary {
		t.Fatalf("pedang legenda: %+v", d)
	}
}

func TestBuyCosmetic(t *testing.T) {
	st := NewState()
	st.Gold = 500
	if err := st.BuyCosmetic("rambut_ikal"); err != nil {
		t.Fatal(err)
	}
	if st.Gold != 350 || !st.OwnsCosmetic("rambut_ikal") {
		t.Fatalf("emas %d lemari %v", st.Gold, st.Wardrobe)
	}
	if err := st.BuyCosmetic("rambut_ikal"); !errors.Is(err, ErrCosmeticOwned) || st.Gold != 350 {
		t.Fatalf("beli ulang: %v emas %d", err, st.Gold)
	}
	if err := st.BuyCosmetic("rambut_pendek"); !errors.Is(err, ErrCosmeticFree) {
		t.Fatalf("gratis: %v", err)
	}
	if err := st.BuyCosmetic("jubah_bangsawan"); !errors.Is(err, ErrLevelLow) || st.Gold != 350 {
		t.Fatalf("level kurang: %v", err)
	}
}

func TestBuyCosmeticRules(t *testing.T) {
	st := NewState()
	st.Gold = 100
	if err := st.BuyCosmetic("skin_salju"); !errors.Is(err, ErrNoGold) || st.Gold != 100 || len(st.Wardrobe) != 0 {
		t.Fatalf("tanpa saldo cukup harus ditolak: %v", err)
	}
	st.Gold = 99999
	if err := st.BuyCosmetic("sayap_naga"); !errors.Is(err, ErrLevelLow) || st.Gold != 99999 {
		t.Fatalf("level kurang: %v", err)
	}
	if err := st.BuyCosmetic("sayap_palsu"); !errors.Is(err, ErrCosmeticUnknown) {
		t.Fatalf("barang ilegal: %v", err)
	}
	st.Level = 40
	if err := st.BuyCosmetic("sayap_naga"); err != nil || st.Gold != 99999-15000 {
		t.Fatalf("mitos: %v %d", err, st.Gold)
	}
}

func TestOnceBlocksRepeatedPurchase(t *testing.T) {
	st := NewState()
	st.Gold = 1000
	buy := func() error { return st.BuyCosmetic("jubah_merah") }
	if err := st.Once("req-1", buy); err != nil {
		t.Fatal(err)
	}
	if err := st.Once("req-1", buy); err != nil || st.Gold != 780 {
		t.Fatalf("permintaan ulang tidak boleh membayar lagi: %v emas %d", err, st.Gold)
	}
	// Barang bertumpuk juga hanya sekali untuk id permintaan yang sama.
	if err := st.Once("req-2", func() error { return Buy(&st, PotionID, 1) }); err != nil {
		t.Fatal(err)
	}
	gold := st.Gold
	if err := st.Once("req-2", func() error { return Buy(&st, PotionID, 1) }); err != nil || st.Gold != gold {
		t.Fatalf("ramuan dibeli dua kali: %d -> %d", gold, st.Gold)
	}
	for i := range ReceiptsKeep + 5 {
		_ = st.Once(string(rune('a'+i%26))+string(rune('A'+i/26)), func() error { return nil })
	}
	if len(st.Receipts) != ReceiptsKeep {
		t.Fatalf("catatan permintaan %d", len(st.Receipts))
	}
	if err := st.Once(string(make([]byte, 65)), buy); !errors.Is(err, ErrBadRequestID) {
		t.Fatalf("id terlalu panjang: %v", err)
	}
}

func TestSetLook(t *testing.T) {
	st := NewState()
	l := Look{Hair: "rambut_panjang", HairColor: "#d9b45a", SkinColor: "#7a4a2c", Face: "bulat", Eyes: "sipit", EyeColor: "#3a78c8",
		Nose: "mancung", Mouth: "lebar", Brow: "tebal", Beard: "kumis", Body: "kekar", Height: 2, Width: -1, Muscle: 3, Head: -2, Torso: 1,
		Clothes: "baju_biasa", Pants: "celana_kain", Skin: "skin_hijau"}
	if err := st.SetLook(l); err != nil {
		t.Fatal(err)
	}
	if !st.Look.Made || st.Look.Hair != "rambut_panjang" || st.Outfit != 2 || st.Validate() != nil {
		t.Fatalf("look %+v outfit %d", st.Look, st.Outfit)
	}
	bad := []Look{
		{Hair: "rambut_ikal"},                  // belum dimiliki
		{Hat: "mahkota"},                       // belum dimiliki
		{Hair: "jubah_merah"},                  // kategori salah
		{Face: "segitiga"},                     // tidak dikenal
		{HairColor: "#123456"},                 // warna di luar palet
		{Height: 4},                            // di luar rentang
		{Accessories: []string{"sabuk_kulit"}}, // belum dimiliki
		{Hair: "rambut_tidak_ada"},
	}
	for _, b := range bad {
		before := st.Look
		if err := st.SetLook(b); err == nil {
			t.Fatalf("harus ditolak: %+v", b)
		}
		if st.Look.Hair != before.Hair {
			t.Fatal("penolakan tidak boleh mengubah penampilan")
		}
	}
	st.Gold = 5000
	for _, id := range []string{"rambut_ikal", "sabuk_kulit", "kalung_perak", "jubah_merah", "topi_petualang"} {
		if err := st.BuyCosmetic(id); err != nil {
			t.Fatal(id, err)
		}
	}
	l = Look{Hair: "rambut_ikal", Accessories: []string{"sabuk_kulit", "kalung_perak"}, Cape: "jubah_merah", Hat: "topi_petualang"}
	if err := st.SetLook(l); err != nil {
		t.Fatal(err)
	}
	if err := st.SetLook(Look{Accessories: []string{"sabuk_kulit", "sabuk_kulit"}}); err == nil {
		t.Fatal("aksesori ganda harus ditolak")
	}
	// Lepas: kosongkan.
	if err := st.SetLook(Look{Hair: "rambut_ikal"}); err != nil || st.Look.Cape != "" || len(st.Look.Accessories) != 0 {
		t.Fatalf("lepas kosmetik: %v %+v", err, st.Look)
	}
	// Ganti di Profil (Outfit lama) menghapus skin toko.
	st.Look.Skin = "skin_hijau"
	if err := st.SetOutfit(1); err != nil || st.Look.Skin != "" {
		t.Fatalf("outfit lama: %v %+v", err, st.Look)
	}
}

func TestEquipNewGear(t *testing.T) {
	st := NewState() // Ksatria = pedang
	st.Gold = 99999
	if err := Buy(&st, "helm_ksatria", 1); !errors.Is(err, ErrLevelLow) {
		t.Fatalf("membeli helm Lv 18 di level 1: %v", err)
	}
	st.Level = 20 // beli dulu (syarat level saat membeli), lalu turunkan untuk menguji syarat saat memakai
	for _, id := range []string{"belati", "kapak_besar", "perisai_kayu", "sepatu_kulit", "helm_ksatria", "zirah_berat"} {
		if err := Buy(&st, id, 1); err != nil {
			t.Fatal(id, err)
		}
	}
	st.Level = 5
	if err := st.Equip("kapak_besar"); !errors.Is(err, ErrWrongStyle) && !errors.Is(err, ErrLevelLow) {
		t.Fatalf("kapak untuk ksatria: %v", err)
	}
	if err := st.Equip("helm_ksatria"); !errors.Is(err, ErrLevelLow) {
		t.Fatalf("level kurang: %v", err)
	}
	base := st.Defense()
	for _, id := range []string{"belati", "perisai_kayu", "sepatu_kulit"} {
		if err := st.Equip(id); err != nil {
			t.Fatal(id, err)
		}
	}
	if st.Defense() != base+2 || st.Equipment.Boots != "sepatu_kulit" || st.Equipment.Offhand != "perisai_kayu" {
		t.Fatalf("pertahanan %d -> %d %+v", base, st.Defense(), st.Equipment)
	}
	// Belati lebih cepat dan lebih mudah kritis dari pedang biasa.
	if ws := st.Style(); ws.AttackMs >= WeaponStyles[StylePedang].AttackMs || ws.CritBonus != 6 {
		t.Fatalf("gaya belati %+v", ws)
	}
	if err := st.Equip("sepatu_legenda"); !errors.Is(err, ErrNotEnough) {
		t.Fatalf("belum dimiliki: %v", err)
	}
	// Ganti ke Pemanah: belati dan perisai dilepas otomatis, sepatu tetap.
	if err := st.SetHero("pemanah"); err != nil {
		t.Fatal(err)
	}
	if st.Equipment.Weapon != "" || st.Equipment.Offhand != "" || st.Equipment.Boots != "sepatu_kulit" {
		t.Fatalf("setelah ganti pahlawan %+v", st.Equipment)
	}
	if err := st.Equip("perisai_kayu"); !errors.Is(err, ErrWrongStyle) {
		t.Fatalf("perisai untuk pemanah: %v", err)
	}
	for _, slot := range []string{SlotBoots} {
		if err := st.Unequip(slot); err != nil {
			t.Fatal(err)
		}
	}
	if err := st.Unequip(SlotOffhand); !errors.Is(err, ErrNothingWorn) {
		t.Fatalf("lepas kosong: %v", err)
	}
	// Senjata mitos (tanpa gaya) bisa dipakai semua pahlawan.
	st.Level = 45
	if err := Buy(&st, "pedang_naga_purba", 1); err != nil {
		t.Fatal(err)
	}
	if err := st.Equip("pedang_naga_purba"); err != nil {
		t.Fatal(err)
	}
}

func TestLookValidateLegacy(t *testing.T) {
	st := NewState() // akun lama: Look kosong tetap sah
	if err := st.Validate(); err != nil {
		t.Fatal(err)
	}
	st.Look.HairColor = "merah"
	if st.Validate() == nil {
		t.Fatal("warna bukan hex harus ditolak")
	}
	st.Look.HairColor = ""
	st.Look.Height = 9
	if st.Validate() == nil {
		t.Fatal("tinggi di luar rentang harus ditolak")
	}
}

func TestLookGender(t *testing.T) {
	st := NewState()
	if err := st.SetLook(Look{Gender: GenderFemale, Beard: "tebal", Hair: "rambut_panjang"}); err != nil {
		t.Fatal(err)
	}
	if st.Look.Gender != GenderFemale || st.Look.Beard != "" || st.Validate() != nil {
		t.Fatalf("pahlawan perempuan: %+v", st.Look)
	}
	if err := st.SetLook(Look{Gender: "naga"}); !errors.Is(err, ErrUnknownLook) {
		t.Fatalf("jenis kelamin tidak dikenal: %v", err)
	}
	if err := st.SetLook(Look{Gender: GenderMale, Beard: "kumis"}); err != nil || st.Look.Beard != "kumis" {
		t.Fatalf("laki-laki berkumis: %v %+v", err, st.Look)
	}
	st.Look.Gender = "x"
	if st.Validate() == nil {
		t.Fatal("jenis kelamin rusak di data harus ditolak")
	}
	old := NewState() // akun lama tanpa jenis kelamin tetap sah (= laki-laki)
	if old.Look.Gender != "" || old.Validate() != nil {
		t.Fatal("akun lama")
	}
}
