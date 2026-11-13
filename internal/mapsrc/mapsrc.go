// Package mapsrc membaca bentuk petak peta dari client/scripts/maps.gd (sumber kebenaran bentuk peta).
//
// Dipakai oleh tools/genmaps (membuat internal/game/tiles_gen.go) dan oleh tes yang memastikan data petak
// server sama dengan klien. Server sendiri tidak membaca maps.gd saat berjalan.
package mapsrc

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strings"
)

// Maps adalah hasil bacaan maps.gd.
type Maps struct {
	Walkable string              // isi const WALKABLE
	Rows     map[string][]string // id peta -> baris petak
}

var (
	reIDConst   = regexp.MustCompile(`^const ([A-Z_]+) := "([a-z_]+)"`)
	reRowsConst = regexp.MustCompile(`^const ([A-Z_]+): Array\[String\] = \[`)
	reRowLine   = regexp.MustCompile(`^\s*"([^"]*)",?\s*(#.*)?$`)
	reWalkable  = regexp.MustCompile(`^const WALKABLE := "([^"]+)"`)
	reMatchCase = regexp.MustCompile(`^\t\t([A-Z_]+):$`)
	reReturn    = regexp.MustCompile(`^\t\t\treturn ([A-Z_]+)$`)
)

// Parse membaca maps.gd.
func Parse(r io.Reader) (Maps, error) {
	ids := map[string]string{}      // nama const -> id peta
	arrays := map[string][]string{} // nama const -> baris
	caseOf := map[string]string{}   // nama const id -> nama const baris (dari static func rows)
	out := Maps{Rows: map[string][]string{}}
	var cur, inRows string
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case cur != "":
			if strings.HasPrefix(line, "]") {
				cur = ""
				continue
			}
			if m := reRowLine.FindStringSubmatch(line); m != nil {
				arrays[cur] = append(arrays[cur], m[1])
			}
		case strings.HasPrefix(line, "static func rows(map_id: String)"):
			inRows = "?"
		case inRows != "":
			if m := reMatchCase.FindStringSubmatch(line); m != nil {
				inRows = m[1]
			} else if m := reReturn.FindStringSubmatch(line); m != nil && inRows != "?" {
				caseOf[inRows] = m[1]
			} else if strings.HasPrefix(line, "\treturn") || (line != "" && !strings.HasPrefix(line, "\t")) {
				inRows = ""
			}
		default:
			if m := reRowsConst.FindStringSubmatch(line); m != nil {
				cur = m[1]
			} else if m := reIDConst.FindStringSubmatch(line); m != nil {
				ids[m[1]] = m[2]
			} else if m := reWalkable.FindStringSubmatch(line); m != nil {
				out.Walkable = m[1]
			}
		}
	}
	if err := sc.Err(); err != nil {
		return out, err
	}
	for idConst, arr := range caseOf {
		id, ok := ids[idConst]
		if !ok {
			return out, fmt.Errorf("maps.gd: id peta %s tidak dikenal", idConst)
		}
		rows, ok := arrays[arr]
		if !ok || len(rows) == 0 {
			return out, fmt.Errorf("maps.gd: baris %s untuk %s kosong", arr, id)
		}
		for i, r := range rows {
			if len(r) != len(rows[0]) {
				return out, fmt.Errorf("maps.gd: %s baris %d panjangnya %d, mau %d", id, i, len(r), len(rows[0]))
			}
		}
		out.Rows[id] = rows
	}
	if out.Walkable == "" || len(out.Rows) == 0 {
		return out, fmt.Errorf("maps.gd: WALKABLE atau peta tidak terbaca")
	}
	return out, nil
}
