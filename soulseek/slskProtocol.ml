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

open TcpBufferedSocket
open LittleEndian
open SlskTypes
open CommonTypes
open CommonGlobals

let get_ip s pos = Ip.rev (get_ip s pos)
let buf_ip buf ip = buf_ip buf (Ip.rev ip)
  
let get_string s pos =
  let len = get_int s pos in
  String.sub s (pos+4) len, pos+4+len
  
let buf_string buf s =
  buf_int buf (String.length s);
  Buffer.add_string buf s

type user_status = {
    mutable status : int;
    avgspeed : int;
    downloadnum : int;
    something : int;
    files : int;
    dirs : int;
    mutable slotsfull : int;
  }      

let buf_user_status buf t =
  buf_int buf t.status;
  buf_int buf t.avgspeed;
  buf_int buf t.downloadnum;
  buf_int buf t.something;
  buf_int buf t.files;
  buf_int buf t.dirs;
  buf_int buf t.slotsfull

let get_int_pos s pos =
  get_int s pos, pos+4

let get_partial_user_status s pos =
  { 
    status = 0;
    avgspeed = get_int s pos;
    downloadnum = get_int s (pos+4);
    something = get_int s (pos+8);
    files = get_int s (pos+12);
    dirs = get_int s (pos+16);
    slotsfull = 0;
  }, pos + 20
  
let get_user_status s pos = (* 4 * 7 = 28 *)
  { 
    status = get_int s pos;
    avgspeed = get_int s (pos+4);
    downloadnum = get_int s (pos+8);
    something = get_int s (pos+12);
    files = get_int s (pos+16);
    dirs = get_int s (pos+20);
    slotsfull = get_int s (pos+24);
  }, pos + 28
  
let unknown opcode s =
  Printf.printf "Unknown: opcode %d" opcode; print_newline ();
  LittleEndian.dump s
  
module C2S = struct
    
    module Login = struct
        type t = {
            login : string;
            password: string;
            version: int;
          }
          
        let parse s = 
          let login, pos = get_string s 0 in
          let password, pos = get_string s pos in
          let version = get_int s pos in
          { login = login; password = password; version = version; }
        
        let print t =
          Printf.printf "LOGIN login:%s password:%s version:%d" 
            t.login t.password t.version;
          print_newline () 
          
        let write buf t =
          buf_string buf t.login;
          buf_string buf t.password;
          buf_int buf t.version
          
      end
    
    module SetWaitPort = struct
        type t = int
          
        let parse s =  get_int s 0
          
        let print t =
          Printf.printf "SETWAITPORT %d" t;
          print_newline () 
          
        let write buf t =
          buf_int buf t
          
      end
    
    module Search = struct
        type t = {
            id : int;
            words : string;
          }
          
        let parse s =  
          let id = get_int s 0 in
          let s, pos = get_string s 4 in
          { id = id; words = s }
          
        let print t =
          Printf.printf "SEARCH %d FOR %s" t.id t.words;
          print_newline () 
          
        let write buf t =
          buf_int buf t.id;
          buf_string buf t.words
          
      end
    
    type t = 
    | LoginReq of Login.t
    | SetWaitPortReq of SetWaitPort.t
    | SearchReq of Search.t
    | GetUserStatsReq of string
    | JoinRoomReq of string
    | AddUserReq of string
    | GetPeerAddressReq of string
    | CantConnectToPeerReq of string
    | LeaveRoomReq of string
    | SayChatroomReq of string * string
    | UnknownReq of int * string
    
    let parse opcode s =
      try
        match opcode with
          1 -> LoginReq (Login.parse s)
        | 2 -> SetWaitPortReq (SetWaitPort.parse s)
        | 3 -> 
            let user, _ = get_string s 0 in
            GetPeerAddressReq user
        | 5 -> 
            let user, _ = get_string s 0 in
            AddUserReq user
        | 13 ->
            let room, pos = get_string s 0 in
            let msg, pos = get_string s pos in
            SayChatroomReq (room, msg)
        | 14 -> 
            let room, _ = get_string s 0 in
            JoinRoomReq room
        | 15 ->             
            let room, _ = get_string s 0 in
            LeaveRoomReq room
        | 26 -> SearchReq (Search.parse s)
        | 36 -> 
            let user, _ = get_string s 0 in
            GetUserStatsReq user
        | 1001 -> 
            let user, _ = get_string s 0 in
            CantConnectToPeerReq user
        | _ -> raise Not_found
      with
        e -> 
          Printf.printf "From client"; print_newline ();
          unknown opcode s;
          UnknownReq (opcode, s)

          
    let print t =
      match t with
        | LoginReq t -> Login.print t  
      | SetWaitPortReq t -> SetWaitPort.print t  
      | SearchReq t -> Search.print t   
      | GetUserStatsReq t -> 
          Printf.printf "GetUserStats %s" t; print_newline () 
      | JoinRoomReq t -> 
          Printf.printf "JoinRoomReq %s" t; print_newline () 
      | LeaveRoomReq t -> 
          Printf.printf "LeaveRoomReq %s" t; print_newline () 
      | AddUserReq t -> 
          Printf.printf "AddUserReq %s" t; print_newline () 
      | GetPeerAddressReq t -> 
          Printf.printf "GetPeerAddressReq %s" t; print_newline () 
      | CantConnectToPeerReq t -> 
          Printf.printf "CantConnectToPeerReq %s" t; print_newline () 
      | SayChatroomReq (room, msg) -> 
          Printf.printf "SayChatroomReq %s: %s" room msg; print_newline () 
      | UnknownReq (opcode, s) ->  unknown opcode s
          
    let write buf t =
      match t with
      | LoginReq t -> buf_int buf 1; Login.write buf t  
      | SetWaitPortReq t -> buf_int buf 2; SetWaitPort.write buf t  
      | SearchReq t -> buf_int buf 26; Search.write buf t  
      | GetUserStatsReq t -> buf_int buf 36; buf_string buf t
      | JoinRoomReq t -> buf_int buf 14; buf_string buf t
      | LeaveRoomReq t -> buf_int buf 15; buf_string buf t
      | AddUserReq t -> buf_int buf 5; buf_string buf t
      | GetPeerAddressReq t -> buf_int buf 3; buf_string buf t
      | CantConnectToPeerReq t -> buf_int buf 1001; buf_string buf t
      | SayChatroomReq (room, msg) -> 
          buf_int buf 13; buf_string buf room; buf_string buf msg
      | UnknownReq (opcode, s) -> 
          buf_int buf opcode;
          Buffer.add_string buf s
      
  end
  
