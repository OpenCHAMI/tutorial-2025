# Recursive wildcard function, obtained from https://stackoverflow.com/a/18258352
#
# Arg 1: Space-separated list of directories to recurse into
# Arg 2: Space-separated list of patterns to match
rwildcard = $(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))

openchami-tutorial-practicum.pdf: $(call rwildcard,.,*.md)
	pandoc --from=gfm \
		--to=pdf \
		--pdf-engine=lualatex \
		--output=openchami-tutorial-practicum.pdf \
		Readme.md \
		AWS_Environment.md \
		Phase\ 1/Readme.md \
		Phase\ 1/service_configuration.md \
		Phase\ 2/Readme.md \
		Phase\ 2/discovery.md \
		Phase\ 2/images.md \
		Phase\ 2/boot.md \
		Phase\ 2/cloud-init.md \
		Phase\ 3/Readme.md \
		Phase\ 3/wireguard.md \
		Phase\ 3/nfsroot.md

.PHONY: clean
clean:
	rm -f openchami-tutorial-practicum.pdf
