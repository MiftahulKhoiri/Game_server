package game

import (
	"errors"
	"strings"
)

// Daftar teman (roadmap no. 176, v0.79.0): nama pemain lain yang disimpan untuk dipilih cepat sebagai tujuan
// dagang. Server memastikan nama itu ada sebelum memanggil AddFriend (lihat api).

const (
	MaxFriends    = 30
	MaxFriendName = 64
)

var (
	ErrFriendSelf  = errors.New("tidak bisa berteman dengan diri sendiri")
	ErrFriendsFull = errors.New("daftar teman sudah penuh")
	ErrFriendDup   = errors.New("pemain itu sudah ada di daftar teman")
	ErrNotFriend   = errors.New("pemain itu tidak ada di daftar teman")
)

func (s State) friendIndex(name string) int {
	for i, f := range s.Friends {
		if strings.EqualFold(f, name) {
			return i
		}
	}
	return -1
}

// AddFriend menambah `name` (nama asli dari database) ke daftar teman. self = nama pemain ini.
func (s *State) AddFriend(name, self string) error {
	switch {
	case strings.EqualFold(name, self):
		return ErrFriendSelf
	case s.friendIndex(name) >= 0:
		return ErrFriendDup
	case len(s.Friends) >= MaxFriends:
		return ErrFriendsFull
	}
	s.Friends = append(s.Friends, name)
	return nil
}

// RemoveFriend membuang `name` dari daftar teman.
func (s *State) RemoveFriend(name string) error {
	i := s.friendIndex(name)
	if i < 0 {
		return ErrNotFriend
	}
	s.Friends = append(s.Friends[:i:i], s.Friends[i+1:]...)
	if len(s.Friends) == 0 {
		s.Friends = nil
	}
	return nil
}

// validFriends: daftar teman tersimpan masuk akal.
func (s State) validFriends() bool {
	if len(s.Friends) > MaxFriends {
		return false
	}
	for i, f := range s.Friends {
		if f == "" || len(f) > MaxFriendName {
			return false
		}
		for _, g := range s.Friends[:i] {
			if strings.EqualFold(f, g) {
				return false
			}
		}
	}
	return true
}
