OCAML ?= ocaml
OCAMLC ?= ocamlc
OCAMLOPT ?= ocamlopt
OCAMLFIND ?= ocamlfind
OCAMLFLAGS ?= -g
OASIS_BIN ?= $(BIN_DIR)/oasis

BUILD_DIR := _bootstrap
OBJ_DIR := $(BUILD_DIR)/obj
SEED_OBJ_DIR := $(BUILD_DIR)/seed-obj
BIN_DIR := $(BUILD_DIR)/bin
BOOTSTRAP_MANIFEST := oasis.toml
BOOTSTRAP_METADATA_HELPER := scripts/render_bootstrap_mod_use.ml
BOOTSTRAP_GENERATOR := scripts/bootstrap_seed_main.ml
BOOTSTRAP_LEGACY_PLANNER := scripts/generate_bootstrap_makefile.ml
BOOTSTRAP_SHARED_OUTPUTS_HELPER := scripts/sync_bootstrap_shared_outputs.sh
BOOTSTRAP_INTERNAL_COMMAND := __bootstrap_makefile
BOOTSTRAP_SEED_METADATA := $(BUILD_DIR)/bootstrap.seed-metadata.mk
BOOTSTRAP_SEED_ROOT := $(BUILD_DIR)/seed
BOOTSTRAP_SEED_BIN := $(BIN_DIR)/oasis-seed
BOOTSTRAP_PROFILE ?=
BOOTSTRAP_PROFILE_KEY := $(if $(strip $(BOOTSTRAP_PROFILE)),$(BOOTSTRAP_PROFILE),workspace-default)
BOOTSTRAP_APP_MK := $(BUILD_DIR)/bootstrap.$(BOOTSTRAP_PROFILE_KEY).app.generated.mk
BOOTSTRAP_FULL_MK := $(BUILD_DIR)/bootstrap.$(BOOTSTRAP_PROFILE_KEY).full.generated.mk

.PHONY: all test clean bootstrap-smoke release-artifacts release-manifests sync-generated release-cut update-homebrew-tap benchmark-bootstrap refresh-bootstrap-seed-metadata FORCE

define REFRESH_BOOTSTRAP_SEED_METADATA
set -eu; \
tmp="$(BOOTSTRAP_SEED_METADATA).tmp"; \
if [ -x "$(OASIS_BIN)" ]; then \
	"$(OASIS_BIN)" $(BOOTSTRAP_INTERNAL_COMMAND) --manifest "$(BOOTSTRAP_MANIFEST)" --format seed-metadata --seed-root "$(BOOTSTRAP_SEED_ROOT)" > "$$tmp"; \
else \
	if "$(OCAML)" "$(BOOTSTRAP_METADATA_HELPER)" --manifest "$(BOOTSTRAP_MANIFEST)" --format seed-metadata --seed-root "$(BOOTSTRAP_SEED_ROOT)" > "$$tmp"; then \
		:; \
	else \
		rm -f "$$tmp"; \
		"$(OCAML)" "$(BOOTSTRAP_LEGACY_PLANNER)" --manifest "$(BOOTSTRAP_MANIFEST)" --format seed-metadata --seed-root "$(BOOTSTRAP_SEED_ROOT)" > "$$tmp"; \
	fi; \
fi; \
if [ -f "$(BOOTSTRAP_SEED_METADATA)" ] && cmp -s "$$tmp" "$(BOOTSTRAP_SEED_METADATA)"; then \
	rm -f "$$tmp"; \
else \
	mv "$$tmp" "$(BOOTSTRAP_SEED_METADATA)"; \
fi
endef

BOOTSTRAP_SKIP_SEED_METADATA_GOALS := clean refresh-bootstrap-seed-metadata release-manifests release-cut update-homebrew-tap

ifeq ($(filter $(BOOTSTRAP_SKIP_SEED_METADATA_GOALS),$(MAKECMDGOALS)),)
-include $(BOOTSTRAP_SEED_METADATA)
endif

