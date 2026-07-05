# =============================================================================
# Makefile — firmware-poc
# Supports:
#   make TARGET=arm    → cross-compile for ARM Cortex-M (arm-linux-gnueabi-gcc)
#   make TARGET=x86    → native build for CI validation (default)
# =============================================================================

TARGET    ?= x86
BUILD_DIR  = build
SRC_DIR    = src
INC_DIR    = include

SRCS = $(wildcard $(SRC_DIR)/*.c)
OBJS = $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SRCS))

BINARY_NAME = firmware.elf

# --- Toolchain selection ---
ifeq ($(TARGET),arm)
    CC      = arm-linux-gnueabi-gcc
    CFLAGS  = -Wall -Wextra -Os -g \
              -march=armv7-a \
              -I$(INC_DIR)
    LDFLAGS = -static
else
    CC      = gcc
    CFLAGS  = -Wall -Wextra -Os -g \
              -I$(INC_DIR)
    LDFLAGS =
endif

# =============================================================================

.PHONY: all clean info

all: $(BUILD_DIR)/$(BINARY_NAME)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/$(BINARY_NAME): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	@echo ""
	@echo "=== Build successful ==="
	@echo "Binary: $@"
	@file $@
	@size $@

clean:
	rm -rf $(BUILD_DIR)

info:
	@echo "TARGET  : $(TARGET)"
	@echo "CC      : $(CC)"
	@echo "CFLAGS  : $(CFLAGS)"
	@echo "Sources : $(SRCS)"
