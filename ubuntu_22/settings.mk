BASE_NAME := rv_tools_image
ANCHOR := a9987a6575311c1b1fa4d953ebb9f08e74f54bfb
OFFSET := 1
PATCH != echo $$(($$(git rev-list $(ANCHOR)..HEAD --count --first-parent) - $(OFFSET)))
IMAGE_TAG := 1.0.$(PATCH)
CONTAINERFILE := ubuntu_22/Containerfile
MAKEFILE := linux.mk
