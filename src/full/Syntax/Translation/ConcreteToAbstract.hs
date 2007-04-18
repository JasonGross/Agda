{-# OPTIONS -cpp -fglasgow-exts -fallow-overlapping-instances -fallow-undecidable-instances #-}

{-| Translation from "Syntax.Concrete" to "Syntax.Abstract". Involves scope analysis,
    figuring out infix operator precedences and tidying up definitions.
-}
module Syntax.Translation.ConcreteToAbstract
    ( ToAbstract(..), localToAbstract
    , concreteToAbstract_
    , concreteToAbstract
    , OldName(..)
    , TopLevel(..)
    , TopLevelInfo(..)
    ) where

import Prelude hiding (mapM)
import Control.Applicative
import Control.Monad.Reader hiding (mapM)
import Data.Typeable
import Data.Traversable (mapM)

import Syntax.Concrete as C
import Syntax.Abstract as A
import Syntax.Position
import Syntax.Common
import Syntax.Info
import Syntax.Concrete.Definitions as CD
import Syntax.Concrete.Operators
import Syntax.Fixity
import Syntax.Scope.Base
import Syntax.Scope.Monad
import Syntax.Strict

import TypeChecking.Monad.Base (TypeError(..), Call(..), typeError)
import TypeChecking.Monad.Trace (traceCall, traceCallCPS)
import TypeChecking.Monad.State
import TypeChecking.Monad.Options

#ifndef __HADDOCK__
import {-# SOURCE #-} Interaction.Imports (scopeCheckImport)
#endif

import Utils.Monad
import Utils.Tuple

#include "../../undefined.h"


{--------------------------------------------------------------------------
    Exceptions
 --------------------------------------------------------------------------}

notAModuleExpr e	    = typeError $ NotAModuleExpr e
notAnExpression e	    = typeError $ NotAnExpression e
notAValidLetBinding d	    = typeError $ NotAValidLetBinding d
nothingAppliedToHiddenArg e = typeError $ NothingAppliedToHiddenArg e

-- Debugging

printLocals :: Int -> String -> ScopeM ()
printLocals v s = verbose v $ do
  locals <- scopeLocals <$> getScope
  liftIO $ putStrLn $ s ++ " " ++ show locals

printScope :: Int -> String -> ScopeM ()
printScope v s = verbose v $ do
  scope <- getScope
  liftIO $ putStrLn $ s ++ " " ++ show scope

{--------------------------------------------------------------------------
    Helpers
 --------------------------------------------------------------------------}

lhsArgs :: C.Pattern -> [NamedArg C.Pattern]
lhsArgs p = case appView p of
    Arg _ (Named _ (IdentP _)) : ps -> ps
    _				    -> __IMPOSSIBLE__
    where
	mkHead	  = Arg NotHidden . unnamed
	notHidden = Arg NotHidden . unnamed
	appView p = case p of
	    AppP p arg	  -> appView p ++ [arg]
	    OpAppP _ x ps -> mkHead (IdentP $ C.QName x) : map notHidden ps
	    ParenP _ p	  -> appView p
	    RawAppP _ _	  -> __IMPOSSIBLE__
	    _		  -> [ mkHead p ]

makeSection :: ModuleInfo -> A.ModuleName -> A.Telescope -> [A.Declaration] -> [A.Declaration]
makeSection info m tel ds = [A.Section info m tel ds]

annotateDecl :: A.Declaration -> ScopeM A.Declaration
annotateDecl d = annotateDecls [d]

annotateDecls :: [A.Declaration] -> ScopeM A.Declaration
annotateDecls ds = do
  s <- getScope
  return $ ScopedDecl s ds

annotateExpr :: A.Expr -> ScopeM A.Expr
annotateExpr e = do
  s <- getScope
  return $ ScopedExpr s e

{--------------------------------------------------------------------------
    Translation
 --------------------------------------------------------------------------}

concreteToAbstract_ :: ToAbstract c a => c -> ScopeM a
concreteToAbstract_ x = toAbstract x

concreteToAbstract :: ToAbstract c a => ScopeInfo -> c -> ScopeM a
concreteToAbstract scope x = withScope_ scope (toAbstract x)

-- | Things that can be translated to abstract syntax are instances of this
--   class.
class ToAbstract concrete abstract | concrete -> abstract where
    toAbstract	  :: concrete -> ScopeM abstract

-- | This function should be used instead of 'toAbstract' for things that need
--   to keep track of precedences to make sure that we don't forget about it.
toAbstractCtx :: ToAbstract concrete abstract =>
		 Precedence -> concrete -> ScopeM abstract
toAbstractCtx ctx c = withContextPrecedence ctx $ toAbstract c

setContextCPS :: Precedence -> (a -> ScopeM b) ->
		 ((a -> ScopeM b) -> ScopeM b) -> ScopeM b
setContextCPS p ret f = do
  p' <- getContextPrecedence
  withContextPrecedence p $ f $ withContextPrecedence p' . ret

localToAbstractCtx :: ToAbstract concrete abstract =>
		     Precedence -> concrete -> (abstract -> ScopeM a) -> ScopeM a
localToAbstractCtx ctx c ret = setContextCPS ctx ret (localToAbstract c)

-- | This operation does not affect the scope, i.e. the original scope
--   is restored upon completion.
localToAbstract :: ToAbstract c a => c -> (a -> ScopeM b) -> ScopeM b
localToAbstract x ret = fst <$> localToAbstract' x ret

-- | Like 'localToAbstract' but returns the scope after the completion of the
--   second argument.
localToAbstract' :: ToAbstract c a => c -> (a -> ScopeM b) -> ScopeM (b, ScopeInfo)
localToAbstract' x ret = do
  scope <- getScope
  withScope scope $ ret =<< toAbstract x

withLocalVars :: ScopeM a -> ScopeM a
withLocalVars m = do
  vars <- scopeLocals <$> getScope
  x    <- m
  modifyScope $ \s -> s { scopeLocals = vars }
  return x

instance (ToAbstract c1 a1, ToAbstract c2 a2) => ToAbstract (c1,c2) (a1,a2) where
  toAbstract (x,y) =
    (,) <$> toAbstract x <*> toAbstract y

instance (ToAbstract c1 a1, ToAbstract c2 a2, ToAbstract c3 a3) =>
	 ToAbstract (c1,c2,c3) (a1,a2,a3) where
    toAbstract (x,y,z) = flatten <$> toAbstract (x,(y,z))
	where
	    flatten (x,(y,z)) = (x,y,z)

instance ToAbstract c a => ToAbstract [c] [a] where
    toAbstract = mapM toAbstract 

instance ToAbstract c a => ToAbstract (Maybe c) (Maybe a) where
    toAbstract Nothing  = return Nothing
    toAbstract (Just x) = Just <$> toAbstract x

-- Names ------------------------------------------------------------------

newtype NewName = NewName C.Name
newtype OldQName = OldQName C.QName
newtype OldName = OldName C.Name
newtype PatName = PatName C.QName

instance ToAbstract NewName A.Name where
  toAbstract (NewName x) = do
    y <- freshAbstractName_ x
    bindVariable x y
    return y

nameExpr :: AbstractName -> A.Expr
nameExpr d = mk (anameKind d) $ anameName d
  where
    mk DefName = Def
    mk ConName = Con

instance ToAbstract OldQName A.Expr where
  toAbstract (OldQName x) = do
    qx <- resolveName x
    case qx of
      VarName x'    -> return $ A.Var x'
      DefinedName d -> return $ nameExpr d
      UnknownName   -> notInScope x

data APatName = VarPatName A.Name
	      | ConPatName AbstractName

instance ToAbstract PatName APatName where
  toAbstract (PatName x) = do
    reportLn 10 $ "checking pattern name: " ++ show x
    rx <- resolveName x
    z  <- case (rx, x) of
      -- TODO: warn about shadowing
      (VarName y,     C.QName x)			  -> return $ Left x
      (DefinedName d, C.QName x) | DefName == anameKind d -> return $ Left x
      (UnknownName,   C.QName x)			  -> return $ Left x
      (DefinedName d, _	 )	 | ConName == anameKind d -> return $ Right d
      _							  -> fail $ "not a constructor: " ++ show x -- TODO
    case z of
      Left x  -> do
	reportLn 10 $ "it was a var: " ++ show x
	p <- VarPatName <$> toAbstract (NewName x)
	printLocals 10 "bound it:"
	return p
      Right c -> do
	reportLn 10 $ "it was a con: " ++ show (anameName c)
	return $ ConPatName c

-- Should be a defined name.
instance ToAbstract OldName A.QName where
  toAbstract (OldName x) = do
    rx <- resolveName (C.QName x)
    case rx of
      DefinedName d -> return $ anameName d
      _		    -> __IMPOSSIBLE__
	  -- fail $ "panic: " ++ show x ++ " should have been defined (not " ++ show rx ++ ")"

newtype NewModuleName  = NewModuleName  C.Name
newtype NewModuleQName = NewModuleQName C.QName
newtype OldModuleName  = OldModuleName  C.QName

instance ToAbstract NewModuleName A.ModuleName where
  toAbstract (NewModuleName x) = mnameFromList . (:[]) <$> freshAbstractName_ x

instance ToAbstract NewModuleQName A.ModuleName where
  toAbstract (NewModuleQName q) =
    foldr1 A.qualifyM <$> mapM (toAbstract . NewModuleName) (toList q)
    where
      toList (C.QName  x) = [x]
      toList (C.Qual m x) = m : toList x

instance ToAbstract OldModuleName A.ModuleName where
  toAbstract (OldModuleName q) = amodName <$> resolveModule q

-- Expressions ------------------------------------------------------------

-- | Peel off 'C.HiddenArg' and represent it as an 'NamedArg'.
mkNamedArg :: C.Expr -> NamedArg C.Expr
mkNamedArg (C.HiddenArg _ e) = Arg Hidden e
mkNamedArg e		     = Arg NotHidden $ unnamed e

-- | Peel off 'C.HiddenArg' and represent it as an 'Arg', throwing away any name.
mkArg :: C.Expr -> Arg C.Expr
mkArg (C.HiddenArg _ e) = Arg Hidden $ namedThing e
mkArg e			= Arg NotHidden e

instance ToAbstract C.Expr A.Expr where
  toAbstract e =
    traceCall (ScopeCheckExpr e) $ annotateExpr =<< case e of
  -- Names
      Ident x -> toAbstract (OldQName x)

  -- Literals
      C.Lit l -> return $ A.Lit l

  -- Meta variables
      C.QuestionMark r n -> do
	scope <- getScope
	return $ A.QuestionMark $ MetaInfo
		    { metaRange  = r
		    , metaScope  = scope
		    , metaNumber = n
		    }
      C.Underscore r n -> do
	scope <- getScope
	return $ A.Underscore $ MetaInfo
		    { metaRange  = r
		    , metaScope  = scope
		    , metaNumber = n
		    }

  -- Raw application
      C.RawApp r es -> do
	e <- parseApplication es
	toAbstract e

  -- Application
      C.App r e1 e2 -> do
	e1 <- toAbstractCtx FunctionCtx e1
	e2 <- toAbstractCtx ArgumentCtx e2
	return $ A.App (ExprRange r) e1 e2

  -- Operator application
      C.OpApp r op es -> toAbstractOpApp r op es

  -- Malplaced hidden argument
      C.HiddenArg _ _ -> nothingAppliedToHiddenArg e

  -- Lambda
      e0@(C.Lam r bs e) -> do
	localToAbstract bs $ \(b:bs') -> do
	e	 <- toAbstractCtx TopCtx e
	let info = ExprRange r
	return $ A.Lam info b $ foldr mkLam e bs'
	where
	    mkLam b e = A.Lam (ExprRange $ fuseRange b e) b e

  -- Function types
      C.Fun r e1 e2 -> do
	e1 <- toAbstractCtx FunctionSpaceDomainCtx $ mkArg e1
	e2 <- toAbstractCtx TopCtx e2
	let info = ExprRange r
	return $ A.Fun info e1 e2

      e0@(C.Pi tel e) ->
	localToAbstract tel $ \tel -> do
	e    <- toAbstractCtx TopCtx e
	let info = ExprRange (getRange e0)
	return $ A.Pi info tel e

  -- Sorts
      C.Set _    -> return $ A.Set (ExprRange $ getRange e) 0
      C.SetN _ n -> return $ A.Set (ExprRange $ getRange e) n
      C.Prop _   -> return $ A.Prop $ ExprRange $ getRange e

  -- Let
      e0@(C.Let _ ds e) ->
	localToAbstract (LetDefs ds) $ \ds' -> do
	e	 <- toAbstractCtx TopCtx e
	let info = ExprRange (getRange e0)
	return $ A.Let info ds' e

  -- Parenthesis
      C.Paren _ e -> toAbstractCtx TopCtx e

  -- Pattern things
      C.As _ _ _ -> notAnExpression e
      C.Dot _ _  -> notAnExpression e
      C.Absurd _ -> notAnExpression e

instance ToAbstract C.LamBinding A.LamBinding where
  toAbstract (C.DomainFree h x) = A.DomainFree h <$> toAbstract (NewName x)
  toAbstract (C.DomainFull tb)	= A.DomainFull <$> toAbstract tb

instance ToAbstract C.TypedBindings A.TypedBindings where
  toAbstract (C.TypedBindings r h bs) = A.TypedBindings r h <$> toAbstract bs

instance ToAbstract C.TypedBinding A.TypedBinding where
  toAbstract (C.TBind r xs t) = do
    t' <- toAbstractCtx TopCtx t
    xs' <- toAbstract (map NewName xs)
    return $ A.TBind r xs' t'
  toAbstract (C.TNoBind e) = do
    e <- toAbstractCtx TopCtx e
    return (A.TNoBind e)

newtype TopLevel a = TopLevel a

-- | Returns the scope inside the checked module.
scopeCheckModule :: Range -> Access -> IsAbstract -> C.QName -> C.Telescope -> [C.Declaration] ->
		    ScopeM (ScopeInfo, [A.Declaration])
scopeCheckModule r a c x tel ds = do
  m <- toAbstract (NewModuleQName x)
  pushScope m
  qm <- getCurrentModule
  ds <- withLocalVars $ do
	  tel <- toAbstract tel
	  makeSection info qm tel <$> toAbstract ds
  scope <- getScope
  popScope a
  bindQModule a x qm
  return (scope, ds)
  where
    info = mkRangedModuleInfo a c r

data TopLevelInfo = TopLevelInfo
	{ topLevelDecls :: [A.Declaration]
	, outsideScope  :: ScopeInfo
	, insideScope	:: ScopeInfo
	}

-- Top-level declarations are always (import|open)* module
instance ToAbstract (TopLevel [C.Declaration]) TopLevelInfo where
    toAbstract (TopLevel ds) = case splitAt (length ds - 1) ds of
	(ds', [C.Module r m tel ds]) -> do
	  setTopLevelModule m
	  ds'	       <- toAbstract ds'
	  (scope0, ds) <- scopeCheckModule r PublicAccess ConcreteDef m tel ds
	  scope	       <- getScope
	  return $ TopLevelInfo (ds' ++ ds) scope scope0
	_ -> __IMPOSSIBLE__

instance ToAbstract [C.Declaration] [A.Declaration] where
  toAbstract = toAbstract . niceDeclarations

newtype LetDefs = LetDefs [C.Declaration]
newtype LetDef = LetDef NiceDeclaration

instance ToAbstract LetDefs [A.LetBinding] where
    toAbstract (LetDefs ds) =
	toAbstract (map LetDef $ niceDeclarations ds)

instance ToAbstract C.RHS A.RHS where
    toAbstract C.AbsurdRHS = return $ A.AbsurdRHS
    toAbstract (C.RHS e)   = A.RHS <$> toAbstract e

instance ToAbstract LetDef A.LetBinding where
    toAbstract (LetDef d) =
	case d of
	    NiceDef _ c [CD.Axiom _ _ _ _ x t] [CD.FunDef _ _ _ _ _ _ [cl]] ->
		do  e <- letToAbstract cl
		    t <- toAbstract t
		    x <- toAbstract (NewName x)
		    return $ A.LetBind (LetSource c) x t e
	    _	-> notAValidLetBinding d
	where
	    letToAbstract (CD.Clause top clhs (C.RHS rhs) []) = do
		p    <- parseLHS top clhs
		localToAbstract (lhsArgs p) $ \args ->
		    do	rhs <- toAbstract rhs
			foldM lambda rhs args
	    letToAbstract _ = notAValidLetBinding d

	    -- Named patterns not allowed in let definitions
	    lambda e (Arg h (Named Nothing (A.VarP x))) = return $ A.Lam i (A.DomainFree h x) e
		where
		    i = ExprRange (fuseRange x e)
	    lambda e (Arg h (Named Nothing (A.WildP i))) =
		do  x <- freshNoName (getRange i)
		    return $ A.Lam i' (A.DomainFree h x) e
		where
		    i' = ExprRange (fuseRange i e)
	    lambda _ _ = notAValidLetBinding d

instance ToAbstract C.Pragma A.Pragma where
    toAbstract (C.OptionsPragma _ opts) = return $ A.OptionsPragma opts
    toAbstract (C.BuiltinPragma _ b e) = do
	e <- toAbstract e
	return $ A.BuiltinPragma b e

-- Only constructor names are bound by definitions.
instance ToAbstract NiceDefinition Definition where

    -- Function definitions
    toAbstract (CD.FunDef r ds f p a x cs) =
	do  (x',cs') <- toAbstract (OldName x,cs)
	    return $ A.FunDef (mkSourcedDefInfo x f p a ds) x' cs'

    -- Data definitions
    toAbstract (CD.DataDef r f p a x pars cons) = do
	(pars,cons) <- localToAbstract pars $ \pars -> do
			cons <- toAbstract (map Constr cons)
			return (pars, cons)
	x' <- toAbstract (OldName x)
	-- The constructors disappeared from scope when we exited the
	-- localToAbstract, so we have to reintroduce them.
	toAbstract (map Constr cons)
	return $ A.DataDef (mkRangedDefInfo x f p a r) x' pars cons

-- The only reason why we return a list is that open declarations disappears.
-- For every other declaration we get a singleton list.
instance ToAbstract NiceDeclaration A.Declaration where

  toAbstract d = annotateDecls =<< case d of  -- TODO: trace call

  -- Axiom
    CD.Axiom r f p a x t -> do
      t' <- toAbstractCtx TopCtx t
      y  <- freshAbstractQName f x
      bindName p DefName x y
      return [ A.Axiom (mkRangedDefInfo x f p a r) y t' ]

  -- Primitive function
    PrimitiveFunction r f p a x t -> do
      t' <- toAbstractCtx TopCtx t
      y  <- freshAbstractQName f x
      bindName p DefName x y
      return [ A.Primitive (mkRangedDefInfo x f p a r) y t' ]

  -- Definitions (possibly mutual)
    NiceDef r cs ts ds -> do
      (ts', ds') <- toAbstract (ts, ds)
      return [ Definition (DeclInfo C.noName_ $ DeclRange r) ts' ds' ]
			  -- TODO: what does the info mean here?

  -- TODO: what does an abstract module mean? The syntax doesn't allow it.
    NiceModule r p a name tel ds -> snd <$> scopeCheckModule r p a name tel ds

    NiceModuleMacro r p a x tel e open dir -> case appView e of
      AppView (Ident m) args  ->
	withLocalVars $ do
	tel' <- toAbstract tel
	(x',m1,args') <- toAbstract ( NewModuleName x
				    , OldModuleName m
				    , args
				    )
	pushScope x'
	m0 <- getCurrentModule
	openModule_ m $ dir { C.publicOpen = True }
	modifyTopScope $ freshCanonicalNames m1 m0
	popScope p
	bindModule p x m0
	case open of
	  DontOpen -> return ()
	  DoOpen   -> openModule_ (C.QName x) dir
	let decl = Apply info m0 m1 args'
	case tel' of
	  []  -> return [ decl ]
	  _	  -> do
	    -- If the module is reabstracted we create an anonymous
	    -- section around it.
	    noName <- freshAbstractName_ $ C.noName $ getRange x
	    top    <- getCurrentModule
	    return $ makeSection info m0 tel' [ decl ]
      _	-> notAModuleExpr e
      where
	info = mkRangedModuleInfo p a r

    NiceOpen r x dir -> do
      current <- getCurrentModule
      m	      <- toAbstract (OldModuleName x)
      n	      <- length . scopeLocals <$> getScope

      -- Opening a submodule or opening into a non-parameterised module
      -- is fine. Otherwise we have to create a temporary module.
      if m `isSubModuleOf` current || n == 0
	then do
	  openModule_ x dir
	  return []
	else do
	  let tmp = C.noName (getRange x) -- TODO: better name?
	  d <- toAbstract $ NiceModuleMacro r PrivateAccess ConcreteDef
					    tmp [] (C.Ident x) DoOpen dir
	  return [d]

    NicePragma r p -> do
      p <- toAbstract p
      return [ A.Pragma r p ]

    NiceImport r x as open dir -> do
      m	  <- toAbstract $ NewModuleQName x
      printScope 10 "before import:"
      i	  <- applyImportDirective dir <$> scopeCheckImport m
      printScope 10 $ "scope checked import: " ++ show i
      modifyTopScope (`mergeScope` i)
      printScope 10 "merged imported sig:"
      ds <- case open of
	DontOpen -> return []
	DoOpen   -> do
	  toAbstract [ C.Open r name dir { usingOrHiding = Hiding []
					 , renaming	 = []
					 }
		     ]
      return $ A.Import (mkRangedModuleInfo PublicAccess ConcreteDef r) m : ds
      where
	  name = maybe x C.QName as

newtype Constr a = Constr a

instance ToAbstract (Constr CD.NiceDeclaration) A.Declaration where
    toAbstract (Constr (CD.Axiom r f p a x t)) = do
	t' <- toAbstractCtx TopCtx t
	y  <- freshAbstractQName f x
	bindName p' ConName x y
	return $ A.Axiom (mkRangedDefInfo x f p a r) y t'
	where
	    -- An abstract constructor is private (abstract constructor means
	    -- abstract datatype, so the constructor should not be exported).
	    p' = case (a, p) of
		    (AbstractDef, _) -> PrivateAccess
		    (_, p)	     -> p

    toAbstract _ = __IMPOSSIBLE__    -- a constructor is always an axiom

-- TODO: do this in a nicer way?
instance ToAbstract (Constr A.Constructor) () where
  toAbstract (Constr (A.ScopedDecl _ [d])) = toAbstract $ Constr d
  toAbstract (Constr (A.Axiom i y _)) = do
    let x = nameConcrete $ qnameName y	-- TODO: right name?
    bindName (defAccess i) ConName x y
  toAbstract _ = __IMPOSSIBLE__	-- constructors are axioms

instance ToAbstract CD.Clause A.Clause where
    toAbstract (CD.Clause top lhs rhs wh) =
	localToAbstract (LeftHandSide top lhs) $ \lhs' -> do	-- the order matters here!
	  printLocals 10 "after lhs:"
	  wh'  <- toAbstract wh	-- TODO: this will have to change when adding modules for local defs
	  rhs' <- toAbstractCtx TopCtx rhs
	  return $ A.Clause lhs' rhs' wh'

data LeftHandSide = LeftHandSide C.Name C.LHS

instance ToAbstract LeftHandSide A.LHS where
    toAbstract (LeftHandSide top lhs) = do
	-- traceCall (ScopeCheckLHS top lhs) ret $ \ret -> do -- TODO
	p    <- parseLHS top lhs
	printLocals 10 "before lhs:"
	args <- toAbstract (lhsArgs p)
	printLocals 10 "checked pattern:"
	args <- toAbstract args -- take care of dot patterns
	printLocals 10 "checked dots:"
	x    <- toAbstract (OldName top)
	return $ A.LHS (LHSSource lhs) x args

instance ToAbstract c a => ToAbstract (Arg c) (Arg a) where
    toAbstract (Arg h e) = Arg h <$> toAbstractCtx (hiddenArgumentCtx h) e

instance ToAbstract c a => ToAbstract (Named name c) (Named name a) where
    toAbstract (Named n e) = Named n <$> toAbstract e

-- Patterns are done in two phases. First everything but the dot patterns, and
-- then the dot patterns. This is because dot patterns can refer to variables
-- bound anywhere in the pattern.

instance ToAbstract c a => ToAbstract (A.Pattern' c) (A.Pattern' a) where
    toAbstract = mapM toAbstract

instance ToAbstract C.Pattern (A.Pattern' C.Expr) where

    toAbstract p@(C.IdentP x) = do
	px <- toAbstract (PatName x)
	case px of
	    VarPatName y -> return $ VarP y
	    ConPatName d -> return $ ConP (PatRange (getRange p)) (anameName d) []

    toAbstract p0@(AppP p q) = do
	(p', q') <- toAbstract (p,q)
	case p' of
	    ConP _ x as -> return $ ConP info x (as ++ [q'])
	    DefP _ x as -> return $ DefP info x (as ++ [q'])
	    _		-> __IMPOSSIBLE__
	where
	    r = getRange p0
	    info = PatSource r $ \pr -> if appBrackets pr then ParenP r p0 else p0

    toAbstract p0@(OpAppP r op ps) = do
	p <- toAbstract (IdentP $ C.QName op)
	ps <- toAbstract ps
	case p of
	  ConP _ x as -> return $ ConP info x (as ++ map (Arg NotHidden . unnamed) ps)
	  DefP _ x as -> return $ DefP info x (as ++ map (Arg NotHidden . unnamed) ps)
	  _	      -> __IMPOSSIBLE__
	where
	    r = getRange p0
	    info = PatSource r $ \pr -> if appBrackets pr then ParenP r p0 else p0

    -- Removed when parsing
    toAbstract (HiddenP _ _) = __IMPOSSIBLE__
    toAbstract (RawAppP _ _) = __IMPOSSIBLE__

    toAbstract p@(C.WildP r)    = return $ A.WildP (PatSource r $ const p)
    toAbstract (C.ParenP _ p)   = toAbstract p
    toAbstract (C.LitP l)	= return $ A.LitP l
    toAbstract p0@(C.AsP r x p) = do
	x <- toAbstract (NewName x)
	p <- toAbstract p
	return $ A.AsP info x p
	where
	    info = PatSource r $ \_ -> p0
    -- we have to do dot patterns at the end
    toAbstract p0@(C.DotP r e) = return $ A.DotP info e
	where info = PatSource r $ \_ -> p0
    toAbstract p0@(C.AbsurdP r) = return $ A.AbsurdP info
	where
	    info = PatSource r $ \_ -> p0

-- | Turn an operator application into abstract syntax. Make sure to record the
-- right precedences for the various arguments.
toAbstractOpApp :: Range -> C.Name -> [C.Expr] -> ScopeM A.Expr
toAbstractOpApp r op@(C.Name _ xs) es = do
    f  <- getFixity (C.QName op)
    op <- toAbstract (OldQName $ C.QName op) -- op-apps cannot bind the op
    foldl app op <$> left f xs es
    where
	app e arg = A.App (ExprRange (fuseRange e arg)) e
		  $ Arg NotHidden $ unnamed arg

	left f (Hole : xs) (e : es) = do
	    e  <- toAbstractCtx (LeftOperandCtx f) e
	    es <- inside f xs es
	    return (e : es)
	left f (Id _ : xs) es = inside f xs es
	left f (Hole : _) []  = __IMPOSSIBLE__
	left f [] _	      = __IMPOSSIBLE__

	inside f [x]	      es      = right f x es
	inside f (Id _ : xs)  es      = inside f xs es
	inside f (Hole : xs) (e : es) = do
	    e  <- toAbstractCtx InsideOperandCtx e
	    es <- inside f xs es
	    return (e : es)
	inside _ (Hole : _) [] = __IMPOSSIBLE__
	inside _ [] _	       = __IMPOSSIBLE__

	right f Hole [e] = do
	    e <- toAbstractCtx (RightOperandCtx f) e
	    return [e]
	right _ (Id _) [] = return []
	right _ Hole _	  = __IMPOSSIBLE__
	right _ (Id _) _  = __IMPOSSIBLE__

