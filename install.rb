#!/usr/bin/ruby

require 'uri'
require 'net/http'
require 'tmpdir'

def download(url, filename)
  url = URI.parse(url)
  Net::HTTP.start(url.host) do |http|
    resp = http.get(url.path)
    open(filename, "wb") do |file|
      file.write(resp.body)
    end
  end
end

def read_users(dir)
  users = {}
  dir = File.join(dir, 'users')
  Dir.entries(dir).select{|f| File.file?(File.join(dir, f)) }.each do |u|
    users[u] = File.readlines(File.join(dir, u)).map{|l| l.strip}.select{|l| !l.empty? }
  end
  users
end

def read_groups(dir, users)
  groups = {}
  dir = File.join(dir, 'groups')
  Dir.entries(dir).select{|f| File.file?(File.join(dir, f)) }.each do |g|
    members = File.readlines(File.join(dir, g)).map{|l| l.strip}.select{|l| !l.empty? }
    groups[g] = members.map{ |u| users[u] }.flatten
  end
  groups
end

def system_users
  users = `cat /etc/passwd | grep -v root | grep '/bin/bash'`.split.map do |u|
    u =~ /([^\s]+):.*:.*:.*:.*:([^\s]+):\/bin\/bash$/
    {:name => $1, :home => $2}
  end
  users = users.select{|u| u[:home] && u[:name] }
  users.select{|u| u[:home].index('/srv') == 0 || u[:home].index('/home') == 0 }
end

def write_authorized_keys(user, homedir, keys)
  filename = File.join(homedir, '.ssh', 'authorized_keys')
  open(filename, 'w') do |file|
    keys.each {|k| file.puts(k) }
  end
  FileUtils.chown(user, user, filename)
  FileUtils.chmod(0600, filename)
end

Dir.mktmpdir do |dir|
  keyfile = File.join(dir, 'keys.tar.gz')
  download(ARGV[0], keyfile)
  `tar -zxf #{keyfile} -C #{dir}`
  raise 'fail' if $?.exitstatus != 0

  users = read_users(dir)
  groups = read_groups(dir, users)
  system_users.each do |su|
    if users[su[:name]]
      puts "writing authorized_keys for #{su[:name]}"
      write_authorized_keys(su[:name], su[:home], users[su[:name]])
    elsif groups[su[:name]]
      puts "writing authorized_keys for #{su[:name]}"
      write_authorized_keys(su[:name], su[:home], groups[su[:name]])
    end
  end
end
