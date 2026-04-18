CRYSTAL_COMPILER := crystal
SOURCE_DIR := src
SOURCE_FILE := traffic
BUILD_DIR := build
BIN_DIR := bin
LIB_DIR := lib
SDL3_MIXER_LIB_DIR := /usr/local/lib
LINKFLAGS := -L$(SDL3_MIXER_LIB_DIR) -Wl,-rpath,$(SDL3_MIXER_LIB_DIR)
RM_CMD := rm -rf
MKDIR_CMD := mkdir -p
PACKER_FILE := build/assets.pack
PACKER_BIN := bin/gsdl-packer
APP_NAME := "Template Game SDL"
GAME_NAME := traffic
GAME_SRC := src/traffic.cr

FLAGS ?=

DEBUG_BIN := $(BUILD_DIR)/$(SOURCE_FILE)_debug
RELEASE_BIN := $(BUILD_DIR)/$(SOURCE_FILE)
SOURCES := $(shell find $(SOURCE_DIR) -name "*.cr")

# Phony targets don't represent files
.PHONY: default build run packer pack build-release run-release clean re release-package release-package-mac release-package-win release-package-linux

# The default target, executed when you just run `make`
default: run

re:
	@$(MAKE) -B run

$(DEBUG_BIN): $(SOURCES)
	@echo "Building $@..."
	$(MKDIR_CMD) $(BUILD_DIR)
	$(CRYSTAL_COMPILER) build $(SOURCE_DIR)/$(SOURCE_FILE).cr -o $@ --link-flags "$(LINKFLAGS)" -p $(FLAGS)
	@echo

build: $(DEBUG_BIN)

run: $(DEBUG_BIN)
	@echo "Running..."
	./$(DEBUG_BIN)
	@echo

$(RELEASE_BIN): $(SOURCES) $(PACKER_FILE)
	@echo "Building release $@..."
	$(MKDIR_CMD) $(BUILD_DIR)
	$(CRYSTAL_COMPILER) build $(SOURCE_DIR)/$(SOURCE_FILE).cr -o $@ --release --link-flags "$(LINKFLAGS)" --no-debug -p $(FLAGS)
	@echo

build-release: $(RELEASE_BIN)

run-release: $(RELEASE_BIN)
	@echo "Running release..."
	./$(RELEASE_BIN)
	@echo

$(PACKER_BIN):
	@echo "Building packer tool..."
	$(MKDIR_CMD) $(BIN_DIR)
	$(CRYSTAL_COMPILER) build lib/game_sdl/src/packer.cr -o $(BIN_DIR)/gsdl-packer --release --no-debug -p $(FLAGS)
	@echo

packer: $(PACKER_BIN)

$(PACKER_FILE): $(PACKER_BIN)
	@echo "Packing assets via GameSDL packer..."
	./$(PACKER_BIN)
	@echo

pack: $(PACKER_FILE)

clean:
	@echo "Executing clean..."
	$(RM_CMD) $(BIN_DIR)
	$(RM_CMD) $(BUILD_DIR)
	@echo

release-package:
	@echo "Creating release package for $(GAME_NAME) (target: $(TARGET))..."
	mkdir -p build
	crystal run lib/game_sdl/src/gsdl/release_helper.cr -- \
		$(if $(GAME_NAME),--game=$(GAME_NAME)) \
		--src=$(if $(SRC),$(SRC),$(GAME_SRC)) \
		--target=$(TARGET) \
		--name=$(if $(APP_NAME),$(APP_NAME),$(GAME_NAME)) \
		$(if $(VERSION),--version=$(VERSION)) \
		$(if $(ICON),--icon=$(ICON)) \
		$(if $(BUNDLE_ID),--bundle-id=$(BUNDLE_ID)) \
		$(if $(OUTPUT),--output=$(OUTPUT))

release-package-mac:
	@$(MAKE) release-package TARGET=mac

release-package-win:
	@$(MAKE) release-package TARGET=win

release-package-linux:
	@$(MAKE) release-package TARGET=linux
