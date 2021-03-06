#
# $Id$
#
# Copyright (c) 2003-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
#

require 'bitchannel/cgi'
require 'fcgi'

module WEBrick
  class CGI
    class << CGI
      remove_method :each_request
    end
    def CGI.each_request(&block)
      ::FCGI.each_cgi_request do |req|
        yield req.env, req.in, req.out
      end
    end
  end
end

module BitChannel
  class FCGI < CGI
  end
end
