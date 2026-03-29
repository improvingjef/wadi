OCAML ?= ocaml
OCAMLC ?= ocamlc
OCAMLOPT ?= ocamlopt
OCAMLFIND ?= ocamlfind
OCAMLFLAGS ?= -g

BUILD_DIR := _bootstrap
OBJ_DIR := $(BUILD_DIR)/obj
BIN_DIR := $(BUILD_DIR)/bin
BOOTSTRAP_MANIFEST := oasis.toml
BOOTSTRAP_GENERATOR := scripts/generate_bootstrap_makefile.ml
BOOTSTRAP_MK := $(BUILD_DIR)/bootstrap.generated.mk
BOOTSTRAP_SOURCES := $(wildcard src/*.ml src/*.mli test/*.ml test/*.mli)

.PHONY: all test clean bootstrap-smoke

all: $(BIN_DIR)/oasis

bootstrap-smoke:
	rm -rf $(BUILD_DIR)
	$(MAKE) $(BIN_DIR)/oasis $(BIN_DIR)/test_runner

test: bootstrap-smoke $(BIN_DIR)/oasis $(BIN_DIR)/test_runner
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) $(BIN_DIR)/test_runner

clean:
	rm -rf $(BUILD_DIR)

$(BUILD_DIR) $(OBJ_DIR) $(BIN_DIR):
	mkdir -p $@

$(BOOTSTRAP_MK): $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_SOURCES) | $(BUILD_DIR)
	$(OCAML) $(BOOTSTRAP_GENERATOR) --manifest $(BOOTSTRAP_MANIFEST) > $@

ifeq ($(filter clean,$(MAKECMDGOALS)),)
BOOTSTRAP_BACKEND ?= $(or $(OASIS_BACKEND),auto)
BOOTSTRAP_NATIVE_OK := $(shell $(OCAMLOPT) -version >/dev/null 2>&1 && printf yes)
BOOTSTRAP_BYTECODE_OK := $(shell $(OCAMLC) -version >/dev/null 2>&1 && printf yes)

ifeq ($(BOOTSTRAP_BACKEND),native)
ifeq ($(BOOTSTRAP_NATIVE_OK),)
$(error BOOTSTRAP_BACKEND=native requested but $(OCAMLOPT) is unavailable)
endif
RESOLVED_BOOTSTRAP_BACKEND := native
else ifeq ($(BOOTSTRAP_BACKEND),bytecode)
ifeq ($(BOOTSTRAP_BYTECODE_OK),)
$(error BOOTSTRAP_BACKEND=bytecode requested but $(OCAMLC) is unavailable)
endif
RESOLVED_BOOTSTRAP_BACKEND := bytecode
else ifeq ($(BOOTSTRAP_BACKEND),auto)
ifeq ($(BOOTSTRAP_NATIVE_OK),yes)
RESOLVED_BOOTSTRAP_BACKEND := native
else ifeq ($(BOOTSTRAP_BYTECODE_OK),yes)
RESOLVED_BOOTSTRAP_BACKEND := bytecode
else
$(error no working OCaml compiler found for bootstrap)
endif
else
$(error unknown BOOTSTRAP_BACKEND '$(BOOTSTRAP_BACKEND)'; expected auto, native, or bytecode)
endif

ifeq ($(RESOLVED_BOOTSTRAP_BACKEND),native)
BOOTSTRAP_COMPILER := $(OCAMLOPT)
BOOTSTRAP_COMPILER_KIND := ocamlopt
OBJ_EXT := cmx
else
BOOTSTRAP_COMPILER := $(OCAMLC)
BOOTSTRAP_COMPILER_KIND := ocamlc
OBJ_EXT := cmo
endif

define BOOTSTRAP_TOOL_CMD
$(if $(strip $(1)),$(OCAMLFIND) $(BOOTSTRAP_COMPILER_KIND) $(1),$(BOOTSTRAP_COMPILER))
endef

-include $(BOOTSTRAP_MK)
endif
