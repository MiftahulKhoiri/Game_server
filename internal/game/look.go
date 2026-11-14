package game

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
)

// Character Creator (v0.82.0): penampilan pahlawan utama (rambut, wajah, tubuh, pakaian, aksesori) dan
// lemari kosmetik yang dibeli di toko. Hanya tampilan: tidak mengubah serangan/pertahanan, rangka, atau
// hitbox (ukuran tubuh hanya dipakai klien untuk menggambar model; aturan gerak memakai petak).
// Klien hanya mengirim id pilihan; server memeriksa id, kepemilikan, level, dan harga.

// Batas penampilan.
const (
	BodyMin        = -3 // nilai penggeser tubuh (tinggi, lebar, otot, kepala, badan): -3..3
	BodyMax        = 3
	MaxAccessories = 4 // aksesori yang dipakai bersamaan
	MaxWardrobe    = 200
	ReceiptsKeep   = 30 // id permintaan pembelian terakhir yang diingat
	maxRequestID   = 64
)

// Kategori kosmetik (toko & lemari).
const (
	CatSkin    = "skin"     // warna pakaian seluruh tubuh (menggantikan Outfit)
	CatHair    = "rambut"   // model rambut
	CatClothes = "pakaian"  // baju (biasa, petualang, jubah penyihir/petualang)
	CatPants   = "celana"   // celana
	CatGloves  = "sarung"   // sarung tangan
	CatHat     = "topi"     // topi/tudung/mahkota (ditampilkan menggantikan helm)
	CatCape    = "jubah"    // jubah di punggung
	CatAcc     = "aksesori" // kalung, cincin, sabuk, sayap, perisai punggung, ornamen
)

// CosmeticCats: urutan kategori di toko dan lemari.
var CosmeticCats = []string{CatSkin, CatHair, CatClothes, CatPants, CatGloves, CatHat, CatCape, CatAcc}

// Cosmetic adalah satu barang tampilan. Price 0 = gratis (otomatis dimiliki). Color dan Shape dipakai klien
// untuk menggambar (warna utama dan bentuk); nilainya dari server supaya toko dan model selalu sama.
type Cosmetic struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Desc     string `json:"desc"`
	Category string `json:"category"`
	Tier     string `json:"tier"`
	Price    int    `json:"price"`
	Level    int    `json:"level,omitempty"`
	Color    string `json:"color,omitempty"`
	Glow     string `json:"glow,omitempty"`
	Shape    string `json:"shape,omitempty"`
	Outfit   int    `json:"outfit,omitempty"` // CatSkin bawaan: nomor Outfit lama yang sama
}

func cos(id, name, cat, tier string, price, level int, color, shape, desc string) Cosmetic {
	return Cosmetic{ID: id, Name: name, Desc: desc, Category: cat, Tier: tier, Price: price, Level: level, Color: color, Shape: shape}
}

