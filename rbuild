#!/usr/bin/env shpp

DATABASE_NAME = ".rbuild.db"

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
  exit
}

func count_servers(database_name) {
  query = "select count(*) from servers;"

  res = $(sqlite3 ${database_name} <<< query)
  return int(res)
}

func list_track_files(database_name) {
  query = "select file_path from files;"

  res = $(sqlite3 ${database_name} <<< query)

  for f in res {
    print(f)
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

func add_server(database_name, map_args) {
  if !map_args.exists("name") {
    print("name not set")
    exit
  }

  if !map_args.exists("addr") {
    print("addr not set")
    exit
  }

  name = map_args["name"]
  addr = map_args["addr"]
  user = ""
  path_srv = ""
  pem = ""
  args = ""

  if map_args.exists("user") {
    user = map_args["user"]
  }

  if map_args.exists("path-srv") {
    path_srv = map_args["path-srv"]
  }

  if map_args.exists("pem") {
    path_srv = map_args["pem"]
  }

  if map_args.exists("args") {
    path_srv = map_args["args"]
  }

  query = "insert into servers values('" + name + "', '"+
           addr + "','" + user + "','" + path_srv + "','" +
           pem + "','" + args + "', '');"

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

func select_cmd(database_name, cmd_name) {
  query = "select name, line from cmds where name='" + cmd_name + "';"

  res = $(sqlite3 ${database_name} <<< query)

  str_cmd = string(res).split("|")
  return str_cmd[1]
}

func handle_args(argv) {
  switch argv[0] {
    case "init" {
      create_database(DATABASE_NAME)
    }

    case "add-git-files" {
      db_name = search_main_file(DATABASE_NAME)
      files = list_git_files(db_name)
      add_git_files(db_name, files)
    }

    case "ls" {
      db_name = search_main_file(DATABASE_NAME)
      list_track_files(db_name)
    }

    case "add" {
      if len(argv) < 2 {
        print("not file")
        exit
      }

      db_name = search_main_file(DATABASE_NAME)
      add_file(db_name, argv[1])
    }

    case "add-server" {
      if len(argv) < 2 {
        print("no arguments for server options")
        exit
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
        exit
      }

      db_name = search_main_file(DATABASE_NAME)
      add_cmd(db_name, argv[1], argv[2])
    }

    default {
      db_name = search_main_file(DATABASE_NAME)
      print(select_cmd(db_name, argv[0]))
    }
  }
}

func usage() {
  print("usage:")
  print("  rbuild [options]")
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
