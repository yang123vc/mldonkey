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
type t
  
val of_inet_addr : Unix.inet_addr -> t
val of_string : string -> t
val of_ints : int * int * int * int -> t

val to_inet_addr : t -> Unix.inet_addr
val to_string : t -> string
val to_ints : t -> int * int * int * int

val to_fixed_string : t -> string

val valid : t -> bool

val resolve_one : t -> string
  