// Cosmetics: seluruh katalog kosmetik.
var Cosmetics = func() []Cosmetic {
	list := []Cosmetic{
		// Skin: empat pertama = variasi pakaian lama (Outfit 0..3), gratis.
		{ID: "skin_asli", Name: "Asli", Desc: "Warna asli pahlawan.", Category: CatSkin, Tier: TierCommon, Color: "#ffffff"},
		{ID: "skin_merah", Name: "Merah Kerajaan", Desc: "Warna pengawal istana.", Category: CatSkin, Tier: TierCommon, Color: "#ff9c8c", Outfit: 1},
		{ID: "skin_hijau", Name: "Hijau Rimba", Desc: "Menyatu dengan hutan.", Category: CatSkin, Tier: TierCommon, Color: "#a6e09a", Outfit: 2},
		{ID: "skin_biru", Name: "Biru Malam", Desc: "Warna langit senja.", Category: CatSkin, Tier: TierCommon, Color: "#9cb6ff", Outfit: 3},
		cos("skin_salju", "Putih Salju", CatSkin, TierUncommon, 250, 1, "#eef4ff", "", "Seputih puncak gunung."),
		cos("skin_senja", "Jingga Senja", CatSkin, TierRare, 450, 5, "#ffb070", "", "Hangat seperti matahari terbenam."),
		cos("skin_emas", "Emas Bangsawan", CatSkin, TierEpic, 1200, 10, "#ffd25a", "", "Berkilau seperti mahkota raja."),
		cos("skin_bayangan", "Bayangan", CatSkin, TierLegendary, 3000, 20, "#6a5a8a", "", "Kelam dan misterius."),
		{ID: "skin_naga", Name: "Sisik Naga", Desc: "Berpendar bara naga terakhir.", Category: CatSkin, Tier: TierMythic, Price: 9000, Level: 35, Color: "#ff6a3a", Glow: "#ff4a12"},
		// Rambut (Shape = bentuk yang digambar klien).
		cos("rambut_pendek", "Pendek", CatHair, TierCommon, 0, 0, "", "pendek", "Rapi dan praktis."),
		cos("rambut_lurus", "Lurus Sebahu", CatHair, TierCommon, 0, 0, "", "lurus", "Lurus jatuh sampai bahu."),
		cos("rambut_panjang", "Panjang", CatHair, TierCommon, 0, 0, "", "panjang", "Terurai sampai punggung."),
		cos("rambut_botak", "Botak", CatHair, TierCommon, 0, 0, "", "botak", "Licin, tanpa rambut."),
		cos("rambut_bergelombang", "Bergelombang", CatHair, TierUncommon, 120, 1, "", "gelombang", "Ombak lembut di sisi kepala."),
		cos("rambut_ikal", "Ikal", CatHair, TierUncommon, 150, 1, "", "ikal", "Ikal-ikal kecil yang lebat."),
		cos("rambut_kepang", "Kepang", CatHair, TierRare, 220, 3, "", "kepang", "Kepang panjang di punggung."),
		cos("rambut_kuncir", "Kuncir Pendekar", CatHair, TierRare, 260, 5, "", "kuncir", "Diikat tinggi ala pendekar."),
		cos("rambut_jambul", "Jambul Liar", CatHair, TierEpic, 800, 12, "", "jambul", "Berdiri tegak menantang angin."),
		// Pakaian.
		cos("baju_biasa", "Baju Biasa", CatClothes, TierCommon, 0, 0, "#ffffff", "biasa", "Pakaian bawaan pahlawan."),
		cos("baju_petualang", "Baju Petualang", CatClothes, TierUncommon, 180, 1, "#c9a27a", "petualang", "Rompi kulit dengan sabuk kantong."),
		cos("jubah_petualang", "Jubah Petualang", CatClothes, TierRare, 380, 5, "#7a8a5a", "jubah_pendek", "Mantel pendek pelindung debu."),
		cos("jubah_penyihir", "Jubah Penyihir", CatClothes, TierRare, 450, 8, "#5a4a9a", "jubah_panjang", "Jubah panjang bersulam bintang."),
		cos("pakaian_bangsawan", "Busana Bangsawan", CatClothes, TierEpic, 1500, 15, "#9a2a3a", "bangsawan", "Beludru merah berhias emas."),
		// Celana.
		cos("celana_kain", "Celana Kain", CatPants, TierCommon, 0, 0, "#ffffff", "", "Celana bawaan."),
		cos("celana_kulit", "Celana Kulit", CatPants, TierUncommon, 90, 1, "#8a5a36", "", "Kulit lentur untuk berlari."),
		cos("celana_tempur", "Celana Tempur", CatPants, TierRare, 280, 6, "#4a5a6a", "", "Berlapis kain tebal di lutut."),
		// Sarung tangan.
		cos("sarung_kulit", "Sarung Tangan Kulit", CatGloves, TierCommon, 60, 1, "#7a4a2a", "", "Pegangan senjata lebih mantap."),
		cos("sarung_besi", "Sarung Tangan Besi", CatGloves, TierRare, 240, 8, "#aab4c2", "", "Buku jari berlapis besi."),
		cos("sarung_naga", "Sarung Tangan Naga", CatGloves, TierLegendary, 2200, 25, "#c83a1e", "", "Dari kulit naga merah."),
		// Topi dan helm hias (ditampilkan menggantikan helm perlengkapan; pertahanan helm tetap dihitung).
		cos("topi_petualang", "Topi Petualang", CatHat, TierUncommon, 140, 1, "#7a5232", "topi", "Bertepi lebar dengan bulu burung."),
		cos("tudung_kepala", "Tudung Kepala", CatHat, TierUncommon, 180, 3, "#3a4a3a", "tudung", "Tudung kain menutupi rambut."),
		cos("mahkota", "Mahkota", CatHat, TierLegendary, 4000, 25, "#ffd25a", "mahkota", "Mahkota emas raja desa."),
		{ID: "mahkota_naga", Name: "Mahkota Naga", Desc: "Bertatah permata api.", Category: CatHat, Tier: TierMythic, Price: 12000, Level: 40, Color: "#ff8a3a", Glow: "#ff4a12", Shape: "mahkota"},
		// Jubah punggung.
		cos("jubah_merah", "Jubah Merah", CatCape, TierUncommon, 220, 1, "#b8322a", "", "Jubah merah pahlawan desa."),
		cos("jubah_biru", "Jubah Biru", CatCape, TierUncommon, 220, 1, "#2a5ab8", "", "Jubah biru pengembara."),
		cos("jubah_bangsawan", "Jubah Bangsawan", CatCape, TierRare, 650, 8, "#6a2a8a", "", "Ungu bersulam benang emas."),
		{ID: "jubah_bintang", Name: "Jubah Bintang", Desc: "Berkelip seperti langit malam.", Category: CatCape, Tier: TierEpic, Price: 2400, Level: 18, Color: "#1a2a5a", Glow: "#8ab0ff"},
		// Aksesori.
		cos("sabuk_kulit", "Sabuk Kulit", CatAcc, TierCommon, 80, 1, "#6a4426", "sabuk", "Sabuk dengan gesper perunggu."),
		cos("kalung_perak", "Kalung Perak", CatAcc, TierUncommon, 160, 1, "#d8dce4", "kalung", "Rantai perak sederhana."),
		cos("cincin_emas", "Cincin Emas", CatAcc, TierRare, 320, 5, "#ffd25a", "cincin", "Cincin emas di jari kanan."),
		cos("perisai_punggung", "Perisai Punggung", CatAcc, TierRare, 420, 6, "#8a6a3a", "perisai_punggung", "Perisai bundar tersandang di punggung."),
		cos("ornamen_bahu", "Ornamen Bahu", CatAcc, TierRare, 520, 8, "#c8a24a", "ornamen", "Hiasan logam di kedua bahu."),
		cos("kalung_permata", "Kalung Permata", CatAcc, TierEpic, 1100, 12, "#e83a5a", "kalung", "Permata merah berpendar lembut."),
		{ID: "sayap_malaikat", Name: "Sayap Malaikat", Desc: "Sayap hias berbulu putih.", Category: CatAcc, Tier: TierLegendary, Price: 6000, Level: 25, Color: "#f4f4ff", Glow: "#c8d8ff", Shape: "sayap"},
		{ID: "sayap_naga", Name: "Sayap Naga", Desc: "Sayap hias naga terakhir.", Category: CatAcc, Tier: TierMythic, Price: 15000, Level: 40, Color: "#8a1e12", Glow: "#ff4a12", Shape: "sayap_naga"},
	}
	return list
}()

