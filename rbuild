#!/usr/bin/env shpp

DATABASE_NAME = ".rbuild.db"

func msg_err(msg...) {
  RED = "\033[0;31m"
  NC = "\033[0m" # No Color

  print(RED, array(msg).join(), NC)
}

func create_database(database_name) {
  query = "create table files(file_path varchar(1024), "+
          "last_modified datetime, primary key(file_path));"

  query += "create table servers(name varchar(64), "+
           "addr varchar(1024), user varchar(128), "+
           "path varchar(1024), pem varchar(1024), "+
           "args varchar(1024), last_build datetime, "+
           "primary key(name));"

  query += "create table cmds(name varchar(64), "+
           "line varchar(1024), primary key(name));"

  query += "create table info(key varchar(64), "+
           "value varchar(1024), primary key(key));"

  sqlite3 ${database_name} <<< query
}

func change_dir(dir) {
  cd ${dir}
}

func search_main_file(file_name) {
  current_dir = path.pwd()

  defer change_dir(current_dir)

  while $(pwd) != "/" {
    if file_name in $(ls -a) {
      return path.pwd() + "/" + file_name
    }

    cd ..
  }

  print(file_name, " don't exists")
  exit 1
}

func count_servers(database_name) {
  query = "select count(*) from servers;"

  res = $(sqlite3 ${database_name} <<< query)
  return int(res.out())
}

func list_track_files(database_name) {
  query = "select file_path from files;"

  res = $(sqlite3 ${database_name} <<< query)

  if res.out() != "" {
    return array(res)
  } else {
    return null
  }
}

func print_list_track_files(database_name) {
  files = list_track_files(database_name)

  if files == null {
    return
  } else {
    for f in files {
      print(f)
    }
  }
}

func file_datetime(file) {
  datetime =  $(stat -c %y ${file})
  return datetime.out().split(".")[0]
}

func git_root_dir() {
  return $(git rev-parse --show-toplevel).out()
}

# list files tracked by git and files in the database
# make the intersection between both, and remove
# from git files array all files that is already
# on the database
func list_git_files(database_name) {
  query = "select file_path from files;"
  res = $(sqlite3 ${database_name} <<< query)

  track_files = array(res)

  current_dir = path.pwd()
  root_dir = git_root_dir()

  cd ${root_dir}

  git_files = array($(git ls-files))
  files = []

  for f in git_files {
    files.append(root_dir + "/" + f)
  }

  for f in track_files {
    files.remove(f)
  }

  cd ${current_dir}
  return files
}

func add_git_files(database_name, git_files) {
  for f in git_files {
    query = "insert into files values('" + f + "', '"+
            file_datetime(f) + "');"
    sqlite3 ${database_name} <<< query
  }
}

func add_file(database_name, str_file) {
  files = glob(str_file)

  for f in files {
    file = path($(pwd).out() + "/" + f)
    file = file.absolute()

    query = "insert into files values('" + file + "', '"+
            file_datetime(file) + "');"
    sqlite3 ${database_name} <<< query
  }
}

func remove_file(database_name, str_file) {
  query = "delete from files where file_path='" + str_file + "';"
  sqlite3 ${database_name} <<< query
}

func add_server(database_name, map_args) {
  if !map_args.exists("--name") {
    print("name not set")
    exit 1
  }

  if !map_args.exists("--addr") {
    print("addr not set")
    exit 1
  }

  name = map_args["--name"]
  addr = map_args["--addr"]
  user = ""
  path_srv = ""
  pem = ""
  args = ""

  if map_args.exists("--user") {
    user = map_args["--user"]
  }

  if map_args.exists("--path-srv") {
    path_srv = map_args["--path-srv"]
  }

  if map_args.exists("--pem") {
    path_srv = map_args["--pem"]
  }

  if map_args.exists("--args") {
    path_srv = map_args["--args"]
  }

  query = "insert into servers values('" + name + "', '"+
           addr + "','" + user + "','" + path_srv + "','" +
           pem + "','" + args + "', '');"

  sqlite3 ${database_name} <<< query
}

func remove_server(database_name, server_name) {
  query = "delete from servers where name=''" + server_name + ";"

  sqlite3 ${database_name} <<< query
}

func list_servers(database_name) {
  query = "select name, addr from servers;"

  res = $(sqlite3 ${database_name} <<< query)

  for f in res {
    print(f)
  }
}

func server_args(argv) {
  map_args = {}
  last_key = ""

  for a in argv {
    if a[0] == "-" {
      last_key = a[1:]
    } else {
      map_args[last_key] = a
    }
  }

  return map_args
}

