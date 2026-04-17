MD_FILES := $(shell find . -name '*.md' -not -path './.git/*')

.PHONY: lint

lint:
	mdl $(MD_FILES)
