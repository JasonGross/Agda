{-# LANGUAGE CPP #-}

module Agda.Interaction.MakeCase where

import Prelude hiding (mapM, mapM_)
import Control.Applicative
import Control.Monad hiding (mapM, mapM_)
import Data.Maybe
import Data.Traversable

import Agda.Syntax.Common
import Agda.Syntax.Position
import qualified Agda.Syntax.Abstract as A
import qualified Agda.Syntax.Info as A
import Agda.Syntax.Internal
import Agda.Syntax.Translation.InternalToAbstract

import Agda.TypeChecking.Monad
import Agda.TypeChecking.Coverage
import Agda.TypeChecking.Pretty
import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Substitute
import Agda.TypeChecking.Irrelevance
import Agda.TypeChecker

import Agda.Interaction.BasicOps

import Agda.Utils.Monad
import qualified Agda.Utils.HashMap as HMap

#include "../undefined.h"
import Agda.Utils.Impossible

data CaseContext = FunctionDef | ExtendedLambda Int Int
                 deriving (Eq)
-- | Find the clause whose right hand side is the given meta
-- BY SEARCHING THE WHOLE SIGNATURE. Returns
-- the original clause, before record patterns have been translated
-- away. Raises an error if there is no matching clause.
--
-- Andreas, 2010-09-21: This looks like a SUPER UGLY HACK to me. You are
-- walking through the WHOLE signature to find an information you have
-- thrown away earlier.  (shutter with disgust).
-- This code fails for record rhs because they have been eta-expanded,
-- so the MVar is gone.
findClause :: MetaId -> TCM (CaseContext, QName, Clause)
findClause m = do
  sig <- getImportedSignature
  let res = do
        def <- HMap.elems $ sigDefinitions sig
        Function{funClauses = cs, funExtLam = extlam} <- [theDef def]
        c <- cs
        unless (rhsIsm $ clauseBody c) []
        return (defName def, c, extlam)
  case res of
    []  -> do
      reportSDoc "interaction.case" 10 $ vcat $
        [ text "Interaction.MakeCase.findClause fails"
        , text "expected rhs to be meta var" <+> (text $ show m)
        , text "but could not find it in the signature"
        ]
      reportSDoc "interaction.case" 100 $ vcat $ map (text . show) (HMap.elems $ sigDefinitions sig)  -- you asked for it!
      ifM (isInstantiatedMeta m)
        -- Andreas, 2012-03-22 If the goal has been solved by eta expansion, further
        -- case splitting is pointless and `smart-ass Agda' will refuse.
        -- Maybe not the best solution, but the lazy alternative to replace this
        -- SUPER UGLY HACK.
        (typeError $ GenericError "Since goal is solved, further case distinction is not supported; try `Solve constraints' instead")
        (typeError $ GenericError "Right hand side must be a single hole when making a case distinction")
    [(n,c, Just (h, nh))] -> return (ExtendedLambda h nh , n , c)
    [(n,c, Nothing)]      -> return (FunctionDef , n , c)
    _   -> __IMPOSSIBLE__
  where
    rhsIsm (Bind b)   = rhsIsm $ unAbs b
    rhsIsm NoBody     = False
    rhsIsm (Body e)   = case ignoreSharing e of
      MetaV m' _  -> m == m'
      _           -> False

makeCase :: InteractionId -> Range -> String -> TCM (CaseContext , [A.Clause])
makeCase hole rng s = withInteractionId hole $ do
  meta <- lookupInteractionId hole
  (casectxt, f, clause@(Clause{ clauseTel = tel, clausePerm = perm, namedClausePats = ps })) <- findClause meta
  reportSDoc "interaction.case" 10 $ vcat
    [ text "splitting clause:"
    , nest 2 $ vcat
      [ text "f       =" <+> prettyTCM f
      , text "context =" <+> (prettyTCM =<< getContextTelescope)
      , text "tel     =" <+> prettyTCM tel
      , text "perm    =" <+> text (show perm)
      , text "ps      =" <+> text (show ps)
      ]
    ]
  vars <- mapM (\s -> deBruijnIndex =<< parseExprIn hole rng s) $ words s
  (,) casectxt <$> split f vars clause
  where
  split :: QName -> [Nat] -> Clause -> TCM [A.Clause]
  split f [] clause =
    (:[]) <$> makeAbstractClause f (clauseToSplitClause clause)
  split f (var : vars) clause = do
    z <- splitClauseWithAbs clause var
    case z of
      Left err          -> typeError $ SplitError err
      Right (Left cl)   -> (:[]) <$> makeAbsurdClause f cl
      Right (Right cov)
        | null vars -> mapM (makeAbstractClause f) $ splitClauses cov
        | otherwise -> concat <$> do
            mapM (\cl -> split f (mapMaybe (newVar cl) vars)
                                 (splitClauseToClause cl))
                 $ splitClauses cov
    where
    -- Note that the body of the created clause is the body of the
    -- argument to split.
    splitClauseToClause :: SplitClause -> Clause
    splitClauseToClause c = Clause
      { clauseRange     = noRange
      , clauseTel       = scTel c
      , clausePerm      = scPerm c
      , namedClausePats = scPats c
      , clauseBody      = clauseBody clause
      , clauseType      = scTarget c
      }

  -- Finds the new variable corresponding to an old one, if any.
  newVar :: SplitClause -> Nat -> Maybe Nat
  newVar c x = case ignoreSharing $ applySubst (scSubst c) (Var x []) of
    Var x [] -> Just x
    _        -> Nothing

  -- NOTE: clauseToSplitClause moved to Coverage.hs

makeAbsurdClause :: QName -> SplitClause -> TCM A.Clause
makeAbsurdClause f (SClause tel perm ps _ t) = do
  reportSDoc "interaction.case" 10 $ vcat
    [ text "Interaction.MakeCase.makeCase: split clause:"
    , nest 2 $ vcat
      [ text "context =" <+> (prettyTCM =<< getContextTelescope)
      , text "tel =" <+> prettyTCM tel
      , text "perm =" <+> text (show perm)
      , text "ps =" <+> text (show ps)
      ]
    ]
  withCurrentModule (qnameModule f) $ do
    -- Normalise the dot patterns
    ps <- addCtxTel tel $ normalise ps
    inContext [] $ reify $ QNamed f $ Clause noRange tel perm ps NoBody t

-- | Make a clause with a question mark as rhs.
makeAbstractClause :: QName -> SplitClause -> TCM A.Clause
makeAbstractClause f cl = do
  A.Clause lhs _ _ <- makeAbsurdClause f cl
  return $ mkClause lhs
  where
    mkClause :: A.LHS -> A.Clause
    mkClause lhs = A.Clause lhs (A.RHS $ A.QuestionMark A.emptyMetaInfo) []

deBruijnIndex :: A.Expr -> TCM Nat
deBruijnIndex e = do
  (v, _) <- -- Andreas, 2010-09-21 allow splitting on irrelevant (record) vars
--            Context.wakeIrrelevantVars $
            applyRelevanceToContext Irrelevant $
              inferExpr e
  case ignoreSharing v of
    Var n _ -> return n
    _       -> typeError . GenericError . show =<< (fsep $
                pwords "The scrutinee of a case distinction must be a variable,"
                ++ [ prettyTCM v ] ++ pwords "isn't.")
