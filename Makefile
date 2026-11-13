.PHONY: maps build run test vet fmt check client-test patch install-user-service install-backup-timer restart clean backup backup-all restore bench cover smoke test-all logs

BIN := bin/gameserver
GODOT ?= godot
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
LDFLAGS := -X github.com/MiftahulKhoiri/Game_server/internal/version.Commit=$(COMMIT)

build:
	go build -ldflags "$(LDFLAGS)" -o $(BIN) ./cmd/gameserver

run: build
	./$(BIN)

test:
	go test ./...

# Bentuk petak peta untuk server (internal/game/tiles_gen.go) dari client/scripts/maps.gd. Jalankan setiap kali
# peta di maps.gd berubah; TestTilesMatchClient gagal bila lupa.
maps:
	go run ./tools/genmaps

vet:
	go vet ./...

# Tolok ukur endpoint & database (roadmap no. 269).
bench:
	go test ./internal/... -run '^$$' -bench . -benchmem

# Cakupan tes per paket + total.
cover:
	go test ./... -coverprofile=coverage.out >/dev/null
	go tool cover -func=coverage.out | tail -n 1

fmt:
	gofmt -w .

# Dijalankan sebelum commit / PR, sama seperti CI.
check:
	@test -z "$$(gofmt -l .)" || (echo "Jalankan 'make fmt'"; gofmt -l .; exit 1)
	go vet ./...
	go test ./...

# Uji klien Godot <-> server. Butuh Godot 4.7:  make client-test GODOT=/path/ke/godot
# Patch isi game tanpa APK baru (lihat docs/PATCH.md). Butuh Godot 4.7:  make patch GODOT=/path/ke/godot
patch:
	GODOT=$(GODOT) bash scripts/build-patch.sh

client-test:
	GODOT=$(GODOT) bash scripts/client-test.sh

# Uji asap server yang sedang berjalan (hanya membaca):  make smoke [URL=http://ip:8090]
smoke:
	bash scripts/smoke-test.sh $(URL)

# Pengujian akhir lengkap (roadmap no. 275): server, klien, lalu uji asap server yang berjalan.
test-all: check client-test smoke

# Pasang server sebagai layanan pengguna systemd (tanpa sudo), lalu nyalakan.
install-user-service: build
	mkdir -p $(HOME)/.config/systemd/user
	cp deploy/gameserver.user.service $(HOME)/.config/systemd/user/gameserver.service
	systemctl --user daemon-reload
	systemctl --user enable --now gameserver

# Bangun ulang lalu mulai ulang layanan (setelah mengubah kode server).
restart: build
	systemctl --user restart gameserver

# Log server (layanan pengguna; "journalctl --user -u" tidak membaca jurnal pengguna di Pi ini).
logs:
	journalctl _SYSTEMD_USER_UNIT=gameserver.service -n 100 -f

backup:
	bash scripts/backup-db.sh

# Cadangan lengkap kode (git bundle) + database + patch ke ~/cadangan_game (atau BACKUP_DEST=...).
backup-all:
	bash scripts/backup-all.sh

# Jadwal mingguan untuk backup-all (systemd tingkat pengguna).
install-backup-timer:
	mkdir -p $(HOME)/.config/systemd/user
	cp deploy/gameserver-backup.service deploy/gameserver-backup.timer $(HOME)/.config/systemd/user/
	systemctl --user daemon-reload
	systemctl --user enable --now gameserver-backup.timer

restore:
	bash scripts/restore-db.sh $(FILE)

clean:
	rm -rf bin