module S2C = struct
    
    module LoginAck = struct
        type t = 
          Success of string * Ip.t
        | Failure of string
        
        let parse s = 
          match int_of_char s.[0] with
            1 -> 
              let message,pos = get_string s 1 in
              let ip = get_ip s pos in
              Success (message, ip)
          | _ -> 
              let reason,pos = get_string s 1 in
              Failure reason
        
        let print t =
          match t with
            Success (message, ip) ->
              Printf.printf "LOGIN ACK: %s" message;
              print_newline ();
              Printf.printf "   IP: %s" (Ip.to_string ip);
              print_newline ()
          | Failure reason ->
              Printf.printf "LOGIN FAILURE %s" reason;
              print_newline () 
        
        let write buf t =
          match t with
            Success (message, ip) ->
              buf_int8 buf 1;
              buf_string buf message;
              buf_ip buf ip
          | Failure reason -> 
              assert false; (* NOT SURE OF THIS PACKET *)
              buf_string buf reason
      
      end
    
    module RoomList = struct
        type t = (string * int) list
        
        let parse s =
          let names, pos = get_list get_string s 0 in
          let nusers, pos = get_list get_int_pos s pos in
          List.map2 (fun name nusers -> name, nusers) names nusers

(*
          let nrooms = get_int s 0 in
          let room_names = Array.create nrooms "" in
          let room_nusers = Array.create nrooms 0 in
          let rec iter_names nleft pos =
            if nleft = 0 then pos else
            let name, pos = get_string s pos in
            room_names.(nrooms - nleft) <- name;
            iter_names (nleft - 1) pos
          in
          let pos = iter_names nrooms 4 in
          
          let nusers = get_int s pos in
          Printf.printf "nusers = %d/ nrooms = %d" nrooms nusers; 
          print_newline ();
          let rec iter_nusers nleft pos =
            if nleft = 0 then pos else
            let nusers = get_int s pos in
            room_nusers.(nrooms - nleft) <- nusers;
            iter_nusers (nleft - 1) (pos+4)
          in
          let pos = iter_nusers nusers (pos+4) in
          { nrooms = nrooms; room_names = room_names; 
            room_nusers = room_nusers; }
*)
        
        let print t =
          Printf.printf "Room list: %d rooms" (List.length t);
          print_newline ();
          List.iter (fun (name, nusers) ->
              Printf.printf "    %50s  %-10d" name nusers;
              print_newline () 
          ) t
        
        let write buf t =
          buf_list (fun buf (name,_) -> buf_string buf name) buf t;
          buf_list (fun buf (_,nusers) -> buf_int buf nusers) buf t;
      
      end
    
    module PriviledgedUsers = struct
        type t = string list
        
        let parse s =
          let users,pos = get_list get_string s 0 in
          users
        
        let print t =
          Printf.printf "PRIVILEDGED USERS:"; print_newline ();
          List.iter (fun u -> Printf.printf "%s\n" u) t;
          print_newline ()
        
        let write buf t =
          buf_list buf_string buf t
      
      end
    
    module ConnectToPeer = struct
        type t = {
            name : string;
            conn_type : string; (* 'P' *)
            ip : Ip.t;
            port : int;
            token : int;
          }
        
        let parse s =
          let name,pos = get_string s 0 in
          let conn_type, pos = get_string s pos in
          let ip = get_ip s pos in
          let port = get_int s (pos+4) in
          let token = get_int s (pos+8) in
          {
            name = name;
            conn_type = conn_type;
            ip  = ip;
            port = port;
            token = token;
          }
        
        let print t =
          Printf.printf "CONNECT TO PEER %s (%s:%d) token %d"
            t.name (Ip.to_string t.ip) t.port t.token;
          print_newline ()
        
        let write buf t =
          buf_string buf t.name;
          buf_string buf t.conn_type;
          buf_ip buf t.ip;
          buf_int buf t.port;
          buf_int buf t.token
      
      end
    
    
    
    module JoinRoomReply = struct
        
        type user = {
            name : string;
            stats : user_status;
          }
        
        type t = {
            room : string;
            users : user list;
          }
        
        let parse s =
          let room,pos = get_string s 0 in
          let users, pos = get_list get_string s pos in
          let statuses, pos = get_list get_int_pos s pos in
          let stats, pos = get_list get_partial_user_status s pos in
          let slots, pos = get_list get_int_pos s pos in
          List.iter2 (fun u s -> u.status <- s) stats statuses;
          List.iter2 (fun u s -> u.slotsfull <- s) stats slots;
          { room = room; 
            users = List.map2 (fun name stats -> { name = name; stats = stats})
            users stats; }
        
        let print t =
          Printf.printf "JOIN ROOM %s:" t.room; print_newline ();
          List.iter (fun u ->
              Printf.printf "   %s" u.name; print_newline ()) t.users;
          print_newline ()
        
        let write buf t =
          Printf.printf  "******* JoinRoomReply not implemented *****"; 
          print_newline ();
          exit 1
      
      end
    
    
    
    type t = 
    | LoginAckReq of LoginAck.t
    | RoomListReq of RoomList.t
    | PriviledgedUsersReq of PriviledgedUsers.t
    | ConnectToPeerReq of ConnectToPeer.t
    
    | GetPeerAddressReplyReq of 
