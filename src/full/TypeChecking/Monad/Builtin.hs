
module TypeChecking.Monad.Builtin where

import Control.Monad.State
import qualified Data.Map as Map

import Syntax.Internal
import TypeChecking.Monad.Base

getBuiltinThings :: TCM (BuiltinThings PrimFun)
getBuiltinThings = gets stBuiltinThings

setBuiltinThings :: BuiltinThings PrimFun -> TCM ()
setBuiltinThings b = modify $ \s -> s { stBuiltinThings = b }

bindBuiltinName :: String -> Term -> TCM ()
bindBuiltinName b x = do
	builtin <- getBuiltinThings
	case Map.lookup b builtin of
	    Just (Builtin y) -> typeError $ DuplicateBuiltinBinding b y x
	    Just (Prim _)    -> typeError $ NoSuchBuiltinName b
	    Nothing	     -> setBuiltinThings $ Map.insert b (Builtin x) builtin

bindPrimitive :: String -> PrimFun -> TCM ()
bindPrimitive b pf = do
	builtin <- getBuiltinThings
	case Map.lookup b builtin :: Maybe (Builtin PrimFun) of
	    _ -> setBuiltinThings $ Map.insert b (Prim pf) builtin


getBuiltin :: String -> TCM Term
getBuiltin x = do
    mt <- getBuiltin' x
    case mt of
        Nothing -> typeError $ NoBindingForBuiltin x
        Just t  -> return t

getBuiltin' :: String -> TCM (Maybe Term)
getBuiltin' x = do
    builtin <- getBuiltinThings
    case Map.lookup x builtin of
	Just (Builtin t) -> return $ Just t
	_		 -> return Nothing

getPrimitive :: String -> TCM PrimFun
getPrimitive x = do
    builtin <- getBuiltinThings
    case Map.lookup x builtin of
	Just (Prim pf) -> return pf
	_	       -> typeError $ NoSuchPrimitiveFunction x

---------------------------------------------------------------------------
-- * The names of built-in things
---------------------------------------------------------------------------

primInteger   = getBuiltin builtinInteger
primFloat     = getBuiltin builtinFloat
primChar      = getBuiltin builtinChar
primString    = getBuiltin builtinString
primBool      = getBuiltin builtinBool
primTrue      = getBuiltin builtinTrue
primFalse     = getBuiltin builtinFalse
primList      = getBuiltin builtinList
primNil       = getBuiltin builtinNil
primCons      = getBuiltin builtinCons
primIO        = getBuiltin builtinIO
primUnit      = getBuiltin builtinUnit
primNat       = getBuiltin builtinNat
primSuc       = getBuiltin builtinSuc
primZero      = getBuiltin builtinZero
primNatPlus   = getBuiltin builtinNatPlus
primNatMinus  = getBuiltin builtinNatMinus
primNatTimes  = getBuiltin builtinNatTimes
primNatDivSuc = getBuiltin builtinNatDivSuc
primNatModSuc = getBuiltin builtinNatModSuc
primNatEquals = getBuiltin builtinNatEquals
primNatLess   = getBuiltin builtinNatLess

builtinNat       = "NATURAL"
builtinSuc       = "SUC"
builtinZero      = "ZERO"
builtinNatPlus   = "NATPLUS"
builtinNatMinus  = "NATMINUS"
builtinNatTimes  = "NATTIMES"
builtinNatDivSuc = "NATDIVSUC"
builtinNatModSuc = "NATMODSUC"
builtinNatEquals = "NATEQUALS"
builtinNatLess   = "NATLESS"
builtinInteger   = "INTEGER"
builtinFloat     = "FLOAT"
builtinChar      = "CHAR"
builtinString    = "STRING"
builtinBool      = "BOOL"
builtinTrue      = "TRUE"
builtinFalse     = "FALSE"
builtinList      = "LIST"
builtinNil       = "NIL"
builtinCons      = "CONS"
builtinIO        = "IO"
builtinUnit      = "UNIT"

builtinTypes :: [String]
builtinTypes =
    [ builtinInteger
    , builtinFloat
    , builtinChar
    , builtinString
    , builtinBool
    , builtinUnit
    , builtinNat
    ]

