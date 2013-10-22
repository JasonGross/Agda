{-# LANGUAGE CPP, PatternGuards, TypeSynonymInstances, FlexibleInstances #-}
-- Initially authored by Andreas, 2013-10-22.

-- | A bidirectional type checker for internal syntax.
--
--   Performs checking on unreduced terms.
--   With the exception that projection-like function applications
--   have to be reduced since they break bidirectionality.

module Agda.TypeChecking.CheckInternal
  ( checkType
  , checkInternal
  ) where

import Control.Applicative
import Control.Monad

import Data.Maybe

import Agda.Syntax.Common
import Agda.Syntax.Internal as I

import Agda.TypeChecking.Conversion
import Agda.TypeChecking.Datatypes (getConType)
import Agda.TypeChecking.Level
import Agda.TypeChecking.Monad
import Agda.TypeChecking.Monad.Builtin
import Agda.TypeChecking.Pretty
import Agda.TypeChecking.ProjectionLike (elimView)
-- import Agda.TypeChecking.Records (projectionType)
import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Substitute
import Agda.TypeChecking.Telescope

import Agda.Utils.Size
import Agda.Utils.Impossible
#include "../undefined.h"

-- | Entry point for e.g. checking WithFunctionType.
checkType :: Type -> TCM ()
checkType t = -- dontAssignMetas $ ignoreSorts $
  checkInternal (unEl t) (sort Inf)

{- Alternative algorithm (does not buy us much)
--
--   This algorithm follows
--     Abel, Coquand, Dybjer, MPC 08
--     Verifying a Semantic βη-Conversion Test for Martin-Löf Type Theory

checkType :: Type -> TCM ()
checkType t = void $ checkType' t

-- | Check a type and infer its sort.
checkType' :: Type -> TCM Sort
checkType' t = do
  reportSDoc "tc.check.internal" 20 $ sep
    [ text "checking internal type "
    , prettyTCM t
    ]
  v <- elimView $ unEl t -- bring projection-like funs in post-fix form
  case ignoreSharing v of
    Pi a b -> do
      s1 <- checkType' $ unDom a
      s2 <- (b $>) <$> do
        addCtxString (absName b) a $ do
          checkType' $ absBody b
      return $ dLub s1 s2
    Sort s -> do
      checkSort s
      return $ sSuc s
    Var i es   -> do
      a <- typeOfBV i
      checkTypeSpine a (Var i   []) es
    Def f es   -> do  -- not a projection-like fun
      a <- defType <$> getConstInfo f
      checkTypeSpine a (Def f   []) es
    MetaV x es -> do -- we assume meta instantiations to be well-typed
      a <- metaType x
      checkTypeSpine a (MetaV x []) es
    v@Lam{}    -> typeError $ InvalidType v
    v@Con{}    -> typeError $ InvalidType v
    v@Lit{}    -> typeError $ InvalidType v
    v@Level{}  -> typeError $ InvalidType v
    DontCare v -> checkType' $ t $> v
    Shared{}   -> __IMPOSSIBLE__

checkTypeSpine :: Type -> Term -> Elims -> TCM Sort
checkTypeSpine a self es = shouldBeSort =<< inferSpine a self es
-}

-- | Entry point for term checking.
checkInternal :: Term -> Type -> TCM ()
checkInternal v t = do
  reportSDoc "tc.check.internal" 20 $ sep
    [ text "checking internal "
    , prettyTCM v
    , text " : "
    , prettyTCM t
    ]
  -- BAD: elimView crashes on unreduced terms!!
  -- v <- elimView v  -- bring projection-like funs in post-fix form
  case ignoreSharing v of
    Var i es   -> do
      a <- typeOfBV i
      checkSpine a (Var i   []) es t
{-  DOES NOT HELP in the treatment of projection-like functions:

    Def f (Apply a : es) -> checkDef' f a es t -- possibly proj.like
    Def f es             -> checkDef  f   es t  -- not a projection-like fun
-}
    Def f es   -> checkDef f es t
    MetaV x es -> do -- we assume meta instantiations to be well-typed
      a <- metaType x
      checkSpine a (MetaV x []) es t
    Con c vs   -> do
      -- we need to fully apply the constructor to make getConType work
      TelV tel t <- telView t
      addCtxTel tel $ do
        let failure = typeError $ DoesNotConstructAnElementOf (conName c) t
            vs'     = raise (size tel) vs ++ teleArgs tel
        a <- maybe failure return =<< getConType c t
        checkArgs a  (Con c   []) vs' t
    Lit l      -> litType l >>= (`subtype` t)
    Lam ai vb  -> do
      (a, b) <- shouldBePi t
      checkArgInfo ai $ domInfo a
      addCtxString (suggest vb b) a $ do
        checkInternal (absBody vb) (absBody b)
    Pi a b     -> do
      s <- shouldBeSort t
      let st = sort s
      checkInternal (unEl $ unDom a) st
      addCtxString (absName b) a $ do
        checkInternal (unEl $ absBody b) $ raise 1 st
    Sort s     -> do
      checkSort s  -- this ensures @s /= Inf@
      (sSuc s `leqSort`) =<< shouldBeSort t
    Level l    -> do
      checkLevel l
      levelType >>= (`subtype` t)
    DontCare v -> checkInternal v t
    Shared{}   -> __IMPOSSIBLE__

-- | Check function application.
checkDef :: QName -> Elims -> Type -> TCM ()
checkDef f es t = do
  def <- getConstInfo f
  if isJust $ isProjection_ $ theDef def then do
     -- we have to reduce away a projection-like function in head position
     -- because we might not be able to infer the type of its principal
     -- argument (it could be a Con)
     -- TODO: a reduce that reduces ONLY projection-like functions
     (`checkInternal` t) =<< elimView =<< reduce (Def f es)
   else checkSpine (defType def) (Def f []) es t

{-
-- | Check ordinary function application.
checkDef :: QName -> Elims -> Type -> TCM ()
checkDef f es t = do
  a <- defType <$> getConstInfo f
  checkSpine a (Def f []) es t

-- | Check possibly projection-like function application
checkDef' :: QName -> I.Arg Term -> Elims -> Type -> TCM ()
checkDef' f a es t = do
  isProj <- isProjection f
  case isProj of
    Nothing -> checkDef f (Apply a : es) t
    Just Projection{} -> do
      let self = unArg a
      b <- infer self
      checkSpine b self (Proj f : es) t
-}

checkSpine :: Type -> Term -> Elims -> Type -> TCM ()
checkSpine a self es t = inferSpine a self es >>= (`subtype` t)

checkArgs :: Type -> Term -> Args -> Type -> TCM ()
checkArgs a self vs t = checkSpine a self (map Apply vs) t

checkArgInfo :: I.ArgInfo -> I.ArgInfo -> TCM ()
checkArgInfo ai ai' = do
  checkHiding    (getHiding ai)     (getHiding ai')
  checkRelevance (getRelevance ai)  (getRelevance ai')
  checkColor     (argInfoColors ai) (argInfoColors ai')

checkHiding    :: Hiding -> Hiding -> TCM ()
checkHiding    h h' = unless (h == h') $ typeError $ HidingMismatch h h'

checkRelevance :: Relevance -> Relevance -> TCM ()
checkRelevance r0 r0' = unless (r == r') $ typeError $ RelevanceMismatch r r'
  where
    r  = canon r0
    r' = canon r0'
    canon Forced    = Relevant
    canon UnusedArg = Relevant
    canon r         = r

checkColor     :: [Color] -> [Color] -> TCM ()
checkColor     c c' = unless (c == c') $ typeError $ ColorMismatch c c'
  -- TODO guilhem

{- THIS WAS TO HELP with projection-like functions, but illusional...

-- | Infer type of a neutral term.
infer :: Term -> TCM Type
infer v = do
  case ignoreSharing v of
    Var i es   -> do
      a <- typeOfBV i
      inferSpine a (Var i   []) es
    Def f (Apply a : es) -> inferDef' f a es -- possibly proj.like
    Def f es             -> inferDef  f   es -- not a projection-like fun
    MetaV x es -> do -- we assume meta instantiations to be well-typed
      a <- metaType x
      inferSpine a (MetaV x []) es
    Shared{} -> __IMPOSSIBLE__
    _ -> __IMPOSSIBLE__

-- | Infer ordinary function application.
inferDef :: QName -> Elims -> TCM Type
inferDef f es = do
  a <- defType <$> getConstInfo f
  inferSpine a (Def f []) es

-- | Infer possibly projection-like function application
inferDef' :: QName -> I.Arg Term -> Elims -> TCM Type
inferDef' f a es = do
  isProj <- isProjection f
  case isProj of
    Nothing -> inferDef f (Apply a : es)
    Just Projection{} -> do
      let self = unArg a
      b <- infer self
      inferSpine b self (Proj f : es)
-}

-- | @inferSpine t self es@ checks that spine @es@ eliminates
--   value @self@ of type @t@ and returns the remaining type
--   (target of elimination).
inferSpine :: Type -> Term -> Elims -> TCM Type
inferSpine t self [] = return t
inferSpine t self (e : es) =
  case e of
    Apply (Arg ai v) -> do
      (a, b) <- shouldBePi t
      checkArgInfo ai $ domInfo a
      checkInternal v $ unDom a
      inferSpine (b `absApp` v) (self `applyE` [e]) es
    -- case: projection or projection-like
    Proj f -> do
      (a, b) <- shouldBePi =<< shouldBeProjectible t f
      checkInternal self $ unDom a
      u <- f `applyDef` (argFromDom a $> self)
      inferSpine (b `absApp` self) u es

-- | Type should either be a record type of a type eligible for
--   the principal argument of projection-like functions.
shouldBeProjectible :: Type -> QName -> TCM Type
-- shouldBeProjectible t f = maybe failure return =<< projectionType t f
shouldBeProjectible t f = maybe failure return =<< getDefType f =<< reduce t
  where failure = typeError $ ShouldBeRecordType t
    -- TODO: more accurate error that makes sense also for proj.-like funs.

shouldBePi :: Type -> TCM (I.Dom Type, Abs Type)
shouldBePi t = do
  t <- reduce t
  case ignoreSharing $ unEl t of
    Pi a b -> return (a, b)
    _      -> typeError $ ShouldBePi t

shouldBeSort :: Type -> TCM Sort
shouldBeSort t = ifIsSort t return (typeError $ ShouldBeASort t)

ifIsSort :: Type -> (Sort -> TCM a) -> TCM a -> TCM a
ifIsSort t yes no = do
  t <- reduce t
  case ignoreSharing $ unEl t of
    Sort s -> yes s
    _      -> no

-- | Check if sort is well-formed.
checkSort :: Sort -> TCM ()
checkSort s =
  case s of
    Type l   -> checkLevel l
    Prop     -> __IMPOSSIBLE__
      -- the dummy Prop should not be part of a term we check
    Inf      -> typeError $ SetOmegaNotValidType
      -- we cannot have Setω on the lhs of the colon
    DLub a b -> do
      checkSort a
      addCtxString (absName b) (defaultDom (sort a)) $ do
        checkSort (absBody b)

-- | Check if level is well-formed.
checkLevel :: Level -> TCM ()
checkLevel (Max ls) = mapM_ checkPlusLevel ls
  where
    checkPlusLevel ClosedLevel{} = return ()
    checkPlusLevel (Plus _ l)    = checkLevelAtom l

    checkLevelAtom l = do
      lvl <- levelType
      case l of
        MetaLevel x es   -> checkInternal (MetaV x es) lvl
        BlockedLevel x v -> checkInternal v lvl
        NeutralLevel v   -> checkInternal v lvl
        UnreducedLevel v -> checkInternal v lvl

-- | Type of a term or sort meta.
metaType :: MetaId -> TCM Type
metaType x = jMetaType . mvJudgement <$> lookupMeta x

-- | Universe subsumption and type equality (subtyping for sizes, resp.).
subtype :: Type -> Type -> TCM ()
subtype t1 t2 = do
  ifIsSort t1 (\ s1 -> (s1 `leqSort`) =<< shouldBeSort t2) $
    leqType t1 t2
