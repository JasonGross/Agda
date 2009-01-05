{
{-# OPTIONS -fno-warn-incomplete-patterns #-}
{-| The parser is generated by Happy (<http://www.haskell.org/happy>).
-}
module Agda.Syntax.Parser.Parser (
      moduleParser
    , exprParser
    , tokensParser
    ) where

import Control.Monad
import Control.Monad.State
import Data.Char  (isDigit)
import Data.List
import Data.Maybe
import qualified Data.Traversable as T

import Agda.Syntax.Position
import Agda.Syntax.Parser.Monad
import Agda.Syntax.Parser.Lexer
import Agda.Syntax.Parser.Tokens
import Agda.Syntax.Concrete
import Agda.Syntax.Concrete.Name
import Agda.Syntax.Concrete.Pretty
import Agda.Syntax.Common
import Agda.Syntax.Fixity
import Agda.Syntax.Literal

import Agda.Utils.Monad

}

%name tokensParser Tokens
%name exprParser Expr
%name moduleParser File
%tokentype { Token }
%monad { Parser }
%lexer { lexer } { TokEOF }

-- This is a trick to get rid of shift/reduce conflicts arising because we want
-- to parse things like "m >>= \x -> k x". See the Expr rule for more
-- information.
%nonassoc LOWEST
%nonassoc '->'

%token
    'let'	{ TokKeyword KwLet $$ }
    'in'	{ TokKeyword KwIn $$ }
    'where'	{ TokKeyword KwWhere $$ }
    'with'	{ TokKeyword KwWith $$ }
    'postulate' { TokKeyword KwPostulate $$ }
    'primitive' { TokKeyword KwPrimitive $$ }
    'open'	{ TokKeyword KwOpen $$ }
    'import'	{ TokKeyword KwImport $$ }
    'using'	{ TokKeyword KwUsing $$ }
    'hiding'	{ TokKeyword KwHiding $$ }
    'renaming'	{ TokKeyword KwRenaming $$ }
    'to'	{ TokKeyword KwTo $$ }
    'public'	{ TokKeyword KwPublic $$ }
    'module'	{ TokKeyword KwModule $$ }
    'data'	{ TokKeyword KwData $$ }
    'codata'	{ TokKeyword KwCoData $$ }
    'record'	{ TokKeyword KwRecord $$ }
    'field'	{ TokKeyword KwField $$ }
    'infix'	{ TokKeyword KwInfix $$ }
    'infixl'	{ TokKeyword KwInfixL $$ }
    'infixr'	{ TokKeyword KwInfixR $$ }
    'mutual'	{ TokKeyword KwMutual $$ }
    'abstract'	{ TokKeyword KwAbstract $$ }
    'private'	{ TokKeyword KwPrivate $$ }
    'Prop'	{ TokKeyword KwProp $$ }
    'Set'	{ TokKeyword KwSet $$ }
    'forall'	{ TokKeyword KwForall $$ }
    'OPTIONS'	{ TokKeyword KwOPTIONS $$ }
    'BUILTIN'	{ TokKeyword KwBUILTIN $$ }
    'IMPORT'	{ TokKeyword KwIMPORT $$ }
    'COMPILED'	{ TokKeyword KwCOMPILED $$ }
    'COMPILED_DATA' { TokKeyword KwCOMPILED_DATA $$ }
    'COMPILED_TYPE' { TokKeyword KwCOMPILED_TYPE $$ }
    'LINE'	{ TokKeyword KwLINE $$ }

    setN	{ TokSetN $$ }
    tex		{ TokTeX $$ }
    comment	{ TokComment $$ }

    '...'	{ TokSymbol SymEllipsis $$ }
    '.'		{ TokSymbol SymDot $$ }
    ';'		{ TokSymbol SymSemi $$ }
    ':'		{ TokSymbol SymColon $$ }
    '='		{ TokSymbol SymEqual $$ }
    '~'		{ TokSymbol SymSim $$ }
    '_'		{ TokSymbol SymUnderscore $$ }
    '?'		{ TokSymbol SymQuestionMark $$ }
    '->'	{ TokSymbol SymArrow $$ }
    '\\'	{ TokSymbol SymLambda $$ }
    '@'		{ TokSymbol SymAs $$ }
    '|'		{ TokSymbol SymBar $$ }
    '('		{ TokSymbol SymOpenParen $$ }
    ')'		{ TokSymbol SymCloseParen $$ }
    '{'		{ TokSymbol SymOpenBrace $$ }
    '}'		{ TokSymbol SymCloseBrace $$ }
    vopen	{ TokSymbol SymOpenVirtualBrace $$ }
    vclose	{ TokSymbol SymCloseVirtualBrace $$ }
    vsemi	{ TokSymbol SymVirtualSemi $$ }
    '{-#'	{ TokSymbol SymOpenPragma $$ }
    '#-}'	{ TokSymbol SymClosePragma $$ }

    id		{ TokId $$ }
    q_id	{ TokQId $$ }

    string	{ TokString $$ }
    literal	{ TokLiteral $$ }

%%

{--------------------------------------------------------------------------
    Parsing the token stream. Used by the TeX compiler.
 --------------------------------------------------------------------------}

-- Parse a list of tokens.
Tokens :: { [Token] }
Tokens : TokensR	{ reverse $1 }

-- Happy is much better at parsing left recursive grammars (constant
-- stack size vs. linear stack size for right recursive).
TokensR :: { [Token] }
TokensR	: TokensR Token	{ $2 : $1 }
	|		{ [] }

-- Parse single token.
Token :: { Token }
Token
    : 'let'	    { TokKeyword KwLet $1 }
    | 'in'	    { TokKeyword KwIn $1 }
    | 'where'	    { TokKeyword KwWhere $1 }
    | 'with'	    { TokKeyword KwWith $1 }
    | 'postulate'   { TokKeyword KwPostulate $1 }
    | 'primitive'   { TokKeyword KwPrimitive $1 }
    | 'open'	    { TokKeyword KwOpen $1 }
    | 'import'	    { TokKeyword KwImport $1 }
    | 'using'	    { TokKeyword KwUsing $1 }
    | 'hiding'	    { TokKeyword KwHiding $1 }
    | 'renaming'    { TokKeyword KwRenaming $1 }
    | 'to'	    { TokKeyword KwTo $1 }
    | 'public'	    { TokKeyword KwPublic $1 }
    | 'module'	    { TokKeyword KwModule $1 }
    | 'data'	    { TokKeyword KwData $1 }
    | 'codata'	    { TokKeyword KwCoData $1 }
    | 'record'	    { TokKeyword KwRecord $1 }
    | 'field'       { TokKeyword KwField $1 }
    | 'infix'	    { TokKeyword KwInfix $1 }
    | 'infixl'	    { TokKeyword KwInfixL $1 }
    | 'infixr'	    { TokKeyword KwInfixR $1 }
    | 'mutual'	    { TokKeyword KwMutual $1 }
    | 'abstract'    { TokKeyword KwAbstract $1 }
    | 'private'	    { TokKeyword KwPrivate $1 }
    | 'Prop'	    { TokKeyword KwProp $1 }
    | 'Set'	    { TokKeyword KwSet $1 }
    | 'forall'	    { TokKeyword KwForall $1 }
    | 'OPTIONS'	    { TokKeyword KwOPTIONS $1 }
    | 'BUILTIN'     { TokKeyword KwBUILTIN $1 }
    | 'IMPORT'      { TokKeyword KwIMPORT $1 }
    | 'COMPILED'    { TokKeyword KwCOMPILED $1 }
    | 'COMPILED_DATA'{ TokKeyword KwCOMPILED_DATA $1 }
    | 'COMPILED_TYPE'{ TokKeyword KwCOMPILED_TYPE $1 }
    | 'LINE'	    { TokKeyword KwLINE $1 }

    | setN	    { TokSetN $1 }
    | tex	    { TokTeX $1 }
    | comment	    { TokComment $1 }

    | '...'	    { TokSymbol SymEllipsis $1 }
    | '.'	    { TokSymbol SymDot $1 }
    | ';'	    { TokSymbol SymSemi $1 }
    | ':'	    { TokSymbol SymColon $1 }
    | '='	    { TokSymbol SymEqual $1 }
    | '~'	    { TokSymbol SymSim $1 }
    | '_'	    { TokSymbol SymUnderscore $1 }
    | '?'	    { TokSymbol SymQuestionMark $1 }
    | '->'	    { TokSymbol SymArrow $1 }
    | '\\'	    { TokSymbol SymLambda $1 }
    | '@'	    { TokSymbol SymAs $1 }
    | '|'	    { TokSymbol SymBar $1 }
    | '('	    { TokSymbol SymOpenParen $1 }
    | ')'	    { TokSymbol SymCloseParen $1 }
    | '{'	    { TokSymbol SymOpenBrace $1 }
    | '}'	    { TokSymbol SymCloseBrace $1 }
    | vopen	    { TokSymbol SymOpenVirtualBrace $1 }
    | vclose	    { TokSymbol SymCloseVirtualBrace $1 }
    | vsemi	    { TokSymbol SymVirtualSemi $1 }
    | '{-#'	    { TokSymbol SymOpenPragma $1 }
    | '#-}'	    { TokSymbol SymClosePragma $1 }

    | id	    { TokId $1 }
    | q_id	    { TokQId $1 }
    | string	    { TokString $1 }

    | literal	    { TokLiteral $1 }

{--------------------------------------------------------------------------
    TeX
 --------------------------------------------------------------------------}

TeX :: { () }
TeX : {- empty -} { () }
    | tex TeX	  { () }

{--------------------------------------------------------------------------
    Top level
 --------------------------------------------------------------------------}

File :: { ([Pragma], [Declaration]) }
File : File1 TeX  { $1 }

File1 : TopLevel		 { ([], $1) }
      | TeX TopLevelPragma File1 { let (ps,m) = $3 in ($2 : ps, m) }


{--------------------------------------------------------------------------
    Meta rules
 --------------------------------------------------------------------------}

-- The first token in a file decides the indentation of the top-level layout
-- block. Or not. It will if we allow the top-level module to be omitted.
-- topen :	{- empty -}	{% pushCurrentContext }


{-  A layout block might have to be closed by a parse error. Example:
	let x = e in e'
    Here the 'let' starts a layout block which should end before the 'in'.  The
    problem is that the lexer doesn't know this, so there is no virtual close
    brace. However when the parser sees the 'in' there will be a parse error.
    This is our cue to close the layout block.
-}
close : vclose  { () }
      | error	{% popContext }


-- You can use concrete semi colons in a layout block started with a virtual
-- brace, so we don't have to distinguish between the two semi colons. You can't
-- use a virtual semi colon in a block started by a concrete brace, but this is
-- simply because the lexer will not generate virtual semis in this case.
semi : ';'	  { $1 }
     | TeX vsemi  { $2 }


-- Enter the 'imp_dir' lex state, where we can parse the keywords 'using',
-- 'hiding', 'renaming' and 'to'.
beginImpDir :: { () }
beginImpDir : {- empty -}   {% pushLexState imp_dir }

{--------------------------------------------------------------------------
    Helper rules
 --------------------------------------------------------------------------}

-- An integer. Used in fixity declarations.
Int :: { Integer }
Int : literal	{% case $1 of {
		     LitInt _ n	-> return $ fromIntegral n;
		     _		-> fail $ "Expected integer"
		   }
		}


{--------------------------------------------------------------------------
    Names
 --------------------------------------------------------------------------}

-- A name is really a sequence of parts, but the lexer just sees it as a
-- string, so we have to do the translation here.
Id :: { Name }
Id : id	    {% mkName $1 }

-- Qualified operators are treated as identifiers, i.e. they have to be back
-- quoted to appear infix.
QId :: { QName }
QId : q_id  {% mkQName $1 }
    | Id    { QName $1 }


-- A module name is just a qualified name
ModuleName :: { QName }
ModuleName : QId { $1 }


-- A binding variable. Can be '_'
BId :: { Name }
BId : Id    { $1 }
    | '_'   { Name (getRange $1) [Hole] }


-- Space separated list of binding identifiers. Used in fixity
-- declarations infixl 100 + -
SpaceBIds :: { [Name] }
SpaceBIds
    : BId SpaceBIds { $1 : $2 }
    | BId	    { [$1] }

-- Comma separated list of binding identifiers. Used in dependent
-- function spaces: (x,y,z : Nat) -> ...
CommaBIds :: { [Name] }
CommaBIds : Application {%
    let getName (Ident (QName x)) = Just x
	getName (Underscore r _)  = Just (Name r [Hole])
	getName _		  = Nothing
    in
    case partition isJust $ map getName $1 of
	(good, []) -> return $ map fromJust good
	_	   -> fail $ "expected sequence of bound identifiers"
    }


-- Space separated list of strings in a pragma.
PragmaStrings :: { [String] }
PragmaStrings
    : {- empty -}	    { [] }
    | string PragmaStrings  { snd $1 : $2 }

PragmaName :: { QName }
PragmaName : string {% fmap QName (mkName $1) }

{--------------------------------------------------------------------------
    Expressions (terms and types)
 --------------------------------------------------------------------------}

{-  Expressions. You might expect lambdas and lets to appear in the first
    expression category (lowest precedence). The reason they don't is that we
    wan't to parse things like

	m >>= \x -> k x

    This will leads to a conflict in the following case

	m >>= \x -> k x >>= \y -> k' y

    At the second '>>=' we can either shift or reduce. We solve this problem
    using Happy's precedence directives. The rule 'Expr -> Expr1' (which is the
    rule you shouldn't use to reduce when seeing '>>=') is given LOWEST
    precedence.  The terminals '->' and op (which is what you should shift)
    is given higher precedence.
-}

-- Top level: Function types.
Expr :: { Expr }
Expr
    : TeleArrow Expr		{ Pi $1 $2 }
    | 'forall' LamBindings Expr	{ forallPi $2 $3 }
    | Application3 '->' Expr	{ Fun (fuseRange $1 $3) (RawApp (getRange $1) $1) $3 }
    | Expr1 %prec LOWEST	{ $1 }

-- Level 1: Application
Expr1  : WithExprs {% case $1 of
		      { [e]    -> return e
		      ; e : es -> return $ WithApp (fuseRange e es) e es
		      ; []     -> fail "impossible: empty with expressions"
		      }
		   }

WithExprs :: { [Expr] }
WithExprs
  : Application3 '|' WithExprs { RawApp (getRange $1) $1 :  $3 }
  | Application		       { [RawApp (getRange $1) $1] }

Application :: { [Expr] }
Application
    : Expr2		{ [$1] }
    | Expr3 Application { $1 : $2 }

-- Level 2: Lambdas and lets
Expr2
    : '\\' LamBindings Expr	   { Lam (fuseRange $1 $3) $2 $3 }
    | '\\' AbsurdLamBindings       { let (bs, h) = $2; r = fuseRange $1 bs in
                                     if null bs then AbsurdLam r h else
                                     Lam r bs (AbsurdLam r h)
                                   }
    | 'let' Declarations 'in' Expr { Let (fuseRange $1 $4) $2 $4 }
    | Expr3			   { $1 }

Application3 :: { [Expr] }
Application3
    : Expr3		 { [$1] }
    | Expr3 Application3 { $1 : $2 }

-- Level 3: Atoms
Expr3
    : QId				{ Ident $1 }
    | literal				{ Lit $1 }
    | '?'				{ QuestionMark (getRange $1) Nothing }
    | '_'				{ Underscore (getRange $1) Nothing }
    | 'Prop'				{ Prop (getRange $1) }
    | 'Set'				{ Set (getRange $1) }
    | setN				{ SetN (getRange (fst $1)) (snd $1) }
    | '{' Expr '}'			{ HiddenArg (fuseRange $1 $3) (unnamed $2) }
    | '{' Id '=' Expr '}'		{ HiddenArg (fuseRange $1 $5) (named (show $2) $4) }
    | '(' Expr ')'			{ Paren (fuseRange $1 $3) $2 }
    | '{' '}'				{ let r = fuseRange $1 $2 in HiddenArg r $ unnamed $ Absurd r }
    | '(' ')'				{ Absurd (fuseRange $1 $2) }
    | Id '@' Expr3			{ As (fuseRange $1 $3) $1 $3 }
    | '.' Expr3				{ Dot (fuseRange $1 $2) $2 }
    | 'record' '{' FieldAssignments '}' { Rec (getRange ($1,$4)) $3 }


FieldAssignments :: { [(Name, Expr)] }
FieldAssignments
  : {- empty -}	      { [] }
  | FieldAssignments1 { $1 }

FieldAssignments1 :: { [(Name, Expr)] }
FieldAssignments1
  : FieldAssignment			  { [$1] }
  | FieldAssignment ';' FieldAssignments1 { $1 : $3 }

FieldAssignment :: { (Name, Expr) }
FieldAssignment
  : Id '=' Expr	  { ($1, $3) }

{--------------------------------------------------------------------------
    Bindings
 --------------------------------------------------------------------------}

-- "Delta ->" to avoid conflict between Delta -> Gamma and Delta -> A.
TeleArrow : Telescope1 '->' { $1 }

Telescope1
    : TypedBindingss	{ {-TeleBind-} $1 }

TypedBindingss :: { [TypedBindings] }
TypedBindingss
    : TypedBindings TypedBindingss { $1 : $2 }
    | TypedBindings		   { [$1] }


-- A typed binding is either (x1,..,xn:A;..;y1,..,ym:B) or {x1,..,xn:A;..;y1,..,ym:B}.
TypedBindings :: { TypedBindings }
TypedBindings
    : '(' TBinds ')' { TypedBindings (fuseRange $1 $3) NotHidden $2 }
    | '{' TBinds '}' { TypedBindings (fuseRange $1 $3) Hidden    $2 }


-- A semicolon separated list of TypedBindings
TBinds :: { [TypedBinding] }
TBinds : TBind		   { [$1] }
       | TBind ';' TBinds2 { $1 : $3 }

TBinds2 :: { [TypedBinding] }
TBinds2 : TBinds	   { $1 }
	| Expr ';' TBinds2 { TNoBind $1 : $3 }
	| Expr		   { [TNoBind $1] }


-- x1,..,xn:A
TBind :: { TypedBinding }
TBind : CommaBIds ':' Expr  { TBind (fuseRange $1 $3) (map mkBoundName_ $1) $3 }


-- A non-empty sequence of lambda bindings.
LamBindings :: { [LamBinding] }
LamBindings
  : LamBinds '->' {%
      case last $1 of
        Left _  -> parseError "Absurd lambda cannot have a body."
        _       -> return [ b | Right b <- $1 ]
      }

AbsurdLamBindings :: { ([LamBinding], Hiding) }
AbsurdLamBindings
  : LamBinds {%
    case last $1 of
      Right _ -> parseError "Missing body for lambda"
      Left h  -> return ([ b | Right b <- init $1], h)
    }

LamBinds :: { [Either Hiding LamBinding] }
LamBinds
  : DomainFreeBinding LamBinds	{ map Right $1 ++ $2 }
  | TypedBindings LamBinds	{ Right (DomainFull $1) : $2 }
  | DomainFreeBinding		{ map Right $1 }
  | TypedBindings		{ [Right $ DomainFull $1] }
  | '(' ')'                     { [Left NotHidden] }
  | '{' '}'                     { [Left Hidden] }

-- A possibly empty sequence of lambda bindings.
LamBindings0 :: { [LamBinding] }
LamBindings0
  : DomainFreeBinding LamBindings0	{ $1 ++ $2 }
  | TypedBindings LamBindings0	        { DomainFull $1 : $2 }
  |             		        { [] }

-- A domain free binding is either x or {x1 .. xn}
DomainFreeBinding :: { [LamBinding] }
DomainFreeBinding
    : BId		{ [DomainFree NotHidden $ mkBoundName_ $1]  }
    | '{' CommaBIds '}' { map (DomainFree Hidden . mkBoundName_) $2 }


{--------------------------------------------------------------------------
    Modules and imports
 --------------------------------------------------------------------------}

-- You can rename imports
ImportImportDirective :: { (Maybe Name, ImportDirective) }
ImportImportDirective
    : ImportDirective	    { (Nothing, $1) }
    | id Id ImportDirective {% isName "as" $1 >> return (Just $2, $3) }

-- Import directives
ImportDirective :: { ImportDirective }
ImportDirective : ImportDirective1 {% verifyImportDirective $1 }

-- Can contain public
ImportDirective1 :: { ImportDirective }
ImportDirective1
    : 'public' ImportDirective2 { $2 { publicOpen = True } }
    | ImportDirective2	        { $1 }

ImportDirective2 :: { ImportDirective }
ImportDirective2
    : UsingOrHiding RenamingDir	{ ImportDirective (fuseRange $1 $2) $1 $2 False }
    | RenamingDir		{ ImportDirective (getRange $1) (Hiding []) $1 False }
    | UsingOrHiding		{ ImportDirective (getRange $1) $1 [] False }
    | {- empty -}		{ ImportDirective noRange (Hiding []) [] False }

UsingOrHiding :: { UsingOrHiding }
UsingOrHiding
    : 'using' '(' CommaImportNames ')'   { Using $3 }
	-- only using can have an empty list
    | 'hiding' '(' CommaImportNames1 ')' { Hiding $3 }

RenamingDir :: { [(ImportedName, Name)] }
RenamingDir
    : 'renaming' '(' Renamings ')'	{ $3 }

-- Renamings of the form 'x to y'
Renamings :: { [(ImportedName, Name)] }
Renamings
    : Renaming ';' Renamings	{ $1 : $3 }
    | Renaming			{ [$1] }

Renaming :: { (ImportedName, Name) }
Renaming
    : ImportName_ 'to' Id { ($1,$3) }

-- We need a special imported name here, since we have to trigger
-- the imp_dir state exactly one token before the 'to'
ImportName_ :: { ImportedName }
ImportName_
    : beginImpDir Id	      { ImportedName $2 }
    | 'module' beginImpDir Id { ImportedModule $3 }

ImportName :: { ImportedName }
ImportName : Id  	 { ImportedName $1 }
	   | 'module' Id { ImportedModule $2 }

CommaImportNames :: { [ImportedName] }
CommaImportNames
    : {- empty -}	{ [] }
    | CommaImportNames1	{ $1 }

CommaImportNames1
    : ImportName			{ [$1] }
    | ImportName ';' CommaImportNames1	{ $1 : $3 }

{--------------------------------------------------------------------------
    Function clauses
 --------------------------------------------------------------------------}

-- A left hand side of a function clause. We parse it as an expression, and
-- then check that it is a valid left hand side.
LHS :: { LHS }
LHS : Expr1 WithExpressions	     {% exprToLHS $1 >>= \p -> return (p $2) }
    | '...' WithPats WithExpressions { Ellipsis (fuseRange $1 $3) $2 $3 }

WithPats :: { [Pattern] }
WithPats : {- empty -}	{ [] }
	 | '|' Application3 WithPats
		{% exprToPattern (RawApp (getRange $2) $2) >>= \p ->
		   return (p : $3)
		}

WithExpressions :: { [Expr] }
WithExpressions
  : {- empty -}	{ [] }
  | 'with' Expr { case $2 of { WithApp _ e es -> e : es; e -> [e] } }

-- Where clauses are optional.
WhereClause :: { WhereClause }
WhereClause
    : {- empty -}		       { NoWhere	 }
    | 'where' Declarations	       { AnyWhere $2	 }
    | 'module' Id 'where' Declarations { SomeWhere $2 $4 }


{--------------------------------------------------------------------------
    Different kinds of declarations
 --------------------------------------------------------------------------}

-- Top-level defintions.
Declaration :: { [Declaration] }
Declaration
    : TypeSig	    { [$1] }
    | Fields        { $1   }
    | FunClause	    { [$1] }
    | Data	    { [$1] }
    | Record	    { [$1] }
    | Infix	    { [$1] }
    | Mutual	    { [$1] }
    | Abstract	    { [$1] }
    | Private	    { [$1] }
    | Postulate	    { [$1] }
    | Primitive	    { [$1] }
    | Open	    { [$1] }
    | Import	    { [$1] }
    | ModuleMacro   { [$1] }
    | Module	    { [$1] }
    | Pragma	    { [$1] }


{--------------------------------------------------------------------------
    Individual declarations
 --------------------------------------------------------------------------}

-- Type signatures can appear everywhere, so the type is completely polymorphic
-- in the indices.
TypeSig :: { Declaration }
TypeSig : Id ':' Expr   { TypeSig $1 $3 }


-- Function declarations. The left hand side is parsed as an expression to allow
-- declarations like 'x::xs ++ ys = e', when '::' has higher precedence than '++'.
FunClause :: { Declaration }
FunClause : LHS RHS WhereClause	{ FunClause $1 $2 $3 }

RHS :: { RHS }
RHS : '=' Expr	    { RHS Recursive $2 }
    | '~' Expr	    { RHS CoRecursive $2 }
    | {- empty -}   { AbsurdRHS }

-- Data declaration. Can be local.
Data :: { Declaration }
Data : 'data' Id LamBindings0 ':' Expr 'where'
	    Constructors	{ Data (getRange ($1, $6, $7)) Inductive $2 (map addType $3) $5 $7 }
     | 'codata' Id LamBindings0 ':' Expr 'where'
	    Constructors	{ Data (getRange ($1, $6, $7)) CoInductive $2 (map addType $3) $5 $7 }


-- Record declarations.
Record :: { Declaration }
Record : 'record' Id LamBindings0 ':' Expr 'where'
	    Declarations0 { Record (getRange ($1, $6, $7)) $2 (map addType $3) $5 $7 }


-- Fixity declarations.
Infix :: { Declaration }
Infix : 'infix'  Int SpaceBIds  { Infix (NonAssoc (fuseRange $1 $3) $2) $3 }
      | 'infixl' Int SpaceBIds  { Infix (LeftAssoc (fuseRange $1 $3) $2) $3 }
      | 'infixr' Int SpaceBIds  { Infix (RightAssoc (fuseRange $1 $3) $2) $3 }

-- Field declarations.
Fields :: { [Declaration] }
Fields : 'field' TypeSignatures { let toField (TypeSig x t) = Field x t in map toField $2 }

-- Mutually recursive declarations.
Mutual :: { Declaration }
Mutual : 'mutual' Declarations  { Mutual (fuseRange $1 $2) $2 }


-- Abstract declarations.
Abstract :: { Declaration }
Abstract : 'abstract' Declarations  { Abstract (fuseRange $1 $2) $2 }


-- Private can only appear on the top-level (or rather the module level).
Private :: { Declaration }
Private : 'private' Declarations	{ Private (fuseRange $1 $2) $2 }


-- Postulates. Can only contain type signatures. TODO: relax this.
Postulate :: { Declaration }
Postulate : 'postulate' TypeSignatures	{ Postulate (fuseRange $1 $2) $2 }


-- Primitives. Can only contain type signatures.
Primitive :: { Declaration }
Primitive : 'primitive' TypeSignatures	{ Primitive (fuseRange $1 $2) $2 }


-- Open
Open :: { Declaration }
Open : 'open' ModuleName OpenArgs ImportDirective {
    let
    { m   = $2
    ; es  = $3
    ; dir = $4
    ; r   = getRange ($1, m, dir)
    } in
    case es of
    { []  -> Open r m dir
    ; _   -> Private r [ ModuleMacro r (noName $ beginningOf $ getRange $2) []
                           (RawApp (fuseRange m es) (Ident m : es)) DoOpen dir
                       ]
    }
  }

OpenArgs :: { [Expr] }
OpenArgs : {- empty -}    { [] }
         | Expr3 OpenArgs { $1 : $2 }

-- Module instantiation
ModuleMacro :: { Declaration }
ModuleMacro : 'module' Id LamBindings0 '=' Expr ImportDirective
		    { ModuleMacro (getRange ($1, $5, $6)) $2 (map addType $3) $5 DontOpen $6 }
	    | 'open' 'module' Id LamBindings0 '=' Expr ImportDirective
		    { ModuleMacro (getRange ($1, $6, $7)) $3 (map addType $4) $6 DoOpen $7 }

-- Import
Import :: { Declaration }
Import : 'import' ModuleName ImportImportDirective
	    { Import (getRange ($1,$2,snd $3)) $2 (fst $3) DontOpen (snd $3) }
       | 'open' 'import' ModuleName ImportImportDirective
	    { Import (getRange ($1,$3,snd $4)) $3 (fst $4) DoOpen (snd $4) }

-- Module
Module :: { Declaration }
Module : 'module' Id LamBindings0 'where' Declarations0
		    { Module (getRange ($1,$4,$5)) (QName $2) (map addType $3) $5 }

-- The top-level consist of a bunch of import and open followed by a top-level module.
TopLevel :: { [Declaration] }
TopLevel : TeX TopModule       { [$2] }
	 | TeX Import TopLevel { $2 : $3 }
	 | TeX Open   TopLevel { $2 : $3 }

-- The top-level module can have a qualified name.
TopModule :: { Declaration }
TopModule : 'module' ModuleName LamBindings0 'where' Declarations0
		    { Module (getRange ($1,$4,$5)) $2 (map addType $3) $5 }

Pragma :: { Declaration }
Pragma : DeclarationPragma  { Pragma $1 }

TopLevelPragma :: { Pragma }
TopLevelPragma
  : OptionsPragma { $1 }
  | LinePragma	  { $1 }

DeclarationPragma :: { Pragma }
DeclarationPragma
  : BuiltinPragma      { $1 }
  | LinePragma	       { $1 }
  | CompiledPragma     { $1 }
  | CompiledDataPragma { $1 }
  | CompiledTypePragma { $1 }
  | ImportPragma       { $1 }

OptionsPragma :: { Pragma }
OptionsPragma : '{-#' 'OPTIONS' PragmaStrings '#-}' { OptionsPragma (fuseRange $1 $4) $3 }

BuiltinPragma :: { Pragma }
BuiltinPragma
    : '{-#' 'BUILTIN' string PragmaName '#-}'
      { BuiltinPragma (fuseRange $1 $5) (snd $3) (Ident $4) }

CompiledPragma :: { Pragma }
CompiledPragma
  : '{-#' 'COMPILED' PragmaName PragmaStrings '#-}'
    { CompiledPragma (fuseRange $1 $5) $3 (unwords $4) }

CompiledTypePragma :: { Pragma }
CompiledTypePragma
  : '{-#' 'COMPILED_TYPE' PragmaName PragmaStrings '#-}'
    { CompiledTypePragma (fuseRange $1 $5) $3 (unwords $4) }

CompiledDataPragma :: { Pragma }
CompiledDataPragma
  : '{-#' 'COMPILED_DATA' PragmaName string PragmaStrings '#-}'
    { CompiledDataPragma (fuseRange $1 $6) $3 (snd $4) $5 }

ImportPragma :: { Pragma }
ImportPragma
  : '{-#' 'IMPORT' PragmaStrings '#-}'
    { ImportPragma (fuseRange $1 $4) (unwords $3) }

-- TODO: When a line pragma is encountered the line and column numbers
-- are updated, but the linear position is preserved. Is this what we
-- want?

LinePragma :: { Pragma }
LinePragma
    : '{-#' 'LINE' string string '#-}' {% do
      let r = fuseRange $1 $5
	  parseFile (i, f)
	    | head f == '"' && last f == '"'  = return $ init (tail f)
	    | otherwise	= parseErrorAt (iStart i) $ "Expected \"filename\", found " ++ f
	  parseLine (i, l)
	    | all isDigit l = return $ read l
	    | otherwise	    = parseErrorAt (iStart i) $ "Expected line number, found " ++ l
      line <- parseLine $3
      file <- parseFile $4
      currentPos <- fmap parsePos get
      setParsePos $ Pn
	{ srcFile = file
	, posPos  = posPos currentPos
	, posLine = line
	, posCol  = 1
	}
      return $ LinePragma r line file
    }

{--------------------------------------------------------------------------
    Sequences of declarations
 --------------------------------------------------------------------------}

-- Non-empty list of type signatures. Used in postulates.
TypeSignatures :: { [TypeSignature] }
TypeSignatures
    : TeX vopen TypeSignatures1 TeX close   { reverse $3 }

-- Inside the layout block.
TypeSignatures1 :: { [TypeSignature] }
TypeSignatures1
    : TypeSignatures1 semi TeX TypeSig  { $4 : $1 }
    | TeX TypeSig			{ [$2] }

-- Constructors are type signatures. But constructor lists can be empty.
Constructors :: { [Constructor] }
Constructors
    : TypeSignatures	  { $1 }
    | TeX vopen TeX close { [] }

-- Arbitrary declarations
Declarations :: { [Declaration] }
Declarations
    : TeX vopen Declarations1 TeX close { reverse $3 }

-- Arbitrary declarations
Declarations0 :: { [Declaration] }
Declarations0
    : TeX vopen TeX close  { [] }
    | Declarations { $1 }

Declarations1 :: { [Declaration] }
Declarations1
    : Declarations1 semi TeX Declaration { reverse $4 ++ $1 }
    | TeX Declaration			 { reverse $2 }


{

{--------------------------------------------------------------------------
    Parsers
 --------------------------------------------------------------------------}

-- | Parse the token stream. Used by the TeX compiler.
tokensParser :: Parser [Token]

-- | Parse an expression. Could be used in interactions.
exprParser :: Parser Expr

-- | Parse a module.
moduleParser :: Parser ([Pragma], [Declaration])


{--------------------------------------------------------------------------
    Happy stuff
 --------------------------------------------------------------------------}

-- | Required by Happy.
happyError :: Parser a
happyError = parseError "Parse error"


{--------------------------------------------------------------------------
    Utility functions
 --------------------------------------------------------------------------}

-- | Create a name from a string.

mkName :: (Interval, String) -> Parser Name
mkName (i, s) = do
    let xs = parts s
    mapM_ isValidId xs
    unless (alternating xs) $ fail $ "a name cannot contain two consecutive underscores"
    return $ Name (getRange i) xs
    where
        parts :: String -> [NamePart]
        parts ""        = []
        parts ('_' : s) = Hole : parts s
        parts s         = Id x : parts s'
          where (x, s') = break (== '_') s

	isValidId Hole   = return ()
	isValidId (Id x) = case parse defaultParseFlags [0] (lexer return) x of
	    ParseOk _ (TokId _) -> return ()
	    _			-> fail $ "in the name " ++ s ++ ", the part " ++ x ++ " is not valid"

	-- we know that there aren't two Ids in a row
	alternating (Hole : Hole : _) = False
	alternating (_ : xs)	      = alternating xs
	alternating []		      = True

-- | Create a qualified name from a list of strings
mkQName :: [(Interval, String)] -> Parser QName
mkQName ss = do
    xs <- mapM mkName ss
    return $ foldr Qual (QName $ last xs) (init xs)

-- | Match a particular name.
isName :: String -> (Interval, String) -> Parser ()
isName s (_,s')
    | s == s'	= return ()
    | otherwise	= fail $ "expected " ++ s ++ ", found " ++ s'

-- | Build a forall pi (forall x y z -> ...)
forallPi :: [LamBinding] -> Expr -> Expr
forallPi bs e = Pi (map addType bs) e

-- | Converts lambda bindings to typed bindings.
addType :: LamBinding -> TypedBindings
addType (DomainFull b)	 = b
addType (DomainFree h x) = TypedBindings r h [TBind r [x] $ Underscore r Nothing]
  where r = getRange x

-- | Check that an import directive doesn't contain repeated names
verifyImportDirective :: ImportDirective -> Parser ImportDirective
verifyImportDirective i =
    case filter ((>1) . length)
	 $ group
	 $ sort xs
    of
	[]  -> return i
	yss -> let Just pos = rStart $ getRange $ head $ concat yss in
               parseErrorAt pos $
		"repeated name" ++ s ++ " in import directive: " ++
		concat (intersperse ", " $ map (show . head) yss)
	    where
		s = case yss of
			[_] -> ""
			_   -> "s"
    where
	xs = names (usingOrHiding i) ++ map fst (renaming i)
	names (Using xs)    = xs
	names (Hiding xs)   = xs

{--------------------------------------------------------------------------
    Patterns
 --------------------------------------------------------------------------}

-- | Turn an expression into a left hand side.
exprToLHS :: Expr -> Parser ([Expr] -> LHS)
exprToLHS e = case e of
  WithApp r e es -> LHS <$> exprToPattern e <*> mapM exprToPattern es
  _		 -> LHS <$> exprToPattern e <*> return []

-- | Turn an expression into a pattern. Fails if the expression is not a
--   valid pattern.
exprToPattern :: Expr -> Parser Pattern
exprToPattern e =
    case e of
	Ident x			-> return $ IdentP x
	App _ e1 e2		-> AppP <$> exprToPattern e1
					<*> T.mapM (T.mapM exprToPattern) e2
	Paren r e		-> ParenP r
					<$> exprToPattern e
	Underscore r _		-> return $ WildP r
	Absurd r		-> return $ AbsurdP r
	As r x e		-> AsP r x <$> exprToPattern e
	Dot r (HiddenArg _ e)	-> return $ HiddenP r $ fmap (DotP r) e
	Dot r e			-> return $ DotP r e
	Lit l			-> return $ LitP l
	HiddenArg r e		-> HiddenP r <$> T.mapM exprToPattern e
	RawApp r es		-> RawAppP r <$> mapM exprToPattern es
	OpApp r x es		-> OpAppP r x <$> mapM exprToPattern es
	_			->
          let Just pos = rStart $ getRange e in
          parseErrorAt pos $ "Not a valid pattern: " ++ show e

}
