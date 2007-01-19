{-# OPTIONS -cpp #-}

{-| Operations on file names. -}
module Utils.FileName where

import Utils.TestHelpers
import Test.QuickCheck
import Data.List

splitFilePath :: FilePath -> (FilePath, String, String)
splitFilePath s =
    case span (/=slash) $ reverse s of
	(elif, sl:htap)
	    | sl == slash   -> let (n,e) = splitExt $ reverse elif in
				(reverse (slash:htap), n, e)
	(elif, "")	    -> let (n,e) = splitExt $ reverse elif in
				("", n, e)
	_		    -> error $ "impossible: splitFilePath " ++ show s

-- | The extension includes the dot
splitExt :: FilePath -> (String, String)
splitExt x =
    case span (/='.') $ reverse x of
	(txe, '.':elif)	-> (reverse elif, '.' : reverse txe)
	(elif, "")	-> (reverse elif, "")
	_		-> error $ "impossible: splitExt " ++ show x

-- | Change the extension of a filename
setExtension :: String -> FilePath -> FilePath
setExtension ext x = p ++ n ++ ext
    where
	(p,n,_) = splitFilePath x

-- | Breaks up a path (possibly including a file) into a list of
-- drives/directories (with the file at the end).

splitPath :: FilePath -> [FilePath]
splitPath "" = []
splitPath (c : cs) | c == slash = split cs
                   | otherwise  = split (c : cs)
  where
  split path = case span (/= slash) path of
    ("", "")        -> []
    (dir, "")       -> [dir]
    (dir, _ : path) -> dir : split path

-- | The moral inverse of splitPath.

unsplitPath :: [FilePath] -> FilePath
unsplitPath dirs = concat $ intersperse [slash] $ "" : dirs ++ [""]

prop_splitPath_unsplitPath =
  forAll (list name) $ \dirs ->
    splitPath (unsplitPath dirs) == dirs

prop_splitPath =
  forAll (positive :: Gen Integer) $ \n ->
  forAll (listOfLength n nonEmptyName) $ \dirs ->
    let path = concat $ intersperse [slash] dirs
    in
    genericLength (splitPath   path)                    == n
    &&
    genericLength (splitPath $ slash : path)            == n
    &&
    genericLength (splitPath $ path ++ [slash])         == n
    &&
    genericLength (splitPath $ slash : path ++ [slash]) == n

-- | Given a path (not including a file) 'dropDirectory' removes
-- the last directory in the path (if any).

dropDirectory :: FilePath -> FilePath
dropDirectory = unsplitPath . reverse . drop 1 . reverse . splitPath

prop_dropDirectory =
  forAll nonEmptyName $ \dir ->
  forAll path $ \p ->
    not (null p) ==>
      dropDirectory "" == "/"
      &&
      dropDirectory [slash] == "/"
      &&
      dropDirectory (addSlash p) == dropDirectory p
      &&
      let p' = slash : p ++ [slash] in
      dropDirectory (p' ++ dir) == p'

#ifdef mingw32_HOST_OS
canonify (drive:':':xs) ys =
    case ys of
	drive':':':ys'
	    | drive == drive'	-> canonify' xs ys'
	    | otherwise		-> ys
	_			-> canonify' xs ys
#endif
canonify xs ys = canonify' xs ys

canonify' (x:xs) (y:ys)
    | x == y	    = canonify' xs ys
canonify' [] ys	    = ys
canonify' (s:_) ys
    | s == slash    = ys
canonify' xs ys	    = dotdot xs ++ ys

dotdot []	    = []
dotdot (s:xs)
    | s == slash    = slash : dotdot xs
dotdot xs	    =
    case break (== slash) xs of
	(_, xs)	-> ".." ++ dotdot xs

addSlash "" = ""
addSlash [c]
    | c == slash    = [slash]
    | otherwise	    = [c,slash]
addSlash (c:s) = c : addSlash s

#ifdef mingw32_HOST_OS
slash = '\\'
#else
slash = '/'
#endif

------------------------------------------------------------------------
-- Generators

-- | Generates a character distinct from 'slash' (it may be @\'.\'@).

nameChar :: Gen Char
nameChar = elements $ filter (not . (`elem` forbidden)) chars
  where
  chars = "." ++ ['a' .. 'g']
  forbidden = [slash]

-- | Generates a possibly empty string of 'nameChar's.

name :: Gen FilePath
name = list nameChar

-- | Generates a non-empty string of 'nameChar's.

nonEmptyName :: Gen FilePath
nonEmptyName = nonEmptyList nameChar

-- Generates a possibly empty path (without any drive).

path :: Gen FilePath
path = list $ elements chars
  where
  chars = "/." ++ ['a' .. 'g']

------------------------------------------------------------------------
-- All tests

tests = do
  quickCheck prop_splitPath_unsplitPath
  quickCheck prop_splitPath
  quickCheck prop_dropDirectory
