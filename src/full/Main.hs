
{-| Agda 2 main module.
-}
module Main where

import Data.List
import System.Environment

import Syntax.Parser
import Syntax.Concrete.Definitions ()
import Syntax.Concrete.Pretty ()
import Syntax.Concrete.Fixity ()
import Syntax.Internal ()
import Syntax.Abstract ()
import Syntax.Scope ()

parseFile' p file
    | "lagda" `isSuffixOf` file	= parseLiterateFile p file
    | otherwise			= parseFile p file

main =
    do	args <- getArgs
	let [file] = filter ((/=) "-" . take 1) args
	    go	| "-i" `elem` args  = stuff file interfaceParser
		| otherwise	    = stuff file moduleParser
	go
    where
	stuff file p =
	    do	r <- parseFile' p file
		case r of
		    ParseOk _ m	    -> print m
		    ParseFailed err ->
			do  print err
--			    r <- parseFile' tokensParser file
--			    case r of
--				ParseOk _ ts	-> mapM_ print ts
--				ParseFailed err	-> print err
