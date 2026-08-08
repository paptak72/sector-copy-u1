AS := ca65
LD := ld65

# Kazdy modul otrzymuje listing .lst z adresami i kodem maszynowym. Jest on
# przydatny przy analizie w monitorze Atari800, a plik .lbl nadaje symboliczne
# nazwy breakpointom. Gotowy XEX powstaje dopiero po przejsciu mapy linkera.
TARGET := build/sector-copy-u1.xex
MAP := build/sector-copy-u1.map
LABELS := build/sector-copy-u1.lbl
CFG := cfg/sector-copy-u1.cfg

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

.PHONY: all clean test

all: $(TARGET)

build:
	mkdir -p build

build/%.o: src/%.s src/os.inc src/hsio-1.33-3985-max8.bin | build
	# -g zachowuje symbole debuggera; -I src pozwala wspoldzielic os.inc.
	$(AS) --cpu 6502 -g -I src -l build/$*.lst -o $@ $<

$(TARGET): $(OBJECTS) $(CFG)
	$(LD) -C $(CFG) -m $(MAP) -Ln $(LABELS) -o $@ $(OBJECTS)

test: $(TARGET)
	# Trzy poziomy kontroli: struktura XEX, fizyczna mapa Atari oraz algorytmy
	# i niezmienniki zrodel (m.in. zakaz powrotu do systemowego SIOV).
	python3 tools/check_xex.py $(TARGET)
	python3 tools/check_memory_map.py $(MAP)
	python3 tools/test_algorithms.py

clean:
	rm -f build/*.o build/*.lst build/*.map build/*.lbl build/*.xex