// LookOption adalah satu pilihan gratis di Character Creator (wajah, mata, hidung, mulut, alis, janggut, tubuh).
type LookOption struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// LookOptions: pilihan gratis per bagian. Pilihan pertama = bawaan.
var LookOptions = map[string][]LookOption{
	// Jenis kelamin (v0.83.0): berlaku untuk semua pahlawan; "" (akun lama) = laki-laki.
	"gender": {{"pria", "Laki-laki"}, {"wanita", "Perempuan"}},
	"face":   {{"oval", "Oval"}, {"bulat", "Bulat"}, {"persegi", "Persegi"}, {"lancip", "Lancip"}},
	"eyes":   {{"bulat", "Bulat"}, {"sipit", "Sipit"}, {"besar", "Besar"}, {"tajam", "Tajam"}},
	"nose":   {{"kecil", "Kecil"}, {"mancung", "Mancung"}, {"lebar", "Lebar"}},
	"mouth":  {{"senyum", "Senyum"}, {"datar", "Datar"}, {"tipis", "Tipis"}, {"lebar", "Lebar"}},
	"brow":   {{"tegas", "Tegas"}, {"tipis", "Tipis"}, {"tebal", "Tebal"}, {"melengkung", "Melengkung"}},
	"beard":  {{"", "Tanpa"}, {"kumis", "Kumis"}, {"tipis", "Jenggot Tipis"}, {"tebal", "Jenggot Tebal"}, {"kambing", "Jenggot Kambing"}, {"lengkap", "Kumis + Jenggot"}, {"penyihir", "Jenggot Penyihir"}},
	"body":   {{"sedang", "Sedang"}, {"ramping", "Ramping"}, {"kekar", "Kekar"}, {"gempal", "Gempal"}},
}

