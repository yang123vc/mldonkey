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
open Options
open Mftp
open Mftp_comm
open DownloadServers
open BasicSocket
open TcpClientSocket
open DownloadOneFile
open DownloadFiles
open DownloadTypes
open DownloadOptions
open DownloadGlobals
open DownloadClient
open Gui_types
  
exception CommandCloseSocket

let result_name r =
  match r.result_names with
    [] -> None
  | name :: _ -> Some name

let search_of_args args =
  incr search_counter;
  let search = {
      search_words = [];
      search_maxsize = None;
      search_minsize = None;
      search_format = None;
      search_avail = None;
      search_media = None;
      search_min_bitrate = None;
      search_title = None;
      search_album = None;
      search_artist = None;
      search_fields = [];
      search_files = Hashtbl.create 127;
      search_num = !search_counter;
      search_nresults = 0;
      search_waiting = List.length !connected_server_list;
      search_string = String2.unsplit args ' ';
      search_handler = (fun _ -> ());
      search_xs_servers = !!known_servers;
    } 
  in
  let rec iter args =
    match args with
      [] -> ()
    | "-minsize" :: minsize :: args ->
        let minsize = Int32.of_string minsize in
        search.search_minsize <- Some minsize;
        iter args
    | "-maxsize"  :: maxsize :: args ->
        let maxsize = Int32.of_string maxsize in
        search.search_maxsize <- Some maxsize;
        iter args
    | "-avail"  :: maxsize :: args ->
        let maxsize = Int32.of_string maxsize in
        search.search_avail <- Some maxsize;
        iter args
    | "-media"  :: filetype :: args ->
        search.search_media <- Some filetype;
        iter args
    | "-Video"  :: args ->
        search.search_media <- Some "Video";
        iter args
    | "-Audio"  :: filetype :: args ->
        search.search_media <- Some "Audio";
        iter args
    | "-format"  :: format :: args ->
        search.search_format <- Some format;
        iter args
    | "-field"  :: field :: format :: args ->
        search.search_fields <- 
          (field, format) :: search.search_fields;
        iter args
    | s :: args ->
        search.search_words <-
          s :: search.search_words;
        iter args
  in
  iter args;
  
  search
  
let last_search = ref []

let forget_search num =  
  if !last_xs = num then last_xs := (-1);
  searches := List.rev (List.fold_left (fun list s ->
        if s.search_num = num then list else s :: list) 
    [] !searches)

let save_file md4 name =
  let real_name = Filename.concat !!incoming_directory name in
  let files = ref [] in
  List.iter (fun file ->
      if file.file_md4 = md4 then begin
          old_files =:= file.file_md4 :: !!old_files;
          file.file_state <- FileRemoved;
          begin
            match file.file_fd with
              None -> ()
            | Some fd -> Unix.close fd; file.file_fd <- None;
          end;
          let old_name = file.file_name in
          (try 
              Sys.rename old_name real_name ;
              file.file_name <- real_name;
            with e -> 
                Printf.printf "Error in rename %s (src [%s] dst [%s])"
                  (Printexc.to_string e) old_name real_name; 
                print_newline ();
          )
          ;
          file.file_changed <- SmallChange;
          !file_change_hook file;
        end 
      else
        files := file :: !files) 
  !!done_files;
  done_files =:= List.rev !files
  
  
let print_search buf s output = 
  last_search := [];
  let counter = ref 0 in
  Printf.bprintf buf "Result of search %d\n" s.search_num;
  Printf.bprintf buf "Reinitialising download selectors\n";
  Printf.bprintf buf "%d results (%s)\n" s.search_nresults 
    (if s.search_waiting = 0 then "done" else
      (string_of_int s.search_waiting) ^ " waiting");
  Hashtbl.iter (fun _ (r, avail) ->
      incr counter;
      Printf.bprintf  buf "[%5d]" !counter;
      if output = HTML then 
        Printf.bprintf buf "\<A HREF=/submit\?q=download\&md4=%s\&size=%s\>"
          (Md4.to_string r.result_md4) (Int32.to_string r.result_size);
      last_search := (!counter, 
        (r.result_size, r.result_md4, result_name r)
      ) :: !last_search;
      List.iter (fun s -> Printf.bprintf buf "%s\n" s) r.result_names;
      if output = HTML then 
        Printf.bprintf buf "\</A HREF\>";
      Printf.bprintf  buf "          %10s %10s " 
        (Int32.to_string r.result_size)
      (Md4.to_string r.result_md4);
      List.iter (fun t ->
          Buffer.add_string buf (Printf.sprintf "%-3s "
              (if t.tag_name = "availability" then string_of_int !avail else
              match t.tag_value with
                String s -> s
              | Uint32 i -> Int32.to_string i
              | Fint32 i -> Int32.to_string i
              | _ -> "???"
            ))
      ) r.result_tags;
      Buffer.add_char buf '\n';
  ) s.search_files
  
