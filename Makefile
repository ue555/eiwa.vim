.PHONY: build build-all test

build:
	./scripts/build.sh

build-all:
	./scripts/build.sh --all

test: build
	CGO_ENABLED=0 go test ./...
	vim -es -N -u tests/minimal.vim -S tests/run.vim
