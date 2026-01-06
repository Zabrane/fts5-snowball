# fts5-snowball Makefile
# Snowball stemmer tokenizer for SQLite FTS5
#
# Supports: Linux, macOS (x86_64, arm64), Windows
#
# Usage:
#   make                    # Build for current platform
#   make compile-macos-arm64 # Build specifically for macOS ARM64
#   make clean              # Clean build artifacts
#   make test               # Test with sqlite3 CLI

SQLITE_VERSION = 3510100
SQLITE_YEAR = 2025
SQLITE_URL = https://www.sqlite.org/$(SQLITE_YEAR)/sqlite-amalgamation-$(SQLITE_VERSION).zip

# Directories
SQLITE_DIR = sqlite
SNOWBALL_DIR = snowball
SRC_DIR = src
DIST_DIR = dist

# Output
OUTPUT_NAME = fts5stemmer

# Detect OS
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

.PHONY: all clean test libstemmer download-sqlite prepare-dirs

# Default target
all: prepare-dirs download-sqlite libstemmer compile

prepare-dirs:
	@mkdir -p $(SQLITE_DIR)
	@mkdir -p $(DIST_DIR)

# Download SQLite amalgamation headers
download-sqlite:
	@if [ ! -f $(SQLITE_DIR)/sqlite3.h ]; then \
		echo "Downloading SQLite $(SQLITE_VERSION) headers..."; \
		curl -L $(SQLITE_URL) --output sqlite3.zip; \
		unzip -o sqlite3.zip; \
		mv sqlite-amalgamation-$(SQLITE_VERSION)/* $(SQLITE_DIR)/; \
		rm -rf sqlite-amalgamation-$(SQLITE_VERSION) sqlite3.zip; \
	else \
		echo "SQLite headers already present"; \
	fi

# Build libstemmer
libstemmer:
	@if [ ! -f $(SNOWBALL_DIR)/GNUmakefile ]; then \
		echo ""; \
		echo "Error: snowball is missing!"; \
		echo "Please run: git submodule update --init"; \
		echo "Or download from: https://github.com/snowballstem/snowball"; \
		echo ""; \
		exit 2; \
	fi
	$(MAKE) CFLAGS="-fPIC" -C $(SNOWBALL_DIR)

# Compile fts5stemmer.o
fts5stemmer.o: $(SRC_DIR)/fts5stemmer.c
	cc -fPIC -Wall -c \
		-I $(SQLITE_DIR) \
		-I $(SNOWBALL_DIR)/include \
		-O3 \
		$(SRC_DIR)/fts5stemmer.c

# Auto-detect and compile for current platform
compile: fts5stemmer.o
ifeq ($(UNAME_S),Darwin)
ifeq ($(UNAME_M),arm64)
	$(MAKE) link-macos-arm64
else
	$(MAKE) link-macos-x86
endif
else ifeq ($(UNAME_S),Linux)
	$(MAKE) link-linux
else
	@echo "Unknown platform: $(UNAME_S)"
	@exit 1
endif

# ============================================================
# Linux
# ============================================================

link-linux:
	cc -fPIC -shared \
		-o $(DIST_DIR)/$(OUTPUT_NAME).so \
		fts5stemmer.o \
		$(SNOWBALL_DIR)/libstemmer.a
	@echo ""
	@echo "Built: $(DIST_DIR)/$(OUTPUT_NAME).so"

compile-linux: prepare-dirs download-sqlite libstemmer fts5stemmer.o link-linux

# ============================================================
# macOS ARM64 (Apple Silicon)
# ============================================================

link-macos-arm64:
	cc -fPIC -dynamiclib \
		-target arm64-apple-macos11 \
		-o $(DIST_DIR)/$(OUTPUT_NAME).dylib \
		fts5stemmer.o \
		$(SNOWBALL_DIR)/libstemmer.a
	@echo ""
	@echo "Built: $(DIST_DIR)/$(OUTPUT_NAME).dylib (arm64)"

compile-macos-arm64: prepare-dirs download-sqlite
	$(MAKE) CFLAGS="-fPIC -target arm64-apple-macos11" -C $(SNOWBALL_DIR) clean
	$(MAKE) CFLAGS="-fPIC -target arm64-apple-macos11" -C $(SNOWBALL_DIR)
	cc -fPIC -Wall -c \
		-target arm64-apple-macos11 \
		-I $(SQLITE_DIR) \
		-I $(SNOWBALL_DIR)/include \
		-O3 \
		$(SRC_DIR)/fts5stemmer.c
	$(MAKE) link-macos-arm64

# ============================================================
# macOS x86_64 (Intel)
# ============================================================

link-macos-x86:
	cc -fPIC -dynamiclib \
		-target x86_64-apple-macos10.12 \
		-o $(DIST_DIR)/$(OUTPUT_NAME)-x86.dylib \
		fts5stemmer.o \
		$(SNOWBALL_DIR)/libstemmer.a
	@echo ""
	@echo "Built: $(DIST_DIR)/$(OUTPUT_NAME)-x86.dylib (x86_64)"

compile-macos-x86: prepare-dirs download-sqlite
	$(MAKE) CFLAGS="-fPIC -target x86_64-apple-macos10.12" -C $(SNOWBALL_DIR) clean
	$(MAKE) CFLAGS="-fPIC -target x86_64-apple-macos10.12" -C $(SNOWBALL_DIR)
	cc -fPIC -Wall -c \
		-target x86_64-apple-macos10.12 \
		-I $(SQLITE_DIR) \
		-I $(SNOWBALL_DIR)/include \
		-O3 \
		$(SRC_DIR)/fts5stemmer.c
	$(MAKE) link-macos-x86

# ============================================================
# macOS Universal (arm64 + x86_64)
# ============================================================

compile-macos-universal: compile-macos-arm64
	@mv $(DIST_DIR)/$(OUTPUT_NAME).dylib $(DIST_DIR)/$(OUTPUT_NAME)-arm64.dylib
	$(MAKE) compile-macos-x86
	lipo -create \
		-output $(DIST_DIR)/$(OUTPUT_NAME).dylib \
		$(DIST_DIR)/$(OUTPUT_NAME)-arm64.dylib \
		$(DIST_DIR)/$(OUTPUT_NAME)-x86.dylib
	@echo ""
	@echo "Built: $(DIST_DIR)/$(OUTPUT_NAME).dylib (universal)"

# ============================================================
# Windows (requires MinGW)
# ============================================================

compile-windows: prepare-dirs download-sqlite libstemmer
	cc -fPIC -Wall -c \
		-I $(SQLITE_DIR) \
		-I $(SNOWBALL_DIR)/include \
		-O3 \
		$(SRC_DIR)/fts5stemmer.c
	cc -shared \
		-o $(DIST_DIR)/$(OUTPUT_NAME).dll \
		fts5stemmer.o \
		$(SNOWBALL_DIR)/libstemmer.a
	@echo ""
	@echo "Built: $(DIST_DIR)/$(OUTPUT_NAME).dll"

# ============================================================
# Test
# ============================================================

test:
ifeq ($(UNAME_S),Darwin)
	@echo "Testing with sqlite3 CLI..."
	@sqlite3 <<< ".load $(DIST_DIR)/$(OUTPUT_NAME)" && echo "Load: OK" || echo "Load: FAILED"
	@sqlite3 <<< "\
		.load $(DIST_DIR)/$(OUTPUT_NAME) \n\
		CREATE VIRTUAL TABLE test USING fts5(x, tokenize='snowball french'); \n\
		INSERT INTO test VALUES ('Un roman français'); \n\
		SELECT * FROM test WHERE test MATCH 'romans'; \n\
	" && echo "French stemming: OK" || echo "French stemming: FAILED"
	@sqlite3 <<< "\
		.load $(DIST_DIR)/$(OUTPUT_NAME) \n\
		CREATE VIRTUAL TABLE test_ar USING fts5(x, tokenize='snowball arabic'); \n\
		INSERT INTO test_ar VALUES ('كتاب الأطفال'); \n\
		SELECT * FROM test_ar WHERE test_ar MATCH 'أطفال'; \n\
	" && echo "Arabic stemming: OK" || echo "Arabic stemming: FAILED"
else
	@echo "Testing with sqlite3 CLI..."
	@echo ".load $(DIST_DIR)/$(OUTPUT_NAME)" | sqlite3 && echo "Load: OK" || echo "Load: FAILED"
endif

# ============================================================
# Clean
# ============================================================

clean:
	rm -f *.o
	rm -rf $(DIST_DIR)
	rm -rf $(SQLITE_DIR)
	-$(MAKE) -C $(SNOWBALL_DIR) clean 2>/dev/null || true

clean-all: clean
	rm -rf $(SNOWBALL_DIR)

# ============================================================
# Help
# ============================================================

help:
	@echo "fts5-snowball Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all                   - Build for current platform (default)"
	@echo "  compile-linux         - Build for Linux"
	@echo "  compile-macos-arm64   - Build for macOS ARM64 (Apple Silicon)"
	@echo "  compile-macos-x86     - Build for macOS x86_64 (Intel)"
	@echo "  compile-macos-universal - Build universal binary for macOS"
	@echo "  compile-windows       - Build for Windows (MinGW)"
	@echo "  test                  - Test with sqlite3 CLI"
	@echo "  clean                 - Remove build artifacts"
	@echo "  clean-all             - Remove everything including snowball"
	@echo ""
	@echo "Supported languages: arabic, basque, catalan, danish, dutch,"
	@echo "  english, finnish, french, german, greek, hindi, hungarian,"
	@echo "  indonesian, irish, italian, lithuanian, nepali, norwegian,"
	@echo "  porter, portuguese, romanian, russian, serbian, spanish,"
	@echo "  swedish, tamil, turkish"
	@echo ""
	@echo "Usage in SQLite:"
	@echo "  .load /path/to/fts5stemmer"
	@echo "  CREATE VIRTUAL TABLE t USING fts5(text, tokenize='snowball french arabic');"
