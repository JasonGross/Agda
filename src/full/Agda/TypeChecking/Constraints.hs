{-# LANGUAGE CPP #-}
module Agda.TypeChecking.Constraints where

import System.IO

import Control.Monad.State
import Control.Monad.Reader
import Control.Monad.Error
import Control.Applicative
import Data.Map as Map
import Data.List as List
import Data.Set as Set

import Agda.Syntax.Common
import Agda.Syntax.Internal
import Agda.Syntax.Scope.Base
import Agda.TypeChecking.Monad
import Agda.TypeChecking.Errors
import Agda.TypeChecking.Pretty
import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Substitute
import Agda.TypeChecking.LevelConstraints
import Agda.TypeChecking.MetaVars.Mention

import {-# SOURCE #-} Agda.TypeChecking.Rules.Term (checkExpr)
import {-# SOURCE #-} Agda.TypeChecking.Conversion
import {-# SOURCE #-} Agda.TypeChecking.MetaVars
import {-# SOURCE #-} Agda.TypeChecking.Empty
import {-# SOURCE #-} Agda.TypeChecking.UniversePolymorphism
import Agda.TypeChecking.Free

import Agda.Utils.Fresh
import Agda.Utils.Monad

#include "../undefined.h"
import Agda.Utils.Impossible

-- | Catches pattern violation errors and adds a constraint.
--
catchConstraint :: MonadTCM tcm => Constraint -> TCM () -> tcm ()
catchConstraint c v = liftTCM $
   catchError_ v $ \err ->
   case errError err of
        -- Not putting s (which should really be the what's already there) makes things go
        -- a lot slower (+20% total time on standard library). How is that possible??
        -- The problem is most likely that there are internal catchErrors which forgets the
        -- state. catchError should preserve the state on pattern violations.
       PatternErr s -> put s >> addConstraint c
       _	    -> throwError err

addConstraint :: MonadTCM tcm => Constraint -> tcm ()
addConstraint c = do
    reportSDoc "tc.constr.add" 20 $ text "adding constraint" <+> prettyTCM c
    c' <- simpl =<< instantiateFull c
    when (c /= c') $ reportSDoc "tc.constr.add" 20 $ text "  simplified:" <+> prettyTCM c'
    addConstraint' c'
  where
    simpl :: MonadTCM tcm => Constraint -> tcm Constraint
    simpl c = do
      n <- genericLength <$> getContext
      simplifyLevelConstraint n c <$> getAllConstraints

-- | Don't allow the argument to produce any constraints.
noConstraints :: MonadTCM tcm => tcm a -> tcm a
noConstraints problem = do
  pid <- fresh
  x  <- solvingProblem pid problem
  cs <- getConstraintsForProblem pid
  unless (List.null cs) $ typeError $ UnsolvedConstraints cs 
  return x

ifNoConstraints :: MonadTCM tcm => tcm a -> (a -> tcm b) -> (ProblemId -> a -> tcm b) -> tcm b
ifNoConstraints check ifNo ifCs = do
  pid <- fresh
  x <- solvingProblem pid check
  ifM (isProblemSolved pid) (ifNo x) (ifCs pid x)

ifNoConstraints_ :: MonadTCM tcm => tcm () -> tcm a -> (ProblemId -> tcm a) -> tcm a
ifNoConstraints_ check ifNo ifCs = ifNoConstraints check (const ifNo) (\pid _ -> ifCs pid)

-- | @guardConstraint cs c@ tries to solve constraints @cs@ first.
--   If successful, it moves on to solve @c@, otherwise it returns
--   a @Guarded c cs@.
guardConstraint :: MonadTCM tcm => Constraint -> tcm () -> tcm ()
guardConstraint c blocker =
  ifNoConstraints_ blocker (solveConstraint_ c) (addConstraint . Guarded c)

whenConstraints :: MonadTCM tcm => tcm () -> tcm () -> tcm ()
whenConstraints action handler =
  ifNoConstraints_ action (return ()) $ \pid -> do
    stealConstraints pid
    handler

-- | Wake up the constraints depending on the given meta.
wakeupConstraints :: MonadTCM tcm => MetaId -> tcm ()
wakeupConstraints x = do
  wakeConstraints (mentionsMeta x)
  solveAwakeConstraints

-- | Wake up all constraints.
wakeupConstraints_ :: MonadTCM tcm => tcm ()
wakeupConstraints_ = do
  wakeConstraints (const True)
  solveAwakeConstraints

solveAwakeConstraints :: MonadTCM tcm => tcm ()
solveAwakeConstraints = do
    verboseS "profile.constraints" 10 $ liftTCM $ tickMax "max-open-constraints" . genericLength =<< getAllConstraints
    unlessM isSolvingConstraints $ nowSolvingConstraints solve
  where
    solve = do
      reportSDoc "tc.constr.solve" 10 $ hsep [ text "Solving awake constraints."
                                             , text . show . length =<< getAwakeConstraints
                                             , text "remaining." ]
      mc <- takeAwakeConstraint
      flip (maybe $ return ()) mc $ \c -> do
        withConstraint solveConstraint c
        solve

solveConstraint :: MonadTCM tcm => Constraint -> tcm ()
solveConstraint c = do
    verboseS "profile.constraints" 10 $ liftTCM $ tick "attempted-constraints"
    verboseBracket "tc.constr.solve" 20 "solving constraint" $ do
      reportSDoc "tc.constr.solve" 20 $ prettyTCM c
      solveConstraint_ c

solveConstraint_ (ValueCmp cmp a u v)       = compareTerm cmp a u v
solveConstraint_ (ElimCmp cmp a e u v)      = compareElims cmp a e u v
solveConstraint_ (TypeCmp cmp a b)          = compareType cmp a b
solveConstraint_ (TelCmp a b cmp tela telb) = compareTel a b cmp tela telb
solveConstraint_ (SortCmp cmp s1 s2)        = compareSort cmp s1 s2
solveConstraint_ (LevelCmp cmp a b)         = compareLevel cmp a b
solveConstraint_ c0@(Guarded c pid)         = do
  ifM (isProblemSolved pid) (solveConstraint_ c)
                            (addConstraint c0)
solveConstraint_ (IsEmpty t)                = isEmptyType t
solveConstraint_ (UnBlock m)                =
  ifM (isFrozen m) (addConstraint $ UnBlock m) $ do
    inst <- mvInstantiation <$> lookupMeta m
    reportSDoc "tc.constr.unblock" 15 $ text ("unblocking a metavar yields the constraint: " ++ show inst)
    case inst of
      BlockedConst t -> do
        reportSDoc "tc.constr.blocked" 15 $
          text ("blocked const " ++ show m ++ " :=") <+> prettyTCM t
        assignTerm m t
      PostponedTypeCheckingProblem cl -> enterClosure cl $ \(e, t, unblock) -> do
        b <- liftTCM unblock
        if not b
          then addConstraint $ UnBlock m
          else do
            tel <- getContextTelescope
            v   <- liftTCM $ checkExpr e t
            assignTerm m $ teleLam tel v
      -- Andreas, 2009-02-09, the following were IMPOSSIBLE cases
      -- somehow they pop up in the context of sized types
      --
      -- already solved metavariables: should only happen for size
      -- metas (not sure why it does, Andreas?)
      InstV{} -> return ()
      InstS{} -> return ()
      -- Open (whatever that means)
      Open -> __IMPOSSIBLE__
      OpenIFS -> __IMPOSSIBLE__
solveConstraint_ (FindInScope m)      =
  ifM (isFrozen m) (addConstraint $ FindInScope m) $ do
    reportSDoc "tc.constr.findInScope" 15 $ text ("findInScope constraint: " ++ show m)
    mv <- lookupMeta m
    let j = mvJudgement mv
    case j of
      IsSort{} -> __IMPOSSIBLE__
      HasType _ tj -> do
        ctx <- getContextVars
        ctxArgs <- getContextArgs
        t <- normalise $ tj `piApply` ctxArgs
        reportSLn "tc.constr.findInScope" 15 $ "findInScope t: " ++ show t
        let candsP1 = [(term, t) | (term, t, Instance) <- ctx]
        let candsP2 = [(term, t) | (term, t, h) <- ctx, h /= Instance]
        let scopeInfo = getMetaScope mv
        let ns = everythingInScope scopeInfo
        let nsList = Map.toList $ nsNames ns
        -- try all abstract names in scope (even ones that you can't refer to
        --  unambiguously)
        let candsP3Names = nsList >>= snd
        candsP3Types <- mapM (typeOfConst . anameName) candsP3Names
        candsP3FV <- mapM (freeVarsToApply . anameName) candsP3Names
        let candsP3 = [(Def (anameName an) vs, t) |
                       (an, t, vs) <- zip3 candsP3Names candsP3Types candsP3FV]
        let cands = [candsP1, candsP2, candsP3]
        cands <- mapM (filterM (uncurry $ checkCandidateForMeta m t )) cands
        let iterCands :: MonadTCM tcm => [(Int, [(Term, Type)])] -> tcm ()
            iterCands [] = do reportSDoc "tc.constr.findInScope" 15 $ text "not a single candidate found..."
                              typeError $ IFSNoCandidateInScope t
            iterCands ((p, []) : cs) = do reportSDoc "tc.constr.findInScope" 15 $ text $
                                            "no candidates found at p=" ++ show p ++ ", trying next p..."
                                          iterCands cs
            iterCands ((p, [(term, t')]):_) =
              do reportSDoc "tc.constr.findInScope" 15 $ text (
                   "one candidate at p=" ++ show p ++ " found for type '") <+>
                   prettyTCM t <+> text "': '" <+> prettyTCM term <+>
                   text "', of type '" <+> prettyTCM t' <+> text "'."
                 leqType t t'
                 assignV m ctxArgs term
            iterCands ((p, cs):_) = do reportSDoc "tc.constr.findInScope" 15 $
                                         text ("still more than one candidate at p=" ++ show p ++ ": ") <+>
                                         prettyTCM (List.map fst cs)
                                       addConstraint $ FindInScope m
        iterCands [(1,concat cands)]
      where
        getContextVars :: MonadTCM tcm => tcm [(Term, Type, Hiding)]
        getContextVars = do
          ctx <- getContext
          let ids = [0.. fromIntegral (length ctx) - 1] :: [Nat]
          types <- mapM typeOfBV ids
          return $ [ (Var i [], t, h) | (Arg h _ _, i, t) <- zip3 ctx [0..] types ]
        checkCandidateForMeta :: (MonadTCM tcm) => MetaId -> Type -> Term -> Type -> tcm Bool
        checkCandidateForMeta m t term t' =
          liftTCM $ flip catchError (\err -> return False) $ do
            reportSLn "tc.constr.findInScope" 20 $ "checkCandidateForMeta t: " ++ show t ++ "; t':" ++ show t' ++ "; term: " ++ show term ++ "."
            localState $ do
               -- domi: we assume that nothing below performs direct IO (except
               -- for logging and such, I guess)
               leqType t t'
               tel <- getContextTelescope
               assignTerm m (teleLam tel term)
               -- make a pass over constraints, to detect cases where some are made
               -- unsolvable by the assignment, but don't do this for FindInScope's
               -- to prevent loops. We currently also ignore UnBlock constraints
               -- to be on the safe side.
               wakeConstraints (isSimpleConstraint . clValue . theConstraint)
               solveAwakeConstraints
            return True
        isSimpleConstraint :: Constraint -> Bool
        isSimpleConstraint FindInScope{} = False
        isSimpleConstraint UnBlock{}     = False
        isSimpleConstraint _             = True

localState :: MonadState s m => m a -> m a
localState m = do
  s <- get
  x <- m
  put s
  return x
