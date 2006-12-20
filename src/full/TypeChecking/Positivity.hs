{-# OPTIONS_GHC -cpp -fglasgow-exts -fallow-undecidable-instances -fallow-overlapping-instances #-}

-- | Check that a datatype is strictly positive.
module TypeChecking.Positivity where

import Prelude hiding (foldr, mapM_, elem, concat)

import Control.Applicative
import Control.Monad hiding (mapM_)
import Control.Monad.Trans (liftIO)
import Control.Monad.State hiding (mapM_)
import Data.Foldable
import Data.Set (Set)
import Data.Monoid
import qualified Data.Set as Set
import qualified Data.Map as Map

import Syntax.Common
import Syntax.Internal
import TypeChecking.Monad
import TypeChecking.Substitute
import TypeChecking.Errors

import Utils.Monad

#include "../undefined.h"

-- | Check that a set of mutually recursive datatypes are strictly positive.
checkStrictlyPositive :: [QName] -> TCM ()
checkStrictlyPositive ds = flip evalStateT noAssumptions $ do
    cs <- concat <$> mapM constructors ds
    mapM_ (\c -> checkPos ds c =<< lift (typeOfConst c)) cs
    where
	constructors d = do
	    def <- lift $ theDef <$> getConstInfo d
	    case def of
		Datatype _ cs _ _ -> return cs
		_		  -> __IMPOSSIBLE__

-- | Assumptions about arguments to datatypes
type Assumptions = Set (QName, Int)

noAssumptions :: Assumptions
noAssumptions = Set.empty

type PosM = StateT Assumptions TCM

isAssumption :: QName -> Int -> PosM Bool
isAssumption q i = do
    a <- get
    return $ Set.member (q,i) a

assume :: QName -> Int -> PosM ()
assume q i = modify $ Set.insert (q,i)

-- | @checkPos ds c t@: Check that @ds@ only occurs stricly positively in the
--   type @t@ of the constructor @c@.
checkPos :: [QName] -> QName -> Type -> PosM ()
checkPos ds c t = mapM_ check ds
    where
	check d = case Map.lookup d defs of
	    Nothing  -> return ()    -- non-recursive
	    Just ocs
		| NonPositive `elem` ocs -> fail $ show d ++ " occurs not strictly positively in the type of the constructor " ++ show c
		| otherwise		 -> mapM_ (uncurry checkPosArg) args
		where
		    args = [ (q, i) | Argument q i <- Set.toList ocs ]

	defs = unMap $ getDefs $ arguments t

	arguments t = case unEl t of
	    Pi a b  -> a : arguments (absBody b)
	    Fun a b -> a : arguments b
	    _	    -> []

-- | Check that a particular argument occurs strictly positively in the
--   definition of a datatype.
checkPosArg :: QName -> Int -> PosM ()
checkPosArg d i = unlessM (isAssumption d i) $ do
    assume d i
    def <- lift $ theDef <$> getConstInfo d
    case def of
	Datatype _ cs _ _ -> do
	    xs <- lift $ map (qualify noModuleName) <$>
		  replicateM (i + 1) (freshName_ "dummy")
	    let x = xs !! i
		args = map (Arg NotHidden . flip Def []) xs
	    let check c = do
		    t <- lift $ typeOfConst c
		    checkPos [x] c (t `piApply'` args)
	    mapM_ check cs
	_		  -> fail $ "cannot guarantee positivity of argument " ++ show i ++ " to non-datatype " ++ show d

data Occurence = Positive | NonPositive | Argument QName Nat
    deriving (Show, Eq, Ord)

newtype Map k v = Map { unMap :: Map.Map k v }
type Defs = Map QName (Set Occurence)

instance (Ord k, Monoid v) => Monoid (Map k v) where
    mempty = Map Map.empty
    mappend (Map ds1) (Map ds2) = Map (Map.unionWith mappend ds1 ds2)

instance Ord k => Functor (Map k) where
    fmap f (Map m) = Map $ fmap f m

makeNegative :: Defs -> Defs
makeNegative = fmap (const $ Set.singleton NonPositive)

makeArgument :: QName -> Int -> Defs -> Defs
makeArgument q i = fmap (Set.insert (Argument q i) . Set.delete Positive)

singlePositive :: QName -> Defs
singlePositive q = Map $ Map.singleton q (Set.singleton Positive)

class HasDefinitions a where
    getDefs :: a -> Defs

instance HasDefinitions Term where
    getDefs t = case ignoreBlocking t of
	Var _ args   -> getDefs args
	Lam _ t	     -> getDefs t
	Lit _	     -> mempty
	Def q args   -> mappend (getDefs q)
				(mconcat $ zipWith (makeArgument q) [0..] $ map getDefs args)
	Con q args   -> getDefs (q, args)
	Pi a b	     -> mappend (makeNegative $ getDefs a) (getDefs b)
	Fun a b	     -> mappend (makeNegative $ getDefs a) (getDefs b)
	Sort _	     -> mempty
	MetaV _ args -> getDefs args
	BlockedV _   -> __IMPOSSIBLE__

instance HasDefinitions Type where
    getDefs = getDefs . unEl

instance HasDefinitions QName where
    getDefs = singlePositive

instance (HasDefinitions a, HasDefinitions b) => HasDefinitions (a,b) where
    getDefs (x,y) = mappend (getDefs x) (getDefs y)

instance (Functor f, Foldable f, HasDefinitions a) =>
	 HasDefinitions (f a) where
    getDefs = foldr mappend mempty . fmap getDefs

