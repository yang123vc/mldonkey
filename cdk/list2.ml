(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

let rec removeq_rec ele list tail =
  match list with
    [] -> List.rev tail
  | e :: list ->
      if e == ele then removeq_rec ele list tail
      else
        removeq_rec ele list (e :: tail)

let rec removeq ele list =
  removeq_rec ele list []

let rec remove_rec ele list tail =
  match list with
    [] -> List.rev tail
  | e :: list ->
      if e = ele then remove_rec ele list tail
      else
        remove_rec ele list (e :: tail)
        
let remove ele list =
  remove_rec ele list []
  
let rec removeq_first ele list =
  match list with
    e :: tail when e == ele -> tail
  | e :: tail -> e :: (removeq_first ele tail)
  | _ -> []

let rec remove_first ele list =
  match list with
    e :: tail when e = ele -> remove_first ele tail
  | e :: tail -> e :: (remove_first ele tail)
  | _ -> []

let rec cut_rec n list r =
  match n, list with
    (0,_) | (_, []) -> List.rev r, list
  | _, x :: tail ->
      cut_rec (n-1) tail (x :: r)
      
let cut n list =
  if n < 0 then failwith "List2.sub: invalid parameter";
  cut_rec n list []
  