REPO_ROOT=$(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Binary Output
BIN_DIR=$(REPO_ROOT)/bin
CONTROLLER_BIN=$(BIN_DIR)/import-controller
IMPORTER_BIN=$(BIN_DIR)/importer

# Source dirs
CMD_DIR=$(REPO_ROOT)/cmd
CONTROLLER_CMD=$(CMD_DIR)/controller
IMPORTER_CMD=$(CMD_DIR)/importer

# Build Dirs
BUILD_DIR=$(REPO_ROOT)/build
CONTROLLER_BUILD=$(BUILD_DIR)/controller
IMPORTER_BUILD=$(BUILD_DIR)/importer

# DOCKER TAG VARS
REGISTRY=jcoperh
CONTROLLER_IMAGE=import-controller
IMPORTER_IMAGE=importer
GIT_USER=$(shell git config --get user.email | sed 's/@.*//')
TAG="$(GIT_USER)-latest"
VERSION=v1

.PHONY: controller importer controller-bin importer-bin controller-image importer-image push-controller push-importer clean
all: clean controller importer
controller: controller-bin controller-image
importer: importer-bin importer-image
push: push-importer push-controller

GOOS?=linux
ARCH?=amd64
CGO_ENABLED=0
LDFLAGS='-extldflags "-static"'

# Compile controller binary
controller-bin:
	GOOS=$(GOOS) GOARCH=$(ARCH) CGO_ENABLED=$(CGO_ENABLED) go build -a -ldflags $(LDFLAGS) -o $(CONTROLLER_BIN) $(CONTROLLER_CMD)/*.go

# Compile importer binary
importer-bin:
	GOOS=$(GOOS) GOARCH=$(ARCH) CGO_ENABLED=$(CGO_ENABLED) go build -a -ldflags $(LDFLAGS) -o $(IMPORTER_BIN) $(IMPORTER_CMD)/*.go

# build the controller image
controller-image: $(CONTROLLER_BUILD)/Dockerfile
	$(eval TEMP_BUILD_DIR=$(CONTROLLER_BUILD)/tmp)
	mkdir -p $(TEMP_BUILD_DIR)
	cp $(CONTROLLER_BIN) $(TEMP_BUILD_DIR)
	cp $(CONTROLLER_BUILD)/Dockerfile $(TEMP_BUILD_DIR)
	docker build -t $(CONTROLLER_IMAGE) $(TEMP_BUILD_DIR)
	docker tag $(CONTROLLER_IMAGE) $(REGISTRY)/$(CONTROLLER_IMAGE):$(TAG)
	-rm -rf $(TEMP_BUILD_DIR)

# build the importer image
importer-image: $(IMPORTER_BUILD)/Dockerfile
	$(eval TEMP_BUILD_DIR=$(IMPORTER_BUILD)/tmp)
	mkdir -p $(TEMP_BUILD_DIR)
	cp $(IMPORTER_BIN) $(TEMP_BUILD_DIR)
	cp $(IMPORTER_BUILD)/Dockerfile $(TEMP_BUILD_DIR)
	docker build -t $(IMPORTER_IMAGE) $(TEMP_BUILD_DIR)
	docker tag $(IMPORTER_IMAGE) $(REGISTRY)/$(IMPORTER_IMAGE):$(TAG)
	-rm -rf $(TEMP_BUILD_DIR)

push-controller:
	docker push $(REGISTRY)/$(CONTROLLER_IMAGE):$(TAG)

push-importer:
	docker push $(REGISTRY)/$(IMPORTER_IMAGE):$(TAG)

clean:
	-rm -rf $(BIN_DIR)/*
	-rm -rf $(CONTROLLER_BUILD)/tmp
	-rm -rf $(IMPORTER_BUILD)/tmp

# push CONTROLLER_IMAGE:$(VERSION). Intended to release stable image built from master branch.
release:
	docker tag $(IMPORTER_IMAGE) $(REGISTRY)/$(IMPORTER_IMAGE):latest
	docker push $(REGISTRY)/$(IMPORTER_IMAGE):latest
	docker tag $(CONTROLLER_IMAGE) $(REGISTRY)/$(CONTROLLER_IMAGE):latest
	docker push $(REGISTRY)/$(CONTROLLER_IMAGE):latest

#	git fetch origin
#ifneq ($(shell git rev-parse --abbrev-ref HEAD), master)
#	$(error Release is intended to be run on master branch. Please checkout master and retry.)
#endif
#ifneq ($(shell git rev-list HEAD..origin/master --count), 0)
#	$(error HEAD is behind origin/master -- $(shell git status -sb --porcelain))
#endif
#ifneq ($(shell git rev-list origin/master..HEAD --count), 0)
#	$(error HEAD is ahead of origin/master --  $(shell git status -sb --porcelain))
#endif
#	docker tag $(IMAGE) $(REGISTRY)/$(CONTROLLER_IMAGE):latest
#	docker push $(REGISTRY)/$(CONTROLLER_IMAGE):latest
