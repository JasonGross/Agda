# Top-level Makefile for Agda 2
# Authors: Ulf Norell, Nils Anders Danielsson

SHELL=bash
## Includes ###############################################################

TOP = .

is_configured = $(shell if test -f mk/config.mk; \
						then echo Yes; \
						else echo No; \
						fi \
				 )

include mk/paths.mk

ifeq ($(is_configured),Yes)
include mk/config.mk
include mk/rules.mk
endif


## Phony targets ##########################################################

.PHONY : default all clean install full prof core \
		 debug doc dist make_configure clean_test examples \
		 test tests succeed fail interaction benchmark up-to-date-std-lib \
		 install-lib install-bin install-emacs-mode

## Default target #########################################################

ifeq ($(is_configured),Yes)
default : install-bin
# tags
else
default : make_configure
endif

## Cabal-based installation ###############################################

# The cabal command.
CABAL_CMD=cabal

# Options used by cabal install.
CABAL_OPTIONS=
#  -f old-time
#  -f epic

ifeq ($(HAVE_GHC_7_7),Yes)
CABAL_OPTIONS+=--ghc-option=-j3
endif

install : install-bin compile-emacs-mode setup-emacs-mode

prof : install-prof-bin

# Installs the Emacs mode, but does not set it up.
install-bin :
	time $(CABAL_CMD) install --disable-library-profiling --disable-documentation $(CABAL_OPTIONS)

install-O0-bin :
	$(CABAL_CMD) install -O0 --disable-library-profiling --disable-documentation $(CABAL_OPTIONS)

install-O2-bin :
	$(CABAL_CMD) install -O2 --disable-library-profiling --disable-documentation $(CABAL_OPTIONS)

install-prof-bin :
	$(CABAL_CMD) install --enable-library-profiling --enable-executable-profiling \
                             --program-suffix=_p --disable-documentation $(CABAL_OPTIONS)

compile-emacs-mode : install-bin
	agda-mode compile

setup-emacs-mode : install-bin
	@echo
	@echo "If the agda-mode command is not found, make sure that the directory"
	@echo "in which it was installed is located on your shell's search path."
	@echo
	agda-mode setup

## Making the make system #################################################

