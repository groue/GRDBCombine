GIT := $(shell command -v git)
JAZZY := $(shell command -v jazzy)
POD := $(shell command -v pod)
SOURCEKITTEN := $(shell command -v sourcekitten)
SWIFT := $(shell command -v xcrun swift)

XCPRETTY = 
XCPRETTY_PATH := $(shell command -v xcpretty 2> /dev/null)
ifdef XCPRETTY_PATH
  XCPRETTY = | xcpretty -c
  ifeq ($(TRAVIS),true)
    XCPRETTY += -f `xcpretty-travis-formatter`
  endif
endif

# Avoid the "No output has been received in the last 10m0s" error on Travis:
COCOAPODS_EXTRA_TIME =
ifeq ($(TRAVIS),true)
  COCOAPODS_EXTRA_TIME = --verbose
endif

# ------------------------------------------------------------------------------

test: test_SPM test_install
test_install: test_CocoaPodsLint

test_SPM:
	$(SWIFT) package clean
	$(SWIFT) build
	$(SWIFT) build -c release
	set -o pipefail && $(SWIFT) test $(XCPRETTY)

test_CocoaPodsLint:
ifdef POD
	$(POD) repo update
	$(POD) lib lint --allow-warnings $(COCOAPODS_EXTRA_TIME)
else
	@echo CocoaPods must be installed for test_CocoaPodsLint
	@exit 1
endif

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
	  --github-file-prefix https://github.com/groue/GRDBCombine/tree/v1.0.0-beta.3 \
	  --module-version 1.0.0-beta.3 \
	  --module GRDBCombine \
	  --root-url https://groue.github.io/GRDBCombine/docs/1.0.0-beta.3/ \
	  --output Documentation/1.0.0-beta.3
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

.PHONY: distclean doc test
