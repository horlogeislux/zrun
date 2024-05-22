(***********************************************************************)
(*                                                                     *)
(*                                                                     *)
(*                        The ZRun Interpreter                         *)
(*                                                                     *)
(*                             Marc Pouzet                             *)
(*                                                                     *)
(*  (c) 2020-2024 Inria Paris                                          *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique. All rights reserved. This file is distributed under   *)
(*  the terms of the INRIA Non-Commercial License Agreement (see the   *)
(*  LICENSE file).                                                     *)
(*                                                                     *)
(* *********************************************************************)

open Lident
open Value
   
let lident ff lid =
  match lid with
  | Name(s) -> Format.fprintf ff "%s" s
  | Modname { qual; id } -> Format.fprintf ff "%s.%s" qual id
                          
let rec print_list value ff l =
  match l with
  | [] -> assert false
  | [x] -> value ff x
  | x :: l -> Format.printf "@[%a,@ %a@]" value x (print_list value) l
            
let rec pvalue ff v =
  match v with
  | Vint(i) -> Format.fprintf ff "%i" i
  | Vbool(b) -> Format.fprintf ff "%s" (if b then "true" else "false")
  | Vfloat(f) -> Format.fprintf ff "%f" f
  | Vchar(c) -> Format.fprintf ff "%c" c
  | Vstring(s) -> Format.fprintf ff "%s" s
  | Vvoid -> Format.fprintf ff "()"
  | Vtuple(l) ->
     Format.fprintf ff "@[<hov 1>(%a)@]" value_list l
  | Vstuple(l) ->
     Format.fprintf ff "@[<hov 1>(%a)@]" pvalue_list l
  | Vconstr0(lid) -> lident ff lid
  | Vconstr1(lid, l) ->
     Format.fprintf ff "@[<hov1>%a(%a)@]" lident lid pvalue_list l 
  | Vstate0(id) -> Ident.fprint_t ff id
  | Vstate1(id, l) ->
     Format.fprintf
       ff "@[<hov 1>%a(%a)@]" Ident.fprint_t id pvalue_list l
  | Vfun _ ->
     Format.fprintf ff "<fun>"
  | Vclosure _ ->
     Format.fprintf ff "<closure>"
  | Vsizefun _ ->
     Format.fprintf ff "<sfun>"
  | Vsizefix { bound; name } ->
     Format.fprintf ff "<sizefix <%a>%a>"
       (Pp_tools.print_opt
          (fun ff i_list -> 
             Pp_tools.print_list_l (fun ff i -> Format.fprintf ff "%d" i)
               "(" "," "" ff i_list)) bound Ident.fprint_t name
  | Vrecord(l) ->
     let one ff { Ast.arg; Ast.label } =
       Format.fprintf ff "@[<hov2>%a =@ %a@]"
         pvalue arg Lident.fprint_t label in
     (Pp_tools.print_list_r one "{" ";" "}") ff l
  | Vabsent ->
     Format.fprintf ff "abs"
  | Vpresent(v) ->
     Format.fprintf ff "!%a" pvalue v
  | Varray(a) -> parray ff a

and parray ff a =
  match a with
  | Vflat(v) ->
     Format.fprintf ff "@[<hov1>[|%a|]@]"
       (fun ff v ->
         Array.iter (fun x -> Format.fprintf ff "%a;@," pvalue x) v)
       v
  | Vmap(m) -> pmap ff m

and pmap ff { m_length; m_u } = Format.fprintf ff "@[[%d] -> ...@]" m_length

and value ff v =
  match v with
  | Vnil -> Format.fprintf ff "nil"
  | Vbot -> Format.fprintf ff "bot"
  | Value(v) -> pvalue ff v                 
              
and pvalue_list ff l = print_list pvalue ff l
                     
and value_list ff l = print_list value ff l
                    
let value_flush ff v =
  Format.fprintf ff "%a@." value v
let pvalue_flush ff l = 
  Format.fprintf ff "%a@." pvalue l
let letdecl ff name v =
  Format.fprintf ff "@[<hov 2>val %s =@ %a@]@." name pvalue v