m4_macros	= $(wildcard $(MACRO_DIR)/*.m4)

make_configure : configure
	@echo "Run './configure' to set up the build system."

configure : aclocal.m4 $(m4_macros) configure.ac
	autoconf

##
## The following targets are only available after running configure #######
##

ifeq ($(is_configured),Yes)

## Making the documentation ###############################################

doc :
	$(MAKE) -C $(HADDOCK_DIR)

## Making the full language ###############################################

ifeq ($(HAVE_RUNHASKELL),Yes)

SETUP	   = Setup.hs
RUNSETUP   = $(RUNHASKELL) $(SETUP)

else

SETUP	   = setup
RUNSETUP   = ./setup

$(SETUP) : Setup.hs
	ghc --make -o $@ $<

endif

CONFIG	= dist/setup-config
CABAL		= Agda.cabal
BUILD		= dist/build-complete
INPLACE = dist/installed-inplace
SOURCES = $(shell $(FIND) $(FULL_SRC_DIR) -name '*hs') \
					$(shell $(FIND) $(FULL_SRC_DIR) -name '*.y') \
					$(shell $(FIND) $(FULL_SRC_DIR) -name '*.x')

$(CONFIG) : $(CABAL) $(SETUP)
	$(RUNSETUP) configure

$(BUILD) : $(CONFIG) $(SOURCES)
	$(RUNSETUP) build
	@date > $@

$(INPLACE) : $(BUILD)
	$(RUNSETUP) register --user --inplace
	@date > $@

$(AGDA_BIN) : $(INPLACE) $(MAIN_SRC_DIR)/Main.hs
	$(MAKE) -C $(MAIN_SRC_DIR)

full : $(AGDA_BIN)

## Making the core language ###############################################

core :
	$(MAKE) -C $(CORE_SRC_DIR)

## Making the Agda 1 to Agda 2 translator #################################

transl :
	(cd $(TRANSL_SRC_DIR); cabal configure && cabal build)

## Making the source distribution #########################################

ifeq ($(HAVE_DARCS)-$(shell if test -d _darcs; then echo darcs; fi),Yes-darcs)
  is_darcs_repo = Yes
else
  is_darcs_repo = No
endif

ifeq ($(is_darcs_repo),Yes)

dist : agda2.tar.gz

agda2.tar.gz :
	$(DARCS) dist -d agda2

else

dist :
	@echo You can only "'make dist'" from the darcs repository.
	@$(FALSE)

endif

tags :
	$(MAKE) -C $(FULL_SRC_DIR) tags
TAGS :
	$(MAKE) -C $(FULL_SRC_DIR) TAGS

## Testing ###########################################################

quick : install-O0-bin quicktest

test : check-whitespace succeed fail interaction latex-test examples library-test lib-succeed # epic-test compiler-test tests

quicktest : succeed fail

tests :
	@echo "======================================================================"
	@echo "======================== Internal test suite ========================="
	@echo "======================================================================"
	$(AGDA_BIN) --test

succeed :
	@echo "======================================================================"
	@echo "===================== Suite of successfull tests ====================="
	@echo "======================================================================"
	@chmod +x test/succeed/checkOutput
	@$(MAKE) -C test/succeed

interaction :
	@echo "======================================================================"
	@echo "===================== Suite of interaction tests ====================="
	@echo "======================================================================"
	@$(MAKE) -C test/interaction

examples :
	@echo "======================================================================"
	@echo "========================= Suite of examples =========================="
	@echo "======================================================================"
	@$(MAKE) -C examples

fail :
	@echo "======================================================================"
	@echo "======================= Suite of failing tests ======================="
	@echo "======================================================================"
	@$(MAKE) -C test/fail

latex-test :
	@echo "======================================================================"
	@echo "================== Suite of tests for LaTeX backend =================="
	@echo "======================================================================"
	@$(MAKE) -C test/latex-backend clean all clean

std-lib :
	darcs get --lazy --repo-name=$@ \
		 http://www.cse.chalmers.se/~nad/repos/lib/

up-to-date-std-lib : std-lib
	@(cd std-lib && darcs pull -a && make setup)

library-test : # up-to-date-std-lib
	@echo "======================================================================"
	@echo "========================== Standard library =========================="
	@echo "======================================================================"
	@(cd std-lib && \
          time $(PWD)/$(AGDA_BIN) -i. -isrc README.agda $(AGDA_TEST_FLAGS) \
            +RTS -s)

continue-library-test :
	@(cd std-lib && \
          time $(PWD)/$(AGDA_BIN) -i. -isrc README.agda +RTS -s)

compiler-test : # up-to-date-std-lib
	@echo "======================================================================"
	@echo "============================== Compiler =============================="
	@echo "======================================================================"
	@(cd test/compiler && \
          time ../../$(AGDA_BIN) --compile -i. -i../../std-lib -i../../std-lib/src \
            Main.agda +RTS -H1G -M1.5G && \
          ./Main)

lib-succeed :
	@echo "======================================================================"
	@echo "========== Successfull tests using the standard library =============="
	@echo "======================================================================"
	@$(MAKE) -C test/$@

epic-test :
	@echo "======================================================================"
	@echo "============================ Epic backend ============================"
	@echo "======================================================================"
	@$(MAKE) -C test/epic

benchmark :
	@$(MAKE) -C benchmark

## Clean ##################################################################

clean :
	$(MAKE) -C $(HADDOCK_DIR) clean
	rm -rf $(OUT_DIR)
	rm -rf dist

veryclean :
	$(MAKE) -C $(HADDOCK_DIR) veryclean
	rm -rf $(OUT_DIR)
	rm -rf configure config.log config.status autom4te.cache mk/config.mk

## Debugging the Makefile #################################################

info :
	@echo "The agda binary is at:         $(AGDA_BIN)"
	@echo "Do we have ghc 7.7?            $(HAVE_GHC_7_7)"
	@echo "Is this the darcs repository?  $(is_darcs_repo)"
	@echo "Agda test flags are:           $(AGDA_TEST_FLAGS)"
	@echo "Cabal flags are:               $(CABAL_OPTIONS)"

else	# is_configured

info :
	@echo "You haven't run configure."

endif	# is_configured

## Whitespace-related #####################################################

# Agda can fail to compile on Windows if files which are CPP-processed
# don't end with a newline character (because we use -Werror).

.PHONY:
fix-whitespace :
	fix-agda-whitespace

.PHONY:
check-whitespace :
	fix-agda-whitespace --check

.PHONY:
install-fix-agda-whitespace :
	cd src/fix-agda-whitespace && \
	$(CABAL_CMD) install $(CABAL_OPTIONS)
