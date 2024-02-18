BASE_NAME ?=
IMAGE_TAG ?=
CONTAINERFILE ?=

CACHE_FROM ?=

PROJECT := riscv-technologies-lab/rv_tools_image
BUILD_DIR := __build__/$(BASE_NAME)/$(IMAGE_TAG)
BUILD_TESTS := $(BUILD_DIR)/tests
CONTAINER_NAME := $(BASE_NAME)_cont
IMAGE_NAME := riscv-technologies-lab/$(BASE_NAME)
IMAGE_NAMETAG := $(IMAGE_NAME):$(IMAGE_TAG)
TESTS_DIR := tests
VCS_REF != git rev-parse HEAD

DEPS != grep --perl-regexp --only-matching "COPY \K.*?(?= \S+$$)" $(CONTAINERFILE)
DEPS += $(CONTAINERFILE)

HELLO_WORLD_DEPS != find $(TESTS_DIR) -type f,l

.PHONY: image
image: $(BUILD_DIR)/image

.PHONY: container
container: $(BUILD_DIR)/container

.PHONY: image_name
image_name:
	$(info $(IMAGE_NAME))

.PHONY: image_nametag
image_nametag:
	$(info $(IMAGE_NAMETAG))

.PHONY: image_tag
image_tag:
	$(info $(IMAGE_TAG))

.PHONY: format
format: $(BUILD_DIR)/node_modules
	npx prettier --ignore-path <(cat .gitignore .prettierignore) --write .

$(BUILD_DIR)/node_modules: package.json package-lock.json
	npm install --save-exact;
	mkdir --parents $(BUILD_DIR) && touch $@

.PHONY: $(BUILD_DIR)/not_ready

IMAGE_CREATE_STATUS != docker image exists $(IMAGE_NAMETAG) || echo "$(BUILD_DIR)/not_ready"
$(BUILD_DIR)/image: $(DEPS) $(IMAGE_CREATE_STATUS)
	docker build \
		--cache-from '$(CACHE_FROM)' \
		--label "org.opencontainers.image.ref.name=$(IMAGE_NAME)" \
		--label "org.opencontainers.image.revision=$(VCS_REF)" \
		--label "org.opencontainers.image.source=https://github.com/$(PROJECT)" \
		--label "org.opencontainers.image.version=$(IMAGE_TAG)" \
		--tag $(IMAGE_NAMETAG) \
		--file $(CONTAINERFILE) .
	mkdir --parents $(BUILD_DIR) && touch $@

CONTAINER_ID != docker container ls --quiet --all --filter name=^$(CONTAINER_NAME)$
CONTAINER_STATE != docker container ls --format {{.State}} --all --filter name=^$(CONTAINER_NAME)$
CONTAINER_RUN_STATUS != [[ ! "$(CONTAINER_STATE)" =~ ^Up ]] && echo "$(BUILD_DIR)/not_ready"
$(BUILD_DIR)/container: $(BUILD_DIR)/image $(CONTAINER_RUN_STATUS)
ifneq ($(CONTAINER_ID),)
	docker container rename $(CONTAINER_NAME) $(CONTAINER_NAME)_$(CONTAINER_ID)
endif
	docker run --interactive --tty --detach \
		--env "TERM=xterm-256color" \
		--mount type=bind,source="$$(pwd)",target="$$(pwd)" \
		--name $(CONTAINER_NAME) \
		--ulimit nofile=1024:1024 \
		--user "$$(id -u ${USER}):$$(id -g ${USER})" \
		--workdir "$$HOME" \
		$(IMAGE_NAMETAG)
	docker exec --user root $(CONTAINER_NAME) \
		bash -c "chown $$(id -u):$$(id -g) $$HOME"
	mkdir --parents $(BUILD_TESTS)
	mkdir --parents $(BUILD_DIR) && touch $@


$(BUILD_TESTS)/gcc/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		CC=gcc \
		CXX=g++ \
		cmake \
		-S $(TESTS_DIR) \
		-B $(BUILD_TESTS)/gcc \
		-G Ninja \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/gcc \
		--verbose \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/gcc/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/g++" $(BUILD_TESTS)/gcc/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/llvm/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		CC=clang \
		CXX=clang++ \
		cmake \
		-S $(TESTS_DIR) \
		-B $(BUILD_TESTS)/llvm \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/llvm \
		--verbose \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/llvm/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/clang++" $(BUILD_TESTS)/llvm/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/valgrind: $(BUILD_TESTS)/gcc/hello_world $(BUILD_TESTS)/llvm/hello_world
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "valgrind $(BUILD_TESTS)/gcc/hello_world"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "valgrind $(BUILD_TESTS)/llvm/hello_world"
	touch $@

$(BUILD_TESTS)/gdb: $(BUILD_TESTS)/gcc/hello_world $(BUILD_TESTS)/llvm/hello_world
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		gdb -ex run -ex quit ./$(BUILD_TESTS)/gcc/hello_world && \
		gdb -ex run -ex quit ./$(BUILD_TESTS)/llvm/hello_world && \
		: "
	touch $@

