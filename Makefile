OCAML ?= ocaml
OCAMLC ?= ocamlc
OCAMLOPT ?= ocamlopt
OCAMLFLAGS ?= -g

STDLIB_DIR := $(shell $(OCAMLC) -where)
UNIX_DIR := $(shell if [ -e "$(STDLIB_DIR)/unix/unix.cmi" ]; then printf '%s\n' "$(STDLIB_DIR)/unix"; elif [ -e "$(STDLIB_DIR)/unix.cmi" ]; then printf '%s\n' "$(STDLIB_DIR)"; fi)
UNIX_FLAGS := $(if $(UNIX_DIR),-I $(UNIX_DIR),)
UNIX_ARCHIVE := $(if $(UNIX_DIR),$(UNIX_DIR)/unix.cmxa,unix.cmxa)

BUILD_DIR := _bootstrap
OBJ_DIR := $(BUILD_DIR)/obj
BIN_DIR := $(BUILD_DIR)/bin
BOOTSTRAP_MANIFEST := oasis.toml
BOOTSTRAP_GENERATOR := scripts/generate_bootstrap_makefile.ml
BOOTSTRAP_MK := $(BUILD_DIR)/bootstrap.generated.mk
BOOTSTRAP_SOURCES := $(wildcard src/*.ml src/*.mli test/*.ml test/*.mli)

.PHONY: all test clean

all: $(BIN_DIR)/oasis

test: $(BIN_DIR)/oasis $(BIN_DIR)/test_runner
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) $(BIN_DIR)/test_runner

clean:
	rm -rf $(BUILD_DIR)

$(BUILD_DIR) $(OBJ_DIR) $(BIN_DIR):
	mkdir -p $@

$(BOOTSTRAP_MK): $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_SOURCES) | $(BUILD_DIR)
	$(OCAML) $(BOOTSTRAP_GENERATOR) --manifest $(BOOTSTRAP_MANIFEST) > $@

ifeq ($(filter clean,$(MAKECMDGOALS)),)
-include $(BOOTSTRAP_MK)
endif

$(OBJ_DIR)/%.cmx: src/%.ml $(BOOTSTRAP_MK) | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/%.cmx: test/%.ml $(BOOTSTRAP_MK) | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<
