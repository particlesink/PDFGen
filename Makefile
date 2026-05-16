CC       ?= gcc
CFLAGS    = -g -Wall -Werror -pipe --std=c23 -O2 -pedantic
LFLAGS    = -lm
XXD       = xxd

ifeq ($(OS),Windows_NT)
  CFLAGS += -D__USE_MINGW_ANSI_STDIO=1
  EXE     = .exe
else
  CFLAGS += -fprofile-arcs -ftest-coverage
  LFLAGS += -fprofile-arcs -ftest-coverage
  EXE     =
endif

TESTPROG = testprog$(EXE)

default: $(TESTPROG) tests/massive-file$(EXE)

$(TESTPROG): pdfgen.o tests/main.o tests/penguin.o tests/rgb.o
	$(CC) -o $@ $^ $(LFLAGS)

tests/massive-file$(EXE): tests/massive-file.c pdfgen.c
	$(CC) -I. -g -o $@ $< pdfgen.c $(LFLAGS)
tests/fuzz-dstr: tests/fuzz-dstr.c pdfgen.c
	$(CC) -I. -g -o $@ $< -fsanitize=fuzzer,address,undefined,integer
tests/fuzz-%: tests/fuzz-%.c pdfgen.c
	$(CC) -I. -g -o $@ $< pdfgen.c -fsanitize=fuzzer,address,undefined,integer
tests/penguin.c: data/penguin.jpg
	# Convert data/penguin.jpg to a C source file with binary data in a variable
	$(XXD) -i $< > $@ || ( rm -f $@ ; false )

%.o: %.c
	$(CC) -I. $(CFLAGS) -c $< -o $@
%$(O_SUFFIX): %.c
	$(CC) -I. -c $< $(CFLAGS_OBJECT) $@ $(CFLAGS)

check: $(TESTPROG) pdfgen.c pdfgen.h example-check
	cppcheck --std=c99 --enable=style,warning,performance,portability,unusedFunction --quiet pdfgen.c pdfgen.h tests/main.c
	$(CXX) -c pdfgen.c $(CFLAGS_OBJECT) /dev/null -Werror -Wall -Wextra
	./tests/tests.sh
	$(CLANG_FORMAT) pdfgen.c | colordiff -u pdfgen.c -
	$(CLANG_FORMAT) pdfgen.h | colordiff -u pdfgen.h -
	$(CLANG_FORMAT) tests/main.c | colordiff -u tests/main.c -
	gcov -r pdfgen.c

coverage: $(TESTPROG)
	./testprog
	rm -rf coverage-html
	mkdir coverage-html
	gcovr -r . --html --html-details -o coverage-html/coverage.html

example-check:
	# Extract the code block from the README & make sure it compiles
	sed -n '/^```/,/^```/ p' < README.md | sed '/^```/ d' > example-check.c
	$(CC) $(CFLAGS) -o example-check example-check.c pdfgen.c $(LFLAGS)
	rm example-check example-check.c

check-fuzz-%: tests/fuzz-%
	mkdir -p fuzz-artifacts
	./$< -verbosity=0 -max_total_time=240 -max_len=8192 -rss_limit_mb=1024 -artifact_prefix="./fuzz-artifacts/"

fuzz-check: check-fuzz-image-data check-fuzz-image-file check-fuzz-header check-fuzz-text check-fuzz-dstr check-fuzz-barcode check-fuzz-ttf

format:
	$(CLANG_FORMAT) -i pdfgen.c pdfgen.h tests/main.c tests/fuzz-*.c tests/massive-file.c

docs:
	doxygen docs/pdfgen.dox 2>&1 | tee doxygen.log
	cat doxygen.log | test `wc -c` -le 0

podman-image:
	podman build -t pdfgen .

podman-build-win32: podman-image
	podman run --rm -v $(PWD):/src -w /src pdfgen bash -c 'make clean && make CC=x86_64-w64-mingw32-gcc'

podman-infer: podman-image
	podman run --rm -v $(PWD):/src -w /src pdfgen bash -c 'make clean && infer run --no-progress-bar -- make CFLAGS="-g -Wall -pipe" LFLAGS="-lm"'

podman-build: podman-image
	podman run --rm -v $(PWD):/src -w /src pdfgen bash -c 'make clean && make'

podman-test: podman-image
	podman run --rm -v $(PWD):/src -w /src pdfgen bash -c 'make clean && scan-build --status-bugs make check'

podman-check: podman-image
	podman run --rm -v $(PWD):/src -w /src pdfgen bash -c 'make clean && make check'

podman-fuzz-check: podman-image
	podman run --rm -v $(PWD):/src -w /src pdfgen bash -c 'make clean && make fuzz-check -j8'

podman-docs: podman-image
	podman run --rm -v $(PWD):/src -w /src pdfgen make docs

podman-coverage: podman-image
	podman run --rm -v $(PWD):/src -w /src -e COVERALLS_REPO_TOKEN=$(COVERALLS_REPO_TOKEN) -e GITHUB_REF=$(GITHUB_REF) pdfgen bash -c 'make clean && make coverage && if [ "$$(basename "$${GITHUB_REF:-none}")" = "master" ]; then ./testprog && coveralls -i pdfgen.c; fi'

podman-shell: podman-image
	podman run -i -t --rm -v $(PWD):/src -w /src pdfgen /bin/bash

.PHONY: default check coverage example-check fuzz-check format docs podman-image podman-build-win32 podman-infer podman-build podman-test podman-check podman-fuzz-check podman-docs podman-coverage podman-shell clean

clean:
	rm -f pdfgen.o tests/main.o tests/penguin.o tests/rgb.o
	rm -f $(TESTPROG) tests/massive-file$(EXE) tests/penguin.c
	rm -f *.gcda *.gcno *.gcov tests/*.gcda tests/*.gcno
	rm -f output.pdf output_encrypted.pdf output.txt output.ps output.ppm
	rm -rf docs/html docs/latex coverage-html

.PHONY: default clean