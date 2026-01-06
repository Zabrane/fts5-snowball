SQLITE_FLAGS=`pkg-config --cflags --silence-errors sqlite3`

all: libstemmer fts5stemmer.o
	@if [ "`uname -s`" = "Darwin" ]; then \
		cc -fPIC -dynamiclib -undefined dynamic_lookup -o fts5stemmer.dylib fts5stemmer.o snowball/libstemmer.a; \
	else \
		cc -fPIC -shared -o fts5stemmer.so fts5stemmer.o snowball/libstemmer.a; \
	fi

libstemmer:
	@if [ ! -f snowball/GNUmakefile ];then \
		echo -e "\n\nError: snowball is missing! Please put it's source code in a directory called 'snowball'"; \
		echo -e "Head to https://github.com/snowballstem/snowball to fetch it\n"; \
		exit 2; \
	fi

	$(MAKE) CFLAGS=-fPIC -C snowball

fts5stemmer.o: src/fts5stemmer.c
	cc -fPIC -Wall -c $(SQLITE_FLAGS) -Isnowball/include -Isqlite -O3 src/fts5stemmer.c

clean:
	@rm *.o
	$(MAKE) -C snowball clean
