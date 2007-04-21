{-# OPTIONS -cpp #-}
module TypeChecking.Monad.Signature where

import Control.Monad.State
import Control.Monad.Reader
import Data.Map (Map)
import qualified Data.Map as Map
import Data.List

import Syntax.Abstract.Name
import Syntax.Common
import Syntax.Internal
import Syntax.Position

import TypeChecking.Monad.Base
import TypeChecking.Monad.Context
import TypeChecking.Monad.Options
import TypeChecking.Substitute

import Utils.Monad
import Utils.Map as Map
import Utils.Size
import Utils.Function

#include "../../undefined.h"

modifySignature :: MonadTCM tcm => (Signature -> Signature) -> tcm ()
modifySignature f = modify $ \s -> s { stSignature = f $ stSignature s }

getSignature :: MonadTCM tcm => tcm Signature
getSignature = liftTCM $ gets stSignature

getImportedSignature :: MonadTCM tcm => tcm Signature
getImportedSignature = liftTCM $ gets stImports

setSignature :: MonadTCM tcm => Signature -> tcm ()
setSignature sig = modifySignature $ const sig

setImportedSignature :: MonadTCM tcm => Signature -> tcm ()
setImportedSignature sig = liftTCM $ modify $ \s -> s { stImports = sig }

withSignature :: MonadTCM tcm => Signature -> tcm a -> tcm a
withSignature sig m =
    do	sig0 <- getSignature
	setSignature sig
	r <- m
	setSignature sig0
        return r

-- | Add a constant to the signature. Lifts the definition to top level.
addConstant :: MonadTCM tcm => QName -> Definition -> tcm ()
addConstant q d = liftTCM $ do
  tel <- getContextTelescope
  modifySignature $ \sig -> sig
    { sigDefinitions = Map.insert q (abstract tel d') $ sigDefinitions sig }
  where
    d' = d { defName = q }

unionSignatures :: [Signature] -> Signature
unionSignatures ss = foldr unionSignature emptySignature ss
  where
    unionSignature (Sig a b) (Sig c d) = Sig (Map.union a c) (Map.union b d)

-- | Add a section to the signature.
addSection :: MonadTCM tcm => ModuleName -> Nat -> tcm ()
addSection m fv = do
  tel <- getContextTelescope
  let sec = Section tel fv
  modifySignature $ \sig -> sig { sigSections = Map.insert m sec $ sigSections sig }

-- | Exit a section. Sets the free variables of the section to 0.
exitSection :: MonadTCM tcm => ModuleName -> tcm ()
exitSection m = do
  sig <- sigSections <$> getSignature
  case Map.lookup m sig of
    Nothing  -> __IMPOSSIBLE__
    Just sec -> modifySignature $ \s ->
      s { sigSections = Map.insert m (sec { secFreeVars = 0 }) sig }

-- | Lookup a section. If it doesn't exist that just means that the module
--   wasn't parameterised.
lookupSection :: MonadTCM tcm => ModuleName -> tcm Telescope
lookupSection m = do
  sig  <- sigSections <$> getSignature
  isig <- sigSections <$> getImportedSignature
  return $ maybe EmptyTel secTelescope $ Map.lookup m sig `mplus` Map.lookup m isig

applySection ::
  MonadTCM tcm => ModuleName -> ModuleName -> Args ->
  Map QName QName -> Map ModuleName ModuleName -> tcm ()
applySection new old ts rd rm = liftTCM $ do
  sig <- getSignature
  let ss = Map.toList $ Map.filterKeys partOfOldM $ sigSections sig
      ds = Map.toList $ Map.filterKeys partOfOldD $ sigDefinitions sig
  mapM_ (copyDef ts) ds
  mapM_ (copySec ts) ss
  where
    partOfOldM x = x `isSubModuleOf` old
    partOfOldD x = x `isInModule`    old

    copyName x = maybe x id $ Map.lookup x rd

    copyDef :: Args -> (QName, Definition) -> TCM ()
    copyDef ts (x, d) = case Map.lookup x rd of
	Nothing -> return ()  -- if it's not in the renaming it was private and
			      -- we won't need it
	Just y	-> addConstant y nd
      where
	t  = defType d `apply` ts
	-- the name is set by the addConstant function
	nd = Defn __IMPOSSIBLE__ t def
	def  = case theDef d of
		Constructor n c d a	-> Constructor (n - size ts) c (copyName d) a
		Datatype np ni _ cs s a -> Datatype (np - size ts) ni (Just cl) (map copyName cs) s a
		_			-> Function [cl] ConcreteDef
	cl = Clause [] $ Body $ Def x ts

    copySec :: Args -> (ModuleName, Section) -> TCM ()
    copySec ts (x, sec) = case Map.lookup x rm of
	Nothing -> return ()  -- if it's not in the renaming it was private and
			      -- we won't need it
	Just y  -> addCtxTel (apply tel ts) $ addSection y 0
      where
	tel = secTelescope sec

-- | Lookup the definition of a name. The result is a closed thing, all free
--   variables have been abstracted over.
getConstInfo :: MonadTCM tcm => QName -> tcm Definition
getConstInfo q = liftTCM $ do
  ab    <- treatAbstractly q
  defs  <- sigDefinitions <$> getSignature
  idefs <- sigDefinitions <$> getImportedSignature
  let allDefs = (Map.unionWith (++) `on` Map.map (:[])) defs idefs
  case Map.lookup q allDefs of
      Nothing	-> fail $ show (getRange q) ++ ": no such name " ++ show q
      Just [d]	-> mkAbs ab d
      Just ds	-> fail $ show (getRange q) ++ ": ambiguous name " ++ show q
  where
    mkAbs True d =
      case makeAbstract d of
	Just d	-> return d
	Nothing	-> fail $ "panic: Not in scope " ++ show q -- __IMPOSSIBLE__
    mkAbs False d = return d

-- | Look up the number of free variables of a section. This is equal to the
--   number of parameters if we're currently inside the section and 0 otherwise.
getSecFreeVars :: MonadTCM tcm => ModuleName -> tcm Nat
getSecFreeVars m = do
  sig <- sigSections <$> getSignature
  return $ maybe 0 secFreeVars $ Map.lookup m sig

-- | Compute the number of free variables of a defined name. This is the sum of
--   the free variables of the sections it's contained in.
getDefFreeVars :: MonadTCM tcm => QName -> tcm Nat
getDefFreeVars q = sum <$> mapM getSecFreeVars ms
  where
    ms = map mnameFromList . inits . mnameToList . qnameModule $ q

-- | Compute the context variables to apply a definition to.
freeVarsToApply :: MonadTCM tcm => QName -> tcm Args
freeVarsToApply x = take <$> getDefFreeVars x <*> getContextArgs

-- | Instantiate a closed definition with the correct part of the current
--   context.
instantiateDef :: MonadTCM tcm => Definition -> tcm Definition
instantiateDef d = do
  vs  <- freeVarsToApply $ defName d
  verbose 30 $ do
    ctx <- getContext
    liftIO $ putStrLn $ "instDef " ++ show (defName d) ++ " " ++
			unwords (map show . take (size vs) . reverse . map (fst . unArg) $ ctx)
  return $ d `apply` vs

-- | Give the abstract view of a definition.
makeAbstract :: Definition -> Maybe Definition
makeAbstract d = do def <- makeAbs $ theDef d
		    return d { theDef = def }
    where
	makeAbs (Datatype _ _ _ _ _ AbstractDef) = Just Axiom
	makeAbs (Function _ AbstractDef)	 = Just Axiom
	makeAbs (Constructor _ _ _ AbstractDef)	 = Nothing
	makeAbs d				 = Just d

-- | Enter abstract mode
inAbstractMode :: MonadTCM tcm => tcm a -> tcm a
inAbstractMode = local $ \e -> e { envAbstractMode = True }

-- | Not in abstract mode.
notInAbstractMode :: MonadTCM tcm => tcm a -> tcm a
notInAbstractMode = local $ \e -> e { envAbstractMode = False }

-- | Check whether a name might have to be treated abstractly (either if we're
--   'inAbstractMode' or it's not a local name). Returns true for things not
--   declared abstract as well, but for those 'makeAbstract' will have no effect.
treatAbstractly :: MonadTCM tcm => QName -> tcm Bool
treatAbstractly q = treatAbstractly' q <$> ask

treatAbstractly' :: QName -> TCEnv -> Bool
treatAbstractly' q env
  | envAbstractMode env = True
  | otherwise		= not $ current == m || current `isSubModuleOf` m
  where
    current = envCurrentModule env
    m	    = qnameModule q

-- | get type of a constant 
typeOfConst :: MonadTCM tcm => QName -> tcm Type
typeOfConst q = defType <$> (instantiateDef =<< getConstInfo q)

-- | The name must be a datatype.
sortOfConst :: MonadTCM tcm => QName -> tcm Sort
sortOfConst q =
    do	d <- theDef <$> getConstInfo q
	case d of
	    Datatype _ _ _ _ s _ -> return s
	    _			 -> fail $ "Expected " ++ show q ++ " to be a datatype."

