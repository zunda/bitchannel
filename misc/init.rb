#!/usr/bin/env ruby
#
# $Id$
#

require 'fileutils'
require 'find'
require 'etc'
require 'optparse'

IFTYPES = {
  'cgi'      => 'cgi',
  'fcgi'     => 'fcgi',
  'fastcgi'  => 'fcgi',
  'rbx'      => 'rbx',
  'mod_ruby' => 'rbx',
  'modruby'  => 'rbx'
}

def main
  vardir = nil
  cgidir = '.'
  srcdir = '.'
  user = nil
  group = nil
  cvscmd = find_command('cvs')
  cvsroot = nil    # ENV['CVSROOT']
  wcname = 'wikidoc'
  params = {
    :iftype     => 'cgi',
    :site_name  => nil,
    :theme      => 'default',
    :logo_url   => nil,
    :html_url_p => false,
    :lang       => 'ja',
    :cgi_url    => nil
  }
  $app_verbose = true

  parser = OptionParser.new(nil, 20, ' ')
  parser.banner = "Usage: ruby #{$0} --lang=LANG --cgiurl=URLPATH --vardir=PATH [options]"
  parser.on('--lang=LANG', 'Content language (ja|en) [REQUIRED]') {|lang|
    params[:lang] = lang
  }
  parser.on('--cgiurl=URLPATH', 'Base URL of CGI [REQUIRED]') {|path|
    params[:cgi_url] = (path + '/').gsub(%r</+>, '/')
  }
  parser.on('--vardir=PATH',
      'Location of working copies and caches [REQUIRED]') {|path|
    vardir = path
  }
  parser.on('--cgidir=PATH',
      "Location where CGI application running (default: #{cgidir})") {|path|
    cgidir = path
  }
  parser.on('--srcdir=PATH',
      "Location of BitChannel working copy (default: #{srcdir})") {|path|
    srcdir = path
  }
  parser.on('--cvsroot=REPO', '$CVSROOT for Wiki contents') {|repo|
    cvsroot = repo
  }
  parser.on('--cvs=PATH',
      "Full path of CVS command (default: #{cvscmd})") {|path|
    cvscmd = path
  }
  parser.on('--user=USER', 'CGI program user') {|spec|
    user = spec
  }
  parser.on('--group=GROUP', 'CGI program group') {|spec|
    group = spec
  }
  parser.on('--iftype=TYPE',
      'Application interface type (cgi|fcgi|rbx)') {|interf|
    params[:iftype] = IFTYPES[interf.downcase]
    unless params[:iftype]
      $stderr.puts "unknown interface type: #{interf}"
      $stderr.puts "choose from followings: #{IFTYPES.keys.join(' ')}"
      exit 1
    end
  }
  parser.on('--htmlurl',
      'Use .../PageName.html for page URL (requires mod_rewrite)') {
    params[:html_url_p] = true
  }
  parser.on('--sitename=NAME', 'Site name') {|name|
    params[:site_name] = name
  }
  parser.on('--logo=URL', 'URL of site logo image') {|url|
    params[:logo_url] = url
  }
  parser.on('--theme=NAME', 'CSS theme') {|theme|
    params[:theme] = theme
  }
  parser.on('-q', '--quiet', 'Does not display verbose messages') {
    $app_verbose = false
  }
  parser.on('--help') {
    puts parser.help
    exit 0
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit 1
  end
  fail "missing --vardir" unless vardir
  fail "missing --cgiurl" unless params[:cgi_url]

  srcdir = File.expand_path(srcdir)
  cgidir = File.expand_path(cgidir)
  vardir = File.expand_path(vardir)
  FileUtils.mkdir_p srcdir, :verbose => $app_verbose
  FileUtils.mkdir_p cgidir, :verbose => $app_verbose
  FileUtils.mkdir_p vardir, :verbose => $app_verbose

  cvsroot_created = false
  unless File.directory?("#{cvsroot}/CVSROOT")
    cvsroot_created = true
    unless cvsroot
      cvsroot = "#{vardir}/repo"
    end
    FileUtils.mkdir_p cvsroot, :verbose => $app_verbose
    cmd "#{cvscmd} -d #{cvsroot} init"
  end
  Dir.chdir "#{srcdir}/pages"
  cmd "#{cvscmd} -Q -d #{cvsroot} import -m 'auto import' #{wcname} bc start"
  cmd "#{cvscmd} -Q -d #{cvsroot} co -d #{vardir}/wc.read #{wcname}"
  cmd "#{cvscmd} -Q -d #{cvsroot} co -d #{vardir}/wc.write #{wcname}"
  FileUtils.mkdir_p "#{vardir}/cache", :verbose => $app_verbose
  if File.expand_path(srcdir) != File.expand_path(cgidir)
    FileUtils.cp "#{srcdir}/index.#{params[:iftype]}", cgidir
    FileUtils.chmod 0755, "#{cgidir}/index.#{params[:iftype]}"
  end

  # requires cgidir initialized
  params[:srcdir] = srcdir
  params[:vardir] = vardir
  params[:cvscmd] = cvscmd
  generate_htaccess cgidir, params
  generate_bitchannelrc cgidir, params

  # requires bitchannelrc
  Dir.chdir cgidir
  msg 'initializing cache...'
  load "#{srcdir}/misc/refresh-linkcache.rb"

  if user or group
    if cvsroot_created
      chown_R user, group, cvsroot
    else
      chown_R user, group, "#{cvsroot}/#{wcname}"
    end
    chown_R user, group, vardir
    chown_R user, group, cgidir
  end

  check_tmp
end

def generate_htaccess(cgidir, params)
  msg "creating #{cgidir}/.htaccess ..."
  File.open("#{cgidir}/.htaccess", 'w') {|f|
    f.write fill_template('htaccess', params)
  }
end

def generate_bitchannelrc(cgidir, params)
  msg "creating #{cgidir}/bitchannelrc ..."
  File.open("#{cgidir}/bitchannelrc", 'w') {|f|
    f.write fill_template('bitchannelrc', params)
  }
end

def fill_template(id, params)
  File.read("#{params[:srcdir]}/misc/template/#{id}.#{params[:lang]}")\
      .gsub(/%%(\w+)%%/) { params[$1.downcase.intern].inspect }\
      .gsub(/^\#%(\w+)%%/) { params[$1.downcase.intern] ? '' : $& }\
      .gsub(/@%(\w+)%%/) { params[$1.downcase.intern] }
end

def check_tmp
  %w( TMP TEMP ).each do |n|
    if ENV[n]
      $stderr.puts(<<MSG)

*** Note from BitChannel initializer ***
You are setting environment variable \$#{n}.
Ensure #{ENV[n]} is writable from CGI user or
set CVS lockdir correctly.
MSG
    end
  end
end

def find_command(cmd)
  ENV['PATH'].split(':')\
      .map {|d| "#{d}/#{cmd}" }\
      .detect {|path| File.executable?(path) }
end

def chown_R(user, group, prefix)
  msg "chown -R #{[user,group].compact.join('.')} #{prefix}"
  uid = user ? get_uid(user) : nil
  gid = group ? get_gid(group) : nil
  Find.find(prefix) do |path|
    File.chown uid, gid, path
  end
end

def get_uid(spec)
  if /\A\d+\z/ =~ spec
  then spec.to_i
  else Etc.getpwnam(spec).uid
  end
end

def get_gid(spec)
  if /\A\d+\z/ =~ spec
  then spec.to_i
  else Etc.getgrnam(spec).gid
  end
end

def cmd(str)
  msg str
  system str
end

def fail(msg)
  $stderr.puts msg
  exit 1
end

def msg(str)
  $stderr.puts str if $app_verbose
end

main
