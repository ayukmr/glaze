# default command
default: bundle build/lists.bc

# install brew dependencies
Brewfile.lock.json: Brewfile
	brew bundle

# install ruby dependencies
Gemfile.lock: Gemfile
	LLVM_CONFIG=$(HOMEBREW_PREFIX)/opt/llvm/bin/llvm-config bundle
	ln -sf $(HOMEBREW_PREFIX)/opt/llvm/lib/libLLVM.dylib /usr/local/lib/libLLVM-15.dylib

# create lists bitcode
build/lists.bc: c/lists.c
	cc -c -emit-llvm -o build/lists.bc c/lists.c

# install dependencies
.PHONY: bundle
bundle: Brewfile.lock.json Gemfile.lock

# clean build directory
.PHONY: clean
clean:
	rm -f build/*
