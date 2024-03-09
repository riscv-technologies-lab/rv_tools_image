BASE_NAME ?=
IMAGE_TAG ?=
CONTAINERFILE ?=

CACHE_FROM ?=

USER_ID ?=
USER_ID != [[ -z "$(USER_ID)" ]] && echo $$(id --user) || echo "$(USER_ID)"
USER_NAME ?=
USER_NAME != [[ -z "$(USER_NAME)" ]] && echo $$(id --user --name) || echo "$(USER_NAME)"

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

IF_DOCKERD_UP := command -v docker &> /dev/null && docker image ls &> /dev/null

IMAGE_ID != $(IF_DOCKERD_UP) && docker images --quiet $(IMAGE_TAG)
IMAGE_CREATE_STATUS != [[ -z "$(IMAGE_ID)" ]] && echo "image_not_created"
CACHE_FROM_OPTION != [[ ! -z "$(CACHE_FROM)" ]] && echo "--cache-from $(CACHE_FROM)"
.PHONY: image_not_created
$(BUILD_DIR)/image: $(DEPS) $(IMAGE_CREATE_STATUS)
	docker build \
		$(CACHE_FROM_OPTION) \
        --label "org.opencontainers.image.ref.name=$(IMAGE_NAME)" \
		--label "org.opencontainers.image.revision=$(VCS_REF)" \
		--label "org.opencontainers.image.source=https://github.com/$(PROJECT)" \
		--label "org.opencontainers.image.version=$(IMAGE_TAG)" \
		--tag $(IMAGE_NAMETAG) \
		--file $(CONTAINERFILE) .
	mkdir --parents $(BUILD_DIR) && touch $@

CONTAINER_ID != $(IF_DOCKERD_UP) && docker container ls --quiet --all --filter name=^/$(CONTAINER_NAME)$
CONTAINER_STATE != $(IF_DOCKERD_UP) && docker container ls --format {{.State}} --all --filter name=^/$(CONTAINER_NAME)$
CONTAINER_RUN_STATUS != [[ "$(CONTAINER_STATE)" != "running" ]] && echo "container_not_running"
.PHONY: container_not_running
$(BUILD_DIR)/container: $(BUILD_DIR)/image $(CONTAINER_RUN_STATUS)
ifneq ($(CONTAINER_ID),)
	docker container rename $(CONTAINER_NAME) $(CONTAINER_NAME)_$(CONTAINER_ID)
endif
	docker run --interactive --tty --detach \
		--env "TERM=xterm-256color" \
		--env "KEEP_SUDO=$(KEEP_SUDO)" \
		--env "USER_ID=$(USER_ID)" \
		--env "USER_NAME=$(USER_NAME)" \
		--mount type=bind,source="$$(pwd)",target="$$(pwd)" \
		--name $(CONTAINER_NAME) \
		--ulimit nofile=1024:1024 \
		--workdir "$$HOME" \
		$(IMAGE_NAMETAG)
	sleep 1


$(BUILD_TESTS)/gcc/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		CC=gcc \
		CXX=g++ \
		cmake \
		-S $(TESTS_DIR) \
		-B $(BUILD_TESTS)/gcc \
		-G Ninja \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/gcc \
		--verbose \
	"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/gcc/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/g++" $(BUILD_TESTS)/gcc/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/llvm/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		CC=clang \
		CXX=clang++ \
		cmake \
		-S $(TESTS_DIR) \
		-B $(BUILD_TESTS)/llvm \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/llvm \
		--verbose \
	"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/llvm/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/clang++" $(BUILD_TESTS)/llvm/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/valgrind: $(BUILD_TESTS)/gcc/hello_world $(BUILD_TESTS)/llvm/hello_world
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "valgrind $(BUILD_TESTS)/gcc/hello_world"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "valgrind $(BUILD_TESTS)/llvm/hello_world"
	touch $@

$(BUILD_TESTS)/gdb: $(BUILD_TESTS)/gcc/hello_world $(BUILD_TESTS)/llvm/hello_world
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		gdb -ex run -ex quit ./$(BUILD_TESTS)/gcc/hello_world && \
		gdb -ex run -ex quit ./$(BUILD_TESTS)/llvm/hello_world && \
		: "
	touch $@

$(BUILD_TESTS)/riscv-gcc/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
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
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/riscv-gcc \
		--verbose \
	"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/riscv-gcc/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/riscv64-unknown-linux-gnu-g++" $(BUILD_TESTS)/gcc/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/riscv-llvm/hello_world: $(BUILD_DIR)/container $(HELLO_WORLD_DEPS)
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
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
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		cmake \
		--build $(BUILD_TESTS)/riscv-llvm \
		--verbose \
	"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "./$(BUILD_TESTS)/llvm/hello_world" | grep --quiet "Hello world!"
	grep --quiet "bin/clang++" $(BUILD_TESTS)/llvm/compile_commands.json
	[[ $$(stat --format "%U" $@) == $$(id --user --name) ]]
	[[ $$(stat --format "%G" $@) == $$(id --group --name) ]]
	touch $@

