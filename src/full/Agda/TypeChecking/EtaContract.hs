{-# LANGUAGE CPP, PatternGuards #-}

-- | Compute eta short normal forms.
module Agda.TypeChecking.EtaContract where

import Agda.Syntax.Common hiding (Arg, Dom, NamedArg, ArgInfo)
import qualified Agda.Syntax.Common as Common
import Agda.Syntax.Internal
import Agda.Syntax.Internal.Generic
import Agda.TypeChecking.Substitute
import Agda.TypeChecking.Free
import Agda.TypeChecking.Monad
-- import {-# SOURCE #-} Agda.TypeChecking.Pretty
import {-# SOURCE #-} Agda.TypeChecking.Records
import {-# SOURCE #-} Agda.TypeChecking.Datatypes
import Agda.Utils.Monad

#include "../undefined.h"
import Agda.Utils.Impossible

-- TODO: move to Agda.Syntax.Internal.SomeThing
data BinAppView = App Term (Arg Term)
                | NoApp Term

binAppView :: Term -> BinAppView
binAppView t = case t of
  Var i xs   -> appE (Var i) xs
  Def c xs   -> appE (Def c) xs
  -- Andreas, 2013-09-17: do not eta-contract when body is (record) constructor
  -- like in \ x -> s , x!  (See interaction/DoNotEtaContractFunIntoRecord)
  -- (Cf. also issue 889 (fixed differently).)
  -- At least record constructors should be fully applied where possible!
  -- TODO: also for ordinary constructors (\ x -> suc x  vs.  suc)?
  Con c xs
    | null (conFields c) -> app (Con c) xs
    | otherwise          -> noApp
  Lit _      -> noApp
  Level _    -> noApp   -- could be an application, but let's not eta contract levels
  Lam _ _    -> noApp
  Pi _ _     -> noApp
  Sort _     -> noApp
  MetaV _ _  -> noApp
  DontCare _ -> noApp
  Shared p   -> binAppView (derefPtr p)  -- destroys sharing
  where
    noApp = NoApp t
    app f [] = noApp
    app f xs = App (f $ init xs) (last xs)
    appE f [] = noApp
    appE f xs
      | Apply v <- last xs = App (f $ init xs) v
      | otherwise          = noApp

-- | Contracts all eta-redexes it sees without reducing.
etaContract :: TermLike a => a -> TCM a
etaContract = traverseTermM etaOnce

etaOnce :: Term -> TCM Term
etaOnce v = do
  -- Andreas, 2012-11-18: this call to reportSDoc seems to cost me 2%
  -- performance on the std-lib
  -- reportSDoc "tc.eta" 70 $ text "eta-contracting" <+> prettyTCM v
  eta v
  where
    eta v@Shared{} = updateSharedTerm eta v
    eta t@(Lam i (Abs _ b)) = do  -- NoAbs can't be eta'd
      imp <- shouldEtaContractImplicit
      case binAppView b of
        App u (Common.Arg info v)
          | (isIrrelevant info || isVar0 v)
                    && allowed imp info
                    && not (freeIn 0 u) ->
            return $ subst __IMPOSSIBLE__ u
        _ -> return t
      where
        isVar0 (Shared p)               = isVar0 (derefPtr p)
        isVar0 (Var 0 [])               = True
        isVar0 (Level (Max [Plus 0 l])) = case l of
          NeutralLevel v   -> isVar0 v
          UnreducedLevel v -> isVar0 v
          BlockedLevel{}   -> False
          MetaLevel{}      -> False
        isVar0 _ = False
        allowed imp i' = getHiding i == getHiding i' && (imp || notHidden i)

    -- Andreas, 2012-12-18:  Abstract definitions could contain
    -- abstract records whose constructors are not in scope.
    -- To be able to eta-contract them, we ignore abstract.
    eta t@(Con c args) = ignoreAbstractMode $ do
      -- reportSDoc "tc.eta" 20 $ text "eta-contracting record" <+> prettyTCM t
      r <- getConstructorData $ conName c -- fails in ConcreteMode if c is abstract
      ifM (isEtaRecord r)
          (do -- reportSDoc "tc.eta" 20 $ text "eta-contracting record" <+> prettyTCM t
              etaContractRecord r c args)
          (return t)
    eta t = return t