(* nick *) string * 
(* ip *)   Ip.t * 
(* port *) int
    | AddUserReplyReq of 
(* nick *)    string * 
(* present *) bool
    | UserStatusReq of 
(* nick *)   string * 
(* status *) int
    | JoinRoomReplyReq of JoinRoomReply.t
    | UserJoinedRoomReq of 
(* room *)  string *
(* user *)  string *
(* status *) user_status
    | UserLeftRoomReq of 
(* room *)  string *
(* user *)  string
    | SayChatroomReq of
(* room *)    string *
(* user *)    string *
(* message *) string
    | UnknownReq of int * string

(*
        servercodes = {Login:1,SetWaitPort:2,
                   GetPeerAddress:3,AddUser:5,GetUserStatus:7,SayChatroom:13,
                   JoinRoom:14,LeaveRoom:15,UserJoinedRoom:16,UserLeftRoom:17,
                   ConnectToPeer:18,MessageUser:22,MessageAcked:23,
                   FileSearch:26,GetUserStats:36,QueuedDownloads:40,
                   PlaceInLineResponse:60,RoomAdded:62,RoomRemoved:63,
                   RoomList:64,ExactFileSearch:65,AdminMessage:66, 
                   GlobalUserList:67,TunneledMessage:68,PrivilegedUsers:69,
CantConnectToPeer:1001}


Unknown: opcode 36
ascii: [
  (13)(0)(0)(0) q u a k e r o a t m e a l
  (0)(0)(0)(0)(0)(0)(0)(0)(0)(0)(0)
(0)(0)(0)(0)(0)(1)(0)(0)(0)
  ]

*)
    
    
    
    
    let parse opcode s =
      try
        match opcode with
          1 -> LoginAckReq (LoginAck.parse s)
        | 3 -> 
            let s, pos = get_string s 0 in
            let ip = get_ip s pos in
            let port = get_int s (pos+4) in
            GetPeerAddressReplyReq (s, ip, port)
        | 5 -> 
            let s, pos = get_string s 0 in
            let present = get_int8 s pos in
            AddUserReplyReq (s, present = 1)
        | 7 -> 
            let user, pos = get_string s 0 in
            let status = get_int s pos in
            UserStatusReq (user, status)
        | 13 -> 
            let room_name, pos = get_string s 0 in
            let user_name, pos = get_string s pos in
            let message, pos = get_string s pos in
            SayChatroomReq (room_name, user_name, message)
        
        | 14 -> JoinRoomReplyReq (JoinRoomReply.parse s)
        | 16 ->
            let room, pos = get_string s 0 in
            let user, pos = get_string s pos in
            let status, pos = get_user_status s pos in            
            UserJoinedRoomReq (room, user, status)
        | 17 -> 
            let room, pos = get_string s 0 in
            let user, pos = get_string s pos in
            UserLeftRoomReq (room, user)
        | 18 -> ConnectToPeerReq (ConnectToPeer.parse s)
        | 64 -> RoomListReq (RoomList.parse s)
        | 69 -> PriviledgedUsersReq (PriviledgedUsers.parse s)
        | _ -> raise Not_found
      with
        e -> 
          Printf.printf "From server:"; print_newline ();
          unknown opcode s;
          UnknownReq (opcode, s)
    
    let print t =
      match t with
        LoginAckReq t -> LoginAck.print t  
      | ConnectToPeerReq t -> ConnectToPeer.print t
      | RoomListReq t -> RoomList.print t
      | PriviledgedUsersReq t -> PriviledgedUsers.print t
      | GetPeerAddressReplyReq (name, ip, port) ->
          Printf.printf "GET PEER ADDRESS REPLY %s = %s:%d" name 
            (Ip.to_string ip) port; print_newline ();
      | AddUserReplyReq (name, present) ->
          Printf.printf "ADD USER REPLY %s %b" name present;
          print_newline ();
      | UserStatusReq (user, status) ->
          Printf.printf "USER STATUS %s %d" user status;
          print_newline ();
      | UserJoinedRoomReq (room, user, _) -> 
          Printf.printf "USER JOIN ROOM: %s %s" room user; 
          print_newline ()
      | UserLeftRoomReq (room, user) ->
          Printf.printf "USER LEFT ROOM %s : %s" room user; print_newline ()
      | JoinRoomReplyReq t -> JoinRoomReply.print t
      | SayChatroomReq (room, user, message) ->
          Printf.printf "SAID ON %s BY %s: %s" room user message;
          print_newline ();
      | UnknownReq (opcode, s) ->  unknown opcode s
    
    let write buf t =
      match t with
        LoginAckReq t -> buf_int buf 1; LoginAck.write buf t  
      | RoomListReq t -> buf_int buf 64; RoomList.write buf t
      | PriviledgedUsersReq t -> buf_int buf 69; PriviledgedUsers.write buf t
      | ConnectToPeerReq t -> buf_int buf 18; ConnectToPeer.write buf t
      | GetPeerAddressReplyReq (name, ip, port) ->
          buf_int buf 3;
          buf_string buf name;
          buf_ip buf ip;
          buf_int buf port
      | AddUserReplyReq (name, present) ->
          buf_int buf 5;
          buf_string buf name;
          buf_int8 buf (if present then 1 else 0)
      | UserJoinedRoomReq (room, user, status) -> 
          buf_int buf 16;
          buf_string buf room;
          buf_string buf user;
          buf_user_status buf status
      | JoinRoomReplyReq t ->
          buf_int buf 14;
          JoinRoomReply.write buf t
      | UserLeftRoomReq (room, user) ->
          buf_int buf 17;
          buf_string buf room;
          buf_string buf user
      | UserStatusReq (user, status) ->
          buf_int buf 7;
          buf_string buf user;
          buf_int buf status

      | SayChatroomReq (room, user, message) ->
          buf_int buf 13;
          buf_string buf room;
          buf_string buf user;
          buf_string buf message

      | UnknownReq (opcode, s) -> 
          buf_int buf opcode;
          Buffer.add_string buf s
  
  end
  
  
