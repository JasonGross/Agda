{-# OPTIONS -cpp -fglasgow-exts #-}
module TypeChecking.Errors where

import Control.Monad.State
import Control.Monad.Error

import Syntax.Common
import Syntax.Fixity
import Syntax.Position
import Syntax.Abstract as A
import Syntax.Internal as I
import Syntax.Abstract.Pretty
import Syntax.Concrete.Pretty
import Syntax.Translation.InternalToAbstract
import Syntax.Translation.AbstractToConcrete

import TypeChecking.Monad

import Utils.Pretty
import Utils.Monad
import Utils.Trace

#include "../undefined.h"

---------------------------------------------------------------------------
-- * Top level function
---------------------------------------------------------------------------

prettyError :: TCErr -> TCM String
prettyError err = liftM show $
    prettyTCM err
    `catchError` \err' -> do
	d <- prettyTCM err'
	return $ text "panic: error when printing error!" $$ d
    `catchError` \err'' -> do
	d <- prettyTCM err''
	return $ text "much panic: error when printing error from printing error!" $$ d
    `catchError` \err''' -> return $ fsep (
	pwords "total panic: error when printing error from printing error from printing error." ++
	pwords "I give up! Approximations of errors:" )
	$$ vcat (map (text . tcErrString) [err,err',err'',err'''])

---------------------------------------------------------------------------
-- * Helpers
---------------------------------------------------------------------------

sayWhere :: HasRange a => a -> Doc -> Doc
sayWhere x d = text (show $ getRange x) $$ d

sayWhen :: CallTrace -> TCM Doc -> TCM Doc
sayWhen tr m = case matchCall interestingCall tr of
    Nothing -> m
    Just c  -> do
	dc <- prettyTCM c
	dm <- m
	return $ sayWhere c (dm $$ dc)

panic :: String -> Doc
panic s = fwords $ "Panic: " ++ s

tcErrString :: TCErr -> String
tcErrString err = show (getRange err) ++ " " ++ case err of
    TypeError _ cl -> errorString $ clValue cl
    Exception r s  -> show r ++ " " ++ s
    PatternErr _   -> "PatternErr"
    AbortAssign _  -> "AbortAssign"

errorString :: TypeError -> String
errorString err = case err of
    InternalError _			       -> "InternalError"
    NotImplemented _			       -> "NotImplemented"
    PropMustBeSingleton			       -> "PropMustBeSingleton"
    ShouldEndInApplicationOfTheDatatype _      -> "ShouldEndInApplicationOfTheDatatype"
    ShouldBeAppliedToTheDatatypeParameters _ _ -> "ShouldBeAppliedToTheDatatypeParameters"
    ShouldBeApplicationOf _ _		       -> "ShouldBeApplicationOf"
    DifferentArities			       -> "DifferentArities"
    WrongHidingInLHS _			       -> "WrongHidingInLHS"
    WrongHidingInLambda _		       -> "WrongHidingInLambda"
    WrongHidingInApplication _		       -> "WrongHidingInApplication"
    ShouldBeEmpty _			       -> "ShouldBeEmpty"
    ShouldBeASort _			       -> "ShouldBeASort"
    ShouldBePi _			       -> "ShouldBePi"
    NotAProperTerm			       -> "NotAProperTerm"
    UnequalTerms _ _ _			       -> "UnequalTerms"
    UnequalTypes _ _			       -> "UnequalTypes"
    UnequalHiding _ _			       -> "UnequalHiding"
    UnequalSorts _ _			       -> "UnequalSorts"
    NotLeqSort _ _			       -> "NotLeqSort"
    MetaCannotDependOn _ _ _		       -> "MetaCannotDependOn"
    MetaOccursInItself _		       -> "MetaOccursInItself"
    GenericError _			       -> "GenericError"
    NoSuchBuiltinName _			       -> "NoSuchBuiltinName"
    DuplicateBuiltinBinding _ _ _	       -> "DuplicateBuiltinBinding"
    NoBindingForBuiltin _		       -> "NoBindingForBuiltin"
    NoSuchPrimitiveFunction _		       -> "NoSuchPrimitiveFunction"
    BuiltinInParameterisedModule _	       -> "BuiltinInParameterisedModule"
    NoRHSRequiresAbsurdPattern _	       -> "NoRHSRequiresAbsurdPattern"
    LocalVsImportedModuleClash _	       -> "LocalVsImportedModuleClash"
    UnsolvedMetasInImport _		       -> "UnsolvedMetasInImport"
    CyclicModuleDependency _		       -> "CyclicModuleDependency"
    FileNotFound _ _			       -> "FileNotFound"
    ClashingFileNamesFor _ _		       -> "ClashingFileNamesFor"
    NotInScope _			       -> "NotInScope"
    NoSuchModule _			       -> "NoSuchModule"
    UninstantiatedModule _		       -> "UninstantiatedModule"
    ClashingDefinition _ _		       -> "ClashingDefinition"
    ClashingModule _ _			       -> "ClashingModule"
    ClashingImport _ _			       -> "ClashingImport"
    ClashingModuleImport _ _		       -> "ClashingModuleImport"
    ModuleDoesntExport _ _		       -> "ModuleDoesntExport"
    NotAModuleExpr _			       -> "NotAModuleExpr"
    NotAnExpression _			       -> "NotAnExpression"
    NotAValidLetBinding _		       -> "NotAValidLetBinding"
    NothingAppliedToHiddenArg _		       -> "NothingAppliedToHiddenArg"
    NoParseForApplication _		       -> "NoParseForApplication"
    AmbiguousParseForApplication _ _	       -> "AmbiguousParseForApplication"
    NoParseForLHS _			       -> "NoParseForLHS"
    AmbiguousParseForLHS _ _		       -> "AmbiguousParseForLHS"