let check_shared_files () = 
  let list = ref [] in
  Hashtbl.iter (fun md4 file -> 
      if file.file_shared then
        match file.file_state with
          FileRemoved ->
            if not (Sys.file_exists file.file_name) then begin
                file.file_shared <- false;
                decr nshared_files;
                begin
                  match file.file_fd with
                    None -> ()
                  | Some fd -> 
                      (try Unix.close fd with _ -> ());
                      file.file_fd <- None;
                end;
                file.file_name <- "";
                list := file.file_md4 :: !list;
              end
        | _ -> ()) files_by_md4;
  List.iter (fun md4 ->
      try Hashtbl.remove files_by_md4 md4 with _ -> ()
  ) !list

let load_server_met filename =
  try
    let module S = Files.Server in
    let s = File.to_string filename in
    let ss = S.read s in
    List.iter (fun r ->
        Printf.printf "add server %s:%d" (Ip.to_string r.S.ip) r.S.port;
        print_newline ();
        let server = add_server r.S.ip r.S.port in
        List.iter (fun tag ->
            match tag with
              { tag_name = "name"; tag_value = String s } -> 
                server.server_name <- s;
            |  { tag_name = "description" ; tag_value = String s } ->
                server.server_description <- s
            | _ -> ()
        ) r.S.tags
    ) ss
  with e ->
      Printf.printf "Exception %s while loading %s" (Printexc.to_string e)
      filename;
      print_newline () 
      
let query_download filenames size md4 location old_file absents =
  
  List.iter (fun m -> 
      if m = md4 then raise Already_done) 
  !!old_files;
  
  List.iter (fun file -> 
      if file.file_md4 = md4 then raise Already_done) 
  !!done_files;
  
  List.iter (fun file -> 
      if file.file_md4 = md4 then raise Already_done) 
  !!files;

  let temp_file = Filename.concat !!temp_directory (Md4.to_string md4) in
  begin
    match old_file with
      None -> ()
    | Some filename ->
        if Sys.file_exists filename && not (
            Sys.file_exists temp_file) then
          (try 
              Printf.printf "Renaming from %s to %s" filename
                temp_file; print_newline ();
              Sys.rename filename temp_file with _ -> ());        
  end;
  
  let file = new_file  temp_file md4 size in
  begin
    match absents with
      None -> ()
    | Some absents -> 
        let absents = Sort.list (fun (p1,_) (p2,_) -> p1 <= p2) absents in
        file.file_absent_chunks <- absents;
  end;
  file.file_filenames <- filenames @ file.file_filenames;
  file.file_state <- FileDownloading;
  files =:= file :: !!files;
  !file_change_hook file;
  set_file_size file file.file_size;
  List.iter (fun s ->
      match s.server_sock with
        None -> () (* assert false !!! *)
      | Some sock ->
          query_locations file s sock
  ) !connected_server_list;
  
  (match location with
      None -> ()
    | Some num ->
        try 
          let c = find_client num in
          (match c.client_kind with
              Indirect_location -> 
                if not (List.memq c file.file_indirect_locations) then
                  file.file_known_locations <- c :: 
                  file.file_indirect_locations
            
            | _ -> 
                if not (List.memq c file.file_known_locations) then
                  file.file_known_locations <- c :: 
                  file.file_known_locations
          );
          match c.client_state with
            NotConnected -> 
              connect_client !client_ip [file] c
          | Connected_busy | Connected_idle | Connected_queued ->
              begin
                match c.client_sock with
                  None -> ()
                | Some sock -> 
                    DownloadClient.query_files c sock [file]
              end
          | _ -> ()
        with _ -> ())

let load_prefs filename = 
  try
    let module P = Files.Pref in
    let s = File.to_string filename in
    let t = P.read s in
    t.P.client_tags, t.P.option_tags
  with e ->
      Printf.printf "Exception %s while loading %s" (Printexc.to_string e)
      filename;
      print_newline ();
      [], []
      
  
