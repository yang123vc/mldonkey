(* Copyright 2002 b8_bavard, b8_fee_carabine, INRIA *)
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

open CommonOptions
open Unix
open TcpBufferedSocket
open DonkeyMftp
open Options
open Mftp_comm
open ServerTypes
open CommonComplexOptions
open CommonNetwork
open CommonServer
  
let server_ini = create_options_file (
    Filename.concat file_basedir "server.ini")
  
let server_port = define_option server_ini ["port"] "port to bind on"
  int_option 4661
let server_name = define_option server_ini ["name"] "small name of server"
    string_option  "mldonkey"
let server_desc = define_option server_ini ["description"] 
  "small description of server" string_option "mldonkey general server"
let welcome_messages = define_option server_ini ["welcome"]
  "list of welcome messages"
  (list_option string_option) [ "Welcome to my mldonkey server" ]
let seed_ip = define_option server_ini ["seedIP"] "IP of server to register"
    (option_option Ip.option) None
let seed_port = define_option server_ini ["seedPort"]
  "Port of server to register" int_option 4661
let max_clients = define_option server_ini ["maxClients"] 
  "Maximal number of clients connected" int_option 200
let max_files = define_option server_ini ["maxFiles"]
  "Maximal number of files connected" int_option 1000
let server_ip = define_option server_ini ["server_ip"] 
    "The last IP used for this server" Ip.option  
    (Ip.my ())
let server_md4 = define_option server_ini ["server_md4"]
  "The MD4 of this server" Md4.option (Md4.random ())

(*Log options*)
let save_log = define_option server_ini ["save_log"]
  "Save all request on a file log" bool_option false
let log_time_out = define_option server_ini ["log_time_out"] 
"time for write on disk logs" float_option 10.
let change_log_file = define_option server_ini ["change_log_file"] "change log file" float_option 21600.
  
  

(*based server option*)
let send_server_stat_delay = define_option server_ini ["send_server_stat_delay"] "time
to wait" float_option 120.
  
let ping_known_servers = define_option server_ini ["ping_known_servers"] "time to ping knowed server"
    float_option 1800.

(*Options for cooperation server protocol*) 
let relais_cooperation_protocol = define_option server_ini
["relais_cooperation_protocol"] "Your server will participate in a groupe of
server" bool_option false

let relais_master = define_option server_ini ["relais_master"] "Your server will
be a master of a group" bool_option false

let max_servers = define_option server_ini ["max_servers"] "Only use if you are a sever master" int_option 5

let max_group_clients = define_option server_ini ["max_group_clients"] "max number of clients in the groupe. if you are a master then the group doesn't support more clients else you can't merge a groupe with a upper bound value" int_option 5000

let max_group_files = define_option server_ini ["max_group_files"] "max number of file in the groupe. The group doesn't support more files" int_option 500
  
let notify_time_out = define_option server_ini ["notify_time_out"] "notify other server about your location modification"
float_option 20.

let connect_time_out = define_option server_ini ["connect_time_out"] "connect deconnect servers"
float_option 5.

let server_dead_time_out = define_option server_ini ["server_dead_time_out"] "Consider a server as dead"
float_option 500.

let server_group_connection_timeout = define_option server_ini ["server_group_connection_timeout"] "time to wait before consider server dead"
float_option 3. 

let known_master =  define_option server_ini ["known_master"]
  "Known_master" (list_option (tuple2_option (Ip.option, int_option)))
  []

  (*
let known_server = define_option server_ini ["known_server"]
  "Known server" (list_option (tuple2_option (Ip.option, int_option)))
  []
*)



  