$(BUILD_TESTS)/riscv-gcc/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		CC=${SCDT_INSTALLATION_ROOT}/riscv-gcc/bin/riscv64-unknown-linux-gnu-gcc \
		CXX=${SCDT_INSTALLATION_ROOT}/riscv-gcc/bin/riscv64-unknown-linux-gnu-g++ \
		cmake \
		-S $(TESTS_DIR) \
		-B $(BUILD_TESTS)/riscv-gcc \
		-G Ninja \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		-DCMAKE_EXE_LINKER_FLAGS=-static \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/riscv-gcc \
		--verbose \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/riscv-gcc/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/riscv64-unknown-linux-gnu-g++" $(BUILD_TESTS)/gcc/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/riscv-llvm/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		CC=${SCDT_INSTALLATION_ROOT}/llvm/bin/clang \
		CXX=${SCDT_INSTALLATION_ROOT}/llvm/bin/clang++ \
		cmake \
		-S $(TESTS_DIR) \
		-B $(BUILD_TESTS)/riscv-llvm \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		-DCMAKE_CXX_FLAGS='--gcc-toolchain=${SCDT_INSTALLATION_ROOT}/riscv-gcc/sysroot'
		-DCMAKE_EXE_LINKER_FLAGS=-static \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/riscv-llvm \
		--verbose \
	"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/llvm/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/clang++" $(BUILD_TESTS)/llvm/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/riscv-qemu: $(BUILD_TESTS)/riscv-gcc/hello_world $(BUILD_TESTS)/riscv-llvm/hello_world
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		${SCDT_INSTALLATION_ROOT}/tools/bin/qemu-riscv64 ./(BUILD_TESTS)/riscv-gcc/hello_world && \
		${SCDT_INSTALLATION_ROOT}/tools/bin/qemu-riscv64 ./(BUILD_TESTS)/riscv-llvm/hello_world && \
		: "
	touch $@

$(BUILD_TESTS)/clang_tidy: $(BUILD_TESTS)/gcc/hello_world $(BUILD_TESTS)/llvm/hello_world
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		clang-tidy -p $(BUILD_TESTS)/gcc $(TESTS_DIR)/hello_world.cpp && \
		clang-tidy -p $(BUILD_TESTS)/llvm $(TESTS_DIR)/hello_world.cpp && \
		: "
	touch $@

$(BUILD_TESTS)/env: $(BUILD_DIR)/container
	# glibc compilation requires env variables to be correctly formed
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$PATH' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$MANPATH' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$INFOPATH' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$PCP_DIR' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$LD_LIBRARY_PATH' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$PKG_CONFIG_PATH' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$PYTHONPATH' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	docker exec $(CONTAINER_NAME) \
		bash -c 'echo $$XDG_DATA_DIRS' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	touch $@

$(BUILD_TESTS)/versions: $(BUILD_DIR)/container
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "cmake --version" | grep --perl-regexp --quiet "3\.26\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "gcc --version" | grep --perl-regexp --quiet "13\.\d+\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "g++ --version" | grep --perl-regexp --quiet "13\.\d+\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang++ --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang-format --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang-tidy --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "FileCheck --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "python3 --version" | grep --perl-regexp --quiet "3\.10\.\d+"
	bash_version=$$(docker exec --workdir "$$(pwd)" $(CONTAINER_NAME) \
		bash -c "bash --version" | grep --perl-regexp --only-matching "\d+\.\d+\.\d+"); \
		{ echo 4.4.0; echo $$bash_version; } | sort --version-sort --check &> /dev/null
	git_version=$$(docker exec --workdir "$$(pwd)" $(CONTAINER_NAME) \
		bash -c "git --version" | grep --perl-regexp --only-matching "\d+\.\d+\.\d+"); \
		{ echo 2.0.0; echo $$git_version; } | sort --version-sort --check &> /dev/null
	touch $@

# Temporaly disable this check
# $(BUILD_DIR)/tests/username: $(BUILD_DIR)/container
# 	container_username=$$(docker exec --workdir "$$(pwd)" $(CONTAINER_NAME) \
# 		bash -c "id --user --name") && \
# 		[[ "$$container_username" == "$$(id --user --name)" ]]
# 	container_home=$$(docker exec --workdir "$$(pwd)" $(CONTAINER_NAME) \
# 		bash -c "echo $$HOME") && \
# 		[[ "$$container_home" == "/home/$$(id --user --name)" ]]
# 	touch $@

.PHONY: check
check: \
	$(BUILD_DIR)/tests/gcc/hello_world \
	$(BUILD_DIR)/tests/llvm/hello_world \
	$(BUILD_DIR)/tests/clang_tidy \
	$(BUILD_DIR)/tests/gdb \
	$(BUILD_DIR)/tests/valgrind \
	$(BUILD_DIR)/tests/env \
	$(BUILD_DIR)/tests/versions \
	# $(BUILD_DIR)/tests/username \

.PHONY: clean
clean:
	docker container ls --quiet --filter name=^$(CONTAINER_NAME) | xargs docker stop || true
	docker container ls --quiet --filter name=^$(CONTAINER_NAME) --all | xargs docker rm || true

