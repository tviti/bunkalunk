SHELL = /bin/sh

.DEFAULT_GOAL := build

PREFIX ?= $(HOME)/.local
EXEC_PREFIX ?= $(PREFIX)

BINDIR ?= $(EXEC_PREFIX)/bin
LIBDIR ?= $(EXEC_PREFIX)/lib
DATADIR ?= $(PREFIX)/share

PYTHON ?= python
JULIA ?= julia

BUILD_DIR ?= $(project_root)/build

project_root := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
julia_project_dir := $(project_root)/src/julia
python_project_dir := $(project_root)/src/python
julia_build_dir := $(BUILD_DIR)/julia
python_build_dir := $(BUILD_DIR)/python
julia_sysimage_dir := $(julia_build_dir)/sysimages

lunk_app_dir := $(julia_build_dir)/app
lunk_archive := $(julia_build_dir)/lunk.tar.gz

lunk_app_sources := $(wildcard $(julia_project_dir)/src/*.jl)
lunk_app_inputs := \
	$(julia_project_dir)/Project.toml \
	$(julia_project_dir)/Manifest.toml \
	$(julia_project_dir)/scripts/app/Project.toml \
	$(julia_project_dir)/scripts/app/Manifest.toml \
	$(julia_project_dir)/scripts/app/build.jl \
	$(julia_project_dir)/scripts/precompile/lunk_cli.jl

.PHONY: build build-lunk build-dev-sysimage build-test-sysimage \
	install install-bunk install-lunk installdirs clean clean-lunk-app

build: build-lunk build-dev-sysimage build-test-sysimage

build-lunk: $(lunk_archive)

build-dev-sysimage: $(julia_sysimage_dir)
	$(JULIA) --project=$(julia_project_dir)/scripts/dev_sysimage \
		$(julia_project_dir)/scripts/dev_sysimage/build.jl \
		$(julia_sysimage_dir)/dev_sysimage.so

build-test-sysimage: $(julia_sysimage_dir)
	$(JULIA) --project=$(julia_project_dir)/scripts/test_sysimage \
		$(julia_project_dir)/scripts/test_sysimage/build.jl \
		$(julia_sysimage_dir)/test_sysimage.so

install: install-bunk install-lunk

install-bunk:
	$(PYTHON) -m pip install $(python_project_dir)

install-lunk: $(lunk_archive) installdirs
	install -d $(DESTDIR)$(LIBDIR)/lunk
	tar -xvzf $(lunk_archive) -C $(DESTDIR)$(LIBDIR)/lunk
	ln -sf ../lib/lunk/bin/Lunk $(DESTDIR)$(BINDIR)/lunk

$(julia_sysimage_dir):
	mkdir -p $(julia_sysimage_dir)

$(lunk_archive): $(lunk_app_sources) $(lunk_app_inputs)
	$(JULIA) --project=$(julia_project_dir)/scripts/app \
		$(julia_project_dir)/scripts/app/build.jl \
		$(julia_build_dir)
	tar -czf "$(lunk_archive).tmp" -C "$(lunk_app_dir)" .
	mv "$(lunk_archive).tmp" "$(lunk_archive)"

installdirs:
	mkdir -p \
		$(DESTDIR)$(BINDIR) \
		$(DESTDIR)$(LIBDIR) \
		$(DESTDIR)$(DATADIR)

clean-lunk-app:
	rm -rf $(julia_build_dir)/app

clean:
	rm -rf $(BUILD_DIR)
