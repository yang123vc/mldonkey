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

open Buffer

type url = {
    proto : string;
    server : string;
    port : int;
    full_file : string;
    file : string;
    user : string;
    passwd : string;
    args : (string*string) list;
    
    string : string;
  }
  
(* encode using x-www-form-urlencoded form *)
let url_decode s =
  let len = String.length s in
  let res = String.create len in
  let pos_s = ref 0 in
  let pos_r = ref 0 in
  let digit_hexa x =
    match x with
    | 'a' .. 'f' -> (Char.code x) + 10 - (Char.code 'a')
    | 'A' .. 'F' -> (Char.code x) + 10 - (Char.code 'A')
    | '0' .. '9' -> (Char.code x) - (Char.code '0')
    | _ -> failwith "Not an hexa number (encode.ml)" in
  while !pos_s < len do
    (match s.[!pos_s] with
    | '+' -> res.[!pos_r] <- ' '; incr pos_s
    | '%' ->
        let fst = digit_hexa s.[!pos_s+1] in
        let snd = digit_hexa s.[!pos_s+2] in
        res.[!pos_r] <- Char.chr (fst*16 + snd);
        pos_s := !pos_s + 3
    | c -> res.[!pos_r] <- c; incr pos_s);
    incr pos_r
  done;
  String.sub res 0 !pos_r


let to_string url =
  let res = Buffer.create 80 in
  add_string res url.proto;
  add_string res "://";
  add_string res url.server;
  if not (url.port == 80 && url.proto = "http"
        || url.port == 21 && url.proto = "ftp")
  then
    (add_char res ':'; add_string res (string_of_int url.port));
  add_string res url.full_file;
  contents res

let cut_args url_end =
  let args = String2.split url_end '&' in
  List.map (fun s -> 
        let (name, value) = String2.cut_at s '=' in
      url_decode name, url_decode value
    ) args 

let create ?(proto="http") ?(server="") ?(port=80) ?(user="") ?(pass="") file =
  let short_file, args = String2.cut_at file '?' in
  let args = cut_args args in
  let url = { proto=proto; server=server; port=port; full_file=file;
      user=user; passwd=pass; file = short_file; args = args; string = "" } in
  { url with string = to_string url }
  
  
let of_string s =
  let get_two init_pos =
    let pos = ref init_pos in
    while s.[!pos] <> ':' && s.[!pos] <> '/' && s.[!pos] <> '@' do
      incr pos
    done;
    let first = String.sub s init_pos (!pos - init_pos) in
    if s.[!pos] = ':'
    then
      (let deb = !pos+1 in
      while s.[!pos] <> '@' && s.[!pos] <> '/' do
        incr pos
      done;
      (first, String.sub s deb (!pos-deb), !pos))
    else
      (first, "", !pos) in
  let cut init_pos default_port =
    let stra, strb, new_pos = get_two init_pos in
    let user, pass, host, port, end_pos =
      if s.[new_pos] = '@'
      then
        (let host, port_str, end_pos = get_two (new_pos+1) in
        let port =
          if port_str="" then default_port else int_of_string port_str in
        stra, strb, host, port, end_pos)
      else
        (let port = if strb="" then default_port else int_of_string strb in
        "anonymous", "cdk@caml.opt", stra, port, new_pos) in
    let len = String.length s in
    let file = String.sub s end_pos (len - end_pos) in
    host, port, file, user, pass in
  if String2.check_prefix s "http://"
  then
    try
      let host, port, full_file, user, pass = cut 7 80 in
      create ~server:host ~port  ~user ~pass full_file
    with _ -> raise (Invalid_argument "this string is not a valid http url")
  else if String2.check_prefix s "ftp://"
  then
    try
      let host, port, file, user, pass = cut 6 21 in
      create ~proto:"ftp" ~server:host ~port ~user ~pass file
    with _ -> raise (Invalid_argument "this string is not a valid ftp url")
  else
(* we accept URL with no protocol for local files *)
  let file = s in
  create ~proto: "file"  file

let to_string url = url.string
