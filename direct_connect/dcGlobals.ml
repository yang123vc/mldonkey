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
open DcTypes
open DcOptions
  
module DO = CommonOptions
  
let nservers = ref 0

  
let listen_sock = ref (None : TcpServerSocket.t option)

let servers_list = ref ([] : server list) 
let connected_servers = ref ([]: server list)
let servers_by_addr = Hashtbl.create 100
let nknown_servers = ref 0  
  
let shared_files = Hashtbl.create 13

let users_by_name = Hashtbl.create 113
    
let files_by_key = Hashtbl.create 47

let current_files = ref []
      
let clients_by_name = Hashtbl.create 113

let results_by_file = Hashtbl.create 111


(**)
(**)
(*             FUNCTIONS          *)
(**)
(**)
  
let set_server_state s state =
  set_server_state (as_server s.server_server) state
let set_room_state s state =
  set_room_state (as_room s.server_room) state
let server_num s = server_num (as_server s.server_server)
let file_num s = file_num (as_file s.file_file)
let server_state s = server_state (as_server s.server_server)
let file_state s = file_state (as_file s.file_file)
let server_must_update s = server_must_update (as_server s.server_server)
let file_must_update s = file_must_update (as_file s.file_file)
    
let new_shared_dir dirname = {
    shared_dirname = dirname;
    shared_files = [];
    shared_dirs = [];
  }

let shared_tree = new_shared_dir ""

let rec add_shared_file node sh dir_list =
  match dir_list with
    [] -> assert false
  | [filename] ->
      node.shared_files <- sh :: node.shared_files
  | dirname :: dir_tail ->
      let node =
        try
          List.assoc dirname node.shared_dirs
        with _ ->
            let new_node = new_shared_dir dirname in
            node.shared_dirs <- (dirname, new_node) :: node.shared_dirs;
            new_node
      in
      add_shared_file node sh dir_tail
  
let add_shared s =
  let full_name = shared_fullname s in
  let codedname = shared_codedname s in
  let sh = {
      shared_fullname = full_name;
      shared_codedname = codedname;
      shared_size = (as_shared_impl s).impl_shared_size;
      shared_fd=  Unix32.create full_name [Unix.O_RDONLY] 0o666;
    } in
  set_shared_ops s sh shared_ops;
  Hashtbl.add shared_files codedname sh;
  add_shared_file shared_tree sh (String2.split codedname '/');
  Printf.printf "Total shared : %s" (Int64.to_string !shared_counter);
  print_newline () 
  
  
exception Found of user  

let new_user server name =
  let u =
    try
      let user = Hashtbl.find users_by_name name in
      user
    with _ ->
        let rec user = {
            user_nick = name;
            user_servers = [];
            user_user = user_impl;
            user_link = "";
            user_data = 0.0;
            user_admin = false;
          } and user_impl = {
            dummy_user_impl with
            impl_user_ops = user_ops;
            impl_user_val = user;
          }
        in
        Hashtbl.add users_by_name name user;
        user_add user_impl;
        user      
  in
  match server with
    None -> u
  | Some s ->
      if not (List.memq s u.user_servers) then begin

          (*Printf.printf "%s(%d) is on %s" u.user_nick u.user_user.impl_user_num s.server_name; print_newline (); *)
          u.user_servers <- s :: u.user_servers;
        end;
      u
        
let user_add server name =
  try
    List.iter (fun user -> if user.user_nick = name then raise (Found user)) 
    server.server_users;
    let user = new_user (Some server) name in
    server_new_user (as_server server.server_server) (as_user user.user_user);
    room_new_user (as_room server.server_room) (as_user user.user_user);
    server.server_users <- user :: server.server_users;
    user
  with Found user -> user
  
