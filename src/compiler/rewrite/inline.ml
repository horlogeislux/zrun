(***********************************************************************)
(*                                                                     *)
(*                                                                     *)
(*          Zelus, a synchronous language for hybrid systems           *)
(*                                                                     *)
(*  (c) 2024 Inria Paris (see the AUTHORS file)                        *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique. All rights reserved. This file is distributed under   *)
(*  the terms of the INRIA Non-Commercial License Agreement (see the   *)
(*  LICENSE file).                                                     *)
(*                                                                     *)
(* *********************************************************************)

(* inlining; this step assumes that static reduction is done already *)
(* this means that all variable defined at top level in declarations *)
(* are of the form [let x = e] where [x] is a closed term in head normal *)
(* form. For the moment, we only consider explicit lambdas *)
(* of the form \x1... e. all function calls [inline f e1 ... en] *)
(* are inlined *)

open Misc
open Location
open Zelus
open Ident
open Lident
open Defnames
open Genv
open Value
open Error
open Mapfold

(* the type of the accumulator *)
type acc =
  { genv : Value.pvalue Genv.genv;
    (* the global environment *)
    renaming : Ident.t Env.t;
    (* name to name environment *)
  }

let empty = { genv = Genv.empty; renaming = Env.empty }

(* Build a renaming from an environment *)
let build global_funs ({ renaming } as acc) env =
  let buildrec n entry (env, renaming) =
    let m = Ident.fresh (Ident.source n) in
    Env.add m entry env,
    Env.add n m renaming in
  let env, renaming = Env.fold buildrec env (Env.empty, renaming) in
  env, { acc with renaming }

let var_ident global_funs ({ renaming } as acc) x =
  try Env.find x renaming, acc with Not_found ->
    Debug.print_string "Inline warning: unbound local" (Ident.name x);
    x, acc


(** Main transformation *)
(* [(\v_list1 ... v_listn. e) e1 ... en] 
 *- rewrites to:
 *- [local v_list1,...,v_listn do p1 = e1 ... pn = en in e]
 *- [(\(v_list1 ... v_listn. v_ret eq) e1 ... en
 *- rewrites to:
 *- [local v_list1,...,v_listn, v_ret
 *-  do p1 = e1 ... pn = en and eq in p_v *)
let local_in funs f_args arg_list acc { r_desc } =
  (* build a list of equations *)
  let eq_list = List.map2 Aux.eq_of_f_arg_arg_make f_args arg_list in
  let vardec_list =
    List.fold_left (fun acc vardec_list -> vardec_list @ acc) [] f_args in
  match r_desc with
  | Exp(e_r) ->
     let e_r, acc = Mapfold.expression_it funs acc e_r in
     Aux.emake (Elocal(Aux.block_make vardec_list eq_list, e_r)),
     acc
  | Returns { b_vars; b_body; b_write; b_env } ->
     let b_body, acc = Mapfold.equation_it funs acc b_body in
     let vardec_list = b_vars @ vardec_list in
     let eq_list = b_body :: eq_list in
     Aux.emake
       (Elocal(Aux.block_make vardec_list eq_list,
               Aux.returns_of_vardec_list_make b_vars)),
     acc

(** Expressions *)
let expression funs ({ genv } as acc) e = 
  let { e_desc } as e, acc = Mapfold.expression funs acc e in
  match e_desc with
  | Eapp { is_inline = true;
           f = { e_desc = Eglobal { lname }; e_loc = f_loc }; arg_list } ->
    let { Genv.info } =
      try Genv.find_value lname genv with Not_found ->
        Format.eprintf 
          "Inline error: unbound global %s at function call\n" 
          (Lident.modname lname);
        raise Error in
      begin match info with
     | Vclosure
       { c_funexp = { f_args; f_body }; c_genv } ->
        let e, acc =
          local_in funs f_args arg_list { acc with genv = c_genv } f_body in
        e, { acc with genv }
     | _ -> e, acc
     end
  | Eapp { f = { e_desc = Efun { f_args; f_body } }; arg_list } ->
     local_in funs f_args arg_list acc f_body
  | _ -> e, acc

(* check that an expression is either a lambda or a global name; the *)
(* global environment only contains lambdas. Update [acc] *)
(* this solution is fragile and may be changed later. It expect that *)
(* all lambdas to be inlined are global and named ([letdef x = fun ...]) *)
let value_and_update ({ genv } as acc) name { e_desc } =
  match e_desc with
  | Efun c_funexp ->
     let v = Vclosure { c_funexp; c_genv = genv; c_env = Env.empty } in
     (* store the value in the global environment *)
     let genv = Genv.add name v genv in { acc with genv }
  | Eglobal { lname } ->
     begin try 
         let { info } = Genv.find_value lname genv in
         (* store the value in the global environment *)
         let genv = Genv.add name info genv in { acc with genv }
       with Not_found -> acc end
  | _ -> raise Fallback

let implementation funs acc impl =
  let { desc } as impl, ({ genv } as acc) = 
    Mapfold.implementation funs acc impl in
  let acc = match desc with
    (* the right-hand side of definitions that are inlined *)
    (* must be either lambdas or global names *)
    | Eletdecl 
      { d_names = [name, id];
        d_leq =
          { l_eq = { eq_desc = EQeq({ pat_desc = Evarpat(n) }, e ) } } }
         when id = n -> 
       value_and_update acc name e
    | _ -> raise Fallback in
  impl, acc

and open_t funs ({ genv } as acc) modname =
  let genv = Genv.open_module genv modname in modname, { acc with genv }

let set_index funs acc n =
  let _ = Ident.set n in n, acc
let get_index funs acc n = Ident.get (), acc

let program genv p =
  let global_funs = { Mapfold.default_global_funs with build; var_ident } in
  let funs =
    { Mapfold.defaults with
      expression; global_funs; set_index; get_index; implementation; 
      open_t } in
  let p, _ = Mapfold.program_it funs { empty with genv } p in
  p

