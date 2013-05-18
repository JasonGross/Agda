-- | Extract used definitions from terms.
module Agda.Syntax.Internal.Defs where

import Control.Monad.Reader
import Control.Monad.Writer

import qualified Data.Foldable as Fold

import Agda.Syntax.Common
import Agda.Syntax.Internal hiding (ArgInfo, Arg, Dom)

-- | @getDefs' lookup keep a@ extracts all used definitions
--   (functions, data/record types) from @a@ that satisfy @keep@.
--   Instantiations of meta variables are obtained via @lookup@.
--
--   @keep@ is expected to be selective so the result will be a short list.
--   (Otherwise switch to a result @Set@).
getDefs' :: GetDefs a => (MetaId -> Maybe Term) -> (QName -> Bool) -> a -> [QName]
getDefs' lookup keep = execWriter . (`runReaderT` GetDefsEnv lookup keep) . getDefs

-- | Inputs to and outputs of @getDefs'@ are organized as a monad.
type GetDefsM = ReaderT GetDefsEnv (Writer [QName])

data GetDefsEnv = GetDefsEnv
  { lookupMeta :: MetaId -> Maybe Term
  , keepDef    :: QName -> Bool
  }

class GetDefs a where
  getDefs :: a -> GetDefsM ()

instance GetDefs Clause where
  getDefs = getDefs . clauseBody

instance GetDefs ClauseBody where
  getDefs b = case b of
    Body v -> getDefs v
    Bind b -> getDefs $ unAbs b
    NoBody -> return ()

instance GetDefs Term where
  getDefs v = case v of
    Def d vs   -> do
      keep <- asks keepDef
      when (keep d) $ tell [d]
      getDefs vs
    Con c vs   -> getDefs vs
    Lit l      -> return ()
    Var i vs   -> getDefs vs
    Lam _ v    -> getDefs v
    Pi a b     -> getDefs a >> getDefs b
    Sort s     -> getDefs s
    Level l    -> getDefs l
    MetaV x vs -> getDefs x >> getDefs vs
    DontCare v -> getDefs v
    Shared p   -> getDefs $ derefPtr p  -- TODO: exploit sharing!

instance GetDefs MetaId where
  getDefs x = do
    lookup <- asks lookupMeta
    getDefs $ lookup x

instance GetDefs Type where
  getDefs (El s t) = getDefs s >> getDefs t

instance GetDefs Sort where
  getDefs s = case s of
    Type l    -> getDefs l
    Prop      -> return ()
    Inf       -> return ()
    DLub s s' -> getDefs s >> getDefs s'

instance GetDefs Level where
  getDefs (Max ls) = getDefs ls

instance GetDefs PlusLevel where
  getDefs ClosedLevel{} = return ()
  getDefs (Plus _ l)    = getDefs l

instance GetDefs LevelAtom where
  getDefs a = case a of
    MetaLevel x vs   -> getDefs x >> getDefs vs
    BlockedLevel _ v -> getDefs v
    NeutralLevel v   -> getDefs v
    UnreducedLevel v -> getDefs v

-- collection instances

instance GetDefs a => GetDefs (Maybe a) where
  getDefs = Fold.mapM_ getDefs

instance GetDefs a => GetDefs [a] where
  getDefs = Fold.mapM_ getDefs

instance GetDefs c => GetDefs (ArgInfo c) where
  getDefs = Fold.mapM_ getDefs

instance (GetDefs c, GetDefs a) => GetDefs (Arg c a) where
  getDefs (Arg c a) = getDefs c >> getDefs a

instance (GetDefs c, GetDefs a) => GetDefs (Dom c a) where
  getDefs (Dom c a) = getDefs c >> getDefs a

instance GetDefs a => GetDefs (Abs a) where
  getDefs = getDefs . unAbs

instance (GetDefs a, GetDefs b) => GetDefs (a,b) where
  getDefs (a,b) = getDefs a >> getDefs b
