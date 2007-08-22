
module Proof where

open import Prelude
open import Lambda
open import Subst
open import Trans
open import Reduction
import Chain

open module C = Chain _≤_ (\x -> refl-≤) (\x y z -> trans-≤)
     renaming (_===_by_ to _<≤>_by_)


data SN {Γ : Ctx}{τ : Type}(t : Term Γ τ) : Set where
  bound : (n : Nat) ->
          ({u : Term Γ τ}(r : t ⟶β* u) -> length r ≤ n) -> SN t

data SNˢ {Γ : Ctx} : {Δ : Ctx} -> Terms Γ Δ -> Set where
  sn-∅   : SNˢ ∅
  _◄sn◄_ : {Δ : Ctx}{τ : Type}{ts : Terms Γ Δ}{t : Term Γ τ} ->
           SNˢ ts -> SN t -> SNˢ (ts ◄ t)

-- Let's prove a simple lemma
lem-SN⟶β : {Γ : Ctx}{τ : Type}{t u : Term Γ τ} ->
           SN t -> t ⟶β* u -> SN u
lem-SN⟶β {Γ}{τ}{t}{u}(bound n cap) r = bound n \r' ->
  chain> length r'
     <≤> length r + length r' by lem-≤+L (length r)
     <≤> length (r ▹◃ r')     by refl-≤' (lem-length▹◃ r r')
     <≤> n                    by cap (r ▹◃ r')
  qed

lem-SN-map : {Γ Δ : Ctx}{σ τ : Type}
             (tm : Term Γ σ -> Term Δ τ) ->
             (f  : {t u : Term Γ σ} -> t ⟶β u -> tm t ⟶β tm u)
             {t : Term Γ σ} -> SN (tm t) -> SN t
lem-SN-map tm f (bound n p) = bound n \r ->
  chain> length r
     <≤> length {R = _⟶β_} (map tm f r)
                by refl-≤' (lem-length-map tm f r)
     <≤> n      by p (map tm f r)
  qed


lem-SN•L : {Γ : Ctx}{σ τ : Type}{t : Term Γ (σ ⟶ τ)}{u : Term Γ σ} ->
          SN (t • u) -> SN t
lem-SN•L {u = u} = lem-SN-map (\v -> v • u) •⟶L

lem-SN↑ : {Γ : Ctx}(Δ : Ctx){σ : Type}{t : Term Γ σ} ->
          SN (t ↑ Δ) -> SN t
lem-SN↑ Δ = lem-SN-map (\v -> v ↑ Δ) (↑⟶β Δ)

lem-SN-x : {Γ Δ : Ctx}{σ : Type}(x : Var Γ (Δ ⇒ σ))
           {ts : Terms Γ Δ} -> SNˢ ts -> SN (var x •ˢ ts)
lem-SN-x x snts = {! !}

infix 30 ⟦_⟧ ∋_

⟦_⟧ ∋_ : (τ : Type){Γ : Ctx} -> Term Γ τ -> Set
⟦ ι     ⟧ ∋ t = SN t
⟦ σ ⟶ τ ⟧ ∋ t = forall {Δ}(u : Term (_ ++ Δ) σ) ->
                ⟦ σ ⟧ ∋ u -> ⟦ τ ⟧ ∋ t ↑ Δ • u

mutual

  lem-⟦⟧⊆SN : (σ : Type){Γ : Ctx}{t : Term Γ σ} ->
              ⟦ σ ⟧ ∋ t -> SN t
  lem-⟦⟧⊆SN ι              okt = okt
  lem-⟦⟧⊆SN (σ ⟶ τ) {Γ}{t} okt = lem-SN↑ (ε , σ) sn-t↑
    where
      ih : {Δ : Ctx}{u : Term Δ τ} -> ⟦ τ ⟧ ∋ u -> SN u
      ih = lem-⟦⟧⊆SN τ

      sn• : (Δ : Ctx)(u : Term (Γ ++ Δ) σ) -> ⟦ σ ⟧ ∋ u -> SN (t ↑ Δ • u)
      sn• Δ u h = ih (okt {Δ} u h)

      u : Term (Γ , σ) σ
      u = var vz

      sn-t↑ : SN (t ↑)
      sn-t↑ = lem-SN•L (sn• (ε , σ) u (lem-⟦⟧ˣ σ vz sn-∅))

  lem-⟦⟧ˣ : (σ : Type){Γ Δ : Ctx}(x : Var Γ (Δ ⇒ σ)){ts : Terms Γ Δ} ->
            SNˢ ts -> ⟦ σ ⟧ ∋ var x •ˢ ts
  lem-⟦⟧ˣ ι       x snts = lem-SN-x x snts
  lem-⟦⟧ˣ (σ ⟶ τ) {Γ}{Δ} x {ts} snts = \u oku -> {! !}
    where
      rem : (u : Term Γ σ) -> ⟦ σ ⟧ ∋ u -> ⟦ τ ⟧ ∋ var x •ˢ ts • u
      rem u oku = lem-⟦⟧ˣ τ x (snts ◄sn◄ lem-⟦⟧⊆SN σ oku)

lem-⟦⟧subst : {Γ Δ : Ctx}{τ : Type}(σ : Type)
              {t : Term (Γ , τ) (Δ ⇒ σ)}{u : Term Γ τ}{vs : Terms Γ Δ} ->
              ⟦ σ ⟧ ∋ t [ u ] •ˢ vs -> ⟦ σ ⟧ ∋ (λ t) • u •ˢ vs
lem-⟦⟧subst ι         h = {!h !} 
lem-⟦⟧subst (σ₁ ⟶ σ₂) h = {! !}
