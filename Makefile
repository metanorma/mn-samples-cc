#!make
SHELL := /bin/bash
# Ensure the xml2rfc cache directory exists locally
IGNORE := $(shell mkdir -p $(HOME)/.cache/xml2rfc)

SRC := $(shell yq r metanorma.yml metanorma.source.files | cut -c 3-999)
ifeq ($(SRC),ll)
SRC := $(filter-out README.adoc, $(wildcard sources/*.adoc))
endif
ifeq ($(SRC),)
SRC := $(filter-out README.adoc, $(wildcard sources/*.adoc))
endif

FORMAT_MARKER := mn-output-
FORMATS := $(shell grep "$(FORMAT_MARKER)" $(SRC) | cut -f 2 -d ' ' | tr ',' '\n' | sort | uniq | tr '\n' ' ')

XML  := $(patsubst sources/%,documents/%,$(patsubst %.adoc,%.xml,$(SRC)))

XMLRFC3  := $(patsubst %.xml,%.v3.xml,$(XML))
HTML := $(patsubst %.xml,%.html,$(XML))
DOC  := $(patsubst %.xml,%.doc,$(XML))
PDF  := $(patsubst %.xml,%.pdf,$(XML))
TXT  := $(patsubst %.xml,%.txt,$(XML))
NITS := $(patsubst %.adoc,%.nits,$(wildcard sources/draft-*.adoc))
WSD  := $(wildcard sources/models/*.wsd)

ifdef METANORMA_DOCKER
  PREFIX_CMD := echo "Running via docker..."; docker run -v "$$(pwd)":/metanorma/ $(METANORMA_DOCKER)
else
  PREFIX_CMD := echo "Running locally..."; bundle exec
endif

_OUT_FILES := $(foreach FORMAT,$(FORMATS),$(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))
OUT_FILES  := $(foreach F,$(_OUT_FILES),$($F))

all: documents.html

documents:
	mkdir -p $@

documents/%.xml: documents sources/%.xml
	export GLOBIGNORE=sources/$*.adoc; \
	mv sources/$(addsuffix .*,$*) documents; \
	unset GLOBIGNORE

%.xml %.html:	%.adoc | bundle
	FILENAME=$^; \
	${PREFIX_CMD} metanorma $$FILENAME; \

documents.rxl: $(XML)
	${PREFIX_CMD} relaton concatenate \
	  -t "$(shell yq r metanorma.yml relaton.collection.name)" \
		-g "$(shell yq r metanorma.yml relaton.collection.organization)" \
		documents $@

documents.html: documents.rxl
	${PREFIX_CMD} relaton xml2html documents.rxl

# %.v3.xml %.xml %.html %.doc %.pdf %.txt: sources/images %.adoc | bundle
# 	FILENAME=$^; \
# 	${COMPILE_CMD}
#
# documents/draft-%.nits:	documents/draft-%.txt
# 	VERSIONED_NAME=`grep :name: draft-$*.adoc | cut -f 2 -d ' '`; \
# 	cp $^ $${VERSIONED_NAME}.txt && \
# 	idnits --verbose $${VERSIONED_NAME}.txt > $@ && \
# 	cp $@ $${VERSIONED_NAME}.nits && \
# 	cat $${VERSIONED_NAME}.nits

%.nits:

%.adoc:

nits: $(NITS)

define FORMAT_TASKS
OUT_FILES-$(FORMAT) := $($(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))

open-$(FORMAT):
	open $$(OUT_FILES-$(FORMAT))

clean-$(FORMAT):
	rm -f $$(OUT_FILES-$(FORMAT))

$(FORMAT): clean-$(FORMAT) $$(OUT_FILES-$(FORMAT))

.PHONY: clean-$(FORMAT)

endef

$(foreach FORMAT,$(FORMATS),$(eval $(FORMAT_TASKS)))

open: open-html

clean:
	rm -rf documents documents.html documents.rxl published *_images sources/plantuml/* $(OUT_FILES)

bundle:
	if [ "x" == "${METANORMA_DOCKER}x" ]; then bundle; fi

.PHONY: bundle all open clean

#
# Watch-related jobs
#

.PHONY: watch serve watch-serve

NODE_BINS          := onchange live-serve run-p
NODE_BIN_DIR       := node_modules/.bin
NODE_PACKAGE_PATHS := $(foreach PACKAGE_NAME,$(NODE_BINS),$(NODE_BIN_DIR)/$(PACKAGE_NAME))

$(NODE_PACKAGE_PATHS): package.json
	npm i

watch: $(NODE_BIN_DIR)/onchange
	make all
	$< $(ALL_SRC) -- make all

define WATCH_TASKS
watch-$(FORMAT): $(NODE_BIN_DIR)/onchange
	make $(FORMAT)
	$$< $$(SRC_$(FORMAT)) -- make $(FORMAT)

.PHONY: watch-$(FORMAT)
endef

$(foreach FORMAT,$(FORMATS),$(eval $(WATCH_TASKS)))

serve: $(NODE_BIN_DIR)/live-server revealjs-css reveal.js
	export PORT=$${PORT:-8123} ; \
	port=$${PORT} ; \
	for html in $(HTML); do \
		$< --entry-file=$$html --port=$${port} --ignore="*.html,*.xml,Makefile,Gemfile.*,package.*.json" --wait=1000 & \
		port=$$(( port++ )) ;\
	done

watch-serve: $(NODE_BIN_DIR)/run-p
	$< watch serve

#
# Deploy jobs
#

publish: published

published: documents.html
	mkdir -p $@ && \
	cp -a documents $@/ && \
	cp $< $@/index.html; \
	if [ -d "sources/images" ]; then cp -a sources/images $@/; fi
