
module Proc where

open import Basics

module ProcDef (U : Set)(T : U -> Set)(Name : U -> Set) where

  LT : U -> Set
  LT a = Lift (T a)

  record Tran (a b : U) : Set where
    upV   : T b -> LT a
    downV : T a -> LT b

  infixr 40 _!_ _!_+_
  infix  40 >_
  infixr 30 _||_ _/|_

  data Proc (a : U) : Set where
    o     : Proc a
    >_    : (T a -> Proc a) -> Proc a
    _!_   : LT a -> Proc a -> Proc a
    _!_+_ : LT a -> Proc a -> (T a -> Proc a) -> Proc a
    _||_  : Proc a -> Proc a -> Proc a
    _/|_  : {b : U} -> Tran a b -> Proc b -> Proc a
    def   : Name a -> Proc a

  Env : Set
  Env = (a : U) -> Name a -> Proc a

record Param : Set1 where
  U    : Set
  T    : U -> Set
  Name : U -> Set
  env  : ProcDef.Env U T Name

module Process (param : Param) where

  private open module Par = Param param      public
  private open module Pro = ProcDef U T Name public

  infixr 40 _!g_ _!_+g_
  infix  40 >g_
  infixr 30 _||g_ _/|g_

  data Guard {a : U} : Proc a -> Set where
    og     : Guard o
    >g_    : (f : T a -> Proc a)                          -> Guard (> f)
    _!g_   : (w : LT a)(p : Proc a)                       -> Guard (w ! p)
    _!_+g_ : (w : LT a)(p : Proc a)(f : T a -> Proc a)    -> Guard (w ! p + f)
    _||g_  : {p1 p2 : Proc a} -> Guard p1 -> Guard p2     -> Guard (p1 || p2)
    _/|g_  : {b : U}(φ : Tran a b){p : Proc b} -> Guard p -> Guard (φ /| p)
    defg   : (x : Name a) -> Guard (env a x)              -> Guard (def x)

  infix 20 _-[_]->_ _-!_!->_

  open Tran

  data _-[_]->_ {a : U} : Proc a -> LT a -> Proc a -> Set where
    qtau   : {p : Proc a}                    -> p -[ bot ]-> p
    rx-o   : {v : T a}                       -> o -[ lift v ]-> o
    rx-!   : {v : T a}{w : LT a}{p : Proc a} -> w ! p -[ lift v ]-> w ! p
    rx->   : {v : T a}{f : T a -> Proc a}    -> > f -[ lift v ]-> f v
    rx-+   : {v : T a}{w : LT a}{p : Proc a}{f : T a -> Proc a} ->
             w ! p + f -[ lift v ]-> f v
    rx-||  : {v : T a}{p1 p2 p1' p2' : Proc a} ->
             p1 -[ lift v ]-> p1' ->
             p2 -[ lift v ]-> p2' ->
             p1 || p2 -[ lift v ]-> p1' || p2'
    rx-/|  : {v : T a}{b : U}{φ : Tran a b}{q q' : Proc b} ->
             q -[ downV φ v ]-> q'   ->
             φ /| q -[ lift v ]-> φ /| q'
    rx-def : {v : T a}{p : Proc a}{x : Name a} ->
             env a x -[ lift v ]-> p ->
             def x -[ lift v ]-> p

  data _-!_!->_ {a : U} : Proc a -> LT a -> Proc a -> Set where
    tx-!   : {w : LT a}{p : Proc a} -> w ! p -! w !-> p
    tx-+   : {w : LT a}{p : Proc a}{f : T a -> Proc a} ->
             w ! p + f -! w !-> p
    tx-!|  : {w : LT a}{p p' q q' : Proc a} ->
             p -! w !-> p' -> q -[ w ]-> q' ->
             p || q -! w !-> p' || q'
    tx-|!  : {w : LT a}{p p' q q' : Proc a} ->
             p -[ w ]-> p' -> q -! w !-> q' ->
             p || q -! w !-> p' || q'
    tx-/|  : {b : U}{w : LT b}{φ : Tran a b}{q q' : Proc b} ->
             q -! w !-> q' ->
             φ /| q -! upV φ =<< w !-> φ /| q'
    tx-def : {w : LT a}{p : Proc a}{x : Name a} ->
             env a x -! w !-> p ->
             def x -! w !-> p

  data Silent {a : U} : Proc a -> Set where
    silent-o   : Silent o
    silent->   : {f : T a -> Proc a} -> Silent (> f)
    silent-||  : {p1 p2 : Proc a} ->
                 Silent p1 -> Silent p2 -> Silent (p1 || p2)
    silent-def : {x : Name a} ->
                 Silent (env _ x) -> Silent (def x)
    silent-/|  : {b : U}{φ : Tran a b}{p : Proc b} ->
                 Silent p -> Silent (φ /| p)