module C2C = struct

type file = {
    file_code : int;
    file_name : string;
    file_size : int32;
    file_format : string;
    file_tags : (int * int) list;
  }

let get_file s pos =
  let code = get_int8 s pos in
  let name, pos = get_string s (pos+1) in
  let size = get_int32 s pos in
  let size2 = get_int32 s (pos+4) in
  let format, pos = get_string s (pos+8) in
  let tags, pos = get_list (fun s pos ->
        (get_int s pos, get_int s (pos+4)), pos+8) s pos
  in
  {
    file_code = code;
    file_name = name;
    file_size = size;
    file_format = format;
    file_tags = tags;
  }, pos
  

let get_dir s pos =
  let dir, pos = get_string s pos in
  let files, pos = get_list get_file s pos in
  (dir, files), pos
    
    module  SharedFileList = struct
        
        type t = (string * (file list)) list
        
        let parse s = 
          let s = Zlib.uncompress_string s in
          let dirs, pos = get_list get_dir s 0 in
          dirs
      
      end
    
    module FileSearchResult = struct
        
        type t = {
            user : string;
            id : int;
            files : file list;
            freeulslots : int;
            ulspeed : int;
          }
        
        let parse s = 
          let s = Zlib.uncompress_string s in
          let user, pos = get_string s 0 in
          let id = get_int s pos in
          let files, pos = get_list get_file s (pos+4) in
          let freeulslots = get_int8 s pos in
          let ulspeed = get_int s (pos+1) in
