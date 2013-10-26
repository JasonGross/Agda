{-# LANGUAGE CPP #-}

module Agda.TypeChecking.Injectivity where

import Prelude hiding (mapM)
import Control.Applicative
-- import Control.Monad hiding (mapM)
import Control.Monad.Error hiding (mapM, forM)
import Control.Monad.State hiding (mapM, forM)
import Control.Monad.Reader hiding (mapM, forM)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Maybe
-- import Data.List
import Data.Traversable

import Agda.Syntax.Common
import Agda.Syntax.Internal
import Agda.TypeChecking.Monad
import Agda.TypeChecking.Substitute
import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Primitive
import {-# SOURCE #-} Agda.TypeChecking.MetaVars
import {-# SOURCE #-} Agda.TypeChecking.Conversion
import Agda.TypeChecking.Pretty
-- import Agda.TypeChecking.Eliminators
import Agda.TypeChecking.Constraints
import Agda.TypeChecking.Polarity
import Agda.Utils.List
-- import Agda.Utils.Monad
import Agda.Utils.Permutation

#include "../undefined.h"
import Agda.Utils.Impossible

-- | Reduce simple (single clause) definitions.
reduceHead :: Term -> TCM (Blocked Term)
reduceHead v = do -- ignoreAbstractMode $ do
  -- Andreas, 2013-02-18 ignoreAbstractMode leads to information leakage
  -- see Issue 796

  -- first, possibly rewrite literal v to constructor form
  v <- constructorForm v
  reportSDoc "tc.inj.reduce" 30 $ text "reduceHead" <+> prettyTCM v
  case ignoreSharing v of
    Def f es -> do

      abstractMode <- envAbstractMode <$> ask
      isAbstract <- treatAbstractly f
      reportSLn "tc.inj.reduce" 50 $
        "reduceHead: we are in " ++ show abstractMode++ "; " ++ show f ++
        " is treated " ++ if isAbstract then "abstractly" else "concretely"

      let v0  = Def f []
          red = unfoldDefinitionE False reduceHead v0 f es
      def <- theDef <$> getConstInfo f
      case def of
        -- Andreas, 2012-11-06 unfold aliases (single clause terminating functions)
        -- see test/succeed/Issue747
        -- We restrict this to terminating functions to not make the
        -- type checker loop here on non-terminating functions.
        -- see test/fail/TerminationInfiniteRecord
        Function{ funClauses = [ _ ], funDelayed = NotDelayed, funTerminates = Just True } -> do
          reportSLn "tc.inj.reduce" 50 $ "reduceHead: head " ++ show f ++ " is Function"
          red
        Datatype{ dataClause = Just _ } -> red
        Record{ recClause = Just _ }    -> red
        _                               -> return $ notBlocked v
    _ -> return $ notBlocked v

headSymbol :: Term -> TCM (Maybe TermHead)
headSymbol v = do -- ignoreAbstractMode $ do
  -- Andreas, 2013-02-18 ignoreAbstractMode leads to information leakage

  v <- ignoreBlocking <$> reduceHead v
  case ignoreSharing v of
    Def f _ -> do
      def <- theDef <$> do ignoreAbstractMode $ getConstInfo f
        -- Andreas, 2013-02-18
        -- if we do not ignoreAbstractMode here, abstract Functions get turned
        -- into Axioms, but we want to distinguish these.
      case def of
        Datatype{}  -> return (Just $ ConsHead f)
        Record{}    -> return (Just $ ConsHead f)
        Axiom{}     -> do
          reportSLn "tc.inj.axiom" 50 $ "headSymbol: " ++ show f ++ " is an Axiom."
          -- Don't treat axioms in the current mutual block
          -- as constructors (they might have definitions we
          -- don't know about yet).
          fs <- lookupMutualBlock =<< currentOrFreshMutualBlock
          if Set.member f fs
            then return Nothing
            else return (Just $ ConsHead f)
        Function{}    -> return Nothing
        Primitive{}   -> return Nothing
        Constructor{} -> __IMPOSSIBLE__
    Con c _ -> return (Just $ ConsHead $ conName c)
    Sort _  -> return (Just SortHead)
    Pi _ _  -> return (Just PiHead)
    Lit _   -> return Nothing -- handle literal heads as well? can't think of
                              -- any examples where it would be useful...
    Lam{}   -> return Nothing
    Var{}   -> return Nothing
    Level{} -> return Nothing
    MetaV{} -> return Nothing
    DontCare{} -> return Nothing
    Shared{}   -> __IMPOSSIBLE__

checkInjectivity :: QName -> [Clause] -> TCM FunctionInverse
checkInjectivity f cs
  | pointLess cs = return NotInjective
  where
    -- Is it pointless to use injectivity for this function?
    pointLess []      = True
    pointLess (_:_:_) = False
    pointLess [Clause{clausePats = ps}] = all (noMatch . unArg) ps
      where noMatch ConP{} = False
            noMatch LitP{} = False
            noMatch ProjP{}= False
            noMatch VarP{} = True
            noMatch DotP{} = True
checkInjectivity f cs = do
  reportSLn "tc.inj.check" 40 $ "Checking injectivity of " ++ show f
  -- Extract the head symbol of the rhs of each clause (skip absurd clauses)
  -- es <- concat <$> mapM entry cs
  es <- catMaybes <$> do
    forM cs $ \ c -> do
      forM (getBody c) $ \ v -> do
        h <- headSymbol v
        return (h, c)
  let (hs, ps) = unzip es
  reportSLn "tc.inj.check" 40 $ "  right hand sides: " ++ show hs
  if all isJust hs && distinct hs
    then do
      let inv = Map.fromList (map fromJust hs `zip` ps)
      reportSLn "tc.inj.check" 20 $ show f ++ " is injective."
      reportSDoc "tc.inj.check" 30 $ nest 2 $ vcat $
        map (\ (h, c) -> text (show h) <+> text "-->" <+>
                          fsep (punctuate comma $ map (text . show) $ clausePats c)
            ) $ Map.toList inv
      return $ Inverse inv
    else return NotInjective
{-
  where
    entry c = do
      case getBody (clauseBody c) of
        Nothing -> return []
        Just v  -> do
          h <- headSymbol v
          return [(h, c)]
-}

{- RETIRED, now using Substitute.getBody instead of rhd
    entry c = do
      mv <- rhs (clauseBody c)
      case mv of
        Nothing -> return []
        Just v  -> do
          h <- headSymbol v
          return [(h, c)]

    rhs (Bind b)   = underAbstraction_ b rhs
    rhs (Body v)   = return $ Just v
    rhs NoBody     = return Nothing
-}

-- | Argument should be on weak head normal form.
functionInverse :: Term -> TCM InvView
functionInverse v = case ignoreSharing v of
  Def f es -> do
    d <- theDef <$> getConstInfo f
    case d of
      Function{ funInv = inv } -> case inv of
        NotInjective  -> return NoInv
        Inverse m     -> return $ Inv f es m
      _ -> return NoInv
  _ -> return NoInv

{-
-- | Argument should be on weak head normal form.
functionInverse :: Term -> TCM InvView
functionInverse v = do
  ev <- elimView $ ignoreSharing v
  case ev of
    DefElim f args -> do
      d <- theDef <$> getConstInfo f
      case d of
        Function{ funInv = inv } -> case inv of
          NotInjective  -> return NoInv
          Inverse m     -> return $ Inv f args m
        _ -> return NoInv
    _ -> return NoInv
-}

{-
data InvView = Inv QName Args (Map TermHead Clause)
             | NoInv
-}

data InvView = Inv QName [Elim] (Map TermHead Clause)
             | NoInv

useInjectivity :: Comparison -> Type -> Term -> Term -> TCM ()
useInjectivity cmp a u v = do
  reportSDoc "tc.inj.use" 30 $ fsep $
    pwords "useInjectivity on" ++
    [ prettyTCM u, prettyTCM cmp, prettyTCM v, text ":", prettyTCM a
    ]
  uinv <- functionInverse u
  vinv <- functionInverse v
  case (uinv, vinv) of
    (Inv f fArgs _, Inv g gArgs _)
      | f == g    -> do
        a <- defType <$> getConstInfo f
        reportSDoc "tc.inj.use" 20 $ vcat
          [ fsep (pwords "comparing application of injective function" ++ [prettyTCM f] ++
                pwords "at")
          , nest 2 $ fsep $ punctuate comma $ map prettyTCM fArgs
          , nest 2 $ fsep $ punctuate comma $ map prettyTCM gArgs
          , nest 2 $ text "and type" <+> prettyTCM a
          ]
        pol <- getPolarity' cmp f
        -- compareArgs pol a (Def f []) fArgs gArgs
        compareElims pol a (Def f []) fArgs gArgs
      | otherwise -> fallBack
    (Inv f args inv, NoInv) -> do
      a <- defType <$> getConstInfo f
      reportSDoc "tc.inj.use" 20 $ fsep $
        pwords "inverting injective function" ++
        [ prettyTCM f, text ":", prettyTCM a, text "for", prettyTCM v
        , parens $ text "args =" <+> prettyList (map prettyTCM args)
        ]
      invert u f a inv args =<< headSymbol v
    (NoInv, Inv g args inv) -> do
      a <- defType <$> getConstInfo g
      reportSDoc "tc.inj.use" 20 $ fsep $
        pwords "inverting injective function" ++
        [ prettyTCM g, text ":", prettyTCM a,  text "for", prettyTCM u
        , parens $ text "args =" <+> prettyList (map prettyTCM args)
        ]
      invert v g a inv args =<< headSymbol u
    (NoInv, NoInv)          -> fallBack
  where
    fallBack = addConstraint $ ValueCmp cmp a u v

--    invert :: Term -> QName -> Type -> Map TermHead Clause -> Args -> Maybe TermHead -> TCM ()
    invert :: Term -> QName -> Type -> Map TermHead Clause -> [Elim] -> Maybe TermHead -> TCM ()
    invert _ _ a inv args Nothing  = fallBack
    invert org f ftype inv args (Just h) = case Map.lookup h inv of
      Nothing -> typeError $ UnequalTerms cmp u v a
      Just (Clause{ clauseTel  = tel
                  , clausePerm = perm
                  , clausePats = ps }) -> do -- instArgs args ps
          -- These are what dot patterns should be instantiated at
          ms <- map unArg <$> newTelMeta tel
          reportSDoc "tc.inj.invert" 20 $ vcat
            [ text "meta patterns" <+> prettyList (map prettyTCM ms)
            , text "  perm =" <+> text (show perm)
            , text "  tel  =" <+> prettyTCM tel
            , text "  ps   =" <+> prettyList (map (text . show) ps)
            ]
          -- and this is the order the variables occur in the patterns
          let ms' = permute (invertP $ compactP perm) ms
          let sub = parallelS (reverse ms)
--          margs <- runReaderT (evalStateT (metaArgs ps) ms') sub
          margs <- runReaderT (evalStateT (mapM metaElim ps) ms') sub
          reportSDoc "tc.inj.invert" 20 $ vcat
            [ text "inversion"
            , nest 2 $ vcat
              [ text "lhs  =" <+> prettyTCM margs
              , text "rhs  =" <+> prettyTCM args
              , text "type =" <+> prettyTCM ftype
              ]
            ]
          -- Since we do not care for the value of non-variant metas here,
          -- we can treat 'Nonvariant' as 'Invariant'.
          -- That ensures these metas do not remain unsolved.
          pol <- purgeNonvariant <$> getPolarity' cmp f
          -- The clause might not give as many patterns as there
          -- are arguments (point-free style definitions).
          let args' = take (length margs) args
          compareElims pol ftype org margs args'
--          compareArgs pol ftype org margs args'
{- Andreas, 2011-05-09 allow unsolved constraints as long as progress
          unless (null cs) $ do
            reportSDoc "tc.inj.invert" 30 $
              text "aborting inversion; remaining constraints" <+> prettyTCM cs
            patternViolation
-}
          -- Check that we made progress, i.e. the head symbol
          -- of the original term should be a constructor.
          org <- reduce org
          h <- headSymbol org
          case h of
            Just h  -> compareTerm cmp a u v
            Nothing -> do
             reportSDoc "tc.inj.invert" 30 $ vcat
               [ text "aborting inversion;" <+> prettyTCM org
               , text "plainly," <+> text (show org)
               , text "has TermHead" <+> text (show h)
               , text "which does not expose a constructor"
               ]
             patternViolation
        `catchError` \err -> case err of
          TypeError   {} -> throwError err
          Exception   {} -> throwError err
          IOException {} -> throwError err
          PatternErr  {} -> fallBack
          {- AbortAssign {} -> fallBack -- UNUSED -}

    nextMeta = do
      m : ms <- get
      put ms
      return m

    dotP :: Monad m => Term -> StateT [Term] (ReaderT Substitution m) Term
    dotP v = do
      sub <- ask
      return $ applySubst sub v

    metaElim (Arg _ (ProjP p)) = return $ Proj p
    metaElim (Arg info p)         = Apply . Arg info <$> metaPat p

    metaArgs args = mapM (traverse metaPat) args

    metaPat (DotP v)         = dotP v
    metaPat (VarP _)         = nextMeta
    metaPat (ConP c mt args) = Con c <$> metaArgs args
    metaPat (LitP l)         = return $ Lit l
    metaPat ProjP{}          = __IMPOSSIBLE__
