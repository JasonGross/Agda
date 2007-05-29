{-# OPTIONS -cpp #-}
module TypeChecking.Substitute where

import Control.Monad.Identity
import Control.Monad.Reader
import Data.Generics
import Data.Map (Map)

import Syntax.Common
import Syntax.Internal

import TypeChecking.Monad.Base
import TypeChecking.Free

import Utils.Monad
import Utils.Size

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
  apply = piApply

instance Apply Sort where
  apply s [] = s
  apply s _  = __IMPOSSIBLE__

instance Apply Telescope where
  apply tel		  []	   = tel
  apply EmptyTel	  _	   = __IMPOSSIBLE__
  apply (ExtendTel _ tel) (t : ts) = absApp tel (unArg t) `apply` ts

instance Apply Definition where
    apply (Defn x t df d) args = Defn x (piApply t args) df (apply d args)

instance Apply Defn where
    apply Axiom _			  = Axiom
    apply (Function cs a) args		  = Function (apply cs args) a
    apply (Datatype np ni cl cs s a) args = Datatype (np - size args) ni (apply cl args) cs s a
    apply (Record np cl fs tel s a) args  = Record (np - size args) (apply cl args) fs (apply tel args) s a
    apply (Constructor np c d a) args	  = Constructor (np - size args) c d a
    apply (Primitive a x cs) args	  = Primitive a x cs

instance Apply PrimFun where
    apply (PrimFun x ar def) args   = PrimFun x (ar - size args) $ \vs -> def (args ++ vs)

instance Apply Clause where
    apply (Clause ps b) args = Clause (drop (size args) ps) $ apply b args

instance Apply ClauseBody where
    apply  b		   []		  = b
    apply (Bind (Abs _ b)) (Arg _ v:args) = subst v b `apply` args
    apply (NoBind b)	   (_:args)	  = b `apply` args
    apply (Body _)	   (_:_)	  = __IMPOSSIBLE__
    apply  NoBody	    _		  = NoBody

instance Apply DisplayTerm where
  apply (DTerm v)	   args = DTerm $ apply v args
  apply (DWithApp v args') args = DWithApp v $ args' ++ args

instance Apply t => Apply [t] where
    apply ts args = map (`apply` args) ts

instance Apply t => Apply (Blocked t) where
    apply b args = fmap (`apply` args) b

instance Apply t => Apply (Maybe t) where
  apply x args = fmap (`apply` args) x

instance (Apply a, Apply b) => Apply (a,b) where
    apply (x,y) args = (apply x args, apply y args)

instance (Apply a, Apply b, Apply c) => Apply (a,b,c) where
    apply (x,y,z) args = (apply x args, apply y args, apply z args)

-- | The type must contain the right number of pis without have to perform any
-- reduction.
piApply :: Type -> Args -> Type
piApply t []				= t
piApply (El _ (Pi  _ b)) (Arg _ v:args) = absApp b v `piApply` args
piApply (El _ (Fun _ b)) (_:args)	= b `piApply` args
piApply _ _				= __IMPOSSIBLE__

-- | @(abstract args v) args --> v[args]@.
class Abstract t where
    abstract :: Telescope -> t -> t

instance Abstract Term where
    abstract = teleLam

instance Abstract Type where
    abstract = telePi

instance Abstract Sort where
    abstract EmptyTel s = s
    abstract _	      s = __IMPOSSIBLE__

instance Abstract Telescope where
  abstract  EmptyTel	        tel = tel
  abstract (ExtendTel arg tel') tel = ExtendTel arg $ fmap (`abstract` tel) tel'

instance Abstract Definition where
    abstract tel (Defn x t df d) = Defn x (telePi tel t) df (abstract tel d)

instance Abstract Defn where
    abstract tel Axiom			    = Axiom
    abstract tel (Function cs a)	    = Function (abstract tel cs) a
    abstract tel (Datatype np ni cl cs s a) = Datatype (size tel + np) ni (abstract tel cl) cs s a
    abstract tel (Record np cl fs ftel s a) = Record (size tel + np) (abstract tel cl) fs (abstract tel ftel) s a
    abstract tel (Constructor np c d a)	    = Constructor (size tel + np) c d a
    abstract tel (Primitive a x cs)	    = Primitive a x (abstract tel cs)

instance Abstract PrimFun where
    abstract tel (PrimFun x ar def) = PrimFun x (ar + n) $ \ts -> def $ drop n ts
	where n = size tel

instance Abstract Clause where
  abstract tel (Clause ps b) = Clause (telVars tel ++ ps) $ abstract tel b
    where
      telVars EmptyTel			  = []
      telVars (ExtendTel arg (Abs x tel)) = fmap (const $ VarP x) arg : telVars tel

instance Abstract ClauseBody where
    abstract EmptyTel		 b = b
    abstract (ExtendTel _ tel)	 b = Bind $ fmap (`abstract` b) tel

instance Abstract t => Abstract [t] where
    abstract tel = map (abstract tel)

instance Abstract t => Abstract (Maybe t) where
  abstract tel x = fmap (abstract tel) x

abstractArgs :: Abstract a => Args -> a -> a
abstractArgs args x = abstract tel x
    where
	tel   = foldr (\(Arg h x) -> ExtendTel (Arg h $ sort Prop) . Abs x) EmptyTel
	      $ zipWith (fmap . const) names args
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

instance Subst DisplayTerm where
  substs us (DTerm v)	     = DTerm $ substs us v
  substs us (DWithApp vs ws) = uncurry DWithApp $ substs us (vs, ws)

instance Subst Telescope where
  substs us  EmptyTel	      = EmptyTel
  substs us (ExtendTel t tel) = uncurry ExtendTel $ substs us (t, tel)

instance (Data a, Subst a) => Subst (Abs a) where
    substs us (Abs x t) = Abs x $ substs (Var 0 [] : raise 1 us) t

instance Subst a => Subst (Arg a) where
    substs us = fmap (substs us)

instance Subst a => Subst (Maybe a) where
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

instance Raise Telescope where
    raiseFrom m k EmptyTel	    = EmptyTel
    raiseFrom m k (ExtendTel a tel) = uncurry ExtendTel $ raiseFrom m k (a, tel)

instance Raise t => Raise (Abs t) where
    raiseFrom m k = fmap (raiseFrom (m + 1) k)

instance Raise t => Raise (Arg t) where
    raiseFrom m k = fmap (raiseFrom m k)

instance Raise t => Raise (Blocked t) where
    raiseFrom m k = fmap (raiseFrom m k)

instance Raise t => Raise [t] where
    raiseFrom m k = fmap (raiseFrom m k)

instance Raise t => Raise (Maybe t) where
    raiseFrom m k = fmap (raiseFrom m k)

instance Raise v => Raise (Map k v) where
    raiseFrom m k = fmap (raiseFrom m k)

instance (Raise a, Raise b) => Raise (a,b) where
    raiseFrom m k (x,y) = (raiseFrom m k x, raiseFrom m k y)

raise :: Raise t => Int -> t -> t
raise = raiseFrom 0

data TelView = TelV Telescope Type

telView :: Type -> TelView
telView t = case unEl t of
  Pi a (Abs x b)  -> absV a x $ telView b
  Fun a b	  -> absV a "_" $ telView (raise 1 b)
  _		  -> TelV EmptyTel t
  where
    absV a x (TelV tel t) = TelV (ExtendTel a (Abs x tel)) t

telePi :: Telescope -> Type -> Type
telePi  EmptyTel	 t = t
telePi (ExtendTel u tel) t = el $ fn u b
  where
    el = El (sLub s1 s2)  
    b = fmap (flip telePi t) tel
    s1 = getSort $ unArg u
    s2 = getSort $ absBody b

    fn a b
      | 0 `freeIn` absBody b = Pi a b
      | otherwise	     = Fun a $ absApp b __IMPOSSIBLE__

