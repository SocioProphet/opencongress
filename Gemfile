source 'http://rubygems.org'

gem 'rails', '~> 3.0.19'
gem 'rake', '~> 0.9.1'

gem 'thin'

# database gems -- need both pg and mysql for app and wiki
gem 'pg'
gem 'mysql'

gem "settingslogic"

gem 'titlecase'

# HAML support
gem "haml", "~> 3.1.8"
gem "haml-rails"
gem 'sass'
# gem "sass-rails"  #<= after upgrading past rails 3.1

# RABL for API / JSON
gem 'rabl'

# Background tasks
gem 'delayed_job', '~> 2.1'

# RMagick
gem 'rmagick', '2.13.1'
gem "galetahub-simple_captcha", '0.1.3', :require => "simple_captcha"

# Image uploads
gem 'carrierwave'
gem 'fog'

gem "awesome_nested_set", ">= 2.0"

# Open Gov APIs
gem "govkit", :git => "git@github.com:sunlightlabs/govkit.git"
gem "congress"

# jammit support
gem "jammit"
gem "closure-compiler"

# paperclip -- for attaching files to requests
gem 'paperclip'

# Deal with unicode strings
gem 'unicode_utils'

# Geocoding users on create
gem 'geocoder', :git => 'git@github.com:sunlightlabs/geocoder.git'

# notifier for production errors
gem "airbrake"
gem "xray", :require => "xray/thread_dump_signal_handler"

# OpenID
gem 'ruby-openid'
gem 'rack-openid'

# JSONP middleware
gem 'rack-contrib'

# memcache
gem 'memcache-client'

# markup tools and parsers
gem 'simple-rss'
gem 'mediacloth'
gem 'hpricot'
gem 'RedCloth'
gem 'bluecloth'
gem 'htmlentities'
gem 'json'
gem 'nokogiri'
gem 'possessive'

# spam protection
gem "defensio", :git => 'git://github.com/drinks/defensio-ruby.git'  # this forces :json api format
gem "defender"

# oauth
gem 'oauth'
gem 'facebooker2'

gem 'will_paginate', '~> 3.0.pre2'

gem "validates_captcha"
gem "okkez-open_id_authentication"

gem 'acts-as-taggable-on', '~> 2.3.3'

gem 'simple_form'

gem 'mechanize'
gem 'formageddon', :git => 'git://github.com/opencongress/formageddon.git'

group :deployment do
  gem 'capistrano'
  gem 'capistrano-ext'
end

group :production do
  # new relic RPM
  gem 'newrelic_rpm'
end

group :test, :development do
  gem 'pry'
  gem 'pry-nav'
  gem 'pry-rescue'
  gem 'pry-stack_explorer'
  gem 'rails_best_practices'
  gem 'simplecov',            :require => false
  gem 'rspec-rails',          '~> 2.4'
  gem 'guard'
  gem 'guard-livereload'
  gem 'awesome_print'
end

group :test do
  gem 'autotest'
  gem 'silent-postgres'  # Quieter postgres log messages
  gem 'database_cleaner'
  gem 'vcr'
  gem 'awesome_print'
  gem 'fuubar'
  gem 'poltergeist'  # Requires PhantomJS >= 1.8.1
  gem 'cucumber'
  gem 'cucumber-rails',       :require => false
  gem 'fuubar-cucumber',      :git => 'git://github.com/martinciu/fuubar-cucumber.git'
  gem 'webmock',              '~> 1.9.0'
  gem 'selenium-client'
  gem 'capybara'
  gem 'launchy'
  gem 'spork'
end

