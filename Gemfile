source "http://rubygems.org"

gem 'rest-client'
gem 'activeresource'
gem 'json'

if RUBY_PLATFORM =~ /mswin|mingw/
  gem 'win32ole'
elsif RUBY_PLATFORM =~ /darwin/
  gem 'rb-appscript', :require => 'appscript'
else
  raise("Unsupported operating system.")
end