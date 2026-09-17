.PHONY: build clean

BUILD_DIR := build
PACKAGE_DIR := $(BUILD_DIR)/package
ZIP_FILE := $(BUILD_DIR)/lambda.zip

build: clean
	@echo "==> Building Lambda package"
	mkdir -p $(PACKAGE_DIR)
	pip install \
		--requirement src/requirements.txt \
		--target $(PACKAGE_DIR)
	cp src/handler.py $(PACKAGE_DIR)/
	cd $(PACKAGE_DIR) && zip -qr ../lambda.zip .
	@echo "==> Lambda package: $(ZIP_FILE)"

clean:
	rm -rf $(BUILD_DIR)

