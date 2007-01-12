{-# OPTIONS -cpp #-}

module TypeChecking.MetaVars where

import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Error
import Data.Generics
import Data.Map (Map)
import Data.Set (Set)
import Data.List as List hiding (sort)
import qualified Data.Map as Map
import qualified Data.Set as Set

import Syntax.Common
import qualified Syntax.Info as Info
import Syntax.Internal
import Syntax.Position

import TypeChecking.Monad
import TypeChecking.Monad.Context
import TypeChecking.Reduce
import TypeChecking.Substitute
import TypeChecking.Constraints
import TypeChecking.Errors
import TypeChecking.Free

#ifndef __HADDOCK__
import {-# SOURCE #-} TypeChecking.Conversion
#endif

import Utils.Fresh
import Utils.List
import Utils.Monad

import TypeChecking.Monad.Debug

#include "../undefined.h"

-- | Find position of a value in a list.
--   Used to change metavar argument indices during assignment.
--
--   @reverse@ is necessary because we are directly abstracting over the list.
--
findIdx :: Eq a => [a] -> a -> Maybe Int
findIdx vs v = findIndex (==v) (reverse vs)

-- | Generate [Var n - 1, .., Var 0] for all declarations in the context.
--   Used to make arguments for newly generated metavars.
--
allCtxVars :: TCM Args
allCtxVars = do
    ctx <- asks envContext
    return $ reverse $ List.map (\i -> Arg NotHidden $ Var i []) $ [0 .. length ctx - 1]

-- | Check whether a meta variable is a place holder for a blocked term.
isBlockedTerm :: MetaId -> TCM Bool
isBlockedTerm x = do
    report 12 $ "is " ++ show x ++ " a blocked term? "
    i <- mvInstantiation <$> lookupMeta x
    let r = case i of
	    BlockedConst _ -> True
	    FirstOrder	   -> False
	    InstV _	   -> False
	    InstS _	   -> False
	    Open	   -> False
    reportLn 12 $ if r then "yes" else "no"
    return r

-- | Check if a meta variable is first order.
isFirstOrder :: MetaId -> TCM Bool
isFirstOrder x = do
    report 12 $ "is " ++ show x ++ " first order? "
    i <- mvInstantiation <$> lookupMeta x
    let r = case i of
	    FirstOrder	   -> True
	    BlockedConst _ -> False
	    InstV _	   -> False
	    InstS _	   -> False
	    Open	   -> False
    reportLn 12 $ if r then "yes" else "no"
    return r



class HasMeta t where
    metaInstance :: t -> MetaInstantiation
    metaVariable :: MetaId -> Args -> t

instance HasMeta Term where
    metaInstance = InstV
    metaVariable = MetaV

instance HasMeta Sort where
    metaInstance = InstS
    metaVariable x _ = MetaS x

-- | The instantiation should not be an 'InstV' or 'InstS' and the 'MetaId'
--   should point to something 'Open' or a 'BlockedConst'.
(=:) :: HasMeta t => MetaId -> t -> TCM ()
x =: t = do
    let i = metaInstance t
    store <- getMetaStore
    modify $ \st -> st { stMetaStore = ins x i store }
    wakeupConstraints
  where
    ins x i store = Map.adjust (inst i) x store
    inst i mv = mv { mvInstantiation = i }

assignTerm :: MetaId -> Term -> TCM ()
assignTerm = (=:)

newSortMeta ::  TCM Sort
newSortMeta = 
    do  i <- createMetaInfo
	MetaS <$> newMeta i (IsSort ())

newTypeMeta :: Sort -> TCM Type
newTypeMeta s = El s <$> newValueMeta (sort s)

newTypeMeta_ ::  TCM Type
newTypeMeta_  = newTypeMeta =<< newSortMeta

newValueMeta ::  Type -> TCM Term
newValueMeta t =
    do	i  <- createMetaInfo
        vs <- allCtxVars
	x  <- newMeta i (HasType () t)
	return $ MetaV x vs

newArgsMeta :: Type -> TCM Args
newArgsMeta (El s tm) = do
    tm <- reduce tm
    case funView tm of
	FunV (Arg h a) _  -> do
	    v	 <- newValueMeta a
	    args <- newArgsMeta $ piApply' (El s tm) [Arg h v]
	    return $ Arg h v : args
	NoFunV _    -> return []

newQuestionMark ::  Type -> TCM Term
newQuestionMark t =
    do	m@(MetaV x _) <- newValueMeta t
	ii	      <- fresh
	addInteractionPoint ii x
	return m

-- | Construct a blocked constant if there are constraints.
blockTerm :: Type -> Term -> TCM Constraints -> TCM Term
blockTerm t v m = do
    cs <- solveConstraints =<< m
    if List.null cs
	then return v
	else do
	    i	  <- createMetaInfo
	    vs	  <- allCtxVars
	    tel   <- getContextTelescope' NotHidden
	    x	  <- newMeta i (HasType () t)
	    store <- getMetaStore
	    modify $ \st -> st { stMetaStore = ins x (BlockedConst $ abstract tel v) store }
	    c <- escapeContext (length tel) $ guardConstraint (return cs) (UnBlock x)
	    addConstraints c
	    return $ MetaV x vs
  where
    ins x i store = Map.adjust (inst i) x store
    inst i mv = mv { mvInstantiation = i }


-- | Generate new metavar of same kind ('Open'X) as that
--     pointed to by @MetaId@ arg.
--
newMetaSame :: MetaId -> (MetaId -> a) -> TCM a
newMetaSame x meta =
    do	mv <- lookupMeta x
	meta <$> newMeta (getMetaInfo mv) (mvJudgement mv)

-- | Extended occurs check.
class Occurs t where
    occurs :: TCM () -> MetaId -> t -> TCM ()

occursCheck :: Occurs a => MetaId -> a -> TCM ()
occursCheck m = occurs (typeError $ MetaOccursInItself m) m

instance Occurs Term where
    occurs abort m v = do
	v <- reduce v
	case v of
	    -- Don't fail on blocked terms
	    BlockedV b	-> occurs' patternViolation v
	    _		-> occurs' abort v
	where
	    occurs' abort v = case ignoreBlocking v of
		Var _ vs    -> occ vs
		Lam _ f	    -> occ f
		Lit l	    -> return ()
		Def c vs    -> occ vs
		Con c vs    -> occ vs
		Pi a b	    -> occ (a,b)
		Fun a b	    -> occ (a,b)
		Sort s	    -> occ s
		MetaV m' vs -> do
		    when (m == m') abort
		    -- Don't fail on flexible occurrence
		    occurs patternViolation m vs
		BlockedV _  -> __IMPOSSIBLE__
		where
		    occ x = occurs abort m x

instance Occurs Type where
    occurs abort m (El s v) = occurs abort m (s,v)

instance Occurs Sort where
    occurs abort m s =
	do  s' <- reduce s
	    case s' of
		MetaS m'  -> when (m == m') abort
		Lub s1 s2 -> occurs abort m (s1,s2)
		Suc s	  -> occurs abort m s
		Type _	  -> return ()
		Prop	  -> return ()

instance Occurs a => Occurs (Abs a) where
    occurs abort m (Abs _ x) = occurs abort m x

instance Occurs a => Occurs (Arg a) where
    occurs abort m (Arg _ x) = occurs abort m x

instance (Occurs a, Occurs b) => Occurs (a,b) where
    occurs abort m (x,y) = occurs abort m x >> occurs abort m y

instance Occurs a => Occurs [a] where
    occurs abort m xs = mapM_ (occurs abort m) xs

abortAssign :: TCM a
abortAssign =
    do	s <- get
	throwError $ AbortAssign s

handleAbort :: TCM a -> TCM a -> TCM a
handleAbort h m =
    m `catchError` \e ->
	case e of
	    AbortAssign s -> do put s; h
	    _		  -> throwError e

-- | Assign to an open metavar.
--   First check that metavar args are in pattern fragment.
--     Then do extended occurs check on given thing.
--
assignV :: Type -> MetaId -> Args -> Term -> TCM Constraints
assignV t x args v =
    handleAbort handler $ do
	verbose 10 $ do
	    d1 <- prettyTCM (MetaV x args)
	    d2 <- prettyTCM v
	    debug $ show d1 ++ " := " ++ show d2

	-- First order meta variables can't be applied
	-- TODO: this might interact badly with η-expansion
	firstOrder <- isFirstOrder x
	when (not (null args) && firstOrder) patternViolation

	-- We don't instantiate blocked terms
	whenM (isBlockedTerm x) patternViolation	-- TODO: not so nice

	-- Check that the arguments are distinct variables
	ids <- checkArgs x args

	-- When checking flexible variables v must be fully instantiated to not
	-- get false positives.
	v <- instantiateFull v

	verbose 15 $ do
	    d <- prettyTCM v
	    debug $ "fully instantiated: " ++ show d

	-- Check that the x doesn't occur in the right hand side
	occursCheck x v

	reportLn 15 "passed occursCheck"

	-- Check that all free variables of v are arguments to x
	-- Not done for first order metas
	unless firstOrder $ do
	    let fv	  = freeVars v
		idset = Set.fromList ids
		badrv = Set.toList $ Set.difference (rigidVars fv) idset
		badfv = Set.toList $ Set.difference (flexibleVars fv) idset
		-- If a rigid variable is not in ids there is no hope
	    unless (null badrv) $ typeError $ MetaCannotDependOn x ids (head badrv)
		-- If a flexible variable is not in ids we can wait and hope that it goes away
	    unless (null badfv) $ patternViolation

	    reportLn 15 "passed free variable check"

	-- Rename the variables in v to make it suitable for abstraction over ids.
	-- Also not done for first order metas (is this correct?)
	v' <- if firstOrder then return v else do
	    -- Basically, if
	    --   Γ	 = a b c d e
	    --   ids = d b e
	    -- then
	    --   v' = (λ a b c d e. v) _ 1 _ 2 0
	    tel <- getContextTelescope' NotHidden
	    let iargs = reverse $ zipWith (rename $ reverse ids) [0..] $ reverse tel
		v'	  = raise (length ids) (abstract tel v) `apply` iargs
	    return v'

	let mkTel i = Arg NotHidden <$> ((,) <$> (show <$> nameOfBV i) <*> typeOfBV i)
	tel' <- mapM mkTel ids

	verbose 15 $ do
	    d <- prettyTCM (abstract tel' v')
	    debug $ "final instantiation: " ++ show d

	-- Perform the assignment (and wake constraints)
	x =: abstract tel' v'
	return []
    where
	rename ids i arg = case findIndex (==i) ids of
	    Just j  -> fmap (const $ Var j []) arg
	    Nothing -> fmap (const __IMPOSSIBLE__) arg	-- we will end up here, but never look at the result

	handler = do
	    reportLn 10 $ "Oops. Undo " ++ show x ++ " := ..."
	    equalTerm t (MetaV x args) v

assignS :: MetaId -> Sort -> TCM Constraints
assignS x s =
    handleAbort (equalSort (MetaS x) s) $ do
	occursCheck x s
	x =: s
	return []

-- | Check that arguments to a metavar are in pattern fragment.
--   Assumes all arguments already in whnf.
--   Parameters are represented as @Var@s so @checkArgs@ really
--     checks that all args are unique @Var@s and returns the
--     list of corresponding indices for each arg-- done
--     to not define equality on @Term@.
--
--   @reverse@ is necessary because we are directly abstracting over this list @ids@.
--
checkArgs :: MetaId -> Args -> TCM [Nat]
checkArgs x args =
    case validParameters args of
	Just ids    -> return $ reverse ids
	Nothing	    -> patternViolation

-- | Check that the parameters to a meta variable are distinct variables.
validParameters :: Monad m => Args -> m [Nat]
validParameters args
    | all isVar args && distinct vars	= return $ reverse vars
    | otherwise				= fail "invalid parameters"
    where
	vars = [ i | Arg _ (Var i []) <- args ]

isVar :: Arg Term -> Bool
isVar (Arg _ (Var _ [])) = True
isVar _			 = False


updateMeta :: (Data a, Occurs a, Abstract a) => MetaId -> a -> TCM ()
updateMeta mI t = 
    do	mv <- lookupMeta mI
	withMetaInfo (getMetaInfo mv) $
	    do	args <- allCtxVars
		cs <- upd mI args (mvJudgement mv) t
		unless (List.null cs) $ fail $ "failed to update meta " ++ show mI
    where
	upd mI args j t = (__IMPOSSIBLE__ `mkQ` updV j `extQ` updS) t
	    where
		updV (HasType _ t) v = assignV t mI args v
		updV _ _	     = __IMPOSSIBLE__

		updS s = assignS mI s