let import_config dirname =
  load_server_met (Filename.concat dirname "server.met");
  let ct, ot = load_prefs (Filename.concat dirname "pref.met") in
  let temp_dir = ref (Filename.concat dirname "temp") in

  List.iter (fun tag ->
      match tag with
      | { tag_name = "name"; tag_value = String s } ->
          client_name =:=  s
      | { tag_name = "port"; tag_value = Uint32 v } ->
          port =:=  Int32.to_int v
      | _ -> ()
  ) ct;

  List.iter (fun tag ->
      match tag with
      | { tag_name = "temp"; tag_value = String s } ->
          if Sys.file_exists s then (* be careful on that *)
            temp_dir := s
          else (Printf.printf "Bad temp directory, using default";
              print_newline ();)
      | _ -> ()
  ) ot;
  
  let list = Unix2.list_directory !temp_dir in
  let module P = Files.Part in
  List.iter (fun filename ->
      try
        if Filename2.last_extension filename = ".part" then
          let filename = Filename.concat !temp_dir filename in
          let met = filename ^ ".met" in
          if Sys.file_exists met then
            let s = File.to_string met in
            let f = P.read s in
            let filenames = ref [] in
            let size = ref Int32.zero in
            List.iter (fun tag ->
                match tag with
                  { tag_name = "filename"; tag_value = String s } ->
                    Printf.printf "Import Download %s" s; 
                    print_newline ();
                    
                    filenames := s :: !filenames;
                | { tag_name = "size"; tag_value = Uint32 v } ->
                    size := v
                | _ -> ()
            ) f.P.tags;
            query_download !filenames !size f.P.md4 None 
              (Some filename) (Some (List.rev f.P.absents));
      
      with _ -> ()
  ) list
  
let broadcast msg =
  let s = msg ^ "\n" in
  let len = String.length s in
  List.iter (fun sock ->
      TcpClientSocket.write sock s 0 len
  ) !user_socks
  
  
type arg_handler =  Buffer.t -> output_type -> string
type arg_kind = 
  Arg_none of arg_handler
| Arg_multiple of (string list -> arg_handler)
| Arg_one of (string -> arg_handler)
| Arg_two of (string -> string -> arg_handler)
  
let execute_command arg_list buf output cmd args =
  try
    List.iter (fun (command, arg_kind, help) ->
        if command = cmd then
          Buffer.add_string buf (
            match arg_kind, args with
              Arg_none f, [] -> f buf output
            | Arg_multiple f, _ -> f args buf output
            | Arg_one f, [arg] -> f arg buf output
            | Arg_two f, [a1;a2] -> f a1 a2 buf output
            | _ -> "Bad number of arguments"
          )
    ) arg_list
  with Not_found -> ()
      
let print_file buf file =
  
  Printf.bprintf buf "[%-5d] %s %10s %32s %s" 
    file.file_num
    (first_name file)
  (Int32.to_string file.file_size)
  (Md4.to_string file.file_md4)
    (if file.file_state = FileDownloaded then
      "done" else
      Int32.to_string file.file_downloaded);
  Buffer.add_char buf '\n';
  Printf.bprintf buf "Connected clients:\n";
  List.iter (fun c ->
      if c.client_state <> NotConnected then
        match c.client_kind with
          Known_location (ip, port) ->
            Printf.bprintf  buf "[%-5d] %12s %-5d    %s\n"
              c.client_num
              (Ip.to_string ip)
            port
            (match c.client_sock with
                None -> ""
              | Some _ -> "Connected")
        | _ ->
            Printf.bprintf  buf "[%-5d] %12s            %s\n"
              c.client_num
              "indirect"
              (match c.client_sock with
                None -> ""
              | Some _ -> "Connected")
  ) (file.file_known_locations @ file.file_indirect_locations)
      
let simple_print_file buf file =
  
  Printf.bprintf buf "[%-5d] %s %10s %32s %s" 
    file.file_num
    (first_name file)
  (Int32.to_string file.file_size)
  (Md4.to_string file.file_md4)
    (if file.file_state = FileDownloaded then
      "done" else
      Int32.to_string file.file_downloaded);
  Buffer.add_char buf '\n'

