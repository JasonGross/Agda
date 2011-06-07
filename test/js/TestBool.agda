open import Common.Prelude
open import TestHarness

module TestBool where

not : Bool → Bool
not true  = false
not false = true

_∧_ : Bool → Bool → Bool
true  ∧ x = x
false ∧ x = false

_∨_ : Bool → Bool → Bool
true  ∨ x = true
false ∨ x = x

_↔_ : Bool → Bool → Bool
true  ↔ true  = true
false ↔ false = true
_     ↔ _     = false

tests : Tests
tests _ = (
    assert true "tt" ,
    assert (not false) "!ff" ,
    assert (true ∧ true) "tt∧tt" ,
    assert (not (true ∧ false)) "!(tt∧ff)" ,
    assert (not (false ∧ false)) "!(ff∧ff)" ,
    assert (not (false ∧ true)) "!(ff∧tt)" ,
    assert (true ∨ true) "tt∨tt" ,
    assert (true ∨ false) "tt∨ff" ,
    assert (false ∨ true) "ff∨tt" ,
    assert (not (false ∨ false)) "!(ff∧ff)" ,
    assert (true ↔ true) "tt=tt" ,
    assert (not (true ↔ false)) "tt≠ff" ,
    assert (not (false ↔ true)) "ff≠tt" ,
    assert (false ↔ false) "ff=ff"
 )