// Palet warna (hex). Pilihan pertama = bawaan.
var (
	HairColors = []string{"#2a1c12", "#1a1614", "#5a3620", "#8a5a30", "#d9b45a", "#eeeef4", "#a8321e", "#c86a24", "#3a5ac8", "#6a3a9a", "#3a8a4a", "#8a8a90"}
	SkinColors = []string{"#d9a477", "#f4d2b4", "#e8bc94", "#c48a5e", "#a06a42", "#7a4a2c", "#5a3420", "#ffe2cc"}
	EyeColors  = []string{"#3a2414", "#141414", "#3a78c8", "#3c8c4a", "#8a6a2a", "#7a7a86", "#9a3ac8", "#c83a2a"}
)

var hexColor = regexp.MustCompile(`^#[0-9a-f]{6}$`)

// Look adalah penampilan pahlawan utama. Nilai kosong = bawaan (pemain lama tetap tampil seperti dulu).
type Look struct {
	Made      bool   `json:"made,omitempty"`   // sudah pernah menyimpan di Character Creator
	Gender    string `json:"gender,omitempty"` // "pria" | "wanita"; kosong = pria (v0.83.0)
	Skin      string `json:"skin,omitempty"`
	Hair      string `json:"hair,omitempty"`
	HairColor string `json:"hair_color,omitempty"`
	SkinColor string `json:"skin_color,omitempty"`
	Face      string `json:"face,omitempty"`
	Eyes      string `json:"eyes,omitempty"`
	EyeColor  string `json:"eye_color,omitempty"`
	Nose      string `json:"nose,omitempty"`
	Mouth     string `json:"mouth,omitempty"`
	Brow      string `json:"brow,omitempty"`
	Beard     string `json:"beard,omitempty"`
	Body      string `json:"body,omitempty"`
	// Penggeser tubuh -3..3 (0 = asli): tinggi, lebar badan, otot, ukuran kepala, proporsi badan atas.
	Height int `json:"height,omitempty"`
	Width  int `json:"width,omitempty"`
	Muscle int `json:"muscle,omitempty"`
	Head   int `json:"head,omitempty"`
	Torso  int `json:"torso,omitempty"`
	// Kosmetik yang dipakai (id dari Cosmetics; "" = tidak ada/bawaan).
	Clothes     string   `json:"clothes,omitempty"`
	Pants       string   `json:"pants,omitempty"`
	Gloves      string   `json:"gloves,omitempty"`
	Hat         string   `json:"hat,omitempty"`
	Cape        string   `json:"cape,omitempty"`
	Accessories []string `json:"accessories,omitempty"`
}

