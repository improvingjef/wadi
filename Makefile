OCAML ?= ocaml
OCAMLC ?= ocamlc
OCAMLOPT ?= ocamlopt
OCAMLFIND ?= ocamlfind
OCAMLFLAGS ?= -g

BUILD_DIR := _bootstrap
OBJ_DIR := $(BUILD_DIR)/obj
SEED_OBJ_DIR := $(BUILD_DIR)/seed-obj
BIN_DIR := $(BUILD_DIR)/bin
BOOTSTRAP_MANIFEST := oasis.toml
BOOTSTRAP_GENERATOR := scripts/bootstrap_seed_main.ml
BOOTSTRAP_SOURCE_HELPER := scripts/render_bootstrap_mod_use.ml
BOOTSTRAP_HELPERS := $(BOOTSTRAP_SOURCE_HELPER)
BOOTSTRAP_SEED_BIN := $(BIN_DIR)/oasis-seed
BOOTSTRAP_PROFILE ?=
BOOTSTRAP_PROFILE_KEY := $(if $(strip $(BOOTSTRAP_PROFILE)),$(BOOTSTRAP_PROFILE),workspace-default)
BOOTSTRAP_APP_MK := $(BUILD_DIR)/bootstrap.$(BOOTSTRAP_PROFILE_KEY).app.generated.mk
BOOTSTRAP_FULL_MK := $(BUILD_DIR)/bootstrap.$(BOOTSTRAP_PROFILE_KEY).full.generated.mk

.PHONY: all test clean bootstrap-smoke release-artifacts

all: $(BIN_DIR)/oasis

bootstrap-smoke:
	rm -rf $(BUILD_DIR)
	$(MAKE) $(BIN_DIR)/oasis $(BIN_DIR)/test_runner

test: bootstrap-smoke $(BIN_DIR)/oasis $(BIN_DIR)/test_runner
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) $(BIN_DIR)/test_runner

release-artifacts: $(BIN_DIR)/oasis
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) bash scripts/generate_release_artifacts.sh

clean:
	rm -rf $(BUILD_DIR)

$(BUILD_DIR) $(OBJ_DIR) $(SEED_OBJ_DIR) $(BIN_DIR):
	mkdir -p $@

BOOTSTRAP_PROFILE_ARG = $(if $(strip $(BOOTSTRAP_PROFILE)),--profile $(BOOTSTRAP_PROFILE),)

ifeq ($(filter clean,$(MAKECMDGOALS)),)
BOOTSTRAP_INTERNAL_COMMAND := __bootstrap_makefile
BOOTSTRAP_SCOPE ?= auto
BOOTSTRAP_NEEDS_FULL := $(filter test bootstrap-smoke $(BIN_DIR)/test_runner,$(MAKECMDGOALS))

ifeq ($(BOOTSTRAP_SCOPE),app)
BOOTSTRAP_MK := $(BOOTSTRAP_APP_MK)
else ifeq ($(BOOTSTRAP_SCOPE),full)
BOOTSTRAP_MK := $(BOOTSTRAP_FULL_MK)
else
BOOTSTRAP_MK := $(if $(BOOTSTRAP_NEEDS_FULL),$(BOOTSTRAP_FULL_MK),$(BOOTSTRAP_APP_MK))
endif

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

BOOTSTRAP_LIBRARY_COMPILE_SOURCES := $(shell BOOTSTRAP_MODULE_MANIFEST=$(BOOTSTRAP_MANIFEST) $(OCAML) $(BOOTSTRAP_SOURCE_HELPER) --format compile-paths)
BOOTSTRAP_LIBRARY_PACKAGES := $(shell BOOTSTRAP_MODULE_MANIFEST=$(BOOTSTRAP_MANIFEST) $(OCAML) $(BOOTSTRAP_SOURCE_HELPER) --format packages)
BOOTSTRAP_LIBRARY_PACKAGE_FLAGS := $(addprefix -package ,$(BOOTSTRAP_LIBRARY_PACKAGES))
BOOTSTRAP_SEED_MAIN_OBJ := $(SEED_OBJ_DIR)/bootstrap_seed_main.$(OBJ_EXT)

$(BOOTSTRAP_SEED_BIN): $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_SOURCE_HELPER) $(BOOTSTRAP_LIBRARY_COMPILE_SOURCES) | $(SEED_OBJ_DIR) $(BIN_DIR)
	rm -f $(SEED_OBJ_DIR)/*.$(OBJ_EXT) $(SEED_OBJ_DIR)/*.cmi $(SEED_OBJ_DIR)/*.o
	set -eu; \
	objs=""; \
	for src in $(BOOTSTRAP_LIBRARY_COMPILE_SOURCES); do \
		base=$$(basename "$$src"); \
		stem=$${base%.*}; \
		ext=$${base##*.}; \
		if [ "$$ext" = "mli" ]; then \
			$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(SEED_OBJ_DIR) -c "$$src" -o $(SEED_OBJ_DIR)/$$stem.cmi; \
		else \
			$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(SEED_OBJ_DIR) -c "$$src" -o $(SEED_OBJ_DIR)/$$stem.$(OBJ_EXT); \
			objs="$$objs $(SEED_OBJ_DIR)/$$stem.$(OBJ_EXT)"; \
		fi; \
	done; \
	$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(SEED_OBJ_DIR) -c $(BOOTSTRAP_GENERATOR) -o $(BOOTSTRAP_SEED_MAIN_OBJ); \
	$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(SEED_OBJ_DIR) -linkpkg -o $@ $$objs $(BOOTSTRAP_SEED_MAIN_OBJ)

$(BOOTSTRAP_APP_MK): $(BOOTSTRAP_SEED_BIN) $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_HELPERS) | $(BUILD_DIR)
	tmp=$@.tmp; \
	$(BOOTSTRAP_SEED_BIN) --manifest $(BOOTSTRAP_MANIFEST) --scope app $(BOOTSTRAP_PROFILE_ARG) > $$tmp && mv $$tmp $@

$(BOOTSTRAP_FULL_MK): $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_HELPERS) | $(BUILD_DIR)
	$(MAKE) BOOTSTRAP_SCOPE=app $(BIN_DIR)/oasis
	tmp=$@.tmp; \
	$(BIN_DIR)/oasis $(BOOTSTRAP_INTERNAL_COMMAND) --manifest $(BOOTSTRAP_MANIFEST) --scope full $(BOOTSTRAP_PROFILE_ARG) > $$tmp && mv $$tmp $@

-include $(BOOTSTRAP_MK)
endif
