{
{-|
-}
module Syntax.Parser.Parser (
      tokensParser
    ) where

import Syntax.Position
import Syntax.Parser.Monad
import Syntax.Parser.Lexer
import Syntax.Parser.Tokens
import Syntax.Concrete

import Utils.Monad

}

%name tokensParser Tokens
%tokentype { Token }
%monad { Parser }
%lexer { lexer } { TokEOF }
-- %expect 3

%token
    let		{ TokKeyword KwLet $$ }
    in		{ TokKeyword KwIn $$ }
    where	{ TokKeyword KwWhere $$ }
    postulate	{ TokKeyword KwPostulate $$ }
    open	{ TokKeyword KwOpen $$ }
    module	{ TokKeyword KwModule $$ }
    data	{ TokKeyword KwData $$ }
    infix	{ TokKeyword KwInfix $$ }
    infixl	{ TokKeyword KwInfixL $$ }
    infixr	{ TokKeyword KwInfixR $$ }
    mutual	{ TokKeyword KwMutual $$ }
    abstract	{ TokKeyword KwAbstract $$ }
    private	{ TokKeyword KwPrivate $$ }
    Prop	{ TokKeyword KwProp $$ }
    Set		{ TokKeyword KwSet $$ }

    SetN	{ TokSetN $$ }
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

    int		{ TokLitInt $$ }
    float	{ TokLitFloat $$ }
    char	{ TokLitChar $$ }
    string	{ TokLitString $$ }

%%

-- Tokens

Token
    : let	{ TokKeyword KwLet $1 }
    | in	{ TokKeyword KwIn $1 }
    | where	{ TokKeyword KwWhere $1 }
    | postulate { TokKeyword KwPostulate $1 }
    | open	{ TokKeyword KwOpen $1 }
    | module	{ TokKeyword KwModule $1 }
    | data	{ TokKeyword KwData $1 }
    | infix	{ TokKeyword KwInfix $1 }
    | infixl	{ TokKeyword KwInfixL $1 }
    | infixr	{ TokKeyword KwInfixR $1 }
    | mutual	{ TokKeyword KwMutual $1 }
    | abstract	{ TokKeyword KwAbstract $1 }
    | private	{ TokKeyword KwPrivate $1 }
    | Prop	{ TokKeyword KwProp $1 }
    | Set	{ TokKeyword KwSet $1 }

    | SetN	{ TokSetN $1 }
    | tex	{ TokTeX $1 }

    | '.'	{ TokSymbol SymDot $1 }
    | ','	{ TokSymbol SymComma $1 }
    | ';'	{ TokSymbol SymSemi $1 }
    | '`'	{ TokSymbol SymBackQuote $1 }
    | ':'	{ TokSymbol SymColon $1 }
    | '='	{ TokSymbol SymEqual $1 }
    | '_'	{ TokSymbol SymUnderscore $1 }
    | '?'	{ TokSymbol SymQuestionMark $1 }
    | '->'	{ TokSymbol SymArrow $1 }
    | '('	{ TokSymbol SymOpenParen $1 }
    | ')'	{ TokSymbol SymCloseParen $1 }
    | '['	{ TokSymbol SymOpenBracket $1 }
    | ']'	{ TokSymbol SymCloseBracket $1 }
    | '{'	{ TokSymbol SymOpenBrace $1 }
    | '}'	{ TokSymbol SymCloseBrace $1 }
    | vopen	{ TokSymbol SymOpenVirtualBrace $1 }
    | vclose	{ TokSymbol SymCloseVirtualBrace $1 }
    | vsemi	{ TokSymbol SymVirtualSemi $1 }

    | id	{ TokId $1 }
    | op	{ TokOp $1 }

    | int	{ TokLitInt $1 }
    | float	{ TokLitFloat $1 }
    | char	{ TokLitChar $1 }
    | string	{ TokLitString $1 }

Tokens	: Token Tokens	{ $1 : $2 }
	|		{ [] }

topen :			{% pushCurrentContext }

{

-- Parsing

tokensParser	:: Parser [Token]

happyError = fail "Parse error"

}
