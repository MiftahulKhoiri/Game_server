.PHONY: build run test vet fmt check client-test patch install-user-service restart clean

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

vet:
	go vet ./...

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

# Pasang server sebagai layanan pengguna systemd (tanpa sudo), lalu nyalakan.
install-user-service: build
	mkdir -p $(HOME)/.config/systemd/user
	cp deploy/gameserver.user.service $(HOME)/.config/systemd/user/gameserver.service
	systemctl --user daemon-reload
	systemctl --user enable --now gameserver

# Bangun ulang lalu mulai ulang layanan (setelah mengubah kode server).
restart: build
	systemctl --user restart gameserver

clean:
	rm -rf bin