let commands = [
    "n", Arg_multiple (fun args buf _ ->
        let ip, port =
          match args with
            [ip ; port] -> ip, port
          | [ip] -> ip, "4663"
          | _ -> failwith "n <ip> [<port>]: bad argument number"
        in
        let ip = Ip.of_string ip in
        let port = int_of_string port in
        
        let s = add_server ip port in
        Printf.bprintf buf "New server %s:%d\n" 
          (Ip.to_string s.server_ip) 
        s.server_port;
        ""
    ), " <ip> [<port>]: add a server";
    
    "vu", Arg_none (fun buf _ ->
        Printf.sprintf "Upload credits : %d minutes\nUpload disabled for %d minutes" !upload_credit !has_upload;
    
    ), " : view upload credits";
    
    "nu", Arg_one (fun num buf _ ->
        let num = int_of_string num in
        if num <= !upload_credit then
          begin
            upload_credit := !upload_credit - num;
            has_upload := !has_upload + num;
            Printf.sprintf "upload disabled for %d minutes" num
          end
        else 
          "not enough upload credits"
    
    
    ), " <m> : disable upload during <m> minutes (multiple of 5)";
    
    "import", Arg_one (fun dirname buf _ ->
        
        try
          import_config dirname;
          "config loaded"
        with e ->
            Printf.sprintf "error %s while loading config" (
              Printexc.to_string e)
    ), " <dirname> : import the config from dirname";
    
    "x", Arg_one (fun num buf _ ->
        try
          let num = int_of_string num in
          let s = Hashtbl.find servers_by_num num in
          match s.server_sock with
            None -> "Not connected"
          | Some sock ->
              shutdown sock "user disconnect";
              "Disconnected"
        with e ->
            Printf.sprintf "Error: %s" (Printexc.to_string e)
    ), " <num> : disconnect from server";
    
    "servers", Arg_one (fun filename buf _ ->
        try
          load_server_met filename;
          "file loaded"
        with e -> 
            Printf.sprintf "error %s while loading file" (Printexc.to_string e)
    ), " <filename> : add the servers from a server.met file";
    
    "commit", Arg_none (fun buf _ ->
        List.iter (fun file ->
            save_file file.file_md4 (first_name file)
        ) !!done_files;
        "commited"
    ) , ": move downloaded files to incoming directory";
    
    "vd", Arg_multiple (fun args buf _ -> 
        match args with
          [arg] ->
            let num = int_of_string arg in
            
            List.iter (fun file ->
                if file.file_num = num then print_file buf file
            )  !!files;
            List.iter (fun file ->
                if file.file_num = num then print_file buf file
            )  !!done_files;
            ""
        | _ ->
            Printf.bprintf  buf "Downloading %d files\n" (List.length !!files);
            
            List.iter (simple_print_file buf) !!files;
            Printf.bprintf  buf "Downloaded %d files\n" (
              List.length !!done_files);
            List.iter (simple_print_file buf) !!done_files;
            if !!done_files = [] then "" else
              "Use 'commit' to move downloaded files to the incoming directory"
    
    ), "<num>: view file info";

    "recover_temp", Arg_none (fun buf _ ->
        let files = Unix2.list_directory !!temp_directory in
        List.iter (fun filename ->
            if String.length filename = 32 then
              try
                let md4 = Md4.of_string filename in
                try
                  ignore (Hashtbl.find files_by_md4 md4)
                with Not_found ->
                    let size = Unix32.getsize32 (Filename.concat 
                          !!temp_directory filename) in
                    query_download [] size md4 None None None
              with e ->
                  Printf.printf "exception %s in recover_temp"
                    (Printexc.to_string e); print_newline ();
        ) files;
        "done"
    ), " : recover lost files from temp directory";
    
    "reshare", Arg_none (fun buf _ ->
        check_shared_files ();
        "check done"
    ), " : check shared files for removal";
    
    "vm", Arg_none (fun buf _ ->
        Printf.bprintf  buf "Connected to %d servers\n" (List.length !connected_server_list);
        List.iter (fun s ->
            Printf.bprintf buf "[%-5d] %s:%-5d  "
              s.server_num
              (Ip.to_string s.server_ip) s.server_port;
            List.iter (fun t ->
                Printf.bprintf buf "%-3s "
                  (match t.tag_value with
                    String s -> s
                  | Uint32 i -> Int32.to_string i
                  | Fint32 i -> Int32.to_string i
                  | _ -> "???"
                )
            ) s.server_tags;
            Printf.bprintf buf " %6d %7d" s.server_nusers s.server_nfiles;
            Buffer.add_char buf '\n'
        ) !connected_server_list;
        ""), ": list connected servers";
    
    "vma", Arg_none (fun buf _ ->
        let list = DownloadServers.all_servers ()
        
        in        
        Printf.bprintf  buf "Servers: %d known\n" (List.length list);
        List.iter (fun s ->
            Printf.bprintf buf "[%-5d] %s:%-5d  "
              s.server_num
              (Ip.to_string s.server_ip) s.server_port;
            List.iter (fun t ->
                Printf.bprintf buf "%-3s "
                  (match t.tag_value with
                    String s -> s
                  | Uint32 i -> Int32.to_string i
                  | Fint32 i -> Int32.to_string i
                  | _ -> "???"
                )
            ) s.server_tags;
            (match s.server_sock with
                None -> ()
              | Some _ ->
                  Printf.bprintf buf " %6d %7d" s.server_nusers s.server_nfiles);
            Buffer.add_char buf '\n'
        ) list; ""), ": list all known servers";
    
    "q", Arg_none (fun buf _ ->
        raise CommandCloseSocket
    ), ": close telnet";
    
    "kill", Arg_none (fun buf _ ->
        exit_properly ();
        "exit"), ": save and kill the server";
    
    "save", Arg_none (fun buf _ ->
        force_save_options ();
        "saved"), ": save";
    
    "d", Arg_multiple (fun args buf _ ->
        try
          let (size, md4, name) =
            match args with
            | [size; md4] -> (Int32.of_string size),(Md4.of_string md4), None
            | [size; md4; name] -> 
                (Int32.of_string size),(Md4.of_string md4), Some name
            | [num] -> 
                List.assoc (int_of_string num) !last_search
            | _ -> failwith "Bad number of arguments"
          in
          query_download [] size md4 None None None;
          "download started"
        with 
          Already_done -> "already done"
        | Not_found ->  "not found"
        | Failure s -> s
    ), "<size> <md4> : download this file";
    
    "upstats", Arg_none (fun buf _ ->
        Printf.bprintf buf "Upload statistics:\n";
        Printf.bprintf buf "Total: %d blocks uploaded\n" !upload_counter;
        let list = ref [] in
        Hashtbl.iter (fun _ file ->
            if file.file_shared then 
              list := file :: !list
        ) files_by_md4;
        let list = Sort.list (fun f1 f2 ->
              f1.file_upload_requests >= f2.file_upload_requests)
          
          !list in
        List.iter (fun file ->
            Printf.bprintf buf "%-50s requests: %8d blocs: %8d\n"
              (first_name file) file.file_upload_requests
              file.file_upload_blocks;
        ) list;
        "done"
    ), " : statistics on upload";
    
    "port", Arg_one (fun arg buf _ ->
        port =:= int_of_string arg;
        "new port will change at next restart"),
    " <port> : change connection port";
    
    "vo", Arg_none (fun buf _ ->
        List.iter (fun (name, value) ->
            Printf.bprintf buf "%s = %s\n" name value)
        (Options.simple_options downloads_ini);
        ""
    ), " : print options";
    
    "set", Arg_two (fun name value buf _ ->
        try
          Options.set_simple_option downloads_ini name value;
          "option value changed"
        with e ->
            Printf.sprintf "Error %s" (Printexc.to_string e)
    ), " <option_name> <option_value> : change option value";
    
    "vr", Arg_multiple (fun args buf output ->
        match args with
          num :: _ -> 
            let num = int_of_string num in
            List.iter (fun s ->
                if s.search_num = num then
                  print_search buf s output
            ) !searches;
            ""
        | [] ->   
            match !searches with 
              s :: _ ->
                print_search buf s output;
                ""
            | _ -> 
                "no searches done\n"
    ), "  [<num>]: view results of a search";
    
    "forget", Arg_one (fun num buf _ ->
        let num = int_of_string num in
        forget_search num;
        ""  
    ), " <num> : forget search <num>";
    
    "ls", Arg_multiple (fun args buf _ ->
        let search = search_of_args args in
        searches := search :: !searches;
        DownloadIndexer.find search;
        "local search started"
    ), " <query> : local search";
    
    "s", Arg_multiple (fun args buf _ ->
        if !connected_server_list = [] then 
          "not connected" else
          begin
            let search = search_of_args args in
            let query = make_query search in
            last_xs := search.search_num;
            searches := search :: !searches;
            List.iter (fun s ->
                match s.server_sock with
                  None -> ()
                | Some sock ->
                    
                    let module M = Mftp_server in
                    let module Q = M.Query in
                    server_send sock (M.QueryReq query);
                    Fifo.put s.server_search_queries (
                      fun s  _ t -> search_handler search t)
            ) !connected_server_list;
            make_xs search;
            Printf.bprintf buf "Query %d Sent to %d\n"
              search.search_num (List.length !connected_server_list);
            ""
          end), " <query> : search for files\n
\tWith special args:
\t-minsize <size>
\t-maxsize <size>
\t-media <Video|Audio|...>
\t-Video
\t-Audio
\t-format <format>
\t-field <field> <fieldvalue> :
";
        
    "vs", Arg_none (fun buf _ ->
      Printf.bprintf  buf "Searching %d queries\n" (List.length !searches);
      List.iter (fun s ->
          Printf.bprintf buf "[%-5d] %s %s\n" s.search_num s.search_string
            (if s.search_waiting = 0 then "done" else
              string_of_int s.search_waiting)
        ) !searches; ""), ": view all queries";

    "cancel", Arg_multiple (fun args buf _ ->
        List.iter (fun num ->
            let num = int_of_string num in
            List.iter (fun file ->
                if file.file_num = num then remove_file file.file_md4
            ) !!files) args; ""
    ), " <num> : cancel download";

    "xs", Arg_none (fun buf _ ->
        if !last_xs >= 0 then begin
            try
              let ss = DownloadFiles.find_search !last_xs in
              make_xs ss;
              "extended search done"
            with e -> Printf.sprintf "Error %s" (Printexc.to_string e)
          end else "No previous extended search"),
    ": extended search";

    "clh", Arg_none (fun buf _ ->
        DownloadIndexer.clear ();
        "local history cleared"
    ), " : clear local history";
    
    "c", Arg_multiple (fun args buf _ ->
        match args with
          [] ->
            force_check_server_connections true;
            "connecting more servers"
        | _ ->
            List.iter (fun num ->
                let num = int_of_string num in
                let s = Hashtbl.find servers_by_num num in
                connect_server s
            ) args;
            "connecting server"
    ),
    " [<num>]: connect to more servers (or to server <num>)";
    
      
  ]

