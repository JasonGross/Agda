
module Agda.TypeChecking.MetaVars.Mention where

import Data.Traversable

import Agda.Syntax.Common
import Agda.Syntax.Internal
import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Monad


class MentionsMeta t where
  mentionsMeta :: MetaId -> t -> Bool

instance MentionsMeta Term where
  mentionsMeta x v = case v of
    Var _ args   -> mm args
    Lam _ b      -> mm b
    Lit{}        -> False
    Def _ args   -> mm args
    Con _ args   -> mm args
    Pi a b       -> mm (a, b)
    Fun a b      -> mm (a, b)
    Sort s       -> mm s
    Level l      -> mm l
    DontCare v   -> False   -- we don't have to look inside don't cares when deciding to wake constraints
    MetaV y args -> x == y || mm args
    where
      mm v = mentionsMeta x v

instance MentionsMeta Level where
  mentionsMeta x (Max as) = mentionsMeta x as

instance MentionsMeta PlusLevel where
  mentionsMeta x ClosedLevel{} = False
  mentionsMeta x (Plus _ a) = mentionsMeta x a

instance MentionsMeta LevelAtom where
  mentionsMeta x l = case l of
    MetaLevel m vs   -> x == m || mentionsMeta x vs
    BlockedLevel m _ -> x == m    -- if it's blocked on a different meta it doesn't matter if it mentions the meta somewhere else
    UnreducedLevel l -> mentionsMeta x l
    NeutralLevel l   -> mentionsMeta x l

instance MentionsMeta Type where
    mentionsMeta x (El s t) = mentionsMeta x (s, t)

instance MentionsMeta Sort where
  mentionsMeta x s = case s of
    Type l     -> mentionsMeta x l
    Prop       -> False
    Inf        -> False
    DLub s1 s2 -> mentionsMeta x (s1, s2)

instance MentionsMeta t => MentionsMeta (Abs t) where
  mentionsMeta x = mentionsMeta x . absBody

instance MentionsMeta t => MentionsMeta (Arg t) where
  mentionsMeta x = mentionsMeta x . unArg

instance MentionsMeta t => MentionsMeta [t] where
  mentionsMeta x = any (mentionsMeta x)

instance MentionsMeta t => MentionsMeta (Maybe t) where
  mentionsMeta x = maybe False (mentionsMeta x)

instance (MentionsMeta a, MentionsMeta b) => MentionsMeta (a, b) where
  mentionsMeta x (a, b) = mentionsMeta x a || mentionsMeta x b

instance (MentionsMeta a, MentionsMeta b, MentionsMeta c) => MentionsMeta (a, b, c) where
  mentionsMeta x (a, b, c) = mentionsMeta x a || mentionsMeta x b || mentionsMeta x c

instance MentionsMeta a => MentionsMeta (Closure a) where
  mentionsMeta x cl = mentionsMeta x (clValue cl)

instance MentionsMeta Elim where
  mentionsMeta x Proj{} = False
  mentionsMeta x (Apply v) = mentionsMeta x v

instance MentionsMeta a => MentionsMeta (Tele a) where
  mentionsMeta x EmptyTel = False
  mentionsMeta x (ExtendTel a b) = mentionsMeta x (a, b)

instance MentionsMeta Constraint where
  mentionsMeta x c = case c of
    ValueCmp _ t u v    -> mm (t, u, v)
    ElimCmp _ t v as bs -> mm ((t, v), (as, bs))
    LevelCmp _ u v      -> mm (u, v)
    TypeCmp _ a b       -> mm (a, b)
    TelCmp a b _ u v    -> mm ((a, b), (u, v))
    SortCmp _ a b       -> mm (a, b)
    Guarded _ cs        -> mm cs  -- no need to look in the guarded constraint
    UnBlock _           -> True   -- shouldn't get here, but if we do we'd better wake this one
    FindInScope m       -> m == x
    IsEmpty t           -> mm t
    where
      mm v = mentionsMeta x v

-- instance (Ord k, MentionsMeta e) => MentionsMeta (Map k e) where
--   mentionsMeta = traverse mentionsMeta

