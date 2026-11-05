.PHONY: build run test vet fmt check clean

BIN := bin/gameserver

build:
	go build -o $(BIN) ./cmd/gameserver

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

clean:
	rm -rf bin