let eval auth buf cmd output =
  let l = String2.tokens cmd in
  match l with
    [] -> ()
  | cmd :: args ->
      if cmd = "help" || cmd = "?" then begin
          Printf.bprintf  buf "Available commands are:\n";
          List.iter (fun (cmd, _, help) ->
              Printf.bprintf  buf "%s %s\n" cmd help) commands
        end else
      if cmd = "q" then
        raise CommandCloseSocket
      else
      if cmd = "auth" then
        let arg_password =
          match args with
            [] -> ""
          | s1 :: _ -> s1
        in
        if !!password = arg_password then begin
            auth := true;
            Printf.bprintf buf "Full access enabled"
          end else
          Printf.bprintf buf "Bad login/password"
      else
      if !auth then
        execute_command commands buf output cmd args      
      else
          Printf.bprintf buf "Command not authorized\n Use 'auth <password>' before."

(* The telnet client *)
        
let buf = Buffer.create 1000

let user_reader auth sock nread  = 
  let b = TcpClientSocket.buf sock in
  let end_pos = b.pos + b.len in
  let new_pos = end_pos - nread in
  for i = new_pos to end_pos - 1 do
    let c = b.buf.[i] in
    if c = '\n' || c = '\r' || c = '\000' then 
      let len = i - b.pos in
      let cmd = String.sub b.buf b.pos len in
      buf_used sock (len+1);
      try
        Buffer.clear buf;
        eval auth buf cmd TEXT;
        Buffer.add_char buf '\n';
        TcpClientSocket.write_string sock (Buffer.contents buf)
      with
        CommandCloseSocket ->
          (try
              shutdown sock "user quit";
          with _ -> ());
      | e ->
          TcpClientSocket.write_string sock
            (Printf.sprintf "exception [%s]\n" (Printexc.to_string e));
          
  done
  
