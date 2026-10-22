PREFIX ?= $(HOME)/.local

.PHONY: build test test-distribution run install uninstall package
build:
	swift build -c release
	@set -eu; \
	stage="$$(mktemp ./tawl.build.XXXXXX)"; \
	trap 'rm -f "$$stage"' EXIT; \
	cp "$$(swift build -c release --show-bin-path)/tawl" "$$stage"; \
	chmod 755 "$$stage"; \
	mv -f "$$stage" ./tawl

test:
	swift test

test-distribution:
	python3 -m unittest discover -s Tests/Distribution -v

run: build
	./tawl

install: build
	./scripts/install.sh --prefix "$(PREFIX)" --binary ./tawl

uninstall:
	./scripts/uninstall.sh --prefix "$(PREFIX)"

package: build
	./scripts/package-release.sh --binary ./tawl --output ./work/release