$(BUILD_TESTS)/riscv-qemu: $(BUILD_TESTS)/riscv-gcc/hello_world $(BUILD_TESTS)/riscv-llvm/hello_world
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		${SCDT_INSTALLATION_ROOT}/tools/bin/qemu-riscv64 ./(BUILD_TESTS)/riscv-gcc/hello_world && \
		${SCDT_INSTALLATION_ROOT}/tools/bin/qemu-riscv64 ./(BUILD_TESTS)/riscv-llvm/hello_world && \
		: "
	touch $@

$(BUILD_TESTS)/clang_tidy: $(BUILD_TESTS)/gcc/hello_world $(BUILD_TESTS)/llvm/hello_world
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c " \
		clang-tidy -p $(BUILD_TESTS)/gcc $(TESTS_DIR)/hello_world.cpp && \
		clang-tidy -p $(BUILD_TESTS)/llvm $(TESTS_DIR)/hello_world.cpp && \
		: "
	touch $@

$(BUILD_TESTS)/env: $(BUILD_DIR)/container
	# glibc compilation requires env variables to be correctly formed
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$PATH' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$MANPATH' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$INFOPATH' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$PCP_DIR' | \
		grep --perl-regexp --quiet --invert-match --only-matching "(^:|:$$|::)"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$LD_LIBRARY_PATH' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$PKG_CONFIG_PATH' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$PYTHONPATH' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$XDG_DATA_DIRS' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	echo 'test -v SC_PATHS; echo $$?' | \
		docker exec --user $(USER_NAME) $(CONTAINER_NAME) bash -i
	echo 'echo $$PATH' | \
		docker exec -i --user $(USER_NAME) $(CONTAINER_NAME) bash -i | \
		grep --quiet --only-matching "/opt/sc-dt/riscv-gcc/bin"
	echo 'echo $$PATH' | \
		docker exec -i --user $(USER_NAME) $(CONTAINER_NAME) bash -i | \
		grep --quiet --only-matching "/opt/sc-dt/llvm/bin"
	echo 'echo $$PATH' | \
		docker exec -i --user $(USER_NAME) $(CONTAINER_NAME) bash -i | \
		grep --quiet --only-matching "/opt/sc-dt/tools/bin"
	docker exec --user $(USER_NAME) $(CONTAINER_NAME) \
		bash -c 'echo $$' | \
		grep --perl-regexp --invert-match --quiet --only-matching "(^:|:$$|::)"
	touch $@

$(BUILD_TESTS)/versions: $(BUILD_DIR)/container
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "cmake --version" | grep --perl-regexp --quiet "3\.26\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "gcc --version" | grep --perl-regexp --quiet "13\.\d+\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "g++ --version" | grep --perl-regexp --quiet "13\.\d+\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang++ --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang-format --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "clang-tidy --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "FileCheck --version" | grep --perl-regexp --quiet "17\.\d+\.\d+"
	docker exec --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -c "python3 --version" | grep --perl-regexp --quiet "3\.10\.\d+"
	bash_version=$$(docker exec --user $(USER_NAME) --workdir "$$(pwd)" $(CONTAINER_NAME) \
		bash -c "bash --version" | grep --perl-regexp --only-matching "\d+\.\d+\.\d+"); \
		{ echo 4.4.0; echo $$bash_version; } | sort --version-sort --check &> /dev/null
	git_version=$$(docker exec --user $(USER_NAME) --workdir "$$(pwd)" $(CONTAINER_NAME) \
		bash -c "git --version" | grep --perl-regexp --only-matching "\d+\.\d+\.\d+"); \
		{ echo 2.0.0; echo $$git_version; } | sort --version-sort --check &> /dev/null
	echo "riscv64-unknown-linux-gnu-gcc --version" | \
		docker exec -i --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -i | grep --perl-regexp --quiet "12\.\d+\.\d+"
	echo "clang --version" | \
		docker exec -i --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -i | grep --perl-regexp --quiet "Target: riscv64-unknown-linux-gnu"
	echo "clang++ --version" | \
		docker exec -i --user $(USER_NAME) --workdir $$(pwd) $(CONTAINER_NAME) \
		bash -i | grep --perl-regexp --quiet "Target: riscv64-unknown-linux-gnu"
	touch $@

# Temporaly disable this check
$(BUILD_DIR)/tests/username: $(BUILD_DIR)/container
	container_username=$$(docker exec --user $(USER_NAME) --workdir "$$(pwd)" $(CONTAINER_NAME) \
		bash -c "id --user --name") && \
		[[ "$$container_username" == "$$(id --user --name)" ]]
	container_home=$$(docker exec --user $(USER_NAME) --workdir "$$(pwd)" $(CONTAINER_NAME) \
		bash -c "echo $$HOME") && \
		[[ "$$container_home" == "/home/$$(id --user --name)" ]]
	touch $@

.PHONY: check
check: \
	$(BUILD_DIR)/tests/gcc/hello_world \
	$(BUILD_DIR)/tests/llvm/hello_world \
	$(BUILD_DIR)/tests/clang_tidy \
	$(BUILD_DIR)/tests/gdb \
	$(BUILD_DIR)/tests/valgrind \
	$(BUILD_DIR)/tests/env \
	$(BUILD_DIR)/tests/versions \
	$(BUILD_DIR)/tests/username \

.PHONY: clean
clean:
	docker container ls --quiet --filter name=^$(CONTAINER_NAME) | ifne xargs docker stop || true
	docker container ls --quiet --filter name=^$(CONTAINER_NAME) --all | ifne xargs docker rm || true
