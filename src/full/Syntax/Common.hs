{-# OPTIONS -fglasgow-exts #-}

{-| Some common syntactic entities are defined in this module.
-}
module Syntax.Common where

import Data.Generics hiding (Fixity)

import Syntax.Position

data Hiding  = Hidden | NotHidden
    deriving (Typeable, Data, Show, Eq)

-- | Functions can be defined in both infix and prefix style. See
--   'Syntax.Concrete.LHS'.
data IsInfix = InfixDef | PrefixDef
    deriving (Typeable, Data, Show, Eq)

-- | Access modifier.
data Access = PrivateDecl | PublicDecl
    deriving (Typeable, Data, Show, Eq)

-- | Equality and ordering on @Name@ are defined to ignore range so same names
--   in different locations are equal.
data Name = Name Range String
    deriving (Typeable, Data)

-- | @noName = 'Name' 'noRange' \"_\"@
noName :: Name
noName = Name noRange "_"

-- Define equality on @Name@ to ignore range so same names in different
--     locations are equal.
--
--   Is there a reason not to do this? -Jeff
--
instance Eq Name where
    (Name _ x) == (Name _ y) = x == y

instance Ord Name where
    compare (Name _ x) (Name _ y) = compare x y


-- | @QName@ is a list of namespaces and the name of the constant.
--   For the moment assumes namespaces are just @Name@s and not
--     explicitly applied modules.
--   Also assumes namespaces are generative by just using derived
--     equality. We will have to define an equality instance to
--     non-generative namespaces (as well as having some sort of
--     lookup table for namespace names).
data QName = Qual Name QName
           | QName Name 
  deriving (Typeable, Data, Eq)


instance Show Name where
    show (Name _ x) = x

instance Show QName where
    show (Qual m x) = show m ++ "." ++ show x
    show (QName x)  = show x


type Nat    = Int
type Arity  = Nat

data Literal = LitInt Range Integer
	     | LitFloat Range Double
	     | LitString Range String
	     | LitChar Range Char
    deriving (Typeable, Data, Eq, Show)


-- | Fixity of infix operators.
data Fixity = LeftAssoc Range Int
	    | RightAssoc Range Int
	    | NonAssoc Range Int
    deriving (Typeable, Data, Eq)

-- | The default fixity. Currently defined to be @'LeftAssoc' 20@.
defaultFixity :: Fixity
defaultFixity = LeftAssoc noRange 20


instance HasRange Name where
    getRange (Name r _)	= r

instance HasRange QName where
    getRange (QName x)  = getRange x
    getRange (Qual n x)	= fuseRange n x

instance HasRange Literal where
    getRange (LitInt r _)	= r
    getRange (LitFloat r _)	= r
    getRange (LitString r _)	= r
    getRange (LitChar r _)	= r

instance HasRange Fixity where
    getRange (LeftAssoc r _)	= r
    getRange (RightAssoc r _)	= r
    getRange (NonAssoc r _)	= r

