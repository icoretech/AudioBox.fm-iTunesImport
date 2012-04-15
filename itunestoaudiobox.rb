#!/usr/bin/env ruby
#--
# Copyright (c) 2011 Claudio Poli
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'rubygems'
require 'bundler/setup'
require 'itunes/library'
require 'rest_client'
require 'json'
require 'open-uri'
require 'optparse'
require 'ostruct'
require 'pp'
require 'digest/md5'

PVERSION = "0.1"
AUDIOBOX_API_URL = 'http://audiobox.fm/api'
$KCODE = "u"
UNWANTED_PLAYLISTS = ["Library", "Music", "Movies", "Podcasts", "Books", "Genius", "iTunes DJ"]

class ParseOptions
  def self.parse(args)
    options = OpenStruct.new
    options.email    = nil
    options.password = nil

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"

      opts.separator " "
      opts.separator "Mandatory options:"

      opts.on("-e", "--email=email", String, "Specifies the AudioBox.fm email.") { |u| options.email = u }
      opts.on("-p", "--password=password", String, "Specifies the AudioBox.fm password.") { |u| options.password = u }

      opts.separator " "
      opts.separator "Specific options:"
      opts.on("-v", "--[no-]verbose", "Run verbosely") { |v| options.verbose = v }

      opts.separator " "

      opts.separator "Common options:"
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on_tail("--version", "Show version") do
        puts PVERSION
        exit
      end
    end # end OptionParser

    opts.parse!(args)
    options
  end # end parse()
end # end class ParseOptions

options = ParseOptions.parse(ARGV)

if options.email.nil? || options.password.nil?
  $stderr.puts "Missing email or password. Please run '#{$0} -h' for help."
  exit 1
else
  puts "[AudioBox] iTunes to AudioBox.fm #{PVERSION} running on Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}), initializing..."
  puts "*"*40

  library = ITunes::Library.load("/Users/Gray/Music/iTunes/iTunes Music Library.xml")

  user = JSON.parse(RestClient::Resource.new("#{AUDIOBOX_API_URL}/user.json", :user => options.email, :password => options.password).get)
  puts "[AudioBox] Maximum Portability is set to #{user['user']['profile']['maximum_portability']}"

  # Get all tracks.
  library_tracks = library.music.tracks.select { |t| t.video? == false }
  # Get remote hashes.
  remote_md5_hashes = RestClient::Resource.new("#{AUDIOBOX_API_URL}/tracks", :user => options.email, :password => options.password).get.split(';')
  puts "[AudioBox] Got hashes list, proceeding."

  added_md5 = []
  library_tracks.each do |t|
    begin
      track_location = CGI::unescape(t.to_hash["Location"].gsub("file://localhost", ""))
      # Check if iTunes track cannot be found on filesystem.
      next unless File.exist?(track_location)
      # Calculate the unique hash for this track.
      track_hash = Digest::MD5.hexdigest(File.read(track_location))
      # Avoid importing duplicates.
      next if remote_md5_hashes.include?(track_hash) || added_md5.include?(track_hash)
      # Start uploads, we will get a token back.
      assigned_track_token = RestClient::Resource.new("#{AUDIOBOX_API_URL}/tracks", options.email, options.password).post(:media => File.new(track_location))
      added_md5 << track_hash
      # Prints out some debug informations.
      puts "[AudioBox] #{assigned_track_token}:#{track_hash} #{t.artist} - #{t.name}"
    rescue Exception => e
      if e.class == Interrupt
        exit
      else
        puts "[AudioBox] Got exception => <#{e.class}>: #{e.message}"
        next
      end
    end
  end

  # Get remote playlists.
  remote_playlists      = JSON.parse(RestClient::Resource.new("#{AUDIOBOX_API_URL}/playlists.json", options.email, options.password).get)
  remote_playlist_names = []
  remote_playlist_hash  = {}
  remote_playlists.each do |remote_playlist|
    remote_playlist_names << remote_playlist['playlist']['name']
    remote_playlist_hash[remote_playlist['playlist']['token']] = remote_playlist['playlist']['name']
  end

  # Get local custom playlists.
  custom_playlists = library.playlists.delete_if {|p| UNWANTED_PLAYLISTS.include?(p.name) }

  # Playlist creation.
  custom_playlist.each do |local_playlist|
    unless remote_playlist_names.include?(local_playlist.name)
      puts "[AudioBox] Creating playlist #{local_playlist.name}."
      RestClient::Resource.new("#{AUDIOBOX_API_URL}/tracks", options.email, options.password).post(:name => local_playlist.name)
    else
      puts "[AudioBox] Skipping playlist #{local_playlist.name} because it already exists."
    end
  end

  custom_playlists.each do |playlist|
    track_tokens_to_add = []
    destination_playlist_token = remote_playlist_hash.reject {|k,v| v != playlist.name }.keys.first
    playlist.tracks.each do |t|
      begin
        track_location = CGI::unescape(t.to_hash["Location"].gsub("file://localhost", ""))
        track_hash       = Digest::MD5.hexdigest(File.read(track_location))
        remote_track_res = RestClient::Resource.new("#{AUDIOBOX_API_URL}/tracks/#{track_hash}.json", options.email, options.password).get
        remote_track     = JSON.parse(remote_track_res)
        track_tokens_to_add << remote_track['track']['token']
      rescue
        next
      end
    end
    add_res = RestClient::Resource.new("#{AUDIOBOX_API_URL}/playlists/#{destination_playlist_token}/add_tracks", options.email, options.password)
    add_res.put(:track_tokens => track_tokens_to_add.uniq)
  end

end
