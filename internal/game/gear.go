package game

import (
	"errors"
	"slices"
)

// Perlengkapan tempur tambahan (Character Creator, v0.82.0): senjata per jenis, zirah ringan/berat/legendaris,
// helm, sepatu, dan perisai. Semua dijual di Toko Peralatan (dan toko di menu) dengan harga dari server.
// Angka draf; diseimbangkan lewat simulasi pertarungan (combat_style_test.go).

// Tingkat kelangkaan (enam tingkat).
const (
	TierCommon    = "common"
	TierUncommon  = "uncommon"
	TierRare      = "rare"
	TierEpic      = "epic"
	TierLegendary = "legendary"
	TierMythic    = "mythic"
)

// Tiers: urutan kelangkaan dari terendah.
var Tiers = []string{TierCommon, TierUncommon, TierRare, TierEpic, TierLegendary, TierMythic}

func validTier(t string) bool { return slices.Contains(Tiers, t) }

// tierOfRarity: kelangkaan tiga tingkat lama -> enam tingkat.
func tierOfRarity(r string) string {
	switch r {
	case "langka":
		return TierRare
	case "epik":
		return TierEpic
	}
	return TierCommon
}

// rarityOfTier: enam tingkat -> tiga tingkat lama (warna nama di klien lama).
func rarityOfTier(t string) string {
	switch t {
	case TierRare:
		return "langka"
	case TierEpic, TierLegendary, TierMythic:
		return "epik"
	}
	return "biasa"
}

// Kesalahan perlengkapan baru.
var (
	ErrLevelLow   = errors.New("level belum cukup untuk barang ini")
	ErrWrongStyle = errors.New("pahlawan ini tidak bisa memakai senjata jenis itu")
)

// offhandStyles: gaya senjata yang tangan kirinya bebas untuk perisai (busur dan tongkat dipegang dua tangan).
var offhandStyles = []string{StylePedang, StyleKapak, StyleTombak}

func gear(id, name, slot, tier string, buy, level int, desc string) ItemDef {
	return ItemDef{ID: id, Name: name, Kind: KindEquipment, Slot: slot, Tier: tier, BuyPrice: buy, SellPrice: buy / 3, Shop: ShopGear, Level: level, Desc: desc}
}

func weapon(id, name, style, tier string, atk, speed, crit, buy, level int, desc string) ItemDef {
	it := gear(id, name, SlotWeapon, tier, buy, level, desc)
	it.Style, it.Attack, it.SpeedPct, it.Crit = style, atk, speed, crit
	return it
}

func protect(id, name, slot, tier string, def, buy, level int, desc string) ItemDef {
	it := gear(id, name, slot, tier, buy, level, desc)
	it.Defense = def
	return it
}

