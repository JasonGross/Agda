
module Agda.TypeChecking.Monad.Env where

import Control.Monad.Reader
import Data.List
import Data.Monoid

import Agda.Syntax.Common
import Agda.Syntax.Abstract.Name

import Agda.TypeChecking.Monad.Base

-- | Get the name of the current module, if any.
currentModule :: TCM ModuleName
currentModule = asks envCurrentModule

-- | Set the name of the current module.
withCurrentModule :: ModuleName -> TCM a -> TCM a
withCurrentModule m =
    local $ \e -> e { envCurrentModule = m }

-- | Get the number of variables bound by anonymous modules.
getAnonymousVariables :: ModuleName -> TCM Nat
getAnonymousVariables m = do
  ms <- asks envAnonymousModules
  return $ sum [ n | (m', n) <- ms, mnameToList m' `isPrefixOf` mnameToList m ]

-- | Add variables bound by an anonymous module.
withAnonymousModule :: ModuleName -> Nat -> TCM a -> TCM a
withAnonymousModule m n =
  local $ \e -> e { envAnonymousModules   = (m, n) : envAnonymousModules e
                  }

-- | Set the current environment to the given
withEnv :: TCEnv -> TCM a -> TCM a
withEnv env m = local (\env0 -> env { envAllowDestructiveUpdate = envAllowDestructiveUpdate env0 }) m

-- | Get the current environment
getEnv :: TCM TCEnv
getEnv = ask

-- | Increases the module nesting level by one in the given
-- computation.
withIncreasedModuleNestingLevel :: TCM a -> TCM a
withIncreasedModuleNestingLevel =
  local (\e -> e { envModuleNestingLevel =
                     envModuleNestingLevel e + 1 })

-- | Restore setting for 'ExpandLast' to default.
doExpandLast :: TCM a -> TCM a
doExpandLast = local $ \ e -> e { envExpandLast = ExpandLast }

dontExpandLast :: TCM a -> TCM a
dontExpandLast = local $ \ e -> e { envExpandLast = DontExpandLast }

-- | If the reduced did a proper match (constructor or literal pattern),
--   then record this as simplification step.
performedSimplification :: TCM a -> TCM a
performedSimplification = local $ \ e -> e { envSimplification = YesSimplification }

performedSimplification' :: Simplification -> TCM a -> TCM a
performedSimplification' simpl = local $ \ e -> e { envSimplification = simpl `mappend` envSimplification e }

-- | Reduce @Def f vs@ only if @f@ is a projection.
onlyReduceProjections :: TCM a -> TCM a
onlyReduceProjections = local $ \ e -> e { envAllowedReductions = [ProjectionReductions] }

dontReduceProjections :: TCM a -> TCM a
dontReduceProjections = local $ \ e -> e { envAllowedReductions = [FunctionReductions] }

allowAllReductions :: TCM a -> TCM a
allowAllReductions = local $ \ e -> e { envAllowedReductions = allReductions }
