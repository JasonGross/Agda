{-# LANGUAGE CPP, TupleSections #-}

module Agda.TypeChecking.Rules.LHS.ProblemRest where

import Agda.Syntax.Common
-- import Agda.Syntax.Position
-- import Agda.Syntax.Info
import Agda.Syntax.Internal as I
import qualified Agda.Syntax.Abstract as A

import Agda.TypeChecking.Monad
import Agda.TypeChecking.Pretty
-- import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Telescope
-- import Agda.TypeChecking.Implicit
import Agda.TypeChecking.Substitute
-- import Agda.TypeChecking.Pretty

import Agda.TypeChecking.Rules.LHS.Problem
import Agda.TypeChecking.Rules.LHS.Implicit

import Agda.Utils.Monad (($>))
import Agda.Utils.Size
import Agda.Utils.Permutation

#include "../../../undefined.h"
import Agda.Utils.Impossible


-- MOVED from LHS:
-- | Rename the variables in a telescope using the names from a given pattern
useNamesFromPattern :: [A.NamedArg A.Pattern] -> Telescope -> Telescope
useNamesFromPattern ps = telFromList . zipWith ren (toPats ps ++ repeat dummy) . telToList
  where
    dummy = A.WildP __IMPOSSIBLE__
    ren (A.VarP x) (Dom info (_, a)) | notHidden info = Dom info (show x, a)
    -- Andreas, 2013-03-13: inserted the following line in the hope to fix issue 819
    -- but it does not do the job, instead, it puts a lot of "_"s
    -- instead of more sensible names into error messages.
    -- ren A.WildP{}  (Dom info (_, a)) | notHidden info = Dom info ("_", a)
    ren A.PatternSynP{} _ = __IMPOSSIBLE__  -- ensure there are no syns left
    ren _ a = a
    toPats = map namedArg

-- | Are there any untyped user patterns left?
noProblemRest :: Problem -> Bool
noProblemRest (Problem _ _ _ (ProblemRest ps _)) = null ps

{- UNUSED and OUTDATED
-- | Get the type of clause.  Only valid if 'noProblemRest'.
typeFromProblem :: Problem -> Type
typeFromProblem (Problem _ _ _ (ProblemRest _ a)) = a
-}

-- | Construct an initial 'split' 'Problem' from user patterns.
--   Example:
--   @
--
--      Case : {A : Set} → Maybe A → Set → Set → Set
--      Case nothing  B C = B
--      Case (just _) B C = C
--
--      sample : {A : Set} (m : Maybe A) → Case m Bool (Maybe A → Bool)
--      sample (just a) (just b) = true
--      sample (just a) nothing  = false
--      sample nothing           = true
--   @
--   The problem generated for the first clause of @sample@
--   with patterns @just a, just b@ would be:
--   @
--      problemInPat  = ["_", "just a"]
--      problemOutPat = [identity-permutation, ["A", "m"]]
--      problemTel    = [A : Set, m : Maybe A]
--      problemRest   =
--        restPats    = ["just b"]
--        restType    = "Case m Bool (Maybe A -> Bool)"
--   @

problemFromPats :: [A.NamedArg A.Pattern] -- ^ The user patterns.
  -> Type            -- ^ The type the user patterns eliminate.
  -> TCM Problem     -- ^ The initial problem constructed from the user patterns.
problemFromPats ps a = do
  TelV tel0' b0 <- telView a
  -- For the initial problem, do not insert trailing implicits.
  -- This has the effect of not including trailing hidden domains in the problem telescope.
  -- In all later call to insertImplicitPatterns, we can then use ExpandLast.
  ps <- insertImplicitPatterns DontExpandLast ps tel0' :: TCM [A.NamedArg A.Pattern]
  -- unless (size tel0' >= size ps) $ typeError $ TooManyArgumentsInLHS a

  -- Redo the telView, in order to *not* normalize the clause type further than necessary.
  -- (See issue 734.)
  TelV tel0 b  <- telViewUpTo (length ps) a
  let gamma     = useNamesFromPattern ps tel0
      as        = telToList gamma
      (ps1,ps2) = splitAt (size as) ps
      -- now (gamma -> b) = a and |gamma| = |ps1|
      pr        = ProblemRest ps2 $ defaultArg b

      -- internal patterns start as all variables
      namedVar x = Named (Just x) (VarP x)
  ips <- mapM (return . argFromDom . fmap (namedVar . fst)) as

      -- the initial problem for starting the splitting
  let problem  = Problem ps1 (idP $ size ps1, ips) gamma pr :: Problem
  reportSDoc "tc.lhs.problem" 10 $
    vcat [ text "checking lhs -- generated an initial split problem:"
         , nest 2 $ vcat
           [ text "ps    =" <+> fsep (map prettyA ps)
           , text "a     =" <+> prettyTCM a
           , text "xs    =" <+> text (show $ map (fst . unDom) as)
           , text "ps1   =" <+> fsep (map prettyA ps1)
        -- , text "ips   =" <+> prettyTCM ips  -- no prettyTCM instance
           , text "gamma =" <+> prettyTCM gamma
           , text "ps2   =" <+> fsep (map prettyA ps2)
           , text "b     =" <+> addCtxTel gamma (prettyTCM b)
           ]
         ]
  return problem

{-
todoProblemRest :: ProblemRest
todoProblemRest = mempty
-}

-- | Try to move patterns from the problem rest into the problem.
--   Possible if type of problem rest has been updated to a function type.
updateProblemRest_ :: Problem -> TCM (Nat, Problem)
updateProblemRest_ p@(Problem _ _ _ (ProblemRest [] _)) = return (0, p)
updateProblemRest_ p@(Problem ps0 (perm0@(Perm n0 is0), qs0) tel0 (ProblemRest ps a)) = do
  TelV tel' b0 <- telView $ unArg a
  case tel' of
    EmptyTel -> return (0, p)  -- no progress
    ExtendTel{} -> do     -- a did reduce to a pi-type
      ps <- insertImplicitPatterns DontExpandLast ps tel'
      -- Issue 734: Redo the telView to preserve clause types as much as possible.
      TelV tel b   <- telViewUpTo (length ps) $ unArg a
      let gamma     = useNamesFromPattern ps tel
          as        = telToList gamma
          (ps1,ps2) = splitAt (size as) ps
          tel1      = telFromList $ telToList tel0 ++ as
          pr        = ProblemRest ps2 (a $> b)
          qs1       = map (argFromDom . fmap (namedVarP . fst)) as
          n         = size as
          perm1     = liftP n perm0 -- IS: Perm (n0 + n) $ is0 ++ [n0..n0+n-1]
      reportSDoc "tc.lhs.problem" 10 $ addCtxTel tel0 $ vcat
        [ text "checking lhs -- updated split problem:"
        , nest 2 $ vcat
          [ text "ps    =" <+> fsep (map prettyA ps)
          , text "a     =" <+> prettyTCM a
          , text "xs    =" <+> text (show $ map (fst . unDom) as)
          , text "ps1   =" <+> fsep (map prettyA ps1)
          , text "gamma =" <+> prettyTCM gamma
          , text "ps2   =" <+> fsep (map prettyA ps2)
          , text "b     =" <+> addCtxTel gamma (prettyTCM b)
          ]
        ]
      return $ (n,) $ Problem (ps0 ++ ps1) (perm1, raise n qs0 ++ qs1) tel1 pr

updateProblemRest :: LHSState -> TCM LHSState
updateProblemRest st@LHSState { lhsProblem = p } = do
  (n, p') <- updateProblemRest_ p
  if (n == 0) then return st else do
    let tau = raiseS n
    return $ LHSState
      { lhsProblem = p'
      , lhsSubst   = applySubst tau (lhsSubst st)
      , lhsDPI     = applySubst tau (lhsDPI st)
      , lhsAsB     = applySubst tau (lhsAsB st)
      }