---------------------------------------------------------------------------
-- * The PrettyTCM class
---------------------------------------------------------------------------

class PrettyTCM a where
    prettyTCM :: a -> TCM Doc

instance PrettyTCM a => PrettyTCM (Closure a) where
    prettyTCM cl = enterClosure cl prettyTCM

instance PrettyTCM Term where prettyTCM x = prettyA <$> reify x
instance PrettyTCM Type where prettyTCM x = prettyA <$> reify x
instance PrettyTCM Sort where prettyTCM x = prettyA <$> reify x

instance Pretty Name where
    pretty = pretty . nameConcrete

instance Pretty QName where
    pretty = pretty . qnameConcrete

instance PrettyTCM TCErr where
    prettyTCM err = case err of
	TypeError s e -> do
	    s0 <- get
	    put s
	    d <- sayWhen (clTrace e) $ prettyTCM e
	    put s0
	    return d
	Exception r s -> return $ sayWhere r $ fwords s
	PatternErr _  -> return $ sayWhere err $ panic "uncaught pattern violation"
	AbortAssign _ -> return $ sayWhere err $ panic "uncaught aborted assignment"

instance PrettyTCM TypeError where
    prettyTCM err = do
	trace <- getTrace
	case err of
	    InternalError s	-> return $ panic s
	    NotImplemented s	-> return $ fwords $ "Not implemented: " ++ s
	    PropMustBeSingleton -> return $ fwords
		"Datatypes in Prop must have at most one constructor when proof irrelevance is enabled"
	    ShouldEndInApplicationOfTheDatatype t -> do
		dt <- prettyTCM t
		return $ fsep $
		    pwords "The target of a constructor must be the datatype applied to its parameters,"
		    ++ [dt] ++ pwords "isn't"
	    ShouldBeAppliedToTheDatatypeParameters s t -> do
		ds <- prettyTCM s
		dt <- prettyTCM t
		return $ fsep $
		    pwords "The target of the constructor should be" ++ [ds] ++
		    pwords "instead of" ++ [dt]
	    ShouldBeApplicationOf t q -> do
		let dq = pretty q
		return $ fsep $
		    pwords "The pattern constructs an element of" ++ [dq] ++ pwords "which is not the right datatype"
	    DifferentArities -> do
		return $ fsep $
		    pwords "The number of arguments in the defining equations differ"
	    WrongHidingInLHS t -> do
		return $ fsep $
		    pwords "Found an implicit argument where an explicit argument was expected"
	    WrongHidingInLambda t -> do
		return $ fsep $
		    pwords "Found an implicit lambda where an explicit lambda was expected"
	    WrongHidingInApplication t -> do
		return $ fsep $
		    pwords "Found an implicit application where an explicit application was expected"
	    ShouldBeEmpty t -> do
		dt <- prettyTCM t
		return $ fsep $
		    [dt] ++ pwords "should be empty, but it isn't (as far as I can see)"
	    ShouldBeASort t -> do
		dt <- prettyTCM t
		return $ fsep $
		    [dt] ++ pwords "should be a sort, but it isn't"
	    ShouldBePi t -> do
		dt <- prettyTCM t
		return $ fsep $
		    [dt] ++ pwords "should be a function type, but it isn't"
	    NotAProperTerm -> do
		return $ fsep $
		    pwords "Found a malformed term"
	    UnequalTerms s t a -> do
		ds <- prettyTCM s
		dt <- prettyTCM t
		da <- prettyTCM a
		return $ fsep $
		    [ds] ++ pwords "!=" ++ [dt] ++ pwords "of type" ++ [da]
	    UnequalTypes a b -> do
		da <- prettyTCM a
		db <- prettyTCM b
		return $ fsep $
		    [da] ++ pwords "!=" ++ [db]
	    UnequalHiding a b -> do
		da <- prettyTCM a
		db <- prettyTCM b
		return $ fsep $
		    [da] ++ pwords "!=" ++ [db] ++
		    pwords "because one is an implicit function type and the other is an explicit function type"
	    UnequalSorts s1 s2 -> do
		d1 <- prettyTCM s1
		d2 <- prettyTCM s2
		return $ fsep $
		    [d1] ++ pwords "!=" ++ [d2]
	    NotLeqSort s1 s2 -> do
		d1 <- prettyTCM s1
		d2 <- prettyTCM s2
		return $ fsep $
		    pwords "The type of the constructor does not fit in the sort of the datatype, since"
		    ++ [d1] ++ pwords "is not less or equal than" ++ [d2]
	    MetaCannotDependOn m ps i -> do
		let pvar i = prettyTCM $ I.Var i []
		xs <- mapM pvar ps
		x  <- pvar i
		dm <- prettyTCM $ MetaV m []
		let deps = case xs of
			[]  -> pwords "does not depend on any variables"
			[x] -> pwords "only depends on the variable" ++ [x]
			_   -> pwords "only depends on the variables" ++ punctuate comma xs
		return $ fsep $
		    pwords "The metavariable" ++ [dm] ++ pwords "cannot depend on" ++ [x] ++
		    pwords "because it" ++ deps
	    MetaOccursInItself m -> do
		dm <- prettyTCM $ MetaV m []
		return $ fsep $
		    pwords "Cannot construct infinite solution of metavariable" ++ [dm]
	    GenericError s  -> return $ fsep $ pwords s
	    NoSuchBuiltinName s ->
		return $ fsep $ pwords "There is no built-in thing called" ++ [text s]
	    DuplicateBuiltinBinding b x y -> do
		dx <- prettyTCM x
		return $ fsep $ pwords "Duplicate binding for built-in thing" ++ [text b <> comma]
			     ++ pwords "previous binding to" ++ [dx]
	    NoBindingForBuiltin x ->
		return $ fsep $ pwords "No binding for builtin thing" ++ [text x <> comma]
			     ++ pwords ("use {-# BUILTIN " ++ x ++ " name #-} to bind it to 'name'")
	    NoSuchPrimitiveFunction x ->
		return $ fsep $ pwords "There is no primitive function called" ++ [text x]
	    BuiltinInParameterisedModule x ->
		return $ fsep $ pwords "The BUILTIN pragma cannot appear inside a bound context" ++
				pwords "(for instance, in a parameterised module or as a local declaration)"
	    NoRHSRequiresAbsurdPattern ps ->
		return $ fsep $
		    pwords "The right-hand side can only be omitted if there" ++
		    pwords "is an absurd pattern, () or {}, in the left-hand side."
	    LocalVsImportedModuleClash m ->
		return $ fsep $
		    pwords "The module" ++ [text $ show m] ++
		    pwords "can refer to either a local module or an imported module"
	    UnsolvedMetasInImport rs ->
		return $ fsep (
		    pwords "There were unsolved metas in an imported module at the following locations:"
		    ) $$ nest 2 (vcat $ map (text . show) rs)
	    CyclicModuleDependency ms ->
		return $ fsep (pwords "cyclic module dependency:")
			$$ nest 2 (vcat $ map (text . show) ms)
	    FileNotFound x files ->
		return $ fsep ( pwords "Failed to find source of module" ++ [text $ show x] ++
				pwords "in any of the following locations:"
			      ) $$ nest 2 (vcat $ map text files)
	    ClashingFileNamesFor x files ->
		return $ fsep ( pwords "Multiple possible sources for module" ++ [text $ show x] ++
				pwords "found:"
			      ) $$ nest 2 (vcat $ map text files)
	    NotInScope xs ->
		return $ fsep (pwords "Not in scope:") $$ nest 2 (vcat $ map name xs)
		where name x = hsep [ pretty x, text "at", text $ show $ getRange x ]
	    NoSuchModule x			-> return $ text "NoSuchModule"
	    UninstantiatedModule x		-> return $ text "UninstantiatedModule"
	    ClashingDefinition x y		-> return $ text "ClashingDefinition"
	    ClashingModule m1 m2		-> return $ text "ClashingModule"
	    ClashingImport x y			-> return $ text "ClashingImport"
	    ClashingModuleImport x y		-> return $ text "ClashingModuleImport"
	    ModuleDoesntExport m xs		-> return $ text "ModuleDoesntExport"
	    NotAModuleExpr e			-> return $ text "NotAModuleExpr"
	    NotAnExpression e			-> return $ text "NotAnExpression"
	    NotAValidLetBinding nd		-> return $ text "NotAValidLetBinding"
	    NothingAppliedToHiddenArg e		-> return $ text "NothingAppliedToHiddenArg"
	    NoParseForApplication es		-> return $ text "NoParseForApplication"
	    AmbiguousParseForApplication es es' -> return $ text "AmbiguousParseForApplication"
	    NoParseForLHS p			-> return $ text "NoParseForLHS"
	    AmbiguousParseForLHS p ps		-> return $ text "AmbiguousParseForLHS"

