{-# LANGUAGE CPP, TypeSynonymInstances #-}
{-# OPTIONS -fno-cse #-}

module Agda.Interaction.GhciTop
  ( module Agda.Interaction.GhciTop
  , module Agda.TypeChecker
  , module TM
  , module Agda.TypeChecking.MetaVars
  , module Agda.TypeChecking.Reduce
  , module Agda.TypeChecking.Errors

  , module Agda.Syntax.Position
  , module Agda.Syntax.Parser
  , module SCo
--  , module SC  -- trivial clash removal: remove all!
--  , module SA
--  , module SI
  , module Agda.Syntax.Scope.Base
  , module Agda.Syntax.Scope.Monad
  , module Agda.Syntax.Translation.ConcreteToAbstract
  , module Agda.Syntax.Translation.AbstractToConcrete
  , module Agda.Syntax.Translation.InternalToAbstract
  , module Agda.Syntax.Abstract.Name

  , module Agda.Interaction.Exceptions
  )
  where

import System.Directory
import System.IO.Unsafe
import Data.Char
import Data.IORef
import Data.Function
import Control.Applicative
import qualified System.IO.UTF8 as UTF8

import Agda.Utils.Fresh
import Agda.Utils.Monad
import Agda.Utils.Monad.Undo
import Agda.Utils.Pretty as P
import Agda.Utils.String
import Agda.Utils.FileName
import Agda.Utils.Tuple

import Control.Monad.Error
import Control.Monad.Reader
import Control.Monad.State hiding (State)
import Control.Exception
import Data.List as List
import qualified Data.Map as Map
import System.Exit
import qualified System.Mem as System

import Agda.TypeChecker
import Agda.TypeChecking.Monad as TM
  hiding (initState, setCommandLineOptions)
import qualified Agda.TypeChecking.Monad as TM
import Agda.TypeChecking.MetaVars
import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Errors
import Agda.TypeChecking.Serialise (encodeFile)

import Agda.Syntax.Position
import Agda.Syntax.Parser
import qualified Agda.Syntax.Parser.Tokens as T
import Agda.Syntax.Concrete as SC
import Agda.Syntax.Common as SCo
import Agda.Syntax.Concrete.Name as CN
import Agda.Syntax.Concrete.Pretty ()
import Agda.Syntax.Abstract as SA
import Agda.Syntax.Abstract.Pretty
import Agda.Syntax.Internal as SI
import Agda.Syntax.Scope.Base
import Agda.Syntax.Scope.Monad hiding (bindName, withCurrentModule)
import qualified Agda.Syntax.Info as Info
import Agda.Syntax.Translation.ConcreteToAbstract
import Agda.Syntax.Translation.AbstractToConcrete hiding (withScope)
import Agda.Syntax.Translation.InternalToAbstract
import Agda.Syntax.Abstract.Name

import Agda.Interaction.Exceptions
import Agda.Interaction.Options
import Agda.Interaction.MakeCase
import qualified Agda.Interaction.BasicOps as B
import qualified Agda.Interaction.CommandLine.CommandLine as CL
import Agda.Interaction.Highlighting.Emacs
import Agda.Interaction.Highlighting.Generate
import qualified Agda.Interaction.Imports as Imp

import Agda.Termination.TermCheck

import qualified Agda.Compiler.MAlonzo.Compiler as MAlonzo

#include "../undefined.h"
import Agda.Utils.Impossible

data State = State
  { theTCState           :: TCState
  , theUndoStack         :: [TCState]
  , theTopLevel          :: Maybe TopLevelInfo
    -- ^ Invariant: The 'TopLevelInfo' corresponds to a type-correct
    --   module.
  , theInteractionPoints :: [InteractionId]
    -- ^ The interaction points of the buffer, in the order in which
    --   they appear in the buffer. The interaction points are
    --   recorded in 'theTCState', but when new interaction points are
    --   added by give or refine Agda does not ensure that the ranges
    --   of later interaction points are updated.
  }

initState :: State
initState = State
  { theTCState           = TM.initState
  , theUndoStack         = []
  , theTopLevel          = Nothing
  , theInteractionPoints = []
  }

{-# NOINLINE theState #-}
theState :: IORef State
theState = unsafePerformIO $ newIORef initState

ioTCM :: TCM a -> IO a
ioTCM cmd = infoOnException $ do
  State { theTCState   = st
        , theUndoStack = us
        } <- readIORef theState
  r <- runTCM $ do
      putUndoStack us
      put st
      x <- withEnv initEnv cmd
      st <- get
      us <- getUndoStack
      return (x,st,us)
  case r of
    Right (a,st',ss') -> do
      modifyIORef theState $ \s ->
        s { theTCState = st'
          , theUndoStack = ss'
          }
      return a
    Left err -> displayErrorAndExit (Left err)

-- | @cmd_load m includes@ loads the module in file @m@, using
-- @includes@ as the include directories.

cmd_load :: FilePath -> [FilePath] -> IO ()
cmd_load m includes =
  cmd_load' m includes True (\_ -> return ()) cmd_metas

-- | @cmd_load' m includes cmd cmd2@ loads the module in file @m@,
-- using @includes@ as the include directories.
--
-- If type checking completes without any exceptions having been
-- encountered then the command @cmd r@ is executed, where @r@ is the
-- second component of the result of 'Imp.createInterface'.
--
-- The command @cmd2@ is executed as the final step of @cmd_load'@,
-- unless an exception is encountered.

cmd_load' :: FilePath -> [FilePath]
          -> Bool -- ^ Allow unsolved meta-variables?
          -> (Imp.CreateInterfaceResult -> TCM ()) -> IO ()
          -> IO ()
cmd_load' file includes unsolvedOK cmd cmd2 = infoOnException $ do
    -- canonicalizePath seems to return absolute paths.
    file <- liftIO $ canonicalizePath file
    clearSyntaxInfo file
    ioTCM $ do
            clearUndoHistory
	    preserveDecodedModules resetState
            decodedModules <- stDecodedModules <$> get
            setUndo

            -- All options are reset when a file is reloaded,
            -- including the choice of whether or not to display
            -- implicit arguments.
            (topLevel, ok) <- Imp.createInterface
              (defaultOptions { optGenerateEmacsFile = True
                              , optAllowUnsolved     = unsolvedOK
                              , optIncludeDirs       = includes })
              noTrace [] Map.empty
              decodedModules emptySignature
              Map.empty Nothing file True

            -- The module type checked, so let us store the abstract
            -- syntax information and the interaction points.
            is <- sortInteractionPoints =<< getInteractionPoints
            liftIO $ modifyIORef theState $ \s ->
              s { theTopLevel          = Just topLevel
                , theInteractionPoints = is
                }
            cmd ok

            -- tellEmacsToReloadSyntaxInfo should run before
            -- tellEmacsToUpdateGoals, because the latter can change
            -- the contents of the buffer, and this can invalidate the
            -- ranges of the syntax-info.
            liftIO tellEmacsToReloadSyntaxInfo
            liftIO tellEmacsToUpdateGoals

    cmd2
    System.performGC

-- | @cmd_compile m includes@ compiles the module in file @m@, using
-- @includes@ as the include directories.

cmd_compile :: FilePath -> [FilePath] -> IO ()
cmd_compile file includes =
  cmd_load' file includes False (\r ->
    case r of
      Imp.Success { Imp.cirInterface = i } -> do
        MAlonzo.compilerMain (return i)
        display_info "*Compilation result*"
                   "The module was successfully compiled."
      Imp.Warnings {} ->
        display_info errorTitle $ unlines
          [ "You can only compile modules without unsolved metavariables"
          , "or termination checking problems."
          ])
    (return ())

cmd_constraints :: IO ()
cmd_constraints = ioTCM $ do
    cs <- map show <$> B.getConstraints
    display_info "*Constraints*" (unlines cs)


cmd_metas :: IO ()
cmd_metas = ioTCM $ do -- CL.showMetas []
  ims <- fst <$> B.typeOfMetas B.AsIs
  hms <- snd <$> B.typeOfMetas B.Normalised -- show unsolved implicit arguments normalised
  di <- mapM (\i -> B.withInteractionId (B.outputFormId i) (showA i)) ims
  dh <- mapM showA' hms
  display_info "*All Goals*" $ unlines $ di ++ dh
  where
    metaId (B.OfType i _) = i
    metaId (B.JustType i) = i
    metaId (B.JustSort i) = i
    metaId (B.Assign i e) = i
    metaId _ = __IMPOSSIBLE__
    showA' m = do
      r <- getMetaRange (metaId m)
      d <- B.withMetaId (B.outputFormId m) (showA m)
      return $ d ++ "  [ at " ++ show r ++ " ]"

cmd_undo :: IO ()
cmd_undo = ioTCM undo

cmd_reset :: IO ()
cmd_reset = ioTCM $ do putUndoStack []; preserveDecodedModules resetState

type GoalCommand = InteractionId -> Range -> String -> IO()

cmd_give :: GoalCommand
cmd_give = give_gen B.give $ \s ce -> case ce of (SC.Paren _ _)-> "'paren"
                                                 _             -> "'no-paren"

cmd_refine :: GoalCommand
cmd_refine = give_gen B.refine $ \s -> emacsStr . show

give_gen give_ref mk_newtxt ii rng s = do
    ioTCM $ do
      scope     <- getInteractionScope ii
      (ae, iis) <- give_ref ii Nothing =<< B.parseExprIn ii rng s
      let newtxt = A . mk_newtxt s $ abstractToConcrete (makeEnv scope) ae
      iis       <- sortInteractionPoints iis
      liftIO $ modifyIORef theState $ \s ->
                 s { theInteractionPoints =
                       replace ii iis (theInteractionPoints s) }
      liftIO $ UTF8.putStrLn $ response $
                 L [A "agda2-give-action", showNumIId ii, newtxt]
      liftIO tellEmacsToUpdateGoals
    cmd_metas
  where
  -- Substitutes xs for x in ys.
  replace x xs ys = concatMap (\y -> if y == x then xs else [y]) ys

-- | Sorts interaction points based on their ranges.

sortInteractionPoints :: [InteractionId] -> TCM [InteractionId]
sortInteractionPoints is =
  map fst . sortBy (compare `on` snd) <$>
    mapM (\i -> (,) i <$> getInteractionRange i) is

-- | Pretty-prints the type of the meta-variable.

prettyTypeOfMeta :: B.Rewrite -> InteractionId -> TCM Doc
prettyTypeOfMeta norm ii = do
  form <- B.typeOfMeta norm ii
  case form of
    B.OfType _ e -> prettyA e
    _            -> text <$> showA form

-- | Pretty-prints the context of the given meta-variable.

prettyContext
  :: B.Rewrite      -- ^ Normalise?
  -> InteractionId
  -> TCM Doc
prettyContext norm ii = B.withInteractionId ii $ do
  ctx <- B.contextOfMeta ii norm
  es  <- mapM (prettyA . B.ofExpr) ctx
  ns  <- mapM (showA   . B.ofName) ctx
  let maxLen = maximum $ 0 : filter (< longNameLength) (map length ns)
  return $ vcat $
           map (\(n, e) -> text n $$ nest (maxLen + 1) (text ":") <+> e) $
           zip ns es

-- | 'prettyContext' lays out @n : e@ on (at least) two lines if @n@
-- has at least @longNameLength@ characters.

longNameLength = 10

cmd_context :: B.Rewrite -> GoalCommand
cmd_context norm ii _ _ = ioTCM $
  display_infoD "*Context*" =<< prettyContext norm ii

cmd_infer :: B.Rewrite -> GoalCommand
cmd_infer norm ii rng s = ioTCM $
  display_infoD "*Inferred Type*"
    =<< B.withInteractionId ii
          (prettyA =<< B.typeInMeta ii norm =<< B.parseExprIn ii rng s)

cmd_goal_type :: B.Rewrite -> GoalCommand
cmd_goal_type norm ii _ _ = ioTCM $ do
    s <- B.withInteractionId ii $ prettyTypeOfMeta norm ii
    display_infoD "*Current Goal*" s

-- | Displays the current goal and context plus the given document.

cmd_goal_type_context_and :: Doc -> B.Rewrite -> GoalCommand
cmd_goal_type_context_and s norm ii _ _ = ioTCM $ do
    goal <- B.withInteractionId ii $ prettyTypeOfMeta norm ii
    ctx  <- prettyContext norm ii
    display_infoD "*Goal type etc.*"
                  (ctx $+$
                   text (replicate 60 '\x2014') $+$
                   text "Goal:" <+> goal $+$
                   s)

-- | Displays the current goal and context.

cmd_goal_type_context :: B.Rewrite -> GoalCommand
cmd_goal_type_context = cmd_goal_type_context_and P.empty

-- | Displays the current goal and context /and/ infers the type of an
-- expression.

cmd_goal_type_context_infer :: B.Rewrite -> GoalCommand
cmd_goal_type_context_infer norm ii rng s = ioTCM $ do
    typ <- B.withInteractionId ii $
             prettyA =<< B.typeInMeta ii norm =<< B.parseExprIn ii rng s
    liftIO $ cmd_goal_type_context_and
               (text "Have:" <+> typ)
               norm ii rng s

-- | Sets the command line options and updates the status information.

setCommandLineOptions :: CommandLineOptions -> TCM ()
setCommandLineOptions opts = do
  TM.setCommandLineOptions opts
  displayStatus

-- | Displays\/updates some status information (currently just
-- indicates whether or not implicit arguments are shown).

displayStatus :: TCM ()
displayStatus = do
  showImpl <- showImplicitArguments
  let statusString = if showImpl then "ShowImplicit" else ""
  liftIO $ UTF8.putStrLn $ response $
    L [A "agda2-status-action", A (quote statusString)]

-- | @display_info header content@ displays @content@ (with header
-- @header@) in some suitable way, and also displays some status
-- information (see 'displayStatus').

display_info :: String -> String -> TCM ()
display_info bufname content = do
  displayStatus
  liftIO $ UTF8.putStrLn $ response $
    L [ A "agda2-info-action"
      , A (quote bufname)
      , A (quote content)
      ]

-- | Like 'display_info', but takes a 'Doc' instead of a 'String'.

display_infoD :: String -> Doc -> TCM ()
display_infoD bufname content = display_info bufname (render content)

response :: Lisp String -> String
response l = show (text "agda2_mode_code" <+> pretty l)

data Lisp a = A a | L [Lisp a] | Q (Lisp a)

instance Pretty a => Pretty (Lisp a) where
  pretty (A a ) = pretty a
  pretty (L xs) = parens (sep (List.map pretty xs))
  pretty (Q x)  = text "'"<>pretty x

instance Pretty String where pretty = text

instance Pretty a => Show (Lisp a) where show = show . pretty

showNumIId = A . tail . show

takenNameStr :: TCM [String]
takenNameStr = do
  xss <- sequence [ List.map (fst . unArg) <$> getContext
                  , Map.keys <$> asks envLetBindings
                  , List.map qnameName . Map.keys . sigDefinitions <$> getSignature
		  ]
  return $ concat [ parts $ nameConcrete x | x <- concat xss]
  where
    parts x = [ s | Id s <- nameParts x ]

refreshStr :: [String] -> String -> ([String], String)
refreshStr taken s = go nameModifiers where
  go (m:mods) = let s' = s ++ m in
                if s' `elem` taken then go mods else (s':taken, s')
  go _        = __IMPOSSIBLE__

nameModifiers = "" : "'" : "''" : [show i | i <-[3..]]

cmd_make_case :: GoalCommand
cmd_make_case ii rng s = ioTCM $ do
  cs <- makeCase ii rng s
  B.withInteractionId ii $ do
    pcs <- mapM prettyA cs
    liftIO $ UTF8.putStrLn $ response $
      L [ A "agda2-make-case-action",
          Q $ L $ List.map (A . quote . show) pcs
        ]

cmd_solveAll :: IO ()
cmd_solveAll = ioTCM $ do
    out <- getInsts
    liftIO $ UTF8.putStrLn $ response $
      L[ A"agda2-solveAll-action" , Q . L $ concatMap prn out]
  where
  getInsts = mapM lowr =<< B.getSolvedInteractionPoints
    where
      lowr (i, m, e) = do
        mi <- getMetaInfo <$> lookupMeta m
        e <- withMetaInfo mi $ lowerMeta <$> abstractToConcrete_ e
        return (i, e)
  prn (ii,e)= [showNumIId ii, A $ emacsStr $ show e]

class LowerMeta a where lowerMeta :: a -> a
instance LowerMeta SC.Expr where
  lowerMeta = go where
    go e = case e of
      Ident _              -> e
      SC.Lit _             -> e
      SC.QuestionMark _ _  -> preMeta
      SC.Underscore _ _    -> preUscore
      SC.App r e1 ae2      -> case appView e of
        SC.AppView (SC.QuestionMark _ _) _ -> preMeta
        SC.AppView (SC.Underscore   _ _) _ -> preUscore
        _ -> SC.App r (go e1) (lowerMeta ae2)
      SC.WithApp r e es	   -> SC.WithApp r (lowerMeta e) (lowerMeta es)
      SC.Lam r bs e1       -> SC.Lam r (lowerMeta bs) (go e1)
      SC.AbsurdLam r h     -> SC.AbsurdLam r h
      SC.Fun r ae1 e2      -> SC.Fun r (lowerMeta ae1) (go e2)
      SC.Pi tb e1          -> SC.Pi (lowerMeta tb) (go e1)
      SC.Set _             -> e
      SC.Prop _            -> e
      SC.SetN _ _          -> e
      SC.Let r ds e1       -> SC.Let r (lowerMeta ds) (go e1)
      Paren r e1           -> case go e1 of
        q@(SC.QuestionMark _ Nothing) -> q
        e2                            -> Paren r e2
      Absurd _          -> e
      As r n e1         -> As r n (go e1)
      SC.Dot r e	-> SC.Dot r (go e)
      SC.RawApp r es	-> SC.RawApp r (lowerMeta es)
      SC.OpApp r x es	-> SC.OpApp r x (lowerMeta es)
      SC.Rec r fs	-> SC.Rec r (List.map (id -*- lowerMeta) fs)
      SC.HiddenArg r e	-> SC.HiddenArg r (lowerMeta e)

instance LowerMeta SC.LamBinding where
  lowerMeta b@(SC.DomainFree _ _) = b
  lowerMeta (SC.DomainFull tb)    = SC.DomainFull (lowerMeta tb)

instance LowerMeta SC.TypedBindings where
  lowerMeta (SC.TypedBindings r h bs) = SC.TypedBindings r h (lowerMeta bs)

instance LowerMeta SC.TypedBinding where
  lowerMeta (SC.TBind r ns e) = SC.TBind r ns (lowerMeta e)
  lowerMeta (SC.TNoBind e)    = SC.TNoBind (lowerMeta e)

instance LowerMeta SC.RHS where
    lowerMeta (SC.RHS e)    = SC.RHS (lowerMeta e)
    lowerMeta  SC.AbsurdRHS = SC.AbsurdRHS

instance LowerMeta SC.Declaration where
  lowerMeta = go where
    go d = case d of
      TypeSig n e1            -> TypeSig n (lowerMeta e1)
      SC.Field n e1           -> SC.Field n (lowerMeta e1)
      FunClause lhs rhs whcl  -> FunClause lhs (lowerMeta rhs) (lowerMeta whcl)
      Data r ind n tel e1 cs  -> Data r ind n
                                 (lowerMeta tel) (lowerMeta e1) (lowerMeta cs)
      SC.Record r n tel e1 cs -> SC.Record r n
                                 (lowerMeta tel) (lowerMeta e1) (lowerMeta cs)
      Infix _ _               -> d
      Mutual r ds             -> Mutual r (lowerMeta ds)
      Abstract r ds           -> Abstract r (lowerMeta ds)
      Private r ds            -> Private r (lowerMeta ds)
      Postulate r sigs        -> Postulate r (lowerMeta sigs)
      SC.Primitive r sigs     -> SC.Primitive r (lowerMeta sigs)
      SC.Open _ _ _           -> d
      SC.Import _ _ _ _ _     -> d
      SC.Pragma _	      -> d
      ModuleMacro r n tel e1 op dir -> ModuleMacro r n
                                    (lowerMeta tel) (lowerMeta e1) op dir
      SC.Module r qn tel ds   -> SC.Module r qn (lowerMeta tel) (lowerMeta ds)

instance LowerMeta SC.WhereClause where
  lowerMeta SC.NoWhere		= SC.NoWhere
  lowerMeta (SC.AnyWhere ds)	= SC.AnyWhere $ lowerMeta ds
  lowerMeta (SC.SomeWhere m ds) = SC.SomeWhere m $ lowerMeta ds

instance LowerMeta a => LowerMeta [a] where
  lowerMeta as = List.map lowerMeta as

instance LowerMeta a => LowerMeta (Arg a) where
  lowerMeta aa = fmap lowerMeta aa

instance LowerMeta a => LowerMeta (Named name a) where
  lowerMeta aa = fmap lowerMeta aa


preMeta   = SC.QuestionMark noRange Nothing
preUscore = SC.Underscore   noRange Nothing

cmd_compute :: Bool -- ^ Ignore abstract?
               -> GoalCommand
cmd_compute ignore ii rng s = ioTCM $ do
  e <- B.parseExprIn ii rng s
  d <- B.withInteractionId ii $ do
         let c = B.evalInCurrent e
         v <- if ignore then ignoreAbstractMode c else c
         prettyA v
  display_info "*Normal Form*" (show d)

-- | Parses and scope checks an expression (using insideScope topLevel
-- as the scope), performs the given command with the expression as
-- input, and displays the result.

parseAndDoAtToplevel
  :: (SA.Expr -> TCM SA.Expr)
     -- ^ The command to perform.
  -> String
     -- ^ The name to used for the buffer displaying the output.
  -> String
     -- ^ The expression to parse.
  -> IO ()
parseAndDoAtToplevel cmd title s = infoOnException $ do
  e <- parse exprParser s
  mTopLevel <- theTopLevel <$> readIORef theState
  ioTCM $ display_info title =<<
    case mTopLevel of
      Nothing       -> return "Error: First load the file."
      Just topLevel -> do
        setScope $ insideScope topLevel
        showA =<< cmd =<< concreteToAbstract_ e

-- | Parse the given expression (as if it were defined at the
-- top-level of the current module) and infer its type.

cmd_infer_toplevel
  :: B.Rewrite  -- ^ Normalise the type?
  -> String
  -> IO ()
cmd_infer_toplevel norm =
  parseAndDoAtToplevel (B.typeInCurrent norm) "*Inferred Type*"

-- | Parse and type check the given expression (as if it were defined
-- at the top-level of the current module) and normalise it.

cmd_compute_toplevel :: Bool -- ^ Ignore abstract?
                     -> String -> IO ()
cmd_compute_toplevel ignore =
  parseAndDoAtToplevel (if ignore then ignoreAbstractMode . c else c)
                       "*Normal Form*"
  where c = B.evalInCurrent

-- change "\<decimal>" to a single character
-- TODO: This seems to be the wrong solution to the problem. Attack
-- the source instead.
emacsStr s = go (show s) where
  go ('\\':ns@(n:_))
     | isDigit n = toEnum (read digits :: Int) : go rest
     where (digits, rest) = span isDigit ns
  go (c:s) = c : go s
  go []    = []

------------------------------------------------------------------------
-- Syntax highlighting

-- | Tell the Emacs mode to rescan the buffer for goals.

tellEmacsToUpdateGoals :: IO ()
tellEmacsToUpdateGoals = do
  is <- theInteractionPoints <$> readIORef theState
  UTF8.putStrLn $ response $ L [A "agda2-annotate", format is]
  where format = Q . L . List.map showNumIId

-- | Tell the Emacs mode to reload the highlighting information.

tellEmacsToReloadSyntaxInfo :: IO ()
tellEmacsToReloadSyntaxInfo =
  UTF8.putStrLn $ response $ L [A "agda2-highlight-reload"]

-- | Tells the Emacs mode to reload the highlighting information and
-- go to the first error position (if any).

tellEmacsToJumpToError :: Range -> IO ()
tellEmacsToJumpToError r = do
  case rStart r of
    Nothing                                -> return ()
    -- Errors for expressions entered using the command line sometimes
    -- have an empty file name component. This should be fixed.
    Just (Pn { srcFile = "" })             -> return ()
    Just (Pn { srcFile = f,  posPos = p }) ->
      UTF8.putStrLn $ response $
        L [A "annotation-goto", Q $ L [A (show f), A ".", A (show p)]]
  tellEmacsToReloadSyntaxInfo

------------------------------------------------------------------------
-- Implicit arguments

-- | Tells Agda whether or not to show implicit arguments.

showImplicitArgs :: Bool -- ^ Show them?
                 -> IO ()
showImplicitArgs showImpl = ioTCM $ do
  opts <- commandLineOptions
  setCommandLineOptions (opts { optShowImplicit = showImpl })

-- | Toggle display of implicit arguments.

toggleImplicitArgs :: IO ()
toggleImplicitArgs = ioTCM $ do
  opts <- commandLineOptions
  setCommandLineOptions (opts { optShowImplicit =
                                  not $ optShowImplicit opts })

------------------------------------------------------------------------
-- Error handling

-- | When an error message is displayed the following title should be
-- used, if appropriate.

errorTitle :: String
errorTitle = "*Error*"

-- | Displays an error (represented either as a 'TCErr' or as a
-- 'Range' and a message) and terminates the program.

displayErrorAndExit :: Either TCErr (Range, String) -> IO a
displayErrorAndExit err = do
  runTCM $ do
    appendErrorToEmacsFile err'
    display_info errorTitle =<< msg
  tellEmacsToJumpToError rng
  exitWith (ExitFailure 1)
  where
  err' = case err of
    Left e           -> e
    Right (rng, msg) -> Exception rng msg

  msg = case err of
    Left e             -> prettyError e
    Right (rng, msg)
      | rng == noRange -> return msg
      | otherwise      -> return (show rng ++ "\n" ++ msg)

  rng = case err of
    Left  e          -> getRange e
    Right (rng, msg) -> rng

-- | Outermost error handler. Should wrap all functions called from
-- Emacs (directly or indirectly).

infoOnException m =
  failOnException inform m `catchImpossible` \e ->
    inform noRange (show e)
  where inform rng msg = displayErrorAndExit (Right (rng, msg))
