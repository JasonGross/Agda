{-# OPTIONS -cpp #-}
module TypeChecking.Substitute where

import Control.Monad.Identity
import Control.Monad.Reader
import Data.Generics
import Data.Map (Map)

import Syntax.Common
import Syntax.Internal

import TypeChecking.Monad.Base

import Utils.Monad

#include "../undefined.h"

-- | Apply something to a bunch of arguments.
--   Preserves blocking tags (application can never resolve blocking).
class Apply t where
    apply :: t -> Args -> t

instance Apply Term where
    apply m [] = m
    apply m args@(Arg _ v:args0) =
	case m of
	    Var i args'   -> Var i (args'++args)
	    Def c args'   -> Def c (args'++args)
	    Con c args'   -> Con c (args'++args)
	    Lam _ u	  -> absApp u v `apply` args0
	    MetaV x args' -> MetaV x (args'++args) 
	    BlockedV b	  -> BlockedV $ b `apply` args
	    Lit l	  -> __IMPOSSIBLE__
	    Pi _ _	  -> __IMPOSSIBLE__
	    Fun _ _	  -> __IMPOSSIBLE__
	    Sort _	  -> __IMPOSSIBLE__

instance Apply Type where
    apply a []		= a
    apply (El s t) args	= El s $ t `apply` args

instance Apply Sort where
    apply s [] = s
    apply s _  = __IMPOSSIBLE__

