{-# OPTIONS -cpp -fglasgow-exts #-}

module TypeChecking.Conversion where

import Control.Monad
import Control.Monad.Error
import Data.Generics

import Syntax.Common
import Syntax.Internal
import TypeChecking.Monad
import TypeChecking.MetaVars
import TypeChecking.Substitute
import TypeChecking.Reduce
import TypeChecking.Constraints
import TypeChecking.Errors
import TypeChecking.Primitive (constructorForm)
import TypeChecking.Free

import Utils.Monad

import TypeChecking.Monad.Debug

#include "../undefined.h"

-- | Check if to lists of arguments are the same (and all variables).
--   Precondition: the lists have the same length.
sameVars :: Args -> Args -> Bool
sameVars xs ys = and $ zipWith same xs ys
    where
	same (Arg _ (Var n [])) (Arg _ (Var m [])) = n == m
	same _ _				   = False

-- | Type directed equality on values.
--
equalTerm :: (MonadError TCErr tcm, MonadTCM tcm) => Type -> Term -> Term -> tcm Constraints
equalTerm a m n =
    catchConstraint (ValueEq a m n) $
    do	a'	 <- reduce a
	proofIrr <- proofIrrelevance
	s	 <- reduce $ getSort a'
	case (proofIrr, s) of
	    (True, Prop)    -> return []
	    _		    ->
		case unEl a' of
		    Pi a _    -> equalFun (a,a') m n
		    Fun a _   -> equalFun (a,a') m n
		    MetaV x _ -> do
			(m,n) <- normalise (m,n)
			if m == n
			    then return []
			    else buildConstraint (ValueEq a m n)
		    Lam _ _   -> __IMPOSSIBLE__
		    _	      -> equalAtom a' m n
    where
	equalFun (a,t) m n =
	    do	name <- freshName_ (suggest $ unEl t)
		addCtx name (unArg a) $ equalTerm t' m' n'
	    where
		p	= fmap (const $ Var 0 []) a
		(m',n') = raise 1 (m,n) `apply` [p]
		t'	= raise 1 t `piApply'` [p]
		suggest (Fun _ _)	 = "x"
		suggest (Pi _ (Abs x _)) = x
		suggest _		 = __IMPOSSIBLE__

-- | Syntax directed equality on atomic values
--
equalAtom :: (MonadError TCErr tcm, MonadTCM tcm) => Type -> Term -> Term -> tcm Constraints
equalAtom t m n =
    catchConstraint (ValueEq t m n) $
    do	m <- constructorForm =<< reduce m
	n <- constructorForm =<< reduce n
	verbose 10 $ do
	    dm <- prettyTCM m
	    dn <- prettyTCM n
	    dt <- prettyTCM t
	    debug $ "equalAtom " ++ show dm ++ " == " ++ show dn ++ " : " ++ show dt
	case (m, n) of
	    _ | f1@(FunV _ _) <- funView m
	      , f2@(FunV _ _) <- funView n -> equalFun f1 f2

	    (Sort s1, Sort s2) -> equalSort s1 s2

	    (Lit l1, Lit l2) | l1 == l2 -> return []
	    (Var i iArgs, Var j jArgs) | i == j -> do
		a <- typeOfBV i
		equalArg a iArgs jArgs
	    (Def x xArgs, Def y yArgs) | x == y -> do
		a <- defType <$> getConstInfo x
		equalArg a xArgs yArgs
	    (Con x xArgs, Con y yArgs)
		| x == y -> do
		    a <- defType <$> getConstInfo x
		    equalArg a xArgs yArgs
	    (MetaV x xArgs, MetaV y yArgs)
		| x == y -> if   sameVars xArgs yArgs
			    then return []
			    else buildConstraint (ValueEq t m n)
		| otherwise -> do
		    [p1, p2] <- mapM getMetaPriority [x,y]
		    -- instantiate later meta variables first
		    if (p1,x) > (p2,y) then assignV t x xArgs n	-- TODO: what if one works but not the other?
				       else assignV t y yArgs m
	    (MetaV x xArgs, _) -> assignV t x xArgs n
	    (_, MetaV x xArgs) -> assignV t x xArgs m
	    (BlockedV _, BlockedV _)	-> do
		n <- normalise n    -- is this what we want?
		m <- normalise m
		if m == n
		    then return []	-- Check syntactic equality for blocked terms
		    else buildConstraint (ValueEq t m n)
	    (BlockedV b, _)    -> buildConstraint (ValueEq t m n)
	    (_,BlockedV b)     -> buildConstraint (ValueEq t m n)
	    _		       -> typeError $ UnequalTerms m n t
    where
	equalFun (FunV (Arg h1 a1) t1) (FunV (Arg h2 a2) t2)
	    | h1 /= h2	= typeError $ UnequalHiding ty1 ty2
	    | otherwise = do
		    let (ty1',ty2') = raise 1 (ty1,ty2)
			arg	    = Arg h1 (Var 0 [])
		    name <- freshName_ (suggest t1 t2)
		    cs   <- equalType a1 a2
		    let c = TypeEq (piApply' ty1' [arg]) (piApply' ty2' [arg])

		    -- We only need to require a1 == a2 if t2 is a dependent function type.
		    -- If it's non-dependent it doesn't matter what we add to the context.
		    let dependent = case t2 of
					Pi _ _	-> True
					Fun _ _	-> False
					_	-> __IMPOSSIBLE__
		    if dependent
			then addCtx name a1 $ guardConstraint (return cs) c
			else do
			    cs' <- addCtx name a1 $ solveConstraint c
			    return $ cs ++ cs'
	    where
		ty1 = El (getSort a1) t1    -- TODO: wrong (but it doesn't matter)
		ty2 = El (getSort a2) t2
		suggest t1 t2 = case concatMap name [t1,t2] of
				    []	-> "_"
				    x:_	-> x
		    where
			name (Pi _ (Abs x _)) = [x]
			name (Fun _ _)	      = []
			name _		      = __IMPOSSIBLE__
	equalFun _ _ = __IMPOSSIBLE__



-- | Type-directed equality on argument lists
--
equalArg :: (MonadError TCErr tcm, MonadTCM tcm) => Type -> Args -> Args -> tcm Constraints
equalArg _ [] [] = return []
equalArg _ [] (_:_) = __IMPOSSIBLE__
equalArg _ (_:_) [] = __IMPOSSIBLE__
equalArg a (arg1 : args1) (arg2 : args2) = do
    a <- reduce a
    case funView (unEl a) of
	FunV (Arg _ b) _ -> do
	    verbose 10 $ do
		db <- prettyTCM b
		darg1 <- prettyTCM arg1
		darg2 <- prettyTCM arg2
		debug $ "equalArg " ++ show darg1 ++ "  ==  " ++ show darg2 ++ " : " ++ show db
            cs1 <- equalTerm b (unArg arg1) (unArg arg2)
	    case (cs1, unEl a) of
		(_:_, Pi _ c) | 0 `freeIn` absBody c
		    -> patternViolation   -- TODO: will duplicate work (all arguments checked so far)
		_   -> do
		    cs2 <- equalArg (piApply' a [arg1]) args1 args2
		    return $ cs1 ++ cs2
        _   -> patternViolation


-- | Equality on Types
equalType :: (MonadError TCErr tcm, MonadTCM tcm) => Type -> Type -> tcm Constraints
equalType ty1@(El s1 a1) ty2@(El s2 a2) =
    catchConstraint (TypeEq ty1 ty2) $ do
	verbose 9 $ do
	    d1 <- prettyTCM ty1
	    d2 <- prettyTCM ty2
	    s1 <- prettyTCM s1
	    s2 <- prettyTCM s2
	    debug $ "equalType " ++ show d1 ++ "  ==  " ++ show d2
	    debug $ "   sorts: " ++ show s1 ++ "  and  " ++ show s2
	cs1 <- equalSort s1 s2
	cs2 <- equalTerm (sort s1) a1 a2
	verbose 9 $ do
	    dcs <- mapM prettyTCM $ cs1 ++ cs2
	    debug $ "   --> " ++ show dcs
	return $ cs1 ++ cs2

leqType :: (MonadError TCErr tcm, MonadTCM tcm) => Type -> Type -> tcm Constraints
leqType ty1@(El s1 a1) ty2@(El s2 a2) = do
     -- TODO: catchConstraint (?)
    (a1, a2) <- reduce (a1,a2)
    case (a1, a2) of
	(Sort s1, Sort s2) -> leqSort s1 s2
	_		   -> equalType (El s1 a1) (El s2 a2)
	    -- TODO: subtyping for function types

---------------------------------------------------------------------------
-- * Sorts
---------------------------------------------------------------------------

-- | Check that the first sort is less or equal to the second.
leqSort :: (MonadError TCErr tcm, MonadTCM tcm) => Sort -> Sort -> tcm Constraints
leqSort s1 s2 =
    catchConstraint (SortEq s1 s2) $
    do	(s1,s2) <- reduce (s1,s2)
-- 	do  d1 <- prettyTCM s1
-- 	    d2 <- prettyTCM s2
-- 	    debug $ "leqSort   " ++ show d1 ++ " <= " ++ show d2
	case (s1,s2) of

	    (Prop    , Prop    )	     -> return []
	    (Type _  , Prop    )	     -> notLeq s1 s2
	    (Suc _   , Prop    )	     -> notLeq s1 s2

	    (Prop    , Type _  )	     -> return []
	    (Type n  , Type m  ) | n <= m    -> return []
				 | otherwise -> notLeq s1 s2
	    (Suc s   , Type n  ) | 1 <= n    -> leqSort s (Type $ n - 1)
				 | otherwise -> notLeq s1 s2
	    (_	     , Suc _   )	     -> equalSort s1 s2

	    (Lub a b , _       )	     -> liftM2 (++) (leqSort a s2) (leqSort b s2)
	    (_	     , Lub _ _ )	     -> equalSort s1 s2

	    (MetaS x , MetaS y ) | x == y    -> return []
	    (MetaS x , _       )	     -> equalSort s1 s2
	    (_	     , MetaS x )	     -> equalSort s1 s2
    where
	notLeq s1 s2 = typeError $ NotLeqSort s1 s2

-- | Check that the first sort equal to the second.
equalSort :: (MonadError TCErr tcm, MonadTCM tcm) => Sort -> Sort -> tcm Constraints
equalSort s1 s2 =
    catchConstraint (SortEq s1 s2) $
    do	(s1,s2) <- reduce (s1,s2)
-- 	do  d1 <- prettyTCM s1
-- 	    d2 <- prettyTCM s2
-- 	    debug $ "equalSort " ++ show d1 ++ " == " ++ show d2
	case (s1,s2) of

	    (MetaS x , MetaS y ) | x == y    -> return []
				 | otherwise -> do
		[p1, p2] <- mapM getMetaPriority [x, y]
		if p1 >= p2 then assignS x s2
			    else assignS y s1
	    (MetaS x , _       )	     -> assignS x s2
	    (_	     , MetaS x )	     -> equalSort s2 s1

	    (Prop    , Prop    )	     -> return []
	    (Type _  , Prop    )	     -> notEq s1 s2
	    (Prop    , Type _  )	     -> notEq s1 s2

	    (Type n  , Type m  ) | n == m    -> return []
				 | otherwise -> notEq s1 s2
	    (Suc s   , Prop    )	     -> notEq s1 s2
	    (Suc s   , Type 0  )	     -> notEq s1 s2
	    (Suc s   , Type 1  )	     -> buildConstraint (SortEq s1 s2)
	    (Suc s   , Type n  )	     -> equalSort s (Type $ n - 1)
	    (Prop    , Suc s   )	     -> notEq s1 s2
	    (Type 0  , Suc s   )	     -> notEq s1 s2
	    (Type 1  , Suc s   )	     -> buildConstraint (SortEq s1 s2)
	    (Type n  , Suc s   )	     -> equalSort (Type $ n - 1) s
	    (_	     , Suc _   )	     -> buildConstraint (SortEq s1 s2)
	    (Suc _   , _       )	     -> buildConstraint (SortEq s1 s2)

	    (Lub _ _ , _       )	     -> buildConstraint (SortEq s1 s2)
	    (_	     , Lub _ _ )	     -> buildConstraint (SortEq s1 s2)

    where
	notEq s1 s2 = typeError $ UnequalSorts s1 s2

