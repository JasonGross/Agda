{-# LANGUAGE TypeOperators, CPP, DeriveDataTypeable, DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
module Agda.TypeChecking.CompiledClause where

import qualified Data.Map as Map
import Data.Map (Map)
import Data.Monoid
import Data.Typeable (Typeable)
import Data.Foldable (Foldable)
import Data.Traversable (Traversable)

import Agda.Syntax.Internal
import Agda.Syntax.Literal

import Agda.Utils.Pretty

#include "../undefined.h"
import Agda.Utils.Impossible

type key :-> value = Map key value

data WithArity c = WithArity { arity :: Int, content :: c }
  deriving (Typeable, Functor, Foldable, Traversable)

-- | Branches in a case tree.
data Case c = Branches
  { conBranches    :: QName :-> WithArity c -- ^ Map from constructor (or projection) names to their arity and the case subtree.  (Projections have arity 0.)
  , litBranches    :: Literal :-> c         -- ^ Map from literal to case subtree.
  , catchAllBranch :: Maybe c               -- ^ (Possibly additional) catch-all clause.
  }
  deriving (Typeable, Functor, Foldable, Traversable)

-- | Case tree with bodies.
data CompiledClauses
  = Case Int (Case CompiledClauses)
    -- ^ @Case n bs@ stands for a match on the @n@-th argument
    -- (counting from zero) with @bs@ as the case branches.
    -- If the @n@-th argument is a projection, we have only 'conBranches'.
    -- with arity 0.
{-
  | CoCase Int (QName :-> CompiledClauses)
    -- ^ @CoCase n bs@ matches on projections.
    --   Catch-all is not meaningful here.
-}
  | Done [Arg String] Term
    -- ^ @Done xs b@ stands for the body @b@ where the @xs@ contains hiding
    --   and name suggestions for the free variables. This is needed to build
    --   lambdas on the right hand side for partial applications which can
    --   still reduce.
  | Fail
    -- ^ Absurd case.
  deriving (Typeable)

emptyBranches = Branches Map.empty Map.empty Nothing
litCase l x = Branches Map.empty (Map.singleton l x) Nothing
conCase c x = Branches (Map.singleton c x) Map.empty Nothing
catchAll x  = Branches Map.empty Map.empty (Just x)

instance Monoid c => Monoid (WithArity c) where
 mempty = WithArity __IMPOSSIBLE__ mempty
 mappend (WithArity n1 c1) (WithArity n2 c2)
  | n1 == n2  = WithArity n1 $ mappend c1 c2
  | otherwise = __IMPOSSIBLE__   -- arity must match!

instance Monoid m => Monoid (Case m) where
  mempty = Branches Map.empty Map.empty Nothing
  mappend (Branches cs  ls  m)
          (Branches cs' ls' m') =
    Branches (Map.unionWith mappend cs cs')
             (Map.unionWith mappend ls ls')
             (mappend m m')

instance Pretty a => Show (Case a) where
  show = show . pretty

instance Show CompiledClauses where
  show = show . pretty

instance Pretty a => Pretty (WithArity a) where
  pretty = pretty . content

instance Pretty a => Pretty (Case a) where
  prettyPrec p (Branches cs ls m) =
    mparens (p > 0) $ vcat $
      prettyMap cs ++ prettyMap ls ++ prC m
    where
      prC Nothing = []
      prC (Just x) = [text "_ ->" <+> pretty x]

prettyMap :: (Show k, Pretty v) => (k :-> v) -> [Doc]
prettyMap m = [ sep [ text (show x ++ " ->")
                    , nest 2 $ pretty v ]
              | (x, v) <- Map.toList m ]

instance Pretty CompiledClauses where
  pretty (Done hs t) = text ("done" ++ show hs) <+> text (show t)
  pretty Fail        = text "fail"
  pretty (Case n bs) =
    sep [ text ("case " ++ show n ++ " of")
        , nest 2 $ pretty bs
        ]
{-
  pretty (CoCase n bs) =
    sep [ text ("cocase " ++ show n ++ " of")
        , nest 2 $ vcat $ prettyMap bs
        ]
-}