instance PrettyTCM Call where
    prettyTCM c = case c of
	CheckClause t cl _  -> do
	    dt  <- prettyTCM t
	    return $ fsep $
		pwords "when checking that the clause"
		++ [prettyA cl] ++ pwords "has type" ++ [dt]
	CheckPatterns ps t _ -> do
	    dt  <- prettyTCM t
	    let dps = map hPretty ps
	    return $ fsep $
		pwords "when checking that the patterns"
		++ dps ++ pwords "fit the type" ++ [dt]
	CheckPattern _ p t _ -> do
	    dt <- prettyTCM t
	    return $ fsep $
		pwords "when checking that the pattern"
		++ [prettyA p] ++ pwords "has type" ++ [dt]
	CheckLetBinding b _ ->
	    return $ fsep $
		pwords "when checking the let binding" ++ [vcat $ map pretty $ abstractToConcrete_ b]
	InferExpr e _ -> do
	    return $ fsep $
		pwords "when inferring the type of" ++ [prettyA e]
	CheckExpr e t _ -> do
	    dt <- prettyTCM t
	    return $ fsep $
		pwords "when checking that the expression"
		++ [prettyA e] ++ pwords "has type" ++ [dt]
	IsTypeCall e s _ -> do
	    ds <- prettyTCM s
	    return $ fsep $
		pwords "when checking that the expression"
		++ [prettyA e] ++ pwords "is a type of sort" ++ [ds]
	IsType_ e _ -> do
	    return $ fsep $
		pwords "when checking that the expression"
		++ [prettyA e] ++ pwords "is a type"
	CheckArguments r es t0 t1 _ -> do
	    let des = map hPretty es
	    dt <- prettyTCM t0
	    return $ fsep $
		pwords "when checking that"
		++ des ++ pwords "are valid arguments to a function of type" ++ [dt]
	CheckDataDef _ x ps cs _ -> do
	    return $ fsep $ pwords "when checking the definition of" ++ [pretty x]
	CheckConstructor d _ _ (A.Axiom _ c _) _ -> do
	    return $ fsep $ pwords "when checking the constructor" ++ [pretty c] ++
			    pwords "in the declaration of" ++ [pretty d]
	CheckConstructor _ _ _ _ _ -> __IMPOSSIBLE__
	CheckFunDef _ f _ _ -> do
	    return $ fsep $ pwords "when checking the definition of" ++ [pretty f]
	CheckPragma _ p _ ->
	    return $ fsep $ pwords "when checking the pragma" ++ [prettyA $ RangeAndPragma noRange p]
	CheckPrimitive _ x e _ ->
	    return $ fsep $ pwords "when checking that the type of the primitive function"
		  ++ [pretty x] ++ pwords "is" ++ [prettyA e]
	InferVar x _ ->
	    return $ fsep $ pwords "when inferring the type of" ++ [pretty x]
	InferDef _ x _ ->
	    return $ fsep $ pwords "when inferring the type of" ++ [pretty x]
	where
	    hPretty a@(Arg h _) = pretty $ abstractToConcreteCtx (hiddenArgumentCtx h) a

interestingCall :: Closure Call -> Maybe (Closure Call)
interestingCall cl = case clValue cl of
    InferVar _ _	      -> Nothing
    InferDef _ _ _	      -> Nothing
    CheckArguments _ [] _ _ _ -> Nothing
    _			      -> Just cl

