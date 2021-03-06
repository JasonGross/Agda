
module Printf where
import AlonzoPrelude
import PreludeList
import PreludeShow
import PreludeString
import PreludeNat

open AlonzoPrelude
open PreludeList hiding (_++_)
open PreludeShow
open PreludeString
open PreludeNat

data Unit : Set where
  unit : Unit

data Format : Set where
  stringArg : Format
  natArg    : Format
  intArg    : Format
  floatArg  : Format
  charArg   : Format
  litChar   : Char -> Format
  badFormat : Char -> Format

data BadFormat (c : Char) : Set where

format : String -> List Format
format s = format' (toList s)
  where
    format' : List Char -> List Format
    format' ('%' :: 's' :: fmt) = stringArg   :: format' fmt
    format' ('%' :: 'n' :: fmt) = natArg      :: format' fmt
    format' ('%' :: 'd' :: fmt) = intArg      :: format' fmt
    format' ('%' :: 'f' :: fmt) = floatArg    :: format' fmt
    format' ('%' :: 'c' :: fmt) = charArg     :: format' fmt
    format' ('%' :: '%' :: fmt) = litChar '%' :: format' fmt
    format' ('%' ::  c  :: fmt) = badFormat c :: format' fmt
    format' (c		:: fmt) = litChar c   :: format' fmt
    format'  []		= []

Printf' : List Format -> Set
Printf' (stringArg   :: fmt) = String  × Printf' fmt
Printf' (natArg      :: fmt) = Nat     × Printf' fmt
Printf' (intArg      :: fmt) = Int     × Printf' fmt
Printf' (floatArg    :: fmt) = Float   × Printf' fmt
Printf' (charArg     :: fmt) = Char    × Printf' fmt
Printf' (badFormat c :: fmt) = BadFormat c
Printf' (litChar _   :: fmt) = Printf' fmt
Printf'  []		     = Unit

Printf : String -> Set
Printf fmt = Printf' (format fmt)

{-
printf' : (fmt : List Format) -> Printf' fmt -> String
printf' (stringArg   :: fmt) < s , args > = s			 ++ printf' fmt args
printf' (natArg      :: fmt) < n , args > = showNat n		 ++ printf' fmt args
printf' (intArg      :: fmt) < n , args > = showInt n		 ++ printf' fmt args
printf' (floatArg    :: fmt) < x , args > = showFloat x	 ++ printf' fmt args
printf' (charArg     :: fmt) < c , args > = showChar c	 ++ printf' fmt args
printf' (litChar c   :: fmt) args = fromList (c :: []) ++ printf' fmt args
printf' (badFormat _ :: fmt) ()
printf'  []		 unit = "" 
-}
printf : (fmt : String) -> Printf fmt -> String
printf fmt = printf' (format fmt)
  where
    printf' : (fmt : List Format) -> Printf' fmt -> String
    printf' (stringArg   :: fmt) < s , args > = s			 ++ printf' fmt args
    printf' (natArg      :: fmt) < n , args > = showNat n		 ++ printf' fmt args
    printf' (intArg      :: fmt) < n , args > = showInt n		 ++ printf' fmt args
    printf' (floatArg    :: fmt) < x , args > = showFloat x	 ++ printf' fmt args
    printf' (charArg     :: fmt) < c , args > = showChar c	 ++ printf' fmt args
    printf' (litChar c   :: fmt) args	    = fromList (c :: []) ++ printf' fmt args
    printf' (badFormat _ :: fmt) ()
    printf'  []		 unit 	    = ""

mainS : String
-- mainS = printf  "pi = %f"  < 3.14 , unit > 
mainS = printf "Answer is %n, pi = %f %% %s" 
	< 42 , < 3.14159 , < "Alonzo" , unit > > >