var gearItems = []ItemDef{
	// Senjata (terpasang di tangan model; gaya harus sama dengan pahlawan).
	weapon("belati", "Belati", StylePedang, TierCommon, 2, 80, 6, 90, 1, "Ringan dan cepat, mudah menusuk titik lemah."),
	weapon("pedang_pendek", "Pedang Pendek", StylePedang, TierCommon, 3, 90, 0, 110, 1, "Pedang satu tangan yang lincah."),
	weapon("pedang_panjang", "Pedang Panjang", StylePedang, TierUncommon, 7, 105, 0, 420, 8, "Jangkauan tebasan lebih panjang."),
	weapon("pedang_dua_tangan", "Pedang Dua Tangan", StylePedang, TierRare, 11, 125, 2, 900, 15, "Berat dan lambat, tebasannya membelah."),
	weapon("pedang_legenda", "Pedang Legenda", StylePedang, TierLegendary, 18, 95, 8, 6000, 30, "Bilah bercahaya dari zaman para naga."),
	weapon("kapak_tangan", "Kapak Tangan", StyleKapak, TierCommon, 4, 95, 0, 140, 1, "Kapak kecil yang mudah diayun."),
	weapon("kapak_besar", "Kapak Besar", StyleKapak, TierRare, 10, 115, 0, 700, 10, "Kapak dua mata untuk pendekar kuat."),
	weapon("palu_perang", "Palu Perang", StyleKapak, TierEpic, 14, 130, 0, 1400, 18, "Pukulannya menggetarkan tanah."),
	weapon("tombak_besi", "Tombak Besi", StyleTombak, TierCommon, 4, 100, 0, 150, 1, "Tombak baja dengan gagang kayu jati."),
	weapon("tombak_naga", "Tombak Naga", StyleTombak, TierEpic, 12, 95, 4, 2200, 20, "Mata tombak dari sisik naga."),
	weapon("tongkat_kayu", "Tongkat Sihir Kayu", StyleSihir, TierCommon, 3, 100, 0, 130, 1, "Tongkat penyihir pemula."),
	weapon("tongkat_kristal", "Tongkat Kristal", StyleSihir, TierRare, 9, 95, 3, 950, 12, "Kristal birunya memperkuat mantra."),
	weapon("busur_pendek", "Busur Pendek", StyleBusur, TierCommon, 3, 90, 0, 130, 1, "Busur ringan, tembakan cepat."),
	weapon("busur_panjang", "Busur Panjang", StyleBusur, TierRare, 8, 105, 5, 800, 10, "Busur besar untuk tembakan jauh dan tepat."),
	weapon("pedang_naga_purba", "Pedang Naga Purba", "", TierMythic, 22, 100, 10, 25000, 45, "Senjata mitos; menyesuaikan diri dengan pahlawan mana pun."),
	// Perisai (tangan kiri; pedang, kapak, tombak).
	protect("perisai_kayu", "Perisai Kayu", SlotOffhand, TierCommon, 1, 80, 1, "Papan kayu berlapis kulit."),
	protect("perisai_besi", "Perisai Besi", SlotOffhand, TierUncommon, 3, 350, 8, "Perisai bundar berlapis besi."),
	protect("perisai_legenda", "Perisai Legenda", SlotOffhand, TierLegendary, 6, 3500, 25, "Lambang singa emas, tak pernah retak."),
	// Zirah (ringan = Baju Kulit, sudah ada).
	protect("zirah_berat", "Zirah Berat", SlotArmor, TierRare, 7, 900, 15, "Lempeng baja tebal; lambat tetapi kokoh."),
	protect("zirah_legenda", "Zirah Legenda", SlotArmor, TierLegendary, 11, 5000, 30, "Zirah emas para pahlawan lama."),
	// Helm.
	protect("helm_baja", "Helm Baja", SlotHelmet, TierUncommon, 4, 450, 10, "Helm baja dengan pelindung pipi."),
	protect("helm_ksatria", "Helm Ksatria", SlotHelmet, TierRare, 6, 1100, 18, "Helm tertutup berjambul."),
	protect("helm_legenda", "Helm Legenda", SlotHelmet, TierLegendary, 9, 4500, 30, "Helm bertanduk emas."),
	// Sepatu.
	protect("sepatu_biasa", "Sepatu Biasa", SlotBoots, TierCommon, 0, 20, 1, "Sepatu kain sehari-hari."),
	protect("sepatu_petualang", "Sepatu Petualang", SlotBoots, TierCommon, 1, 60, 1, "Nyaman untuk perjalanan jauh."),
	protect("sepatu_kulit", "Sepatu Kulit", SlotBoots, TierUncommon, 1, 90, 3, "Kulit tebal tahan air."),
	protect("sepatu_besi", "Sepatu Besi", SlotBoots, TierUncommon, 2, 260, 8, "Ujung besi melindungi kaki."),
	protect("sepatu_armor", "Sepatu Armor", SlotBoots, TierRare, 3, 600, 15, "Pelat baja sampai lutut."),
	protect("sepatu_legenda", "Sepatu Legenda", SlotBoots, TierLegendary, 5, 3000, 30, "Ringan seperti bulu, keras seperti batu."),
}

// styleAllows: apakah senjata/perisai `def` boleh dipakai pahlawan bergaya `style`.
func styleAllows(def ItemDef, style string) bool {
	switch def.Slot {
	case SlotWeapon:
		return def.Style == "" || def.Style == style
	case SlotOffhand:
		return slices.Contains(offhandStyles, style)
	}
	return true
}

// dropIncompatible melepas senjata/perisai yang tidak cocok dengan pahlawan aktif (dipanggil saat ganti pahlawan).
func (s *State) dropIncompatible() {
	style := s.HeroDef().styleID()
	if def, ok := ItemByID(s.Equipment.Weapon); ok && !styleAllows(def, style) {
		s.Equipment.Weapon = ""
	}
	if def, ok := ItemByID(s.Equipment.Offhand); ok && !styleAllows(def, style) {
		s.Equipment.Offhand = ""
	}
}
