{-# OPTIONS -fglasgow-exts -fallow-undecidable-instances #-}
module TypeChecking.Monad where

import Data.Map as Map

import Control.Monad.Error
import Control.Monad.State
import Control.Monad.Reader
import Data.Generics

import Syntax.Common
import Syntax.Internal
import Syntax.Internal.Debug ()

import Utils.Fresh

---------------------------------------------------------------------------
-- * Type checking state
---------------------------------------------------------------------------

data TCState =
    TCSt { stFreshThings    :: FreshThings
	 , stMetaStore	    :: MetaStore
	 , stConstraints    :: Constraints
	 , stSignature	    :: Signature
	 }

data FreshThings =
	Fresh { fMeta	    :: MetaId
	      , fName	    :: NameId
	      , fConstraint :: ConstraintId
	      }
    deriving (Show)

initState :: TCState
initState =
    TCSt { stFreshThings = Fresh 0 0 0
	 , stMetaStore	 = Map.empty
	 , stConstraints = Map.empty
	 , stSignature   = Map.empty
	 }

instance HasFresh MetaId FreshThings where
    nextFresh s = (i, s { fMeta = i + 1 })
	where
	    i = fMeta s

instance HasFresh NameId FreshThings where
    nextFresh s = (i, s { fName = i + 1 })
	where
	    i = fName s

instance HasFresh ConstraintId FreshThings where
    nextFresh s = (i, s { fConstraint = i + 1 })
	where
	    i = fConstraint s

instance HasFresh i FreshThings => HasFresh i TCState where
    nextFresh s = (i, s { stFreshThings = f })
	where
	    (i,f) = nextFresh $ stFreshThings s

---------------------------------------------------------------------------
-- ** Constraints
---------------------------------------------------------------------------

newtype ConstraintId = CId Nat
    deriving (Eq, Ord, Show, Num, Typeable, Data)

data Constraint = ValueEq Type Term Term
		| TypeEq Type Type
  deriving (Show, Typeable, Data)

type Constraints = Map ConstraintId (Signature,Context,Constraint)

---------------------------------------------------------------------------
-- ** Meta variables
---------------------------------------------------------------------------

data MetaVariable = InstV Term
                  | InstT Type
                  | InstS Sort
                  | UnderScoreV Type [ConstraintId]
                  | UnderScoreT Sort [ConstraintId]
                  | UnderScoreS      [ConstraintId]
                  | HoleV       Type [ConstraintId]
                  | HoleT       Sort [ConstraintId]
  deriving (Typeable, Data, Show)

type MetaStore = Map MetaId MetaVariable

---------------------------------------------------------------------------
-- ** Signature
---------------------------------------------------------------------------

type Signature	 = Map ModuleName ModuleDef
type Definitions = Map Name Definition

data ModuleDef = MDef { mdefName       :: ModuleName
		      , mdefTelescope  :: Telescope
		      , mdefNofParams  :: Nat
		      , mdefModuleName :: ModuleName
		      , mdefArgs       :: Args
		      }
	       | MExplicit
		      { mdefName       :: ModuleName
		      , mdefTelescope  :: Telescope
		      , mdefNofParams  :: Nat
		      , mdefDefs       :: Definitions
		      }
    deriving (Show, Typeable, Data)

data Definition = Defn { defType     :: Type
		       , defFreeVars :: Nat
		       , theDef	     :: Defn
		       }
    deriving (Show, Typeable, Data)

data Defn = Axiom
	  | Function [Clause] IsAbstract
	  | Datatype Nat	-- nof parameters
		     [QName]	-- constructor names
		     IsAbstract
	  | Constructor Nat	-- nof parameters
			QName	-- name of datatype
			IsAbstract
    deriving (Show, Typeable, Data)

defClauses :: Definition -> [Clause]
defClauses (Defn _ _ (Function cs _)) = cs
defClauses _			      = []


---------------------------------------------------------------------------
-- * Type checking environment
---------------------------------------------------------------------------

data TCEnv =
    TCEnv { envContext	     :: Context
	  , envCurrentModule :: ModuleName
	  , envAbstractMode  :: Bool
		-- ^ When checking the typesignature of a public definition
		--   or the body of a non-abstract definition this is true.
		--   To prevent information about abstract things leaking
		--   outside the module.
	  }
    deriving (Show)

initEnv :: TCEnv
initEnv = TCEnv { envContext	   = []
		, envCurrentModule = noModuleName
		, envAbstractMode  = False
		}

---------------------------------------------------------------------------
-- ** Context
---------------------------------------------------------------------------

type Context = [(Name, Type)]

---------------------------------------------------------------------------
-- * Type checking errors
---------------------------------------------------------------------------

data TCErr = Fatal String 
	   | PatternErr [MetaId] -- ^ for pattern violations, carries involved metavars
  deriving Show

instance Error TCErr where
    noMsg = Fatal ""
    strMsg s = Fatal s

patternViolation mIds = throwError $ PatternErr mIds

---------------------------------------------------------------------------
-- * Type checking monad
---------------------------------------------------------------------------

type TCErrMon = Either TCErr
type TCM = StateT TCState (ReaderT TCEnv TCErrMon)

runTCM :: TCM a -> Either TCErr a
runTCM m = flip runReaderT initEnv
	 $ flip evalStateT initState
	 $ m

