{-# OPTIONS -fglasgow-exts #-}

{-| The translation of abstract syntax to concrete syntax has two purposes.
    First it allows us to pretty print abstract syntax values without having to
    write a dedicated pretty printer, and second it serves as a sanity check
    for the concrete to abstract translation: translating from concrete to
    abstract and then back again should be (more or less) the identity.
-}
module Syntax.Translation.AbstractToConcrete where

import Control.Monad.Reader

import Syntax.Common
import Syntax.Position
import Syntax.Info
import Syntax.Concrete as C
import Syntax.Abstract as A

import Utils.Maybe
import Utils.Monad

-- Flags ------------------------------------------------------------------

-- | The translation is configurable. Currently you can choose whether to
--   make use of the pieces of concrete syntax stored in the info parts of
--   the abstract syntax. When pretty printing, this is what you want, but
--   if the purpose is to verify the correctness of the translation from
--   concrete to abstract we want to look at all of the abstract syntax.
data Flags = Flags  { useStoredConcreteSyntax :: Bool
		    , precedenceLevel	      :: Precedence
		    }

defaultFlags :: Flags
defaultFlags = Flags { useStoredConcreteSyntax	= True
		     , precedenceLevel		= TopCtx
		     }

-- The Monad --------------------------------------------------------------

-- | We make the translation monadic for modularity purposes.
type AbsToCon = Reader Flags

abstractToConcrete :: ToConcrete a c => Flags -> a -> c
abstractToConcrete flags a = runReader (toConcrete a) flags

-- Dealing with stored syntax ---------------------------------------------

-- | Indicates that the argument is a stored piece of syntax which
--   should only be used 
stored :: a -> AbsToCon (Maybe a)
stored x =
    do	b <- useStoredConcreteSyntax <$> ask
	return $ if b then Just x else Nothing

-- Dealing with precedences -----------------------------------------------

-- | General bracketing function.
bracket' ::    (e -> e)		    -- ^ the bracketing function
	    -> (Precedence -> Bool) -- ^ do we need brackets
	    -> e -> AbsToCon e
bracket' paren needParen e =
    do	p <- precedenceLevel <$> ask
	return $ if needParen p then paren e else e

-- | Expression bracketing
bracket :: (Precedence -> Bool) -> C.Expr -> AbsToCon C.Expr
bracket par e = bracket' (Paren (getRange e)) par e

-- | Pattern bracketing
bracketP :: (Precedence -> Bool) -> C.Pattern -> AbsToCon C.Pattern
bracketP par e = bracket' (ParenP (getRange e)) par e

-- The To Concrete Class --------------------------------------------------

class ToConcrete a c | a -> c where
    toConcrete :: a -> AbsToCon c

-- Info instances ---------------------------------------------------------

instance ToConcrete ExprInfo (Maybe C.Expr) where
    toConcrete (ExprSource e)	= stored e
    toConcrete _		= return Nothing

instance ToConcrete DeclInfo (Maybe [C.Declaration]) where
    toConcrete (DeclSource ds)	= stored ds
    toConcrete _		= return Nothing

instance ToConcrete DefInfo (Maybe [C.Declaration]) where
    toConcrete info = toConcrete $ defInfo info

-- Expression instance ----------------------------------------------------

instance ToConcrete A.Expr C.Expr where
    toConcrete (Var i _) = return $ Ident (concreteName i)
    toConcrete (Def i _) = return $ Ident (concreteName i)
    toConcrete (Con i _) = return $ Ident (concreteName i)
	-- for names we have to use the name from the info, since the abstract name has been
	-- resolved to a fully qualified name (except for variables)
    toConcrete (A.Lit l)	    = return $ C.Lit l
    toConcrete (A.QuestionMark i)   = return $ C.QuestionMark (getRange i)
    toConcrete (A.Underscore i)	    = return $ C.Underscore (getRange i)
    toConcrete _ = undefined

