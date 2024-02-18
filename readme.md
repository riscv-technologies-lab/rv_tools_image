# Container image for C++ builds

Container image for reproducible C++ builds targeting local and CI usage.

## Using the image

```bash
# Bootstrap
docker run --interactive --tty --detach \
  --env "TERM=xterm-256color" `# colored terminal` \
  --mount type=bind,source="$(pwd)",target="$(pwd)" `# mount your repo` \
  --name cpp \
  --ulimit nofile=1024:1024 `# workaround for valgrind` \
  --user "$$(id -u ${USER}):$$(id -g ${USER})" `# keeps your non-root username` \
  --workdir "$HOME" `# podman sets homedir to the workdir for some reason` \
  ghcr.io/riscv-technologies-lab/rv_tools_image:latest `# note: always pin here exact tag!`
docker exec --user root cpp bash -c "chown $(id --user):$(id --group) $HOME"

# Execute single command
docker exec --workdir "$(pwd)" cpp bash -c 'your_command'

# Attach to container
docker exec --workdir "$(pwd)" --interactive --tty cpp bash
```

## Build

**Requirements:** `docker`, `GNU Make >= 4.3`

```bash
make
```

## Test

```bash
make check
```

## Clean

```bash
make clean
```
