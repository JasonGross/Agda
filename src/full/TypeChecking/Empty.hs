
module TypeChecking.Empty where

import Syntax.Internal
import TypeChecking.Monad
import TypeChecking.Reduce

-- | Make sure that a type is empty.
isEmptyType :: Type -> TCM ()
isEmptyType t = do
    t <- reduce t
    case t of
	El _ (Def d _) -> do
	    Defn _ _ di <- getConstInfo d
	    case di of
		Datatype _ [] _ _ -> return ()
		_		  -> notEmpty t
	_ -> notEmpty t
    where
	notEmpty t = typeError $ ShouldBeEmpty t


