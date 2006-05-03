{
{-# OPTIONS -fno-warn-incomplete-patterns #-}
{-| The parser is generated by Happy (<http://www.haskell.org/happy>).
-}
module Syntax.Parser.Parser (
      moduleParser
    , exprParser
    , tokensParser
    , interfaceParser
    ) where

import Data.List

import Syntax.Position
import Syntax.Parser.Monad
import Syntax.Parser.Lexer
import Syntax.Parser.Tokens
import Syntax.Concrete
import Syntax.Concrete.Name
import Syntax.Interface
import Syntax.Common
import Syntax.Fixity
import Syntax.Literal
import qualified Syntax.Abstract.Name as A

import Utils.Monad

}

%name tokensParser Tokens
%name exprParser Expr
%name moduleParser File
%name interfaceParser Interface
%tokentype { Token }
%monad { Parser }
%lexer { lexer } { TokEOF }

-- This is a trick to get rid of shift/reduce conflicts arising because we want
-- to parse things like "m >>= \x -> k x". See the Expr rule for more
-- information.
%nonassoc LOWEST
%nonassoc '`' '->' op

%token
    'let'	{ TokKeyword KwLet $$ }
    'in'	{ TokKeyword KwIn $$ }
    'where'	{ TokKeyword KwWhere $$ }
    'postulate' { TokKeyword KwPostulate $$ }
    'open'	{ TokKeyword KwOpen $$ }
    'import'	{ TokKeyword KwImport $$ }
    'using'	{ TokKeyword KwUsing $$ }
    'hiding'	{ TokKeyword KwHiding $$ }
    'renaming'	{ TokKeyword KwRenaming $$ }
    'to'	{ TokKeyword KwTo $$ }
    'module'	{ TokKeyword KwModule $$ }
    'data'	{ TokKeyword KwData $$ }
    'infix'	{ TokKeyword KwInfix $$ }
    'infixl'	{ TokKeyword KwInfixL $$ }
    'infixr'	{ TokKeyword KwInfixR $$ }
    'mutual'	{ TokKeyword KwMutual $$ }
    'abstract'	{ TokKeyword KwAbstract $$ }
    'private'	{ TokKeyword KwPrivate $$ }
    'Prop'	{ TokKeyword KwProp $$ }
    'Set'	{ TokKeyword KwSet $$ }

    setN	{ TokSetN $$ }
    tex		{ TokTeX $$ }

    '.'		{ TokSymbol SymDot $$ }
    ','		{ TokSymbol SymComma $$ }
    ';'		{ TokSymbol SymSemi $$ }
    '`'		{ TokSymbol SymBackQuote $$ }
    ':'		{ TokSymbol SymColon $$ }
    '='		{ TokSymbol SymEqual $$ }
    '_'		{ TokSymbol SymUnderscore $$ }
    '?'		{ TokSymbol SymQuestionMark $$ }
    '->'	{ TokSymbol SymArrow $$ }
    '\\'	{ TokSymbol SymLambda $$ }
    '('		{ TokSymbol SymOpenParen $$ }
    ')'		{ TokSymbol SymCloseParen $$ }
    '['		{ TokSymbol SymOpenBracket $$ }
    ']'		{ TokSymbol SymCloseBracket $$ }
    '{'		{ TokSymbol SymOpenBrace $$ }
    '}'		{ TokSymbol SymCloseBrace $$ }
    vopen	{ TokSymbol SymOpenVirtualBrace $$ }
    vclose	{ TokSymbol SymCloseVirtualBrace $$ }
    vsemi	{ TokSymbol SymVirtualSemi $$ }

    id		{ TokId $$ }
    op		{ TokOp $$ }
    q_id	{ TokQId $$ }
    q_op	{ TokQOp $$ }

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
    | 'postulate'   { TokKeyword KwPostulate $1 }
    | 'open'	    { TokKeyword KwOpen $1 }
    | 'import'	    { TokKeyword KwImport $1 }
    | 'using'	    { TokKeyword KwUsing $1 }
    | 'hiding'	    { TokKeyword KwHiding $1 }
    | 'renaming'    { TokKeyword KwRenaming $1 }
    | 'to'	    { TokKeyword KwTo $1 }
    | 'module'	    { TokKeyword KwModule $1 }
    | 'data'	    { TokKeyword KwData $1 }
    | 'infix'	    { TokKeyword KwInfix $1 }
    | 'infixl'	    { TokKeyword KwInfixL $1 }
    | 'infixr'	    { TokKeyword KwInfixR $1 }
    | 'mutual'	    { TokKeyword KwMutual $1 }
    | 'abstract'    { TokKeyword KwAbstract $1 }
    | 'private'	    { TokKeyword KwPrivate $1 }
    | 'Prop'	    { TokKeyword KwProp $1 }
    | 'Set'	    { TokKeyword KwSet $1 }

    | setN	    { TokSetN $1 }
    | tex	    { TokTeX $1 }

    | '.'	    { TokSymbol SymDot $1 }
    | ','	    { TokSymbol SymComma $1 }
    | ';'	    { TokSymbol SymSemi $1 }
    | '`'	    { TokSymbol SymBackQuote $1 }
    | ':'	    { TokSymbol SymColon $1 }
    | '='	    { TokSymbol SymEqual $1 }
    | '_'	    { TokSymbol SymUnderscore $1 }
    | '?'	    { TokSymbol SymQuestionMark $1 }
    | '->'	    { TokSymbol SymArrow $1 }
    | '\\'	    { TokSymbol SymLambda $1 }
    | '('	    { TokSymbol SymOpenParen $1 }
    | ')'	    { TokSymbol SymCloseParen $1 }
    | '['	    { TokSymbol SymOpenBracket $1 }
    | ']'	    { TokSymbol SymCloseBracket $1 }
    | '{'	    { TokSymbol SymOpenBrace $1 }
    | '}'	    { TokSymbol SymCloseBrace $1 }
    | vopen	    { TokSymbol SymOpenVirtualBrace $1 }
    | vclose	    { TokSymbol SymCloseVirtualBrace $1 }
    | vsemi	    { TokSymbol SymVirtualSemi $1 }

    | id	    { TokId $1 }
    | op	    { TokOp $1 }
    | q_id	    { TokQId $1 }
    | q_op	    { TokQOp $1 }

    | literal	    { TokLiteral $1 }

{--------------------------------------------------------------------------
    Top level
 --------------------------------------------------------------------------}

File :: { TopLevelDeclaration }
File : TopModule	{ $1 }
     | tex File		{ $2 }


{--------------------------------------------------------------------------
    Interface files
 --------------------------------------------------------------------------}

Interface :: { Interface }
Interface
    : 'module' ModuleName Slash Int 'where'
      vopen
	functions ':' CommaNamesWithFixities vsemi
	constructors ':' CommaNamesWithFixities
	Interfaces
      close
			{ Interface { moduleName	= A.mkModuleName $2
				    , arity		= $4
				    , definedNames	= $9
				    , constructorNames	= $13
				    , subModules	= $14
				    }
			}

Interfaces :: { [Interface] }
Interfaces : {- empty -}		{ [] }
	   | vsemi Interface Interfaces { $2 : $3 }

AbsName :: { A.Name }
AbsName : Name At Int	   { A.Name (A.NameId $3) $1 }

AbsNameWithFixity :: { (A.Name, Fixity) }
AbsNameWithFixity
    : AbsName		   { ($1, defaultFixity) }
    | 'infix'  Int AbsName { ($3, NonAssoc (fuseRange $1 $3) $2) }
    | 'infixl' Int AbsName { ($3, LeftAssoc (fuseRange $1 $3) $2) }
    | 'infixr' Int AbsName { ($3, RightAssoc (fuseRange $1 $3) $2) }

CommaNamesWithFixities
    : {- empty -}		{ [] }
    | CommaNamesWithFixities1	{ $1 }

CommaNamesWithFixities1
    : AbsNameWithFixity				    { [$1] }
    | AbsNameWithFixity ',' CommaNamesWithFixities1 { $1 : $3 }

Slash	     : op {% isName "/" $1 }
At	     : op {% isName "@" $1 }
functions    : id {% isName "functions" $1 }
constructors : id {% isName "constructors" $1 }

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
close : vclose	{ () }
      | error	{% popContext }


-- You can use concrete semi colons in a layout block started with a virtual
-- brace, so we don't have to distinguish between the two semi colons. You can't
-- use a virtual semi colon in a block started by a concrete brace, but this is
-- simply because the lexer will not generate virtual semis in this case.
semi : ';'	{ $1 }
     | vsemi	{ $1 }


-- Enter the 'imp_dir' lex state, where we can parse the keywords 'using',
-- 'hiding', 'renaming' and 'to'.
beginImpDir :: { () }
beginImpDir : {- empty -}   {% pushLexState imp_dir }

{--------------------------------------------------------------------------
    Helper rules
 --------------------------------------------------------------------------}

-- An integer. Used in fixity declarations.
Int :: { Int }
Int : literal	{% case $1 of {
		     LitInt _ n	-> return $ fromIntegral n;
		     _		-> fail $ "Expected integer"
		   }
		}


{--------------------------------------------------------------------------
    Names
 --------------------------------------------------------------------------}

-- Unqualifed identifiers. This is something that could appear in a binding
-- position.
Id :: { Name }
Id  : id	    { $1 }
    | '(' op ')'    { $2 }


-- Unqualified operators. Used in left hand sides.
Op :: { Name }
Op : op		{ $1 }
   | '`' id '`'	{ $2 }

-- Qualified operators are treated as identifiers, i.e. they have to be back
-- quoted to appear infix.
QId :: { QName }
QId : q_id	    { $1 }
    | q_op	    { $1 }
    | Id	    { QName $1 }


-- Qualified identifier which isn't an operator
ModuleName :: { QName }
ModuleName
    : q_id  { $1 }
    | id    { QName $1 }

-- Infix operator. All names except unqualified operators have to be back
-- quoted.
QOp :: { QName }
QOp : Op	    { QName $1 }
    | '`' q_id '`'  { $2 }
    | '`' q_op '`'  { $2 }


-- A binding variable. Can be '_'
BId :: { Name }
BId : Id    { $1 }
    | '_'   { NoName $1 }

-- An unqualified name (identifier or operator). This is what you write in
-- import lists.
Name :: { Name }
Name : id   { $1 }
     | op   { $1 }

-- Comma separated list of binding identifiers. Used in dependent
-- function spaces: (x,y,z : Nat) -> ...
CommaBIds :: { [Name] }
CommaBIds
    : BId ',' CommaBIds	{ $1 : $3 }
    | BId		{ [$1] }


-- Comma separated list of operators. Used in infix declarations.
CommaOps :: { [Name] }
CommaOps
    : Op ',' CommaOps	{ $1 : $3 }
    | Op		{ [$1] }

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
    precedence.  The terminals '`' '->' and op (which is what you should shift)
    is given higher precedence.
-}

-- Top level: Function types.
Expr :: { Expr }
Expr
    : TypedBinding '->' Expr	{ Pi $1 $3 }
    | '{' Expr '}' '->' Expr	{ Fun (fuseRange $1 $5) Hidden $2 $5 }
    | Expr1 '->' Expr		{ Fun (fuseRange $1 $3) NotHidden $1 $3 }
    | Expr1 %prec LOWEST	{ $1 }

-- Level 1: Infix operators
Expr1
    : Expr1 QOp Expr2		{ InfixApp $1 $2 $3 }
    | Expr2			{ $1 }

-- Level 2: Lambdas and lets
Expr2
    : '\\' LamBindings '->' Expr	{ Lam (fuseRange $1 $4) $2 $4 }
    | 'let' LocalDeclarations 'in' Expr	{ Let (fuseRange $1 $4) $2 $4 }
    | Expr3				{ $1 }

-- Level 3: Application
Expr3
    : Expr3 Expr4	    { App (fuseRange $1 $2) NotHidden $1 $2 }
    | Expr3 '{' Expr '}'    { App (fuseRange $1 $4) Hidden $1 $3 }
    | Expr4		    { $1 }

-- Level 4: Atoms
Expr4
    : QId		{ Ident $1 }
    | literal		{ Lit $1 }
    | '?'		{ QuestionMark $1 }
    | '_'		{ Underscore $1 }
    | 'Prop'		{ Prop $1 }
    | 'Set'		{ Set $1 }
    | setN		{ uncurry SetN $1 }
    | '(' Expr ')'	{ Paren (fuseRange $1 $3) $2 }


-- Sorts
Sort :: { Expr }
Sort : 'Prop'		{ Prop $1 }
     | 'Set'		{ Set $1 }
     | setN		{ uncurry SetN $1 }


{--------------------------------------------------------------------------
    Bindings
 --------------------------------------------------------------------------}

-- A telescope is a non-empty sequence of typed bindings.
Telescope :: { Telescope }
Telescope
    : TypedBinding Telescope	{ $1 : $2 }
    | TypedBinding		{ [$1] }


-- A typed binding is either (x1,..,xn:A) or {x1,..,xn:A}.
TypedBinding :: { TypedBinding }
TypedBinding
    : '(' CommaBIds ':' Expr ')'
			    { TypedBinding (fuseRange $1 $5) NotHidden $2 $4 }
    | '{' CommaBIds ':' Expr '}'
			    { TypedBinding (fuseRange $1 $5) Hidden $2 $4 }


-- A non-empty sequence of lambda bindings. For purely aestethical reasons we
-- disallow mixing typed and untyped bindings in lambdas.
LamBindings :: { [LamBinding] }
LamBindings
    : Telescope		    { map DomainFull $1 }
    | DomainFreeBindings    { $1 }


-- A non-empty sequence of domain-free bindings
DomainFreeBindings :: { [LamBinding] }
DomainFreeBindings
    : DomainFreeBinding DomainFreeBindings  { $1 : $2 }
    | DomainFreeBinding			    { [$1] }


-- A domain free binding is either x or {x}
DomainFreeBinding :: { LamBinding }
DomainFreeBinding
    : BId	    { DomainFree NotHidden $1 }
    | '{' BId '}'   { DomainFree Hidden $2 }


MaybeTelescope :: { Telescope }
MaybeTelescope : {- empty -}	{ [] }
	       | Telescope	{ $1 }


{--------------------------------------------------------------------------
    Modules and imports
 --------------------------------------------------------------------------}

-- You can rename imports
RenamedImport :: { Maybe Name }
RenamedImport : {- empty -} { Nothing }
	      | id id	    {% isName "as" $1 >> return (Just $2) }

-- Import directives
ImportDirective :: { ImportDirective }
ImportDirective : ImportDirective_ {% verifyImportDirective $1 }

ImportDirective_ :: { ImportDirective }
ImportDirective_
    : UsingOrHiding RenamingDir	{ ImportDirective (fuseRange $1 $2) $1 $2 }
    | RenamingDir		{ ImportDirective (getRange $1) (Hiding []) $1 }
    | UsingOrHiding		{ ImportDirective (getRange $1) $1 [] }
    | {- empty -}		{ ImportDirective noRange (Hiding []) [] }

UsingOrHiding :: { UsingOrHiding }
UsingOrHiding
    : beginImpDir ',' 'using' '(' CommaImportNames ')'   { Using $5 }
	-- only using can have an empty list
    | beginImpDir ',' 'hiding' '(' CommaImportNames1 ')' { Hiding $5 }

RenamingDir :: { [(ImportedName, Name)] }
RenamingDir
    : beginImpDir ',' 'renaming' '(' Renamings ')'	{ $5 }

-- Renamings of the form 'x to y'
Renamings :: { [(ImportedName,Name)] }
Renamings
    : Renaming ',' Renamings	{ $1 : $3 }
    | Renaming			{ [$1] }

Renaming :: { (ImportedName, Name) }
Renaming
    : ImportName_ 'to' Name	{ ($1,$3) }

-- We need a special imported name here, since we have to trigger
-- the imp_dir state exactly one token before the 'to'
ImportName_ :: { ImportedName }
ImportName_
    : beginImpDir Name		{ ImportedName $2 }
    | 'module' beginImpDir Name	{ ImportedModule $3 }

ImportName :: { ImportedName }
ImportName : Name	    { ImportedName $1 }
	   | 'module' Name  { ImportedModule $2 }

CommaImportNames :: { [ImportedName] }
CommaImportNames
    : {- empty -}	{ [] }
    | CommaImportNames1	{ $1 }

CommaImportNames1
    : ImportName			{ [$1] }
    | ImportName ',' CommaImportNames1	{ $1 : $3 }

{--------------------------------------------------------------------------
    Function clauses
 --------------------------------------------------------------------------}

-- A left hand side of a function clause. We parse it as an expression, and
-- then check that it is a valid left hand side.
LHS :: { LHS }
LHS : Expr  {% exprToLHS $1 }

-- Where clauses are optional.
WhereClause :: { WhereClause }
WhereClause
    : {- empty -}		{ [] }
    | 'where' LocalDeclarations	{ $2 }


{--------------------------------------------------------------------------
    Different kinds of declarations
 --------------------------------------------------------------------------}

-- Local declarations.
LocalDeclaration :: { LocalDeclaration }
LocalDeclaration
    : TypeSig	    { $1 }
    | FunClause	    { $1 }
    | Data	    { $1 }
    | Infix	    { $1 }
    | Mutual	    { $1 }
    | Abstract	    { $1 }
    | Open	    { $1 }
    | ModuleMacro   { $1 }
    | Module	    { $1 }  -- why not have local modules?

-- Declarations that can appear in a private block.
PrivateDeclaration :: { PrivateDeclaration }
PrivateDeclaration
    : TypeSig	    { $1 }
    | FunClause	    { $1 }
    | Data	    { $1 }
    | Infix	    { $1 }
    | Mutual	    { $1 }
    | Abstract	    { $1 }
    | Postulate	    { $1 }
    | Private	    { $1 }  -- we allow private inside private because we can,
			    -- and because generated code might want to use it
			    -- to simplify things
    | Open	    { $1 }
    | ModuleMacro   { $1 }
    | Module	    { $1 }


-- Declarations that can appear in a mutual block.
MutualDeclaration :: { MutualDeclaration }
MutualDeclaration
    : TypeSig	{ $1 }
    | FunClause { $1 }
    | Data	{ $1 }
    | Infix	{ $1 }
    | Private	{ $1 }


-- Declarations that can appear in an abstract block.
AbstractDeclaration :: { AbstractDeclaration }
AbstractDeclaration
    : TypeSig	    { $1 }
    | FunClause	    { $1 }
    | Data	    { $1 }
    | Infix	    { $1 }
    | Abstract	    { $1 }
    | Mutual	    { $1 }
    | Private	    { $1 }
    | Open	    { $1 }


-- Top-level defintions.
TopLevelDeclaration :: { TopLevelDeclaration }
TopLevelDeclaration
    : TypeSig	    { $1 }
    | FunClause	    { $1 }
    | Data	    { $1 }
    | Infix	    { $1 }
    | Mutual	    { $1 }
    | Abstract	    { $1 }
    | Private	    { $1 }
    | Postulate	    { $1 }
    | Open	    { $1 }
    | Import	    { $1 }
    | ModuleMacro   { $1 }
    | Module	    { $1 }


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
FunClause : LHS '=' Expr WhereClause	{ FunClause $1 $3 $4 }


-- Data declaration. Can be local.
Data :: { Declaration }
Data : 'data' Id MaybeTelescope ':' Sort 'where'
	    Constructors	{ Data (getRange ($1, $6, $7)) $2 $3 $5 $7 }


-- Fixity declarations.
Infix :: { Declaration }
Infix : 'infix' Int CommaOps	{ Infix (NonAssoc (fuseRange $1 $3) $2) $3 }
      | 'infixl' Int CommaOps	{ Infix (LeftAssoc (fuseRange $1 $3) $2) $3 }
      | 'infixr' Int CommaOps	{ Infix (RightAssoc (fuseRange $1 $3) $2) $3 }


-- Mutually recursive declarations.
Mutual :: { Declaration }
Mutual : 'mutual' MutualDeclarations  { Mutual (fuseRange $1 $2) $2 }


-- Abstract declarations.
Abstract :: { Declaration }
Abstract : 'abstract' AbstractDeclarations  { Abstract (fuseRange $1 $2) $2 }


-- Private can only appear on the top-level (or rather the module level).
Private :: { Declaration }
Private : 'private' PrivateDeclarations	{ Private (fuseRange $1 $2) $2 }


-- Postulates. Only on top-level or in a private block.
-- NOTE: Does it make sense to allow private postulates?
Postulate :: { Declaration }
Postulate : 'postulate' TypeSignatures	{ Postulate (fuseRange $1 $2) $2 }


-- Open
Open :: { Declaration }
Open : 'open' ModuleName ImportDirective   { Open (getRange ($1,$2,$3)) $2 $3 }


-- ModuleMacro
ModuleMacro :: { Declaration }
ModuleMacro : 'module' id MaybeTelescope '=' Expr ImportDirective
		    { ModuleMacro (getRange ($1, $5, $6)) $2 $3 $5 $6 }


-- Import
Import :: { Declaration }
Import : 'import' ModuleName RenamedImport ImportDirective
	    { Import (getRange ($1,$2,$4)) $2 $3 $4 }

-- Module
Module :: { Declaration }
Module : 'module' id MaybeTelescope 'where' TopLevelDeclarations
		    { Module (getRange ($1,$4,$5)) (QName $2) $3 $5 }

-- The top-level module can have a qualified name.
TopModule :: { Declaration }
TopModule : 'module' ModuleName MaybeTelescope 'where' TopLevelDeclarations
		    { Module (getRange ($1,$4,$5)) $2 $3 $5 }

{--------------------------------------------------------------------------
    Sequences of declarations
 --------------------------------------------------------------------------}

-- Non-empty list of type signatures. Used in postulates.
TypeSignatures :: { [TypeSignature] }
TypeSignatures
    : '{' TypeSignatures1 '}'	    { reverse $2 }
    | vopen TypeSignatures1 close   { reverse $2 }

-- Inside the layout block.
TypeSignatures1 :: { [TypeSignature] }
TypeSignatures1
    : TypeSignatures1 semi TypeSig  { $3 : $1 }
    | TypeSig			    { [$1] }

-- Constructors are type signatures. But constructor lists can be empty.
Constructors :: { [Constructor] }
Constructors
    : TypeSignatures		    { $1 }
    | '{' '}'			    { [] }
    | vopen close		    { [] }


-- Sequences of local declarations are controlled by layout.  To improve Happy
-- performance we parse the lists left recursively, which means we have to
-- reverse the list in the end.
LocalDeclarations :: { [LocalDeclaration] }
LocalDeclarations
    : '{' LocalDeclarations1 '}'	    { reverse $2 }
    | vopen LocalDeclarations1 close { reverse $2 }


-- Inside the layout block. Declaration lists have to be non-empty.
LocalDeclarations1 :: { [LocalDeclaration] }
LocalDeclarations1
    : LocalDeclarations1 semi LocalDeclaration	{ $3 : $1 }
    | LocalDeclaration				{ [$1] }


-- Private declarations
PrivateDeclarations :: { [PrivateDeclaration] }
PrivateDeclarations
    : '{' PrivateDeclarations1 '}'	    { reverse $2 }
    | vopen PrivateDeclarations1 close { reverse $2 }

PrivateDeclarations1 :: { [PrivateDeclaration] }
PrivateDeclarations1
    : PrivateDeclarations1 semi PrivateDeclaration	{ $3 : $1 }
    | PrivateDeclaration				{ [$1] }


-- Mutual declarations
MutualDeclarations :: { [MutualDeclaration] }
MutualDeclarations
    : '{' MutualDeclarations1 '}'	{ reverse $2 }
    | vopen MutualDeclarations1 close	{ reverse $2 }

MutualDeclarations1 :: { [MutualDeclaration] }
MutualDeclarations1
    : MutualDeclarations1 semi MutualDeclaration    { $3 : $1 }
    | MutualDeclaration				    { [$1] }


-- Abstract declarations
AbstractDeclarations :: { [AbstractDeclaration] }
AbstractDeclarations
    : '{' AbstractDeclarations1 '}'	{ reverse $2 }
    | vopen AbstractDeclarations1 close { reverse $2 }

AbstractDeclarations1 :: { [AbstractDeclaration] }
AbstractDeclarations1
    : AbstractDeclarations1 semi AbstractDeclaration	{ $3 : $1 }
    | AbstractDeclaration				{ [$1] }


-- Top-level declarations
TopLevelDeclarations :: { [TopLevelDeclaration] }
TopLevelDeclarations
    : '{' TopLevelDeclarations1 '}'	{ reverse $2 }
    | vopen TopLevelDeclarations1 close { reverse $2 }

TopLevelDeclarations1 :: { [TopLevelDeclaration] }
TopLevelDeclarations1
    : TopLevelDeclarations1 semi TopLevelDeclaration	{ $3 : $1 }
    | TopLevelDeclarations1 tex				{ $1 }
    | TopLevelDeclaration				{ [$1] }
    | tex TopLevelDeclaration				{ [$2] }


{

{--------------------------------------------------------------------------
    Parsers
 --------------------------------------------------------------------------}

-- | Parse the token stream. Used by the TeX compiler.
tokensParser :: Parser [Token]

-- | Parse an expression. Could be used in interactions.
exprParser :: Parser Expr

-- | Parse a module.
moduleParser :: Parser TopLevelDeclaration

-- | Parse an interface.
interfaceParser :: Parser Interface


{--------------------------------------------------------------------------
    Happy stuff
 --------------------------------------------------------------------------}

-- | Required by Happy.
happyError :: Parser a
happyError = parseError "Parse error"


{--------------------------------------------------------------------------
    Utility functions
 --------------------------------------------------------------------------}

-- | Match a particular name.
isName :: String -> Name -> Parser ()
isName s x = case x of
		Name _ s' | s == s' -> return ()
		_		    -> happyError

-- | Check that an import directive doesn't contain repeated names
verifyImportDirective :: ImportDirective -> Parser ImportDirective
verifyImportDirective i =
    case filter ((>1) . length)
	 $ group
	 $ sort xs
    of
	[]  -> return i
	yss -> parseErrorAt (rStart $ getRange $ head $ concat yss) $
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

-- | Turn an expression into a left hand side. Fails if the expression is not a
--   valid lhs.
exprToLHS :: Expr -> Parser LHS
exprToLHS e =
    case spine e of
	(_, Ident (QName x)) : es ->
	    do	args <- mapM (uncurry exprToArg) es
		return $ LHS r PrefixDef x args
	(_, InfixApp e1 (QName x) e2) : es ->
	    do	args <- mapM (uncurry exprToArg) $
			    (NotHidden,e1) : (NotHidden,e2) : es
		return $ LHS r InfixDef x args
	_   -> parseError "Parse error in left hand side."
    where
	r = getRange e
	spine (App _ h e1 e2)	= spine e1 ++ [(h, e2)]
	spine (Paren _ e)	= spine e
	spine e			= [(NotHidden,e)]

	exprToArg :: Hiding -> Expr -> Parser (Arg Pattern)
	exprToArg h e = Arg h <$> exprToPattern e

	exprToPattern :: Expr -> Parser Pattern
	exprToPattern e =
	    case e of
		Ident x			-> return $ IdentP x
		App _ h e1 e2		-> AppP h <$> exprToPattern e1
						  <*> exprToPattern e2
		InfixApp e1 op e2	-> InfixAppP
						<$> exprToPattern e1
						<*> return op
						<*> exprToPattern e2
		Paren r e		-> ParenP r
						<$> exprToPattern e
		Underscore r		-> return $ WildP r
		_			-> parseError "Parse error in pattern"

}
