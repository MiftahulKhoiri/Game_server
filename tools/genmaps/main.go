// Perintah genmaps membuat internal/game/tiles_gen.go dari client/scripts/maps.gd.
//
//	go run ./tools/genmaps        (atau: make maps)
//
// Jalankan setiap kali bentuk peta di maps.gd berubah; TestTilesMatchClient gagal bila lupa.
package main

import (
	"bytes"
	"fmt"
	"go/format"
	"log"
	"os"
	"sort"

	"github.com/MiftahulKhoiri/Game_server/internal/mapsrc"
)

func main() {
	f, err := os.Open("client/scripts/maps.gd")
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	m, err := mapsrc.Parse(f)
	if err != nil {
		log.Fatal(err)
	}
	var b bytes.Buffer
	b.WriteString("// Kode ini dibuat oleh tools/genmaps dari client/scripts/maps.gd. JANGAN DIUBAH MANUAL: jalankan `make maps`.\n\n")
	b.WriteString("package game\n\n")
	fmt.Fprintf(&b, "// walkableTiles: lambang petak yang bisa diinjak (WALKABLE di maps.gd).\nconst walkableTiles = %q\n\n", m.Walkable)
	b.WriteString("// mapRows: bentuk petak setiap peta (baris = sumbu z/y, kolom = sumbu x).\nvar mapRows = map[string][]string{\n")
	ids := make([]string, 0, len(m.Rows))
	for id := range m.Rows {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		fmt.Fprintf(&b, "\t%q: {\n", id)
		for _, r := range m.Rows[id] {
			fmt.Fprintf(&b, "\t\t%q,\n", r)
		}
		b.WriteString("\t},\n")
	}
	b.WriteString("}\n")
	src, err := format.Source(b.Bytes())
	if err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile("internal/game/tiles_gen.go", src, 0o644); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("internal/game/tiles_gen.go: %d peta\n", len(ids))
}