func add_cmd(database_name, cmd_name, cmd_line) {
  query = "insert into cmds values('" + cmd_name + "', '"+
           cmd_line + "');"

  sqlite3 ${database_name} <<< query
}

func remove_cmd(database_name, cmd_name) {
  query = "delete from cmds where name ='" + cmd_name + "';"

  sqlite3 ${database_name} <<< query
}

func select_cmd(database_name, cmd_name) {
  query = "select name, line from cmds where name='" + cmd_name + "';"

  res = $(sqlite3 ${database_name} <<< query)

  if res.out() == "" {
    print("command: '", cmd_name, "' not found")
    exit 1
  }

  str_cmd = string(res).split("|")
  return str_cmd[1]
}

func get_server_last_build(database_name, server = null) {
  query = "select * from files;"
  res_files = $(sqlite3 ${database_name} <<< query)
  last_build = null

  if server == null {
    query = "select last_build from servers;"
    res_server = $(sqlite3 ${database_name} <<< query)

    num_servers = count_servers(database_name)

    if num_servers > 1 {
      print("server must be specified")
      exit 1
    } else if num_servers == 1 {
      last_build = res_server.out()
    } else {
      print("no server found")
      exit 1
    }
  } else {
    query = "select last_build from servers where name='" + server + "';"
    res_server = $(sqlite3 ${database_name} <<< query)

    if (res_server.out() != "") {
      last_build = res_server.out()
    } else {
      print("server " + server + " not found")
      exit 1
    }
  }

  return last_build
}

class Date {
  func __init__(v) {
    datetime = v.split(" ");
    date = datetime[0]
    time = datetime[1]

    date = date.split("-")
    this.year = int(date[0])
    this.month = int(date[1])
    this.day = int(date[2])

    time = time.split(":")
    this.hour = int(time[0])
    this.min = int(time[1])
    this.sec = int(time[2])
  }

  func equal(date) {
    b = this.year == data.year && this.month == data.month &&
        this.day == data.day && this.hour == data.hour &&
        this.min == data.min && this.sec == data.sec

    return b
  }

  func lesser(date) {
    if this.year < date.year {
      return true
    } else if this.year > date.year {
      return false
    } else if this.month < date.month {
      return true
    } else if this.month > date.month {
      return false
    } else if this.day < date.day {
      return true
    } else if this.day > date.day {
      return false
    } else if this.hour < date.hour {
      return true
    } else if this.hour > date.hour {
      return false
    } else if this.min < date.min {
      return true
    } else if this.min > date.min {
      return false
    } else if this.sec < date.sec {
      return true
    } else if this.sec > date.sec {
      return false
    } else {
      return false
    }
  }

  func __eq__(date) {
    return this.equal(date)
  }

  func __lt__(date) {
    return this.lesser(date)
  }

  func __gt__(date) {
    return !this.lesser(date)
  }

  func __print__() {
    return string(this.year) + "-" + string(this.month) + "-" +
           string(this.day) + " " + string(this.hour) + ":" +
           string(this.min) + ":" + string(this.sec)
  }
}

func get_files_to_send(database_name, last_build) {
  track_files = list_track_files(database_name)

  date_build = Date(last_build)
  print("date build: ", date_build)

  arr_files = []
  for file in track_files {
    date_file = Date(file_datetime(file))
    print(date_file)

    if date_build < date_file {
      arr_files.append(file)
    }
  }

  return arr_files
}

func print_files_to_send(database_name, last_build) {
  files = get_files_to_send(database_name, last_build)

  for file in files {
    print(file)
  }
}

func update_server_last_build(database_name, server = null) {
  now = $(date +"%Y-%m-%d %H:%M:%S")

  if count_servers(database_name) == 1 {
    query = "update servers set last_build='" + now + "';"
    sqlite3 ${database_name} <<< query
  } else {
    if server == null {
      exit 1
    }

    query = "update servers set last_build='" + now + "' where name='" +
        server + "';"
    sqlite3 ${database_name} <<< query
  }
}

