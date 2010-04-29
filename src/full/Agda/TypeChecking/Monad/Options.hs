{-# LANGUAGE CPP #-}

module Agda.TypeChecking.Monad.Options where

import Control.Monad.Reader
import Control.Monad.State
import Data.Maybe
import Text.PrettyPrint
import qualified Agda.Utils.IO.Locale as LocIO
import System.Directory
import System.FilePath

import Agda.TypeChecking.Monad.Base
import Agda.Interaction.Options
import Agda.Utils.FileName
import Agda.Utils.Monad
import Agda.Utils.List
import Agda.Utils.Trie (Trie)
import qualified Agda.Utils.Trie as Trie

#include "../../undefined.h"
import Agda.Utils.Impossible

-- | Sets the pragma options.

setPragmaOptions :: MonadTCM tcm => PragmaOptions -> tcm ()
setPragmaOptions opts = do
  clo <- commandLineOptions
  case checkOpts (clo { optPragmaOptions = opts }) of
    Left err   -> __IMPOSSIBLE__
    Right opts ->
      modify $ \s -> s { stPragmaOptions = optPragmaOptions opts }

-- | Sets the command line options (both persistent and pragma options
-- are updated).
--
-- Ensures that the 'optInputFile' field contains an absolute path.
--
-- An empty list of include directories is interpreted as @["."]@.

setCommandLineOptions :: MonadTCM tcm => CommandLineOptions -> tcm ()
setCommandLineOptions opts =
  case checkOpts opts of
    Left err   -> __IMPOSSIBLE__
    Right opts -> do
      opts <- case optInputFile opts of
        Nothing -> return opts
        Just f  -> do
          -- canonicalizePath seems to return absolute paths.
          f <- liftIO $ canonicalizePath f
          return (opts { optInputFile = Just f })
      let newOpts = opts { optIncludeDirs =
              case optIncludeDirs opts of
                [] -> ["."]
                is -> is
            }
      modify $ \s -> s { stPersistentOptions = newOpts
                       , stPragmaOptions     = optPragmaOptions newOpts
                       }

-- | Returns the pragma options which are currently in effect.

pragmaOptions :: MonadTCM tcm => tcm PragmaOptions
pragmaOptions = liftTCM $ gets stPragmaOptions

-- | Returns the command line options which are currently in effect.

commandLineOptions :: MonadTCM tcm => tcm CommandLineOptions
commandLineOptions = liftTCM $ do
  p  <- gets stPragmaOptions
  cl <- gets stPersistentOptions
  return $ cl { optPragmaOptions = p }

setOptionsFromPragma :: MonadTCM tcm => OptionsPragma -> tcm ()
setOptionsFromPragma ps = do
    opts <- commandLineOptions
    case parsePragmaOptions ps opts of
	Left err    -> typeError $ GenericError err
	Right opts' -> setPragmaOptions opts'

-- | Disable display forms.
enableDisplayForms :: MonadTCM tcm => tcm a -> tcm a
enableDisplayForms =
  local $ \e -> e { envDisplayFormsEnabled = True }

-- | Disable display forms.
disableDisplayForms :: MonadTCM tcm => tcm a -> tcm a
disableDisplayForms =
  local $ \e -> e { envDisplayFormsEnabled = False }

-- | Check if display forms are enabled.
displayFormsEnabled :: MonadTCM tcm => tcm Bool
displayFormsEnabled = asks envDisplayFormsEnabled

-- | Don't eta contract implicit
dontEtaContractImplicit :: MonadTCM tcm => tcm a -> tcm a
dontEtaContractImplicit = local $ \e -> e { envEtaContractImplicit = False }

-- | Do eta contract implicit
doEtaContractImplicit :: MonadTCM tcm => tcm a -> tcm a
doEtaContractImplicit = local $ \e -> e { envEtaContractImplicit = True }

shouldEtaContractImplicit :: MonadTCM tcm => tcm Bool
shouldEtaContractImplicit = asks envEtaContractImplicit

-- | Don't reify interaction points
dontReifyInteractionPoints :: MonadTCM tcm => tcm a -> tcm a
dontReifyInteractionPoints =
  local $ \e -> e { envReifyInteractionPoints = False }

shouldReifyInteractionPoints :: MonadTCM tcm => tcm Bool
shouldReifyInteractionPoints = asks envReifyInteractionPoints

-- | Gets the include directories.

getIncludeDirs :: MonadTCM tcm => tcm [AbsolutePath]
getIncludeDirs =
  map mkAbsolute . optIncludeDirs <$> commandLineOptions

-- | Makes the include directories absolute.
--
-- Relative directories are made absolute with respect to the given
-- path.

makeIncludeDirsAbsolute :: MonadTCM tcm => AbsolutePath -> tcm ()
makeIncludeDirsAbsolute root = do
  opts <- commandLineOptions
  setCommandLineOptions $
    opts { optIncludeDirs =
             map (filePath root </>) $ optIncludeDirs opts }

setInputFile :: MonadTCM tcm => FilePath -> tcm ()
setInputFile file =
    do	opts <- commandLineOptions
	setCommandLineOptions $
          opts { optInputFile = Just file }

-- | Should only be run if 'hasInputFile'.
getInputFile :: MonadTCM tcm => tcm FilePath
getInputFile =
    do	mf <- optInputFile <$> commandLineOptions
	case mf of
	    Just file	-> return file
	    Nothing	-> __IMPOSSIBLE__

hasInputFile :: MonadTCM tcm => tcm Bool
hasInputFile = isJust <$> optInputFile <$> commandLineOptions

proofIrrelevance :: MonadTCM tcm => tcm Bool
proofIrrelevance = optProofIrrelevance <$> pragmaOptions

hasUniversePolymorphism :: MonadTCM tcm => tcm Bool
hasUniversePolymorphism = optUniversePolymorphism <$> pragmaOptions

showImplicitArguments :: MonadTCM tcm => tcm Bool
showImplicitArguments = optShowImplicit <$> pragmaOptions

setShowImplicitArguments :: MonadTCM tcm => Bool -> tcm a -> tcm a
setShowImplicitArguments showImp ret = do
  opts <- pragmaOptions
  let imp = optShowImplicit opts
  setPragmaOptions $ opts { optShowImplicit = showImp }
  x <- ret
  opts <- pragmaOptions
  setPragmaOptions $ opts { optShowImplicit = imp }
  return x

ignoreInterfaces :: MonadTCM tcm => tcm Bool
ignoreInterfaces = optIgnoreInterfaces <$> commandLineOptions

positivityCheckEnabled :: MonadTCM tcm => tcm Bool
positivityCheckEnabled = not . optDisablePositivity <$> pragmaOptions

typeInType :: MonadTCM tcm => tcm Bool
typeInType = not . optUniverseCheck <$> pragmaOptions

getVerbosity :: MonadTCM tcm => tcm (Trie String Int)
getVerbosity = optVerbose <$> pragmaOptions

type VerboseKey = String

hasVerbosity :: MonadTCM tcm => VerboseKey -> Int -> tcm Bool
hasVerbosity k n | n < 0     = __IMPOSSIBLE__
                 | otherwise = do
    t <- getVerbosity
    let ks = wordsBy (`elem` ".:") k
	m  = maximum $ 0 : Trie.lookupPath ks t
    return (n <= m)

-- | Precondition: The level must be non-negative.
verboseS :: MonadTCM tcm => VerboseKey -> Int -> tcm () -> tcm ()
verboseS k n action = whenM (hasVerbosity k n) action

reportS :: MonadTCM tcm => VerboseKey -> Int -> String -> tcm ()
reportS k n s = verboseS k n $ liftIO $ LocIO.putStr s

reportSLn :: MonadTCM tcm => VerboseKey -> Int -> String -> tcm ()
reportSLn k n s = verboseS k n $ liftIO $ LocIO.putStrLn s

reportSDoc :: MonadTCM tcm => VerboseKey -> Int -> tcm Doc -> tcm ()
reportSDoc k n d = verboseS k n $ liftIO . LocIO.print =<< d

verboseBracket :: MonadTCM tcm => VerboseKey -> Int -> String -> tcm a -> tcm a
verboseBracket k n s m = do
  v <- hasVerbosity k n
  if not v then m
           else do
    liftIO $ LocIO.putStrLn $ "{ " ++ s
    x <- m
    liftIO $ LocIO.putStrLn "}"
    return x

