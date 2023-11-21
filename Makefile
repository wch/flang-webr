ROOT = $(abspath .)
BUILD = $(ROOT)/build
SOURCE = $(ROOT)/llvm-project
PREFIX = $(ROOT)

HOST = $(PREFIX)/host
WASM = $(PREFIX)/wasm

FLANG_BIN = $(BUILD)/bin/flang-new

RUNTIME_SOURCES := $(wildcard $(SOURCE)/flang/runtime/*.cpp)
RUNTIME_SOURCES += $(SOURCE)/flang/lib/Decimal/decimal-to-binary.cpp
RUNTIME_SOURCES += $(SOURCE)/flang/lib/Decimal/binary-to-decimal.cpp
RUNTIME_OBJECTS = $(patsubst $(SOURCE)/%,$(BUILD)/%,$(RUNTIME_SOURCES:.cpp=.o))
RUNTIME_LIB = $(BUILD)/flang/runtime/libFortranRuntime.a

FLANG_WASM_CMAKE_VARS := $(FLANG_WASM_CMAKE_VARS)

.PHONY: all
all: $(FLANG_BIN) $(RUNTIME_LIB)

$(SOURCE):
	git clone --single-branch -b webr --depth=1 https://github.com/georgestagg/llvm-project

$(FLANG_BIN): $(SOURCE)
	@mkdir -p $(BUILD)
	cmake -G Ninja -S $(SOURCE)/llvm -B $(BUILD) \
	  -DCMAKE_INSTALL_PREFIX=$(HOST) \
	  -DCMAKE_BUILD_TYPE=MinSizeRel \
	  -DCMAKE_C_COMPILER=clang \
	  -DCMAKE_CXX_COMPILER=clang++ \
	  -DLLVM_DEFAULT_TARGET_TRIPLE="wasm32-unknown-emscripten" \
	  -DLLVM_TARGETS_TO_BUILD="WebAssembly" \
	  -DLLVM_ENABLE_PROJECTS="clang;flang;mlir" \
	  -DLLVM_USE_LINKER=lld \
	  $(FLANG_WASM_CMAKE_VARS)
	TERM=dumb cmake --build $(BUILD)

.PHONY: wasm-runtime
wasm-runtime: $(FLANG_BIN) $(RUNTIME_LIB)

RUNTIME_CXXFLAGS := $(RUNTIME_CXXFLAGS)
RUNTIME_CXXFLAGS += -I$(BUILD)/include -I$(BUILD)/tools/flang/runtime
RUNTIME_CXXFLAGS += -I$(SOURCE)/flang/include -I$(SOURCE)/llvm/include
RUNTIME_CXXFLAGS += -DFLANG_LITTLE_ENDIAN
RUNTIME_CXXFLAGS += -fPIC -Wno-c++11-narrowing -fvisibility=hidden
RUNTIME_CXXFLAGS += -DFE_UNDERFLOW=0 -DFE_OVERFLOW=0 -DFE_INEXACT=0
RUNTIME_CXXFLAGS += -DFE_INVALID=0 -DFE_DIVBYZERO=0 -DFE_ALL_EXCEPT=0

$(RUNTIME_LIB): $(RUNTIME_OBJECTS)
	@rm -f $@
	emar -rcs $@ $^

$(BUILD)%.o : $(SOURCE)%.cpp
	@mkdir -p $(@D)
	em++ $(RUNTIME_CXXFLAGS) -o $@ -c $<

.PHONY: install
install: $(FLANG_BIN) $(RUNTIME_LIB)
	install -D -t $(HOST)/bin -m 755 $(FLANG_BIN)
	install -D -t $(WASM)/lib -m 644 $(RUNTIME_LIB)

.PHONY: check
check:
	cmake --build $(BUILD) --target check-all

.PHONY: clean
clean:
	cmake --build $(BUILD) --target clean

.PHONY: clean-all
clean-all:
	rm -rf $(SOURCE) $(BUILD)