func server_data(database_name, server = null) {
  query = ""

  if count_servers(database_name) == 1 {
    query = " from servers;"
  } else {
    if server == null {
      exit 1
    }

    query = " from servers where name='" + server + "';"
  }

  # user
  query_user = "select user" + query
  res_server = $(sqlite3 ${database_name} <<< query_user)
  user = string(res_server)

  # addr
  query_addr = "select addr" + query
  res_server = $(sqlite3 ${database_name} <<< query_addr)
  addr = string(res_server)

  # pem
  query_pem = "select pem" + query
  res_server = $(sqlite3 ${database_name} <<< query_pem)
  pem = string(res_server)

  # sshpath
  query_path = "select path" + query
  res_server = $(sqlite3 ${database_name} <<< query_path)
  sshpath = string(res_server)

  return user, addr, pem, sshpath
}

func scp_cmd(database_name, server = null) {
  user, addr, pem, sshpath = server_data(database_name, server)

  scp_args = []
  last_build = get_server_last_build(database_name)
  files_send = get_files_to_send(database_name, last_build)
  scp_args.extend(files_send)
  print(files_send)

  if pem != "" {
    scp_args.append("-i")
    scp_args.append(pem)
  }

  addr = user + "@" + addr + ":" + sshpath
  scp_args.append(addr)

  scp ${scp_args}
}

func ssh_cmd(database_name, cmd_content, server = null) {
  user, addr, pem, sshpath = server_data(database_name, server)

  ssh_args = []
  addr = user + "@" + addr + ":" + sshpath
  ssh_args.append(addr)
  ssh_args.append("bash -s")

  ssh ${ssh_args} << ${cmd_content}
}

func exec_cmd(database_name, cmd_name, server = null) {
  # send files the was modified since last build
  scp_cmd(database_name, server)

  # get command content
  cmd_content = select_cmd(db_name, cmd_name)

  # send the command
  ssh_cmd(database_name, cmd_content, server)

  # update data of last build
  update_server_last_build(database_name)
}

func handle_args(argv) {
  switch argv[0] {
    case "init" {
      create_database(DATABASE_NAME)
    }

    case "add-git" {
      db_name = search_main_file(DATABASE_NAME)
      files = list_git_files(db_name)
      add_git_files(db_name, files)
    }

    case "ls" {
      db_name = search_main_file(DATABASE_NAME)
      print_list_track_files(db_name)
    }

    case "add" {
      if len(argv) < 2 {
        print("not file")
        exit 1
      }

      db_name = search_main_file(DATABASE_NAME)
      add_file(db_name, argv[1])
    }

    case "rm" {
      db_name = search_main_file(DATABASE_NAME)
      if argv[0][0] == "@" {
        remove_server(db_name, argv[0][1:])
      } else if argv[0][0] == ">" {
        remove_cmd(db_name, argv[0][1:])
      } else {
        remove_file(db_name, argv[0])
      }
    }

    case "add-server" {
      if len(argv) < 2 {
        print("no arguments for server options")
        exit 1
      }

      db_name = search_main_file(DATABASE_NAME)
      add_server(db_name, server_args(argv[1:]))
    }

    case "ls-servers" {
      db_name = search_main_file(DATABASE_NAME)
      list_servers(db_name)
    }

    case "cmd" {
       if len(argv) < 3 {
        print("commands arguments not correct")
        exit 1
      }

      db_name = search_main_file(DATABASE_NAME)
      add_cmd(db_name, argv[1], argv[2])
    }

    default {
      if len(argv) < 2 {
        print("command not not specified")
        exit 1
      }

      db_name = search_main_file(DATABASE_NAME)

      # check if the first is a server name
      if argv[0][0] == "@" {
        server_name = argv[0][1:]
        exec_cmd(db_name, argv[1], server_name)
      } else {
        exec_cmd(db_name, argv[1], server_name)
      }
    }
  }
}

func usage() {
  print("usage: rbuild [--version] [--help]")
  print("              <command> [<args>]")
  print("")
  print("start a working area")
  print("   init         Create database of rbuild, must be on the root of the project")
  print("")
  print("work on the current change")
  print("   add          Add file to the index")
  print("   add-git      Add files from git repository")
  print("   add-server   Add a server on the list")
  print("   cmd          Add a command on database")
  print("   rm           Remove a file or a server or a command")
  print("")
  print("examine the history and state")
  print("   ls           Show the files tracked")
  print("   ls-servers   Show the server on database")
  print("   ls-cmds      Show the commands stored on database")
  print("")
  print("commands for server")
  print("   rbuild <cmd_name>")
  print("      Send a command for the server, if there is only one server")
  print("")
  print("   rbuild @server_name <cmd_name>")
  print("      Send a command for the server specified")
  print("")
}

func main(argv) {
  if len(argv) < 2 {
    usage()
    return
  }

  handle_args(argv[1:])
}

if __main__ {
  main(args)
}