// Jenis kelamin pahlawan (v0.83.0).
const (
	GenderMale   = "pria"
	GenderFemale = "wanita"
)

// Kesalahan penampilan dan lemari.
var (
	ErrUnknownLook     = errors.New("pilihan penampilan tidak dikenal")
	ErrCosmeticUnknown = errors.New("kosmetik tidak dikenal")
	ErrCosmeticOwned   = errors.New("kosmetik ini sudah dimiliki")
	ErrCosmeticNotOwn  = errors.New("kosmetik ini belum dimiliki; beli dulu di toko")
	ErrCosmeticFree    = errors.New("kosmetik ini gratis, tidak perlu dibeli")
	ErrWrongCategory   = errors.New("kosmetik ini tidak cocok untuk bagian itu")
	ErrWardrobeFull    = errors.New("lemari kosmetik penuh")
	ErrBadRequestID    = errors.New("id permintaan tidak sah")
)

// CosmeticByID mencari kosmetik.
func CosmeticByID(id string) (Cosmetic, bool) {
	i := slices.IndexFunc(Cosmetics, func(c Cosmetic) bool { return c.ID == id })
	if i < 0 {
		return Cosmetic{}, false
	}
	return Cosmetics[i], true
}

// OwnsCosmetic: kosmetik gratis atau sudah dibeli.
func (s State) OwnsCosmetic(id string) bool {
	c, ok := CosmeticByID(id)
	return ok && (c.Price == 0 || slices.Contains(s.Wardrobe, id))
}

// Once menjalankan fn sekali untuk id permintaan `req` (kosong = selalu dijalankan). Permintaan yang diulang
// (mis. jaringan putus lalu klien mengirim lagi) tidak dijalankan kedua kali dan tidak dianggap gagal.
func (s *State) Once(req string, fn func() error) error {
	if len(req) > maxRequestID {
		return ErrBadRequestID
	}
	if req != "" && slices.Contains(s.Receipts, req) {
		return nil
	}
	if err := fn(); err != nil {
		return err
	}
	if req != "" {
		s.Receipts = append(s.Receipts, req)
		if n := len(s.Receipts) - ReceiptsKeep; n > 0 {
			s.Receipts = append([]string(nil), s.Receipts[n:]...)
		}
	}
	return nil
}

// BuyCosmetic membeli kosmetik dengan emas: harga dan level dari server, emas dikurangi dan kosmetik masuk
// lemari dalam satu perubahan state (satu transaksi database di lapisan store).
func (s *State) BuyCosmetic(id string) error {
	c, ok := CosmeticByID(id)
	switch {
	case !ok:
		return ErrCosmeticUnknown
	case c.Price == 0:
		return ErrCosmeticFree
	case slices.Contains(s.Wardrobe, id):
		return ErrCosmeticOwned
	case s.Level < c.Level:
		return ErrLevelLow
	case s.Gold < c.Price:
		return ErrNoGold
	case len(s.Wardrobe) >= MaxWardrobe:
		return ErrWardrobeFull
	}
	s.Gold -= c.Price
	s.Wardrobe = append(s.Wardrobe, id)
	s.record(LedgerBuy, fmt.Sprintf("Membeli kosmetik %s", c.Name), -c.Price)
	return nil
}

func optionOK(part, id string) bool {
	return slices.ContainsFunc(LookOptions[part], func(o LookOption) bool { return o.ID == id })
}

// checkCosmetic: id kosong (bawaan) atau kosmetik kategori `cat` yang dimiliki.
func (s State) checkCosmetic(id, cat string) error {
	if id == "" {
		return nil
	}
	c, ok := CosmeticByID(id)
	if !ok {
		return ErrCosmeticUnknown
	}
	if c.Category != cat {
		return ErrWrongCategory
	}
	if !s.OwnsCosmetic(id) {
		return ErrCosmeticNotOwn
	}
	return nil
}

