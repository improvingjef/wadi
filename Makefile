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

COMMON_OBJS := \
	$(OBJ_DIR)/string_util.cmx \
	$(OBJ_DIR)/fs.cmx \
	$(OBJ_DIR)/process.cmx \
	$(OBJ_DIR)/toolchain.cmx \
	$(OBJ_DIR)/manifest.cmx \
	$(OBJ_DIR)/builder.cmx \
	$(OBJ_DIR)/cleaner.cmx

APP_OBJS := \
	$(COMMON_OBJS) \
	$(OBJ_DIR)/tester.cmx \
	$(OBJ_DIR)/cli.cmx \
	$(OBJ_DIR)/main.cmx

TEST_OBJS := \
	$(OBJ_DIR)/test_support.cmx \
	$(OBJ_DIR)/test_manifest.cmx \
	$(OBJ_DIR)/test_build.cmx \
	$(OBJ_DIR)/test_clean.cmx \
	$(OBJ_DIR)/test_process.cmx \
	$(OBJ_DIR)/test_run.cmx \
	$(OBJ_DIR)/test_test.cmx \
	$(OBJ_DIR)/test_main.cmx

.PHONY: all test clean

all: $(BIN_DIR)/oasis

test: $(BIN_DIR)/oasis $(BIN_DIR)/test_runner
	OASIS_BIN=$(abspath $(BIN_DIR)/oasis) $(BIN_DIR)/test_runner

clean:
	rm -rf $(BUILD_DIR)

$(OBJ_DIR) $(BIN_DIR):
	mkdir -p $@

$(OBJ_DIR)/string_util.cmx: src/string_util.ml | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) -c -o $@ $<

$(OBJ_DIR)/fs.cmx: src/fs.ml $(OBJ_DIR)/string_util.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/process.cmx: src/process.ml $(OBJ_DIR)/string_util.cmx $(OBJ_DIR)/fs.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/toolchain.cmx: src/toolchain.ml $(OBJ_DIR)/string_util.cmx $(OBJ_DIR)/process.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/manifest.cmx: src/manifest.ml $(OBJ_DIR)/string_util.cmx $(OBJ_DIR)/fs.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/builder.cmx: src/builder.ml $(OBJ_DIR)/string_util.cmx $(OBJ_DIR)/fs.cmx $(OBJ_DIR)/process.cmx $(OBJ_DIR)/toolchain.cmx $(OBJ_DIR)/manifest.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/cleaner.cmx: src/cleaner.ml $(OBJ_DIR)/string_util.cmx $(OBJ_DIR)/fs.cmx $(OBJ_DIR)/manifest.cmx $(OBJ_DIR)/builder.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/tester.cmx: src/tester.ml $(COMMON_OBJS) | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/cli.cmx: src/cli.ml $(COMMON_OBJS) $(OBJ_DIR)/tester.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/main.cmx: src/main.ml $(OBJ_DIR)/cli.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_support.cmx: test/test_support.ml $(COMMON_OBJS) | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_manifest.cmx: test/test_manifest.ml $(COMMON_OBJS) $(OBJ_DIR)/test_support.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_build.cmx: test/test_build.ml $(COMMON_OBJS) $(OBJ_DIR)/test_support.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_clean.cmx: test/test_clean.ml $(COMMON_OBJS) $(OBJ_DIR)/test_support.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_process.cmx: test/test_process.ml $(COMMON_OBJS) $(OBJ_DIR)/test_support.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_run.cmx: test/test_run.ml $(COMMON_OBJS) $(OBJ_DIR)/test_support.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_test.cmx: test/test_test.ml $(COMMON_OBJS) $(OBJ_DIR)/test_support.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(OBJ_DIR)/test_main.cmx: test/test_main.ml $(OBJ_DIR)/test_support.cmx $(OBJ_DIR)/test_manifest.cmx $(OBJ_DIR)/test_build.cmx $(OBJ_DIR)/test_clean.cmx $(OBJ_DIR)/test_process.cmx $(OBJ_DIR)/test_run.cmx $(OBJ_DIR)/test_test.cmx | $(OBJ_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -c -o $@ $<

$(BIN_DIR)/oasis: $(APP_OBJS) | $(BIN_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -o $@ $(UNIX_ARCHIVE) $(APP_OBJS)

$(BIN_DIR)/test_runner: $(COMMON_OBJS) $(TEST_OBJS) | $(BIN_DIR)
	$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -o $@ $(UNIX_ARCHIVE) $(COMMON_OBJS) $(TEST_OBJS)
