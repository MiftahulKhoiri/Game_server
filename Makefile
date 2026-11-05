.PHONY: build run test vet fmt check client-test clean

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
client-test:
	GODOT=$(GODOT) bash scripts/client-test.sh

clean:
	rm -rf bin