// SetLook menyimpan penampilan dari Character Creator. Semua id diperiksa, kosmetik harus dimiliki.
func (s *State) SetLook(l Look) error {
	for part, id := range map[string]string{"gender": l.Gender, "face": l.Face, "eyes": l.Eyes, "nose": l.Nose, "mouth": l.Mouth, "brow": l.Brow, "beard": l.Beard, "body": l.Body} {
		if id != "" && !optionOK(part, id) {
			return fmt.Errorf("%w: %s", ErrUnknownLook, part)
		}
	}
	for _, pair := range [][2]any{{l.HairColor, HairColors}, {l.SkinColor, SkinColors}, {l.EyeColor, EyeColors}} {
		if c := pair[0].(string); c != "" && !slices.Contains(pair[1].([]string), c) {
			return fmt.Errorf("%w: warna", ErrUnknownLook)
		}
	}
	for _, v := range []int{l.Height, l.Width, l.Muscle, l.Head, l.Torso} {
		if v < BodyMin || v > BodyMax {
			return fmt.Errorf("%w: ukuran tubuh harus %d..%d", ErrUnknownLook, BodyMin, BodyMax)
		}
	}
	for _, pair := range [][2]string{{l.Skin, CatSkin}, {l.Hair, CatHair}, {l.Clothes, CatClothes}, {l.Pants, CatPants}, {l.Gloves, CatGloves}, {l.Hat, CatHat}, {l.Cape, CatCape}} {
		if err := s.checkCosmetic(pair[0], pair[1]); err != nil {
			return err
		}
	}
	if len(l.Accessories) > MaxAccessories {
		return fmt.Errorf("%w: aksesori maksimal %d", ErrUnknownLook, MaxAccessories)
	}
	for i, id := range l.Accessories {
		if slices.Contains(l.Accessories[:i], id) || id == "" {
			return fmt.Errorf("%w: aksesori ganda", ErrUnknownLook)
		}
		if err := s.checkCosmetic(id, CatAcc); err != nil {
			return err
		}
	}
	l.Made = true
	if l.Gender == GenderFemale {
		l.Beard = "" // pahlawan perempuan tidak berjenggot/berkumis
	}
	if l.Skin != "" {
		c, _ := CosmeticByID(l.Skin)
		s.Outfit = c.Outfit // skin bawaan = variasi pakaian lama; skin toko memakai warna sendiri (Outfit 0)
	}
	l.Accessories = slices.Clone(l.Accessories)
	s.Look = l
	return nil
}

// validLook: pemeriksaan bentuk data (dipanggil di Validate). Kepemilikan diperiksa saat SetLook; di sini
// hanya panjang dan rentang, supaya data lama tetap terbaca walau katalog berubah.
func (s State) validLook() error {
	l := s.Look
	bad := errors.New("data penampilan tidak sah")
	if l.Gender != "" && l.Gender != GenderMale && l.Gender != GenderFemale {
		return bad
	}
	for _, v := range []string{l.Skin, l.Hair, l.HairColor, l.SkinColor, l.Face, l.Eyes, l.EyeColor, l.Nose, l.Mouth, l.Brow, l.Beard, l.Body, l.Clothes, l.Pants, l.Gloves, l.Hat, l.Cape} {
		if len(v) > 64 {
			return bad
		}
	}
	for _, c := range []string{l.HairColor, l.SkinColor, l.EyeColor} {
		if c != "" && !hexColor.MatchString(c) {
			return bad
		}
	}
	for _, v := range []int{l.Height, l.Width, l.Muscle, l.Head, l.Torso} {
		if v < BodyMin || v > BodyMax {
			return bad
		}
	}
	if len(l.Accessories) > MaxAccessories || len(s.Wardrobe) > MaxWardrobe || len(s.Receipts) > ReceiptsKeep {
		return bad
	}
	for _, list := range [][]string{l.Accessories, s.Wardrobe, s.Receipts} {
		for _, id := range list {
			if id == "" || len(id) > 64 {
				return bad
			}
		}
	}
	return nil
}
