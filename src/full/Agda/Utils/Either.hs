------------------------------------------------------------------------
-- | Utilities for the 'Either' type
------------------------------------------------------------------------

module Agda.Utils.Either
  ( rights
  , isLeft, isRight
  , tests
  ) where

import Control.Arrow
import Agda.Utils.TestHelpers

-- | Extracts the right elements from the list.

rights :: [Either a b] -> [b]
rights xs = [ x | Right x <- xs ]

-- | Extracts the left elements from the list.

lefts :: [Either a b] -> [a]
lefts xs = [ x | Left x <- xs ]

-- | Returns 'True' iff the argument is @'Right' x@ for some @x@.

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left  _) = False

-- | Returns 'True' iff the argument is @'Left' x@ for some @x@.

isLeft :: Either a b -> Bool
isLeft (Right _) = False
isLeft (Left _)  = True

------------------------------------------------------------------------
-- All tests

tests :: IO Bool
tests = runTests "Agda.Utils.Either" []
