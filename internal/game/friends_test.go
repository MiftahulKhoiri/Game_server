package game

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
)

func TestFriendsRules(t *testing.T) {
	st := NewState()
	if err := st.AddFriend("Sekar", "sekar"); err != ErrFriendSelf {
		t.Fatalf("diri sendiri: %v", err)
	}
	if err := st.AddFriend("Bayu", "Sekar"); err != nil {
		t.Fatal(err)
	}
	if err := st.AddFriend("BAYU", "Sekar"); err != ErrFriendDup {
		t.Fatalf("kembar: %v", err)
	}
	for i := len(st.Friends); i < MaxFriends; i++ {
		if err := st.AddFriend(fmt.Sprintf("P%d", i), "Sekar"); err != nil {
			t.Fatal(err)
		}
	}
	if err := st.AddFriend("Lebih", "Sekar"); err != ErrFriendsFull {
		t.Fatalf("penuh: %v", err)
	}
	if err := st.Validate(); err != nil {
		t.Fatalf("daftar penuh tetap sah: %v", err)
	}
	if err := st.RemoveFriend("bayu"); err != nil || st.friendIndex("Bayu") >= 0 {
		t.Fatalf("hapus: %v %v", err, st.Friends)
	}
	if err := st.RemoveFriend("bayu"); err != ErrNotFriend {
		t.Fatalf("hapus lagi: %v", err)
	}
}

func TestFriendsValidateAndCompat(t *testing.T) {
	raw, _ := json.Marshal(NewState())
	if strings.Contains(string(raw), "friends") {
		t.Fatal("state baru menulis friends")
	}
	for _, bad := range [][]string{{""}, {"A", "a"}, {strings.Repeat("x", MaxFriendName+1)}} {
		st := NewState()
		st.Friends = bad
		if st.Validate() == nil {
			t.Errorf("%q dianggap sah", bad)
		}
	}
}