instance Apply Definition where
    apply (Defn t n d) args = Defn (piApply' t args) (n - length args) (apply d args)

instance Apply Defn where
    apply Axiom _		       = Axiom
    apply (Function cs a) args	       = Function (apply cs args) a
    apply (Datatype np ni cs s a) args = Datatype (np - length args) ni cs s a
    apply (Constructor np cs a) args   = Constructor (np - length args) cs a
    apply (Primitive a x cs) args      = Primitive a x cs

instance Apply PrimFun where
    apply (PrimFun x ar def) args   = PrimFun x (ar - length args) $ \vs -> def (args ++ vs)

instance Apply Clause where
    apply (Clause ps b) args = Clause (drop (length args) ps) $ apply b args

instance Apply ClauseBody where
    apply  b		   []		  = b
    apply (Bind (Abs _ b)) (Arg _ v:args) = subst v b `apply` args
    apply (NoBind b)	   (_:args)	  = b `apply` args
    apply (Body _)	   (_:_)	  = __IMPOSSIBLE__
    apply  NoBody	    _		  = NoBody

instance Apply t => Apply [t] where
    apply ts args = map (`apply` args) ts

instance Apply t => Apply (Blocked t) where
    apply b args = fmap (`apply` args) b

instance (Apply a, Apply b) => Apply (a,b) where
    apply (x,y) args = (apply x args, apply y args)

instance (Apply a, Apply b, Apply c) => Apply (a,b,c) where
    apply (x,y,z) args = (apply x args, apply y args, apply z args)

-- | The type must contain the right number of pis without have to perform any
-- reduction.
piApply' :: Type -> Args -> Type
piApply' t []				 = t
piApply' (El _ (Pi  _ b)) (Arg _ v:args) = absApp b v `piApply'` args
piApply' (El _ (Fun _ b)) (_:args)	 = b
piApply' _ _				 =
    __IMPOSSIBLE__

-- | @(abstract args v) args --> v[args]@.
class Abstract t where
    abstract :: Telescope -> t -> t

instance Abstract Term where
    abstract tel v = foldl (\v (Arg h (s,_)) -> Lam h (Abs s v)) v $ reverse tel

instance Abstract Type where
    abstract tel (El s t) = El s $ abstract tel t

instance Abstract Sort where
    abstract [] s = s
    abstract _ s = __IMPOSSIBLE__

instance Abstract Definition where
    abstract tel (Defn t n d) = Defn (telePi tel t) (length tel + n) (abstract tel d)

instance Abstract Defn where
    abstract tel Axiom			 = Axiom
    abstract tel (Function cs a)	 = Function (abstract tel cs) a
    abstract tel (Datatype np ni cs s a) = Datatype (length tel + np) ni cs s a
    abstract tel (Constructor np cs a)	 = Constructor (length tel + np) cs a
    abstract tel (Primitive a x cs)	 = Primitive a x (abstract tel cs)

instance Abstract PrimFun where
    abstract tel (PrimFun x ar def) = PrimFun x (ar + n) $ \ts -> def $ drop n ts
	where n = length tel

instance Abstract Clause where
    abstract tel (Clause ps b) = Clause (ps0 ++ ps) $ abstract tel b
	where
	    ps0 = map (fmap $ \(s,_) -> VarP s) tel

instance Abstract ClauseBody where
    abstract []			 b = b
    abstract (Arg _ (s,_) : tel) b = Bind $ Abs s $ abstract tel b

instance Abstract t => Abstract [t] where
    abstract tel = map (abstract tel)

abstractArgs :: Abstract a => Args -> a -> a
abstractArgs args x = abstract tel x
    where
	tel   = zipWith (\arg x -> fmap (const (x, sort Prop)) arg) args names
	names = cycle $ map (:[]) ['a'..'z']

-- | Substitute a term for the nth free variable.
--
class Subst t where
    substs :: [Term] -> t -> t

subst :: Subst t => Term -> t -> t
subst u t = substs (u : map var [0..]) t
    where
	var n = Var n []

instance Subst Term where
    substs us t =
	case t of
	    Var i vs   -> (us !!! i) `apply` substs us vs
	    Lam h m    -> Lam h $ substs us m
	    Def c vs   -> Def c $ substs us vs
	    Con c vs   -> Con c $ substs us vs
	    MetaV x vs -> MetaV x $ substs us vs
	    Lit l      -> Lit l
	    Pi a b     -> uncurry Pi $ substs us (a,b)
	    Fun a b    -> uncurry Fun $ substs us (a,b)
	    Sort s     -> Sort s
	    BlockedV b -> BlockedV $ substs us b
        where
            []     !!! n = error "unbound variable"
            (x:xs) !!! 0 = x
            (_:xs) !!! n = xs !!! (n - 1)

instance Subst Type where
    substs us (El s t) = El s $ substs us t

instance Subst t => Subst (Blocked t) where
    substs us b = fmap (substs us) b

instance (Data a, Subst a) => Subst (Abs a) where
    substs us (Abs x t) = Abs x $ substs (Var 0 [] : raise 1 us) t

instance Subst a => Subst (Arg a) where
    substs us = fmap (substs us)

instance Subst a => Subst [a] where
    substs us = map (substs us)

instance (Subst a, Subst b) => Subst (a,b) where
    substs us (x,y) = (substs us x, substs us y)

instance Subst ClauseBody where
    substs us (Body t)   = Body $ substs us t
    substs us (Bind b)   = Bind $ substs us b
    substs us (NoBind b) = NoBind $ substs us b
    substs _   NoBody	 = NoBody

-- | Instantiate an abstraction
absApp :: Subst t => Abs t -> Term -> t
absApp (Abs _ v) u = subst u v

-- | Add @k@ to index of each open variable in @x@.
class Raise t where
    raiseFrom :: Int -> Int -> t -> t

instance Raise Term where
    raiseFrom m k v =
	case v of
	    Var i vs
		| i < m	    -> Var i $ rf vs
		| otherwise -> Var (i + k) $ rf vs
	    Lam h m	    -> Lam h $ rf m
	    Def c vs	    -> Def c $ rf vs
	    Con c vs	    -> Con c $ rf vs
	    MetaV x vs	    -> MetaV x $ rf vs
	    Lit l	    -> Lit l
	    Pi a b	    -> uncurry Pi $ rf (a,b)
	    Fun a b	    -> uncurry Fun $ rf (a,b)
	    Sort s	    -> Sort s
	    BlockedV b	    -> BlockedV $ rf b
	where
	    rf x = raiseFrom m k x

instance Raise Type where
    raiseFrom m k (El s t) = El s $ raiseFrom m k t

instance Raise t => Raise (Abs t) where
    raiseFrom m k = fmap (raiseFrom (m + 1) k)

instance Raise t => Raise (Arg t) where
    raiseFrom m k = fmap (raiseFrom m k)

instance Raise t => Raise (Blocked t) where
    raiseFrom m k = fmap (raiseFrom m k)

instance Raise t => Raise [t] where
    raiseFrom m k = fmap (raiseFrom m k)

instance Raise v => Raise (Map k v) where
    raiseFrom m k = fmap (raiseFrom m k)

instance (Raise a, Raise b) => Raise (a,b) where
    raiseFrom m k (x,y) = (raiseFrom m k x, raiseFrom m k y)

raise :: Raise t => Int -> t -> t
raise = raiseFrom 0