FORCE:

$(BOOTSTRAP_SEED_METADATA): $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_METADATA_HELPER) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_LEGACY_PLANNER) FORCE | $(BUILD_DIR)
	@$(call REFRESH_BOOTSTRAP_SEED_METADATA)

all: $(BIN_DIR)/oasis

bootstrap-smoke:
	rm -rf $(BUILD_DIR)
	$(MAKE) $(BIN_DIR)/oasis $(BIN_DIR)/test_runner

test: bootstrap-smoke $(BIN_DIR)/oasis $(BIN_DIR)/test_runner
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) $(BIN_DIR)/test_runner

release-artifacts: $(BIN_DIR)/oasis
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) ./scripts/generate_release_artifacts.sh

release-manifests:
	./scripts/generate_packaging_manifests.sh --source-archive-dir dist --asset-index-output dist/release-assets.json

sync-generated: $(BIN_DIR)/oasis
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) ./scripts/exec_oasis_subtool.sh sync-generated

release-cut:
	@if [ -z "$(VERSION)" ]; then \
		echo "make release-cut VERSION=X.Y.Z [TAG=1]" >&2; \
		exit 2; \
	fi
	./scripts/cut_release.sh --version "$(VERSION)" $(if $(TAG),--tag,)

update-homebrew-tap:
	@if [ -z "$(TAP_DIR)" ]; then \
		echo "make update-homebrew-tap TAP_DIR=/path/to/homebrew-oasis [SOURCE_ARCHIVE=dist/archive.tar.gz | FORMULA=dist/oasis.rb] [COMMIT=1] [PUSH=1]" >&2; \
		exit 2; \
	fi
	./scripts/update_homebrew_tap.sh --tap-dir "$(TAP_DIR)" $(if $(SOURCE_ARCHIVE),--source-archive "$(SOURCE_ARCHIVE)",$(if $(FORMULA),--formula "$(FORMULA)",)) $(if $(COMMIT),--commit,) $(if $(PUSH),--push,)

benchmark-bootstrap:
	scripts/benchmark_bootstrap.sh --workspace .

refresh-bootstrap-seed-metadata: $(BOOTSTRAP_SEED_METADATA)

clean:
	rm -rf $(BUILD_DIR)

$(BUILD_DIR) $(OBJ_DIR) $(SEED_OBJ_DIR) $(BIN_DIR):
	mkdir -p $@

BOOTSTRAP_PROFILE_ARG = $(if $(strip $(BOOTSTRAP_PROFILE)),--profile $(BOOTSTRAP_PROFILE),)

BOOTSTRAP_SKIP_INCLUDE_GOALS := clean test bootstrap-smoke benchmark-bootstrap refresh-bootstrap-seed-metadata release-manifests release-cut update-homebrew-tap
BOOTSTRAP_SKIP_GENERATED_MK ?=

ifeq ($(filter $(BOOTSTRAP_SKIP_INCLUDE_GOALS),$(MAKECMDGOALS)),)
BOOTSTRAP_SCOPE ?= auto
BOOTSTRAP_NEEDS_FULL := $(filter test bootstrap-smoke $(BIN_DIR)/test_runner,$(MAKECMDGOALS))

ifeq ($(BOOTSTRAP_SKIP_GENERATED_MK),)
ifeq ($(BOOTSTRAP_SCOPE),app)
BOOTSTRAP_MK := $(BOOTSTRAP_APP_MK)
else ifeq ($(BOOTSTRAP_SCOPE),full)
BOOTSTRAP_MK := $(BOOTSTRAP_FULL_MK)
else
BOOTSTRAP_MK := $(if $(BOOTSTRAP_NEEDS_FULL),$(BOOTSTRAP_FULL_MK),$(BOOTSTRAP_APP_MK))
endif
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

BOOTSTRAP_LIBRARY_PACKAGE_FLAGS := $(addprefix -package ,$(BOOTSTRAP_LIBRARY_PACKAGES))
BOOTSTRAP_SEED_MAIN_OBJ := $(SEED_OBJ_DIR)/bootstrap_seed_main.$(OBJ_EXT)

