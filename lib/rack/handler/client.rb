# frozen_string_literal: true

require 'socket'
require 'rack/content_length'
require 'rack/rewindable_input'
require 'http/parser'

module Rack
  module Handler
    class Client
      def self.run(app, options = {})
	host = options[:host] || "localhost"
	port = options[:port] || 8080
	sock = TCPSocket.open(host, port)
        serve sock, app
      end

      def self.serve(sock, app)
        env = ENV.to_hash
        env.delete "HTTP_CONTENT_LENGTH"

        env[SCRIPT_NAME] = ""  if env[SCRIPT_NAME] == "/"
	parser = Http::Parser.new
	input = Rack::RewindableInput.new(sock)
	while true do
	  line = input.gets
	  break if line.nil?
	  parser.parse line
	  break if line.chomp.size == 0
	end
        env.update(
          RACK_VERSION      => Rack::VERSION,
          RACK_INPUT        => input,
          RACK_ERRORS       => STDERR,
          RACK_MULTITHREAD  => false,
          RACK_MULTIPROCESS => true,
          RACK_RUNONCE      => false,
          RACK_URL_SCHEME   => ["yes", "on", "1"].include?(ENV[HTTPS]) ? "https" : "http"
        )
	env[REQUEST_METHOD] = parser.http_method
        env[QUERY_STRING] ||= parser.query
        env[HTTP_VERSION] ||= env[SERVER_PROTOCOL]
        env[REQUEST_PATH] ||= parser.path

        status, headers, body = app.call(env)
        begin
          send_headers sock, status, headers
          send_body sock, body
        ensure
          body.close  if body.respond_to? :close
        end
      end

      def self.send_headers(sock, status, headers)
        sock.print "Status: #{status}\r\n"
        headers.each { |k, vs|
          vs.split("\n").each { |v|
            sock.print "#{k}: #{v}\r\n"
	    sock.flush
          }
        }
        sock.print "\r\n"
        sock.flush
      end

      def self.send_body(sock,body)
        body.each { |part|
          sock.print part
	  sock.flush
        }
      end
    end
  end
end
