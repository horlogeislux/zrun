(***********************************************************************)
(*                                                                     *)
(*                                                                     *)
(*          Zelus, a synchronous language for hybrid systems           *)
(*                                                                     *)
(*  (c) 2023 Inria Paris (see the AUTHORS file)                        *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique. All rights reserved. This file is distributed under   *)
(*  the terms of the INRIA Non-Commercial License Agreement (see the   *)
(*  LICENSE file).                                                     *)
(*                                                                     *)
(* *********************************************************************)

(* kind.ml : basic operations over kinds *)

open Deftypes
open Typerrors
   
(** The kind of an expression tells wheither it is:
 *- const: a compile-time known constant;
 *- static: a static expression, known at instantiation time;
 *- any: a combinational expression;
 *- node: a stateful expression; either with only discrete-state variables
 *-       or both *)

(** The kind for function types:
 *- -V->                 -V|V->
 *- -S->                 -S|S->
 *- -A->                 -*|A->  any input; output is combinational
 *- -D->                 -*|D ->                      stateful (discrete)
 *- -C->                 -*|C ->                      stateful (continuous)
 *)

let vkind k = match k with | Tfun(v) -> v | Tnode _ -> Tany

(* kind from const or static *)
let kind_of_const is_const = Tfun(if is_const then Tconst else Tstatic)
let const_of_kind k =
  match k with
  | Tfun(Tconst) -> true
  | Tfun(Tstatic) -> false
  | Tfun _ | Tnode _ -> assert false

(* kind from a sort *)
let kind_of_sort sort =
  let k = match sort with
    | Sort_const -> Tconst | Sort_static -> Tstatic | _ -> Tany in
  Tfun(k)

let sort_of_kind k =
  match k with
  | Tnode _ -> Sort_val
  | Tfun(vkind) ->
     match vkind with
     | Tconst -> Sort_const | Tstatic -> Sort_static | Tany -> Sort_val
                                               
(* order between kinds *)
let vkind_is_less_than actual_v expected_v =
  match actual_v, expected_v with
  | (Tconst, _) | (Tstatic, (Tstatic | Tany)) | (Tany, Tany) -> true
  | _ -> false

let left_right k =
  match k with
    | Tfun(k) ->
       (match k with
        | Tconst -> Tconst, Tconst | Tstatic -> Tstatic, Tstatic
        | Tany -> Tany, Tany)
    | Tnode _ -> Tany, Tany

let is_less_than actual_k expected_k =
  match actual_k, expected_k with
  | Tfun(k1), Tfun(k2) -> vkind_is_less_than k1 k2
  | Tfun _, Tnode _ -> true
  | Tnode k1, Tnode k2 when k1 = k2 -> true
  | _ -> false

let stateful = function | Tfun _ -> false | Tnode _ -> true

(* The sup of two kind. This function should be applied when *)
(* the sup exists; it should not raise an error *)
let sup k1 k2 =
  let sup k1 k2 = match k1, k2 with
  | (Tconst, _) -> k2 | (_, Tconst) -> k1
  | (Tstatic, _) -> k2 | (_, Tstatic) -> k1
  | (Tany, Tany) -> Tany in
  match k1, k2 with
  | (Tfun k1, Tfun k2) -> Tfun (sup k1 k2)
  | (Tfun _, _) -> k2
  | (_, Tfun _) -> k1
  | _ -> if k1 = k2 then k1 else assert false
                              
let sup_list l =
  match l with
  | [] -> Tfun(Tconst)
  | x :: l -> List.fold_left sup x l

let vinf v1 v2 =
  match v1, v2 with
  | (Tconst, _) -> v2 | (_, Tconst) -> v1
  | (Tstatic, _) -> v2 | (_, Tstatic) -> v1
  | _ -> v1

(* Check that a type belong to kind [ka]. The intuition is this:
 *- a function f of type t1 -{k1|k2}-> t2 must be such that:
 *- t1 is in kind k1 and t2 is in kind k2;
 *- it can only be applied in a context [ka]
 *- such that [ka <= k1]. *)
let rec in_kind ka { t_desc } =
  match t_desc with
  | Tvar -> true
  | Tproduct(ty_list) | Tconstr(_, ty_list, _) ->
     List.for_all (in_kind ka) ty_list
  | Tlink(ty_link) -> in_kind ka ty_link
  | Tsize _ -> true
  | Tvec(ty, _) -> in_kind ka ty
  | Tarrow(kfun, t1, t2) ->
     let left_kfun, right_kfun = left_right kfun in
     in_kind left_kfun t1 && in_kind right_kfun t2
                               && vkind_is_less_than ka left_kfun

(* Kind inheritance. If the context has kind [expected_k] *)
(* and the local declaration is kind [vkind] *)
(* names will have the minimum of the two *)
let inherits expected_k vkind =
  match expected_k, vkind with
  | Tnode _, (Tconst | Tstatic) -> Tfun vkind
  | Tnode _, Tany -> expected_k
  | Tfun vfun, _ ->
     let vfun = match vfun, vkind with
       | (Tconst, _) | (_, Tconst) -> Tconst
       | (Tstatic, _) | (_, Tstatic) -> Tstatic
       | _ -> Tany in
     Tfun vfun
  