define SYNC_BOOTSTRAP_SHARED_OUTPUTS
set -eu; \
sh "$(BOOTSTRAP_SHARED_OUTPUTS_HELPER)" \
	--makefile "$(1)" \
	--metadata "$(BOOTSTRAP_SEED_METADATA)" \
	--obj-dir "$(OBJ_DIR)" \
	--obj-ext "$(OBJ_EXT)"
endef

$(BOOTSTRAP_SEED_BIN): $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_METADATA_HELPER) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_LEGACY_PLANNER) $(BOOTSTRAP_LIBRARY_COMPILE_SOURCES) | $(OBJ_DIR) $(SEED_OBJ_DIR) $(BIN_DIR)
	@if [ -z "$(strip $(BOOTSTRAP_LIBRARY_COMPILE_SOURCES))" ]; then \
		$(MAKE) refresh-bootstrap-seed-metadata; \
		$(MAKE) BOOTSTRAP_SKIP_GENERATED_MK=yes $@; \
		exit 0; \
	fi; \
	set -eu; \
	objs=""; \
	for src in $(BOOTSTRAP_LIBRARY_COMPILE_SOURCES); do \
		base=$$(basename "$$src"); \
		stem=$${base%.*}; \
		ext=$${base##*.}; \
		if [ "$$ext" = "mli" ]; then \
			$(if $(strip $(BOOTSTRAP_LIBRARY_ENV_PREFIX)),$(BOOTSTRAP_LIBRARY_ENV_PREFIX) ,)$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) $(BOOTSTRAP_LIBRARY_COMPILE_FLAGS) -I $(OBJ_DIR) -c "$$src" -o $(OBJ_DIR)/$$stem.cmi; \
		else \
			$(if $(strip $(BOOTSTRAP_LIBRARY_ENV_PREFIX)),$(BOOTSTRAP_LIBRARY_ENV_PREFIX) ,)$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) $(BOOTSTRAP_LIBRARY_COMPILE_FLAGS) -I $(OBJ_DIR) -c "$$src" -o $(OBJ_DIR)/$$stem.$(OBJ_EXT); \
			objs="$$objs $(OBJ_DIR)/$$stem.$(OBJ_EXT)"; \
		fi; \
	done; \
	$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR) -c $(BOOTSTRAP_GENERATOR) -o $(BOOTSTRAP_SEED_MAIN_OBJ); \
	$(call BOOTSTRAP_TOOL_CMD,$(BOOTSTRAP_LIBRARY_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR) -linkpkg -o $@ $$objs $(BOOTSTRAP_SEED_MAIN_OBJ)

ifeq ($(BOOTSTRAP_SKIP_GENERATED_MK),)
$(BOOTSTRAP_APP_MK): $(BOOTSTRAP_SEED_BIN) $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_SHARED_OUTPUTS_HELPER) | $(BUILD_DIR)
	tmp=$@.tmp; \
	$(BOOTSTRAP_SEED_BIN) --manifest $(BOOTSTRAP_MANIFEST) --scope app $(BOOTSTRAP_PROFILE_ARG) > $$tmp && mv $$tmp $@; \
	$(call SYNC_BOOTSTRAP_SHARED_OUTPUTS,$@)

$(BOOTSTRAP_FULL_MK): $(BOOTSTRAP_SEED_BIN) $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) $(BOOTSTRAP_SHARED_OUTPUTS_HELPER) | $(BUILD_DIR)
	tmp=$@.tmp; \
	$(BOOTSTRAP_SEED_BIN) --manifest $(BOOTSTRAP_MANIFEST) --scope full $(BOOTSTRAP_PROFILE_ARG) > $$tmp && mv $$tmp $@; \
	$(call SYNC_BOOTSTRAP_SHARED_OUTPUTS,$@)

-include $(BOOTSTRAP_MK)
endif
endif