(*        let ???? = get_int s (pos+5) in *)
          {
            user = user;
            id = id;
            files = files;
            freeulslots = freeulslots;
            ulspeed = ulspeed;
          }
      end
    
    module FolderContentsReply = struct
        
        type t = (string * (string * file list) list) list
        
        
        let parse s = 
          let s = Zlib.uncompress_string s in
          let folders, pos = get_list (fun s pos ->
                let folder, pos = get_string s pos in
                let dirs, pos = get_list get_dir s pos in
                (folder, dirs), pos) s 0
          in
          folders
          
      end
      
    type t = 
    | GetSharedFileListReq
    | SharedFileListReq of SharedFileList.t
    | FileSearchResultReq of FileSearchResult.t
    | FolderContentsReplyReq of FolderContentsReply.t
    | TransferRequestReq of 
(* download *)   bool *
(* request id *) int *
(* file name *)  string *
(* file size *)  int32
    | TransferReplyReq of 
(* request id *) int *
(* allowed *)    bool *
(* reason *)     string
    | FolderContentsReq of string
    | UnknownReq of int * string
      
    let parse opcode s =
      try
        match opcode with          
        | 4 -> GetSharedFileListReq
        | 5 -> SharedFileListReq (SharedFileList.parse s)
        | 9 -> FileSearchResultReq (FileSearchResult.parse s)
        | 36 -> 
            let dir, pos = get_string s 4 in
            FolderContentsReq dir
        | 37 -> FolderContentsReplyReq (FolderContentsReply.parse s)
        | 40 ->
            let download = get_int s 0 = 0 in
            let req = get_int s 4 in
            let file, pos = get_string s 8 in
            let size = get_int32 s pos in
            TransferRequestReq (download, req, file, size)
        | 41 -> 
            let req = get_int s 0 in
            let allowed = get_int8 s 4 = 1 in
            let reason, pos = get_string s 5 in
            TransferReplyReq (req, allowed, reason)
