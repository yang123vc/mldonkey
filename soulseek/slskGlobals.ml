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

open CommonResult
open BasicSocket
open CommonGlobals
open CommonTypes
open CommonClient
open CommonComplexOptions
open GuiProto
open Options
open CommonFile
open CommonUser
open CommonRoom
open CommonTypes
open CommonShared
open CommonServer
open SlskOptions
open SlskTypes


let login () = 
  if !!login = "" then !!CommonOptions.client_name else !!login
  
let set_server_state s state =
  set_server_state (as_server s.server_server) state
let set_client_state s state =
  set_client_state (as_client s.client_client) state
let set_room_state s state =
  set_room_state (as_room s.room_room) state
let server_num s = server_num (as_server s.server_server)
let file_num s = file_num (as_file s.file_file)
let server_state s = server_state (as_server s.server_server)
let file_state s = file_state (as_file s.file_file)
let server_must_update s = server_must_update (as_server s.server_server)
let file_must_update s = file_must_update (as_file s.file_file)
let user_num  u = user_num  (as_user u.user_user)
  
let file_size file = file.file_file.impl_file_size
let file_downloaded file = file.file_file.impl_file_downloaded
let file_age file = file.file_file.impl_file_age
let file_fd file = file.file_file.impl_file_fd
  
let client_type c =
  client_type (as_client c.client_client)

let nknown_servers = ref 0
let connected_servers = ref ([] : server list)

let servers_by_addr = Hashtbl.create 13
  
let new_server addr port=
  try
    Hashtbl.find servers_by_addr (addr, port) 
  with _ ->
      incr nknown_servers;
      let rec h = { 
          server_server = server_impl;
          server_name = "<unknown>";
          server_addr = addr;
          server_nusers = 0;
          server_info = "";
          server_connection_control = new_connection_control 0.0;
          server_sock = None;
          server_port = port;
          server_nick = 0;
          server_last_nick = "";
          server_search = None;
          server_search_timeout = 0.0;
          server_users = [];
        } and 
        server_impl = {
          dummy_server_impl with
          impl_server_val = h;
          impl_server_ops = server_ops;
        }       in
      server_add server_impl;
      Hashtbl.add servers_by_addr (addr, port) h;
      h

let searches = ref ([] :  (int * CommonTypes.search) list)
let nsearches = ref 0

let clients_by_name = Hashtbl.create 113

let users_by_name = Hashtbl.create 113

let results_by_file = Hashtbl.create 111

let new_user name =
  try
    Hashtbl.find users_by_name name
  with _ ->
      let rec user = {
          user_nick = name;
          user_user = user_impl;
          user_rooms = [];
        } and user_impl = {
          dummy_user_impl with
          impl_user_ops = user_ops;
          impl_user_val = user;
        }
      in
      Hashtbl.add users_by_name name user;
      user_add user_impl;
      user      
      
let new_client name =
  try
    Hashtbl.find clients_by_name name 
  with _ ->
      let u = new_user name in
      let rec c = {
          client_client = impl;
          client_peer_sock = None;
          client_download_sock = None;
          client_result_socks = [];
          client_name = name;
          client_addr = None;
          client_files = [];
          client_pos = Int32.zero;
          client_all_files = None;
          client_receiving = Int32.zero;
          client_connection_control = new_connection_control 0.0;
          client_download = None;
          client_user = u;
        } and impl = {
          dummy_client_impl with
          impl_client_val = c;
          impl_client_ops = client_ops;
        } in
      new_client impl;
      Hashtbl.add clients_by_name name c;
      c

      
let new_result filename filesize =
  let basename = Filename2.basename filename in
  let key = (basename, filesize) in  
  try
    Hashtbl.find results_by_file key
  with _ ->
      let rec result = {
          result_result = result_impl;
          result_name = basename;
          result_size = filesize;
          result_sources = [];
        } and
        result_impl = {
          dummy_result_impl with
          impl_result_val = result;
          impl_result_ops = result_ops;
        } in
      CommonResult.new_result result_impl;
      Hashtbl.add results_by_file key result;
      result
        
        
let add_result_source r u filename =
  if not (List.mem_assoc u r.result_sources) then begin
      r.result_sources <- (u, filename) :: r.result_sources
    end
      
let rooms_by_name = Hashtbl.create 13
  
let new_room name =
  try 
    Hashtbl.find rooms_by_name name
  with _ ->
      let rec room = {
          room_room = room_impl;
          room_name = name;
          room_nusers = 0;
          room_users = [];
          room_messages = [];
        } and 
        room_impl = {
          dummy_room_impl with
          impl_room_val = room;
          impl_room_ops = room_ops;
          impl_room_state = RoomPaused;
        }         
      in 
      room_add room_impl;
      Hashtbl.add rooms_by_name name room;
      room