let user_closed sock  msg =
  user_socks := List2.removeq sock !user_socks;
  ()
  
let telnet_handler t event = 
  Printf.printf "CONNECTION FROM REMOTE USER"; print_newline ();
  match event with
    TcpServerSocket.CONNECTION (s, Unix.ADDR_INET (from_ip, from_port)) ->
      
      let sock = TcpClientSocket.create_simple s in
      let auth = ref (!!password = "") in
      TcpClientSocket.set_reader sock (user_reader auth);
      TcpClientSocket.set_closer sock user_closed;
      user_socks := sock :: !user_socks;
      TcpClientSocket.write_string sock "\nWelcome on mldonkey command-line\n";
      TcpClientSocket.write_string sock "\nUse ? for help\n\n";
  | _ -> ()

(* The HTTP client *)

let buf = Buffer.create 1000
      
open Http_server

let add_submit_entry buf =
  Buffer.add_string buf
    "<form action=\"submit\">
<table width=\"100%\" border=0>
<tr>
<td width=\"1%\"><input type=text name=q size=40 value=\"\"></td>
<td align=left><input type=submit value=\"Execute\"></td>
</tr>
</table>
</form>
"

let add_simple_commands buf =
  Buffer.add_string buf
  "
  <h2>Connected to <a href=http://go.to/mldonkey> MLdonkey </a> 
