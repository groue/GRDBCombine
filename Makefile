GIT := $(shell command -v git)
JAZZY := $(shell command -v jazzy)
SOURCEKITTEN := $(shell command -v sourcekitten)
SWIFT := $(shell command -v xcrun swift)

doc:
ifdef JAZZY
ifdef SOURCEKITTEN
	$(SWIFT) build
	$(SOURCEKITTEN) doc --spm-module GRDBCombine > Documentation/GRDBCombine.json
	$(JAZZY) \
	  --clean \
	  --sourcekitten-sourcefile Documentation/GRDBCombine.json \
	  --author 'Gwendal Roué' \
	  --author_url https://github.com/groue \
	  --github_url https://github.com/groue/GRDBCombine \
	  --github-file-prefix https://github.com/groue/GRDBCombine/tree/v0.5.0 \
	  --module-version 0.5 \
	  --module GRDBCombine \
	  --root-url https://groue.github.io/GRDBCombine/docs/0.5/ \
	  --output Documentation/0.5
else
	@echo SourceKitten must be installed for doc: brew install sourcekitten
	@exit 1
endif
else
	@echo Jazzy must be installed for doc: gem install jazzy
	@exit 1
endif

distclean:
	$(GIT) reset --hard
	$(GIT) clean -dffx .

.PHONY: distclean doc