(*
          | 15 -> UserInfoRequest
          | 16 -> UserInfoReply

              *)
        | _ -> raise Not_found
      with
        e -> 
          Printf.printf "From peer:"; print_newline ();
          unknown opcode s;
          UnknownReq (opcode, s)
    
    let print t =
      match t with
      | GetSharedFileListReq -> 
          Printf.printf "GetSharedFileListReq"; print_newline () 
      | FolderContentsReq folder ->
          Printf.printf "FolderContentsReq"; print_newline ();
      | FolderContentsReplyReq folders ->
          Printf.printf "FolderContentsReplyReq"; print_newline ();
          List.iter (fun (s, dirs) ->
              Printf.printf "  Folder: %s" s; print_newline ();
              List.iter (fun (dir, files) ->
                  Printf.printf "    Directory: %s" dir; print_newline ();
                  List.iter (fun file ->
                      Printf.printf "      %50s%ld" 
                        file.file_name file.file_size; print_newline ();
                  ) files;
              ) dirs
          ) folders
      | TransferRequestReq (download, req, file, size) ->
          Printf.printf "TransferRequestReq %d for %s of %s %ld" req
            (if download then "Download" else "Upload") file size;
          print_newline ();
      | TransferReplyReq (req, allowed, reason) ->
          Printf.printf "TransferReplyReq %d %s for %s" req
            (if allowed then "Allowed" else "Rejected") reason;
          print_newline ();          
      | FileSearchResultReq t ->
          Printf.printf "FileSearchResultReq for %s token %d" 
            t.FileSearchResult.user t.FileSearchResult.id; 
          print_newline ();
          List.iter (fun file ->
              Printf.printf "  %50s%ld" 
              file.file_name file.file_size; print_newline ();
          ) t.FileSearchResult.files;
          
      | SharedFileListReq dirs ->
          Printf.printf "SharedFileListReq"; print_newline ();
          List.iter (fun (dir, files) ->
              Printf.printf "    Directory: %s" dir; print_newline ();
              List.iter (fun file ->
                  Printf.printf "      %50s%ld" 
                  file.file_name file.file_size; print_newline ();
              ) files;
          ) dirs

      | UnknownReq (opcode, s) ->  unknown opcode s
          
    let write buf t =
      match t with
      | GetSharedFileListReq -> buf_int buf 4
      | FolderContentsReq dir -> buf_int buf 36;
          buf_int buf 1; buf_string buf dir
      | FolderContentsReplyReq folders ->
          failwith "write FolderContentsReplyReq not implemented"
          
      | TransferRequestReq (download, req, file, size) ->
          buf_int buf 40;
          buf_int buf (if download then 0 else 1);
          buf_int buf req;
          buf_string buf file;
          buf_int32 buf size

      | TransferReplyReq (req, allowed, reason) ->
          buf_int buf 41;
          buf_int buf 0;
          buf_int8 buf (if allowed then 1 else 0);
          buf_string buf reason

      | FileSearchResultReq t ->
          failwith "write FileSearchResultReq not implemented"
          
      | SharedFileListReq dirs ->
          failwith "write SharedFileListReq not implemented"
          
      | UnknownReq (opcode, s) -> 
          buf_int buf opcode;
          Buffer.add_string buf s
      
  end
  
let soulseek_handler parse f sock nread =
  let b = TcpBufferedSocket.buf sock in
  try
    while b.len >= 4 do
      let msg_len = get_int b.buf b.pos in
      if b.len >= 4 + msg_len then
        begin
          let opcode = get_int b.buf (b.pos+4) in
          let data = String.sub b.buf (b.pos+8) (msg_len-4) in
(*          LittleEndian.dump (String.sub b.buf b.pos (msg_len+4)); *)
          TcpBufferedSocket.buf_used sock (msg_len + 4);
          let t = parse opcode data in
(*          print t; *)
          f t sock
        end
      else raise Not_found
    done
  with Not_found -> ()

        
let buf = Buffer.create 1000
      
let server_msg_to_string t = 
  Buffer.clear buf;
  buf_int buf 0;
  C2S.write buf t;
  let s = Buffer.contents buf in
  let len = String.length s - 4 in
  str_int s 0 len;
  s 
      
let client_msg_to_string t = 
  Buffer.clear buf;
  buf_int buf 0;
  C2C.write buf t;
  let s = Buffer.contents buf in
  let len = String.length s - 4 in
  str_int s 0 len;
  s 

    
let server_send sock t =

  Printf.printf "SENDING TO SERVER:"; print_newline ();
  C2S.print t;
  
  let s = server_msg_to_string t in
  LittleEndian.dump s;
  write_string sock s

    
let client_send sock t =
  Printf.printf "SENDING TO CLIENT:"; print_newline ();
  C2C.print t;
  let s = client_msg_to_string t in
  LittleEndian.dump s;
  write_string sock s

  
let init_peer_connection sock login token =
  Buffer.clear buf;
  buf_int buf 0;
  buf_int8 buf 1;
  buf_string buf login;
  buf_string buf "P";
  buf_int buf token;

  let s = Buffer.contents buf in
  let len = String.length s - 4 in
  str_int s 0 len;
  write_string sock s ;
  
  Printf.printf "INIT PEER CONNECTION:";
  dump s

let init_result_connection sock token =
  Buffer.clear buf;
  buf_int buf 0;
  buf_int8 buf 0;
  buf_int buf token;

  let s = Buffer.contents buf in
  let len = String.length s - 4 in
  str_int s 0 len;
  write_string sock s ;
  
  Printf.printf "INIT RESULT CONNECTION:";
  dump s



  