WEB server</h2>
<br>
<table width=\"100%\" border=0>
<tr>
  <td><a href=/submit?q=vm> View Connected Servers </a></td>
  <td><a href=/submit?q=vma> View All Servers </a></td>
  <td><a href=/submit?q=c> Connect More Servers </a></td>
  <td><a href=/submit?q=xs> Extended Search </a></td>
  <td><a href=/submit?q=upstats> Upload Statistics </a></td>
  </tr>
  </table>  
<table width=\"100%\" border=0>
<tr>
<td><a href=/submit?q=vr> View Results </a></td>
<td><a href=/submit?q=vd> View Downloads </a></td>
<td><a href=/submit?q=commit> Commit Downloads </a></td>
<td><a href=/submit?q=vs> View Searches </a></td>
<td><a href=/submit?q=vo> View Options </a></td>
<td><a href=/submit?q=help> View Help </a></td>
  </tr>
  </table>
<br>
"
  
  
let http_handler t r =
  Buffer.clear buf;  
  if (!!http_password <> "" || !!http_login <> "") &&
    (r.options.passwd <> !!http_password || r.options.login <> !!http_login)
  then begin
      need_auth buf "MLdonkey"
    end
  else
    begin
      Buffer.add_string  buf "HTTP/1.0 200 OK\r\n";
      Buffer.add_string  buf "Server: MLdonkey\r\n";
      Buffer.add_string  buf "Connection: close\r\n";
      Buffer.add_string  buf "Content-Type: text/html; charset=iso-8859-1\r\n";
      Buffer.add_string  buf "\r\n";
      

      add_simple_commands buf;
      try
        match r.get_url.Url.file with
          "/" -> 
            add_submit_entry buf
        | "/submit" ->
            begin
              match r.get_url.Url.args with
                ["q", cmd ] ->
                  add_submit_entry buf;
                  let s = 
                    let b = Buffer.create 10000 in
                    eval (ref true) b cmd HTML;
                    html_escaped (Buffer.contents b)
                  in
                  Printf.bprintf buf  "\n<pre>\n%s\n</pre>\n" s;
                  
              | [ "q", "download"; "md4", md4_string; "size", size_string ] ->
                  
                  query_download [] (Int32.of_string size_string)
                  (Md4.of_string md4_string) None None None;
                  Printf.bprintf buf  "\n<pre>\nDownload started\n</pre>\n";
              | args -> 
                  List.iter (fun (s,v) ->
                      Printf.printf "[%s]=[%s]" (String.escaped s) (String.escaped v);
                      print_newline ()) args;
                  
                  raise Not_found
            end
        | _ -> raise Not_found
      with e ->
          Printf.bprintf buf "\nException %s\n" (Printexc.to_string e);
    end;
  
  let s = Buffer.contents buf in
  let len = String.length s in
  TcpClientSocket.set_max_write_buffer t (len + 100);
  TcpClientSocket.write t s 0 len;
  TcpClientSocket.close_after_write t
        
      
  
let create_http_handler () = 
  create {
    port = !!http_port;
    requests = [];
    addrs = [];
    base_ref = "";
    default = http_handler;
  }