AS := ca65
LD := ld65

# Kazdy modul otrzymuje listing .lst z adresami i kodem maszynowym. Jest on
# przydatny przy analizie w monitorze Atari800, a plik .lbl nadaje symboliczne
# nazwy breakpointom. Gotowy XEX powstaje dopiero po przejsciu mapy linkera.
TARGET := build/sector-copy-u1.xex
MAP := build/sector-copy-u1.map
LABELS := build/sector-copy-u1.lbl
CFG := cfg/sector-copy-u1.cfg
DIAG_TARGET := build/xf551-density-diagnostic.xex
DIAG_MAP := build/xf551-density-diagnostic.map
DIAG_LABELS := build/xf551-density-diagnostic.lbl
DIAG_OBJECT := build/xf551_density.o
DIAG_CFG := cfg/xf551-density.cfg

SOURCES := \
	src/hsio_blob.s \
	src/main.s \
	src/ui.s \
	src/sio.s \
	src/geometry.s \
	src/memory.s \
	src/buffer.s \
	src/copy.s

OBJECTS := $(SOURCES:src/%.s=build/%.o)

.PHONY: all clean diagnostic test

all: $(TARGET)

diagnostic: $(DIAG_TARGET)

build:
	mkdir -p build

build/%.o: src/%.s src/os.inc src/hsio-1.33-3985-max8.bin | build
	# -g zachowuje symbole debuggera; -I src pozwala wspoldzielic os.inc.
	$(AS) --cpu 6502 -g -I src -l build/$*.lst -o $@ $<

$(DIAG_OBJECT): diagnostics/xf551_density.s src/os.inc | build
	$(AS) --cpu 6502 -g -I src -l build/xf551_density.lst -o $@ $<

$(TARGET): $(OBJECTS) $(CFG)
	$(LD) -C $(CFG) -m $(MAP) -Ln $(LABELS) -o $@ $(OBJECTS)

$(DIAG_TARGET): $(DIAG_OBJECT) build/hsio_blob.o build/ui.o build/sio.o $(DIAG_CFG)
	$(LD) -C $(DIAG_CFG) -m $(DIAG_MAP) -Ln $(DIAG_LABELS) -o $@ \
		$(DIAG_OBJECT) build/hsio_blob.o build/ui.o build/sio.o

test: $(TARGET) $(DIAG_TARGET)
	# Trzy poziomy kontroli: struktura XEX, fizyczna mapa Atari oraz algorytmy
	# i niezmienniki zrodel (m.in. zakaz powrotu do systemowego SIOV).
	python3 tools/check_xex.py $(TARGET)
	python3 tools/check_xex.py $(DIAG_TARGET)
	python3 tools/check_memory_map.py $(MAP)
	python3 tools/test_algorithms.py

clean:
	rm -f build/*.o build/*.lst build/*.map build/*.lbl build/*.xex
