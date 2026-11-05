package game

import "testing"

func TestNewStateValid(t *testing.T) {
	if err := NewState().Validate(); err != nil {
		t.Fatalf("state awal harus valid: %v", err)
	}
}

func TestValidateRejects(t *testing.T) {
	tests := map[string]func(*State){
		"level 0":             func(s *State) { s.Level = 0 },
		"level terlalu besar": func(s *State) { s.Level = MaxLevel + 1 },
		"xp negatif":          func(s *State) { s.XP = -1 },
		"hp melebihi max":     func(s *State) { s.HP = s.MaxHP + 1 },
		"hp negatif":          func(s *State) { s.HP = -1 },
		"gold negatif":        func(s *State) { s.Gold = -5 },
		"map kosong":          func(s *State) { s.Map = "" },
		"posisi negatif":      func(s *State) { s.X = -1 },
		"item tanpa id":       func(s *State) { s.Inventory = []Item{{ID: "", Qty: 1}} },
		"qty nol":             func(s *State) { s.Inventory = []Item{{ID: "potion", Qty: 0}} },
		"qty kebanyakan":      func(s *State) { s.Inventory = []Item{{ID: "potion", Qty: MaxStack + 1}} },
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			s := NewState()
			mutate(&s)
			if err := s.Validate(); err == nil {
				t.Fatal("seharusnya ditolak")
			}
		})
	}
}