let new_file file_id name file_size =
  let key = (name, file_size) in
  try
    Hashtbl.find files_by_key key
  with _ ->
      let file_temp = Filename.concat !!DO.temp_directory 
          (Printf.sprintf "DC-%s" (Md4.to_string file_id)) in
      let current_size = try
          Unix32.getsize32 file_temp
        with e ->
            Printf.printf "Exception %s in current_size" (Printexc.to_string e); 
            print_newline ();
            Int32.zero
      in
      
      let rec file = {
          file_file = impl;
          file_name = name;
          file_id = file_id;
          file_temp = file_temp;
          file_clients = [];
        } and impl = {
          dummy_file_impl with
          impl_file_fd = Unix32.create file_temp [Unix.O_RDWR; Unix.O_CREAT] 0o666;
          impl_file_size = file_size;
          impl_file_downloaded = current_size;
          impl_file_val = file;
          impl_file_ops = file_ops;
          impl_file_age = last_time ();          

        } in
      let state = if current_size = file_size then FileDownloaded else begin
            current_files := file :: !current_files;
            FileDownloading
          end
      in
      file_add impl state;
      Hashtbl.add files_by_key key file;
      file

let find_file file_name file_size =
  Hashtbl.find files_by_key (file_name, file_size)
      
let new_client name =
  try
    Hashtbl.find clients_by_name name 
  with _ ->
      let user = new_user None name in
      let rec c = {
          client_client = impl;
          client_sock = None;
          client_name = name;
          client_addr = None;
          client_files = [];
          client_download = DcIdle;
          client_pos = Int32.zero;
          client_all_files = None;
          client_receiving = Int32.zero;
          client_user = user;
          client_connection_control = new_connection_control 0.0;
        } and impl = {
          dummy_client_impl with
          impl_client_val = c;
          impl_client_ops = client_ops;
        } in
      new_client impl;
      Hashtbl.add clients_by_name name c;
      c

      
let add_file_client file user filename = 
  let  c = new_client user.user_nick in
  if not (List.memq c file.file_clients) then begin
      file.file_clients <- c :: file.file_clients;
      c.client_files <- (file, filename) :: c.client_files;
      file_new_source (as_file file.file_file) (as_client c.client_client)
    end;
  c

let add_result_source r u filename =
  if not (List.mem_assoc u r.result_sources) then begin
      r.result_sources <- (u, filename) :: r.result_sources
    end
      
let remove_client c =
  Hashtbl.remove clients_by_name c.client_name;
  List.iter (fun (file,_) ->
      file.file_clients <- List2.removeq c file.file_clients
  ) c.client_files;
  client_remove (as_client c.client_client)
  
      
let set_client_state c state =
  set_client_state (as_client c.client_client) state
              
let login () =
  if !!login = "" then !!CommonOptions.client_name else !!login
    
let login s =
  let nick = 
    if s.server_nick = 0 then login () else 
      Printf.sprintf "%s_%d" (login ()) s.server_nick 
  in
  s.server_nick <- s.server_nick + 1;
  s.server_last_nick <- nick;
  nick

let client_type c =
  client_type (as_client c.client_client)
    
let new_server addr port=
  try
    Hashtbl.find servers_by_addr (addr, port) 
  with _ ->
      incr nknown_servers;
      let rec h = { 
          server_server = server_impl;
          server_room = room_impl;
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
          server_messages = [];
        } and 
        server_impl = {
          dummy_server_impl with
          impl_server_val = h;
          impl_server_ops = server_ops;
        } and 
        room_impl = {
          dummy_room_impl with
          impl_room_val = h;
          impl_room_ops = room_ops;
        }         
      in
      server_add server_impl;
      room_add room_impl;
      Hashtbl.add servers_by_addr (addr, port) h;
      h
  
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
      
let server_remove s =
  server_remove (as_server s.server_server);
  Hashtbl.remove servers_by_addr (s.server_addr, s.server_port);
  decr nknown_servers;
  servers_list := List2.removeq s !servers_list
    
let _ =
  network.op_network_share <- add_shared

  
  
let file_size file = file.file_file.impl_file_size
let file_downloaded file = file.file_file.impl_file_downloaded
let file_age file = file.file_file.impl_file_age
let file_fd file = file.file_file.impl_file_fd
  